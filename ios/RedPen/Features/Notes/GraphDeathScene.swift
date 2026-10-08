import SceneKit
import UIKit
import Metal
import simd

// MARK: - Bodies leaving the map (the effects)
//
// GraphDeath plans each death; this plays it. When a rebuild finds bodies
// on the scene still showing that the new one no longer has (a note or
// folder deleted), GraphMemory hands them over (GraphDeparture): a copy of
// each body's node, where it was and how big, what it was and whom it was
// linked to. GraphDeathStage then, in the new scene's world:
//
// - puts each copy back where it was, named "dying" and in category 2, so
//   it can be neither picked nor hit: the new map is live under it at once;
// - runs its body's curves (GraphDeath.scale, .opacity; a pulsar's spin)
//   and its effect's pieces - billboard glows and rings, and a few particle
//   systems whose starts are delayed to their phase - as SCNActions, so
//   they play on SceneKit's own clock whatever the simulation is doing;
// - draws its links drawing back into it (a small ribbon writer of its own,
//   from the new scene's positions each frame, stepped by GraphSim);
// - and removes every node it made once its death is over.
//
// Each dying body costs a handful of draws for a second or two (a few
// billboards, at most three particle systems), and only the biggest few
// dying at once get a full effect (GraphDeath.plans): the rest shrink and
// fade.

/// A body the scene being replaced showed and the new one has not.
struct GraphDeparture {
    let id: UUID
    /// A copy of its node as it was drawn (the old scene keeps its own).
    let node: SCNNode
    /// Where it was, in the space's own coordinates, and how big it was
    /// drawn (its radius times its pop).
    let position: SIMD3<Float>
    let radius: Float
    let scale: Float
    let kind: GraphDeathKind
    let count: Int
    /// Its style code, for its links' look.
    let code: Int
    /// Whom it was linked to, and each link's seed.
    let partners: [(UUID, Int)]
    /// Where the container it sat in is, when that container stays: if it
    /// is only hidden (a Neurons cell closing), it folds back into it there
    /// instead of dying.
    var into: SIMD3<Float>? = nil
}

/// How the links of the scene they die in look, for the dying links.
struct GraphDeathLinks {
    let material: SCNMaterial
    let halfWidth: Float
    var seeded: Bool = false
    var arbor: GraphLinkArbor? = nil
    var bridge: GraphLinkBridge? = nil
}

