import Foundation

// MARK: - The Space styles' physics, on the CPU
//
// What the Space theme's bodies do follows a little real physics, the same
// here as in their shaders (GraphSpaceShaders) and their animator
// (GraphStyleAnimator), so it can be checked on Linux
// (Tests/SpaceStyleTests):
//
// - a black hole's disk turns as Kepler says, the inner lanes fastest
//   (angular speed as r^-1.5), and is brightest where its gas comes towards
//   the eye (relativistic beaming, D^3);
// - a lit body's day side faces its light, whichever of the nearest suns
//   that is (each weighted by the inverse square of its distance), with a
//   soft terminator and a reddened band along it;
// - a gas giant's ring is shadowed by the planet on the side away from the
//   sun, and throws its own shadow on the clouds;
// - a pulsar's two beams sweep round its spin axis once a period, and its
//   links beat twice a turn; its wind nebula lies square to that axis;
// - a comet's ion tail points straight away from its light, its dust tail
//   curves back along its path;
// - a sun's corona carries its seed and how hard it is moving in one
//   number (the plane's z scale), so dragged, its rays flare;
// - each style's sparks when it moves: a black hole's bright plume of
//   debris, a sun's plasma, a comet's icy dust.
//
// The styles themselves (GraphNodeStyle) live here too, so a theme that
// mirrors them (the Neurons' cell states, NeuronState) is tested with them.
// Plain SIMD3<Float> arithmetic (no simd module). Foundation only.

/// What a note looks like in the Space. Each is physically inspired, with
/// its own look at rest, its own answer to being dragged, and its own
/// effect on the links that reach it (see GraphStyleShaders.link):
///
/// - black hole: a black sphere, a Doppler-bright photon ring, lensed arcs,
///   a Keplerian accretion disk; links bend in and fall into it;
/// - sun: granulation, limb darkening, corona, prominences and flares;
///   links run whiter near it and it throws its pulses out as plasma;
/// - rocky planet: continents, clouds, a terminator towards the nearest
///   sun, air, a moon that lags when dragged; pulses glint on arrival;
/// - gas giant: banded clouds with jets and a storm, a tilted ring with
///   shadows; dragged, the bands smear; links light a bar on the ring;
/// - pulsar: a tiny core and two sweeping beams; its links beat in step;
/// - comet: a nucleus, a coma and two tails pointing away from the
///   nearest sun, stretching when it moves.
///
/// The raw value is stored; `code` is what the link shader reads, and also
/// which end of a link sends: the higher code is the link's A end.
nonisolated enum GraphNodeStyle: String, CaseIterable, Sendable, Identifiable {
    case blackHole
    case rocky
    case gasGiant
    case comet
    case pulsar
    case sun

    var id: String { rawValue }

    /// The link shader's number for this style (0...5), and its send rank.
    var code: Int {
        switch self {
        case .blackHole: return 0
        case .rocky: return 1
        case .gasGiant: return 2
        case .comet: return 3
        case .pulsar: return 4
        case .sun: return 5
        }
    }

    var name: String {
        switch self {
        case .blackHole: return "Black holes"
        case .sun: return "Suns"
        case .rocky: return "Rocky planets"
        case .gasGiant: return "Gas giants"
        case .pulsar: return "Pulsars"
        case .comet: return "Comets"
        }
    }

    var symbol: String {
        switch self {
        case .blackHole: return "circle.circle.fill"
        case .sun: return "sun.max.fill"
        case .rocky: return "globe.europe.africa.fill"
        case .gasGiant: return "circle.lefthalf.filled"
        case .pulsar: return "dot.radiowaves.left.and.right"
        case .comet: return "sparkle"
        }
    }

    /// The order the picker lists them in.
    static let menuOrder: [GraphNodeStyle] = [.blackHole, .sun, .rocky, .gasGiant, .pulsar, .comet]

    /// How long a pulsar takes to turn once, in seconds. The link shader
    /// beats twice a turn (4/3 a second) and GraphShape.clockPeriod (3000 s)
    /// is a whole number of turns, so the clock's wrap never shows
    /// (SpaceOptics, tested on Linux).
    static let pulsarPeriod: Float = SpaceOptics.pulsarPeriod
}

