import Foundation

// MARK: - How a body leaves the map
//
// When a note or folder is deleted, its body does not simply vanish: it
// dies the way the thing it stands for dies, for a second or two, while
// its links draw back into it - and nothing waits for it (the new map is
// live underneath; the dying body can be neither picked nor dragged).
//
// Space, each kind of body as physics has it:
//   rocky planet, moon   torn apart by tides: stretched along the pull,
//                        shattered, its debris a ring that spreads and fades
//   gas giant            its atmosphere stripped away as a shell that swells
//                        and fades, its small core left to fade
//   small star           swells to a red giant, puffs off a planetary nebula
//                        (a ring spreading out) and leaves a white dwarf
//                        that fades
//   big star (a folder   collapses, a supernova flash, and an expanding
//   holding many, or     shock shell
//   the home star)
//   black hole           evaporates: shrinking ever faster as its Hawking
//                        glow grows hotter, ending in a bright pop
//   pulsar               spins down, its beams dimming
//   comet                breaks into fragments that drift apart and
//                        sublimate in a fading puff of gas
// Neurons, apoptosis: the cell shrinks and rounds up, its membrane blebs,
//   its nucleus condenses and breaks into beads, and it falls apart into
//   apoptotic bodies that fade as they are cleared away; its axons and
//   dendrites draw back.
// Circuit, a short circuit: a spark and arcs at the part, a hot orange
//   glow, a puff of smoke rising; the part chars dark and fades, and its
//   traces flash and go dark.
//
// This file is the plan: which effect for which body, how long, its
// phases, how many particles, and the curves the body follows - pure
// Foundation, tested on Linux (Tests/GraphDeathTests.swift). The effects
// themselves are GraphDeathScene's.
//
// Reduce Motion or a still space (SpaceQuality .still): a quick fade only.
// The Graphics budget: at Smooth fewer particles and simpler pieces; only
// the biggest few dying at once get their full effect (6 at High, 3 at
// Smooth) - the rest shrink and fade - so deleting a folder of hundreds
// never floods the frame.

/// What a body is, as far as its death goes.
nonisolated enum GraphDeathKind: Int, Sendable, CaseIterable {
    case rocky
    case moon
    case gasGiant
    case smallStar
    case bigStar
    case blackHole
    case pulsar
    case comet
    /// A Neurons cell.
    case cell
    /// A Circuit part (chip, capacitor, LED, pad).
    case part
    /// A theme's wiring (the Circuit's taps and connectors).
    case wiring
    /// Anything else (a single look's body with no better match).
    case plain
}

/// How it dies.
nonisolated enum GraphDeathEffect: String, Sendable, Equatable {
    case tidalDisruption
    case atmosphereStripped
    case planetaryNebula
    case supernova
    case evaporation
    case spinDown
    case cometBreakup
    case apoptosis
    case shortCircuit
    /// Shrink and fade (a body over the budget's count, wiring, plain).
    case fade
}

/// One stage of a death, in seconds from its start.
nonisolated struct GraphDeathPhase: Sendable, Equatable {
    let name: String
    let start: Double
    let end: Double
}

/// A body's death: its effect, how long it all takes (the effect's last
/// piece gone), its stages, how many particles its effects may throw in
/// all, and when its links have drawn back into it.
nonisolated struct GraphDeathPlan: Sendable, Equatable {
    let effect: GraphDeathEffect
    let duration: Double
    let phases: [GraphDeathPhase]
    let particles: Int
    let linksGone: Double

    func phase(_ name: String) -> GraphDeathPhase? {
        phases.first { $0.name == name }
    }

    /// How far through stage `name` it is at `t` (0 before, 1 after).
    func progress(_ name: String, at t: Double) -> Double {
        guard let p = phase(name) else { return 0 }
        let span: Double = max(p.end - p.start, 0.0001)
        return min(max((t - p.start) / span, 0), 1)
    }
}

/// One dying body, as the plan sees it: what it is, its size (radius, in
/// the space's units) and how much it held (a folder's notes).
nonisolated struct GraphDeathInput: Sendable, Equatable {
    let kind: GraphDeathKind
    let radius: Float
    let count: Int
}

