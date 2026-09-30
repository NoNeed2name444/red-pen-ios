import Foundation

// MARK: - Crash and failure reports: the front door
//
// Anywhere in the app that catches a failure worth fixing:
//
//     Diagnostics.record(.error, area: .sync, message: "sync.failed", error: error)
//
// and a screen or action worth knowing about when something later goes wrong:
//
//     Diagnostics.breadcrumb("screen:library")
//
// Both take StaticString on purpose: only text written in the app's source can
// be passed, so nothing a student typed, imported or recorded can ever be a
// message or a breadcrumb. `error` is reduced to its domain, number and case
// name (DiagScrub.error) - its description is never read.
//
// Cheap and safe from any thread; does nothing when the student has turned
// reports off (Settings > AI models > Crash and failure reports). Crashes and
// hangs come from MetricKit, and unclean exits from the running marker - both
// in DiagnosticsPlatform.swift, which also sends the queue.
enum Diagnostics {
    static let enabledKey = "vignette.diagnostics.enabled"

    /// On unless the student turned it off (the privacy text says so).
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static let center: DiagnosticsCenter = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return DiagnosticsCenter(folder: base.appendingPathComponent("diagnostics", isDirectory: true),
                                 enabled: { Diagnostics.isEnabled })
    }()

    static func record(_ kind: DiagKind, area: DiagArea, message: StaticString,
                       error: Error? = nil, code: Int? = nil) {
        center.record(kind, area: area, message: "\(message)", error: error, code: code)
    }

    static func breadcrumb(_ name: StaticString) {
        center.breadcrumb("\(name)")
    }
}

/// Holds the queue, the breadcrumbs and the running marker, and writes them to
/// disk off the caller's thread. One lock: every call is short.
final class DiagnosticsCenter: @unchecked Sendable {
    let folder: URL
    private let lock = NSLock()
    private let io = DispatchQueue(label: "diagnostics.io", qos: .utility)
    private var outbox: DiagOutbox
    private var crumbs = DiagBreadcrumbs()
    private var marker: DiagRunMarker?
    private var markerWriteQueued = false
    private let enabled: () -> Bool

    /// The device as it is now; set by the platform side at launch.
    var device: () -> DiagDevice = { DiagDevice.unknown }
    var clock: () -> Int = { Int(Date().timeIntervalSince1970) }

    private var outboxURL: URL { folder.appendingPathComponent("outbox.json") }
    private var markerURL: URL { folder.appendingPathComponent("running.json") }

    init(folder: URL, enabled: @escaping () -> Bool) {
        self.folder = folder
        self.enabled = enabled
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("outbox.json")
        if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode(DiagOutbox.self, from: data) {
            outbox = stored
        } else {
            outbox = DiagOutbox()
        }
    }

    // MARK: recording

    /// A failure the app caught. Cancellation and plain "no connection" are
    /// not failures of the app, and are not recorded.
    func record(_ kind: DiagKind, area: DiagArea, message: String, error: Error? = nil, code: Int? = nil) {
        guard enabled() else { return }
        if let error, Self.isNoise(error) { return }
        let now: Int = clock()
        var event = DiagEvent(kind: kind, area: area, message: message, at: now)
        event.code = code
        event.error = error.map(DiagScrub.error)
        breadcrumb("fail:\(area.rawValue)")
        add(event)
    }

    /// A finished report (MetricKit's, or an unclean exit): checked,
    /// fingerprinted, given the trail and the device, and queued.
    func add(_ raw: DiagEvent) {
        guard enabled() else { return }
        let dev: DiagDevice = device()
        var event = DiagScrub.checked(raw)
        lock.lock()
        if event.breadcrumbs.isEmpty && !event.kind.isFatal { event.breadcrumbs = crumbs.before(event.at) }
        lock.unlock()
        if event.device == nil { event.device = dev }
        event.fingerprint = DiagFingerprint.of(event, binary: dev.binary)
        lock.lock()
        outbox.add(event)
        outbox.prune(now: clock())
        lock.unlock()
        saveOutbox()
    }

