import SwiftUI

// The Performance theme (GraphTheme.performance) in the Ideas map: the
// engine's Metal map (GraphPerfMapView) in place of the SceneKit scene,
// with the map's own controls round it unchanged (Graph3DView: the filter,
// the Look menu, Recentre, the peek card, a body's options). This file is
// the glue: it builds the engine's scene off the main thread from the
// adapter's snapshot (or a synthetic vault of 100,000 or 300,000 notes, the
// readout's demo), and turns the engine's hits back into notes and folders.

/// The demo maps the readout offers (never the owner's notes).
enum GraphPerfDemo {
    static let key: String = "vignette.space.perfDemo"
    static let sizes: [Int] = [100_000, 300_000]
}

/// The map with its speed readout (top left): notes, links, frames a
/// second, and what this frame drew; its menu swaps in a demo vault.
struct GraphPerfSpace: View {
    let source: GraphPerfSource?
    let filter: GraphFilter
    let recenter: Int
    var command = GraphMapCommand()
    var chosen: UUID? = nil
    var linksFor: UUID? = nil
    var touch = GraphTouchHandlers()
    var bold: Bool = false
    @AppStorage(GraphPerfDemo.key) private var demo: Int = 0
    @State private var stats = GraphPerfStats()
    @Environment(\.graphics) private var graphics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                map(insets: geo.safeAreaInsets)
            }
            .ignoresSafeArea()
            readout
                .padding(.leading, 16)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func map(insets: EdgeInsets) -> some View {
        #if canImport(Metal) && canImport(MetalKit)
        GraphPerfMap(source: source, demo: demoInForce, filter: filter, recenter: recenter, insets: insets,
                     command: command, chosen: chosen, linksFor: linksFor, touch: touch, tier: tier, bold: bold,
                     reduceMotion: reduceMotion, onStats: { stats = $0 })
        #else
        Text("This device cannot draw the fast map.")
        #endif
    }

    /// The demo asked for: the stored choice, or the design preview's.
    private var demoInForce: Int {
        GraphPreview.isOn ? (GraphPreview.perfDemo ?? 0) : demo
    }

    private var demoBinding: Binding<Int> {
        GraphPreview.isOn ? .constant(demoInForce) : $demo
    }

    /// High quality or Smooth (the Graphics setting); Low Power Mode saves more.
    private var tier: GraphPerfTier {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return .saver }
        return graphics.tier == .high ? .high : .smooth
    }

    private var readout: some View {
        Menu {
            Picker("Map", selection: demoBinding) {
                Text("Your notes").tag(0)
                Text("Demo: 100,000 notes").tag(GraphPerfDemo.sizes[0])
                Text("Demo: 300,000 notes").tag(GraphPerfDemo.sizes[1])
            }
            .pickerStyle(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.line)
                    .font(.caption.monospacedDigit().weight(.semibold))
                Text(stats.drawn)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Speed")
        .accessibilityValue(stats.line)
        .accessibilityHint("How fast the map draws. Opens the demo maps of 100,000 and 300,000 notes.")
        .accessibilityIdentifier("perfReadout")
    }
}

#if canImport(Metal) && canImport(MetalKit)
/// The engine's map view in SwiftUI.
struct GraphPerfMap: UIViewRepresentable {
    let source: GraphPerfSource?
    let demo: Int
    let filter: GraphFilter
    let recenter: Int
    let insets: EdgeInsets
    let command: GraphMapCommand
    let chosen: UUID?
    let linksFor: UUID?
    let touch: GraphTouchHandlers
    let tier: GraphPerfTier
    let bold: Bool
    let reduceMotion: Bool
    let onStats: (GraphPerfStats) -> Void

    func makeCoordinator() -> GraphPerfCoordinator {
        GraphPerfCoordinator(recenter: recenter, commandSerial: command.serial)
    }

    func makeUIView(context: Context) -> GraphPerfMapView {
        let view = GraphPerfMapView(frame: .zero)
        context.coordinator.attach(view)
        apply(to: view, context.coordinator)
        return view
    }

    func updateUIView(_ view: GraphPerfMapView, context: Context) {
        apply(to: view, context.coordinator)
    }

    static func dismantleUIView(_ view: GraphPerfMapView, coordinator: GraphPerfCoordinator) {
        coordinator.stop()
    }

    private func apply(to view: GraphPerfMapView, _ c: GraphPerfCoordinator) {
        c.touch = touch
        view.onStats = onStats
        view.reduceMotion = reduceMotion
        view.insets = (Float(insets.top), Float(insets.leading), Float(insets.bottom), Float(insets.trailing))
        view.preferredFPS = GraphQuality.frameRate
        view.setTier(tier, bold: bold)
        view.accessibilityLabel = GraphTheme.performance.mapLabel
        view.accessibilityHint = GraphTheme.performance.hint
        c.load(source: source, demo: demo)
        c.apply(filter: GraphPerfAdapter.filter(filter))
        c.choose(chosen, links: linksFor)
        if c.commandSerial != command.serial {
            c.commandSerial = command.serial
            c.run(command.kind)
        }
        if c.recenter != recenter {
            c.recenter = recenter
            view.recentre()
        }
    }
}