/// The deaths playing in one scene (made on the main thread when it is
/// built; its links stepped by GraphSim on the render thread).
nonisolated final class GraphDeathStage: @unchecked Sendable {
    private let dying: [GraphDeparture]
    private let plans: [GraphDeathPlan]
    private let lines: SCNNode
    private let look: GraphDeathLinks
    private let lively: Bool
    private var writer: GraphRibbonWriter?
    /// Each dying link: its dying end, its other end (an index in the new
    /// scene, or -1), or another dying body (or -1), and its seed.
    private var links: [(Int, Int, Int, Int)] = []
    private var elapsed: Double = 0
    private let longest: Double
    private(set) var finished: Bool = false
    private var slots: [SIMD3<Float>] = []
    private var slotRadius: [Float] = []
    private var slotCode: [Int] = []
    private var ribbons: [GraphRibbonLink] = []

    /// Each dying body's flash now, for what is behind the name pills
    /// (GraphLabelContrast.swift): where it is, its radius, how bright the
    /// flash is (0...1) and how many radii it reaches. Render thread, with
    /// GraphSim's lock held.
    func flashes() -> [(SIMD3<Float>, Float, Double, Double)] {
        guard !finished else { return [] }
        var out: [(SIMD3<Float>, Float, Double, Double)] = []
        for (k, d) in dying.enumerated() where k < plans.count {
            let plan: GraphDeathPlan = plans[k]
            let flash: (Double, Double) = GraphShine.deathFlash(plan.effect.rawValue, t: elapsed,
                                                                duration: plan.duration)
            guard flash.0 > 0.02 else { continue }
            out.append((d.position, max(d.radius, 0.02), flash.0, flash.1))
        }
        return out
    }

    /// The deaths for a new scene whose bodies are `keeping`, or nil when
    /// none of the scene being replaced's bodies has gone. `hidden` are
    /// ones still in the vault that the new scene does not show (inside a
    /// closed cell): they fold back into their container, not die.
    @MainActor
    static func make(world: SCNNode, keeping: Set<UUID>, key: String, lively: Bool,
                     links: GraphDeathLinks, hidden: Set<UUID> = []) -> GraphDeathStage? {
        let leaving: [GraphDeparture] = GraphMemory.leaving(keeping: keeping, key: key)
        // a closed cell's parts and notes fold back into it, staggered
        // innermost last; only what was deleted dies
        var folded: Int = 0
        for d in leaving {
            guard let into = d.into, hidden.contains(d.id) else { continue }
            GraphDeathArt.fold(d, into: into, wait: lively ? min(Double(folded) * 0.02, 0.4) : 0, lively: lively,
                               in: world)
            folded += 1
        }
        let gone: [GraphDeparture] = leaving.filter { $0.into == nil || !hidden.contains($0.id) }
        guard !gone.isEmpty else { return nil }
        let still: Bool = !lively
        let smooth: Bool = GraphQuality.current.tier != .high
        let inputs: [GraphDeathInput] = gone.map {
            GraphDeathInput(kind: $0.kind, radius: $0.radius, count: $0.count)
        }
        let plans: [GraphDeathPlan] = GraphDeath.plans(inputs, still: still, smooth: smooth)
        return GraphDeathStage(dying: gone, plans: plans, world: world, lively: lively, look: links)
    }

    @MainActor
    init(dying: [GraphDeparture], plans: [GraphDeathPlan], world: SCNNode, lively: Bool, look: GraphDeathLinks) {
        self.dying = dying
        self.plans = plans
        self.lively = lively
        self.look = look
        var most: Double = 0
        for p in plans { most = max(most, p.duration) }
        longest = most
        let node = SCNNode()
        node.name = "dyingLinks"
        node.renderingOrder = 5
        node.categoryBitMask = 2
        world.addChildNode(node)
        lines = node
        for (k, d) in dying.enumerated() {
            GraphDeathArt.play(d, plan: plans[k], in: world)
        }
    }

    /// Finds each dying link's other end in the new scene (by id; one
    /// dying too is joined to it), and makes the writers. Main thread, from
    /// GraphSim's init.
    func resolve(index: [UUID: Int], fence: GraphFrameFence) {
        var dyingAt: [UUID: Int] = [:]
        for (k, d) in dying.enumerated() { dyingAt[d.id] = k }
        var seen = Set<String>()
        for (k, d) in dying.enumerated() {
            for (other, seed) in d.partners {
                if let j = index[other] {
                    links.append((k, j, -1, seed))
                } else if let m = dyingAt[other] {
                    let key: String = GraphMemory.key(d.id, other)
                    guard seen.insert(key).inserted else { continue }
                    links.append((k, -1, m, seed))
                }
            }
        }
        let budget: GraphicsBudget = GraphQuality.current
        writer = GraphRibbonWriter(halfWidth: look.halfWidth, material: look.material, samples: budget.linkSamples,
                                   expected: links.count, seeded: look.seeded, fence: fence, arbor: look.arbor,
                                   bridge: look.bridge)
    }

    /// One frame of the links drawing back into their dying bodies. Render
    /// thread, with GraphSim's lock held; `position`, `radius` and `codes`
    /// are the new scene's.
    func step(_ dt: Float, position: [SIMD3<Float>], radius: [Float], codes: [Int], eye: SIMD3<Float>,
              device: MTLDevice?) {
        guard !finished else { return }
        elapsed += Double(max(dt, 0))
        slots.removeAll(keepingCapacity: true)
        slotRadius.removeAll(keepingCapacity: true)
        slotCode.removeAll(keepingCapacity: true)
        ribbons.removeAll(keepingCapacity: true)
        for (k, d) in dying.enumerated() {
            let s: SIMD2<Float> = GraphDeath.scale(plans[k], at: elapsed)
            slots.append(d.position)
            slotRadius.append(d.radius * max(s.y, 0.05))
            slotCode.append(d.code)
        }
        for (d, other, mate, seed) in links {
            var reach: Float = GraphDeath.linkReach(plans[d], at: elapsed)
            if !lively { reach = elapsed < plans[d].duration ? 1 : 0 }
            guard reach > 0.001 else { continue }
            var b: Int = mate
            if other >= 0 {
                guard other < position.count else { continue }
                b = slots.count
                slots.append(position[other])
                slotRadius.append(other < radius.count ? radius[other] : 0.1)
                slotCode.append(other < codes.count ? codes[other] : 0)
            } else if mate >= 0 {
                reach = min(reach, GraphDeath.linkReach(plans[mate], at: elapsed))
            }
            guard b >= 0 else { continue }
            ribbons.append(GraphRibbonLink(a: d, b: b, seed: seed, grow: reach))
        }
        if !lively {
            let fade: Double = min(elapsed / max(longest, 0.01), 1)
            lines.opacity = CGFloat(1 - fade)
        } else {
            lines.opacity = 1
        }
        let geometry: SCNGeometry? = writer?.write(links: ribbons, position: slots, radius: slotRadius,
                                                   codes: slotCode, axis: nil, focus: -1, eye: eye, device: device)
        if lines.geometry !== geometry { lines.geometry = geometry }
        if elapsed > longest + 0.1 {
            finished = true
            lines.geometry = nil
        }
    }
}

