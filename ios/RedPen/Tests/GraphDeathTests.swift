// How bodies leave the Ideas map (GraphDeath), and the pure pieces that
// keep the map's links steady and its framing centred:
//
// - D: each kind of body gets its own death (tides, stripping, nebula,
//   supernova, evaporation, spin-down, break-up, apoptosis, short circuit);
//   durations of one to two and a half seconds; phases in order and inside
//   the death; every body gone (or invisible) by the end and whole at the
//   start; links drawn back before the body goes; Reduce Motion a quick
//   fade; the budget caps full effects and particles (Smooth fewer).
// - R: the link buffers' ring (GraphBufferRing) never hands out a set the
//   GPU may still be reading, grows when all are in flight, and the link
//   ends follow a body's live size (GraphLinkEnds).
// - F: the whole-map framing aims at the middle of the map's box
//   (GraphMapBounds), whatever the plan's offset.
// - S: the Neurons' synapse (GraphLinkArbor): the membrane steps and the v
//   coding round-trip; one cup per link, hugging the membrane across the
//   cleft, inside its ribbon, bigger than the old cups and bounded round
//   the cell; the impulse landing on it at the arrival time.
//
// Compiled with GraphDeath.swift, GraphFrameSync.swift and
// GraphSynapse.swift (Foundation only).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: D the deaths

let expected: [(GraphDeathKind, GraphDeathEffect)] = [
    (.rocky, .tidalDisruption), (.moon, .tidalDisruption), (.gasGiant, .atmosphereStripped),
    (.smallStar, .planetaryNebula), (.bigStar, .supernova), (.blackHole, .evaporation),
    (.pulsar, .spinDown), (.comet, .cometBreakup), (.cell, .apoptosis), (.part, .shortCircuit),
    (.wiring, .fade), (.plain, .fade)
]
var effectBad: [String] = []
for (kind, effect) in expected where GraphDeath.plan(kind, smooth: false).effect != effect {
    effectBad.append("\(kind)")
}
check("D1 each kind of body dies its own way", effectBad.isEmpty, "\(effectBad)")

check("D1 Universe roles map to kinds",
      GraphDeath.kind(universeRole: "galaxy", count: 9) == .blackHole
      && GraphDeath.kind(universeRole: "star", count: 2) == .smallStar
      && GraphDeath.kind(universeRole: "star", count: 30) == .bigStar
      && GraphDeath.kind(universeRole: "home", count: 0) == .bigStar
      && GraphDeath.kind(universeRole: "gasGiant", count: 0) == .gasGiant
      && GraphDeath.kind(universeRole: "moon", count: 0) == .moon
      && GraphDeath.kind(universeRole: "pulsar", count: 0) == .pulsar
      && GraphDeath.kind(universeRole: "oort", count: 0) == .comet
      && GraphDeath.kind(universeRole: "rocky", count: 0) == .rocky)
check("D1 single looks' styles map to kinds", GraphDeath.kind(style: "sun") == .smallStar
      && GraphDeath.kind(style: "blackHole") == .blackHole && GraphDeath.kind(style: "comet") == .comet
      && GraphDeath.kind(style: "unknown") == .plain)

var curveBad: [String] = []
for kind in GraphDeathKind.allCases {
    for smooth in [false, true] {
        let plan: GraphDeathPlan = GraphDeath.plan(kind, smooth: smooth)
        let name: String = "\(kind)\(smooth ? "/smooth" : "")"
        if plan.effect != .fade && (plan.duration < 1 || plan.duration > 2.5) { curveBad.append("\(name) lasts \(plan.duration)") }
        for p in plan.phases where p.start < 0 || p.end > plan.duration + 1e-9 || p.end <= p.start {
            curveBad.append("\(name) phase \(p.name) \(p.start)-\(p.end)")
        }
        let start: SIMD2<Float> = GraphDeath.scale(plan, at: 0)
        if abs(start.y - 1) > 0.01 || abs(start.x - 1) > 0.01 || GraphDeath.opacity(plan, at: 0) < 0.99 {
            curveBad.append("\(name) not whole at the start")
        }
        let end: SIMD2<Float> = GraphDeath.scale(plan, at: plan.duration)
        let gone: Bool = end.y < 0.25 || GraphDeath.opacity(plan, at: plan.duration) < 0.01
        if !gone { curveBad.append("\(name) still there at the end: \(end) \(GraphDeath.opacity(plan, at: plan.duration))") }
        if GraphDeath.linkReach(plan, at: 0) < 0.99 || GraphDeath.linkReach(plan, at: plan.linksGone) > 0.001 {
            curveBad.append("\(name) links")
        }
        if plan.linksGone > plan.duration + 1e-9 { curveBad.append("\(name) links outlast the body") }
        var t: Double = 0
        var last: Float = 2
        while t <= plan.duration {
            let reach: Float = GraphDeath.linkReach(plan, at: t)
            if reach > last + 1e-6 { curveBad.append("\(name) links grow back at \(t)") }
            last = reach
            let s: SIMD2<Float> = GraphDeath.scale(plan, at: t)
            let o: Float = GraphDeath.opacity(plan, at: t)
            if !(s.x.isFinite && s.y.isFinite) || s.x < 0 || s.y < 0 || o < 0 || o > 1 {
                curveBad.append("\(name) at \(t): \(s) \(o)")
                break
            }
            t += 0.02
        }
    }
}
check("D2 1 to 2.5 s, phases inside, whole at the start, gone at the end, links drawn back first", curveBad.isEmpty,
      "\(curveBad.prefix(5))")

