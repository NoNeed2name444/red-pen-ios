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
// shows summaries sooner), the far one draws fewer bundles (the narrowest
// and faintest go first). The split is never coarsened for time it did not
// cost, so a costly far stage cannot hide every note. A long run of
// cheap frames opens them sooner again, slowly (/ 1.05 after 45 frames
// under half the share), so the detail never see-saws. After a change the
// controller waits out the frames already on their way to the GPU before
// judging again.
//
// The same number paces the streaming: how many links are copied and how
// many bodies laid out a frame scale with the room left in the frame.
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
    /// Frames to wait after a change (the ones in flight still carry the old detail).
    static let settle: Int = 4

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
    /// frame's own cost counts: a refresh missed while it was within its
    /// share is the system's (on the simulator, every few frames).
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
                    setSplit(split * Self.coarser)
                case .cpu:
                    if stages.plan >= stages.cpu * 0.5 { setSplit(split * Self.coarser) }
                }
            }
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

    /// Room to spare: the notes come back first (down to where the tier
    /// starts), then the bundles, then finer detail still.
    private mutating func finer(_ step: Float) {
        if split > startSplit {
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

    /// Links copied to the GPU this frame (at least a leaf's worth).
    var linkBudget: Int { 16_000 + Int(160_000 * room) }
    /// Bodies laid out this frame.
    var bodyBudget: Int { 8_000 + Int(72_000 * room) }

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

/// Link pages on the GPU: a phone with less memory keeps fewer leaves'
/// links (and so draws fewer links in full); the bodies and summaries are
/// always all there.
nonisolated enum GraphPerfMemoryBudget {
    /// Pages of 1,024 links (8 bytes each): 8 MB of them under 4 GB, 24 MB
    /// under 6 GB, 40 MB above.
    static func linkPages(physicalMemory: UInt64) -> Int {
        let gb: UInt64 = 1 << 30
        if physicalMemory > 0 && physicalMemory < 4 * gb { return 1_024 }
        if physicalMemory > 0 && physicalMemory < 6 * gb { return 3_072 }
        return 5_120
    }
}