// MARK: - The pieces

/// Builds and runs one death's pieces. Main thread.
@MainActor
enum GraphDeathArt {
    /// Puts the dying body's copy back, runs its curves and its effect, and
    /// clears everything away after.
    static func play(_ d: GraphDeparture, plan: GraphDeathPlan, in world: SCNNode) {
        let r: Float = max(d.radius, 0.02)
        // the body's copy, in a holder turned so its x is the tidal pull
        let holder = SCNNode()
        holder.name = "dying"
        holder.categoryBitMask = 2
        holder.simdPosition = d.position
        let axis: SIMD3<Float> = tidalAxis(d)
        let turn = simd_quatf(from: SIMD3<Float>(1, 0, 0), to: axis)
        holder.simdOrientation = turn
        let body: SCNNode = d.node
        body.name = "dying"
        body.simdPosition = SIMD3<Float>(0, 0, 0)
        body.simdOrientation = turn.inverse
        quiet(body)
        holder.addChildNode(body)
        world.addChildNode(holder)
        let base: Float = d.scale
        let spinning: Bool = plan.effect == .spinDown
        let life: TimeInterval = plan.duration
        let curve = SCNAction.customAction(duration: life) { _, e in
            let t: Double = Double(e)
            let s: SIMD2<Float> = GraphDeath.scale(plan, at: t)
            let size: Float = max(base, 0.001)
            holder.simdScale = SIMD3<Float>(max(s.x * size, 0.0005), max(s.y * size, 0.0005), max(s.y * size, 0.0005))
            holder.opacity = CGFloat(GraphDeath.opacity(plan, at: t))
            if spinning {
                // spun down: the angle is the integral of (1 - x)^2
                let x: Double = plan.progress("spin", at: t)
                let span: Double = (plan.phase("spin")?.end ?? 1.6)
                let angle: Double = 9 * span * (1 - pow(1 - x, 3)) / 3
                body.simdOrientation = turn.inverse * simd_quatf(angle: Float(angle), axis: SIMD3<Float>(0, 1, 0))
            }
        }
        holder.runAction(SCNAction.sequence([curve, SCNAction.removeFromParentNode()]))
        // the effect, round the body's centre
        let fx = SCNNode()
        fx.name = "dyingEffect"
        fx.categoryBitMask = 2
        fx.simdPosition = d.position
        world.addChildNode(fx)
        effect(plan, radius: r, axis: axis, in: fx)
        let tail: TimeInterval = life + 1.6
        fx.runAction(SCNAction.sequence([SCNAction.wait(duration: tail), SCNAction.removeFromParentNode()]))
    }