let hole: GraphDeathPlan = GraphDeath.plan(.blackHole, smooth: false)
let early: Float = 1 - GraphDeath.scale(hole, at: 0.4).y
let late: Float = GraphDeath.scale(hole, at: 1.0).y - GraphDeath.scale(hole, at: 1.6).y
check("D3 a black hole evaporates ever faster (Hawking)", late > early * 0.9, "\(early) \(late)")
let star: GraphDeathPlan = GraphDeath.plan(.smallStar, smooth: false)
check("D3 a small star swells to a giant first", GraphDeath.scale(star, at: 0.6).y > 1.3)
let nova: GraphDeathPlan = GraphDeath.plan(.bigStar, smooth: false)
check("D3 a supernova's star is gone at the flash", GraphDeath.scale(nova, at: 0.5).y == 0)
let rock: GraphDeathPlan = GraphDeath.plan(.rocky, smooth: false)
let pulled: SIMD2<Float> = GraphDeath.scale(rock, at: 0.45)
check("D3 tides stretch a planet along the pull before it breaks", pulled.x > pulled.y * 1.5, "\(pulled)")
let pulsar: GraphDeathPlan = GraphDeath.plan(.pulsar, smooth: false)
check("D3 a pulsar spins down", GraphDeath.spin(pulsar, at: 0) == 1 && GraphDeath.spin(pulsar, at: 0.8) < 0.5
      && GraphDeath.spin(pulsar, at: 1.6) == 0)
let cell: GraphDeathPlan = GraphDeath.plan(.cell, smooth: false)
let apoptosis: [String] = cell.phases.map(\.name)
check("D3 apoptosis: shrink, bleb, condense, fragment, apoptotic bodies, in that order",
      apoptosis == ["shrink", "bleb", "condense", "fragment", "bodies"]
      && zip(cell.phases, cell.phases.dropFirst()).allSatisfy { $0.start <= $1.start })
check("D3 a cell rounds up smaller before it breaks", GraphDeath.scale(cell, at: 0.6).y < 0.8
      && GraphDeath.scale(cell, at: 0.6).y > 0.7)
let short: GraphDeathPlan = GraphDeath.plan(.part, smooth: false)
check("D3 a short circuit: spark first, smoke last; traces flash then go dark",
      short.phases.first?.name == "spark" && short.phases.last?.name == "smoke"
      && GraphDeath.traceFlash(short, at: 0.08) > 0.9 && GraphDeath.traceFlash(short, at: 1.0) == 0
      && GraphDeath.opacity(short, at: 0.9) < 0.6)
check("D3 only a short circuit flashes its traces", GraphDeath.traceFlash(cell, at: 0.08) == 0)

// the budget
var many: [GraphDeathInput] = []
for k in 0..<40 {
    let kind: GraphDeathKind = k % 5 == 0 ? .smallStar : .rocky
    many.append(GraphDeathInput(kind: kind, radius: Float(k % 7) * 0.05 + 0.05, count: k))
}
many.append(GraphDeathInput(kind: .wiring, radius: 9, count: 0))
let high: [GraphDeathPlan] = GraphDeath.plans(many, still: false, smooth: false)
let smoothPlans: [GraphDeathPlan] = GraphDeath.plans(many, still: false, smooth: true)
let fullHigh: Int = high.filter { $0.effect != .fade }.count
let fullSmooth: Int = smoothPlans.filter { $0.effect != .fade }.count
check("D4 a folder of 40 deleted: at most 6 full effects (3 at Smooth)", fullHigh == 6 && fullSmooth == 3,
      "\(fullHigh) \(fullSmooth)")
