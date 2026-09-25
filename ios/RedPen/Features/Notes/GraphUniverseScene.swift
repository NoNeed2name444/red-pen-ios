import SceneKit
import UIKit
import simd

/// Builds the Universe look (GraphUniverse) as a scene: every folder a black
/// hole or a star, every note a planet, moon, pulsar or comet, each built by
/// GraphStyleKit and moved by GraphSim at its own index.
///
///     world
///       folder:<id> (black hole or star; GraphSim moves it)
///         its orbit rings (one line circle per orbit, in the orbit's plane)
///         its gravity well (a galaxy core with notes)
///       note:<id> (planet, moon, pulsar or comet)
///       home (the home star, when there are no folders)
///       links, far links (between galaxies and to comets, fainter)
///
/// Every planet's lit materials are its own star's (GraphStyleKit caches
/// them per owner), so each terminator faces its own star and a black
/// hole's planets are lit from its disk.
@MainActor
extension GraphSceneBuilder {
    static func buildUniverse(store: NoteStore, plan: UniversePlan, edges: [(UUID, UUID)], lively: Bool,
                              bold: Bool, shaders: GraphShaderSupport, contrast: Bool,
                              folderLooks: [UUID: GraphNodeStyle]) -> GraphScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.black
        let sky: SCNNode = GraphSpace.makeSky()
        scene.rootNode.addChildNode(sky)
        let rig = SCNNode()
        rig.name = "tiltRig"
        scene.rootNode.addChildNode(rig)
        let world = SCNNode()
        rig.addChildNode(world)
        let textColor = UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1)

        // links: the approved calm beam, finer; between galaxies and to
        // comets 55% as bright, in a node of their own
        let styled: GraphStyleSupport = GraphStyleProbe.support
        let beam: Bool = styled.has("link")
        let linkMaterial: SCNMaterial = GraphStyleKit.link(bold: bold, old: shaders.link, styled: beam,
                                                           lively: lively, reach: 0.5)
        let farMaterial: SCNMaterial = GraphStyleKit.link(bold: bold, old: shaders.link, styled: beam,
                                                          lively: lively, reach: 0.5)
        let energy: Float = bold ? 0.825 : 0.55
        farMaterial.setValue(NSNumber(value: energy), forKey: "rpEnergy")
        if !beam && !shaders.link { farMaterial.diffuse.intensity = 0.55 }
        let lines = SCNNode()
        lines.name = "links"
        lines.renderingOrder = 5
        lines.categoryBitMask = 2
        world.addChildNode(lines)
        let farLines = SCNNode()
        farLines.name = "farLinks"
        farLines.renderingOrder = 5
        farLines.categoryBitMask = 2
        world.addChildNode(farLines)

        // the style shaders' noise loops: only at full liveliness and High
        let detail: Float = SpaceQuality.current() == .full ? GraphQuality.current.shaderDetail : 0
        let kit = GraphStyleKit(store: store, shaders: shaders, support: styled, lively: lively, detail: detail)
        // every folder's tone from its planned galaxy, which for a folder
        // with a missing parent or in a cycle is not the store's top level
        let galaxyTone: [Int: UIColor] = Self.galaxyTones(plan, store: store)
        var folderTone: [UUID: UIColor] = [:]
        for body in plan.bodies where body.role == .galaxy || body.role == .star {
            if let tone = galaxyTone[body.galaxy] { folderTone[body.id] = tone }
        }
        kit.tones = folderTone
        var clocked: [SCNMaterial] = []
        if shaders.link || beam {
            clocked.append(linkMaterial)
            clocked.append(farMaterial)
        }
        let hotRingMaterial = GraphLook.ring(tint: .white, hot: true, shader: shaders.ring, lively: lively)
        if shaders.ring { clocked.append(hotRingMaterial) }
        let hotRing: SCNGeometry = plane(hotRingMaterial)
        let hotDisk: SCNGeometry = plane(GraphLook.disk(tint: .white, hot: true, shader: shaders.disk))

        var noteByID: [UUID: Note] = [:]
        for note in store.notes { noteByID[note.id] = note }
        var random = SplitMix64(seed: 0x6A26)
        var infos: [GraphNodeInfo] = []
        var styles: [UUID: GraphNodeStyle] = [:]
        var folders: [UUID: Int] = [:]
        var titles: [String: Int] = [:]
        var galaxyOf: [UUID: UUID] = [:]
        for (i, body) in plan.bodies.enumerated() {
            // a folder look: by the note's planned galaxy
            let galaxyID: UUID? = body.galaxy >= 0 ? plan.bodies[body.galaxy].id : nil
            let override: GraphNodeStyle? = galaxyID.flatMap { folderLooks[$0] }
            let dress: UniverseDress = Self.dress(body, index: i, override: override)
            let note: Note? = dress.kind == .note ? noteByID[body.id] : nil
            let folder: UUID? = dress.kind == .folder ? body.id : note?.folderId
            let r: Float = body.sphere / GraphStyleKit.bodyScale(dress.style)
            let made: GraphStyledParts = kit.make(name: dress.name, folder: folder, style: dress.style, radius: r,
                                                  random: &random, look: dress.look, light: dress.light,
                                                  palette: body.palette)
            let node: SCNNode = made.node
            node.simdPosition = body.home
            let rim: UIColor? = galaxyTone[body.galaxy].map { Self.rim(tone: $0) }
            let label: SCNNode = Self.label(body.label, color: textColor, height: 1, contrast: contrast, rim: rim,
                                            cut: dress.kind == .note)
            node.addChildNode(label)
            world.addChildNode(node)

            let root: UUID? = galaxyID
            if dress.kind == .note, let galaxyID { galaxyOf[body.id] = galaxyID }
            var info = GraphNodeInfo(id: body.id, node: node, label: label, kind: note?.kind ?? .page,
                                     root: root, home: body.home, radius: made.radius,
                                     ringStretch: made.ringStretch, ringLeaf: made.ringLeaf,
                                     ringGeometry: made.ringGeometry, diskLeaf: made.diskLeaf,
                                     diskGeometry: made.diskGeometry, spin: made.spin, spinRate: made.spinRate)
            info.style = dress.style
            info.hotRing = made.hotRing
            info.hotDisk = made.hotDisk
            info.swell = made.swell
            info.stretchGain = made.stretchGain
            info.glowGain = 0.82 + 0.18 * min(Float(body.links) / 5, 1)
            info.body = dress.kind
            info.parent = body.parent
            info.orbit = body.orbit
            info.shell = body.shell
            info.light = body.light
            infos.append(info)
            styles[body.id] = dress.style
            if dress.kind != .note {
                folders[body.id] = i
                titles[body.title] = i
            }
        }

        // the orbit rings, each a child of the body it circles
        var rings: [SCNNode] = []
        var ringLooks: [Int: SCNMaterial] = [:]
        for shell in plan.shells {
            let owner: UniverseBody = plan.bodies[shell.owner]
            let galaxy: Int = owner.galaxy
            let material: SCNMaterial
            if let made = ringLooks[galaxy] {
                material = made
            } else {
                let tone: UIColor? = galaxyTone[galaxy]
                material = Self.ringMaterial(tone)
                ringLooks[galaxy] = material
            }
            let geometry: SCNGeometry = Self.circle(radius: shell.radius, u: shell.u, v: shell.v)
            geometry.materials = [material]
            let ring = SCNNode(geometry: geometry)
            ring.name = "orbitRing"
            ring.renderingOrder = 1
            ring.categoryBitMask = 2
            ring.opacity = 0.5
            infos[shell.owner].node.addChildNode(ring)
            rings.append(ring)
        }

        // a faint gravity well round each galaxy with notes, in its tone
        if kit.hasWells {
            for (i, body) in plan.bodies.enumerated() where body.role == .galaxy && !body.empty {
                let reach: Float = plan.systems[i].map { simd_length($0) }.max() ?? 1
                let side: Float = 2.2 * (reach + 0.5)
                let tone: UIColor = galaxyTone[i] ?? NoteTone.uiColor(for: body.id, in: store)
                infos[i].node.addChildNode(kit.makeWell(colour: tone, side: side))
            }
        }

        let orbit: SCNNode = kit.makeOrbit()
        world.addChildNode(orbit)
        // the kit's shared materials tick every frame; its copies per owner
        // star or comet less often (GraphSim.tickShaders)
        let split = kit.splitClocked()
        clocked.append(contentsOf: split.shared)
        var extent: Float = 1
        for p in plan.envelope { extent = max(extent, simd_length(p)) }
        let styler = GraphStyleAnimator(rigs: kit.rigs, suns: [], lit: kit.lit, orbit: orbit, extent: extent,
                                        owned: kit.owned, nearest: kit.nearest, lights: plan.lights)

        var emitters: [SCNNode] = []
        var trails: [SCNParticleSystem] = []
        if lively {
            for _ in 0..<4 {
                let system: SCNParticleSystem = GraphLook.trail(scale: 1.2)
                let emitter = SCNNode()
                emitter.categoryBitMask = 2
                emitter.renderingOrder = 7
                emitter.addParticleSystem(system)
                world.addChildNode(emitter)
                emitters.append(emitter)
                trails.append(system)
            }
        }

        // the camera: a first guess; the view frames the envelope
        let pad: Float = 0.3
        let whole = GraphWindow(aspect: 0.46, share: 1, across: 0, up: 0)
        let distance: Float = GraphFraming.distance(points: plan.envelope, pad: pad, window: whole, fill: 0.88)
        let camera = SCNCamera()
        camera.fieldOfView = Double(GraphFraming.fieldOfView)
        camera.zNear = 0.05
        let far: Float = distance * 4 + extent * 4 + 20
        camera.zFar = Double(far)
        let skyRadius: Float = far * 0.5
        sky.simdScale = SIMD3<Float>(skyRadius, skyRadius, skyRadius)
        camera.wantsHDR = false
        camera.bloomIntensity = 0
        camera.wantsExposureAdaptation = false
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3<Float>(0, 0, distance)
        scene.rootNode.addChildNode(cameraNode)

        var kinds: [String: (Int, Int)] = [:]
        for link in plan.links {
            let key: String = GraphMemory.key(plan.bodies[link.a].id, plan.bodies[link.b].id)
            kinds[key] = (link.kind, link.centre)
        }
        let universe = GraphUniverseLooks(shells: rings, shellOwner: plan.shells.map(\.owner), linkKinds: kinds,
                                          farLines: farLines, farMaterial: farMaterial)
        var simLooks = GraphSimLooks(linkMaterial: linkMaterial, hotRing: hotRing, hotDisk: hotDisk,
                                     clocked: clocked, emitters: emitters, trails: trails, sky: sky)
        simLooks.slowClocked = split.owned
        simLooks.styler = styler
        simLooks.universe = universe
        simLooks.recall = GraphMemory.recall(ids: infos.map(\.id), edges: edges, styles: styles, lively: lively)
        let sim = GraphSim(world: world, rig: rig, infos: infos, edges: edges, lines: lines, looks: simLooks,
                           lively: lively, labelReach: 5.5)
        GraphMemory.remember(sim, edges: edges, styles: styles)
        var built = GraphScene(scene: scene, camera: cameraNode, sim: sim, homes: plan.envelope, pad: pad)
        built.universe = true
        built.systems = plan.systems
        built.summary = plan.summary
        built.folders = folders
        built.containerTitles = titles
        built.dragTarget = Self.busiestStar(plan)
        built.galaxies = plan.bodies.filter { $0.role == .galaxy }.map(\.id)
        built.galaxyOf = galaxyOf
        return built
    }

    /// The depth-1 star with the most notes (ties: the lower index), for the
    /// design preview's drag; the busiest folder of any kind without one.
    private static func busiestStar(_ plan: UniversePlan) -> Int? {
        var best: Int?
        var most: Int = -1
        for (i, body) in plan.bodies.enumerated() where body.role == .star && body.tier == 1 && body.count > most {
            best = i
            most = body.count
        }
        if best != nil { return best }
        for (i, body) in plan.bodies.enumerated() where body.role != .galaxy && body.count > most {
            best = i
            most = body.count
        }
        return best
    }

    /// How a planned body is built: its style, look, light, what it is and
    /// its node's name. A folder look re-skins a galaxy's notes, each
    /// keeping its role, orbit and size.
    private static func dress(_ body: UniverseBody, index: Int, override: GraphNodeStyle?) -> UniverseDress {
        let noteName: String = "note:" + body.id.uuidString
        let folderName: String = "folder:" + body.id.uuidString
        let owner: GraphLight = .fixed(body.light)
        switch body.role {
        case .galaxy:
            return UniverseDress(style: .blackHole, look: .galaxy(empty: body.empty), light: .key, kind: .folder,
                                 name: folderName)
        case .star:
            return UniverseDress(style: .sun, look: .star(tier: body.tier, dark: body.empty), light: .key,
                                 kind: .folder, name: folderName)
        case .home:
            return UniverseDress(style: .sun, look: .star(tier: 1, dark: false), light: .key, kind: .home,
                                 name: "home")
        case .comet:
            return UniverseDress(style: .comet, look: .comet(active: true), light: .nearest(index), kind: .note,
                                 name: noteName)
        case .oort:
            return UniverseDress(style: .comet, look: .comet(active: false), light: .key, kind: .note,
                                 name: noteName)
        case .gasGiant, .rocky, .moon, .pulsar:
            let natural: (GraphNodeStyle, GraphBodyLook) = Self.natural(body)
            guard let style = override, style != natural.0 else {
                return UniverseDress(style: natural.0, look: natural.1, light: owner, kind: .note, name: noteName)
            }
            let planet: Bool = style == .rocky || style == .gasGiant
            var look: GraphBodyLook = planet ? .planet(ringed: false) : .plain
            // a black hole without its disk (2.5 times its sphere), so it
            // keeps the planet's footprint and stays smaller than its star
            if style == .blackHole { look = .galaxy(empty: true) }
            return UniverseDress(style: style, look: look, light: owner, kind: .note, name: noteName)
        }
    }

    private static func natural(_ body: UniverseBody) -> (GraphNodeStyle, GraphBodyLook) {
        switch body.role {
        case .gasGiant: return (.gasGiant, .planet(ringed: body.ringed))
        case .moon: return (.rocky, .moon)
        case .pulsar: return (.pulsar, .plain)
        default: return (.rocky, .planet(ringed: false))
        }
    }

    /// Each galaxy's tone, by its body index: a top-level folder's own
    /// (NoteTone); a galaxy the plan made of a folder whose parent is missing
    /// or sits in a cycle takes the palette's next colours after them, in
    /// name order, so each galaxy's names, rings and cores share one tone.
    private static func galaxyTones(_ plan: UniversePlan, store: NoteStore) -> [Int: UIColor] {
        let tops: [UUID] = store.subfolders(of: nil).map(\.id)
        var extra: [(String, Int)] = []
        var tones: [Int: UIColor] = [:]
        for (i, body) in plan.bodies.enumerated() where body.role == .galaxy {
            if tops.contains(body.id) {
                tones[i] = NoteTone.uiColor(for: body.id, in: store)
            } else {
                extra.append((body.title, i))
            }
        }
        extra.sort { a, b in
            if a.0 != b.0 { return a.0.localizedStandardCompare(b.0) == .orderedAscending }
            return a.1 < b.1
        }
        for (k, pair) in extra.enumerated() {
            tones[pair.1] = NoteTone.uiColor(at: tops.count + k)
        }
        return tones
    }

    /// A name pill's rim in a galaxy: the usual rim mixed half with its tone.
    static func rim(tone colour: UIColor) -> UIColor {
        let tone: SIMD3<Float> = GraphStyleArt.components(colour)
        let base: SIMD3<Float> = GraphStyleArt.components(rimFill)
        let mixed: SIMD3<Float> = (tone + base) * 0.5
        return UIColor(red: CGFloat(mixed.x), green: CGFloat(mixed.y), blue: CGFloat(mixed.z), alpha: 1)
    }

    /// An orbit ring's look: faint, added, never hiding what is behind it;
    /// the galaxy's tone half mixed with white at half strength, grey round
    /// the home star.
    private static func ringMaterial(_ tone: UIColor?) -> SCNMaterial {
        var colour = SIMD3<Float>(0.35, 0.37, 0.42)
        if let tone {
            let c: SIMD3<Float> = GraphStyleArt.components(tone)
            let white = SIMD3<Float>(1, 1, 1)
            colour = (c + white) * 0.25
        }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: CGFloat(colour.x), green: CGFloat(colour.y),
                                            blue: CGFloat(colour.z), alpha: 1)
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        return material
    }

    /// A 96-segment line circle of `radius` in the plane of `u` and `v`.
    static func circle(radius: Float, u: SIMD3<Float>, v: SIMD3<Float>) -> SCNGeometry {
        let count: Int = 96
        var points: [SCNVector3] = []
        points.reserveCapacity(count)
        for k in 0..<count {
            let angle: Float = Float(k) * 2 * Float.pi / Float(count)
            let x: SIMD3<Float> = u * (cos(angle) * radius)
            let y: SIMD3<Float> = v * (sin(angle) * radius)
            let p: SIMD3<Float> = x + y
            points.append(SCNVector3(x: p.x, y: p.y, z: p.z))
        }
        var indices: [Int32] = []
        indices.reserveCapacity(count * 2)
        for k in 0..<count {
            indices.append(Int32(k))
            indices.append(Int32((k + 1) % count))
        }
        let source = SCNGeometrySource(vertices: points)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        return SCNGeometry(sources: [source], elements: [element])
    }
}

/// How one planned body is built (GraphSceneBuilder.buildUniverse).
struct UniverseDress {
    let style: GraphNodeStyle
    let look: GraphBodyLook
    let light: GraphLight
    let kind: GraphBodyKind
    let name: String
}