/// Builds the map off the main thread, and speaks for it to the Ideas map:
/// a hit on a body is that note or folder; on a folder's glow, that folder
/// (and the camera flies in). In a demo vault nothing reaches the notes: a
/// tap chooses the body on the map itself.
@MainActor
final class GraphPerfCoordinator {
    weak var view: GraphPerfMapView?
    var touch = GraphTouchHandlers()
    var recenter: Int
    var commandSerial: Int
    private(set) var scene: GraphPerfScene?
    private var loadedKey: String = ""
    private var building: Task<Void, Never>?
    private var demo: Bool = false
    private var filter: GraphPerfFilter = .all
    private var maskedScene: Int = -1
    private var sceneNumber: Int = 0
    private var chosenID: UUID?
    private var linksID: UUID?

    init(recenter: Int, commandSerial: Int) {
        self.recenter = recenter
        self.commandSerial = commandSerial
    }

    func attach(_ view: GraphPerfMapView) {
        self.view = view
        view.onTap = { [weak self] hit in self?.tapped(hit) }
        view.onDoubleTap = { [weak self] hit in self?.doubleTapped(hit) }
        view.onHold = { [weak self] hit, point in self?.held(hit, at: point) }
    }

    func stop() {
        building?.cancel()
        building = nil
        view?.metal.isPaused = true
    }

    /// Builds the map again when the notes changed or the demo was switched.
    func load(source: GraphPerfSource?, demo size: Int) {
        let key: String = size > 0 ? "demo \(size)" : "notes \(source?.version ?? -1)"
        guard key != loadedKey else { return }
        let input: GraphPerfInput? = size > 0 ? nil : source?.input
        guard size > 0 || input != nil else { return }
        loadedKey = key
        demo = size > 0
        building?.cancel()
        building = Task { [weak self] in
            let made: GraphPerfScene? = await Task.detached(priority: .userInitiated) { () -> GraphPerfScene? in
                let wanted: GraphPerfInput = input ?? GraphPerfSynthetic.make(GraphPerfSynthetic.Spec(notes: size))
                return GraphPerfScene.build(wanted)
            }.value
            guard !Task.isCancelled, let self, let made else { return }
            self.show(made)
        }
    }

    private func show(_ made: GraphPerfScene) {
        scene = made
        sceneNumber += 1
        view?.show(made)
        applyMask()
        applyChoice()
    }

    func apply(filter next: GraphPerfFilter) {
        guard next != filter || maskedScene != sceneNumber else { return }
        filter = next
        applyMask()
    }

    private func applyMask() {
        guard let scene, let view else { return }
        maskedScene = sceneNumber
        view.setMask(demo ? nil : scene.graph.mask(filter))
    }

    /// What the Ideas map has chosen, and whose links it shows.
    func choose(_ id: UUID?, links: UUID?) {
        guard !demo else { return }
        guard id != chosenID || links != linksID else { return }
        chosenID = id
        linksID = links
        applyChoice()
    }

    private func applyChoice() {
        guard let scene, let view, !demo else { return }
        view.select(chosenID.flatMap { scene.body($0) })
        view.focus(linksID.flatMap { scene.body($0) })
    }

    /// A request from the card: a link chip's glide, Fly in, the design preview's hold.
    func run(_ kind: GraphMapCommand.Kind) {
        guard let scene, let view else { return }
        switch kind {
        case .select(let id, let glide):
            if glide, let b = scene.body(id) { view.fly(toBody: b) }
        case .flyIn(let id):
            guard let b = scene.body(id) else { return }
            if scene.isNote(b) {
                view.fly(toBody: b)
            } else {
                view.fly(toCluster: b - scene.graph.noteCount)
            }
        case .previewHold(let id):
            guard let b = scene.body(id), let point = view.screenPoint(of: b) else { return }
            let hold: (UUID, CGPoint) -> Void = touch.hold
            DispatchQueue.main.async { hold(id, point) }
        case .none, .clear, .links:
            break
        }
    }

    private func tapped(_ hit: GraphPerfHit?) {
        guard let scene, let view else { return }
        switch hit {
        case .body(let b)?:
            if demo {
                view.select(b)
            } else {
                touch.select(scene.id(b))
            }
        case .cluster(let s)?:
            view.fly(toCluster: s)
            if !demo && s < scene.graph.folderCount { touch.select(scene.graph.folderIDs[s]) }
        case nil:
            if demo {
                view.select(nil)
            } else {
                touch.select(nil)
            }
        }
    }

    private func doubleTapped(_ hit: GraphPerfHit?) {
        guard let scene, let view, case .body(let b)? = hit else { return }
        if demo {
            view.fly(toBody: b)
        } else if let id = scene.id(b) {
            touch.double(id)
        }
    }

    private func held(_ hit: GraphPerfHit, at point: CGPoint) {
        guard let scene, !demo else { return }
        switch hit {
        case .body(let b):
            if let id = scene.id(b) { touch.hold(id, point) }
        case .cluster(let s):
            if s < scene.graph.folderCount { touch.hold(scene.graph.folderIDs[s], point) }
        }
    }
}
#endif
