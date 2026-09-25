import SwiftUI
import SceneKit
import UIKit
import simd

/// The space: every note as a soft point in 3D and every connection as a fine
/// thread between two, the way Obsidian's graph shows a vault - but something
/// to turn round in the hand rather than a flat picture.
///
/// It is a piece of deep space, seen through the screen as through a window:
/// it runs on under the bottom glass, and tilting the device turns it a
/// hair (see GraphSim's tilt rig), so it reads as being BEHIND the glass
/// while the controls stand out in front of it. Every note is a small black
/// hole - a black sphere, a thin photon ring hugging its rim and a tilted,
/// streaky accretion disk, tinted a little by its folder - and every link a
/// stream of plasma with an electric aura (see GraphLook). Pages are a little
/// larger than ideas.
///
/// Names stay out of the way: a note's name shows, on a solid dark pill just
/// the size of the words, only while the pointer hovers over it (iPad
/// trackpad, mouse or Pencil) or while it is pressed or dragged; it goes
/// when the finger lifts. Tapping it twice opens it. The only other controls
/// are two round tools: one to filter, one to bring the view back to the
/// middle.
///
/// It is alive rather than frozen: the notes drift gently, pop in with a small
/// bounce, and a note dragged with a finger pulls its neighbours along and
/// springs home when let go (see GraphSim). Drag empty space to turn it,
/// pinch to come closer. With Reduce Motion on the space stands still.
///
/// Where each note belongs is worked out by ForceLayout3D, off the main
/// thread, and again only when notes or links change.
struct Graph3DView: View {
    @EnvironmentObject private var notes: NoteStore
    let open: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The sky's shared switch (SpaceQuality): at .still - Low Power Mode,
    /// a hot device - the map holds still too.
    @Environment(\.spaceQuality) private var quality
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.layoutDirection) private var direction
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
                    Text("Every note appears here as a point in space, joined to the notes it links to. Type one in the bar below.")
                }
            } else if let built {
                space(built)
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

    /// The space itself, running on under the glass, with its tools in the
    /// safe area. The graph is fitted to the part of the view that is not
    /// under glass (the safe area, read here), so no note starts hidden
    /// under the bars. No SwiftUI transform ever touches the SceneKit view:
    /// its own tilt comes from inside the scene.
    private func space(_ built: GraphScene) -> some View {
        ZStack {
            GeometryReader { geo in
                let insets: GraphInsets = screenInsets(geo.safeAreaInsets)
                GraphSCNView(built: built, filter: filter, recenter: recenter,
                             insets: insets, onTap: open)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Space of ideas")
                    .accessibilityHint("Drag to turn, pinch to zoom. Press and hold a note to see its name; tap it twice to open it.")
                    .accessibilityIdentifier("graph3D")
            }
            .ignoresSafeArea()
        }
        .overlay {
            if filter != .all && shownCount == 0 {
                Text("Nothing here for this filter.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
        }
        .ideaTools { tools }
        // the space is always night, whatever the phone's setting
        .environment(\.colorScheme, .dark)
    }

    /// The safe area's insets, left and right as on screen.
    private func screenInsets(_ edges: EdgeInsets) -> GraphInsets {
        let rtl: Bool = direction == .rightToLeft
        let left: CGFloat = rtl ? edges.trailing : edges.leading
        let right: CGFloat = rtl ? edges.leading : edges.trailing
        return GraphInsets(top: Float(edges.top), left: Float(left),
                           bottom: Float(edges.bottom), right: Float(right))
    }

    // MARK: the tools

    private var filterSymbol: String {
        filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill"
    }

    /// The only controls on screen: filter, and back to the middle.
    @ViewBuilder
    private var tools: some View {
        let filtering: Bool = filter != .all
        let ink: Color = filtering ? Color.accentColor : Color.secondary
        let glass: Glass = IdeaToolGlass.glass(active: filtering)
        Menu {
            filterMenu
        } label: {
            IdeaToolFace(symbol: filterSymbol)
        }
        .foregroundStyle(ink)
        .glassEffect(glass, in: .circle)
        .popOut(.floating, in: Circle())
        .hoverEffect(.highlight)
        .accessibilityLabel("Filter")

        IdeaToolButton(symbol: "scope", label: "Recentre") {
            recenter += 1
        }
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
        parts.append("\(quality.rawValue)")
        parts.append("\(bold)")
        parts.append("\(highContrast)")
        return parts.joined(separator: "\n")
    }

    /// Reduce Transparency or Increase Contrast: brighter, solid links.
    private var bold: Bool {
        reduceTransparency || highContrast
    }

    /// Increase Contrast: black name pills with a white rim.
    private var highContrast: Bool {
        contrast == .increased
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
        let lively: Bool = !reduceMotion && quality != .still && SpaceQuality.current() != .still
        built = GraphSceneBuilder.build(store: notes, positions: worked.0, edges: edges,
                                        lively: lively, bold: bold, shaders: worked.1,
                                        pageRadius: worked.2, contrast: highContrast)
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
///       label (billboarded; hidden until hovered, pressed or chosen)
///         rim, pill, words
///
/// and the whole graph hangs from the scene as root -> tilt rig -> world:
/// the rig is turned a few hundredths of a radian by the device's tilt
/// (GraphSim), so the notes shift against the sky like things seen through
/// a window.
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
                      pageRadius: Float, contrast: Bool = false) -> GraphScene {
        let scene = SCNScene()
        // deep space: a sky of geometry kept round the camera (GraphSpace)
        scene.background.contents = UIColor.black
        let sky: SCNNode = GraphSpace.makeSky()
        scene.rootNode.addChildNode(sky)
        // root -> tilt rig -> world: the rig turns with the device's tilt
        let rig = SCNNode()
        rig.name = "tiltRig"
        scene.rootNode.addChildNode(rig)
        let world = SCNNode()
        rig.addChildNode(world)
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
            let label = Self.label(title, color: textColor, height: labelHeight, contrast: contrast)
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

        // kept for GraphSim's signature; names now show only when hovered,
        // pressed or chosen, not by distance
        let scaledReach: Float = distance * 0.55
        let labelReach: Float = max(scaledReach, 5.5)
        let simLooks = GraphSimLooks(linkMaterial: linkMaterial, hotRing: hotRing, hotDisk: hotDisk,
                                     clocked: clocked, emitters: emitters, trails: trails, sky: sky)
        let sim = GraphSim(world: world, rig: rig, infos: infos, edges: edges, lines: lines,
                           looks: simLooks, lively: lively, labelReach: labelReach)
        return GraphScene(scene: scene, camera: cameraNode, sim: sim, homes: homes, pad: pad)
    }

    /// A one-by-one square plane; each note scales it to size.
    private static func plane(_ material: SCNMaterial) -> SCNGeometry {
        let plane = SCNPlane(width: 1, height: 1)
        plane.materials = [material]
        return plane
    }

    /// A small flat title that always faces the camera, on a solid dark
    /// pill just the size of the words, with a thin lighter rim round it.
    /// Everything in it is fully opaque and drawn over the whole scene
    /// without depth testing, so no link, glow or note ever shows through or
    /// hides it. It starts hidden; GraphSim shows it for the hovered,
    /// pressed or chosen note.
    private static func label(_ text: String, color: UIColor, height: Float, contrast: Bool) -> SCNNode {
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

        // the pill hugs the words: a little room each side, less above and
        // below
        let textWidth: Float = (high.x - low.x) * scale
        let textHeight: Float = (high.y - low.y) * scale
        let padX: Float = height * 0.22
        let padY: Float = height * 0.10
        let pillWidth: Float = textWidth + padX * 2
        let pillHeight: Float = textHeight + padY * 2
        let pillColor: UIColor = contrast ? UIColor.black : Self.pillFill
        let pill = SCNPlane(width: CGFloat(pillWidth), height: CGFloat(pillHeight))
        pill.cornerRadius = CGFloat(pillHeight / 2)
        pill.materials = [Self.solid(pillColor)]
        let pillNode = SCNNode(geometry: pill)
        pillNode.simdPosition = SIMD3<Float>(0, textHeight / 2, -0.002)

        // the rim: one step behind the pill and a hair bigger all round
        let edge: Float = height * 0.12
        let rimWidth: Float = pillWidth + edge
        let rimHeight: Float = pillHeight + edge
        let rimColor: UIColor = contrast ? UIColor.white : Self.rimFill
        let rim = SCNPlane(width: CGFloat(rimWidth), height: CGFloat(rimHeight))
        rim.cornerRadius = CGFloat(rimHeight / 2)
        rim.materials = [Self.solid(rimColor)]
        let rimNode = SCNNode(geometry: rim)
        rimNode.simdPosition = SIMD3<Float>(0, textHeight / 2, -0.004)

        // drawn after everything else in the space: the rim, then the pill,
        // then the words on top
        rimNode.renderingOrder = 19
        pillNode.renderingOrder = 20
        textNode.renderingOrder = 21

        let holder = SCNNode()
        holder.name = "label"
        holder.renderingOrder = 20
        holder.addChildNode(rimNode)
        holder.addChildNode(pillNode)
        holder.addChildNode(textNode)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        holder.constraints = [billboard]
        return holder
    }

    /// A solid dark slate: dark enough for the pale words, not so black it
    /// reads as a hole.
    private static let pillFill = UIColor(red: 0.12, green: 0.13, blue: 0.19, alpha: 1)
    private static let rimFill = UIColor(red: 0.40, green: 0.43, blue: 0.55, alpha: 1)

    /// Fully opaque, unlit, and never tested against depth: it replaces what
    /// is behind it rather than blending with it.
    private static func solid(_ colour: UIColor) -> SCNMaterial {
        let look = SCNMaterial()
        look.diffuse.contents = colour
        look.lightingModel = .constant
        look.transparency = 1
        look.blendMode = .replace
        look.isDoubleSided = true
        look.writesToDepthBuffer = false
        look.readsFromDepthBuffer = false
        return look
    }
}

/// SceneKit's view, wrapped so a tap can say which note it landed on and a
/// drag on a note can move it - neither of which SwiftUI's SceneView offers.
/// Turning and zooming, when the finger is not on a note, are SceneKit's own
/// camera control.
///
/// - A finger (or Pencil, or click) down on a note shows its name for as
///   long as it is held (FramingSCNView forwards touch down and lift).
/// - One tap on a note chooses it: its ring brightens and there is a small
///   selection tick. One tap on empty space lets it go. A single tap never
///   opens anything, and never waits for a second.
/// - Two taps on a note open it. Two taps on empty space are SceneKit's own
///   (bring the camera back), which wait for ours to find no note there.
/// - The pointer (trackpad, mouse, Pencil hover) shows the name of the note
///   it is over.
///
/// A note is found by where it is on screen - the nearest within 28 points
/// of a finger, 16 of the pointer - with SceneKit's own hit test as the
/// fallback for a note drawn bigger than that up close.
struct GraphSCNView: UIViewRepresentable {
    let built: GraphScene
    let filter: GraphFilter
    let recenter: Int
    /// How much of the view is under glass on each side; the graph is
    /// framed to the rest.
    let insets: GraphInsets
    let onTap: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, recenter: recenter, insets: insets)
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
        view.onPress = { [weak coordinator] point in coordinator?.pressed(at: point) }
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = coordinator
        view.addGestureRecognizer(tap)
        coordinator.tapper = tap
        let twice = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.opened(_:)))
        twice.numberOfTapsRequired = 2
        twice.delegate = coordinator
        view.addGestureRecognizer(twice)
        coordinator.doubleTapper = twice
        let hover = UIHoverGestureRecognizer(target: coordinator, action: #selector(Coordinator.hovered(_:)))
        view.addGestureRecognizer(hover)
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
            coordinator.insets = insets
            coordinator.recentre()
        } else if coordinator.insets != insets {
            coordinator.inset(to: insets)
        }
    }

    static func dismantleUIView(_ view: FramingSCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: (UUID) -> Void
        var recenterCount: Int
        /// How much of the view is under glass; framing fits the rest.
        var insets: GraphInsets
        private(set) var sim: GraphSim?
        weak var view: SCNView?
        weak var panner: UIPanGestureRecognizer?
        weak var tapper: UITapGestureRecognizer?
        weak var doubleTapper: UITapGestureRecognizer?
        private var camera: SCNNode?
        /// The notes' homes and how far each reaches, for framing.
        private var homes: [SIMD3<Float>] = []
        private var pad: Float = 0
        /// Whether the graph was last framed for a wide (landscape) view;
        /// nil before the first framing.
        private var framedWide: Bool?
        /// Where the last framing put the camera, to tell whether it has
        /// been turned or zoomed since.
        private var framedPose: simd_float4x4?
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
        /// The camera's own drags and double taps already told to wait for
        /// ours.
        private var wired: Set<ObjectIdentifier> = []
        /// The design preview's drag has been started (see GraphPreview).
        private var previewDragged: Bool = false
        /// The design preview's chosen note has been picked (see GraphPreview).
        private var previewChosen: Bool = false
        /// Where the pointer was when the hovered note was last looked for.
        private var lastHover: CGPoint?
        /// The small tick when a note is chosen.
        private let chooser = UISelectionFeedbackGenerator()

        init(onTap: @escaping (UUID) -> Void, recenter: Int, insets: GraphInsets) {
            self.onTap = onTap
            self.recenterCount = recenter
            self.insets = insets
        }

        /// Shows a newly built scene.
        func attach(_ built: GraphScene, to view: SCNView) {
            sim = built.sim
            camera = built.camera
            homes = built.homes
            pad = built.pad
            framedWide = nil
            framedPose = nil
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
            } else if GraphPreview.chooses && !previewChosen {
                previewChosen = true
                runPreviewChoice()
            }
        }

        /// For the design preview (`-graphPreview` alone): a moment after
        /// the space appears, chooses the most-linked note and holds it as a
        /// press would, so the picture at rest shows one name on its pill.
        private func runPreviewChoice() {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, let sim = self.sim, let i = sim.busiestNote() else { return }
                sim.select(i)
                sim.press(i)
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

        /// The glass round the space changed (the switcher folded, the
        /// keyboard or the dock came or went). While the camera is still
        /// where the last framing left it, the graph glides to fit the new
        /// window; once it has been turned or zoomed, it is left alone and
        /// the next Recentre uses the new window.
        func inset(to new: GraphInsets) {
            insets = new
            guard framedWide != nil, untouched else { return }
            frame(animated: true)
        }

        /// Whether the camera is still where the last framing put it.
        private var untouched: Bool {
            guard let view, let camera, let pose = framedPose else { return false }
            guard view.pointOfView === camera else { return false }
            return Self.same(camera.simdTransform, pose)
        }

        private static func same(_ a: simd_float4x4, _ b: simd_float4x4) -> Bool {
            let gaps: [SIMD4<Float>] = [a.columns.0 - b.columns.0, a.columns.1 - b.columns.1,
                                        a.columns.2 - b.columns.2, a.columns.3 - b.columns.3]
            for gap in gaps where gap.max() > 0.001 || gap.min() < -0.001 {
                return false
            }
            return true
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
        /// one of the part not under glass, centred in that part, seen from
        /// the front.
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
            let window: GraphWindow = GraphFraming.window(width: Float(size.width),
                                                          height: Float(size.height), insets: insets)
            let distance: Float = GraphFraming.distance(points: turned, pad: pad, window: window)
            let home: SIMD3<Float> = GraphFraming.cameraHome(distance: distance, window: window)
            view.pointOfView = camera
            view.defaultCameraController.target = SCNVector3(x: 0, y: 0, z: 0)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.6 : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sim.world.simdOrientation = turn
            camera.simdPosition = home
            camera.simdOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            SCNTransaction.commit()
            framedPose = camera.simdTransform
        }

        /// The view is going: stop drawing and let go of the simulation.
        func stop() {
            view?.isPlaying = false
            view?.delegate = nil
        }

        // MARK: gestures

        /// SceneKit's camera control brings its own gestures. Each of its
        /// drags is told to wait until ours has decided the finger is not on
        /// a note, so a drag on a note moves the note and a drag anywhere
        /// else turns the space; and each of its double taps waits for ours
        /// to find no note under the finger, so two taps on a note open it
        /// and two taps on empty space still bring the camera back.
        private func wireCameraGestures(in view: SCNView) {
            for other in view.gestureRecognizers ?? [] {
                let key = ObjectIdentifier(other)
                if wired.contains(key) { continue }
                if let panner, other !== panner, other is UIPanGestureRecognizer {
                    other.require(toFail: panner)
                    wired.insert(key)
                } else if let doubleTapper, other !== doubleTapper,
                          let tap = other as? UITapGestureRecognizer, tap.numberOfTapsRequired == 2 {
                    other.require(toFail: doubleTapper)
                    wired.insert(key)
                }
            }
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let view else { return true }
            if gesture === doubleTapper {
                // only on a note; on empty space SceneKit's own double tap
                // takes over
                let point: CGPoint = gesture.location(in: view)
                return pick(at: point, radius: 28, in: view) != nil
            }
            guard gesture === panner else { return true }
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

        /// A single tap never holds up a double tap - ours or SceneKit's -
        /// and is never held up by one: choosing a note is instant.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            let involvesTap: Bool = gesture === tapper || other === tapper
            guard involvesTap else { return false }
            return gesture is UITapGestureRecognizer && other is UITapGestureRecognizer
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

        /// One tap: chooses the note under the finger (its ring brightens;
        /// its name showed only while it was pressed), or, on empty space,
        /// lets the chosen one go. Never opens.
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view, let sim else { return }
            let point: CGPoint = gesture.location(in: view)
            guard let i = pick(at: point, radius: 28, in: view) else {
                sim.clearSelection()
                return
            }
            // the second tap of a double tap lands here too: already chosen
            if sim.selectedNote == i { return }
            sim.select(i)
            chooser.selectionChanged()
        }

        /// Two taps on a note: open it.
        @objc func opened(_ gesture: UITapGestureRecognizer) {
            guard let view, let sim else { return }
            let point: CGPoint = gesture.location(in: view)
            guard let i = pick(at: point, radius: 28, in: view) else { return }
            if sim.selectedNote != i { sim.select(i) }
            onTap(sim.ids[i])
        }

        /// The pointer over the space: the note under it shows its name.
        /// Looked for again only once the pointer has moved 2 points.
        @objc func hovered(_ gesture: UIHoverGestureRecognizer) {
            guard let view, let sim else { return }
            switch gesture.state {
            case .began, .changed:
                let point: CGPoint = gesture.location(in: view)
                if let last = lastHover {
                    let dx: CGFloat = point.x - last.x
                    let dy: CGFloat = point.y - last.y
                    let moved: CGFloat = dx * dx + dy * dy
                    if moved <= 4 { return }
                }
                lastHover = point
                sim.hover(pick(at: point, radius: 16, in: view))
            default:
                lastHover = nil
                sim.hover(nil)
            }
        }

        /// A finger, Pencil or click down on the space (`point`), or lifted
        /// (nil): the note under it shows its name for as long as it is
        /// held. Taps, double taps and drags see the same touches as before.
        func pressed(at point: CGPoint?) {
            guard let sim else { return }
            guard let point, let view else {
                sim.press(nil)
                return
            }
            sim.press(pick(at: point, radius: 28, in: view))
        }

        /// The shown note nearest `point` on screen, within `radius` points;
        /// SceneKit's hit test when none is that close (a note drawn large,
        /// up close).
        private func pick(at point: CGPoint, radius: CGFloat = 28, in view: SCNView) -> Int? {
            guard let sim else { return nil }
            var best: Int?
            var bestSquared: CGFloat = radius * radius
            for (i, local) in sim.visiblePositions() {
                let world: SIMD3<Float> = sim.world.simdConvertPosition(local, to: nil)
                let scenePoint = SCNVector3(x: world.x, y: world.y, z: world.z)
                let projected: SCNVector3 = view.projectPoint(scenePoint)
                let depth: Float = projected.z
                guard depth >= 0, depth <= 1 else { continue }
                let dx: CGFloat = CGFloat(projected.x) - point.x
                let dy: CGFloat = CGFloat(projected.y) - point.y
                let squared: CGFloat = dx * dx + dy * dy
                if squared < bestSquared {
                    best = i
                    bestSquared = squared
                }
            }
            return best ?? noteIndex(at: point, in: view)
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
/// once it has a size and again when the phone turns; and when one finger
/// goes down on it and lifts, so a pressed note can show its name while it
/// is held. The touches still reach every gesture recogniser as before.
final class FramingSCNView: SCNView {
    var onResize: ((CGSize) -> Void)?
    /// Where a single finger went down, or nil when it lifts, is cancelled
    /// or a second finger joins it.
    var onPress: ((CGPoint?) -> Void)?
    private var lastSize: CGSize = .zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        let down: Int = event?.allTouches?.count ?? touches.count
        guard down == 1, let touch = touches.first else {
            onPress?(nil)
            return
        }
        onPress?(touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        onPress?(nil)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        onPress?(nil)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size: CGSize = bounds.size
        guard size != lastSize else { return }
        lastSize = size
        onResize?(size)
    }
}