nonisolated enum GraphDeath {
    /// At most this many full effects at once (High, Smooth).
    static func fullAllowed(smooth: Bool) -> Int {
        smooth ? 3 : 6
    }

    /// A folder at least this full is a big star (a supernova).
    static let bigStarCount: Int = 8

    /// Which kind a Universe role or a single look's style makes: by name,
    /// so the scene (which knows its roles and styles) and the tests agree.
    static func kind(universeRole role: String, count: Int) -> GraphDeathKind {
        switch role {
        case "galaxy": return .blackHole
        case "home": return .bigStar
        case "star": return count >= bigStarCount ? .bigStar : .smallStar
        case "gasGiant": return .gasGiant
        case "moon": return .moon
        case "pulsar": return .pulsar
        case "comet", "oort": return .comet
        default: return .rocky
        }
    }

    static func kind(style: String) -> GraphDeathKind {
        switch style {
        case "blackHole": return .blackHole
        case "sun": return .smallStar
        case "gasGiant": return .gasGiant
        case "pulsar": return .pulsar
        case "comet": return .comet
        case "rocky": return .rocky
        default: return .plain
        }
    }

    /// Every dying body's plan: full effects for the biggest few (by
    /// radius, then what they held, then their order), a shrink-and-fade
    /// for the rest; a quick fade for all when the space holds still.
    static func plans(_ dying: [GraphDeathInput], still: Bool, smooth: Bool) -> [GraphDeathPlan] {
        let order: [Int] = dying.indices.sorted { a, b in
            if dying[a].radius != dying[b].radius { return dying[a].radius > dying[b].radius }
            if dying[a].count != dying[b].count { return dying[a].count > dying[b].count }
            return a < b
        }
        var full = Set<Int>()
        let allowed: Int = fullAllowed(smooth: smooth)
        for i in order where full.count < allowed && dying[i].kind != .wiring && dying[i].kind != .plain {
            full.insert(i)
        }
        var out: [GraphDeathPlan] = []
        for (i, d) in dying.enumerated() {
            if still {
                out.append(quickFade())
            } else if full.contains(i) {
                out.append(plan(d.kind, smooth: smooth))
            } else {
                out.append(fade(d.kind == .wiring ? 0.5 : 0.8))
            }
        }
        return out
    }

    /// Reduce Motion, a still space: gone in a third of a second.
    static func quickFade() -> GraphDeathPlan {
        GraphDeathPlan(effect: .fade, duration: 0.3, phases: [GraphDeathPhase(name: "fade", start: 0, end: 0.3)],
                       particles: 0, linksGone: 0.3)
    }

    static func fade(_ seconds: Double) -> GraphDeathPlan {
        GraphDeathPlan(effect: .fade, duration: seconds,
                       phases: [GraphDeathPhase(name: "fade", start: 0, end: seconds)],
                       particles: 0, linksGone: seconds * 0.8)
    }

    /// One body's full effect.
    static func plan(_ kind: GraphDeathKind, smooth: Bool) -> GraphDeathPlan {
        let share: Double = smooth ? 0.4 : 1
        func sparks(_ n: Int) -> Int { max(Int(Double(n) * share), 6) }
        func p(_ name: String, _ a: Double, _ b: Double) -> GraphDeathPhase {
            GraphDeathPhase(name: name, start: a, end: b)
        }
        switch kind {
        case .rocky, .moon:
            return GraphDeathPlan(effect: .tidalDisruption, duration: 1.9,
                                  phases: [p("stretch", 0, 0.6), p("shatter", 0.5, 0.85), p("ring", 0.5, 1.9)],
                                  particles: sparks(70), linksGone: 0.7)
        case .gasGiant:
            return GraphDeathPlan(effect: .atmosphereStripped, duration: 2.1,
                                  phases: [p("strip", 0, 1.4), p("core", 0.9, 2.1)],
                                  particles: sparks(80), linksGone: 0.9)
        case .smallStar:
            return GraphDeathPlan(effect: .planetaryNebula, duration: 2.4,
                                  phases: [p("swell", 0, 0.7), p("puff", 0.6, 2.4), p("dwarf", 0.7, 2.4)],
                                  particles: sparks(60), linksGone: 1.0)
        case .bigStar:
            return GraphDeathPlan(effect: .supernova, duration: 2.3,
                                  phases: [p("collapse", 0, 0.25), p("flash", 0.25, 0.8), p("shock", 0.3, 2.3)],
                                  particles: sparks(110), linksGone: 0.5)
        case .blackHole:
            return GraphDeathPlan(effect: .evaporation, duration: 2.0,
                                  phases: [p("shrink", 0, 1.7), p("pop", 1.7, 2.0)],
                                  particles: sparks(40), linksGone: 1.2)
        case .pulsar:
            return GraphDeathPlan(effect: .spinDown, duration: 1.9,
                                  phases: [p("spin", 0, 1.6), p("fade", 1.1, 1.9)],
                                  particles: 0, linksGone: 1.2)
        case .comet:
            return GraphDeathPlan(effect: .cometBreakup, duration: 1.9,
                                  phases: [p("crack", 0, 0.4), p("fragments", 0.3, 1.9), p("gas", 0.2, 1.5)],
                                  particles: sparks(50), linksGone: 0.8)
        case .cell:
            return GraphDeathPlan(effect: .apoptosis, duration: 2.3,
                                  phases: [p("shrink", 0, 0.6), p("bleb", 0.3, 1.2), p("condense", 0.5, 1.1),
                                           p("fragment", 1.0, 1.6), p("bodies", 1.2, 2.3)],
                                  particles: sparks(40), linksGone: 1.0)
        case .part:
            return GraphDeathPlan(effect: .shortCircuit, duration: 1.7,
                                  phases: [p("spark", 0, 0.3), p("glow", 0.1, 0.9), p("char", 0.2, 1.1),
                                           p("smoke", 0.3, 1.7)],
                                  particles: sparks(60), linksGone: 0.9)
        case .wiring:
            return fade(0.5)
        case .plain:
            return fade(0.8)
        }
    }

    // MARK: the body's own curves

    static func smooth(_ x: Double) -> Double {
        let t: Double = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The body's size at `t`, as (along its tidal axis, across) times its
    /// size when it began to die. Every effect ends at 0 or invisible.
    static func scale(_ plan: GraphDeathPlan, at t: Double) -> SIMD2<Float> {
        let s: Double
        var along: Double = 1
        switch plan.effect {
        case .tidalDisruption:
            let stretch: Double = smooth(plan.progress("stretch", at: t))
            let gone: Double = smooth(plan.progress("shatter", at: t))
            along = 1 + 0.8 * stretch
            s = (1 - 0.35 * stretch) * (1 - gone)
        case .atmosphereStripped:
            let strip: Double = smooth(plan.progress("strip", at: t))
            let core: Double = smooth(plan.progress("core", at: t))
            s = (1 - 0.55 * strip) * (1 - core)
        case .planetaryNebula:
            let swell: Double = smooth(plan.progress("swell", at: t))
            let collapse: Double = smooth(plan.progress("dwarf", at: t) * 3)
            let giant: Double = 1 + 0.5 * swell
            s = giant * (1 - collapse) + 0.2 * collapse
        case .supernova:
            let crush: Double = smooth(plan.progress("collapse", at: t))
            s = t < (plan.phase("flash")?.start ?? 0.25) + 0.05 ? 1 - 0.2 * crush : 0
        case .evaporation:
            // Hawking: the mass goes as (1 - t/T)^(1/3), faster at the end
            let x: Double = plan.progress("shrink", at: t)
            s = pow(max(1 - x, 0), 1.0 / 3.0)
        case .spinDown:
            s = 1 - smooth(plan.progress("fade", at: t))
        case .cometBreakup:
            s = 1 - smooth(plan.progress("fragments", at: t) * 2)
        case .apoptosis:
            let shrink: Double = smooth(plan.progress("shrink", at: t))
            let apart: Double = smooth(plan.progress("fragment", at: t))
            s = (1 - 0.25 * shrink) * (1 - apart)
        case .shortCircuit:
            s = 1 - 0.1 * smooth(plan.progress("char", at: t))
        case .fade:
            s = 1 - 0.4 * smooth(plan.progress("fade", at: t))
        }
        return SIMD2<Float>(Float(s * along), Float(s))
    }

    /// The body's opacity at `t` (0 once it is gone).
    static func opacity(_ plan: GraphDeathPlan, at t: Double) -> Float {
        let o: Double
        switch plan.effect {
        case .planetaryNebula:
            o = 1 - smooth((t - 1.6) / max(plan.duration - 1.6, 0.01))
        case .spinDown:
            o = 1 - 0.7 * smooth(plan.progress("spin", at: t))
        case .shortCircuit:
            let char: Double = smooth(plan.progress("char", at: t))
            let fade: Double = smooth(plan.progress("smoke", at: t))
            o = (1 - 0.55 * char) * (1 - fade)
        case .fade:
            o = 1 - smooth(plan.progress("fade", at: t))
        default:
            o = t >= plan.duration ? 0 : 1
        }
        return Float(min(max(o, 0), 1))
    }

    /// How far a dying body's links still reach out of it at `t` (1 at
    /// the start, 0 once drawn back in).
    static func linkReach(_ plan: GraphDeathPlan, at t: Double) -> Float {
        let x: Double = min(max(t / max(plan.linksGone, 0.01), 0), 1)
        return Float(1 - smooth(x))
    }

    /// A pulsar's spin rate at `t`, as a share of its rate when it began
    /// to die: spinning down.
    static func spin(_ plan: GraphDeathPlan, at t: Double) -> Float {
        let x: Double = plan.progress("spin", at: t)
        return Float(max(1 - x, 0) * max(1 - x, 0))
    }

    /// A circuit's traces flash as the part shorts, then go dark: 0 to 1.
    static func traceFlash(_ plan: GraphDeathPlan, at t: Double) -> Float {
        guard plan.effect == .shortCircuit else { return 0 }
        let rise: Double = smooth(t / 0.08)
        let fall: Double = 1 - smooth((t - 0.1) / 0.5)
        return Float(max(min(rise, fall), 0))
    }
}
