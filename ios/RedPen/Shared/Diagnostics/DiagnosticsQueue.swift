import Foundation

// MARK: - Crash and failure reports: what is kept on the device until it is sent
//
// The breadcrumbs (the last screens and actions), the reports waiting to go,
// the "running" marker that tells a crash or a kill from a clean exit, and the
// reading of MetricKit's call stacks. Foundation only, tested on Linux
// (Tests/DiagnosticsTests.swift); DiagnosticsCenter holds them and writes them
// to disk, DiagnosticsPlatform.swift feeds and sends them.

/// The last 50 screens and actions: names only.
struct DiagBreadcrumbs: Codable, Equatable {
    static let capacity = 50
    private(set) var items: [DiagCrumb] = []

    mutating func add(_ name: String, at time: Int) {
        guard let name = DiagScrub.crumb(name) else { return }
        // the same thing twice in a row, in the same second, is one step
        if let last = items.last, last.s == name, last.t == time { return }
        items.append(DiagCrumb(t: time, s: name))
        if items.count > Self.capacity { items.removeFirst(items.count - Self.capacity) }
    }

    /// As a report carries them: seconds before `time`, oldest first.
    func before(_ time: Int) -> [DiagCrumb] {
        items.filter { $0.t <= time }.map { DiagCrumb(t: max(0, time - $0.t), s: $0.s) }
    }
}

/// The reports waiting to be sent, and how many went today.
struct DiagOutbox: Codable, Equatable {
    static let maxQueued = 60
    /// per request: the server takes at most 12, and its free plan's query
    /// limit is why
    static let maxPerUpload = 10
    static let maxPerDay = 40
    static let maxAgeDays = 14
    static let recentKept = 30

    var events: [DiagEvent] = []
    /// sent lately, for the developer view
    var recent: [DiagEvent] = []
    var day: String = ""
    var sentToday: Int = 0
    var pingedDay: String = ""
    var pingedBuild: String = ""

    /// Queues a report. The same problem again, not yet sent, adds to the
    /// count of the one waiting instead of queuing another; a crash report
    /// replaces the "unclean exit" guessed for the same moment.
    mutating func add(_ incoming: DiagEvent) {
        var event = incoming
        if event.kind == .crash {
            let guessed = events.filter { $0.kind == .unclean && abs($0.at - event.at) <= 3600 }
            // the trail the marker kept is the crash's own
            if event.breadcrumbs.isEmpty, let trail = guessed.last?.breadcrumbs { event.breadcrumbs = trail }
            events.removeAll { $0.kind == .unclean && abs($0.at - event.at) <= 3600 }
        }
        if let i = events.firstIndex(where: { $0.fingerprint == event.fingerprint }) {
            events[i].count = min(events[i].count + event.count, 1000)
            if event.at >= events[i].at {
                events[i].at = event.at
                events[i].breadcrumbs = event.breadcrumbs
                events[i].device = event.device ?? events[i].device
            }
            return
        }
        events.append(event)
        while events.count > Self.maxQueued {
            // the oldest failure goes first; crashes are kept longest
            if let i = events.firstIndex(where: { !$0.kind.isFatal }) {
                events.remove(at: i)
            } else {
                events.removeFirst()
            }
        }
    }

    /// What to send now: crashes first, then oldest first, within today's
    /// allowance.
    func batch(today: String) -> [DiagEvent] {
        let used: Int = day == today ? sentToday : 0
        let room: Int = max(0, min(Self.maxPerUpload, Self.maxPerDay - used))
        let ordered = events.sorted { a, b in
            if a.kind.isFatal != b.kind.isFatal { return a.kind.isFatal }
            return a.at < b.at
        }
        return Array(ordered.prefix(room))
    }

    /// The server took these.
    mutating func sent(_ ids: [String], today: String) {
        if day != today { day = today; sentToday = 0 }
        let taken = events.filter { ids.contains($0.id) }
        sentToday += taken.count
        events.removeAll { ids.contains($0.id) }
        recent = Array((taken + recent).prefix(Self.recentKept))
    }

    /// The server refused these for what they are: sending again would not help.
    mutating func drop(_ ids: [String]) {
        events.removeAll { ids.contains($0.id) }
    }

    mutating func prune(now: Int) {
        let cutoff: Int = now - Self.maxAgeDays * 86_400
        events.removeAll { $0.at < cutoff }
    }