let biggest: Float = many.filter { $0.kind != .wiring }.map(\.radius).max() ?? 0
let chosen: [Float] = many.indices.filter { high[$0].effect != .fade }.map { many[$0].radius }
check("D4 the biggest get them; wiring never does", chosen.allSatisfy { $0 >= biggest - 0.1 }
      && high.last?.effect == .fade)
let sparksHigh: Int = high.map(\.particles).reduce(0, +)
let sparksSmooth: Int = smoothPlans.map(\.particles).reduce(0, +)
check("D4 particles bounded, fewer at Smooth", sparksHigh <= 6 * 110 && sparksSmooth < sparksHigh,
      "\(sparksHigh) \(sparksSmooth)")
let still: [GraphDeathPlan] = GraphDeath.plans(many, still: true, smooth: false)
check("D5 Reduce Motion or a still space: a quick fade, no particles",
      still.allSatisfy { $0.effect == .fade && $0.duration <= 0.35 && $0.particles == 0 })
check("D5 the same bodies, the same plans", GraphDeath.plans(many, still: false, smooth: false) == high)

// MARK: R the link buffers

// a simulated GPU three frames behind: no set is ever written while it may
// be read, and the ring stays small
var used: [UInt64] = [0, 0, 0]
var inFlight: [UInt64: Int] = [:]
var overwritten: Int = 0
var most: Int = 3
for frame in UInt64(1)...UInt64(500) {
    let lag: UInt64 = frame % 7 == 0 ? 4 : 2
    let finished: UInt64 = frame > lag ? frame - lag : 0
    var k: Int
    if let pick = GraphBufferRing.pick(used: used, finished: finished, now: frame) {
        k = pick
    } else if used.count < GraphBufferRing.most {
        used.append(0)
        k = used.count - 1
    } else {
        k = GraphBufferRing.fallback(used: used, now: frame)
    }
    if used[k] > finished { overwritten += 1 }
    used[k] = frame
    inFlight[frame] = k
    most = max(most, used.count)
}
check("R1 a set still being drawn is never written again", overwritten == 0, "\(overwritten)")
check("R1 the ring grows only as far as the GPU lags", most <= 6, "\(most)")
check("R2 nothing free: none is picked", GraphBufferRing.pick(used: [5, 6, 7], finished: 4, now: 8) == nil)
check("R2 the least recently used free set is picked", GraphBufferRing.pick(used: [5, 2, 7], finished: 6, now: 8) == 1)
check("R2 never the set written this frame", GraphBufferRing.pick(used: [8, 0], finished: 8, now: 8) == 1)
var ends: [Float] = []
GraphLinkEnds.radii([0.2, 0.1, 0.3], scale: [1, 0.5, 1.3], into: &ends)
check("R3 link ends follow a body's live size", abs(ends[0] - 0.2) < 1e-6 && abs(ends[1] - 0.05) < 1e-6
      && abs(ends[2] - 0.39) < 1e-6, "\(ends)")
GraphLinkEnds.radii([0.2], scale: [0], into: &ends)
check("R3 ... never collapsing to the centre", ends.count == 1 && ends[0] > 0)

// MARK: F framing

let plan: [SIMD3<Float>] = [SIMD3<Float>(-2, -5.4, 0), SIMD3<Float>(1, 3.2, 0.5), SIMD3<Float>(0, 0, -0.5)]
let middle: SIMD3<Float> = GraphMapBounds.centre(plan)
check("F1 the framing aims at the middle of the map's box", abs(middle.y + 1.1) < 1e-5 && abs(middle.x + 0.5) < 1e-5
      && abs(middle.z) < 1e-5, "\(middle)")
let centred: [SIMD3<Float>] = GraphMapBounds.centred(plan)
let low: Float = centred.map(\.y).min() ?? 0
let top: Float = centred.map(\.y).max() ?? 0
check("F1 ... so it is framed evenly above and below", abs(low + top) < 1e-5)
check("F1 nothing: the origin", GraphMapBounds.centre([]) == SIMD3<Float>(0, 0, 0))

// MARK: S the synapse: one gel golf-tee cup per link

