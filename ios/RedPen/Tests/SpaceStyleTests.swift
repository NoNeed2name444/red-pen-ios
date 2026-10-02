// The Space theme's styles follow a little real physics (SpaceOptics), the
// same in their shaders (GraphSpaceShaders) and their animator
// (GraphStyleAnimator). None of it needs a screen, so it is checked here:
//
// - a black hole's disk: Kepler's angular speed (r^-1.5), the gas fastest
//   at the inner edge, beaming brightest where it comes towards the eye;
// - light: the terminator faces the light, the nearer sun wins, the
//   reddened band sits on the terminator;
// - a gas giant: the planet shadows its ring on the far side from the sun,
//   and the ring's shadow falls on the far hemisphere; the Cassini
//   division is dark;
// - a pulsar: its beams sweep once a period at their tilt from the axis,
//   the links beat twice a turn (and the shaders say so), its nebula lies
//   square to the axis as seen;
// - a comet: the ion tail points exactly away from the light, the dust
//   tail lags behind the motion, more the faster, never past square;
// - a sun's corona carries its seed and motion in one number and gives
//   them back;
// - each style's sparks: a black hole's plume thrown back, longest and
//   densest; a sun's plasma warm; a comet's dust icy.
//
// Compiled with GraphShaderKit.swift, GraphSpaceShaders.swift and
// GraphSpaceOptics.swift (Foundation only).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func close(_ a: Float, _ b: Float, _ tolerance: Float = 1e-4) -> Bool {
    abs(a - b) <= tolerance
}

func unit(_ v: SIMD3<Float>) -> SIMD3<Float> {
    SpaceOptics.unit(v, or: SIMD3<Float>(0, 1, 0))
}

let dot = SpaceOptics.dot
let x = SIMD3<Float>(1, 0, 0)
let y = SIMD3<Float>(0, 1, 0)
let z = SIMD3<Float>(0, 0, 1)

// MARK: P1 the black hole's disk

let inner: Float = SpaceOptics.diskInner
check("P1 the inner edge turns at the full rate", close(SpaceOptics.keplerRate(radius: inner), 1))
check("P1 twice as far out turns 2^-1.5 as fast (Kepler)",
      close(SpaceOptics.keplerRate(radius: inner * 2), pow(2, -1.5), 1e-5))
var slowing: Bool = true
var last: Float = 2
for k in 0...20 {
    let r: Float = inner + Float(k) * (1 - inner) / 20
    let rate: Float = SpaceOptics.keplerRate(radius: r)
    if rate > last { slowing = false }
    last = rate
}
check("P1 every lane further out turns slower", slowing)
check("P1 inside the inner edge holds at the edge's rate", close(SpaceOptics.keplerRate(radius: 0.1), 1))
check("P1 the gas is fastest at the inner edge, half light's speed", close(SpaceOptics.diskSpeed(radius: inner), 0.5)
      && SpaceOptics.diskSpeed(radius: 1) < 0.5)
check("P1 its speed falls as 1/sqrt(r)", close(SpaceOptics.diskSpeed(radius: inner * 4), 0.25, 1e-5))
let toward: Float = SpaceOptics.beaming(speed: 0.4, towardEye: 1)
let away: Float = SpaceOptics.beaming(speed: 0.4, towardEye: -1)
let across: Float = SpaceOptics.beaming(speed: 0.4, towardEye: 0)
check("P1 the side coming towards the eye is brightest (beaming)", toward > across && across > away,
      "\(toward) \(across) \(away)")
check("P1 square to the eye, no beaming", close(across, 1))
check("P1 beaming held to 0.3...3.5", SpaceOptics.beaming(speed: 0.5, towardEye: 1) == 3.5
      && SpaceOptics.beaming(speed: 0.5, towardEye: -1) == 0.3)

// MARK: P2 light and the terminator

