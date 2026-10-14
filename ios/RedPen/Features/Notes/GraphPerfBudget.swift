// The million map's frame budget (plans 4c and 4e): the map runs at the
// screen's own rate - 120 frames a second on ProMotion, 60 elsewhere - and a
// device that cannot keep it draws less, never slower.
//
// Each frame reports what it cost (its CPU time, and its GPU time once the
// GPU is done) and how long since the last one. A frame over its share of
// the refresh (`share` of 1/rate: 6.25 ms of 8.33 at 120), or a refresh
// missed, counts against the detail; two in a row and cells open later
// (`split` x 1.2, so a slow phone shows summaries sooner). A long run of
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
    /// Frames to wait after a change (the ones in flight still carry the old detail).
    static let settle: Int = 4

    private var over: Int = 0
    private var under: Int = 0
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

    init(screenFPS: Int, tier: GraphPerfTier = .high) {
        self.screenFPS = Self.rate(screenFPS)
        split = Self.startingSplit(tier)
    }

    /// The rate to ask for: the screen's own, whatever the tier (30 at the least).
    static func rate(_ screenFPS: Int) -> Int { max(screenFPS, 30) }

    /// One refresh, and the map's share of it (seconds).
    var period: Double { 1 / Double(screenFPS) }
    var target: Double { period * share }

    /// A frame's cost: `cpu` and `gpu` seconds (nil while the GPU has not
    /// reported), and `interval`, the seconds since the frame before (nil
    /// for the first after a pause).
    mutating func record(cpu: Double, gpu: Double?, interval: Double?) {
        let cost = max(cpu, gpu ?? 0)
        lastCost = cost
        if wait > 0 {
            wait -= 1
            return
        }
        let missed = interval.map { $0 > period * 1.5 && $0 < 0.25 } ?? false
        if cost > target || missed {
            over += 1
            under = 0
            if over >= Self.overRun {
                setSplit(split * Self.coarser)
                over = 0
            }
        } else if cost < target * 0.5 {
            under += 1
            over = 0
            if under >= Self.underRun {
                setSplit(split / Self.finer)
                under = 0
            }
        } else {
            over = 0
            under = 0
        }
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