    /// Once a day per build, an empty report says the build is running, so a
    /// fixed problem can be told from a quiet week.
    func pingDue(today: String, build: String) -> Bool {
        pingedDay != today || pingedBuild != build
    }

    mutating func pinged(today: String, build: String) {
        pingedDay = today
        pingedBuild = build
    }

    static func dayString(_ time: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y: Int = c.year ?? 1970, m: Int = c.month ?? 1, d: Int = c.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}

/// Written while the app is on screen, removed when it goes to the
/// background. Still there at the next launch, it means the app ended while
/// in use: a crash, or killed for memory or by the watchdog.
struct DiagRunMarker: Codable, Equatable {
    var build: String
    var startedAt: Int
    /// set while in the foreground
    var activeSince: Int?
    var crumbs: [DiagCrumb] = []

    /// The report a marker left by the last run stands for, if any.
    static func uncleanExit(_ previous: DiagRunMarker?, binary: String) -> DiagEvent? {
        guard let previous, let since = previous.activeSince else { return nil }
        let at: Int = max(since, previous.crumbs.last?.t ?? since)
        var trail = DiagBreadcrumbs()
        for c in previous.crumbs { trail.add(c.s, at: c.t) }
        var event = DiagEvent(kind: .unclean, area: .app, message: "app.ended_in_use", at: at)
        event.breadcrumbs = trail.before(at)
        event.fingerprint = DiagFingerprint.of(event, binary: binary)
        return event
    }
}

// MARK: - MetricKit's call stacks

/// Reads MXCallStackTree.jsonRepresentation():
/// callStacks[] -> threadAttributed, callStackRootFrames[] -> subFrames[].
/// A crash's attributed thread is the one that crashed; its root frame is the
/// innermost (where it crashed) and each subFrame is the caller. A hang's tree
/// is sampled and can branch: the busiest branch is followed.
enum DiagCallStack {
    static func frames(fromJSON data: Data, limit: Int = 32) -> [DiagFrame] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stacks = object["callStacks"] as? [[String: Any]], !stacks.isEmpty else { return [] }
        let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks[0]
        guard let roots = stack["callStackRootFrames"] as? [[String: Any]] else { return [] }
        var out: [DiagFrame] = []
        var level: [[String: Any]] = roots
        while out.count < limit, let next = busiest(level) {
            if let frame = frame(next) { out.append(frame) }
            level = next["subFrames"] as? [[String: Any]] ?? []
        }
        return out
    }

    private static func busiest(_ frames: [[String: Any]]) -> [String: Any]? {
        frames.max { a, b in
            let x: Int = (a["sampleCount"] as? NSNumber)?.intValue ?? 0
            let y: Int = (b["sampleCount"] as? NSNumber)?.intValue ?? 0
            return x < y
        }
    }

    private static func frame(_ node: [String: Any]) -> DiagFrame? {
        guard let name = node["binaryName"] as? String,
              let offset = (node["offsetIntoBinaryTextSegment"] as? NSNumber)?.uint64Value else { return nil }
        return DiagFrame(b: name, u: node["binaryUUID"] as? String, o: offset)
    }
}

// MARK: - The copied report

enum DiagReportText {
    static func text(_ events: [DiagEvent], device: DiagDevice) -> String {
        var lines: [String] = []
        lines.append("Diagnostics \u{2014} \(device.buildName) \(device.flavour)")
        lines.append("\(device.model) \u{00B7} iOS \(device.os) \u{00B7} \(device.memoryGB) GB \u{00B7} \(device.freeDiskGB) GB free \u{00B7} \(device.thermal) \u{00B7} graphics \(device.graphics)")
        for e in events {
            lines.append("")
            let when: String = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(e.at)))
            lines.append("[\(e.kind.rawValue)] \(DiagFingerprint.title(e, binary: device.binary)) \u{00D7}\(e.count) \u{2014} \(when)")
            lines.append("  fingerprint \(e.fingerprint)")
            for (i, f) in e.frames.prefix(12).enumerated() {
                lines.append("  \(i) \(f.b)+0x\(String(f.o, radix: 16))")
            }
            if !e.breadcrumbs.isEmpty {
                lines.append("  trail: " + e.breadcrumbs.map { "-\($0.t)s \($0.s)" }.joined(separator: ", "))
            }
        }
        return lines.joined(separator: "\n")
    }
}
