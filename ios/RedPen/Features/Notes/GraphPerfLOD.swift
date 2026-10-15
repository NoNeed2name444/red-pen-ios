// Level of detail on the Performance map: how big and how solid each body
// and link is drawn for its size on screen, how many labels each graphics
// tier can afford, which bodies get them, and the frame-time numbers the
// speed readout shows. The shaders apply the same rules; they are written
// here too so the tests can hold them. Foundation only.
import Foundation

/// The graphics tiers, as far as this map cares.
nonisolated enum GraphPerfTier: Int, Sendable, CaseIterable {
    /// Low Power Mode or a hot device.
    case saver
    case smooth
    case high

    /// Labels on screen at once.
    var labelBudget: Int {
        switch self {
        case .high: return 12
        case .smooth: return 8
        case .saver: return 4
        }
    }

    /// A link's strength before the rules below cut it.
    var linkBase: Float { self == .high ? 0.22 : 0.14 }
}

nonisolated enum GraphPerfLOD {
    static let noteClamp: ClosedRange<Float> = 1.25...28
    static let hubClamp: ClosedRange<Float> = 3...48
    /// A cluster's glow is never drawn smaller than this radius (points).
    static let glowFloor: Float = 2

    /// The projection's vertical focal length in points: projection[1][1]
    /// times half the view height, as the pick's projection computes it.
    static func focal(projectionYY: Float, viewHeight: Float) -> Float { projectionYY * viewHeight / 2 }

    /// A body's radius on screen: world radius times focal over depth.
    static func pixelRadius(_ radius: Float, depth: Float, focal: Float) -> Float {
        depth > 0 ? radius * focal / depth : 0
    }

    /// The radius it is drawn at: never so small it vanishes between
    /// pixels, never so big one body hides the map.
    static func drawnRadius(_ rho: Float, isNote: Bool) -> Float {
        let r = isNote ? noteClamp : hubClamp
        return min(max(rho, r.lowerBound), r.upperBound)
    }

    /// A note fades out below about a pixel instead of shimmering (hubs never fade).
    static func noteAlpha(_ rho: Float) -> Float { smoothstep(0.35, 1.25, rho) }

    static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// How a link stands to the focused body ("Show links").
    enum Focus: Sendable { case none, touches, elsewhere }

    /// A link's alpha: the tier's base (x1.5 when bold, for Reduce
    /// Transparency or Increase Contrast), times its fainter end, times its
    /// length on screen (a link under 2 points is not drawn, over 12 is
    /// whole), times depth fog; links between folders x0.55 (as the
    /// Universe's far links); with a focus, the rest dimmed to x0.15.
    static func linkAlpha(tier: GraphPerfTier, bold: Bool = false, endA: Float, endB: Float,
                          lengthOnScreen: Float, fog: Float = 1, crossFolder: Bool = false,
                          focus: Focus = .none) -> Float {
        var a = tier.linkBase * (bold ? 1.5 : 1)
        a *= min(endA, endB) * smoothstep(2, 12, lengthOnScreen) * fog
        if crossFolder { a *= 0.55 }
        if focus == .elsewhere { a *= 0.15 }
        return min(a, 1)
    }
}

/// Which bodies carry a label: the nearest few on screen, always the
/// selection, and steady - a shown label keeps its place unless a newcomer
/// is clearly nearer, so labels do not flicker as the camera drifts.
nonisolated struct GraphPerfLabelChooser: Sendable {
    var budget: Int
    /// A shown label counts as this much nearer than it is.
    var hold: Float = 0.95
    private(set) var shown: [Int] = []

    init(budget: Int) { self.budget = budget }

    /// From (body, depth) candidates on screen, the labels to show, nearest
    /// first, with the selection always among them. One pass, k kept: O(n k).
    mutating func choose(_ candidates: [(index: Int, depth: Float)], selection: Int? = nil) -> [Int] {
        let room = max(budget - (selection == nil ? 0 : 1), 0)
        let wasShown = Set(shown)
        var best: [(Float, Int)] = []
        best.reserveCapacity(room + 1)
        for c in candidates where c.index != selection {
            let key = (wasShown.contains(c.index) ? c.depth * hold : c.depth, c.index)
            if best.count == room, let last = best.last, !(key < last) { continue }
            let at = best.firstIndex { key < $0 } ?? best.count
            best.insert(key, at: at)
            if best.count > room { best.removeLast() }
        }
        shown = (selection.map { [$0] } ?? []) + best.map { $0.1 }
        return shown
    }
}

