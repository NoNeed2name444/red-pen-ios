import SwiftUI
import SceneKit
import UIKit
import simd

/// The space: every note as a soft point in 3D and every connection as a fine
/// thread between two, the way Obsidian's graph shows a vault - but something
/// to turn round in the hand rather than a flat picture.
///
/// It is a piece of deep space. Every note is a small black hole - a black
/// sphere, a thin photon ring hugging its rim and a tilted, streaky
/// accretion disk, tinted a little by its folder - and every link a stream of
/// plasma with an electric aura (see GraphLook). Pages are a little larger
/// than ideas. Titles appear only for the few notes nearest you, fading in
/// as you come closer. The only controls
/// are two small buttons in the corner: one to filter, one to bring the view
/// back to the middle.
///
/// It is alive rather than frozen: the notes drift gently, pop in with a small
/// bounce, and a note dragged with a finger pulls its neighbours along and
/// springs home when let go (see GraphSim). Drag empty space to turn it,
/// pinch to come closer, tap a note to open it. With Reduce Motion on the
/// space stands still.
///
/// Where each note belongs is worked out by ForceLayout3D, off the main
/// thread, and again only when notes or links change.
struct Graph3DView: View {
    @EnvironmentObject private var notes: NoteStore
    let open: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var built: GraphScene?
    @State private var filter: GraphFilter = .all
    /// Bumped by the recentre button; the view notices the change.
    @State private var recenter: Int = 0