var levelBad: [String] = []
for q in 0..<GraphLinkArbor.levels {
    let r: Float = GraphLinkArbor.radius(level: q)
    if GraphLinkArbor.level(for: r) != q { levelBad.append("level \(q)") }
    for length in [Float(0.3), 2.7, 59.9] {
        for lit in [0, 1] {
            let band: Int = GraphLinkArbor.band(length: length, level: q, lit: lit)
            let (l, lv, li) = GraphLinkArbor.read(band: band)
            if lv != q || li != lit || abs(l - length) > 0.0626 || band >= 16_384 {
                levelBad.append("band \(length) \(q) \(lit) -> \(l) \(lv) \(li) \(band)")
            }
        }
    }
}
check("S1 membrane steps and the v coding round-trip, under 16,384", levelBad.isEmpty, "\(levelBad.prefix(3))")
var stepWorst: Float = 0
var r: Float = 0.06
while r < 0.44 {
    let stepped: Float = GraphLinkArbor.radius(level: GraphLinkArbor.level(for: r))
    stepWorst = max(stepWorst, abs(stepped / r - 1))
    r += 0.003
}
check("S1 a membrane's step is within 8% of it", stepWorst < 0.08, "\(stepWorst)")

let axon = GraphLinkArbor(membrane: 1.25, share: 0.3)
let tract = GraphLinkArbor(membrane: 1.25, share: 0.2)
var cupBad: [String] = []
for (arbor, h) in [(axon, Float(0.08)), (tract, Float(0.13))] {
    for q in 0..<GraphLinkArbor.levels {
        let rr: Float = GraphLinkArbor.radius(level: q)
        let m: GraphArborMeasures = arbor.measures(r: rr, h: h)
        // the cup hugs the membrane across the cleft, its back behind it
        if abs(m.front - (rr + m.cleft)) > 1e-6 || m.back <= m.front { cupBad.append("hug \(q)") }
        // bigger than yesterday's cups (1.1 fibre radii either side) wherever
        // the target is big enough to take it
        let old: Float = 1.1 * m.fibre
        if m.cup < old * 1.3 && GraphLinkArbor.widest * m.front - 0.75 * m.thick > old * 1.3 { cupBad.append("small cup \(q)") }
        // the cup and its rim inside the ribbon where it sits
        let wide: Float = arbor.halfWidth(dEnd: m.back, r: rr, h: h)
        if m.cup + 1.5 * m.thick > wide + 1e-5 { cupBad.append("cup outside the ribbon \(q)") }
        // the neck starts where the ribbon is at its full width
        if abs(arbor.halfWidth(dEnd: m.back + m.neck, r: rr, h: h) - m.wide) > 1e-5 { cupBad.append("ramp \(q)") }
        if abs(arbor.halfWidth(dEnd: m.start + 0.5, r: rr, h: h) - h) > 1e-6 { cupBad.append("base width \(q)") }
        // never reaching further round the cell than its share
        if arbor.reach(r: rr, h: h) > GraphLinkArbor.widest + 1e-5 { cupBad.append("reach \(q) \(arbor.reach(r: rr, h: h))") }
    }
}
check("S2 one cup per link: hugging the membrane across the cleft, inside its ribbon, bigger than the old cups",
      cupBad.isEmpty, "\(cupBad.prefix(4))")
// two links arriving from sides further apart than both cups' reach never
// touch: the cups are bounded round the cell (the widest two together)
var widestPair: Float = 0
for q in 0..<GraphLinkArbor.levels {
    let rq: Float = GraphLinkArbor.radius(level: q)
    let a: Float = axon.reach(r: rq, h: 0.08)
    let b: Float = tract.reach(r: rq, h: 0.13)
    widestPair = max(widestPair, max(a + b, max(a + a, b + b)))
}
check("S3 two cups on one cell never touch when their links arrive over 50 degrees apart", widestPair < 0.85,
      "\(widestPair)")
// the impulse lands on the cup's back at pos 1: NeuronImpulse's arrival
var landBad: Int = 0
for length in [Float(0.8), 1.7, 4.2] {
    for q in [0, 6, 12] {
        let m: GraphArborMeasures = axon.measures(r: GraphLinkArbor.radius(level: q), h: 0.08)
        if abs(GraphLinkArbor.landing(length: length, measures: m) + m.back - length) > 1e-6 { landBad += 1 }
    }
}
check("S4 the impulse lands on the cup at the arrival time (the dendrite glow in step)", landBad == 0)
let trim: Float = GraphLinkArbor.endTrim(membrane: 0.13)
check("S4 the ribbon runs to the target's centre, give or take the membrane's step", abs(trim) < 0.13 * 0.08)

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
