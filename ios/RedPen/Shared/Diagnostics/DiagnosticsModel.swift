import Foundation

// MARK: - Crash and failure reports: what one report is
//
// The app's "debugger": when something crashes, hangs or fails, a short
// technical report goes to the worker (server/diagnostics.js), which groups
// the same problem into one row, and a GitHub workflow turns each group into
// an issue to fix (server/triage/diagnostics-triage.mjs).
//
// What a report can hold is decided by its TYPES, not by care at each call:
//   - a failure's message is a key from the app's own source ("sync.failed"),
//     passed as a StaticString, so no text anybody typed can be one
//   - an error is reduced to its domain, number and case name - never its
//     description, which is where a server's or a file's words would be
//   - breadcrumbs are names of screens and actions, never their content
//   - a crash is exception codes and call-stack addresses
// Every field is checked again against the same patterns before it is kept
// here, and once more on the server.
//
// Foundation only, so the whole of it is tested on Linux
// (Tests/DiagnosticsTests.swift).

enum DiagKind: String, Codable, CaseIterable {
    /// MetricKit, delivered on the launch after it happened
    case crash, hang, cpu, disk
    /// the app was in use and then was not, with no crash report (killed for
    /// memory, by the watchdog, or a crash MetricKit has not delivered)
    case unclean
    /// caught by the app itself
    case error, warning

    var isFatal: Bool {
        switch self {
        case .error, .warning: return false
        default: return true
        }
    }
}

/// Which part of the app a report is about.
enum DiagArea: String, Codable, CaseIterable {
    case app, ai
    case cloudJobs = "cloud_jobs"
    case transcribe, voice, audio, sync
    case importing = "import"
    case export, graph3d, metal, download, account
    case metricKit = "metrickit"
}

/// One frame of a call stack: the binary, its UUID (to find its dSYM) and the
/// offset into its text segment.
struct DiagFrame: Codable, Equatable {
    var b: String
    var u: String?
    var o: UInt64
}

struct DiagException: Codable, Equatable {
    var type: Int?
    var code: Int?
    var signal: Int?
    var name: String?
    var className: String?
    var termination: String?
}

/// An error, as much of it as is safe to send.
struct DiagError: Codable, Equatable {
    var domain: String
    var code: Int
    var name: String?
}

/// A screen or action. `t` is absolute seconds while it is kept on the
/// device, and seconds before the problem once it is in a report.
struct DiagCrumb: Codable, Equatable {
    var t: Int
    var s: String
}

/// The device a report came from - nothing that tells one person's phone
/// from another's of the same model.
struct DiagDevice: Codable, Equatable {
    var model: String
    var os: String
    var idiom: String
    var app: String
    var build: String
    var flavour: String
    var binary: String
    var memoryGB: Int
    var freeDiskGB: Int
    var thermal: String
    var lowPower: Bool
    var graphics: String

    static let unknown = DiagDevice(model: "unknown", os: "0", idiom: "other", app: "0", build: "0",
                                    flavour: "dev", binary: "RedPen", memoryGB: 0, freeDiskGB: 0,
                                    thermal: "nominal", lowPower: false, graphics: "automatic")

    /// "1.2 (45)", the way the server names a build.
    var buildName: String { "\(app) (\(build))" }

    static func thermalName(_ raw: Int) -> String {
        switch raw {
        case 1: return "fair"
        case 2: return "serious"
        case 3: return "critical"
        default: return "nominal"
        }
    }
}

struct DiagEvent: Codable, Equatable, Identifiable {
    /// Random, on this device only: which queued report the server took.
    var id: String = UUID().uuidString
    var kind: DiagKind
    var area: DiagArea
    var message: String
    var code: Int?
    var error: DiagError?
    var exception: DiagException?
    var frames: [DiagFrame] = []
    var durationMs: Int?
    var at: Int
    var count: Int = 1
    var breadcrumbs: [DiagCrumb] = []
    var device: DiagDevice?
    var fingerprint: String = ""
}

