import SceneKit
import SwiftUI
import UIKit

/// The atlas's manifest, read once from the app's Anatomy folder.
enum AtlasLibrary {
    static let manifest: AnatomyManifest? = {
        guard let url = AnatomyAtlas.file("anatomy.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? AnatomyAtlas.manifest(from: data)
    }()

    /// The parts' names, for a link's line: "Heart, Blood vessels".
    static func names(of parts: [String]) -> String {
        let names: [String] = parts.compactMap { manifest?.part($0)?.name }
        return names.isEmpty ? ScienceTool.atlas.blurb : names.joined(separator: ", ")
    }
}

/// The 3D atlas (Resources/Anatomy, the Human Reference Atlas's male and
/// female organ sets, CC BY 4.0): turn the body with a finger, pinch to come
/// closer, tap a structure for its name. Male or Female switches the body;
/// the chips show or hide each body system and the structures that lie
/// inside others; the search finds any structure of the body by name.
/// Opened from a topic or a body system, it shows that topic's parts, in the
/// body that has them (the last body chosen when both do).
struct AnatomyAtlasView: View {
    var focus: [String] = []
    var title: String?
    /// A structure to choose once the atlas is in ("heart/VH_M_heart_left_ventricle"),
    /// for the screenshots (SciencePreviewScreen).
    var choosing: String?
    @StateObject private var model = AtlasModel()
    @State private var query = ""
    @AppStorage(AnatomySex.rememberedKey) private var lastBody = AnatomySex.male.rawValue

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                AtlasSceneView(model: model)
                    .accessibilityElement()
                    .accessibilityLabel("The body in 3D")
                    .accessibilityHint("Search for a structure to choose it.")
                    .accessibilityIdentifier("atlasScene")
                switch model.state {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Loading the atlas")
                case .failed(let why):
                    WardEmptyState(symbol: "exclamationmark.triangle", title: "The atlas could not be read", message: why)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready:
                    if let chosen = model.chosen {
                        AtlasChosenCard(chosen: chosen, onCloser: { model.frameChosen() }, onClose: { model.choose(nil) })
                            .padding(WardSpace.gutter)
                    }
                }
                if searching, let shown = model.shownBody {
                    AtlasSearchResults(query: query, atlasBody: shown) { part, structure in
                        model.reveal(part: part, structure: structure)
                        query = ""
                    }
                }
            }
            // kept while the other body loads, so the switch stays put
            if model.state != .loading || !model.systems.isEmpty {
                layers
            }
        }
        .wardScreen()
        .navigationTitle(title ?? ScienceTool.atlas.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Find a structure")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.frameShown()
                } label: {
                    Label("Fit the view", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityIdentifier("atlasFit")
            }
        }
        .task {
            let preferred: AnatomySex = AnatomySex(remembered: lastBody)
            let sex: AnatomySex = AtlasLibrary.manifest?.body(for: Set(focus), preferred: preferred) ?? preferred
            await model.load(focus: Set(focus), sex: sex)
            if let choosing { model.reveal(key: choosing) }
        }
        // a container, so the card and the chips keep their own identifiers
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anatomyAtlas")
    }

    /// Which body, then the layers: one chip per body system, the structures
    /// inside, and the topic's own parts alone when opened from one; the
    /// credit under them.
    private var layers: some View {
        VStack(alignment: .leading, spacing: WardSpace.s) {
            HStack(spacing: WardSpace.m) {
                WardSegmented(selection: Binding(get: { model.sex }, set: { sex in
                    lastBody = sex.rawValue
                    Task { await model.show(sex) }
                }), options: AnatomySex.allCases) { sex in
                    Text(sex.name)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Body")
                .accessibilityIdentifier("atlasBody")
                if !model.focus.isEmpty && model.focusHere.isEmpty {
                    Text("This topic's parts are in the other body.")
                        .font(.caption)
                        .foregroundStyle(Color.wardInkSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WardSpace.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WardSpace.s) {
                    if !model.focusHere.isEmpty {
                        WardFilterChip(text: "Only these", symbol: "scope", selected: model.onlyFocus) {
                            model.onlyFocus.toggle()
                        }
                        .accessibilityIdentifier("atlasOnlyThese")
                    }
                    ForEach(model.systems) { system in
                        WardFilterChip(text: system.name, selected: model.visible.contains(system)) {
                            model.toggle(system)
                        }
                        .accessibilityIdentifier("atlasLayer-\(system.rawValue)")
                    }
                    WardFilterChip(text: "Inside", symbol: "circle.dashed.inset.filled", selected: model.showInner) {
                        model.showInner.toggle()
                    }
                    .accessibilityIdentifier("atlasInside")
                }
                .padding(.horizontal, WardSpace.gutter)
            }
            Text("Human Reference Atlas organs (from the Visible Human Male and Female, U.S. National Library of Medicine), the NIH 3D skull and two TotalSegmentator CT scans, all CC BY 4.0.")
                .font(.caption2)
                .foregroundStyle(Color.wardInkSecondary)
                .padding(.horizontal, WardSpace.gutter)
        }
        .padding(.vertical, WardSpace.s)
    }
}

/// The chosen structure: its name, where it belongs, its tissue and its
/// UBERON identifier.
private struct AtlasChosenCard: View {
    let chosen: AtlasModel.Chosen
    let onCloser: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WardSpace.s) {
            HStack(alignment: .top, spacing: WardSpace.m) {
                VStack(alignment: .leading, spacing: WardSpace.xs) {
                    Text(chosen.structure.title)
                        .font(.headline)
                        .foregroundStyle(Color.wardInk)
                    Text(chosen.part.name + " \u{00B7} " + chosen.part.system.name)
                        .font(.caption)
                        .foregroundStyle(Color.wardInkSecondary)
                    if let origin = chosen.structure.origin {
                        Text(origin)
                            .font(.caption)
                            .foregroundStyle(Color.wardInkSecondary)
                    }
                }
                Spacer(minLength: WardSpace.s)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.wardCircle)
                .accessibilityLabel("Close")
            }
            HStack(spacing: WardSpace.s) {
                WardChip(text: chosen.structure.tissue.name, tone: .grey)
                if let id = chosen.structure.uberon, let link = chosen.structure.uberonURL, let url = URL(string: link) {
                    Link(id, destination: url)
                        .font(.caption.weight(.semibold))
                }
                Spacer(minLength: 0)
                Button("Look closer", action: onCloser)
                    .buttonStyle(.wardCompact)
                    .accessibilityIdentifier("atlasCloser")
            }
        }
        .frame(maxWidth: 520)
        .wardCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("atlasChosen")
    }
}

