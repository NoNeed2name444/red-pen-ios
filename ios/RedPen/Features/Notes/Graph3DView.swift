import SwiftUI
import SceneKit
import UIKit
import simd

/// The space: every note as a soft point in 3D and every connection as a fine
/// thread between two, the way Obsidian's graph shows a vault - but something
/// to turn round in the hand rather than a flat picture.
///
/// It is kept quiet on purpose. Pages are a little larger than ideas; notes
/// are matte pastel dots coloured by folder, with nothing drawn round them;
/// titles appear only for the few notes nearest you, fading in as you come
/// closer. The only controls
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
    @Environment(\.colorScheme) private var scheme
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
                    .accessibilityLabel("Space of ideas")
                    .accessibilityHint("Drag to turn, pinch to zoom, tap a note to open it.")
                    .overlay {
                        if filter != .all && shownCount == 0 {
                            Text("Nothing here for this filter.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) { controls }
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
        parts.append("\(scheme == .dark)")
        return parts.joined(separator: "\n")
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
        let positions = await Task.detached(priority: .userInitiated) {
            ForceLayout3D.layout(nodes: ids, edges: edges, groups: groups)
        }.value
        guard !Task.isCancelled else { return }
        built = GraphSceneBuilder.build(store: notes, positions: positions, edges: edges,
                                        dark: scheme == .dark, lively: !reduceMotion)
    }
}

/// A built scene, the camera it is seen through, where that camera starts,
/// and the simulation that keeps it moving.
struct GraphScene {
    let scene: SCNScene
    let camera: SCNNode
    let cameraHome: SIMD3<Float>
    let sim: GraphSim
}

/// Turns notes and their positions into SceneKit nodes.
///
/// Each note's node is named "note:<id>", which is how a tap finds out which
/// note it landed on.
///
/// Nothing is drawn round a note - no bubble, glow, rim or see-through
/// shell - so each reads as one clean matte dot.
@MainActor
enum GraphSceneBuilder {
    static func build(store: NoteStore, positions: [UUID: SIMD3<Float>], edges: [(UUID, UUID)],
                      dark: Bool, lively: Bool) -> GraphScene {
        let scene = SCNScene()
        // clear, so the app's own backdrop shows through behind the space
        scene.background.contents = UIColor.clear
        let world = SCNNode()
        scene.rootNode.addChildNode(world)

        // SceneKit does not follow light and dark by itself, so the colours
        // are settled for the one in use
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let textColor: UIColor = UIColor.secondaryLabel.resolvedColor(with: traits)
        let lineAlpha: CGFloat = dark ? 0.28 : 0.22
        let lineColor: UIColor = UIColor.label.resolvedColor(with: traits).withAlphaComponent(lineAlpha)

        // connections: hairlines, all in one geometry that GraphSim redraws
        // as the notes move
        let lineMaterial = SCNMaterial()
        lineMaterial.diffuse.contents = lineColor
        lineMaterial.lightingModel = .constant
        lineMaterial.blendMode = .alpha
        lineMaterial.writesToDepthBuffer = false
        let lines = SCNNode()
        lines.name = "links"
        lines.renderingOrder = 5
        world.addChildNode(lines)

        // notes: soft matte pastel spheres, pages larger than ideas, coloured
        // by folder. Lambert shading has no shine or highlight at all.
        var infos: [GraphNodeInfo] = []
        var extent: Float = 1
        for note in store.notes {
            guard let p = positions[note.id] else { continue }
            extent = max(extent, simd_length(p))
            let radius: Float = note.kind == .page ? 0.2 : 0.12
            let sphere = SCNSphere(radius: CGFloat(radius))
            sphere.segmentCount = 20
            let material = SCNMaterial()
            material.lightingModel = .lambert
            material.diffuse.contents = pastel(NoteTone.uiColor(for: note.folderId, in: store), dark: dark)
            material.specular.contents = UIColor.black
            material.reflective.contents = nil
            material.emission.contents = UIColor.black
            // fully opaque: a see-through sphere blended over the lines and
            // the backdrop shows a pale ring at its edge
            material.transparency = 1
            material.blendMode = .replace
            sphere.materials = [material]
            let node = SCNNode(geometry: sphere)
            node.name = "note:\(note.id.uuidString)"
            node.simdPosition = p

            let title: String = note.title.isEmpty ? "Untitled" : note.title
            let labelHeight: Float = note.kind == .page ? 0.13 : 0.11
            let label = Self.label(title, color: textColor, height: labelHeight)
            let lift: Float = radius + 0.08
            label.simdPosition = SIMD3<Float>(0, lift, 0)
            node.addChildNode(label)
            world.addChildNode(node)

            let info = GraphNodeInfo(id: note.id, node: node, label: label, kind: note.kind,
                                     root: store.rootFolder(of: note.folderId), home: p)
            infos.append(info)
        }

        // soft light: an even ambient wash and one gentle light from over the
        // viewer's shoulder, carried with the camera so the shading stays
        // the same however the space is turned
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = dark ? 520 : 700
        ambient.color = UIColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // the camera stands well back, leaving plenty of empty space round
        // the notes
        let camera = SCNCamera()
        camera.fieldOfView = 55
        camera.zNear = 0.05
        let far: Float = extent * 12 + 20
        camera.zFar = Double(far)
        // no HDR, bloom or glare: those put a glow round every bright dot
        camera.wantsHDR = false
        camera.bloomIntensity = 0
        camera.wantsExposureAdaptation = false
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let distance: Float = extent * 2.6 + 3
        let cameraHome = SIMD3<Float>(0, 0, distance)
        cameraNode.simdPosition = cameraHome
        scene.rootNode.addChildNode(cameraNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = dark ? 380 : 450
        sun.color = UIColor.white
        sun.castsShadow = false
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.simdEulerAngles = SIMD3<Float>(-0.6, 0.45, 0)
        cameraNode.addChildNode(sunNode)

        // titles come within reach as the camera comes closer; from where it
        // starts only a small space shows any
        let scaledReach: Float = distance * 0.55
        let labelReach: Float = max(scaledReach, 5.5)
        let sim = GraphSim(world: world, infos: infos, edges: edges, lines: lines,
                           lineMaterial: lineMaterial, lively: lively, labelReach: labelReach)
        return GraphScene(scene: scene, camera: cameraNode, cameraHome: cameraHome, sim: sim)
    }

    /// The palette colour lifted towards white, for soft pastel fills. Less
    /// so at night, where pale colours would glare.
    static func pastel(_ color: UIColor, dark: Bool) -> UIColor {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
        let lift: CGFloat = dark ? 0.2 : 0.4
        let red: CGFloat = r + (1 - r) * lift
        let green: CGFloat = g + (1 - g) * lift
        let blue: CGFloat = b + (1 - b) * lift
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }

    /// A small flat title that always faces the camera. It starts hidden;
    /// GraphSim fades it in when the note is near enough.
    private static func label(_ text: String, color: UIColor, height: Float) -> SCNNode {
        let shown: String = text.count > 28 ? String(text.prefix(27)) + "\u{2026}" : text
        let geometry = SCNText(string: shown, extrusionDepth: 0)
        geometry.font = UIFont.systemFont(ofSize: 10, weight: .regular)
        geometry.flatness = 0.3
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        geometry.materials = [material]

        let textNode = SCNNode(geometry: geometry)
        // centred over the point, sitting on it
        let (low, high) = textNode.boundingBox
        let middleX: Float = (low.x + high.x) / 2
        textNode.pivot = SCNMatrix4MakeTranslation(middleX, low.y, 0)
        // a 10-point font is about 10 units tall; shrink it to `height`
        let scale: Float = height / 10
        textNode.scale = SCNVector3(x: scale, y: scale, z: scale)

        let holder = SCNNode()
        holder.name = "label"
        holder.renderingOrder = 20
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

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
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

    func updateUIView(_ view: SCNView, context: Context) {
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

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
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
        private var cameraHome = SIMD3<Float>(0, 0, 10)
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

        init(onTap: @escaping (UUID) -> Void, recenter: Int) {
            self.onTap = onTap
            self.recenterCount = recenter
        }

        /// Shows a newly built scene.
        func attach(_ built: GraphScene, to view: SCNView) {
            sim = built.sim
            camera = built.camera
            cameraHome = built.cameraHome
            shownFilter = nil
            // the simulation steps on SceneKit's render loop, once per frame
            view.delegate = built.sim
            view.scene = built.scene
            view.pointOfView = built.camera
            view.defaultCameraController.target = SCNVector3(x: 0, y: 0, z: 0)
            view.isPlaying = true
            wireCameraGestures(in: view)
            built.sim.appear()
        }

        func apply(_ filter: GraphFilter) {
            guard let sim else { return }
            if shownFilter == filter { return }
            shownFilter = filter
            sim.apply(filter)
        }

        /// Glides the camera back to where it started, looking at the middle.
        func recentre() {
            guard let view, let camera else { return }
            view.pointOfView = camera
            view.defaultCameraController.target = SCNVector3(x: 0, y: 0, z: 0)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.6
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            camera.simdPosition = cameraHome
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
            let options: [SCNHitTestOption: Any] = [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue,
                SCNHitTestOption.ignoreHiddenNodes: true
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