let sun = SIMD4<Float>(10, 0, 0, 1)
check("P2 one sun: the light comes from it", dot(SpaceOptics.light(at: .zero, suns: [sun], key: y), x) > 0.999)
let near = SIMD4<Float>(0, 2, 0, 1)
let far = SIMD4<Float>(20, 0, 0, 1)
let both: SIMD3<Float> = SpaceOptics.light(at: .zero, suns: [near, far], key: x)
check("P2 two suns: the nearer one wins (inverse square)", dot(both, y) > 0.9, "\(both)")
check("P2 no suns: the key light", dot(SpaceOptics.light(at: .zero, suns: [], key: z), z) > 0.999)
let off = SIMD4<Float>(0, 0, 0, 0)
check("P2 a slot with no sun adds nothing", dot(SpaceOptics.light(at: .zero, suns: [off, sun], key: y), x) > 0.999)
check("P2 the side facing the light is in full day", close(SpaceOptics.day(normal: x, light: x), 1))
check("P2 the far side is night", close(SpaceOptics.day(normal: -x, light: x), 0))
let edge: Float = SpaceOptics.day(normal: y, light: x)
check("P2 the terminator is soft (partly lit)", edge > 0.1 && edge < 0.6, "\(edge)")
// the day side, weighted, faces the light from any direction
var faces: Bool = true
for k in 0..<12 {
    let a: Float = Float(k) * 0.52
    let l: SIMD3<Float> = unit(SIMD3<Float>(cos(a), 0.4 * sin(a * 1.7), sin(a)))
    var lit = SIMD3<Float>(0, 0, 0)
    for j in 0..<200 {
        let u: Float = Float(j) * 2.399963
        let h: Float = 1 - (Float(j) + 0.5) * 2 / 200
        let ring: Float = max(1 - h * h, 0).squareRoot()
        let n = SIMD3<Float>(cos(u) * ring, h, sin(u) * ring)
        lit += n * SpaceOptics.day(normal: n, light: l)
    }
    if dot(unit(lit), l) < 0.99 { faces = false }
}
check("P2 the day side faces the light, whichever way it comes", faces)
let duskOn: Float = SpaceOptics.dusk(normal: unit(SIMD3<Float>(0.04, 1, 0)), light: x)
check("P2 the reddened band sits on the terminator", duskOn > 0.8 && SpaceOptics.dusk(normal: x, light: x) < 0.01
      && SpaceOptics.dusk(normal: -x, light: x) < 0.01, "\(duskOn)")

// MARK: P3 a gas giant and its ring

check("P3 the planet shadows the ring behind it from the sun", SpaceOptics.planetShadowsRing(x: -1.6, y: 0, light: x))
check("P3 not on the sun's side", !SpaceOptics.planetShadowsRing(x: 1.6, y: 0, light: x))
check("P3 not beside the shadow", !SpaceOptics.planetShadowsRing(x: -1.6, y: 1.4, light: x))
check("P3 the shadow is a planet wide", SpaceOptics.planetShadowsRing(x: -2.0, y: 0.9, light: x)
      && !SpaceOptics.planetShadowsRing(x: -2.0, y: 1.1, light: x))
// sun above the ring plane (y up): the ring shades the southern clouds
let high: SIMD3<Float> = unit(SIMD3<Float>(1, 0.5, 0))
let south: SIMD3<Float> = unit(SIMD3<Float>(-0.2, -0.45, 0.3))
let north: SIMD3<Float> = unit(SIMD3<Float>(-0.2, 0.45, 0.3))
let hit: Float? = SpaceOptics.ringShadowRadius(point: south, light: high)
check("P3 the ring's shadow falls on the hemisphere away from the sun", hit != nil
      && SpaceOptics.ringShadowRadius(point: north, light: high) == nil, "\(String(describing: hit))")
var banded: Int = 0
for k in 0..<60 {
    let lat: Float = -Float(k) / 60
    let p: SIMD3<Float> = unit(SIMD3<Float>(0.6, lat, 0.2))
    if let rho = SpaceOptics.ringShadowRadius(point: p, light: high), SpaceOptics.ringDensity(rho) > 0.3 { banded += 1 }
}
check("P3 ... as a band where the ring is dense", banded > 3 && banded < 57, "\(banded)")
check("P3 the Cassini division is dark", SpaceOptics.ringDensity(1.95) < SpaceOptics.ringDensity(1.8) * 0.3
      && SpaceOptics.ringDensity(1.95) < SpaceOptics.ringDensity(2.1) * 0.3)
