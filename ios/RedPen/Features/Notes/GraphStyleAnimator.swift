import SceneKit
import UIKit
import simd

/// One note's style pieces, as GraphStyleKit built them, for the animator.
nonisolated struct GraphStyleRig {
    let style: GraphNodeStyle
    /// The note's own frame for its disk, ring or spin axis (its z).
    let tilt: SCNNode
    let base: simd_quatf
    /// The body sphere, inside `tilt`, turned by `bodyTurn` so its own y is
    /// the tilt's z, and spun about that.
    let body: SCNNode
    let bodyRadius: Float
    /// The body's y scale over its radius (a gas giant is a little oblate).
    let bodyFlat: Float
    /// Radians a second the body turns.
    let bodySpin: Float
    let bodyTurn: simd_quatf
    let diskLeaf: SCNNode
    let diskSide: Float
    let ringLeaf: SCNNode
    let ringSide: Float
    let moon: SCNNode?
    let moonOrbit: Float
    let beam: SCNNode?
    /// A beam's half width and half length; a tail's width and length.
    let extraSize: SIMD2<Float>
    let tail: SCNNode?
    /// 0 to 1, fixed for the note: phases, flares, which way a beam starts.
    let seed: Float
    /// The glowing pieces the haze dims: never the opaque body.
    let haze: [SCNNode]
    /// The base radius, for the selection orbit.
    let reach: Float
}

/// What GraphSim knows this frame, handed to the animator.
nonisolated struct GraphStyleFrame {
    let dt: Float
    /// GraphSim's wrapped clock times rpMotion: the same time the shaders
    /// see, so a pulsar's beams and its links' beats stay in step.
    let time: Float
    /// The camera, and its screen's right and up, in the space's own
    /// coordinates.
    let eye: SIMD3<Float>
    let right: SIMD3<Float>
    let up: SIMD3<Float>
    /// The key light's direction in the space's coordinates.
    let key: SIMD3<Float>
    /// The space's own coordinates to the scene's, for the suns' uniforms.
    let toScene: simd_float4x4
    let grabbed: Int?
    let selected: Int?
    /// False with Reduce Motion (or SpaceQuality .still): everything is
    /// posed, nothing runs.
    let lively: Bool
}