    /// A body whose container closed: it shrinks as it glides back into
    /// the container's centre, then goes. Still: it simply goes.
    static func fold(_ d: GraphDeparture, into: SIMD3<Float>, wait: Double, lively: Bool, in world: SCNNode) {
        guard lively else { return }
        let body: SCNNode = d.node
        body.name = "folding"
        quiet(body)
        body.simdPosition = d.position
        let size: Float = max(d.scale, 0.001)
        body.simdScale = SIMD3<Float>(size, size, size)
        world.addChildNode(body)
        let from: SIMD3<Float> = d.position
        let life: TimeInterval = 0.55
        let curve = SCNAction.customAction(duration: life) { node, e in
            let x: Float = Float(min(max(Double(e) / life, 0), 1))
            let t: Float = x * x * (3 - 2 * x)
            node.simdPosition = from + (into - from) * t
            let s: Float = max(size * (1 - t), 0.0005)
            node.simdScale = SIMD3<Float>(s, s, s)
            node.opacity = CGFloat(1 - 0.6 * t)
        }
        body.runAction(SCNAction.sequence([SCNAction.wait(duration: wait), curve,
                                           SCNAction.removeFromParentNode()]))
    }

    /// Everything in the copy unpickable and nameless.
    private static func quiet(_ node: SCNNode) {
        node.categoryBitMask = 2
        if node.name == "label" {
            node.isHidden = true
        }
        for child in node.childNodes { quiet(child) }
    }

    /// The way the tides pull: towards its first partner, or a fixed tilt.
    private static func tidalAxis(_ d: GraphDeparture) -> SIMD3<Float> {
        let seed: Float = Float(GraphUniverse.fnv(d.id.uuidString) % 1000) / 1000
        let a: Float = seed * 6.2831853
        return simd_normalize(SIMD3<Float>(cos(a), 0.35, sin(a)))
    }