// MARK: - Checking every field

enum DiagScrub {
    private static func whole(_ text: String, _ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "^(?:" + pattern + ")$") else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func replace(_ text: String, _ pattern: String, _ with: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: with)
    }

    /// A failure's message: a key like "sync.failed", or nothing.
    static func messageKey(_ text: String) -> String? {
        whole(text, "[a-z][a-z0-9_.]{0,63}") ? text : nil
    }

    /// A name out of code (an exception, a class, an error domain).
    static func identifier(_ text: String?, max: Int = 80) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        return whole(text, "[A-Za-z_][A-Za-z0-9_.]{0,\(max - 1)}") ? text : nil
    }

    /// A breadcrumb: a screen or action name.
    static func crumb(_ text: String) -> String? {
        whole(text, "[A-Za-z0-9_.:/-]{1,48}") ? text : nil
    }

    /// Only the namespace and code of a termination reason.
    static func termination(_ text: String?) -> String? {
        guard let text,
              let regex = try? NSRegularExpression(pattern: "Namespace ([A-Z_]{1,32}),\\s*Code (0x[0-9A-Fa-f]{1,16}|[0-9]{1,12})"),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let space = Range(match.range(at: 1), in: text),
              let code = Range(match.range(at: 2), in: text) else { return nil }
        return "Namespace \(text[space]), Code \(text[code])"
    }

    /// Free text with anything that could identify somebody taken out, for
    /// the rare place free text is shown (the copied report). Nothing that
    /// goes to the server needs it: no field there is free text.
    static func clean(_ text: String?, max: Int = 160) -> String? {
        guard var s = text else { return nil }
        s = replace(s, "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", "<email>")
        s = replace(s, "[A-Za-z][A-Za-z0-9+.-]*://\\S+", "<url>")
        s = replace(s, "~?(?:/[^\\s/]+){2,}/?", "<path>")
        s = replace(s, "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", "<id>")
        s = replace(s, "\\b(?:0x)?[0-9A-Fa-f]{12,}\\b", "<id>")
        s = replace(s, "[A-Za-z0-9_\\-]{24,}", "<id>")
        s = replace(s, "[0-9]{4,}", "#")
        s = replace(s, "\\s+", " ").trimmingCharacters(in: .whitespaces)
        if s.count > max { s = String(s.prefix(max)) }
        return s.isEmpty ? nil : s
    }

    /// An error reduced to its domain, number and case name. Its description
    /// is never read: that is where a server's reply or a file's contents
    /// would be.
    static func error(_ error: Error) -> DiagError {
        let ns = error as NSError
        var name: String?
        let mirror = Mirror(reflecting: error)
        if mirror.displayStyle == .enum {
            if let label = mirror.children.first?.label {
                // a case with a payload: its name, never the payload
                name = label
            } else {
                // a case without one prints as its name (or as a description
                // written in the source, which the identifier check refuses
                // unless it is a single word)
                name = String(describing: error)
            }
        }
        return DiagError(domain: identifier(ns.domain) ?? "unknown", code: ns.code,
                         name: identifier(name, max: 60))
    }

    /// A report with every field checked against its pattern: what does not
    /// match is dropped or replaced, never passed on.
    static func checked(_ event: DiagEvent) -> DiagEvent {
        var e = event
        e.message = messageKey(event.message) ?? "unknown"
        if let x = event.exception {
            e.exception = DiagException(type: x.type, code: x.code, signal: x.signal,
                                        name: identifier(x.name), className: identifier(x.className),
                                        termination: termination(x.termination))
        }
        if let err = event.error {
            e.error = DiagError(domain: identifier(err.domain) ?? "unknown", code: err.code,
                                name: identifier(err.name, max: 60))
        }
        e.breadcrumbs = event.breadcrumbs.compactMap { c in crumb(c.s).map { DiagCrumb(t: c.t, s: $0) } }
        e.frames = Array(event.frames.prefix(32)).filter { whole($0.b, "[A-Za-z0-9_.+ -]{1,64}") }
            .map { f in DiagFrame(b: f.b, u: f.u.flatMap { whole($0, "[0-9A-Fa-f-]{32,36}") ? $0 : nil }, o: f.o) }
        e.count = min(max(event.count, 1), 1000)
        return e
    }
}

