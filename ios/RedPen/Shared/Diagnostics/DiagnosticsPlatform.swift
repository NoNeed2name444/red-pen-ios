import Foundation
import SwiftUI
import UIKit
#if canImport(MetricKit)
import MetricKit
#endif

// MARK: - Crash and failure reports: the device side
//
// Started from RedPenApp: reads what the last run left (the running marker),
// listens to MetricKit, keeps the marker in step with the app going to and
// from the background, and sends what is waiting over the app's own signed-in
// API (AuthAPI.send -> POST /diagnostics), at most every half hour and within
// the queue's daily allowance (DiagOutbox).
//
// MetricKit delivers crash, hang, CPU and disk-write reports on the launch
// after they happen, and only when the person has "Share With App Developers"
// on (Settings > Privacy & Security > Analytics & Improvements). Whether it
// delivers at all to an app installed by Swift Playgrounds is unverified; the
// running marker and the app's own failure reports work in every build either
// way.

/// What goes over the wire.
struct DiagUpload: Encodable {
    var device: DiagDevice
    var events: [DiagEvent]
}

@MainActor
enum DiagnosticsRuntime {
    private static var started = false
    private static var lastSend: Date?
    private static var sending = false
    private static var scheduled: Task<Void, Never>?
    /// What the last send said, for the developer view.
    static private(set) var lastStatus: String = ""

    /// At launch (not in a screenshot or preview run).
    static func start() {
        guard !started else { return }
        started = true
        DiagnosticsDevice.prepare()
        Diagnostics.center.device = { DiagnosticsDevice.now() }
        Diagnostics.center.launched(build: DiagnosticsDevice.now().buildName,
                                    foreground: UIApplication.shared.applicationState != .background)
        #if canImport(MetricKit)
        MetricKitBridge.shared.start()
        #endif
    }

    /// Keeps the running marker in step, and sends a little after the app
    /// comes to the front (MetricKit's report of a crash arrives in the first
    /// seconds, and should replace the guessed "unclean exit" before either
    /// is sent).
    static func phaseChanged(_ phase: ScenePhase, token: @escaping @MainActor () -> String?) {
        guard started else { return }
        switch phase {
        case .active:
            Diagnostics.center.becameActive()
            scheduled?.cancel()
            scheduled = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { return }
                _ = await sendIfDue(token: token())
            }
        case .background:
            Diagnostics.center.wentBackground()
        default:
            break
        }
    }

    @discardableResult
    static func sendIfDue(token: String?, force: Bool = false) async -> String {
        guard Diagnostics.isEnabled else { return note("Reports are turned off.") }
        guard let token, !token.isEmpty, token != Session.localToken else {
            return note("This device has no server account, so reports wait here.")
        }
        if !force, let lastSend, Date().timeIntervalSince(lastSend) < 30 * 60 { return lastStatus }
        guard !sending else { return "Already sending." }
        sending = true
        defer { sending = false }
        lastSend = Date()
        let center = Diagnostics.center
        let device: DiagDevice = center.device()
        let batch: [DiagEvent] = center.batch()
        guard !batch.isEmpty || center.pingDue(build: device.buildName) else { return note("Nothing to send.") }
        do {
            try await AuthAPI.send("/diagnostics", body: DiagUpload(device: device, events: batch),
                                   token: token, timeout: 15)
            center.sent(batch.map(\.id), build: device.buildName)
            let count: Int = batch.count
            return note(count == 0 ? "Up to date." : "Sent \(count) report\(count == 1 ? "" : "s").")
        } catch AuthAPI.Failure.tooManyTries {
            return note("Today's reports are used up; the rest go tomorrow.")
        } catch AuthAPI.Failure.notConfigured {
            return note("The server does not take reports yet; they wait here.")
        } catch AuthAPI.Failure.signedOut {
            return note("Signed out; reports wait until you sign in again.")
        } catch AuthAPI.Failure.offline {
            return note("No connection; reports wait here.")
        } catch {
            // kept: the queue drops anything over two weeks old by itself
            return note("Not sent this time; tried again later.")
        }
    }

    private static func note(_ status: String) -> String {
        lastStatus = status
        return status
    }

    // MARK: testing the pipeline (personal build only, from the developer view)

    static func simulateFailure() {
        Diagnostics.record(.error, area: .app, message: "debug.simulated_failure",
                           error: NSError(domain: "RedPen.Diagnostics", code: 42))
    }

    /// Blocks the main thread long enough for MetricKit to call it a hang.
    static func simulateHang() {
        Diagnostics.breadcrumb("debug:simulate_hang")
        Thread.sleep(forTimeInterval: 4)
    }

    /// A real crash: the running marker reports it at the next launch, and
    /// MetricKit (where it delivers) with its call stack.
    static func simulateCrash() -> Never {
        Diagnostics.breadcrumb("debug:simulate_crash")
        Diagnostics.center.flushToDisk()
        fatalError("Diagnostics: a crash asked for from the developer view")
    }
}

// MARK: - The device, as a report describes it

enum DiagnosticsDevice {
    private static var base: DiagDevice = .unknown
    private static let lock = NSLock()
    private static var disk: (at: Date, gb: Int) = (.distantPast, 0)