    private static func effect(_ plan: GraphDeathPlan, radius r: Float, axis: SIMD3<Float>, in fx: SCNNode) {
        let n: Int = plan.particles
        switch plan.effect {
        case .tidalDisruption:
            let ring: SCNNode = flatRing(colour: SIMD3<Float>(0.85, 0.7, 0.55), axis: axis)
            fx.addChildNode(ring)
            grow(ring, plan: plan, phase: "ring", from: 1.2 * r, to: 5 * r, peak: 0.8)
            let debris = SCNParticleSystem.death(count: n, start: 0.55, over: 0.15, life: 1.2, size: 0.14 * r,
                                                 speed: 0.9 * r, colour: SIMD3<Float>(0.9, 0.72, 0.5))
            debris.emitterShape = SCNTorus(ringRadius: CGFloat(1.4 * r), pipeRadius: CGFloat(0.3 * r))
            debris.birthDirection = .surfaceNormal
            let emitter = SCNNode()
            emitter.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_cross(axis, SIMD3<Float>(0, 0, 1)))
            emitter.addParticleSystem(debris)
            fx.addChildNode(emitter)
        case .atmosphereStripped:
            let shell: SCNNode = glow(colour: SIMD3<Float>(0.95, 0.75, 0.45))
            fx.addChildNode(shell)
            grow(shell, plan: plan, phase: "strip", from: 2.6 * r, to: 6.5 * r, peak: 0.7)
            let wind = SCNParticleSystem.death(count: n, start: 0, over: 1.2, life: 1.0, size: 0.18 * r,
                                               speed: 0.6 * r, colour: SIMD3<Float>(0.95, 0.78, 0.5))
            wind.emitterShape = SCNSphere(radius: CGFloat(r))
            wind.birthLocation = .surface
            wind.birthDirection = .surfaceNormal
            let push: SIMD3<Float> = axis * (2.2 * r)
            wind.acceleration = SCNVector3(x: push.x, y: push.y, z: push.z)
            fx.addParticleSystem(wind)
        case .planetaryNebula:
            let giant: SCNNode = glow(colour: SIMD3<Float>(1.0, 0.45, 0.2))
            fx.addChildNode(giant)
            grow(giant, plan: plan, phase: "swell", from: 2.2 * r, to: 3.4 * r, peak: 0.9)
            let nebula: SCNNode = billboardRing(colour: SIMD3<Float>(0.45, 0.95, 0.85))
            fx.addChildNode(nebula)
            grow(nebula, plan: plan, phase: "puff", from: 1.5 * r, to: 7 * r, peak: 0.85)
            let dwarf: SCNNode = glow(colour: SIMD3<Float>(0.9, 0.95, 1.0))
            fx.addChildNode(dwarf)
            grow(dwarf, plan: plan, phase: "dwarf", from: 1.2 * r, to: 0.7 * r, peak: 1.0)
            let gas = SCNParticleSystem.death(count: n, start: 0.65, over: 0.4, life: 1.6, size: 0.3 * r,
                                              speed: 1.4 * r, colour: SIMD3<Float>(1.0, 0.55, 0.75))
            gas.emitterShape = SCNSphere(radius: CGFloat(r))
            gas.birthLocation = .surface
            gas.birthDirection = .surfaceNormal
            fx.addParticleSystem(gas)
        case .supernova:
            let flash: SCNNode = glow(colour: SIMD3<Float>(1.0, 0.97, 0.9))
            fx.addChildNode(flash)
            grow(flash, plan: plan, phase: "flash", from: 1 * r, to: 11 * r, peak: 1.0, early: 0.2)
            let shock: SCNNode = billboardRing(colour: SIMD3<Float>(0.7, 0.85, 1.0))
            fx.addChildNode(shock)
            grow(shock, plan: plan, phase: "shock", from: 2 * r, to: 15 * r, peak: 0.9)
            let ejecta = SCNParticleSystem.death(count: n, start: 0.27, over: 0.08, life: 1.3, size: 0.2 * r,
                                                 speed: 7 * r, colour: SIMD3<Float>(1.0, 0.8, 0.5))
            ejecta.emitterShape = SCNSphere(radius: CGFloat(r * 0.5))
            ejecta.birthDirection = .surfaceNormal
            ejecta.dampingFactor = 1.2
            fx.addParticleSystem(ejecta)
        case .evaporation:
            let hawking: SCNNode = glow(colour: SIMD3<Float>(0.75, 0.85, 1.0))
            fx.addChildNode(hawking)
            let life: TimeInterval = plan.duration
            let hot = SCNAction.customAction(duration: life) { node, e in
                let t: Double = Double(e)
                let x: Double = plan.progress("shrink", at: t)
                let pop: Double = plan.progress("pop", at: t)
                let left: Double = pow(max(1 - x, 0), 1.0 / 3.0)
                let rr: Double = Double(r)
                let body: Double = rr * (3.2 * left + 0.6)
                let burst: Double = rr * 6 * sin(pop * Double.pi)
                let size: Float = Float(body + burst)
                node.simdScale = SIMD3<Float>(size, size, 1)
                let heat: Double = 0.25 + 0.75 * x * x
                let flash: Double = pop > 0 ? 1 - pop : 0
                node.opacity = CGFloat(min(heat + flash, 1))
            }
            hawking.runAction(SCNAction.sequence([hot, SCNAction.fadeOut(duration: 0.15)]))
            let burst = SCNParticleSystem.death(count: n, start: 1.7, over: 0.06, life: 0.7, size: 0.12 * r,
                                                speed: 5 * r, colour: SIMD3<Float>(0.85, 0.9, 1.0))
            burst.emitterShape = SCNSphere(radius: CGFloat(r * 0.2))
            burst.birthDirection = .surfaceNormal
            fx.addParticleSystem(burst)
        case .spinDown:
            let beams: SCNNode = glow(colour: SIMD3<Float>(0.7, 0.8, 1.0))
            fx.addChildNode(beams)
            grow(beams, plan: plan, phase: "spin", from: 3 * r, to: 1.5 * r, peak: 0.6, early: 0.99)
        case .cometBreakup:
            let coma: SCNNode = glow(colour: SIMD3<Float>(0.55, 1.0, 0.9))
            fx.addChildNode(coma)
            grow(coma, plan: plan, phase: "gas", from: 2 * r, to: 5.5 * r, peak: 0.7)
            let bits = SCNParticleSystem.death(count: max(n / 4, 6), start: 0.3, over: 0.1, life: 1.5,
                                               size: 0.35 * r, speed: 0.9 * r, colour: SIMD3<Float>(0.8, 0.95, 1.0))
            bits.emitterShape = SCNSphere(radius: CGFloat(r * 0.6))
            bits.birthDirection = .surfaceNormal
            bits.dampingFactor = 0.6
            fx.addParticleSystem(bits)
            let dust = SCNParticleSystem.death(count: n, start: 0.35, over: 1.0, life: 0.9, size: 0.12 * r,
                                               speed: 1.2 * r, colour: SIMD3<Float>(0.6, 1.0, 0.95))
            dust.emitterShape = SCNSphere(radius: CGFloat(r))
            dust.birthLocation = .surface
            dust.birthDirection = .surfaceNormal
            fx.addParticleSystem(dust)
        case .apoptosis:
            let tint = SIMD3<Float>(0.55, 0.95, 0.88)
            let blebs = SCNParticleSystem.death(count: max(n / 3, 6), start: 0.3, over: 0.6, life: 0.7,
                                                size: 0.4 * r, speed: 0, colour: tint)
            blebs.emitterShape = SCNSphere(radius: CGFloat(r * 0.8))
            blebs.birthLocation = .surface
            blebs.propertyControllers = [.size: SCNParticlePropertyController(animation: keys([0, 1, 0.7])),
                                         .opacity: SCNParticlePropertyController(animation: keys([0, 0.9, 0]))]
            fx.addParticleSystem(blebs)
            let bodies = SCNParticleSystem.death(count: max(n / 2, 6), start: 1.2, over: 0.25, life: 1.0,
                                                 size: 0.32 * r, speed: 0.6 * r, colour: tint)
            bodies.emitterShape = SCNSphere(radius: CGFloat(r * 0.6))
            bodies.birthLocation = .surface
            bodies.birthDirection = .surfaceNormal
            bodies.dampingFactor = 1.5
            fx.addParticleSystem(bodies)
            // the nucleus: condensing, then breaking into beads
            for k in 0..<3 {
                let bead: SCNNode = glow(colour: SIMD3<Float>(0.55, 0.6, 1.0))
                fx.addChildNode(bead)
                let a: Float = Float(k) * 2.094
                let out = SIMD3<Float>(cos(a), sin(a), 0.3) * (0.45 * r)
                let life: TimeInterval = plan.duration
                let move = SCNAction.customAction(duration: life) { node, e in
                    let t: Double = Double(e)
                    let c: Double = plan.progress("condense", at: t)
                    let f: Double = GraphDeath.smooth(plan.progress("fragment", at: t))
                    let gone: Double = GraphDeath.smooth(plan.progress("bodies", at: t))
                    let size: Float = r * Float(1.4 - 0.8 * c - 0.2 * f)
                    node.simdScale = SIMD3<Float>(size, size, 1)
                    node.simdPosition = out * Float(f)
                    let show: Double = k == 0 ? 1 : f
                    node.opacity = CGFloat(min(c * 3, 1) * show * (1 - gone))
                }
                bead.opacity = 0
                bead.runAction(move)
            }
        case .fade:
            break
        }
    }

    /// A glow that swells from `from` to `to` over `phase`, brightening to
    /// `peak` by `early` of it and fading out by its end.
    private static func grow(_ node: SCNNode, plan: GraphDeathPlan, phase: String, from: Float, to: Float,
                             peak: Float, early: Double = 0.25) {
        node.opacity = 0
        let life: TimeInterval = plan.duration
        let run = SCNAction.customAction(duration: life) { n, e in
            let x: Double = plan.progress(phase, at: Double(e))
            let eased: Float = Float(GraphDeath.smooth(x))
            let size: Float = from + (to - from) * (1 - (1 - eased) * (1 - eased))
            n.simdScale = SIMD3<Float>(size, size, size)
            let up: Double = min(x / max(early, 0.001), 1)
            let down: Double = x <= early ? 1 : 1 - GraphDeath.smooth((x - early) / max(1 - early, 0.001))
            let live: Double = plan.phase(phase).map { Double(e) >= $0.start } == true ? 1 : 0
            n.opacity = CGFloat(Double(peak) * up * down * live)
        }
        node.runAction(run)
    }

    /// A soft additive glow, facing the camera, one unit across.
    private static func glow(colour: SIMD3<Float>) -> SCNNode {
        let plane = SCNPlane(width: 1, height: 1)
        plane.materials = [GraphDeathArt.additive(GraphStyleArt.glow, colour: colour)]
        let node = SCNNode(geometry: plane)
        node.categoryBitMask = 2
        node.renderingOrder = 9
        let face = SCNBillboardConstraint()
        face.freeAxes = .all
        node.constraints = [face]
        return node
    }

    /// A ring (a planetary nebula, a shock shell) facing the camera.
    private static func billboardRing(colour: SIMD3<Float>) -> SCNNode {
        let node: SCNNode = flatRing(colour: colour, axis: SIMD3<Float>(0, 0, 1))
        let face = SCNBillboardConstraint()
        face.freeAxes = .all
        node.constraints = [face]
        return node
    }

    /// A ring lying square to `axis` (a debris ring).
    private static func flatRing(colour: SIMD3<Float>, axis: SIMD3<Float>) -> SCNNode {
        let plane = SCNPlane(width: 1, height: 1)
        let look: SCNMaterial = GraphDeathArt.additive(GraphArt.ring, colour: colour)
        look.isDoubleSided = true
        plane.materials = [look]
        let node = SCNNode(geometry: plane)
        node.categoryBitMask = 2
        node.renderingOrder = 9
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: axis)
        return node
    }

    /// Unlit, added, depth-tested but never written.
    static func additive(_ image: UIImage, colour: SIMD3<Float>) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.multiply.contents = UIColor(red: CGFloat(colour.x), green: CGFloat(colour.y),
                                             blue: CGFloat(colour.z), alpha: 1)
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        return material
    }

    /// A particle property's keyframes over its life, evenly spaced.
    private static func keys(_ values: [Double]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation()
        animation.values = values.map { NSNumber(value: $0) }
        let last: Double = Double(max(values.count - 1, 1))
        animation.keyTimes = values.indices.map { NSNumber(value: Double($0) / last) }
        return animation
    }
}