/// Structures of the body shown whose name holds every word typed, to choose one.
private struct AtlasSearchResults: View {
    let query: String
    let atlasBody: AnatomyBody
    let onChoose: (AtlasPart, AnatomyStructure) -> Void
    @Environment(\.dismissSearch) private var dismissSearch

    var body: some View {
        let found = AnatomyAtlas.search(query, in: atlasBody)
        List {
            if found.isEmpty {
                WardEmptyState(symbol: "magnifyingglass", title: "No results",
                               message: "Try a part of a name, such as \u{201C}femur\u{201D}, \u{201C}coronary\u{201D} or \u{201C}left kidney\u{201D}.")
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(Array(found.prefix(60).enumerated()), id: \.offset) { _, hit in
                    Button {
                        onChoose(hit.part, hit.structure)
                        dismissSearch()
                    } label: {
                        WardRow(symbol: "scope", title: hit.structure.title,
                                detail: hit.part.name + " \u{00B7} " + hit.part.system.name, chevron: false)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityIdentifier("atlasResult-\(hit.structure.node)")
                }
            } footer: {
                if found.count > 60 { Text("The first 60 of \(found.count); type more to narrow it.") }
            }
            .wardRowBackground()
        }
        .wardForm()
    }
}

/// The SCNView the model owns, in SwiftUI.
private struct AtlasSceneView: UIViewRepresentable {
    let model: AtlasModel