    /// The parts that need the main thread, read once.
    @MainActor
    static func prepare() {
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osText: String = os.patchVersion > 0
            ? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)" : "\(os.majorVersion).\(os.minorVersion)"
        let idiom: String
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: idiom = "phone"
        case .pad: idiom = "pad"
        default: idiom = "other"
        }
        let memory: Int = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        let device = DiagDevice(
            model: modelIdentifier(), os: osText, idiom: idiom,
            app: safe(info?["CFBundleShortVersionString"] as? String ?? "1.0"),
            build: safe(info?["CFBundleVersion"] as? String ?? "1"),
            flavour: flavour, binary: Bundle.main.executableURL?.lastPathComponent ?? "RedPen",
            memoryGB: memory, freeDiskGB: 0, thermal: "nominal", lowPower: false, graphics: "automatic")
        lock.lock()
        base = device
        lock.unlock()
    }

    /// Now, from any thread: the base plus what changes (heat, Low Power
    /// Mode, free space, the Graphics setting).
    static func now() -> DiagDevice {
        lock.lock()
        var device = base
        let cached = disk
        lock.unlock()
        let process = ProcessInfo.processInfo
        device.thermal = DiagDevice.thermalName(process.thermalState.rawValue)
        device.lowPower = process.isLowPowerModeEnabled
        // the owner's Graphics setting (SpaceQuality.swift, GraphQuality.key)
        let graphics: String = UserDefaults.standard.string(forKey: "vignette.space.graphics") ?? "automatic"
        device.graphics = ["automatic", "high", "smooth"].contains(graphics) ? graphics : "automatic"
        if Date().timeIntervalSince(cached.at) < 300 {
            device.freeDiskGB = cached.gb
        } else {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let bytes: Int64 = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage ?? 0
            let gb: Int = Int(bytes / 1_073_741_824)
            lock.lock()
            disk = (Date(), gb)
            lock.unlock()
            device.freeDiskGB = gb
        }
        return device
    }

    /// Which kind of build this is, so the owner can tell a Playgrounds
    /// build (no dSYMs, so no symbols) from an Xcode one.
    static var flavour: String {
        if PersonalBuild.isOn { return "personal" }
        #if SWIFT_PACKAGE
        return "playgrounds"
        #elseif DEBUG
        return "dev"
        #else
        return "store"
        #endif
    }

    /// "iPhone17,3" - the model, never the name somebody gave their phone.
    private static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        let machine: String = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine.isEmpty ? "unknown" : machine
    }

    private static func safe(_ text: String) -> String {
        let kept = text.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
        return kept.isEmpty ? "0" : String(kept.prefix(16))
    }
}

// MARK: - MetricKit

#if canImport(MetricKit)
/// Crash, hang, CPU and disk-write reports, turned into DiagEvents. A payload
/// seen once is not added again (pastDiagnosticPayloads repeats them).
final class MetricKitBridge: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitBridge()
    private let seenKey = "vignette.diagnostics.metrickitSeen"

    func start() {
        MXMetricManager.shared.add(self)
        take(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        take(payloads)
    }

    private func take(_ payloads: [MXDiagnosticPayload]) {
        let seen: Double = UserDefaults.standard.double(forKey: seenKey)
        var newest: Double = seen
        for payload in payloads {
            let end: Double = payload.timeStampEnd.timeIntervalSince1970
            guard end > seen else { continue }
            newest = max(newest, end)
            let at = Int(end)
            for d in payload.crashDiagnostics ?? [] { Diagnostics.center.add(crash(d, at: at)) }
            for d in payload.hangDiagnostics ?? [] {
                var e = DiagEvent(kind: .hang, area: .metricKit, message: "metrickit.hang", at: at)
                e.durationMs = Int(d.hangDuration.converted(to: .milliseconds).value)
                e.frames = DiagCallStack.frames(fromJSON: d.callStackTree.jsonRepresentation())
                Diagnostics.center.add(e)
            }
            for d in payload.cpuExceptionDiagnostics ?? [] {
                var e = DiagEvent(kind: .cpu, area: .metricKit, message: "metrickit.cpu_exception", at: at)
                e.frames = DiagCallStack.frames(fromJSON: d.callStackTree.jsonRepresentation())
                Diagnostics.center.add(e)
            }
            for d in payload.diskWriteExceptionDiagnostics ?? [] {
                var e = DiagEvent(kind: .disk, area: .metricKit, message: "metrickit.disk_write_exception", at: at)
                e.frames = DiagCallStack.frames(fromJSON: d.callStackTree.jsonRepresentation())
                Diagnostics.center.add(e)
            }
        }
        if newest > seen { UserDefaults.standard.set(newest, forKey: seenKey) }
    }

    private func crash(_ d: MXCrashDiagnostic, at: Int) -> DiagEvent {
        var e = DiagEvent(kind: .crash, area: .metricKit, message: "metrickit.crash", at: at)
        var x = DiagException(type: d.exceptionType?.intValue, code: d.exceptionCode?.intValue,
                              signal: d.signal?.intValue, name: nil, className: nil,
                              termination: d.terminationReason)
        // the exception's name and class, never its composed message (which
        // can hold whatever string the code was working on)
        if let reason = d.exceptionReason {
            x.name = reason.exceptionName
            x.className = reason.className
        }
        e.exception = x
        e.frames = DiagCallStack.frames(fromJSON: d.callStackTree.jsonRepresentation())
        return e
    }
}
#endif

// MARK: - Breadcrumbs for screens

extension View {
    /// A breadcrumb when this screen appears: its name, never its content.
    func diagnosticsScreen(_ name: StaticString) -> some View {
        onAppear { Diagnostics.breadcrumb(name) }
    }
}
