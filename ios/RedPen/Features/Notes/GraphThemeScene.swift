import SceneKit
import UIKit
import simd

// MARK: - The themes' shared scene
//
// Every theme other than Space (GraphTheme) is planned into a ThemePlan by
// its own Foundation planner and built here, the same way for all of them:
//
//     world
//       folder:<id> / note:<id> / home   (each body, as its look makes it;
//                                          GraphSim moves it at its index)
//         its look's pieces, a halo on GraphSim's ring leaf, a glow
//         its name pill
//       links       (one geometry, the look's link material)
//       far links   (tracts between regions, to loose notes, and pathways)
//
// and run by GraphSim exactly as the Universe is (universe = true): every
// body springs to its parent's live position plus its orbit's offset, so a
// dragged container carries everything inside it; names, picking, the
// filter, fly-in and double taps all work unchanged. What differs is only
// the look (GraphThemeLook): the bodies' nodes, the link materials and
// widths, the sky, and whatever it runs each frame (GraphThemeTicker).
//
// A new theme adds its planner and look to GraphThemes, its legend to
// GraphLegendContent, and flips GraphTheme.isReady - nothing here changes.
// A look may also route its links on a board (GraphThemeLook.board: the
// Circuit's traces) and add pieces of its own to the world (decorate: the
// Circuit's motherboard).

/// One body as a theme's look builds it. GraphSim drives the ring pieces as
/// it does a planet's: `ringStretch` (inside a billboarded holder) is
/// squashed along the motion and faded with it, `ringLeaf` carries the
/// halo (swapped for the look's hot halo while chosen); `diskLeaf` is spun.
struct GraphThemeParts {
    let node: SCNNode
    /// How far links are trimmed from its centre (times GraphShape.linkTrim)
    /// and how far it can be picked.
    let radius: Float
    let ringStretch: SCNNode
    let ringLeaf: SCNNode
    let ringGeometry: SCNGeometry
    let diskLeaf: SCNNode
    /// Lit by the look's ticker (the Neurons: an impulse arriving).
    var glow: SCNNode? = nil
    /// One of the many small bodies whose halo GraphSim may hide when it is
    /// tiny on screen in a crowded map (the Universe's rocky planets).
    var thinnable: Bool = false
}

extension GraphThemeParts {
    /// The ring geometry of a body with no standing halo: nothing to draw
    /// (no draw call), while GraphSim can still put the chosen body's hot
    /// ring on the leaf and put this back after.
    static let noHalo: SCNGeometry = SCNGeometry()
}

/// A theme's look: everything the shared scene needs from it.
@MainActor
protocol GraphThemeLook: AnyObject {
    var theme: GraphTheme { get }
    /// The backdrop, kept round the camera by GraphSim and scaled by the
    /// builder.
    func makeSky() -> SCNNode
    var linkMaterial: SCNMaterial { get }
    var farMaterial: SCNMaterial { get }
    var linkHalfWidth: Float { get }
    var farHalfWidth: Float { get }
    /// The chosen body's halo (a unit plane; each leaf is scaled to size).
    var hotRing: SCNGeometry { get }
    /// Materials whose shaders read `rpClock`, set by GraphSim each frame.
    var clocked: [SCNMaterial] { get }
    /// Body `index` of `plan`, its node named "note:<id>", "folder:<id>"
    /// or "home".
    func makeBody(_ body: ThemeBody, index: Int, plan: ThemePlan) -> GraphThemeParts
    /// A region's colour, for its name pills' rims (nil: the usual rim).
    func tone(region: Int, plan: ThemePlan) -> UIColor?
    /// What runs each frame on the render thread, made once every body is.
    func ticker(parts: [GraphThemeParts], plan: ThemePlan) -> GraphThemeTicker?
    /// A board the links are routed on, flat, square to its edges (the
    /// Circuit); nil (the default) draws them as camera-facing beams.
    var board: GraphLinkBoard? { get }
    /// Anything the look adds to the world beside the bodies (the Circuit:
    /// the motherboard under everything). Nothing by default.
    func decorate(world: SCNNode, plan: ThemePlan)
}

extension GraphThemeLook {
    var board: GraphLinkBoard? { nil }
    func decorate(world: SCNNode, plan: ThemePlan) {}
}

/// Which planner and look each theme has.
@MainActor
enum GraphThemes {
    /// The theme's plan (nil for Space, planned by GraphUniverse, and for a
    /// theme not built yet). Called off the main thread.
    nonisolated static func plan(_ theme: GraphTheme, _ input: UniverseInput) -> ThemePlan? {
        switch theme {
        case .neurons: return GraphNeurons.plan(input)
        case .circuit: return GraphCircuit.plan(input)
        case .space: return nil
        }
    }

    /// The theme's look, made for this build (the Graphics budget and
    /// liveliness as they are now).
    static func look(_ theme: GraphTheme, lively: Bool, bold: Bool) -> GraphThemeLook? {
        switch theme {
        case .neurons: return GraphNeuronLook(lively: lively, bold: bold)
        case .circuit: return GraphCircuitLook(lively: lively, bold: bold)
        case .space: return nil
        }
    }

    /// Checks the theme's shaders once, off the main thread, before its
    /// first build.
    nonisolated static func prepare(_ theme: GraphTheme) {
        switch theme {
        case .neurons: _ = NeuronProbe.support
        case .circuit: _ = CircuitProbe.support
        case .space: break
        }
    }
}

