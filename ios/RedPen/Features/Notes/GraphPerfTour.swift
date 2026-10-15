// The million map's proof tour (plan 4f's measured before and after, D5).
//
// Under -graphPreviewPerfTour the Performance map flies this tour by itself,
// the same path on every run, and counts its frames:
//
//   warm      3 s      the map starts turning, eased in; not measured
//   measure   10 s     a steady turn and two zooms, in to about the map's
//                      edge and out again, measured; then 1 s easing to rest,
//                      one whole turn from where it began
//   front     8 s      still: the whole map from the usual angle
//   turn      1.2 s    half a turn, eased; the swap is timed from its end
//                      until no cell is still morphing to its shell's detail
//   back      8 s      still: the far side now in front
//   near      13 s     3 s round to the front and in to the hub (a well-linked
//                      note near the front), then still
//   chosen    8 s      still, the hub chosen
//   far       8 s      a cut to the whole map (the tour's one jump), still
//   compare   6 x 4 s  high, smooth and saver, each with the fade off and then
//                      on: 1 s still while the switch settles, then 3 s of a
//                      slow eased turn, measured; a level's off and on runs
//                      turn over the same arc, one each way
//
// and then step gives nil. A pose is a function of the time alone, eased
// from the one before (no jump but the cut at far), so two runs, or two
// builds, fly the same path.
//
// Each drawn frame's report counts towards its step's phase. The summary
// has a line per phase begun: the frame rate's median, 5th percentile and
// 1% low (the rates at the median, 95th and 99th percentile frame interval,
// nearest rank), the CPU's and GPU's median and 95th percentile, and the
// medians of draw calls, instances and cells per depth shell, with the GPU
// memory's peak and the frames counted; the turn's line has the swap, and a
// last line the whole tour's GPU memory peak. A phase's numbers are worked
// out once, after it ends, so the tour adds next to nothing to the frames
// it measures.
//
// Foundation only, free of Stethoscore types: tested on Linux
// (Tests/GraphPerfTourTests.swift).
import Foundation

/// What the tour knows of the map (filled by the map view).
nonisolated struct GraphPerfTourMap: Sendable {
    var centre: SIMD3<Float>
    var radius: Float
    /// The view's size (points).
    var width: Float
    var height: Float
    /// The whole map's framing.
    var whole: GraphPerfCamera
    /// A well-linked note near the front, to fly to and choose.
    var hub: Int?
    var hubPosition: SIMD3<Float>?
}

/// What the tour asks of one frame.
nonisolated struct GraphPerfTourStep: Sendable, Equatable {
    /// The pose for this frame.
    var camera: GraphPerfCamera
    /// The readout shows "tour: <phase>".
    var phase: String
    /// A Graphics level to force (nil keeps the user's).
    var tier: GraphPerfTier? = nil
    /// The depth fade on; off gives the "before" numbers.
    var fade: Bool = true
    /// The body chosen (the scene's body index); nil: nothing chosen.
    var select: Int? = nil
    /// This frame counts towards `phase`'s numbers.
    var measuring: Bool = false
}

/// One drawn frame's numbers, from the renderer.
nonisolated struct GraphPerfFrameReport: Sendable, Equatable {
    /// Seconds since the frame before.
    var interval: Double
    /// The CPU's own frame time (seconds).
    var cpu: Double
    /// The GPU's (seconds; a wall-clock estimate on the simulator).
    var gpu: Double
    var drawCalls: Int
    /// Bodies, glows, bundles and the chosen neighbourhood drawn.
    var instances: Int
    /// MTLDevice.currentAllocatedSize (bytes).
    var gpuMemory: Int
    /// Cells still moving to their shell's detail.
    var ramping: Int
    /// Cells in the front, middle and back shells.
    var shells: SIMD3<Int32>
}