    func makeUIView(context: Context) -> SCNView { model.view }

    func updateUIView(_ view: SCNView, context: Context) {}
}

/// The scene: every structure a node named "part/structure", in materials by
/// tissue, under a camera that orbits the body and a light that rides with
/// it. Reading and building happen off the main thread; showing, hiding and
/// choosing on it.
@MainActor
final class AtlasModel: NSObject, ObservableObject {
    enum State: Equatable { case loading, ready, failed(String) }

    struct Chosen: Equatable {
        let part: AtlasPart
        let structure: AnatomyStructure
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var chosen: Chosen?
    @Published var visible: Set<AnatomySystem> = [] { didSet { applyVisibility() } }
    @Published var showInner = false { didSet { applyVisibility() } }
    @Published var onlyFocus = true { didSet { applyVisibility(); frameShown() } }
    @Published private(set) var sex: AnatomySex = .male
    /// The body on screen, once read.
    private(set) var shownBody: AnatomyBody?
    private(set) var focus: Set<String> = []
    /// The topic's parts that the body shown has.
    private(set) var focusHere: Set<String> = []
    private(set) var systems: [AnatomySystem] = []

    let view = SCNView(frame: .zero)
    private let scene = SCNScene()
    private let camera = SCNNode()
    private var nodes: [String: SCNNode] = [:]
    private var entries: [String: Chosen] = [:]
    /// Parts that hold structures inside others: their outer ones fade
    /// while "Inside" is on.
    private var hollow: Set<String> = []
    private var lit: (node: SCNNode, materials: [SCNMaterial])?

    override init() {
        super.init()
        let lens = SCNCamera()
        lens.zNear = 0.01
        lens.zFar = 20
        lens.fieldOfView = 35
        camera.camera = lens
        // a light that rides with the camera, and a soft fill
        let headlight = SCNNode()
        headlight.light = SCNLight()
        headlight.light?.type = .directional
        headlight.light?.intensity = 900
        camera.addChildNode(headlight)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 350
        scene.rootNode.addChildNode(fill)
        scene.rootNode.addChildNode(camera)

        view.scene = scene
        view.pointOfView = camera
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        // the Graphics budget's multisampling, as the Neurons map takes it
        view.antialiasingMode = GraphQuality.current.msaa >= 4 ? .multisampling4X : .multisampling2X
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        view.addGestureRecognizer(tap)
    }

    // MARK: loading

    func load(focus: Set<String>, sex: AnatomySex) async {
        guard shownBody == nil, state == .loading else { return }
        self.focus = focus
        await assemble(sex)
    }

    /// The other body: the scene emptied and built again, the layers as the
    /// topic wants them in it.
    func show(_ sex: AnatomySex) async {
        guard sex != self.sex || shownBody == nil, state != .loading else { return }
        choose(nil)
        for node in nodes.values { node.removeFromParentNode() }
        nodes = [:]
        entries = [:]
        hollow = []
        shownBody = nil
        state = .loading
        await assemble(sex)
    }

    /// One body read and put in the scene.
    private func assemble(_ sex: AnatomySex) async {
        self.sex = sex
        guard let manifest = AtlasLibrary.manifest, let body = manifest.body(sex) else {
            state = .failed("Its files are missing from this build.")
            return
        }
        let parts: [AtlasPart] = body.parts
        let built: [(part: AtlasPart, nodes: [SCNNode])] = await Task.detached(priority: .userInitiated) {
            AtlasModel.build(parts)
        }.value
        // another body chosen while this one was being read: that one wins
        guard self.sex == sex else { return }
        guard !built.isEmpty else {
            state = .failed("Its meshes could not be read.")
            return
        }
        for (part, made) in built {
            for (structure, node) in zip(part.structures, made) {
                let key: String = node.name ?? ""
                nodes[key] = node
                entries[key] = Chosen(part: part, structure: structure)
                scene.rootNode.addChildNode(node)
                if structure.inner { hollow.insert(part.id) }
            }
        }
        shownBody = body
        focusHere = focus.filter { body.part($0) != nil }
        let present: Set<AnatomySystem> = Set(built.map(\.part.system))
        systems = AnatomySystem.allCases.filter { present.contains($0) }
        let focused: Set<AnatomySystem> = Set(built.filter { focusHere.contains($0.part.id) }.map(\.part.system))
        visible = focused.isEmpty ? present : focused
        state = .ready
        frameShown()
    }

