// The million map's frame budget (plans 4c and 4e): the map runs at the
// screen's own rate - 120 frames a second on ProMotion, 60 elsewhere - and a
// device that cannot keep it draws less, never slower.
//
// Each frame reports what it cost, stage by stage (its CPU time, and the GPU
// time of the near stage - notes and links - and of the far stage - bundles
// and glows - once the GPU is done) and how long since the last one. A frame
// over its share of the refresh (`share` of 1/rate: 6.25 ms of 8.33 at 120)
// counts against the stage that took the time (a refresh missed by a frame
// within its share is the system's, not the map's); two in a row and that stage
// draws less: the near one opens cells later (`split` x 1.2, so a slow phone
// shows summaries sooner) and, once the split is half again its start,
// pulls the depth band in (GraphPerfDepthBand: what lies past its end is
// not drawn; `pull` x 0.9, down to 0.7); the far one draws fewer bundles
// (the narrowest and faintest go first). The split is never coarsened for
// time it did not cost, so a costly far stage cannot hide every note. A
// long run of cheap frames gives the band back first, then opens cells
// sooner again, slowly (/ 1.05 after 45 frames under half the share), so
// the detail never see-saws. After a change the controller waits out the
// frames already on their way to the GPU before judging again.
//
// The same number paces the streaming: how many bodies are laid out a frame
// scales with the room left in the frame.
//
// Foundation only: tested on Linux (Tests/GraphPerfBudgetTests.swift).
import Foundation