    var body: some View {
        Group {
            if notes.notes.isEmpty {
                ContentUnavailableView {
                    Label("Dump your first idea", systemImage: "cube.transparent")
                } description: {
                    Text("Every note appears here as a point in space, joined to the notes it links to. Type one in the bar above.")
                }
            } else if let built {
                GraphSCNView(built: built, filter: filter, recenter: recenter, onTap: open)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Space of ideas")
                    .accessibilityHint("Drag to turn, pinch to zoom, tap a note to open it.")
                    .accessibilityIdentifier("graph3D")
                    .overlay {
                        if filter != .all && shownCount == 0 {
                            Text("Nothing here for this filter.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) { controls }
                    // the space is always night, whatever the phone's setting
                    .environment(\.colorScheme, .dark)
            } else {
                ProgressView()
            }
        }
        .task(id: signature) { await rebuild() }
        // a folder being filtered to was deleted: show everything again
        .onChange(of: notes.folders) { _, _ in
            if case .folder(let id) = filter, notes.folder(id) == nil { filter = .all }
        }
    }

    // MARK: the corner controls

    /// The only controls on screen: filter, and back to the middle.
    private var controls: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                Menu {
                    filterMenu
                } label: {
                    Image(systemName: filter == .all
                          ? "line.3.horizontal.decrease"
                          : "line.3.horizontal.decrease.circle.fill")
                        .font(.body.weight(.medium))
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .foregroundStyle(.secondary)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Filter")

                Button {
                    recenter += 1
                } label: {
                    Image(systemName: "scope")
                        .font(.body.weight(.medium))
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Recentre")
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var filterMenu: some View {
        Picker("Show", selection: $filter) {
            Text("Everything").tag(GraphFilter.all)
            Text("Pages").tag(GraphFilter.pages)
            Text("Ideas").tag(GraphFilter.ideas)
            Text("Linked notes").tag(GraphFilter.linked)
        }
        .pickerStyle(.inline)
        let tops: [NoteFolder] = notes.subfolders(of: nil)
        if !tops.isEmpty {
            Picker("Folder", selection: $filter) {
                ForEach(tops) { folder in
                    Text(folder.name).tag(GraphFilter.folder(folder.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// How many notes the current filter lets through, to say so when none do.
    private var shownCount: Int {
        var degree: [UUID: Int] = [:]
        for edge in notes.allEdges() {
            degree[edge.0, default: 0] += 1
            degree[edge.1, default: 0] += 1
        }
        var count: Int = 0
        for note in notes.notes {
            let root: UUID? = notes.rootFolder(of: note.folderId)
            let links: Int = degree[note.id] ?? 0
            if filter.admits(kind: note.kind, root: root, degree: links) { count += 1 }
        }
        return count
    }

    // MARK: building

    /// Everything the picture depends on. When this changes the layout is
    /// worked out again; moving a card on the board does not change it.
    private var signature: String {
        var parts: [String] = []
        for note in notes.notes {
            let folder: String = note.folderId?.uuidString ?? ""
            parts.append("\(note.id.uuidString)|\(note.title)|\(note.kind.rawValue)|\(folder)")
        }
        for edge in notes.allEdges() {
            parts.append(edge.0.uuidString + edge.1.uuidString)
        }
        for folder in notes.folders {
            let parent: String = folder.parentId?.uuidString ?? ""
            parts.append("\(folder.id.uuidString)|\(folder.name)|\(parent)")
        }
        parts.append("\(reduceMotion)")
        parts.append("\(bold)")
        return parts.joined(separator: "\n")
    }

    /// Reduce Transparency or Increase Contrast: brighter, solid links.
    private var bold: Bool {
        reduceTransparency || contrast == .increased
    }

    private func rebuild() async {
        let ids = notes.notes.map(\.id)
        let edges = notes.allEdges()
        var folders: [UUID: UUID] = [:]
        for note in notes.notes {
            if let folder = note.folderId { folders[note.id] = folder }
        }
        // a constant copy: a var cannot be handed to another thread
        let groups = folders
        // the layout, and (once per launch) a check that the shaders work
        // then packed into one constellation and turned to show its broadest
        // face (GraphFraming)
        let worked = await Task.detached(priority: .userInitiated) {
            let laid = ForceLayout3D.layout(nodes: ids, edges: edges, groups: groups)
            let radius: Float = GraphFraming.pageRadius(laid, edges: edges)
            let reach: Float = radius * GraphShape.diskRadius
            let positions = GraphFraming.arrange(laid, edges: edges, pad: reach)
            let support: GraphShaderSupport = GraphShaderProbe.support
            return (positions, support, radius)
        }.value
        guard !Task.isCancelled else { return }
        built = GraphSceneBuilder.build(store: notes, positions: worked.0, edges: edges,
                                        lively: !reduceMotion, bold: bold, shaders: worked.1,
                                        pageRadius: worked.2)
    }
}

/// A built scene, the camera it is seen through, where that camera starts,
/// and the simulation that keeps it moving.
struct GraphScene {
    let scene: SCNScene
    let camera: SCNNode
    let sim: GraphSim
    /// Every note's home, for framing (GraphFraming.distance).
    let homes: [SIMD3<Float>]
    /// How far a note's look reaches past its centre.
    let pad: Float
}

/// Turns notes and their positions into SceneKit nodes.
///
/// Each note's node is named "note:<id>", which is how a tap finds out which
/// note it landed on. Only the black spheres and the titles can be hit
/// (category 1); rings, disks, links and sparks are category 2.
///
/// Each note is built as:
///
///     note (black sphere)
///       disk tilt (fixed, a little different for every note)
///         disk (a flat plane, spun about its own axis by GraphSim)
///       ring holder (billboarded: always faces the camera)
///         ring stretch (lifted towards the camera; squash and stretch)
///           ring (the plane, turned back so its bright side stays right)
///       label
///
/// The ring is lifted more than a radius towards the camera, so no part of
/// its own sphere is ever in front of it and the rim shows all the way
/// round from every angle; it is still tested against depth, so another
/// note in front hides it. The disk stays a flat, tilted plane through the
/// centre, so its far half passes behind the sphere as it should.
@MainActor
enum GraphSceneBuilder {
    static func build(store: NoteStore, positions: [UUID: SIMD3<Float>], edges: [(UUID, UUID)],
                      lively: Bool, bold: Bool, shaders: GraphShaderSupport,
                      pageRadius: Float) -> GraphScene {
        let scene = SCNScene()
        // deep space: a sky of geometry kept round the camera (GraphSpace)
        scene.background.contents = UIColor.black
        let sky: SCNNode = GraphSpace.makeSky()
        scene.rootNode.addChildNode(sky)
        let world = SCNNode()
        scene.rootNode.addChildNode(world)
        let ideaRadius: Float = pageRadius * 0.62

        let textColor = UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1)

        // connections: camera-facing ribbons, all in one geometry that
        // GraphSim rebuilds as the notes move; the look is in the shader
        let linkMaterial = GraphLook.link(bold: bold, shader: shaders.link, lively: lively)
        let lines = SCNNode()
        lines.name = "links"
        lines.renderingOrder = 5
        lines.categoryBitMask = 2
        world.addChildNode(lines)

        // shared by every note: two spheres (page, idea) and one black
        // material; a ring and a disk per folder; a bright pair for the
        // selected note
        let hole: SCNMaterial = GraphLook.hole()
        let pageSphere = SCNSphere(radius: CGFloat(pageRadius))
        let ideaSphere = SCNSphere(radius: CGFloat(ideaRadius))
        for sphere in [pageSphere, ideaSphere] {
            sphere.segmentCount = 28
            sphere.materials = [hole]
        }
        var clocked: [SCNMaterial] = []
        if shaders.link { clocked.append(linkMaterial) }
        var looks: [UUID?: (ring: SCNGeometry, disk: SCNGeometry)] = [:]
        func look(for folder: UUID?) -> (ring: SCNGeometry, disk: SCNGeometry) {
            if let made = looks[folder] { return made }
            let tint: UIColor = GraphLook.tint(NoteTone.uiColor(for: folder, in: store))
            let ringMaterial = GraphLook.ring(tint: tint, hot: false, shader: shaders.ring, lively: lively)
            let diskMaterial = GraphLook.disk(tint: tint, hot: false, shader: shaders.disk)
            if shaders.ring { clocked.append(ringMaterial) }
            let made = (ring: plane(ringMaterial), disk: plane(diskMaterial))
            looks[folder] = made
            return made
        }
        let hotRingMaterial = GraphLook.ring(tint: .white, hot: true, shader: shaders.ring, lively: lively)
        if shaders.ring { clocked.append(hotRingMaterial) }
        let hotRing: SCNGeometry = plane(hotRingMaterial)
        let hotDisk: SCNGeometry = plane(GraphLook.disk(tint: .white, hot: true, shader: shaders.disk))

        var random = SplitMix64(seed: 0x6A26)
        var infos: [GraphNodeInfo] = []
        var extent: Float = 1
        var homes: [SIMD3<Float>] = []
        for note in store.notes {
            guard let p = positions[note.id] else { continue }
            extent = max(extent, simd_length(p))
            homes.append(p)
            let isPage: Bool = note.kind == .page
            let radius: Float = isPage ? pageRadius : ideaRadius
            let node = SCNNode(geometry: isPage ? pageSphere : ideaSphere)
            node.name = "note:\(note.id.uuidString)"
            node.simdPosition = p
            let pair = look(for: note.folderId)

            // the disk: flat, tilted so it is seen a little from above, each
            // note a little differently
            let tilt = SCNNode()
            let lean: Float = 0.26 + random.unit() * 0.14
            let roll: Float = random.unit() * 0.3
            let yaw: Float = random.unit() * Float.pi
            let flat = simd_quatf(angle: lean - Float.pi / 2, axis: SIMD3<Float>(1, 0, 0))
            let rolled = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
            let turned = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            tilt.simdOrientation = turned * rolled * flat
            let disk = SCNNode(geometry: pair.disk)
            let diskSide: Float = radius * GraphShape.diskRadius * 2
            disk.simdScale = SIMD3<Float>(diskSide, diskSide, 1)
            let startSpin: Float = random.unit() * Float.pi
            disk.simdEulerAngles = SIMD3<Float>(0, 0, startSpin)
            disk.renderingOrder = 4
            disk.categoryBitMask = 2
            tilt.addChildNode(disk)
            node.addChildNode(tilt)

            // the photon ring: always facing the camera, in front of its
            // own sphere
            let holder = SCNNode()
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .all
            holder.constraints = [billboard]
            let stretch = SCNNode()
            let lift: Float = radius * GraphShape.ringLift
            stretch.simdPosition = SIMD3<Float>(0, 0, lift)
            stretch.opacity = 0.85
            let ring = SCNNode(geometry: pair.ring)
            let ringSide: Float = radius * GraphShape.ringPlane
            ring.simdScale = SIMD3<Float>(ringSide, ringSide, 1)
            // after the links (5), so the ring's glow reads on top of the
            // line where they meet
            ring.renderingOrder = 6
            ring.categoryBitMask = 2
            stretch.addChildNode(ring)
            holder.addChildNode(stretch)
            node.addChildNode(holder)

            let title: String = note.title.isEmpty ? "Untitled" : note.title
            let labelHeight: Float = max(radius * 1.05, 0.17)
            let label = Self.label(title, color: textColor, height: labelHeight)
            let labelLift: Float = radius * 2.3 + 0.04
            label.simdPosition = SIMD3<Float>(0, labelLift, 0)
            node.addChildNode(label)
            world.addChildNode(node)

            // each disk turns once every 10 to 20 seconds at rest
            let pace: Float = 0.5 + random.unit() * 0.5
            let spinRate: Float = 0.31 + pace * 0.31
            let info = GraphNodeInfo(id: note.id, node: node, label: label, kind: note.kind,
                                     root: store.rootFolder(of: note.folderId), home: p,
                                     radius: radius, ringStretch: stretch, ringLeaf: ring,
                                     ringGeometry: pair.ring, diskLeaf: disk,
                                     diskGeometry: pair.disk, spin: startSpin, spinRate: spinRate)
            infos.append(info)
        }

        // comet trails: a few emitters shared by whichever notes are moving
        // fastest; none at all with Reduce Motion
        var emitters: [SCNNode] = []
        var trails: [SCNParticleSystem] = []
        if lively {
            for _ in 0..<4 {
                let system: SCNParticleSystem = GraphLook.trail(scale: pageRadius / 0.2)
                let emitter = SCNNode()
                emitter.categoryBitMask = 2
                emitter.renderingOrder = 7
                emitter.addParticleSystem(system)
                world.addChildNode(emitter)
                emitters.append(emitter)
                trails.append(system)
            }
        }

        // the camera: placed by the view to fit the graph to the screen
        // (GraphFraming); here, a first guess for a phone held upright.
        // Everything is unlit, so there are no lights.
        // framed to the rings; the thin, tilted disks may reach a little past
        let pad: Float = pageRadius * 1.4
        let distance: Float = GraphFraming.distance(points: homes, pad: pad, aspect: 0.46)
        let camera = SCNCamera()
        camera.fieldOfView = Double(GraphFraming.fieldOfView)
        camera.zNear = 0.05
        let far: Float = distance * 4 + extent * 4 + 20
        camera.zFar = Double(far)
        // the sky sits just inside the far plane, kept round the camera
        let skyRadius: Float = far * 0.5
        sky.simdScale = SIMD3<Float>(skyRadius, skyRadius, skyRadius)
        // no HDR, bloom or glare: the glows are baked into the textures and
        // shaders, and camera bloom would put a halo round everything bright
        camera.wantsHDR = false
        camera.bloomIntensity = 0
        camera.wantsExposureAdaptation = false
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let cameraHome = SIMD3<Float>(0, 0, distance)
        cameraNode.simdPosition = cameraHome
        scene.rootNode.addChildNode(cameraNode)

        // titles come within reach as the camera comes closer; from where it
        // starts only a small space shows any
        let scaledReach: Float = distance * 0.55
        let labelReach: Float = max(scaledReach, 5.5)
        let simLooks = GraphSimLooks(linkMaterial: linkMaterial, hotRing: hotRing, hotDisk: hotDisk,
                                     clocked: clocked, emitters: emitters, trails: trails, sky: sky)
        let sim = GraphSim(world: world, infos: infos, edges: edges, lines: lines,
                           looks: simLooks, lively: lively, labelReach: labelReach)
        return GraphScene(scene: scene, camera: cameraNode, sim: sim, homes: homes, pad: pad)
    }

    /// A one-by-one square plane; each note scales it to size.
    private static func plane(_ material: SCNMaterial) -> SCNGeometry {
        let plane = SCNPlane(width: 1, height: 1)
        plane.materials = [material]
        return plane
    }

    /// A small flat title that always faces the camera. It starts hidden;
    /// GraphSim fades it in when the note is near enough.
    private static func label(_ text: String, color: UIColor, height: Float) -> SCNNode {
        let shown: String = text.count > 28 ? String(text.prefix(27)) + "\u{2026}" : text
        let geometry = SCNText(string: shown, extrusionDepth: 0)
        geometry.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        geometry.flatness = 0.3
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        // always in front: a note between the camera and a name never hides it
        material.readsFromDepthBuffer = false
        geometry.materials = [material]

        let textNode = SCNNode(geometry: geometry)
        // centred over the point, sitting on it
        let (low, high) = textNode.boundingBox
        let middleX: Float = (low.x + high.x) / 2
        textNode.pivot = SCNMatrix4MakeTranslation(middleX, low.y, 0)
        // a 10-point font is about 10 units tall; shrink it to `height`
        let scale: Float = height / 10
        textNode.scale = SCNVector3(x: scale, y: scale, z: scale)

        // a dark rounded pill just the size of the words behind them, so the
        // title reads clearly over the glowing links
        let textWidth: Float = (high.x - low.x) * scale
        let textHeight: Float = (high.y - low.y) * scale
        let padX: Float = height * 0.45
        let padY: Float = height * 0.28
        let pillWidth: Float = textWidth + padX * 2
        let pillHeight: Float = textHeight + padY * 2
        let pill = SCNPlane(width: CGFloat(pillWidth), height: CGFloat(pillHeight))
        pill.cornerRadius = CGFloat(pillHeight / 2)
        let pillLook = SCNMaterial()
        pillLook.diffuse.contents = UIColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 0.9)
        pillLook.lightingModel = .constant
        pillLook.isDoubleSided = true
        pillLook.writesToDepthBuffer = false
        pillLook.readsFromDepthBuffer = false
        pill.materials = [pillLook]
        let pillNode = SCNNode(geometry: pill)
        pillNode.simdPosition = SIMD3<Float>(0, textHeight / 2, -0.002)
        // drawn after the links, then the words on top of the pill
        pillNode.renderingOrder = 20
        textNode.renderingOrder = 21

        let holder = SCNNode()
        holder.name = "label"
        holder.renderingOrder = 20
        holder.addChildNode(pillNode)
        holder.addChildNode(textNode)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        holder.constraints = [billboard]
        return holder
    }
}

/// SceneKit's view, wrapped so a tap can say which note it landed on and a
/// drag on a note can move it - neither of which SwiftUI's SceneView offers.
/// Turning and zooming, when the finger is not on a note, are SceneKit's own
/// camera control.
struct GraphSCNView: UIViewRepresentable {
    let built: GraphScene
    let filter: GraphFilter
    let recenter: Int
    let onTap: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, recenter: recenter)
    }

    func makeUIView(context: Context) -> FramingSCNView {
        let view = FramingSCNView(frame: .zero)
        // the sky covers it; black until the first frame
        view.backgroundColor = .black
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        // step and draw every frame the screen shows: 120 a second on
        // ProMotion, 60 elsewhere (SceneKit caps it at what the screen can do)
        view.preferredFramesPerSecond = 120
        view.rendersContinuously = true
        view.isJitteringEnabled = false
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true

        let coordinator = context.coordinator
        coordinator.view = view
        view.onResize = { [weak coordinator] size in coordinator?.resized(to: size) }
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = coordinator
        view.addGestureRecognizer(pan)
        coordinator.panner = pan

        coordinator.attach(built, to: view)
        coordinator.apply(filter)
        return view
    }

    func updateUIView(_ view: FramingSCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        if coordinator.sim !== built.sim {
            coordinator.attach(built, to: view)
        }
        coordinator.apply(filter)
        if coordinator.recenterCount != recenter {
            coordinator.recenterCount = recenter
            coordinator.recentre()
        }
    }

    static func dismantleUIView(_ view: FramingSCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: (UUID) -> Void
        var recenterCount: Int
        private(set) var sim: GraphSim?
        weak var view: SCNView?
        weak var panner: UIPanGestureRecognizer?
        private var camera: SCNNode?
        /// The notes' homes and how far each reaches, for framing.
        private var homes: [SIMD3<Float>] = []
        private var pad: Float = 0
        /// Whether the graph was last framed for a wide (landscape) view;
        /// nil before the first framing.
        private var framedWide: Bool?
        private var shownFilter: GraphFilter?
        /// The note a drag is about to pick up, found when the drag begins.
        private var pending: Int?
        /// How far into the screen the dragged note sits, so it moves across
        /// the screen at that depth.
        private var dragDepth: Float = 0
        /// From the finger to the note's centre, so it does not jump.
        private var dragOffset = SIMD3<Float>(0, 0, 0)
        /// True between a drag picking a note up and letting it go.
        private var dragging: Bool = false
        /// The camera's own drag gestures already told to wait for ours.
        private var wired: Set<ObjectIdentifier> = []
        /// The design preview's drag has been started (see GraphPreview).
        private var previewDragged: Bool = false

        init(onTap: @escaping (UUID) -> Void, recenter: Int) {
            self.onTap = onTap
            self.recenterCount = recenter
        }

        /// Shows a newly built scene.
        func attach(_ built: GraphScene, to view: SCNView) {
            sim = built.sim
            camera = built.camera
            homes = built.homes
            pad = built.pad
            framedWide = nil
            shownFilter = nil
            // the simulation steps on SceneKit's render loop, once per frame
            view.delegate = built.sim
            view.scene = built.scene
            view.pointOfView = built.camera
            view.defaultCameraController.target = SCNVector3(x: 0, y: 0, z: 0)
            view.isPlaying = true
            wireCameraGestures(in: view)
            frame(animated: false)
            built.sim.appear()
            if GraphPreview.drags && !previewDragged {
                previewDragged = true
                runPreviewDrag()
            }
        }

        /// For the design preview (`-graphPreviewDrag`): a second after the
        /// space appears, picks up the most-linked note, carries it along an
        /// arc across the screen for two seconds, and lets go - so a
        /// screenshot can catch the moving look.
        private func runPreviewDrag() {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let sim = self.sim, let view = self.view,
                      let i = sim.busiestNote() else { return }
                let pov: simd_float4x4 = view.pointOfView?.simdWorldTransform ?? matrix_identity_float4x4
                let screenRight = SIMD3<Float>(pov.columns.0.x, pov.columns.0.y, pov.columns.0.z)
                let screenUp = SIMD3<Float>(pov.columns.1.x, pov.columns.1.y, pov.columns.1.z)
                let right: SIMD3<Float> = sim.world.simdConvertVector(screenRight, from: nil)
                let up: SIMD3<Float> = sim.world.simdConvertVector(screenUp, from: nil)
                let start: SIMD3<Float> = sim.currentPosition(i)
                sim.grab(i)
                let steps: Int = 120
                for k in 1...steps {
                    try? await Task.sleep(nanoseconds: 16_666_667)
                    let s: Float = Float(k) / Float(steps)
                    let angle: Float = s * Float.pi
                    let across: Float = (1 - cos(angle)) * 1.6
                    let lift: Float = sin(angle) * 1.2
                    let moved: SIMD3<Float> = right * across + up * lift
                    sim.drag(to: start + moved)
                }
                sim.release()
            }
        }

        func apply(_ filter: GraphFilter) {
            guard let sim else { return }
            if shownFilter == filter { return }
            shownFilter = filter
            sim.apply(filter)
        }

        /// Glides the camera back to the fitted view of the whole graph.
        func recentre() {
            frame(animated: true)
        }

        /// The view changed size. The first time it has a size, and whenever
        /// it turns between upright and wide, the graph is framed again.
        func resized(to size: CGSize) {
            guard size.width > 1, size.height > 1 else { return }
            let wide: Bool = size.width > size.height
            guard framedWide != wide else { return }
            frame(animated: framedWide != nil)
        }

        /// Fits the whole graph to the screen (GraphFraming): its longest
        /// spread along the screen's long side, filling 80% of the shorter
        /// one, centred, seen from the front.
        private func frame(animated: Bool) {
            guard let view, let camera, let sim else { return }
            let size: CGSize = view.bounds.size
            guard size.width > 1, size.height > 1 else { return }
            let wide: Bool = size.width > size.height
            framedWide = wide
            // upright: the graph's long axis (y) runs up the screen; wide:
            // turned a quarter so it runs across
            let angle: Float = wide ? -Float.pi / 2 : 0
            let turn = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1))
            let turned: [SIMD3<Float>] = homes.map { turn.act($0) }
            let aspect = Float(size.width / size.height)
            let distance: Float = GraphFraming.distance(points: turned, pad: pad, aspect: aspect)
            view.pointOfView = camera
            view.defaultCameraController.target = SCNVector3(x: 0, y: 0, z: 0)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.6 : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sim.world.simdOrientation = turn
            camera.simdPosition = SIMD3<Float>(0, 0, distance)
            camera.simdOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            SCNTransaction.commit()
        }

        /// The view is going: stop drawing and let go of the simulation.
        func stop() {
            view?.isPlaying = false
            view?.delegate = nil
        }

        // MARK: gestures

        /// SceneKit's camera control brings its own drag gestures. Each is
        /// told to wait until ours has decided the finger is not on a note,
        /// so a drag on a note moves the note and a drag anywhere else turns
        /// the space.
        private func wireCameraGestures(in view: SCNView) {
            guard let panner else { return }
            for other in view.gestureRecognizers ?? [] {
                guard other !== panner, other is UIPanGestureRecognizer else { continue }
                let key = ObjectIdentifier(other)
                if wired.contains(key) { continue }
                other.require(toFail: panner)
                wired.insert(key)
            }
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard gesture === panner, let view else { return true }
            let point: CGPoint = gesture.location(in: view)
            pending = noteIndex(at: point, in: view)
            guard pending != nil else { return false }
            // on a note: make sure the camera does not turn as well, by
            // switching its drags off and on again, which cancels them
            wireCameraGestures(in: view)
            for other in view.gestureRecognizers ?? [] {
                guard other !== gesture, other is UIPanGestureRecognizer else { continue }
                other.isEnabled = false
                other.isEnabled = true
            }
            return true
        }

        @objc func panned(_ gesture: UIPanGestureRecognizer) {
            guard let view, let sim else { return }
            let point: CGPoint = gesture.location(in: view)
            switch gesture.state {
            case .began:
                guard let i = pending else { return }
                // the depth of the note on screen is found once, here; each
                // move after that is one unprojection onto that depth
                let local: SIMD3<Float> = sim.currentPosition(i)
                let world: SIMD3<Float> = sim.world.simdConvertPosition(local, to: nil)
                let scenePoint = SCNVector3(x: world.x, y: world.y, z: world.z)
                let projected: SCNVector3 = view.projectPoint(scenePoint)
                dragDepth = projected.z
                let finger: SIMD3<Float> = fingerPoint(point, in: view, sim: sim)
                dragOffset = local - finger
                dragging = true
                sim.grab(i)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            case .changed:
                guard dragging else { return }
                let finger: SIMD3<Float> = fingerPoint(point, in: view, sim: sim)
                let target: SIMD3<Float> = finger + dragOffset
                sim.drag(to: target)
            default:
                dragging = false
                pending = nil
                sim.release()
            }
        }

        /// Where the finger is, at the dragged note's depth, in the space's
        /// own coordinates.
        private func fingerPoint(_ point: CGPoint, in view: SCNView, sim: GraphSim) -> SIMD3<Float> {
            let screen = SCNVector3(x: Float(point.x), y: Float(point.y), z: dragDepth)
            let world: SCNVector3 = view.unprojectPoint(screen)
            let inScene = SIMD3<Float>(world.x, world.y, world.z)
            return sim.world.simdConvertPosition(inScene, from: nil)
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view, let sim else { return }
            let point: CGPoint = gesture.location(in: view)
            guard let i = noteIndex(at: point, in: view) else { return }
            sim.select(i)
            onTap(sim.ids[i])
        }

        /// Looks through everything under the finger for the nearest shown
        /// note, climbing from a
        /// label to the note it belongs to.
        private func noteIndex(at point: CGPoint, in view: SCNView) -> Int? {
            guard let sim else { return nil }
            // only the spheres and titles (category 1): not the rings,
            // disks, links or sparks round them
            let options: [SCNHitTestOption: Any] = [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue,
                SCNHitTestOption.ignoreHiddenNodes: true,
                SCNHitTestOption.categoryBitMask: 1
            ]
            let hits = view.hitTest(point, options: options)
            for hit in hits {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name, name.hasPrefix("note:"),
                       let id = UUID(uuidString: String(name.dropFirst(5))),
                       let slot = sim.index[id] {
                        return slot
                    }
                    node = current.parent
                }
            }
            return nil
        }
    }
}

/// An SCNView that says when its size changes, so the graph can be framed
/// once it has a size and again when the phone turns.
final class FramingSCNView: SCNView {
    var onResize: ((CGSize) -> Void)?
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        let size: CGSize = bounds.size
        guard size != lastSize else { return }
        lastSize = size
        onResize?(size)
    }
}