/// Moves each style's own pieces, on SceneKit's render thread, from
/// GraphSim's positions, speeds, motion levels and drag state. Called with
/// GraphSim's lock held; touches only SceneKit nodes and the lit
/// materials' light uniforms, never SwiftUI.
///
/// - black hole: the disk precesses slowly, leans into the way it is
///   dragged on a soft spring (so it wobbles and settles when let go) and
///   runs hotter; the photon ring turns so its bright side is the side of
///   the disk coming towards the eye, and knows the disk's inclination;
/// - sun: turns slowly; its face runs hotter when dragged (its corona
///   swells in GraphSim, and it sheds sparks);
/// - rocky planet: turns; its moon follows its orbit on a spring, so a
///   dragged planet leaves it behind and it swings back round;
/// - gas giant: turns; dragged, its bands smear (the body's z code) and
///   the ring shimmers;
/// - pulsar: the beams sweep round the spin axis once every
///   GraphNodeStyle.pulsarPeriod from the shaders' own clock, facing the
///   eye; dragged, the axis nutates and the beams lengthen;
/// - comet: the tail points away from the nearest sun (or the key light)
///   and swings behind and stretches as it moves;
/// - every note: glows dim with distance (haze);
/// - the chosen note: an orbit ring, eased in.
///
/// Light: in the graph look every lit material is lit by the four busiest
/// suns. In the Universe each planet's materials are lit by its own star or
/// black hole (written only when that owner moves), each flying comet by
/// the nearest light, and the Oort cloud by the key light alone.
nonisolated final class GraphStyleAnimator: @unchecked Sendable {
    private let rigs: [GraphStyleRig]
    /// The notes that are suns, the busiest first (at most four light).
    private let suns: [Int]
    private let lit: [SCNMaterial]
    private let orbit: SCNNode?
    /// How far the graph reaches from its centre, for the haze.
    private let extent: Float

    /// The angle GraphSim turns each ring's plane to within its holder.
    private(set) var leafTurn: [Float]
    /// Each note's disk (or spin) axis in the space's coordinates.
    private(set) var axis: [SIMD3<Float>]

    private var bodyAngle: [Float]
    private var lean: [SIMD3<Float>]
    private var leanVelocity: [SIMD3<Float>]
    private var moonAt: [SIMD3<Float>]
    private var moonVelocity: [SIMD3<Float>]
    private var moonPlaced: [Bool]
    private var hazeShown: [Float]
    private var orbitNote: Int?
    private var orbitGrow: Float = 0
    private var litOnce: Bool = false
    /// The Universe's lights: each owner and the materials it lights, where
    /// it was last written, and each comet's own materials.
    private let owners: [Int]
    private let ownedBy: [[SCNMaterial]]
    /// Where each owner was, in the space's own coordinates, when its
    /// materials were last written.
    private var ownerShown: [SIMD3<Float>]
    /// The space-to-scene turn (its first two columns) at the last write:
    /// the device-tilt rig turns it a little all the time, which moves no
    /// star in the space, so only a turn past 0.01 rad rewrites them all.
    private var turnShown: (SIMD3<Float>, SIMD3<Float>) = (SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 0, 0))
    private let nearest: [(SCNMaterial, Int)]
    private var nearestShown: [SIMD3<Float>]
    /// What comet tails point away from: every light in the Universe, the
    /// suns in the graph look.
    private let tailLights: [Int]

    private let leanStiffness: Float = 40
    private let leanDamping: Float = 3.8
    private let moonStiffness: Float = 30
    private let moonDamping: Float = 3.8

    init(rigs: [GraphStyleRig], suns: [Int], lit: [SCNMaterial], orbit: SCNNode?, extent: Float,
         owned: [(SCNMaterial, Int)] = [], nearest: [(SCNMaterial, Int)] = [], lights: [Int]? = nil) {
        self.rigs = rigs
        self.suns = Array(suns.prefix(4))
        self.lit = lit
        self.orbit = orbit
        self.extent = max(extent, 1)
        var order: [Int] = []
        var groups: [Int: [SCNMaterial]] = [:]
        for (material, owner) in owned {
            if groups[owner] == nil { order.append(owner) }
            groups[owner, default: []].append(material)
        }
        owners = order
        ownedBy = order.map { groups[$0] ?? [] }
        let far = SIMD3<Float>(1e9, 1e9, 1e9)
        ownerShown = [SIMD3<Float>](repeating: far, count: order.count)
        self.nearest = nearest
        nearestShown = [SIMD3<Float>](repeating: far, count: nearest.count)
        tailLights = lights ?? Array(suns.prefix(4))
        let count: Int = rigs.count
        let zero = SIMD3<Float>(0, 0, 0)
        leafTurn = [Float](repeating: 0, count: count)
        axis = rigs.map { $0.base.act(SIMD3<Float>(0, 0, 1)) }
        bodyAngle = rigs.map { $0.seed * 6.2831853 }
        lean = [SIMD3<Float>](repeating: zero, count: count)
        leanVelocity = [SIMD3<Float>](repeating: zero, count: count)
        moonAt = [SIMD3<Float>](repeating: zero, count: count)
        moonVelocity = [SIMD3<Float>](repeating: zero, count: count)
        moonPlaced = [Bool](repeating: false, count: count)
        hazeShown = [Float](repeating: -1, count: count)
        orbit?.isHidden = true
    }

    /// The colour of the sparks a moving note sheds.
    func sparkColor(_ i: Int) -> UIColor {
        guard i >= 0, i < rigs.count else { return UIColor.orange }
        switch rigs[i].style {
        case .blackHole: return UIColor(red: 1, green: 0.55, blue: 0.12, alpha: 1)
        case .sun: return UIColor(red: 1, green: 0.88, blue: 0.55, alpha: 1)
        case .rocky: return UIColor(red: 0.7, green: 0.82, blue: 1, alpha: 1)
        case .gasGiant: return UIColor(red: 1, green: 0.82, blue: 0.55, alpha: 1)
        case .pulsar: return UIColor(red: 0.62, green: 0.66, blue: 1, alpha: 1)
        case .comet: return UIColor(red: 0.6, green: 1, blue: 0.92, alpha: 1)
        }
    }

    /// Whether note `i` is a sun (links glow whiter, and planets are lit
    /// by it).
    func isSun(_ i: Int) -> Bool {
        i >= 0 && i < rigs.count && rigs[i].style == .sun
    }

    // MARK: each frame

    func step(_ f: GraphStyleFrame, position: [SIMD3<Float>], velocity: [SIMD3<Float>],
              level: [Float], visible: [Bool], pop: [Float]) {
        let dt: Float = f.lively ? min(max(f.dt, 0), 0.05) : 0
        for i in rigs.indices where visible[i] {
            let p: SIMD3<Float> = position[i]
            let v: SIMD3<Float> = velocity[i]
            let m: Float = f.lively ? level[i] : 0
            let scale: Float = max(pop[i], 0.05)
            let rig: GraphStyleRig = rigs[i]
            let n: SIMD3<Float> = turnTilt(i, rig: rig, velocity: v, motion: m, frame: f, dt: dt)
            spinBody(i, rig: rig, motion: m, dt: dt)
            switch rig.style {
            case .blackHole:
                shapeHole(i, rig: rig, at: p, axis: n, motion: m, scale: scale, frame: f)
            case .sun:
                let code: Float = (2 + rig.seed) / scale
                rig.ringLeaf.simdScale = SIMD3<Float>(rig.ringSide, rig.ringSide, code)
            case .rocky:
                moveMoon(i, rig: rig, at: p, axis: n, frame: f, dt: dt, scale: scale)
            case .gasGiant:
                let side: Float = rig.diskSide
                rig.diskLeaf.simdScale = SIMD3<Float>(side, side, side * (1 + m))
            case .pulsar:
                sweepBeams(rig, at: p, axis: n, motion: m, frame: f)
            case .comet:
                swingTail(rig, at: p, velocity: v, motion: m, frame: f, position: position)
            }
            dim(i, rig: rig, at: p, eye: f.eye)
        }
        placeOrbit(f, position: position, visible: visible, pop: pop)
        light(f, position: position, visible: visible)
        lightOwned(f, position: position)
        lightNearest(f, position: position)
    }

    /// Precession, and the lean into the motion on a soft spring. Returns
    /// the disk's (or spin) axis now.
    private func turnTilt(_ i: Int, rig: GraphStyleRig, velocity v: SIMD3<Float>, motion m: Float,
                          frame f: GraphStyleFrame, dt: Float) -> SIMD3<Float> {
        let n0: SIMD3<Float> = rig.base.act(SIMD3<Float>(0, 0, 1))
        var gain: Float = 0.22
        if rig.style == .rocky || rig.style == .sun { gain = 0.1 }
        var target: SIMD3<Float> = simd_cross(n0, v) * gain
        let size: Float = simd_length(target)
        if size > 0.6 { target *= 0.6 / size }
        if !f.lively { target = SIMD3<Float>(0, 0, 0) }
        if dt > 0 {
            let pull: SIMD3<Float> = (target - lean[i]) * leanStiffness
            let brake: SIMD3<Float> = leanVelocity[i] * leanDamping
            leanVelocity[i] += (pull - brake) * dt
            lean[i] += leanVelocity[i] * dt
        } else if !f.lively {
            lean[i] = SIMD3<Float>(0, 0, 0)
            leanVelocity[i] = SIMD3<Float>(0, 0, 0)
        }
        let t: Float = f.time
        let phase: Float = rig.seed * 6.2831853
        let yaw: Float = 0.1 * sin(t * 0.13 + phase)
        let nod: Float = 0.06 * sin(t * 0.09 + phase * 0.5)
        let precess: simd_quatf = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: nod, axis: SIMD3<Float>(1, 0, 0))
        var nutate = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
        if rig.style == .pulsar && m > 0.001 {
            let wobble: Float = m * 0.35 * sin(t * 7)
            let across: SIMD3<Float> = rig.base.act(SIMD3<Float>(1, 0, 0))
            nutate = simd_quatf(angle: wobble, axis: across)
        }
        let tilt: Float = simd_length(lean[i])
        var leaning = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
        if tilt > 0.00001 { leaning = simd_quatf(angle: tilt, axis: lean[i] / tilt) }
        let turned: simd_quatf = leaning * nutate * precess * rig.base
        rig.tilt.simdOrientation = turned
        let n: SIMD3<Float> = turned.act(SIMD3<Float>(0, 0, 1))
        axis[i] = n
        return n
    }

    private func spinBody(_ i: Int, rig: GraphStyleRig, motion m: Float, dt: Float) {
        guard rig.style != .blackHole else { return }
        var angle: Float = bodyAngle[i] + rig.bodySpin * dt
        if angle > 6.2831853 { angle -= 6.2831853 }
        bodyAngle[i] = angle
        let spun = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
        rig.body.simdOrientation = rig.bodyTurn * spun
        let r: Float = rig.bodyRadius
        let code: Float = 1 + 0.004 * m
        rig.body.simdScale = SIMD3<Float>(r, r * rig.bodyFlat, r * code)
    }

    /// The disk's heat, and the ring turned to the disk: +x the side coming
    /// towards the eye, z the inclination with the side the broad arc is
    /// on (see GraphStyleShaders.bhRing).
    private func shapeHole(_ i: Int, rig: GraphStyleRig, at p: SIMD3<Float>, axis n: SIMD3<Float>,
                           motion m: Float, scale: Float, frame f: GraphStyleFrame) {
        let side: Float = rig.diskSide
        rig.diskLeaf.simdScale = SIMD3<Float>(side, side, side * (1 + m))
        let gap: SIMD3<Float> = f.eye - p
        let far: Float = max(simd_length(gap), 0.0001)
        let toEye: SIMD3<Float> = gap / far
        let q: SIMD3<Float> = simd_cross(toEye, n)
        let k: Float = min(simd_length(q), 1)
        let qx: Float = simd_dot(q, f.right)
        let qy: Float = simd_dot(q, f.up)
        if qx * qx + qy * qy > 0.000_001 { leafTurn[i] = atan2(qy, qx) }
        let above: Float = simd_dot(n, toEye) >= 0 ? 1 : -1
        let code: Float = (2 + k * above) / scale
        rig.ringLeaf.simdScale = SIMD3<Float>(rig.ringSide, rig.ringSide, code)
    }

    /// The moon: on a spring towards its place on its orbit, so it lags
    /// and swings when the planet is dragged.
    private func moveMoon(_ i: Int, rig: GraphStyleRig, at p: SIMD3<Float>, axis n: SIMD3<Float>,
                          frame f: GraphStyleFrame, dt: Float, scale: Float) {
        guard let moon = rig.moon else { return }
        let e1: SIMD3<Float> = rig.tilt.simdOrientation.act(SIMD3<Float>(1, 0, 0))
        let e2: SIMD3<Float> = simd_cross(n, e1)
        let angle: Float = f.time * 0.5 + rig.seed * 6.2831853
        let ring: SIMD3<Float> = e1 * cos(angle) + e2 * sin(angle)
        let target: SIMD3<Float> = p + ring * rig.moonOrbit
        if !moonPlaced[i] || dt <= 0 {
            moonAt[i] = target
            moonVelocity[i] = SIMD3<Float>(0, 0, 0)
            moonPlaced[i] = true
        } else {
            let pieces: Int = max(1, Int((dt * 120).rounded(.up)))
            let h: Float = dt / Float(pieces)
            for _ in 0..<pieces {
                let pull: SIMD3<Float> = (target - moonAt[i]) * moonStiffness
                let brake: SIMD3<Float> = moonVelocity[i] * moonDamping
                moonVelocity[i] += (pull - brake) * h
                moonAt[i] += moonVelocity[i] * h
            }
        }
        var offset: SIMD3<Float> = moonAt[i] - p
        let reach: Float = simd_length(offset)
        let most: Float = rig.moonOrbit * 4
        if reach > most {
            offset *= most / reach
            moonAt[i] = p + offset
        }
        moon.simdPosition = offset / scale
    }

    /// The two beams round the spin axis, facing the eye.
    private func sweepBeams(_ rig: GraphStyleRig, at p: SIMD3<Float>, axis n: SIMD3<Float>,
                            motion m: Float, frame f: GraphStyleFrame) {
        guard let beam = rig.beam else { return }
        let e1: SIMD3<Float> = rig.tilt.simdOrientation.act(SIMD3<Float>(1, 0, 0))
        let e2: SIMD3<Float> = simd_cross(n, e1)
        let turn: Float = f.time / GraphNodeStyle.pulsarPeriod
        let phase: Float = (turn - floor(turn)) * 6.2831853 + rig.seed * 6.2831853
        let tilt: Float = 0.61
        let around: SIMD3<Float> = e1 * cos(phase) + e2 * sin(phase)
        let b: SIMD3<Float> = simd_normalize(n * cos(tilt) + around * sin(tilt))
        let gap: SIMD3<Float> = f.eye - p
        let toEye: SIMD3<Float> = gap / max(simd_length(gap), 0.0001)
        let face: Float = abs(simd_dot(b, toEye))
        beam.simdOrientation = Self.facing(along: b, eye: toEye)
        let w: Float = rig.extraSize.x * 2
        let long: Float = rig.extraSize.y * 2 * (1 + 0.35 * m)
        beam.simdScale = SIMD3<Float>(w, long, w * (1 + face))
    }

    /// The tail, away from the nearest sun or the key light, swung behind
    /// the motion and stretched by it.
    private func swingTail(_ rig: GraphStyleRig, at p: SIMD3<Float>, velocity v: SIMD3<Float>,
                           motion m: Float, frame f: GraphStyleFrame, position: [SIMD3<Float>]) {
        guard let tail = rig.tail else { return }
        var away: SIMD3<Float> = -f.key
        var nearest: Float = Float.greatestFiniteMagnitude
        for s in tailLights where s < position.count {
            let gap: SIMD3<Float> = p - position[s]
            let d: Float = simd_length_squared(gap)
            if d < nearest && d > 0.0001 {
                nearest = d
                away = gap / d.squareRoot()
            }
        }
        var dir: SIMD3<Float> = away
        if f.lively { dir -= v * 0.6 }
        let size: Float = simd_length(dir)
        dir = size > 0.0001 ? dir / size : away
        let gap: SIMD3<Float> = f.eye - p
        let toEye: SIMD3<Float> = gap / max(simd_length(gap), 0.0001)
        let long: Float = rig.extraSize.y * (1 + 1.2 * m)
        let wide: Float = rig.extraSize.x
        tail.simdOrientation = Self.facing(along: dir, eye: toEye)
        tail.simdScale = SIMD3<Float>(wide, long, wide * (1 + m))
        tail.simdPosition = dir * (long * 0.5)
    }

    /// A turn whose y is `along` and whose z leans as far towards the eye
    /// as it can.
    private static func facing(along y: SIMD3<Float>, eye: SIMD3<Float>) -> simd_quatf {
        var z: SIMD3<Float> = eye - y * simd_dot(y, eye)
        if simd_length_squared(z) < 0.000_001 {
            let helper: SIMD3<Float> = abs(y.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            z = simd_cross(y, helper)
        }
        z = simd_normalize(z)
        let x: SIMD3<Float> = simd_cross(y, z)
        let turn = simd_float3x3(columns: (x, y, z))
        return simd_quatf(turn)
    }

    /// Far notes' glows dim a little: a cheap haze.
    private func dim(_ i: Int, rig: GraphStyleRig, at p: SIMD3<Float>, eye: SIMD3<Float>) {
        let centre: Float = simd_length(eye)
        let d: Float = simd_distance(eye, p)
        let near: Float = centre - extent * 0.3
        let far: Float = centre + extent
        let t: Float = min(max((d - near) / max(far - near, 0.001), 0), 1)
        let eased: Float = t * t * (3 - 2 * t)
        let haze: Float = 1 - 0.5 * eased
        if abs(haze - hazeShown[i]) < 0.02 { return }
        hazeShown[i] = haze
        for node in rig.haze { node.opacity = CGFloat(haze) }
    }

    /// The orbit ring round the chosen note: grows in from a little larger
    /// and fainter over a quarter of a second.
    private func placeOrbit(_ f: GraphStyleFrame, position: [SIMD3<Float>], visible: [Bool], pop: [Float]) {
        guard let orbit else { return }
        var note: Int? = f.selected
        if let n = note, n >= rigs.count || !visible[n] { note = nil }
        if note != orbitNote {
            orbitNote = note
            orbitGrow = f.lively ? 0 : 1
        }
        guard let i = note else {
            if !orbit.isHidden { orbit.isHidden = true }
            return
        }
        if f.dt > 0 { orbitGrow = min(1, orbitGrow + f.dt / 0.25) }
        let left: Float = 1 - orbitGrow
        let eased: Float = 1 - left * left * left
        let ring: Float = rigs[i].reach * 2.2 / 0.9 * 2
        let size: Float = ring * (1.35 - 0.35 * eased) * max(pop[i], 0.05)
        orbit.simdPosition = position[i]
        orbit.simdScale = SIMD3<Float>(size, size, size)
        orbit.opacity = CGFloat(eased)
        if orbit.isHidden { orbit.isHidden = false }
    }

    /// Hands every lit material the suns' places in the scene.
    private func light(_ f: GraphStyleFrame, position: [SIMD3<Float>], visible: [Bool]) {
        guard !lit.isEmpty else { return }
        if suns.isEmpty && litOnce { return }
        litOnce = true
        var values: [NSValue] = []
        for k in 0..<4 {
            var v = SCNVector4(x: 0, y: 0, z: 0, w: 0)
            if k < suns.count, visible[suns[k]] {
                let local: SIMD3<Float> = position[suns[k]]
                let world: SIMD4<Float> = f.toScene * SIMD4<Float>(local.x, local.y, local.z, 1)
                v = SCNVector4(x: world.x, y: world.y, z: world.z, w: 1)
            }
            values.append(NSValue(scnVector4: v))
        }
        for material in lit {
            for k in 0..<4 { material.setValue(values[k], forKey: "rpSun\(k)") }
        }
    }

    /// Each owner's place in the scene, handed to the materials it lights -
    /// only when the owner has moved more than 0.002 in the space (a star
    /// dragged, springing back or a new scene gliding in), or the space
    /// itself has turned more than about 0.01 rad in the scene since the
    /// last write (a fly-in, turning the phone). The device-tilt rig's few
    /// hundredths of a radian turn a star and its planets together, so the
    /// slightly stale light cannot be seen.
    private func lightOwned(_ f: GraphStyleFrame, position: [SIMD3<Float>]) {
        guard !owners.isEmpty else { return }
        let c0 = SIMD3<Float>(f.toScene.columns.0.x, f.toScene.columns.0.y, f.toScene.columns.0.z)
        let c1 = SIMD3<Float>(f.toScene.columns.1.x, f.toScene.columns.1.y, f.toScene.columns.1.z)
        let drift0: Float = simd_length_squared(c0 - turnShown.0)
        let drift1: Float = simd_length_squared(c1 - turnShown.1)
        let turned: Bool = drift0 > 0.0001 || drift1 > 0.0001
        if turned { turnShown = (c0, c1) }
        for (k, owner) in owners.enumerated() where owner < position.count {
            let local: SIMD3<Float> = position[owner]
            let gap: SIMD3<Float> = local - ownerShown[k]
            if !turned && simd_length_squared(gap) < 0.000_004 { continue }
            ownerShown[k] = local
            let value: NSValue = Self.sun(Self.scene(local, f))
            for material in ownedBy[k] { material.setValue(value, forKey: "rpSun0") }
        }
    }

    /// Each flying comet's own materials, lit by the nearest light.
    private func lightNearest(_ f: GraphStyleFrame, position: [SIMD3<Float>]) {
        guard !tailLights.isEmpty else { return }
        for (k, pair) in nearest.enumerated() where pair.1 < position.count {
            let p: SIMD3<Float> = position[pair.1]
            var best: Int = tailLights[0]
            var bestSquared: Float = Float.greatestFiniteMagnitude
            for s in tailLights where s < position.count {
                let d: Float = simd_distance_squared(p, position[s])
                if d < bestSquared {
                    bestSquared = d
                    best = s
                }
            }
            let world: SIMD3<Float> = Self.scene(position[best], f)
            let gap: SIMD3<Float> = world - nearestShown[k]
            if simd_length_squared(gap) < 0.000_004 { continue }
            nearestShown[k] = world
            pair.0.setValue(Self.sun(world), forKey: "rpSun0")
        }
    }

    /// A point in the space's coordinates, in the scene's.
    private static func scene(_ local: SIMD3<Float>, _ f: GraphStyleFrame) -> SIMD3<Float> {
        let world: SIMD4<Float> = f.toScene * SIMD4<Float>(local.x, local.y, local.z, 1)
        return SIMD3<Float>(world.x, world.y, world.z)
    }

    /// A light at a scene position, as a sun uniform.
    private static func sun(_ world: SIMD3<Float>) -> NSValue {
        let v = SCNVector4(x: world.x, y: world.y, z: world.z, w: 1)
        return NSValue(scnVector4: v)
    }
}