/// What the speed readout shows: the map's size, what this frame drew,
/// and how fast frames come.
nonisolated struct GraphPerfStats: Sendable, Equatable {
    var notes: Int = 0
    var links: Int = 0
    /// Drawn one by one, as glows, and as lines (links and bundles).
    var drawnBodies: Int = 0
    var drawnGlows: Int = 0
    var drawnLines: Int = 0
    /// Frames a second over the last half second, and the slowest twentieth's CPU time.
    var fps: Double = 0
    var cpuP95: Double = 0
    /// The slowest twentieth's GPU time (0 until the GPU reports).
    var gpuP95: Double = 0
    /// The screen's fastest rate (0: not known).
    var screenFPS: Int = 0
    /// The frame budget's split size (points; 0 where there is none).
    var detail: Float = 0
    /// The million map's stages, medians over the last readout (seconds; 0
    /// where not measured): the CPU's own time, the GPU's near stage (notes,
    /// links) and far stage (bundles, glows).
    var cpuMedian: Double = 0
    /// The planning (on its own thread, a frame ahead).
    var planMedian: Double = 0
    var nearMedian: Double = 0
    var farMedian: Double = 0
    /// The share of the map's screen at or above 250 of 255 (-1: not measured).
    var saturated: Double = -1
    /// The layout is still settling.
    var settling: Bool = false

    /// "100,000 notes · 230,080 links"
    var line: String {
        Self.grouped(notes) + (notes == 1 ? " note" : " notes") + " \u{00B7} " + Self.grouped(links)
            + (links == 1 ? " link" : " links")
    }

    /// The slower of the CPU's and the GPU's time for a frame (slowest twentieth).
    var frameTime: Double { max(cpuP95, gpuP95) }

    /// "118 of 120 fps · 3.4 ms a frame of 8.3": the rate, the screen's
    /// fastest, and what a frame costs against the time one refresh allows.
    var pace: String {
        let rate = String(Int(fps.rounded()))
        guard screenFPS > 0 else { return rate + " fps \u{00B7} " + Self.millis(frameTime) + " ms a frame" }
        return rate + " of " + String(screenFPS) + " fps \u{00B7} " + Self.millis(frameTime) + " ms a frame of "
            + Self.millis(1 / Double(screenFPS))
    }

    /// Milliseconds to one decimal, a dot in every locale.
    static func millis(_ seconds: Double) -> String {
        let tenths = Int((max(seconds, 0) * 10_000).rounded())
        return String(tenths / 10) + "." + String(tenths % 10)
    }

    /// "98,412 drawn · 236 glows · 231,940 lines", and on the million map
    /// " · opens at 26 pt" (the frame budget's split)
    var drawn: String {
        Self.grouped(drawnBodies) + " drawn \u{00B7} " + Self.grouped(drawnGlows)
            + (drawnGlows == 1 ? " glow" : " glows") + " \u{00B7} " + Self.grouped(drawnLines) + " lines"
            + (detail > 0 ? " \u{00B7} opens at " + String(Int(detail.rounded())) + " pt" : "")
    }

    /// "cpu 0.9 · plan 0.3 · near 3.1 · far 1.2 ms · 0.4% at 250+", where the
    /// stages are measured (the million map); empty elsewhere. The plan runs
    /// on its own thread, so it is not part of the CPU's; the last part is
    /// the share of the screen saturated, when measured.
    var stages: String {
        guard cpuMedian > 0 || nearMedian > 0 || farMedian > 0 else { return "" }
        let shown = "cpu " + Self.millis(cpuMedian) + " \u{00B7} plan " + Self.millis(planMedian) + " \u{00B7} near "
            + Self.millis(nearMedian)
            + " \u{00B7} far " + Self.millis(farMedian) + " ms"
        guard saturated >= 0 else { return shown }
        return shown + " \u{00B7} " + Self.percent(saturated) + " at 250+"
    }

    /// A share as a percentage to one decimal, a dot in every locale.
    static func percent(_ share: Double) -> String {
        let tenths = Int((max(share, 0) * 1_000).rounded())
        return String(tenths / 10) + "." + String(tenths % 10) + "%"
    }

    /// The middle value (0 for none).
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// Thousands with commas, the same in every locale (the readout is a meter).
    static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (k, ch) in digits.enumerated() {
            if k > 0 && (digits.count - k) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + out
    }
}

/// Frame times (seconds) summed up as the speed readout shows them.
nonisolated struct GraphPerfFrameStats: Sendable, Equatable {
    let count: Int
    let p50: Double
    let p95: Double
    /// Frames that missed at least one refresh: over 1.5 times the target.
    let hitches: Int

    init(_ frames: [Double], target: Double) {
        let sorted = frames.sorted()
        count = sorted.count
        p50 = Self.percentile(sorted, 0.5)
        p95 = Self.percentile(sorted, 0.95)
        hitches = frames.filter { $0 > target * 1.5 }.count
    }

    /// Nearest rank: the smallest value with at least `q` of the frames at or under it.
    static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((q * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}
