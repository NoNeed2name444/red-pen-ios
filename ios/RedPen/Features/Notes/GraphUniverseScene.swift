import SceneKit
import UIKit
import simd

/// Builds the Universe look (GraphUniverse) as a scene: every folder a black
/// hole or a star, every note a planet, moon, pulsar or comet, each built by
/// GraphStyleKit and moved by GraphSim at its own index.
///
///     world
///       folder:<id> (black hole or star; GraphSim moves it)
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
            // stars and planets drawn a fifth past their planned sphere
            // (owner-ref-1's big bodies); the plan's room round each still
            // clears them, at the shortest links too. A ringed giant keeps
            // its size so its ring stays inside its room; moons, comets,
            // pulsars and black holes keep theirs.
            var grow: Float = 1
            switch dress.look {
            case .star, .planet(ringed: false): grow = 1.2
            default: break
            }
            let r: Float = body.sphere * grow / GraphStyleKit.bodyScale(dress.style)
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
            info.count = body.count
            info.deathKind = override != nil && dress.kind == .note
                ? GraphDeath.kind(style: dress.style.rawValue)
                : GraphDeath.kind(universeRole: body.role.rawValue, count: body.count)
            info.orbit = body.orbit
            info.shell = body.shell
            info.light = body.light
            info.shine = GraphShine.universe(body.role.rawValue, empty: body.empty, tier: body.tier)
            infos.append(info)
            styles[body.id] = dress.style
            if dress.kind != .note {
                folders[body.id] = i
                titles[body.title] = i
            }
        }

        // no orbit rings or gravity wells: each body is one piece, its glow
        // and its beams part of it (owner-ref-1)
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
        var universe = GraphUniverseLooks(shells: [], shellOwner: [], linkKinds: kinds,
                                          farLines: farLines, farMaterial: farMaterial)
        // fine beams that start inside each body, so they leave its limb
        // (the body hides the rest); a black hole's at its horizon, where
        // they flash, a pulsar's and a comet's at their glow's edge
        universe.halfWidth = 0.07
        universe.farHalfWidth = 0.07
        universe.trims = [1.0, 0.72, 0.72, 1.0, 1.0, 0.75]
        var simLooks = GraphSimLooks(linkMaterial: linkMaterial, hotRing: hotRing, hotDisk: hotDisk,
                                     clocked: clocked, emitters: emitters, trails: trails, sky: sky)
        simLooks.slowClocked = split.owned
        simLooks.styler = styler
        simLooks.universe = universe
        simLooks.recall = GraphMemory.recall(ids: infos.map(\.id), edges: edges, styles: styles, lively: lively)
        // bodies deleted since the scene on screen die in this one
        let key: String = "universe"
        let dyingLinks = GraphDeathLinks(material: linkMaterial, halfWidth: universe.halfWidth)
        simLooks.dying = GraphDeathStage.make(world: world, keeping: Set(infos.map(\.id)), key: key,
                                              lively: lively, links: dyingLinks)
        let sim = GraphSim(world: world, rig: rig, infos: infos, edges: edges, lines: lines, looks: simLooks,
                           lively: lively, labelReach: 5.5)
        GraphMemory.remember(sim, edges: edges, styles: styles, key: key)
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
}

/// How one planned body is built (GraphSceneBuilder.buildUniverse).
struct UniverseDress {
    let style: GraphNodeStyle
    let look: GraphBodyLook
    let light: GraphLight
    let kind: GraphBodyKind
    let name: String
}
