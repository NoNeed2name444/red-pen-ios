import Foundation

// MARK: - Graphics: High quality or Smooth
//
// The owner's "Graphics" setting (Settings > Look and feel), separate from
// SpaceQuality: SpaceQuality says how much may MOVE (Reduce Motion, Low
// Power Mode, a hot device), this says how much each moving thing may COST.
//
//   Automatic      Smooth on an older or low-memory phone, on a hot device
//                  and in Low Power Mode; High quality otherwise (default)
//   High quality   everything: 120 frames a second on ProMotion, full star
//                  field, twinkle, drifting nebula, detailed shaders
//   Smooth         the cheaper version of every piece in every look (the
//                  space backdrop, the 3D map, and the looks still to come):
//                  fewer stars, no twinkle, a still nebula, the shaders'
//                  simple path (no noise loops), fewer samples along each
//                  link, 60 frames a second, lighter anti-aliasing, fewer
//                  sparks, no soft haze round small bodies
//
// Pure Foundation, so the choice and the budgets are tested on Linux
// (Tests/GraphicsTests.swift). The iOS side - reading the device, the
// setting and publishing the result - is in SpaceQuality.swift.

/// What the owner picked in Settings.
nonisolated enum GraphicsChoice: String, CaseIterable, Sendable {
    case automatic
    case high
    case smooth

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .high: return "High quality"
        case .smooth: return "Smooth"
        }
    }

    /// An unknown or missing stored value is Automatic.
    static func stored(_ raw: String?) -> GraphicsChoice {
        guard let raw, let choice = GraphicsChoice(rawValue: raw) else { return .automatic }
        return choice
    }
}

