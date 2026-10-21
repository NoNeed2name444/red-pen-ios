import Foundation

/// What a recorded opening (`-uiPreviewSplash`) notes about the hand-off's
/// long holds, beside the longest gap LaunchStage already reports: for every
/// gap between display refreshes over 50 ms, how long it was and how much of
/// it the main thread spent on the CPU (working, or waiting), and the
/// moments of the hand-off, home's first appearance and the start and end of
/// each of home's data loads. Diagnostics only: nothing here is read by the
/// app.
///
/// Every time is on the host clock (CACurrentMediaTime) as it is taken, and
/// put on the opening's clock only when the line is written (`fields`), since
/// some marks come before the hand-off is known.
struct LaunchDiagnostics {
    /// A gap this long between two refreshes is listed.
    static let gapThreshold: Double = 0.050
    /// The most marks the line holds.
    static let mostMarks = 40

    struct Gap: Equatable {
        /// When the gap ended (host clock).
        var end: Double
        /// Seconds between the two refreshes.
        var length: Double
        /// Seconds of CPU time the main thread used across it.
        var cpu: Double
    }

    struct Mark: Equatable {
        var name: String
        var start: Double
        /// Nil for a moment; the end of a load.
        var end: Double?
    }

    private(set) var gaps: [Gap] = []
    private(set) var marks: [Mark] = []
    /// The display link's nominal interval at the last refresh (seconds).
    private(set) var interval: Double?
    private var lastCPU: Double?

    /// One display refresh reaching the main thread. `end` is when it is
    /// shown (host clock), `gap` the time since the one before (nil for the
    /// first, or before the hand-off), `cpu` the main thread's CPU seconds
    /// so far, `interval` the link's nominal interval.
    mutating func tick(end: Double, gap: Double?, cpu: Double, interval: Double) {
        if let gap, gap > Self.gapThreshold, let before = lastCPU {
            gaps.append(Gap(end: end, length: gap, cpu: max(0, cpu - before)))
        }
        lastCPU = cpu
        self.interval = interval
    }

    mutating func moment(_ name: String, at host: Double) {
        marks.append(Mark(name: name, start: host, end: nil))
    }

    mutating func load(_ name: String, from start: Double, to end: Double) {
        marks.append(Mark(name: name, start: start, end: end))
    }

    /// The readout's extra fields, each led by a space:
    /// ` gaps=+0.94:117ms/cpu98ms,+1.40:62ms/cpu8ms interval_ms=16.7
    /// marks=handoff+0.73,home+0.75,plan+0.80..+1.38`. `clock` puts a host
    /// time on the opening's clock; loads outside `from`...`to` (the
    /// hand-off until home is still, opening clock) are left out.
    func fields(clock: (Double) -> Double, from: Double, to: Double) -> String {
        func s(_ x: Double) -> String { String(format: "%+.2f", x) }
        func ms(_ x: Double) -> Int { Int((x * 1000).rounded()) }
        let gapText = gaps.isEmpty ? "none"
            : gaps.map { "\(s(clock($0.end))):\(ms($0.length))ms/cpu\(ms($0.cpu))ms" }.joined(separator: ",")
        let intervalText = interval.map { String(format: "%.1f", $0 * 1000) } ?? "none"
        let kept = marks.filter { m in
            guard let end = m.end else { return true }
            return clock(end) >= from && clock(m.start) <= to
        }.sorted { $0.start < $1.start }.prefix(Self.mostMarks)
        let markText = kept.isEmpty ? "none" : kept.map { m in
            m.end.map { "\(m.name)\(s(clock(m.start)))..\(s(clock($0)))" } ?? "\(m.name)\(s(clock(m.start)))"
        }.joined(separator: ",")
        return " gaps=\(gapText) interval_ms=\(intervalText) marks=\(markText)"
    }
}