nonisolated enum SpaceOptics {
    // MARK: the black hole's disk

    /// The disk's inner edge (the innermost stable orbit), as a share of
    /// its outer radius (GraphShape.diskInner).
    static let diskInner: Float = 0.43

    /// How fast the disk turns at `r` (a share of its outer radius), over
    /// the inner edge's: (inner / r)^1.5, Kepler's third law.
    static func keplerRate(radius r: Float, inner: Float = diskInner) -> Float {
        let rr: Float = max(r, inner)
        return pow(inner / rr, 1.5)
    }

    /// The gas's speed at `r`, as a share of light's: half at the inner
    /// edge, falling as 1 / sqrt(r).
    static func diskSpeed(radius r: Float, inner: Float = diskInner) -> Float {
        0.5 * (inner / max(r, inner)).squareRoot()
    }

    /// Relativistic beaming: D^3, D = 1 / (1 - beta cos), where `towardEye`
    /// is the cosine between the gas's motion and the line to the eye;
    /// held to 0.3...3.5 so the receding side never vanishes.
    static func beaming(speed beta: Float, towardEye cosine: Float) -> Float {
        let d: Float = 1 / max(1 - beta * cosine, 0.05)
        return min(max(d * d * d, 0.3), 3.5)
    }

    // MARK: light

    /// The light on a body at `p`: the suns (xyz their places, w 1 when
    /// there is a sun) each weighted by 1 / distance^2, and a trace of the
    /// key light when there is none; unit length. As the shaders' `light`.
    static func light(at p: SIMD3<Float>, suns: [SIMD4<Float>], key: SIMD3<Float>) -> SIMD3<Float> {
        var l: SIMD3<Float> = key * 0.0001
        for s in suns.prefix(4) {
            let d = SIMD3<Float>(s.x, s.y, s.z) - p
            let e: Float = max(dot(d, d), 0.0001)
            l += d * (s.w / (e * e.squareRoot()))
        }
        return unit(l, or: unit(key, or: SIMD3<Float>(0, 1, 0)))
    }

    /// How much of the day a surface whose normal is `n` sees from light
    /// `l`: 0 on the night side, 1 in full day, a soft terminator between
    /// (as the rocky shader's rp_day).
    static func day(normal n: SIMD3<Float>, light l: SIMD3<Float>) -> Float {
        smoothstep(-0.08, 0.22, dot(n, l))
    }

    /// The reddened band along the terminator: 1 on it, falling off either
    /// side (as rp_dusk).
    static func dusk(normal n: SIMD3<Float>, light l: SIMD3<Float>) -> Float {
        let x: Float = dot(n, l) - 0.04
        return exp(-x * x * 90)
    }

    // MARK: a gas giant and its ring

    /// Whether the planet's shadow falls on the ring at (x, y) in the
    /// ring's plane (planet radii, the planet at the origin), with the
    /// light along `l` in the planet's own frame (z square to the ring):
    /// behind the planet from the sun, within one radius of the line
    /// through its centre. As the gasRing shader.
    static func planetShadowsRing(x: Float, y: Float, light l: SIMD3<Float>) -> Bool {
        let along: Float = x * l.x + y * l.y
        let rho2: Float = x * x + y * y
        let off: Float = rho2 - along * along
        return along < 0 && off < 1
    }

    /// Where the line from cloud point `p` (unit sphere, the ring in y = 0)
    /// towards the light `l` crosses the ring's plane: its distance from
    /// the centre in planet radii, or nil when it never does (the light on
    /// the other side). As the gasBody shader's ring shadow.
    static func ringShadowRadius(point p: SIMD3<Float>, light l: SIMD3<Float>) -> Float? {
        let ly: Float = abs(l.y) < 0.001 ? 0.001 : l.y
        let t: Float = -p.y / ly
        guard t >= 0 else { return nil }
        let hx: Float = p.x + l.x * t
        let hz: Float = p.z + l.z * t
        return (hx * hx + hz * hz).squareRoot()
    }

    /// The ring's own density at `rho` planet radii, 0...1 (a faint C ring
    /// inside, the Cassini division dark), as the shaders' ringDensity.
    static func ringDensity(_ rho: Float) -> Float {
        let body: Float = smoothstep(1.3, 1.36, rho) * (1 - smoothstep(2.2, 2.3, rho))
        let gd: Float = (rho - 1.95) / 0.03
        let gap: Float = 1 - 0.85 * exp(-gd * gd)
        let cring: Float = 0.35 + 0.65 * smoothstep(1.42, 1.52, rho)
        return body * gap * cring
    }

    // MARK: the pulsar

    /// How long a pulsar takes to turn once (seconds). The links beat
    /// twice a turn, and GraphShape.clockPeriod (3000 s) is a whole number
    /// of turns, so the clock's wrap never shows.
    static let pulsarPeriod: Float = 1.5

    /// The links' beats a second: two a turn (the shader's 1.3333333).
    static var linkBeat: Float { 2 / pulsarPeriod }

    /// Where the beams are round the spin axis at `time` (radians, 0...2pi
    /// plus the seed's turn).
    static func beamPhase(time: Float, seed: Float) -> Float {
        let turn: Float = time / pulsarPeriod
        return (turn - turn.rounded(.down)) * 2 * Float.pi + seed * 2 * Float.pi
    }

    /// One beam's direction: tilted `tilt` from the spin axis `n`, at
    /// `phase` round it (`e1`, `e2` square to `n` and to each other).
    static func beam(axis n: SIMD3<Float>, e1: SIMD3<Float>, e2: SIMD3<Float>, phase: Float,
                     tilt: Float = 0.61) -> SIMD3<Float> {
        let around: SIMD3<Float> = e1 * cos(phase) + e2 * sin(phase)
        return unit(n * cos(tilt) + around * sin(tilt), or: n)
    }

    /// The wind nebula's place on screen: the angle to turn its plane so
    /// its +y runs along the spin axis as seen (from the screen's right),
    /// and how edge-on its torus is (0 the axis at the eye: a round ring;
    /// 1 the axis across the sky: a thin line).
    static func nebula(axis n: SIMD3<Float>, toEye: SIMD3<Float>, right: SIMD3<Float>,
                       up: SIMD3<Float>) -> (turn: Float, edgeOn: Float) {
        let ax: Float = dot(n, right)
        let ay: Float = dot(n, up)
        let seen: Float = (ax * ax + ay * ay).squareRoot()
        let edgeOn: Float = min(length(cross(unit(toEye, or: SIMD3<Float>(0, 0, 1)), n)), 1)
        let turn: Float = seen > 0.000_01 ? atan2(ay, ax) - Float.pi / 2 : 0
        return (turn, edgeOn)
    }

    /// The torus's height over its width on screen, for `edgeOn`.
    static func nebulaRatio(edgeOn k: Float) -> Float {
        max(1 - k * k, 0).squareRoot()
    }

    // MARK: the comet

    /// The two tails of a comet at `position` moving at `velocity`, lit
    /// from `light` (a place; nil: the key light's direction `key`): the
    /// ion tail straight away from the light, the dust tail bent back
    /// towards where the comet has been - more the faster it goes (a slow
    /// orbit, about 0.1 a second, bends it by some 14 degrees; a drag up to
    /// 35), never past square to the light.
    static func cometTails(position p: SIMD3<Float>, velocity v: SIMD3<Float>, light: SIMD3<Float>?,
                           key: SIMD3<Float>) -> (ion: SIMD3<Float>, dust: SIMD3<Float>) {
        var away: SIMD3<Float> = -unit(key, or: SIMD3<Float>(0, 1, 0))
        if let light { away = unit(p - light, or: away) }
        let speed: Float = length(v)
        guard speed > 0.0001 else { return (away, away) }
        // the velocity's part square to the ion tail: the dust lags behind it
        let across: SIMD3<Float> = v - away * dot(v, away)
        let lag: Float = min(speed * 2.5, 0.7)
        let dust: SIMD3<Float> = unit(away - unit(across, or: SIMD3<Float>(0, 0, 0)) * lag, or: away)
        return (away, dust)
    }

    // MARK: the corona's number

    /// A sun's corona plane carries its seed (to 1/32) and how hard it is
    /// moving (0...1) in its z scale: 2 + seed + motion * 0.03.
    static func coronaCode(seed: Float, motion: Float) -> Float {
        let s: Float = (min(max(seed, 0), 0.999) * 32).rounded(.down) / 32
        let m: Float = min(max(motion, 0), 1)
        return 2 + s + m * (0.96 / 32)
    }

    /// The seed and motion back from a corona's code (as the shader reads
    /// it).
    static func coronaRead(_ code: Float) -> (seed: Float, motion: Float) {
        let v: Float = min(max(code - 2, 0), 0.9999)
        let s: Float = (v * 32).rounded(.down) / 32
        let m: Float = min(max((v - s) * 32 / 0.96, 0), 1)
        return (s, m)
    }

    // MARK: sparks when a body moves

    /// How one style's sparks look (GraphSim's trail emitters wear the
    /// fastest bodies' looks): life, size and speed (times the trail's
    /// scale), how wide they spray (degrees), how far they streak along
    /// their way, the colours they pass through over their life (sRGB,
    /// first to last), whether they are thrown back against the motion,
    /// and how many a second at full speed.
    struct Trail: Sendable, Equatable {
        let life: Float
        let size: Float
        let speed: Float
        let spread: Float
        let stretch: Float
        let colours: [SIMD3<Float>]
        let backward: Bool
        let rate: Float
    }

    /// By style code (GraphNodeStyle.code): 0 black hole, 1 rocky, 2 gas
    /// giant, 3 comet, 4 pulsar, 5 sun.
    static func trail(style code: Int) -> Trail {
        switch code {
        case 0:
            // a bright plume of debris, white-gold cooling to ember red,
            // streaking back along where the hole has been
            return Trail(life: 1.1, size: 0.05, speed: 0.45, spread: 22, stretch: 0.08,
                         colours: [SIMD3<Float>(1.0, 0.95, 0.84), SIMD3<Float>(1.0, 0.6, 0.15),
                                   SIMD3<Float>(0.62, 0.08, 0.0)],
                         backward: true, rate: 260)
        case 5:
            // plasma thrown off all round: white-yellow to orange
            return Trail(life: 0.7, size: 0.045, speed: 0.3, spread: 180, stretch: 0.03,
                         colours: [SIMD3<Float>(1.0, 0.95, 0.75), SIMD3<Float>(1.0, 0.55, 0.12)],
                         backward: false, rate: 200)
        case 3:
            // icy dust, cyan-white, left behind
            return Trail(life: 0.9, size: 0.03, speed: 0.15, spread: 60, stretch: 0.02,
                         colours: [SIMD3<Float>(0.85, 1.0, 1.0), SIMD3<Float>(0.45, 0.85, 1.0)],
                         backward: true, rate: 170)
        case 4:
            return Trail(life: 0.5, size: 0.03, speed: 0.2, spread: 180, stretch: 0.02,
                         colours: [SIMD3<Float>(0.85, 0.9, 1.0), SIMD3<Float>(0.55, 0.5, 1.0)],
                         backward: false, rate: 150)
        case 2:
            return Trail(life: 0.55, size: 0.035, speed: 0.12, spread: 180, stretch: 0,
                         colours: [SIMD3<Float>(1.0, 0.86, 0.6), SIMD3<Float>(0.8, 0.55, 0.3)],
                         backward: false, rate: 140)
        default:
            return Trail(life: 0.5, size: 0.03, speed: 0.12, spread: 180, stretch: 0,
                         colours: [SIMD3<Float>(0.75, 0.85, 1.0), SIMD3<Float>(0.5, 0.6, 0.8)],
                         backward: false, rate: 140)
        }
    }

    // MARK: helpers

    static func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let v: SIMD3<Float> = a * b
        return v.x + v.y + v.z
    }

    static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    static func length(_ v: SIMD3<Float>) -> Float {
        dot(v, v).squareRoot()
    }

    static func unit(_ v: SIMD3<Float>, or fallback: SIMD3<Float>) -> SIMD3<Float> {
        let n: Float = length(v)
        return n > 0.000_01 ? v / n : fallback
    }

    static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t: Float = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