@MainActor
extension GraphSceneBuilder {
    static func buildTheme(store: NoteStore, plan: ThemePlan, look: GraphThemeLook, edges noteEdges: [(UUID, UUID)],
                           lively: Bool, contrast: Bool) -> GraphScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.black
        let sky: SCNNode = look.makeSky()
        scene.rootNode.addChildNode(sky)
        let rig = SCNNode()
        rig.name = "tiltRig"
        scene.rootNode.addChildNode(rig)
        let world = SCNNode()
        rig.addChildNode(world)
        let textColor = UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1)

        let lines = SCNNode()
        lines.name = "links"
        lines.renderingOrder = 5
        lines.categoryBitMask = 2
        world.addChildNode(lines)
        let farLines = SCNNode()
        farLines.name = "farLinks"
        farLines.renderingOrder = 4
        farLines.categoryBitMask = 2
        world.addChildNode(farLines)

        var noteByID: [UUID: Note] = [:]
        for note in store.notes { noteByID[note.id] = note }
        var infos: [GraphNodeInfo] = []
        var parts: [GraphThemeParts] = []
        var folders: [UUID: Int] = [:]
        var titles: [String: Int] = [:]
        var galaxyOf: [UUID: UUID] = [:]
        var tones: [Int: UIColor] = [:]
        for (i, body) in plan.bodies.enumerated() {
            let made: GraphThemeParts = look.makeBody(body, index: i, plan: plan)
            let node: SCNNode = made.node
            node.simdPosition = body.home
            var rim: UIColor?
            if body.region >= 0 {
                if tones[body.region] == nil { tones[body.region] = look.tone(region: body.region, plan: plan) }
                rim = tones[body.region].map { Self.rim(tone: $0) }
            }
            let isNote: Bool = body.kind == .note
            let label: SCNNode = Self.label(body.label, color: textColor, height: 1, contrast: contrast, rim: rim,
                                            cut: isNote)
            node.addChildNode(label)
            world.addChildNode(node)
            let regionID: UUID? = body.region >= 0 ? plan.bodies[body.region].id : nil
            if isNote, let regionID { galaxyOf[body.id] = regionID }
            let note: Note? = isNote ? noteByID[body.id] : nil
            var info = GraphNodeInfo(id: body.id, node: node, label: label, kind: note?.kind ?? .page,
                                     root: regionID, home: body.home, radius: made.radius,
                                     ringStretch: made.ringStretch, ringLeaf: made.ringLeaf,
                                     ringGeometry: made.ringGeometry, diskLeaf: made.diskLeaf,
                                     diskGeometry: nil, spin: 0, spinRate: 0)
            // no style kit here: the look's own pieces, and the plan's send
            // rank for which end of a link sends
            info.style = .rocky
            info.swell = 0.25
            info.stretchGain = 0.6
            info.glowGain = 0.8 + 0.2 * min(Float(body.links) / 5, 1)
            info.body = Self.kind(body.kind)
            info.parent = body.parent
            info.orbit = body.orbit
            info.linkCode = body.rank
            info.thinnable = made.thinnable
            infos.append(info)
            parts.append(made)
            if !isNote {
                folders[body.id] = i
                titles[body.title] = i
            }
        }

        look.decorate(world: world, plan: plan)

        // the notes' links, and every container wired to those inside it
        var edges: [(UUID, UUID)] = noteEdges
        var kinds: [String: (Int, Int)] = [:]
        for link in plan.links {
            let a: UUID = plan.bodies[link.a].id
            let b: UUID = plan.bodies[link.b].id
            kinds[GraphMemory.key(a, b)] = (link.kind, link.centre)
            if link.kind == 4 { edges.append((a, b)) }
        }

        var extent: Float = 1
        for p in plan.envelope { extent = max(extent, simd_length(p)) }
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

        var universe = GraphUniverseLooks(shells: [], shellOwner: [], linkKinds: kinds, farLines: farLines,
                                          farMaterial: look.farMaterial)
        universe.halfWidth = look.linkHalfWidth
        universe.farHalfWidth = look.farHalfWidth
        universe.seeded = true
        universe.board = look.board
        universe.ticker = look.ticker(parts: parts, plan: plan)
        var simLooks = GraphSimLooks(linkMaterial: look.linkMaterial, hotRing: look.hotRing, hotDisk: SCNGeometry(),
                                     clocked: look.clocked, emitters: [], trails: [], sky: sky)
        simLooks.universe = universe
        // no styles: a body whose look changes (another theme) pops in anew
        let styles: [UUID: GraphNodeStyle] = [:]
        simLooks.recall = GraphMemory.recall(ids: infos.map(\.id), edges: edges, styles: styles, lively: lively)
        let sim = GraphSim(world: world, rig: rig, infos: infos, edges: edges, lines: lines, looks: simLooks,
                           lively: lively, labelReach: 5.5)
        GraphMemory.remember(sim, edges: edges, styles: styles)
        var built = GraphScene(scene: scene, camera: cameraNode, sim: sim, homes: plan.envelope, pad: pad)
        built.universe = true
        built.theme = look.theme
        built.systems = plan.systems
        built.summary = plan.summary
        built.folders = folders
        built.containerTitles = titles
        built.dragTarget = Self.busiestRelay(plan)
        built.galaxies = plan.regions.map { plan.bodies[$0].id }
        built.galaxyOf = galaxyOf
        return built
    }

    private static func kind(_ kind: ThemeBodyKind) -> GraphBodyKind {
        switch kind {
        case .note: return .note
        case .folder: return .folder
        case .home: return .home
        }
    }

    /// The first-level container holding the most notes (ties: the lower
    /// index), for the design preview's drag; any container without one.
    private static func busiestRelay(_ plan: ThemePlan) -> Int? {
        var best: Int?
        var most: Int = -1
        for (i, body) in plan.bodies.enumerated() where body.kind != .note && body.depth == 1 && body.count > most {
            best = i
            most = body.count
        }
        if best != nil { return best }
        for (i, body) in plan.bodies.enumerated() where body.kind != .note && body.count > most {
            best = i
            most = body.count
        }
        return best
    }
}