check("P3 nothing inside the C ring or beyond the A ring", SpaceOptics.ringDensity(1.1) == 0
      && SpaceOptics.ringDensity(2.4) == 0)
check("P3 the C ring is faint", SpaceOptics.ringDensity(1.4) < SpaceOptics.ringDensity(1.7) * 0.6)

// MARK: P4 the pulsar

let period: Float = SpaceOptics.pulsarPeriod
check("P4 the beams come round once a period", close(SpaceOptics.beamPhase(time: 0.37, seed: 0.2),
                                                     SpaceOptics.beamPhase(time: 0.37 + period, seed: 0.2), 1e-3))
check("P4 half a period: half a turn", close(SpaceOptics.beamPhase(time: period / 2, seed: 0)
                                              - SpaceOptics.beamPhase(time: 0, seed: 0), Float.pi, 1e-3))
let b0: SIMD3<Float> = SpaceOptics.beam(axis: z, e1: x, e2: y, phase: 0)
let b1: SIMD3<Float> = SpaceOptics.beam(axis: z, e1: x, e2: y, phase: 2)
check("P4 a beam stays at its tilt from the spin axis as it sweeps",
      close(acos(dot(b0, z)), 0.61, 1e-4) && close(acos(dot(b1, z)), 0.61, 1e-4))
check("P4 the links beat twice a turn", close(SpaceOptics.linkBeat * period, 2))
check("P4 the link shader beats at that rate", GraphStyleShaders.link.contains("rp_t * 1.3333333")
      && close(1.3333333, SpaceOptics.linkBeat, 1e-6))
check("P4 the core and nebula flash at it too", GraphStyleShaders.pulsarCore.contains("rp_t * 1.3333333")
      && GraphStyleShaders.pulsarGlow.contains("rp_t * 1.3333333"))
check("P4 3000 s of clock is a whole number of turns (no jump at the wrap)",
      close((3000 / period).rounded(), 3000 / period, 1e-3))
let faceOn = SpaceOptics.nebula(axis: z, toEye: z, right: x, up: y)
let edgeOn = SpaceOptics.nebula(axis: y, toEye: z, right: x, up: y)
let sideways = SpaceOptics.nebula(axis: x, toEye: z, right: x, up: y)
check("P4 the axis at the eye: the nebula a round ring", faceOn.edgeOn < 0.01
      && close(SpaceOptics.nebulaRatio(edgeOn: faceOn.edgeOn), 1, 1e-3))
check("P4 the axis across the sky: the torus seen edge on", close(edgeOn.edgeOn, 1, 1e-4)
      && SpaceOptics.nebulaRatio(edgeOn: edgeOn.edgeOn) < 0.01)
check("P4 its +y turned along the axis as seen", close(edgeOn.turn, 0, 1e-5)
      && close(sideways.turn, -Float.pi / 2, 1e-5), "\(edgeOn.turn) \(sideways.turn)")

// MARK: P5 the comet

let cometAt = SIMD3<Float>(5, 0, 0)
let restTails = SpaceOptics.cometTails(position: cometAt, velocity: .zero, light: .zero, key: y)
check("P5 at rest both tails point straight away from the light", dot(restTails.ion, x) > 0.999
      && dot(restTails.dust, x) > 0.999)