// MARK: - Which reports are the same problem (the same as server/diagnostics.js)

enum DiagFingerprint {
    /// FNV-1a, 64 bits, over UTF-8, as 16 hex characters.
    static func fnv1a64(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// The top five frames in the app's own binary, or of any binary.
    static func keyFrames(_ frames: [DiagFrame], binary: String) -> [DiagFrame] {
        let own = frames.filter { $0.b == binary }
        return Array((own.isEmpty ? frames : own).prefix(5))
    }

    static func canonical(_ event: DiagEvent, binary: String) -> String {
        switch event.kind {
        case .crash, .hang, .cpu, .disk:
            let x = event.exception
            let typeText: String = String(x?.type ?? -1)
            let signalText: String = String(x?.signal ?? -1)
            let what: String = x?.name ?? x?.className ?? "t\(typeText):s\(signalText)"
            let frames: String = keyFrames(event.frames, binary: binary)
                .map { "\($0.b)+\(String($0.o, radix: 16))" }.joined(separator: ",")
            let middle: String = event.kind == .hang ? "" : what
            return "\(event.kind.rawValue)|\(middle)|\(frames)"
        case .unclean:
            return "unclean|\(event.area.rawValue)|\(event.breadcrumbs.last?.s ?? "")"
        case .error, .warning:
            let parts: [String] = [
                event.kind.rawValue, event.area.rawValue, event.message,
                event.error?.domain ?? "", event.error.map { String($0.code) } ?? "",
                event.error?.name ?? "", event.code.map { String($0) } ?? "",
            ]
            return parts.joined(separator: "|")
        }
    }

    static func of(_ event: DiagEvent, binary: String) -> String {
        fnv1a64(canonical(event, binary: binary))
    }

    /// A one-line name, for the developer view and the copied report.
    static func title(_ event: DiagEvent, binary: String) -> String {
        let top = keyFrames(event.frames, binary: binary).first
        let at: String = top.map { " at \($0.b)+0x\(String($0.o, radix: 16))" } ?? ""
        switch event.kind {
        case .crash:
            let x = event.exception
            let what: String = x?.name ?? x?.className ?? signalName(x?.signal) ?? "exception \(x?.type ?? -1)"
            return "Crash: \(what)\(at)"
        case .hang:
            let seconds: String = event.durationMs.map { String(format: " of %.1fs", Double($0) / 1000) } ?? ""
            return "Hang\(seconds)\(at)"
        case .cpu: return "CPU exception\(at)"
        case .disk: return "Disk-write exception\(at)"
        case .unclean:
            let after: String = event.breadcrumbs.last.map { " after \($0.s)" } ?? ""
            return "Unclean exit (killed or crashed)\(after)"
        case .error, .warning:
            let word: String = event.kind == .warning ? "Warning" : "Failure"
            let code: String = event.code.map { " [\($0)]" } ?? ""
            let why: String = event.error.map { e in " (\(e.domain) \(e.code)\(e.name.map { " " + $0 } ?? ""))" } ?? ""
            return "\(word) in \(event.area.rawValue): \(event.message)\(code)\(why)"
        }
    }

    static func signalName(_ signal: Int?) -> String? {
        switch signal {
        case 4: return "SIGILL"
        case 5: return "SIGTRAP"
        case 6: return "SIGABRT"
        case 8: return "SIGFPE"
        case 9: return "SIGKILL"
        case 10: return "SIGBUS"
        case 11: return "SIGSEGV"
        default: return nil
        }
    }
}