nonisolated struct GraphPerfFrameBudget: Sendable, Equatable {
    /// The screen's fastest rate (UIScreen.maximumFramesPerSecond).
    let screenFPS: Int
    /// The share of a refresh the map may spend (the rest is the system's).
    var share: Double = 0.75
    /// The split size (points, radius): a cell opens once it is this big on screen.
    private(set) var split: Float
    static let finest: Float = 16
    static let coarsest: Float = 480
    static let coarser: Float = 1.2
    static let finer: Float = 1.05
    /// Frames over budget in a row before coarser; under half before finer.
    static let overRun: Int = 2
    static let underRun: Int = 45
    /// Far under (a quarter of the target): finer by more, sooner, so detail
    /// lost to a stall comes back in a second or two, not forty.
    static let farFiner: Float = 1.25
    static let farUnderRun: Int = 10
    /// A frame this slow is a stall (the map being built, the app waking),
    /// not the load the detail puts on the GPU: it is not counted.
    static let stall: Double = 0.25
    /// Frames not counted after a map is shown (its first frames carry the build).
    static let warmUp: Int = 30
    /// A frame interval past this many refreshes is a missed refresh.
    static let missed: Double = 1.25
    /// Frames to wait after a change (the ones in flight still carry the old detail).
    static let settle: Int = 4
    /// The depth band's width as the budget allows it (GraphPerfDepthBand.depths):
    /// pulled in by `pullStep` once the split is `pullAfter` times its start.
    private(set) var pull: Float = 1
    static let pullStep: Float = 0.9
    static let pullAfter: Float = 1.5

    /// The share of the bundles drawn, heaviest first (the far stage's detail).
    private(set) var bundleShare: Double = 1
    static let bundleCut: Double = 0.7
    static let fewestBundles: Double = 0.05
    /// Where the split starts (the tier's), the first thing room buys back.
    private let startSplit: Float
    /// The last frame's stages, for the readout.
    private(set) var lastStages = GraphPerfFrameStages(cpu: 0, near: nil, far: nil)

    private var over: Int = 0
    private var under: Int = 0
    private var farUnder: Int = 0
    private var wait: Int = 0
    /// The last frames' costs, for the readout (seconds).
    private(set) var lastCost: Double = 0
    private(set) var changes: Int = 0

    /// The starting split for each graphics tier: the saver starts coarse.
    static func startingSplit(_ tier: GraphPerfTier) -> Float {
        switch tier {
        case .high: return 26
        case .smooth: return 34
        case .saver: return 56
        }
    }

    /// `warmUp`: the first frames not counted (GraphPerfFrameBudget.warmUp
    /// when a map has just been shown).
    init(screenFPS: Int, tier: GraphPerfTier = .high, warmUp: Int = 0) {
        self.screenFPS = Self.rate(screenFPS)
        split = Self.startingSplit(tier)
        startSplit = split
        wait = max(warmUp, 0)
    }

    /// The rate to ask for: the screen's own, whatever the tier (30 at the least).
    static func rate(_ screenFPS: Int) -> Int { max(screenFPS, 30) }

    /// One refresh, and the map's share of it (seconds).
    var period: Double { 1 / Double(screenFPS) }
    var target: Double { period * share }

    /// A frame's cost when only the total GPU time is known: all of it is
    /// taken as the near stage (the detail).
    mutating func record(cpu: Double, gpu: Double?, interval: Double?) {
        record(GraphPerfFrameStages(cpu: cpu, near: gpu, far: nil, plan: cpu), interval: interval)
    }

    /// A frame's cost, stage by stage (seconds; a GPU stage is nil until the
    /// GPU reports it), and `interval`, the seconds since the frame before
    /// (nil for the first after a pause).
    ///
    /// Over budget, the stage that took the time pays: the near stage by a
    /// coarser split, the far stage by fewer bundles, the CPU by a coarser
    /// split only when planning (which grows with what is open) is most of
    /// it. The split never coarsens for time it did not cost. Only the
    /// frame's own cost counts against it: a refresh missed while it was
    /// within its share may be the system's (on the simulator, every few
    /// frames), so it cuts nothing, but it opens nothing further either.
    mutating func record(_ stages: GraphPerfFrameStages, interval: Double?) {
        let cost = stages.cost
        lastCost = cost
        lastStages = stages
        if wait > 0 {
            wait -= 1
            return
        }
        if cost >= Self.stall { return }
        if cost > target {
            over += 1
            under = 0
            farUnder = 0
            if over >= Self.overRun {
                over = 0
                switch stages.heaviest {
                case .far:
                    setBundleShare(bundleShare * Self.bundleCut)
                case .near:
                    coarser()
                case .cpu:
                    if stages.plan >= stages.cpu * 0.5 { coarser() }
                }
            }
        } else if let interval, interval > period * Self.missed {
            // a refresh missed though the frame was cheap: where the GPU's
            // time is not reported (the simulator says 0) this may be the
            // GPU, so nothing opens further; nothing closes for it either
            under = 0
            farUnder = 0
        } else if cost < target * 0.5 {
            under += 1
            over = 0
            farUnder = cost < target * 0.25 ? farUnder + 1 : 0
            if farUnder >= Self.farUnderRun {
                finer(Self.farFiner)
                under = 0
                farUnder = 0
            } else if under >= Self.underRun {
                finer(Self.finer)
                under = 0
            }
        } else {
            over = 0
            under = 0
            farUnder = 0
        }
    }

    /// Less detail: a coarser split, and past half again its start, a
    /// tighter depth band too (it culls the most for the least seen).
    private mutating func coarser() {
        if split >= startSplit * Self.pullAfter && pull > GraphPerfDepthBand.tightest {
            setPull(pull * Self.pullStep)
        } else {
            setSplit(split * Self.coarser)
        }
    }

    private mutating func setPull(_ next: Float) {
        let clamped = min(max(next, GraphPerfDepthBand.tightest), 1)
        guard clamped != pull else { return }
        pull = clamped
        wait = Self.settle
        changes += 1
    }

    /// Room to spare: the depth band comes back first, then the notes
    /// (down to where the tier starts), then the bundles, then finer detail
    /// still.
    private mutating func finer(_ step: Float) {
        if pull < 1 {
            setPull(pull / Self.pullStep)
        } else if split > startSplit {
            setSplit(max(split / step, startSplit))
        } else if bundleShare < 1 {
            setBundleShare(min(bundleShare / Self.bundleCut, 1))
        } else {
            setSplit(split / step)
        }
    }

    private mutating func setBundleShare(_ next: Double) {
        let clamped = min(max(next, Self.fewestBundles), 1)
        guard clamped != bundleShare else { return }
        bundleShare = clamped
        wait = Self.settle
        changes += 1
    }

    /// How many of `count` bundles to draw (heaviest first): at least one.
    func bundleLimit(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(Int((Double(count) * bundleShare).rounded(.up)), 1), count)
    }

    private mutating func setSplit(_ next: Float) {
        let clamped = min(max(next, Self.finest), Self.coarsest)
        guard clamped != split else { return }
        split = clamped
        wait = Self.settle
        changes += 1
    }

    /// The room left in this frame, 0...1 (the share of the target not spent).
    var room: Double { min(max(1 - lastCost / max(target, 1e-6), 0), 1) }

    /// Bodies laid out this frame (at least a leaf's: GraphPerfStreamer).
    var bodyBudget: Int { 4_000 + Int(24_000 * room) }

    /// The chunk settings this budget asks for.
    var settings: GraphPerfChunkSettings {
        var s = GraphPerfChunkSettings()
        s.split = split
        return s
    }
}

/// One frame's cost by stage (seconds): the CPU's (planning, streaming and
/// encoding; not the waits for a free slot or a drawable), the GPU's near
/// stage (layout, notes, links: what the split opens) and far stage
/// (bundles and summary glows), and of the CPU's, the planning. A GPU stage
/// is nil until it reports.
nonisolated struct GraphPerfFrameStages: Sendable, Equatable {
    var cpu: Double
    var near: Double?
    var far: Double?
    /// The part of `cpu` spent planning (it grows with the split).
    var plan: Double = 0

    enum Stage: Sendable, Equatable { case cpu, near, far }

    /// The frame's cost: the CPU and the GPU run side by side.
    var cost: Double { max(cpu, (near ?? 0) + (far ?? 0)) }

    /// The stage that took the most.
    var heaviest: Stage {
        let n = near ?? 0, f = far ?? 0
        if f > n && f > cpu { return .far }
        return n >= cpu ? .near : .cpu
    }
}