extension SCNParticleSystem {
    /// A one-off burst for a death: `count` particles over `over` seconds,
    /// starting `start` seconds in, each living `life`, fading as it goes.
    @MainActor
    static func death(count: Int, start: Double, over: Double, life: Double, size: Float, speed: Float,
                      colour: SIMD3<Float>) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        let span: Double = max(over, 0.02)
        system.loops = false
        system.idleDuration = CGFloat(start)
        system.emissionDuration = CGFloat(span)
        system.birthRate = CGFloat(Double(max(count, 1)) / span)
        system.particleLifeSpan = CGFloat(life)
        system.particleLifeSpanVariation = CGFloat(life * 0.3)
        system.particleSize = CGFloat(size)
        system.particleSizeVariation = CGFloat(size * 0.4)
        system.particleVelocity = CGFloat(speed)
        system.particleVelocityVariation = CGFloat(speed * 0.5)
        system.spreadingAngle = 30
        system.particleImage = GraphArt.spark
        system.particleColor = UIColor(red: CGFloat(colour.x), green: CGFloat(colour.y), blue: CGFloat(colour.z),
                                       alpha: 1)
        system.blendMode = .additive
        system.isLightingEnabled = false
        system.isAffectedByGravity = false
        system.isLocal = false
        system.sortingMode = .none
        let fade = CAKeyframeAnimation()
        fade.values = [NSNumber(value: 1.0), NSNumber(value: 0.7), NSNumber(value: 0.0)]
        fade.keyTimes = [NSNumber(value: 0.0), NSNumber(value: 0.5), NSNumber(value: 1.0)]
        system.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        return system
    }
}