/// The two budgets every look is drawn to.
nonisolated enum GraphicsTier: Int, Comparable, Sendable {
    case smooth = 0
    case high = 1

    static func < (lhs: GraphicsTier, rhs: GraphicsTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What Automatic looks at, read from the device (SpaceQuality.swift).
nonisolated struct GraphicsDeviceState: Sendable, Equatable {
    /// ProcessInfo.physicalMemory, in bytes.
    var memory: UInt64
    var lowPower: Bool = false
    /// ProcessInfo.ThermalState.rawValue: 0 nominal, 1 fair, 2 serious,
    /// 3 critical.
    var thermal: Int = 0
    /// The screen's fastest rate (UIScreen.maximumFramesPerSecond).
    var screenFPS: Int = 60
}

nonisolated enum GraphicsResolver {
    /// Below this a phone counts as "under 6 GB". A 6 GB phone reports a
    /// little under 6e9 bytes of physicalMemory (the system keeps some), a
    /// 4 GB one about 3.9e9, so the line sits between the two rather than at
    /// 6e9 exactly, which would wrongly send every 6 GB phone to Smooth.
    static let memoryFloor: UInt64 = 5_000_000_000

    /// The tier in force.
    static func resolve(_ choice: GraphicsChoice, device: GraphicsDeviceState) -> GraphicsTier {
        switch choice {
        case .high: return .high
        case .smooth: return .smooth
        case .automatic:
            if device.lowPower { return .smooth }
            if device.thermal >= 2 { return .smooth }
            if device.memory > 0 && device.memory < memoryFloor { return .smooth }
            return .high
        }
    }
}

/// How much each look may spend, per tier. One value read everywhere
/// (GraphQuality.current on the render thread, the environment in SwiftUI),
/// so a new look gets both budgets by reading it.
nonisolated struct GraphicsBudget: Sendable, Equatable {
    let tier: GraphicsTier
    /// Points along each link's curve (the ribbon has one more). At 40 the
    /// sampled strip strays from the true curve by 5% of the Universe's
    /// beam half-width at its tightest curl into a black hole; at 20 by
    /// 20% - both too little to see (the old six segments strayed by twice
    /// the half-width, the kinks the owner saw).
    let linkSamples: Int
    /// The most frames a second the 3D map and the pop-out's tilt run at.
    let maxFPS: Int
    /// Multisampling: 4 or 2.
    let msaa: Int
    /// The style shaders' rpDetail: 1 draws their noise loops, 0 their
    /// single-pass path.
    let shaderDetail: Float
    /// How many sparks a moving body throws, as a share of the full number.
    let particleScale: Float
    /// Above this many bodies, a small body's halo goes while it is tiny on
    /// screen.
    let crowdedAbove: Int
    /// The backdrop: twinkling stars, a drifting nebula, and every Nth
    /// faint star (1: all of them).
    let twinkle: Bool
    let nebulaDrifts: Bool
    let starStride: Int
    /// Soft glow and haze layers (the near stars' halos, the bright stars'
    /// glow, the neuron look's gel halo, the circuit look's trace bloom).
    let haze: Bool

    static let high = GraphicsBudget(tier: .high, linkSamples: 40, maxFPS: 120, msaa: 4, shaderDetail: 1,
                                     particleScale: 1, crowdedAbove: 150, twinkle: true, nebulaDrifts: true,
                                     starStride: 1, haze: true)
    static let smooth = GraphicsBudget(tier: .smooth, linkSamples: 20, maxFPS: 60, msaa: 2, shaderDetail: 0,
                                       particleScale: 0.4, crowdedAbove: 60, twinkle: false,
                                       nebulaDrifts: false, starStride: 2, haze: false)

    static func of(_ tier: GraphicsTier) -> GraphicsBudget {
        tier == .high ? high : smooth
    }

    /// The frame rate to ask for on a screen that can do `screenFPS`.
    func frameRate(screen screenFPS: Int) -> Int {
        let top: Int = max(screenFPS, 30)
        return min(maxFPS, top)
    }
}

// MARK: - Even frame steps

/// Turns the render loop's wobbly call times into even steps.
///
/// SceneKit calls its delegate when the update runs, not when the frame
/// will be seen, so each call is a millisecond or two early or late, and the
/// raw step between two calls wobbles by twice that - one long, the next
/// short. Moving the orbits by those raw steps makes them shimmer back and
/// forth against a steady display: a stutter, worst at 120 frames a second.
///
/// The screen only ever shows frames on a 1/120 s grid (every rate the app
/// runs at - 120, 60, 40, 30 - is a whole number of those ticks), so this
/// keeps its own frame clock on that grid: each call moves it on by the
/// whole number of ticks nearest to where the call says it should be (and
/// a twentieth of the call's wobble, so it settles on the calls' middle).
/// The step is then 1, 2, 3... ticks to within a small fraction of a
/// millisecond, and the clock never strays more than half a tick from real
/// time, so nothing drifts. A call far off
/// the grid (a stall, or the first frame) sets the clock to the call's own
/// time, and that step is capped at 0.05 s.
nonisolated struct GraphFramePacer: Sendable {
    static let tick: Double = 1.0 / 120.0
    static let longest: Double = 0.05
    /// The frame clock: the time of the frame just stepped, on the grid.
    private(set) var stamp: Double = 0
    private var started: Bool = false

    init() {}

    /// The step to move everything on by for a frame whose update runs at
    /// `time` (seconds, any origin).
    mutating func step(at time: Double) -> Double {
        let tick: Double = Self.tick
        guard time.isFinite else { return tick }
        guard started else {
            started = true
            stamp = time
            return tick
        }
        let ahead: Double = time - stamp
        let ticks: Double = (ahead / tick).rounded()
        // off the grid by a whole frame or more: a stall, a pause, or the
        // clock going backwards - start again from here
        if ticks < 1 || ticks > 6 {
            stamp = time
            if ahead <= 0 { return tick }
            return min(ahead, Self.longest)
        }
        // a twentieth of the way towards the call's own time as well, so the
        // clock settles on the middle of the calls' wobble rather than on
        // wherever the first call happened to fall
        let onGrid: Double = ticks * tick
        let off: Double = ahead - onGrid
        let step: Double = onGrid + off * 0.05
        stamp += step
        return step
    }
}