let flying = SIMD3<Float>(0, 0.1, 0)
let slow = SpaceOptics.cometTails(position: cometAt, velocity: flying, light: .zero, key: y)
check("P5 moving: the ion tail still exactly away from the light", dot(slow.ion, x) > 0.9999)
check("P5 the dust tail lags behind the motion", dot(slow.dust, flying) < 0 && dot(slow.dust, x) > 0)
let lagSlow: Float = acos(min(dot(slow.dust, slow.ion), 1))
let fast = SpaceOptics.cometTails(position: cometAt, velocity: flying * 20, light: .zero, key: y)
let lagFast: Float = acos(min(dot(fast.dust, fast.ion), 1))
check("P5 a slow orbit bends the dust tail visibly; faster bends it more",
      lagSlow > 0.15 && lagFast > lagSlow, "\(lagSlow) \(lagFast)")
check("P5 never past square to the light", lagFast < Float.pi / 2 && dot(fast.dust, x) > 0.5)
let keyTails = SpaceOptics.cometTails(position: cometAt, velocity: .zero, light: nil, key: y)
check("P5 with no sun, away from the key light", dot(keyTails.ion, -y) > 0.999)
let alongTails = SpaceOptics.cometTails(position: cometAt, velocity: x, light: .zero, key: y)
check("P5 flying straight away from the sun: no lag sideways", dot(alongTails.dust, x) > 0.999)

// MARK: P6 the corona's number

var roundTrip: Bool = true
for k in 0..<64 {
    let seed: Float = Float(k) / 64
    for m in stride(from: Float(0), through: 1, by: 0.125) {
        let read = SpaceOptics.coronaRead(SpaceOptics.coronaCode(seed: seed, motion: m))
        let wantSeed: Float = (seed * 32).rounded(.down) / 32
        if !close(read.seed, wantSeed, 1e-4) || !close(read.motion, m, 2e-3) { roundTrip = false }
    }
}
check("P6 a corona's code gives back its seed (to 1/32) and motion", roundTrip)
check("P6 the code stays between 2 and 3 (the shader's |z| - 2)",
      SpaceOptics.coronaCode(seed: 0.999, motion: 1) < 3 && SpaceOptics.coronaCode(seed: 0, motion: 0) >= 2)
check("P6 the shader reads it the same way", GraphStyleShaders.sunCorona.contains("floor(rp_code * 32.0) / 32.0")
      && GraphStyleShaders.sunCorona.contains("* 32.0 / 0.96"))

// MARK: P7 sparks

let plume: SpaceOptics.Trail = SpaceOptics.trail(style: 0)
let plasma: SpaceOptics.Trail = SpaceOptics.trail(style: 5)
let ice: SpaceOptics.Trail = SpaceOptics.trail(style: 3)
let others: [SpaceOptics.Trail] = (0...5).map { SpaceOptics.trail(style: $0) }
check("P7 a black hole's plume is thrown back, narrow and streaking", plume.backward && plume.spread < 45
      && plume.stretch > 0)
check("P7 ... the longest-lived and densest", others.allSatisfy { $0.life <= plume.life && $0.rate <= plume.rate })
check("P7 ... white-gold cooling to ember red", (plume.colours.first?.x ?? 0) > 0.9 && (plume.colours.last?.y ?? 1) < 0.2)
check("P7 a sun's plasma is warm", plasma.colours.allSatisfy { $0.x >= $0.z })
check("P7 a comet's dust is icy and left behind", ice.backward && (ice.colours.first?.z ?? 0) >= (ice.colours.first?.x ?? 1) - 0.2
      && (ice.colours.last?.z ?? 0) > (ice.colours.last?.x ?? 1))
check("P7 every colour on screen's scale, every life positive",
      others.allSatisfy { t in t.life > 0 && t.colours.allSatisfy { c in c.min() >= 0 && c.max() <= 1 } })

// MARK: P8 the shaders keep the physics

check("P8 the rocky terminator is the tested one", GraphStyleShaders.rockBody.contains("smoothstep(-0.08, 0.22, rp_ndl)"))
check("P8 the ring shadow on the clouds only with a ring", GraphStyleShaders.gasBody.contains("* rpRinged"))
check("P8 the disk's Kepler shear", GraphStyleShaders.bhDisk.contains("pow(rp_in / max(rp_r, rp_in), 1.5)")
      && close(0.43, SpaceOptics.diskInner))

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
