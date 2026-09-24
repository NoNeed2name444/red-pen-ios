import SwiftUI
import SceneKit
import UIKit
import simd

/// The space: every note as a point in 3D and every connection as a thread
/// between two, the way Obsidian's graph shows a vault - but something to turn
/// round in the hand rather than a flat picture.
///
/// Pages are larger than ideas. Each folder is a faint glass bubble with its
/// notes gathered inside, so the shape of what you know - which topics are
/// crowded, which ideas are joined to nothing yet - can be seen at a glance.
/// Drag to turn it, pinch to come closer, tap a note to open it.
///
/// The layout is worked out once (ForceLayout3D, off the main thread) and
/// again only when notes or links change. It turns slowly on its own unless
/// Reduce Motion is on.
struct Graph3DView: View {
    @EnvironmentObject private var notes: NoteStore
    let open: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var built: GraphScene?

    var body: some View {
        Group {
            if notes.notes.isEmpty {
                ContentUnavailableView {
                    Label("Dump your first idea", systemImage: "cube.transparent")
                } description: {
                    Text("Every note appears here as a point in space, joined to the notes it links to. Type one in the bar above.")
                }
            } else if let built {
                GraphSCNView(scene: built.scene, camera: built.camera, onTap: open)
                    .overlay(alignment: .bottom) {
                        Text("Drag to turn \u{00B7} pinch to zoom \u{00B7} tap a note to open it")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: .capsule)
                            .padding(.bottom, 12)
                            .allowsHitTesting(false)
                    }
            } else {
                ProgressView()
            }
        }
        .task(id: signature) { await rebuild() }
    }

    /// Everything the picture depends on. When this changes the layout is
    /// worked out again; moving a card on the board does not change it.
    private var signature: String {
        let noteKey = notes.notes.map {
            "\($0.id.uuidString)|\($0.title)|\($0.kind.rawValue)|\($0.folderId?.uuidString ?? "")"
        }
        let edgeKey = notes.allEdges().map { $0.0.uuidString + $0.1.uuidString }
        let folderKey = notes.folders.map { "\($0.id.uuidString)|\($0.name)|\($0.parentId?.uuidString ?? "")" }
        return (noteKey + edgeKey + folderKey + ["\(reduceMotion)", "\(scheme == .dark)"])
            .joined(separator: "\n")
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
                                        dark: scheme == .dark, rotate: !reduceMotion)
    }
}

/// A built scene and the camera it is seen through.
struct GraphScene {
    let scene: SCNScene
    let camera: SCNNode
}

/// Turns notes and their positions into SceneKit nodes.
///
/// Each note's node is named "note:<id>", which is how a tap finds out which
/// note it landed on; a folder's bubble is named "folder:<id>".
@MainActor
enum GraphSceneBuilder {
    static func build(store: NoteStore, positions: [UUID: SIMD3<Float>], edges: [(UUID, UUID)],
                      dark: Bool, rotate: Bool) -> GraphScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        // everything hangs from one node, so turning the whole graph is
        // turning that
        let world = SCNNode()
        scene.rootNode.addChildNode(world)

        // SceneKit does not follow light and dark by itself, so the colours
        // are settled for the one in use
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let textColor = UIColor.label.resolvedColor(with: traits).withAlphaComponent(0.85)
        let lineColor = UIColor.secondaryLabel.resolvedColor(with: traits).withAlphaComponent(0.4)

        // folders: a faint bubble round each folder's notes
        var byFolder: [UUID: [SIMD3<Float>]] = [:]
        for note in store.notes {
            if let folder = note.folderId, let p = positions[note.id] {
                byFolder[folder, default: []].append(p)
            }
        }
        for (folderId, points) in byFolder {
            var centre = SIMD3<Float>(0, 0, 0)
            for p in points { centre += p }
            centre /= Float(points.count)
            var reach: Float = 0
            for p in points { reach = max(reach, simd_length(p - centre)) }
            let radius = max(reach + 0.6, 0.8)

            let sphere = SCNSphere(radius: CGFloat(radius))
            sphere.segmentCount = 36
            let material = SCNMaterial()
            material.diffuse.contents = NoteTone.uiColor(for: folderId, in: store).withAlphaComponent(0.10)
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            sphere.materials = [material]
            let bubble = SCNNode(geometry: sphere)
            bubble.name = "folder:\(folderId.uuidString)"
            bubble.simdPosition = centre
            // drawn after the notes, so they show through it
            bubble.renderingOrder = 10
            if let folder = store.folder(folderId) {
                let label = Self.label(folder.name, color: textColor, height: 0.34)
                label.simdPosition = SIMD3<Float>(0, radius + 0.2, 0)
                bubble.addChildNode(label)
            }
            world.addChildNode(bubble)
        }