nonisolated final class GraphPerfTour {
    /// One stretch of the tour: its name, how long it lasts, and the part of
    /// it measured (seconds into it; nil for none).
    struct Phase: Sendable, Equatable {
        let name: String
        let duration: Double
        let measured: Range<Double>?
    }

    // MARK: - The schedule

    static let warmTime: Double = 3
    /// The opening turn's speed eases in over this much of the warm-up.
    static let rampIn: Double = 1.5
    static let measureTime: Double = 10
    /// After the measure, the turn eases to rest over this long.
    static let rampOut: Double = 1
    /// Zooms in and out again during the measure.
    static let zoomCycles: Double = 2
    static let stillTime: Double = 8
    static let turnTime: Double = 1.2
    /// The flight round to the front and in to the hub.
    static let flyTime: Double = 3
    static let nearStill: Double = 10
    /// Each comparison: still while the switch settles, then a slow turn.
    static let settleTime: Double = 1
    static let sweepTime: Double = 3
    /// How far each comparison turns (radians).
    static let sweep: Double = Double.pi / 4
    /// The hub is framed in a ball this share of the map's radius across: on
    /// the million (radius 688, a spacing of 1) about the 4.9 spacings the
    /// map's own flight to a note frames.
    static let nearShare: Float = 0.0075
    /// The levels compared, each with the fade off and then on.
    static let levels: [GraphPerfTier] = [.high, .smooth, .saver]

    static let schedule: [Phase] = {
        var out: [Phase] = [
            Phase(name: "warm", duration: warmTime, measured: nil),
            Phase(name: "measure", duration: measureTime + rampOut, measured: 0..<measureTime),
            Phase(name: "front", duration: stillTime, measured: 0..<stillTime),
            Phase(name: "turn", duration: turnTime, measured: 0..<turnTime),
            Phase(name: "back", duration: stillTime, measured: 0..<stillTime),
            Phase(name: "near", duration: flyTime + nearStill, measured: flyTime..<(flyTime + nearStill)),
            Phase(name: "chosen", duration: stillTime, measured: 0..<stillTime),
            Phase(name: "far", duration: stillTime, measured: 0..<stillTime)
        ]
        for level in levels {
            for fade in [false, true] {
                out.append(Phase(name: compareName(level, fade: fade), duration: settleTime + sweepTime,
                                 measured: settleTime..<(settleTime + sweepTime)))
            }
        }
        return out
    }()

    /// "compare smooth fade off"
    static func compareName(_ tier: GraphPerfTier, fade: Bool) -> String {
        "compare " + levelName(tier) + " fade " + (fade ? "on" : "off")
    }

    static func levelName(_ tier: GraphPerfTier) -> String {
        switch tier {
        case .high: return "high"
        case .smooth: return "smooth"
        case .saver: return "saver"
        }
    }

    /// When each phase starts (seconds into the tour).
    static let starts: [Double] = {
        var at: Double = 0
        return schedule.map { phase in
            defer { at += phase.duration }
            return at
        }
    }()

    /// The whole tour (seconds).
    static let duration: Double = schedule.reduce(0) { $0 + $1.duration }

    private static let index: [String: Int] = {
        var out: [String: Int] = [:]
        for (k, phase) in schedule.enumerated() { out[phase.name] = k }
        return out
    }()

    private static let turnIndex: Int = index["turn"] ?? 3
    private static let backIndex: Int = index["back"] ?? 4
    private static let nearIndex: Int = index["near"] ?? 5
    private static let chosenIndex: Int = index["chosen"] ?? 6
    private static let farIndex: Int = index["far"] ?? 7
    private static let compareIndex: Int = index[compareName(.high, fade: false)] ?? 8

    /// The phase at `t` seconds into the tour and how far into it (nil once over).
    static func locate(_ t: Double) -> (phase: Int, at: Double)? {
        guard t < duration else { return nil }
        let time = max(t, 0)
        var k = schedule.count - 1
        while k > 0 && starts[k] > time { k -= 1 }
        return (k, time - starts[k])
    }

    // MARK: - The path

    /// The opening turn's steady speed (rad/s): eased in, steady and eased
    /// out, it comes to one whole turn, so the front still is the view the
    /// tour began with and the hub is in front again.
    static var openingSpeed: Double {
        2 * Double.pi / (rampIn / 2 + (warmTime + measureTime - rampIn) + rampOut / 2)
    }

    /// Smoothstep: 0 below 0, 1 above 1, flat at both ends.
    static func ease(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// How far a speed eased in from rest over `ramp` seconds has gone `t`
    /// seconds in, at a steady speed of 1 after the ramp.
    static func easedIn(_ t: Double, ramp: Double) -> Double {
        guard t > 0 else { return 0 }
        guard t < ramp else { return ramp / 2 + (t - ramp) }
        let x = t / ramp
        return ramp * (x * x * x - x * x * x * x / 2)
    }

    /// How far a speed of 1 eased to rest over `ramp` seconds has gone `t` seconds in.
    static func easedOut(_ t: Double, ramp: Double) -> Double {
        guard t > 0 else { return 0 }
        guard t < ramp else { return ramp / 2 }
        let x = t / ramp
        return t - ramp * (x * x * x - x * x * x * x / 2)
    }

    /// The opening turn `t` seconds into the tour (radians, 0 to one whole turn).
    static func openingTurn(_ t: Double) -> Double {
        let steady = warmTime + measureTime
        if t <= steady { return openingSpeed * easedIn(t, ramp: rampIn) }
        return openingSpeed * (easedIn(steady, ramp: rampIn) + easedOut(t - steady, ramp: rampOut))
    }

    /// The measure's zoom `u` seconds into it: the log of the distance's share
    /// of the whole view's (0 at both ends, flat there; `depth` at its deepest).
    static func zoom(_ u: Double, depth: Double) -> Double {
        guard u > 0 && u < measureTime else { return 0 }
        return -depth * (1 - cos(2 * Double.pi * zoomCycles * u / measureTime)) / 2
    }

    // MARK: - The tour

    let map: GraphPerfTourMap
    /// The whole map's framing, and the hub's, framed from the front.
    let whole: GraphPerfCamera
    let near: GraphPerfCamera
    /// How deep the measure's zooms go: the log of the whole view's distance
    /// over the nearest (about the map's radius: the eye at its edge).
    let zoomDepth: Double

    private let lock = NSLock()
    private var tallies: [Tally]
    /// Lines worked out for phases that are over.
    private var lines: [String?]
    /// The latest phase recorded.
    private var current: Int = -1
    private var finished: Bool = false
    private var frames: Int = 0
    private var seconds: Double = 0
    private var memoryPeak: Int = 0
    /// The swap: the time since the turn's last frame, and whether (and when)
    /// a frame after it had no cell ramping.
    private var afterTurn: Double = 0
    private var turnSeen: Bool = false
    private var swap: Double?
    private var stillRamping: Int = 0

    init(map: GraphPerfTourMap) {
        self.map = map
        var whole = map.whole
        whole.distance = max(whole.distance.isFinite ? whole.distance : 1, 1e-3)
        self.whole = whole
        let ball: Float = max(map.radius * Self.nearShare, 1e-3)
        near = whole.framing(centre: map.hubPosition ?? map.centre, radius: ball, width: map.width,
                             height: map.height, fill: 0.9)
        let nearest: Float = min(max(map.radius, 1e-3), whole.distance * 0.8)
        zoomDepth = Double(log(whole.distance / nearest))
        tallies = Array(repeating: Tally(), count: Self.schedule.count)
        lines = Array(repeating: nil, count: Self.schedule.count)
    }

    /// The step `seconds` into the tour; nil when it is done.
    func step(at seconds: Double) -> GraphPerfTourStep? {
        guard let (k, u) = Self.locate(seconds.isNaN ? 0 : seconds) else {
            lock.lock()
            finished = true
            lock.unlock()
            return nil
        }
        let phase = Self.schedule[k]
        var step = GraphPerfTourStep(camera: camera(phase: k, at: u), phase: phase.name)
        step.measuring = phase.measured?.contains(u) ?? false
        if k == Self.chosenIndex { step.select = map.hub }
        if k >= Self.compareIndex {
            let run = k - Self.compareIndex
            step.tier = Self.levels[min(run / 2, Self.levels.count - 1)]
            step.fade = run % 2 == 1
        }
        return step
    }

    /// The pose `u` seconds into phase `k`.
    private func camera(phase k: Int, at u: Double) -> GraphPerfCamera {
        let start: Double = Self.starts[k]
        let yaw0: Double = Double(whole.yaw)
        let turned: Double = Self.openingTurn(Self.warmTime + Self.measureTime + Self.rampOut)
        var c = whole
        func yaw(_ angle: Double) -> Float { GraphPerfCamera.wrap(Float(yaw0 + angle)) }
        switch k {
        case ..<Self.turnIndex:
            // warm, measure, front: the opening turn, with the measure's zooms
            c.yaw = yaw(Self.openingTurn(start + u))
            if Self.schedule[k].name == "measure" {
                c.distance = whole.distance * Float(exp(Self.zoom(u, depth: zoomDepth)))
            }
        case Self.turnIndex:
            c.yaw = yaw(turned + Double.pi * Self.ease(u / Self.turnTime))
        case Self.backIndex:
            c.yaw = yaw(turned + Double.pi)
        case Self.nearIndex:
            // round to the front over the first half, then in: the hub stays on
            // screen, the target reaching it before the zoom is close
            let v: Double = min(u / Self.flyTime, 1)
            c.yaw = yaw(turned + Double.pi + Double.pi * Self.ease(v / 0.5))
            let along = Float(Self.ease((v - 0.2) / 0.6))
            c.target = whole.target + (near.target - whole.target) * along
            let closer = Float(Self.ease((v - 0.3) / 0.7))
            c.distance = exp(log(whole.distance) * (1 - closer) + log(max(near.distance, 1e-6)) * closer)
            c.pitch = whole.pitch + (near.pitch - whole.pitch) * closer
        case Self.chosenIndex:
            c.yaw = yaw(turned + 2 * Double.pi)
            c.target = near.target
            c.distance = near.distance
            c.pitch = near.pitch
        case Self.farIndex:
            break
        default:
            // compare: the run's slow turn, forth on the off run and back on the on run
            let run = k - Self.compareIndex
            let e = Self.ease((u - Self.settleTime) / Self.sweepTime)
            c.yaw = yaw(Self.sweep * (run % 2 == 0 ? e : 1 - e))
        }
        return c
    }

    /// Counts one drawn frame towards its step's phase.
    func record(_ report: GraphPerfFrameReport, step: GraphPerfTourStep) {
        guard let k = Self.index[step.phase] else { return }
        lock.lock()
        defer { lock.unlock() }
        if k > current { current = k }
        tallies[k].add(report, measuring: step.measuring)
        lines[k] = nil
        frames += 1
        if report.interval > 0 && report.interval.isFinite { seconds += report.interval }
        memoryPeak = max(memoryPeak, report.gpuMemory)
        // the swap: from the turn's last frame until a frame with nothing ramping
        if k == Self.turnIndex {
            turnSeen = true
            afterTurn = 0
            swap = nil
            stillRamping = report.ramping
        } else if k == Self.backIndex && turnSeen && swap == nil {
            if report.interval > 0 && report.interval.isFinite { afterTurn += report.interval }
            if report.ramping <= 0 {
                swap = afterTurn
            } else {
                stillRamping = report.ramping
            }
        }
    }

    /// One line per phase begun, in order, then "done" once the tour is over.
    var summary: String {
        lock.lock()
        defer { lock.unlock() }
        var out: [String] = []
        for k in 0..<Self.schedule.count where tallies[k].frames > 0 {
            let over = finished || k < current
            if !over {
                out.append(Self.schedule[k].name + ": " + Self.grouped(tallies[k].frames) + " frames so far")
                continue
            }
            // the turn's line waits for the swap, until the still after it ends
            let settled = k != Self.turnIndex || swap != nil || finished || current > Self.backIndex
            if let line = lines[k] {
                out.append(line)
            } else {
                let line = phaseLine(k)
                if settled { lines[k] = line }
                out.append(line)
            }
        }
        if finished {
            out.append("done: " + Self.tenths(seconds) + " s, " + Self.grouped(frames) + " frames \u{00B7} GPU memory peak "
                       + Self.megabytes(memoryPeak))
        }
        return out.joined(separator: "\n")
    }

    /// A phase's line, from its frames.
    private func phaseLine(_ k: Int) -> String {
        let tally = tallies[k]
        var parts: [String] = []
        switch k {
        case Self.turnIndex:
            parts.append(swapWords)
        case Self.nearIndex, Self.chosenIndex:
            parts.append(map.hub.map { "hub " + String($0) } ?? "no hub, the centre")
        default:
            break
        }
        guard !tally.measured.isEmpty else {
            parts.append(Self.grouped(tally.frames) + " frames in " + Self.tenths(tally.seconds) + " s, not measured")
            return Self.schedule[k].name + ": " + parts.joined(separator: " \u{00B7} ")
        }
        parts.append(Self.numbers(tally.measured).words)
        parts.append("GPU " + Self.megabytes(tally.memoryPeak))
        let counted = tally.measured.count
        parts.append(Self.grouped(counted) + (counted == tally.frames ? "" : " of " + Self.grouped(tally.frames))
                     + " frames")
        return Self.schedule[k].name + ": " + parts.joined(separator: " \u{00B7} ")
    }

    /// "swap 340 ms", or how long it has been without one.
    private var swapWords: String {
        if let swap { return "swap " + Self.wholeMillis(swap) + " ms" }
        if current > Self.backIndex || (finished && turnSeen) {
            return "swap over " + Self.wholeMillis(afterTurn) + " ms (" + Self.grouped(stillRamping) + " cells still ramping)"
        }
        return "swap pending"
    }

    // MARK: - The numbers

    /// A phase's frames so far.
    private struct Tally {
        var frames: Int = 0
        var seconds: Double = 0
        var memoryPeak: Int = 0
        var measured: [GraphPerfFrameReport] = []

        mutating func add(_ report: GraphPerfFrameReport, measuring: Bool) {
            frames += 1
            if report.interval > 0 && report.interval.isFinite { seconds += report.interval }
            memoryPeak = max(memoryPeak, report.gpuMemory)
            if measuring { measured.append(report) }
        }
    }

    /// What a phase's measured frames come to.
    struct Numbers: Sendable, Equatable {
        /// Frames a second: at the median interval, the 5th percentile, the 1% low.
        var fps: Double
        var fpsP5: Double
        var fpsLow: Double
        /// Seconds: the median and 95th percentile (GPU: of the frames that report it; nil for none).
        var cpu: Double
        var cpuP95: Double
        var gpu: Double?
        var gpuP95: Double?
        /// Medians.
        var drawCalls: Int
        var instances: Int
        var shells: SIMD3<Int32>

        /// "60.0 fps (p5 54.2, 1% low 41.0) · cpu 2.1 (p95 3.4) · gpu 7.9 (p95 9.2) ms · 41 draws ·
        /// 412,331 instances · cells 812/1,940/3,377"
        var words: String {
            let rate = GraphPerfTour.tenths(fps) + " fps (p5 " + GraphPerfTour.tenths(fpsP5) + ", 1% low "
                + GraphPerfTour.tenths(fpsLow) + ")"
            let gpuWords = gpu.map { "gpu " + GraphPerfTour.millis($0) + " (p95 " + GraphPerfTour.millis(gpuP95 ?? $0) + ") ms" }
                ?? "gpu not reported"
            let times = "cpu " + GraphPerfTour.millis(cpu) + " (p95 " + GraphPerfTour.millis(cpuP95) + ")"
                + (gpu == nil ? " ms \u{00B7} " : " \u{00B7} ") + gpuWords
            let cells = "cells " + GraphPerfTour.grouped(Int(shells.x)) + "/" + GraphPerfTour.grouped(Int(shells.y)) + "/"
                + GraphPerfTour.grouped(Int(shells.z))
            return [rate, times, GraphPerfTour.grouped(drawCalls) + (drawCalls == 1 ? " draw" : " draws"),
                    GraphPerfTour.grouped(instances) + " instances", cells].joined(separator: " \u{00B7} ")
        }
    }

    /// The numbers of a run of frames (zeros for none).
    static func numbers(_ reports: [GraphPerfFrameReport]) -> Numbers {
        let fps = rates(reports.map(\.interval))
        let cpu = reports.map(\.cpu).filter { $0.isFinite && $0 >= 0 }.sorted()
        let gpu = reports.map(\.gpu).filter { $0.isFinite && $0 > 0 }.sorted()
        func middle(_ values: [Int]) -> Int { Int(median(values.map(Double.init).sorted()).rounded()) }
        let shells = SIMD3<Int32>(Int32(middle(reports.map { Int($0.shells.x) })),
                                  Int32(middle(reports.map { Int($0.shells.y) })),
                                  Int32(middle(reports.map { Int($0.shells.z) })))
        return Numbers(fps: fps.median, fpsP5: fps.p5, fpsLow: fps.low,
                       cpu: median(cpu), cpuP95: percentile(cpu, 0.95),
                       gpu: gpu.isEmpty ? nil : median(gpu), gpuP95: gpu.isEmpty ? nil : percentile(gpu, 0.95),
                       drawCalls: middle(reports.map(\.drawCalls)), instances: middle(reports.map(\.instances)),
                       shells: shells)
    }

    /// The frame rate over frame intervals (seconds): the rates at the median
    /// interval, at the 95th percentile's (the 5th percentile of the rate:
    /// one frame in twenty is slower) and at the 99th's (the 1% low: one in a
    /// hundred is slower). Intervals that are not positive are left out.
    static func rates(_ intervals: [Double]) -> (median: Double, p5: Double, low: Double) {
        let sorted = intervals.filter { $0 > 0 && $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return (0, 0, 0) }
        return (1 / median(sorted), 1 / percentile(sorted, 0.95), 1 / percentile(sorted, 0.99))
    }

    /// The middle of sorted values, or the mean of the two middle ones (0 for none).
    static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let n = sorted.count
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }

    /// Nearest rank, as GraphPerfFrameStats: the smallest of sorted values
    /// with at least `q` of them at or under it (0 for none).
    static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((q * Double(sorted.count) - 1e-9).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    // MARK: - Words (a dot and commas in every locale: the summary is a meter)

    /// To one decimal: "59.9".
    static func tenths(_ x: Double) -> String {
        let tenths = Int((x.isFinite ? max(x, 0) : 0) * 10 + 0.5)
        return String(tenths / 10) + "." + String(tenths % 10)
    }

    /// Seconds as milliseconds to one decimal: "2.1".
    static func millis(_ seconds: Double) -> String { tenths(seconds * 1_000) }

    /// Seconds as whole milliseconds, grouped: "1,340".
    static func wholeMillis(_ seconds: Double) -> String {
        grouped(Int((seconds.isFinite ? max(seconds, 0) : 0) * 1_000 + 0.5))
    }

    /// Bytes as megabytes (millions) to one decimal: "412.7 MB".
    static func megabytes(_ bytes: Int) -> String { tenths(Double(bytes) / 1_000_000) + " MB" }

    /// Thousands with commas: "412,331".
    static func grouped(_ n: Int) -> String {
        let digits = String(n.magnitude)
        var out = ""
        for (k, ch) in digits.enumerated() {
            if k > 0 && (digits.count - k) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + out
    }
}