    /// Every part's nodes, built off the main thread.
    nonisolated private static func build(_ parts: [AtlasPart]) -> [(part: AtlasPart, nodes: [SCNNode])] {
        var materials: [AnatomyTissue: SCNMaterial] = [:]
        func material(_ tissue: AnatomyTissue) -> SCNMaterial {
            if let made = materials[tissue] { return made }
            let c = tissue.colour
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
            m.specular.contents = UIColor(white: 0.25, alpha: 1)
            m.shininess = 0.3
            m.lightingModel = .blinn
            // both faces of what is solid, so an open end (a vessel cut where
            // the organ set stops) shows its inside rather than a hole
            m.isDoubleSided = tissue.opacity == 1
            if tissue.opacity < 1 {
                m.transparency = tissue.opacity
                m.writesToDepthBuffer = false
                m.blendMode = .alpha
            }
            materials[tissue] = m
            return m
        }
        return parts.compactMap { part in
            guard let url = AnatomyAtlas.file(part.file), let data = try? Data(contentsOf: url),
                  let meshes = try? AnatomyAtlas.meshes(of: part, from: data) else { return nil }
            let made: [SCNNode] = zip(part.structures, meshes).map { structure, mesh in
                let node = SCNNode(geometry: geometry(mesh, material(structure.tissue)))
                node.name = part.id + "/" + structure.node
                // the see-through skin is drawn after what it covers
                if structure.tissue == .skin { node.renderingOrder = 10 }
                return node
            }
            return (part, made)
        }
    }

    nonisolated private static func geometry(_ mesh: AnatomyMesh, _ material: SCNMaterial) -> SCNGeometry {
        let positions: Data = mesh.positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let normals: Data = mesh.normals().withUnsafeBufferPointer { Data(buffer: $0) }
        let indices: Data = mesh.indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let stride: Int = MemoryLayout<Float>.size * 3
        let vertexSource = SCNGeometrySource(data: positions, semantic: .vertex, vectorCount: mesh.vertexCount,
                                             usesFloatComponents: true, componentsPerVector: 3,
                                             bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: stride)
        let normalSource = SCNGeometrySource(data: normals, semantic: .normal, vectorCount: mesh.vertexCount,
                                             usesFloatComponents: true, componentsPerVector: 3,
                                             bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: stride)
        let element = SCNGeometryElement(data: indices, primitiveType: .triangles, primitiveCount: mesh.triangleCount,
                                         bytesPerIndex: MemoryLayout<UInt32>.size)
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        geometry.materials = [material]
        return geometry
    }

    // MARK: showing

    func toggle(_ system: AnatomySystem) {
        if visible.contains(system) { visible.remove(system) } else { visible.insert(system) }
    }

    private func shows(_ entry: Chosen) -> Bool {
        visible.contains(entry.part.system)
            && (focusHere.isEmpty || !onlyFocus || focusHere.contains(entry.part.id))
            && (showInner || !entry.structure.inner)
    }

    private func applyVisibility() {
        for (key, entry) in entries {
            guard let node = nodes[key] else { continue }
            node.isHidden = !shows(entry)
            node.opacity = showInner && !entry.structure.inner && hollow.contains(entry.part.id) ? 0.25 : 1
        }
        if let chosen, nodes[nodeKey(chosen)]?.isHidden == true { choose(nil) }
    }

    private func nodeKey(_ entry: Chosen) -> String { entry.part.id + "/" + entry.structure.node }