/// A frame's GPU stages from the wall clock, for where the GPU's own
/// timestamps are missing (the simulator reports about 0, so the budget
/// would never see the GPU's load): the near stage runs from when its
/// command buffer could start (committed, and the frame before done) to
/// when it is done, plus the screen stage after the far one; the far stage
/// from near done to far done. Completion is seen a little late, so this
/// errs high: the budget trims a little early, never late.
nonisolated enum GraphPerfWallStages {
    /// The GPU's own times are used while they cover this share of the wall's.
    static let trusted: Double = 0.25

    /// Host times (seconds): A (near) committed, A, B (far) and C (screen)
    /// done, and the frame before's C done.
    static func stages(commitA: Double, doneA: Double, doneB: Double, doneC: Double,
                       lastDoneC: Double) -> (near: Double, far: Double) {
        let start = max(commitA, lastDoneC)
        let near = max(doneA - start, 0) + max(doneC - max(doneB, doneA), 0)
        let far = max(doneB - doneA, 0)
        return (near, far)
    }

    /// Whether the GPU's own times are believable next to the wall's.
    static func gpuTimesUsable(gpu: Double, wall: Double) -> Bool {
        wall <= 0 || gpu >= wall * trusted
    }
}

/// The million map's exposure (round 5): links, bundles and glows add up as
/// light in a half-float texture, and the screen shows that light through a
/// tone curve, 1 - exp(-k x), so a crowded region reads as a bright structure
/// rather than a flat white. `k` follows the frame's own light: the 97th
/// percentile of the lit samples in a 64 x 64 grid lands at `level` of white,
/// and the change is smoothed over `settle` seconds, in the log, so the picture
/// never pumps. The same grid's screen colours give the share of the screen at
/// or above 250 of 255 (`saturated`), which the readout shows.
nonisolated struct GraphPerfExposure: Sendable, Equatable {
    /// Where the 97th percentile of the light lands (of white).
    static let level: Float = 0.6
    static let percentile: Float = 0.97
    /// Seconds for the exposure to cover most (63%) of a change.
    static let settle: Double = 0.3
    /// The curve's strength stays in this range (a near-empty frame is not
    /// lifted to grey; a blazing one still shows its brightest).
    static let range: ClosedRange<Float> = 0.004...8
    /// Light below this counts as none.
    static let lit: Float = 1.0 / 1024
    /// A screen colour at or above this luminance counts as saturated.
    static let white: Float = 250.0 / 255.0

    /// The curve's strength: shown = 1 - exp(-k * light).
    private(set) var k: Float = 1
    /// The share of the measured screen at 250 or more (-1 before a measure).
    private(set) var saturated: Double = -1
    /// The last frame's 97th-percentile light (0 when nothing was lit).
    private(set) var high: Float = 0
    private var primed = false

    init() {}

    /// The strength that lands `light` at `level`.
    static func strength(for light: Float) -> Float {
        guard light > 0 else { return range.upperBound }
        let k = -log(1 - level) / light
        return min(max(k, range.lowerBound), range.upperBound)
    }

    /// Takes one measure: `samples` holds pairs (light luminance, screen
    /// luminance), `seconds` since the last measure.
    mutating func update(samples: UnsafeBufferPointer<Float>, seconds: Double) {
        let n = samples.count / 2
        guard n > 0 else { return }
        // light by its float bits: 8 bins an octave, no sort
        var bins = [Int32](repeating: 0, count: 2_048)
        var lit = 0, white = 0
        bins.withUnsafeMutableBufferPointer { b in
            for i in 0..<n {
                let light = samples[2 * i], shown = samples[2 * i + 1]
                if shown >= Self.white { white += 1 }
                guard light >= Self.lit, light.isFinite else { continue }
                lit += 1
                b[Int(min(light.bitPattern >> 20, 2_047))] += 1
            }
        }
        saturated = Double(white) / Double(n)
        guard lit > 0 else {
            high = 0
            return
        }
        let want = Int32((Float(lit) * Self.percentile).rounded(.up))
        var seen: Int32 = 0, bin = 0
        for i in 0..<bins.count {
            seen += bins[i]
            if seen >= want {
                bin = i
                break
            }
        }
        // the bin's middle
        high = Float(bitPattern: UInt32(bin) << 20 | (1 << 19))
        let target = Self.strength(for: high)
        if !primed {
            k = target
            primed = true
            return
        }
        let t = Float(1 - exp(-max(seconds, 0) / Self.settle))
        k = exp(log(k) + (log(target) - log(k)) * t)
    }
}