    func breadcrumb(_ name: String) {
        guard enabled() else { return }
        let now: Int = clock()
        lock.lock()
        crumbs.add(name, at: now)
        marker?.crumbs = crumbs.items
        lock.unlock()
        saveMarkerSoon()
    }

    static func isNoise(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        // cancelled, not connected, connection lost, international roaming off
        return ns.domain == NSURLErrorDomain && [-999, -1009, -1005, -1018].contains(ns.code)
    }

    // MARK: the running marker

    /// At launch: what the last run left says whether it ended cleanly. The
    /// new run's marker is written now - already active for a launch into
    /// the foreground, so a launch the watchdog kills is caught too, and not
    /// for a launch in the background (a background refresh), which iOS may
    /// end at any time without anything being wrong.
    func launched(build: String, foreground: Bool = false) {
        let previous: DiagRunMarker? = (try? Data(contentsOf: markerURL))
            .flatMap { try? JSONDecoder().decode(DiagRunMarker.self, from: $0) }
        if let unclean = DiagRunMarker.uncleanExit(previous, binary: device().binary) {
            add(unclean)
        }
        lock.lock()
        marker = DiagRunMarker(build: build, startedAt: clock(), activeSince: foreground ? clock() : nil,
                               crumbs: crumbs.items)
        lock.unlock()
        saveMarkerNow()
    }

    func becameActive() {
        breadcrumb("app:active")
        lock.lock()
        marker?.activeSince = clock()
        lock.unlock()
        saveMarkerNow()
    }

    func wentBackground() {
        breadcrumb("app:background")
        lock.lock()
        marker?.activeSince = nil
        lock.unlock()
        saveMarkerNow()
    }

    // MARK: sending

    func batch() -> [DiagEvent] {
        lock.lock(); defer { lock.unlock() }
        return outbox.batch(today: DiagOutbox.dayString(clock()))
    }

    func pingDue(build: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return outbox.pingDue(today: DiagOutbox.dayString(clock()), build: build)
    }

    func sent(_ ids: [String], build: String) {
        lock.lock()
        let today: String = DiagOutbox.dayString(clock())
        outbox.sent(ids, today: today)
        outbox.pinged(today: today, build: build)
        lock.unlock()
        saveOutbox()
    }

    func drop(_ ids: [String]) {
        lock.lock()
        outbox.drop(ids)
        lock.unlock()
        saveOutbox()
    }

    /// Everything waiting and lately sent, for the developer view.
    func snapshot() -> (queued: [DiagEvent], recent: [DiagEvent], sentToday: Int) {
        lock.lock(); defer { lock.unlock() }
        let today: String = DiagOutbox.dayString(clock())
        return (outbox.events, outbox.recent, outbox.day == today ? outbox.sentToday : 0)
    }

    /// Turned off: nothing waiting is sent later.
    func clear() {
        lock.lock()
        outbox.events = []
        outbox.recent = []
        lock.unlock()
        saveOutbox()
    }

    // MARK: disk

    private func saveOutbox() {
        lock.lock()
        let snapshot = outbox
        lock.unlock()
        let url = outboxURL
        io.async {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }

    private func saveMarkerNow() {
        lock.lock()
        let snapshot = marker
        lock.unlock()
        let url = markerURL
        io.async {
            if let snapshot, let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }

    /// Breadcrumbs come in bursts; the marker is written at most once a second.
    private func saveMarkerSoon() {
        lock.lock()
        let queued = markerWriteQueued
        markerWriteQueued = true
        lock.unlock()
        guard !queued else { return }
        io.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.markerWriteQueued = false
            self.lock.unlock()
            self.saveMarkerNow()
        }
    }

    /// Waits for pending writes (the tests, and before a deliberate crash).
    func flushToDisk() {
        saveMarkerNow()
        saveOutbox()
        io.sync {}
    }
}