    // MARK: choosing

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point: CGPoint = gesture.location(in: view)
        let hits: [SCNHitTestResult] = view.hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true,
        ])
        // past the see-through skin and anything faded, to what is solid
        let solid: SCNNode? = hits.map(\.node).first { node in
            node.opacity == 1 && entries[node.name ?? ""]?.structure.tissue != .skin
        }
        choose((solid ?? hits.first?.node)?.name)
    }

    func choose(_ key: String?) {
        if let lit { lit.node.geometry?.materials = lit.materials }
        lit = nil
        guard let key, let entry = entries[key], let node = nodes[key], let geometry = node.geometry else {
            chosen = nil
            return
        }
        let originals: [SCNMaterial] = geometry.materials
        geometry.materials = originals.map { original in
            let glowing: SCNMaterial = (original.copy() as? SCNMaterial) ?? SCNMaterial()
            glowing.emission.contents = UIColor(Color.wardBeam).withAlphaComponent(0.55)
            return glowing
        }
        lit = (node, originals)
        chosen = entry
    }

    /// A structure by its node's name ("part/structure"), as the search reveals one.
    func reveal(key: String) {
        guard let entry = entries[key] else { return }
        reveal(part: entry.part, structure: entry.structure)
    }

    /// A structure from the search: its layer shown, then chosen and framed.
    func reveal(part: AtlasPart, structure: AnatomyStructure) {
        let entry = Chosen(part: part, structure: structure)
        if !visible.contains(part.system) { visible.insert(part.system) }
        if !focusHere.isEmpty && onlyFocus && !focusHere.contains(part.id) { onlyFocus = false }
        if structure.inner && !showInner { showInner = true }
        choose(nodeKey(entry))
        frameChosen(context: true)
    }

    // MARK: the camera

    /// The chosen structure: close up ("Look closer"), or with its
    /// surroundings in view and lifted clear of the card below it, as a
    /// search or a topic opens it.
    func frameChosen(context: Bool = false) {
        guard let chosen, let node = nodes[nodeKey(chosen)] else { return }
        if context {
            frame([node], margin: 2.6, nearest: 0.3, lift: 0.18)
        } else {
            frame([node])
        }
    }

    /// Everything shown, or the whole scene when nothing is.
    func frameShown() {
        let shown: [SCNNode] = nodes.values.filter { !$0.isHidden }
        frame(shown.isEmpty ? Array(nodes.values) : shown)
    }

    /// margin: room around the box; nearest: the closest the camera comes;
    /// lift: how far up the view the box sits, as a share of the view's height.
    private func frame(_ targets: [SCNNode], margin: Float = 1.2, nearest: Float = 0.15, lift: Float = 0) {
        guard !targets.isEmpty else { return }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for node in targets {
            let box = node.boundingBox
            lo = pointwiseMin(lo, SIMD3(box.min.x, box.min.y, box.min.z))
            hi = pointwiseMax(hi, SIMD3(box.max.x, box.max.y, box.max.z))
        }
        let centre: SIMD3<Float> = (lo + hi) / 2
        // far enough back that the box fits both ways: the 35° is the view's
        // height, so a narrow portrait screen needs more room for the width
        let half: Float = tan(35 * .pi / 360)
        let bounds: CGSize = view.bounds.size
        let aspect: Float = bounds.height > 0 ? Float(bounds.width / bounds.height) : 1
        let tall: Float = (hi.y - lo.y) / 2 / half
        let wide: Float = max(hi.x - lo.x, hi.z - lo.z) / 2 / (half * max(0.3, aspect))
        let distance: Float = max(nearest, max(tall, wide) * margin + (hi.z - lo.z) / 2)
        // looking at a point below the box raises the box in the view
        let aim: SIMD3<Float> = centre - SIMD3(0, lift * 2 * distance * half, 0)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        camera.simdPosition = aim + SIMD3(0, 0, distance)
        camera.simdLook(at: aim)
        SCNTransaction.commit()
        // turning still turns about the structure, which keeps its place in the view
        view.defaultCameraController.target = SCNVector3(centre.x, centre.y, centre.z)
    }
}