        // connections: a thin thread from note to note
        for (a, b) in edges {
            guard let pa = positions[a], let pb = positions[b],
                  let thread = Self.thread(from: pa, to: pb, color: lineColor) else { continue }
            world.addChildNode(thread)
        }

        // notes: pages larger than ideas, coloured by folder
        for note in store.notes {
            guard let p = positions[note.id] else { continue }
            let radius: Float = note.kind == .page ? 0.22 : 0.13
            let sphere = SCNSphere(radius: CGFloat(radius))
            sphere.segmentCount = 24
            let material = SCNMaterial()
            material.diffuse.contents = NoteTone.uiColor(for: note.folderId, in: store)
            material.specular.contents = UIColor(white: 1, alpha: 0.25)
            sphere.materials = [material]
            let node = SCNNode(geometry: sphere)
            node.name = "note:\(note.id.uuidString)"
            node.simdPosition = p
            let title = note.title.isEmpty ? "Untitled" : note.title
            let label = Self.label(title, color: textColor, height: note.kind == .page ? 0.2 : 0.15)
            label.simdPosition = SIMD3<Float>(0, radius + 0.1, 0)
            node.addChildNode(label)
            world.addChildNode(node)
        }

        // the camera stands back far enough to see everything
        var extent: Float = 1
        for p in positions.values { extent = max(extent, simd_length(p)) }
        let camera = SCNCamera()
        camera.fieldOfView = 55
        camera.zNear = 0.05
        camera.zFar = Double(extent * 12 + 20)
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3<Float>(0, 0, extent * 2.4 + 2)
        scene.rootNode.addChildNode(cameraNode)

        if rotate {
            // a full turn in a minute and a half: alive, not busy
            world.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 90)))
        }
        return GraphScene(scene: scene, camera: cameraNode)
    }

    /// A small flat title that always faces the camera.
    private static func label(_ text: String, color: UIColor, height: Float) -> SCNNode {
        let shown = text.count > 28 ? String(text.prefix(27)) + "\u{2026}" : text
        let geometry = SCNText(string: shown, extrusionDepth: 0)
        geometry.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        geometry.flatness = 0.2
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]

        let textNode = SCNNode(geometry: geometry)
        // centred over the point, sitting on it
        let (low, high) = textNode.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation((low.x + high.x) / 2, low.y, 0)
        // a 10-point font is about 10 units tall; shrink it to `height`
        let scale = height / 10
        textNode.scale = SCNVector3(scale, scale, scale)

        let holder = SCNNode()
        holder.addChildNode(textNode)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        holder.constraints = [billboard]
        return holder
    }

    /// A thin cylinder from one point to another. SceneKit's cylinder stands
    /// along y, so it is turned from y onto the line between the two.
    private static func thread(from a: SIMD3<Float>, to b: SIMD3<Float>, color: UIColor) -> SCNNode? {
        let line = b - a
        let length = simd_length(line)
        guard length > 0.001 else { return nil }
        let cylinder = SCNCylinder(radius: 0.018, height: CGFloat(length))
        cylinder.radialSegmentCount = 6
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        cylinder.materials = [material]
        let node = SCNNode(geometry: cylinder)
        node.simdPosition = (a + b) / 2
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: line / length)
        return node
    }
}

/// SceneKit's view, wrapped so a tap can say which note it landed on -
/// something SwiftUI's SceneView does not report. Turning and zooming are
/// SceneKit's own camera control.
struct GraphSCNView: UIViewRepresentable {
    let scene: SCNScene
    let camera: SCNNode
    let onTap: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.scene = scene
        view.pointOfView = camera
        // keeps the slow turn going
        view.isPlaying = true
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTap = onTap
        if view.scene !== scene {
            view.scene = scene
            view.pointOfView = camera
            view.isPlaying = true
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onTap: (UUID) -> Void

        init(onTap: @escaping (UUID) -> Void) {
            self.onTap = onTap
        }

        /// Looks through everything under the finger - a folder's bubble is
        /// usually in front - for the nearest note, climbing from a label to
        /// the note it belongs to.
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue
            ])
            for hit in hits {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name, name.hasPrefix("note:"),
                       let id = UUID(uuidString: String(name.dropFirst(5))) {
                        onTap(id)
                        return
                    }
                    node = current.parent
                }
            }
        }
    }
}
