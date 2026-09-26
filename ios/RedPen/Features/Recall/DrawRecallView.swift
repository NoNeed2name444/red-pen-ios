import SwiftUI
import PencilKit

/// Draw a figure from memory, then lay the real one over it.
///
/// Drawing a diagram from a blank page is the hardest way to recall it and so
/// the one that sticks: seeing the brachial plexus a hundred times is not the
/// same as having to put the cords in the right order yourself. The figure's
/// title stays hidden until asked for, and the picture itself does not appear
/// until Compare.
///
/// Compare puts the original over the drawing at half strength, with a slider
/// to fade from one to the other, and lists the figure's labels so the student
/// can tick the ones they got. Each attempt is kept, on this device, per
/// figure. A finger works as well as a Pencil.
struct DrawRecallView: View {
    let figure: RecallFigure
    /// A kept attempt to open with, already drawn - used by the example.
    let opening: RecallAttempt?

    @Environment(\.dismiss) private var dismiss
    /// The window as the presenter measured it, until this screen has
    /// measured its own.
    @Environment(\.windowSpan) private var outerSpan

    @State private var drawing = PKDrawing()
    /// Changes whenever the drawing is replaced from here rather than drawn,
    /// so the canvas knows to take it.
    @State private var canvasVersion = UUID()
    @State private var comparing = false
    /// 0 is only the drawing, 1 only the original; half way shows both.
    @State private var fade = 0.5
    @State private var showTitle = false
    @State private var got: Set<String> = []
    @State private var attemptID: UUID?
    @State private var attempts: [RecallAttempt] = []
    @State private var paperSize: CGSize = .zero
    @State private var pendingOpen: RecallAttempt?
    @State private var measuredSpan: WindowSpan?
    /// The drawing as a picture of the paper it was drawn on, shown in place
    /// of the canvas while comparing - see `paper`.
    @State private var drawnPicture: UIImage?
    /// Where the tool picker covers the window when it is docked, in window
    /// points; null while it floats or is hidden.
    @State private var pickerFrame: CGRect = .null
    /// The Compare pill's row, in the same points, to keep it clear of the
    /// docked tool picker.
    @State private var pillRow: CGRect = .zero

    init(figure: RecallFigure, opening: RecallAttempt? = nil) {
        self.figure = figure
        self.opening = opening
    }

    private var span: WindowSpan { measuredSpan ?? outerSpan }
    /// Most of an iPad: Compare moves from the top corner to the bottom
    /// right, under the right hand. On a phone PencilKit's tool picker docks
    /// at the bottom, so Compare stays at the top there.
    private var broad: Bool { span == .broad }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                prompt
                paper
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            // one bottom container: the compare panel, or on a wide iPad the
            // Compare pill
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomContainer }
            .modeScreen(.anki)
            .navigationTitle(comparing ? "Compare" : "Draw from memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
        .environment(\.windowSpan, span)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            let now = WindowSpan(width: width)
            if now != measuredSpan { measuredSpan = now }
        }
        // PencilKit: the UI holds its still pose, and the camera stays off
        .popOutFrozen()
        .popOutFacePaused()
        .onAppear {
            attempts = RecallAttempts.load(figure.key)
            pendingOpen = opening
            openPendingIfReady()
        }
    }

    /// Close first, always (Esc too). While drawing: the ellipsis menu with
    /// Clear drawing, and on a phone Compare.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        if !comparing {
            ToolbarItem(placement: .topBarTrailing) {
                drawingMenu
            }
        }
        if !comparing && !broad {
            ToolbarItem(placement: .confirmationAction) {
                Button("Compare") { compare() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    /// The rare, destructive things, out of the way of the pen.
    private var drawingMenu: some View {
        Menu {
            Button(role: .destructive) {
                clearDrawing()
            } label: {
                Label("Clear drawing", systemImage: "trash")
            }
            .disabled(drawing.strokes.isEmpty)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    // MARK: - Pieces

    private var prompt: some View {
        HStack(alignment: .center, spacing: 8) {
            promptText
            Spacer(minLength: 8)
            if !comparing && !figure.title.isEmpty {
                titleEye
            }
        }
        .frame(minHeight: 44)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var promptText: some View {
        if showTitle || comparing {
            Text(figure.title.isEmpty ? "Untitled figure" : figure.title)
                .font(.subheadline.weight(.semibold))
        } else {
            Text("Draw it as you remember it, labels and all.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Shows or hides the figure's title: an eye beside the prompt.
    private var titleEye: some View {
        let symbol: String = showTitle ? "eye.slash" : "eye"
        let label: String = showTitle ? "Hide title" : "Show title"
        return Button {
            showTitle.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .accessibleGlass(.regular.interactive(), in: Circle())
                .popOut(.raised, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
    }

    /// The drawing, with the original over it when comparing. Both share the
    /// picture's proportions, so what is drawn lines up with what is there.
    /// It lies on the glass: never moved by the pop-out.
    ///
    /// The compare panel takes room from the paper, and the canvas's strokes
    /// keep their point positions while the original shrinks with it. So
    /// while comparing, the canvas stays in place but unseen, and a picture
    /// of the drawing - taken on the whole paper it was drawn on - is shown
    /// instead: it scales exactly as the original does.
    private var paper: some View {
        ZStack {
            Color.white
            PencilCanvas(drawing: $drawing, enabled: !comparing, version: canvasVersion,
                         pickerFrame: $pickerFrame)
                .opacity(comparing ? 0 : 1)
            if comparing {
                RecallCompareLayers(drawn: drawnPicture, original: figure.image, fade: fade)
            }
        }
        .aspectRatio(paperRatio, contentMode: .fit)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { measured(geo.size) }
                    .onChange(of: geo.size) { _, now in measured(now) }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The paper's width over its height: the picture's, or 4:3 when the
    /// picture has no usable size - a zero or broken size would make the
    /// layout divide by zero, and a view with no size cannot be drawn on.
    private var paperRatio: CGFloat {
        let size = figure.image.size
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return 4.0 / 3.0 }
        let ratio: CGFloat = size.width / size.height
        return ratio
    }

    /// The screen's one bottom container.
    @ViewBuilder
    private var bottomContainer: some View {
        if comparing {
            comparePanel
                .frame(maxWidth: 820)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
        } else if broad {
            comparePillRow
        }
    }

    /// Compare at the bottom right. A tool picker docked along the bottom
    /// can cover it, so then the pill rises just clear of the picker. It
    /// is moved, not re-laid-out, so the paper keeps its size.
    private var comparePillRow: some View {
        let lift: CGFloat = Self.pillLift(row: pillRow, picker: pickerFrame)
        return HStack {
            Spacer(minLength: 0)
            comparePill
                .offset(y: -lift)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if frame != pillRow { pillRow = frame }
        }
        .animation(.snappy(duration: 0.2), value: lift)
    }

    /// How far the Compare row must rise to sit above a docked tool picker.
    /// Both frames are in window points.
    static func pillLift(row: CGRect, picker: CGRect) -> CGFloat {
        guard !picker.isNull, !picker.isEmpty, row.width > 0, row.height > 0 else { return 0 }
        guard picker.intersects(row) else { return 0 }
        let clear: CGFloat = row.maxY - picker.minY
        return max(0, clear)
    }

    /// On a wide iPad: Compare as the screen's hero, bottom right.
    private var comparePill: some View {
        Button(action: compare) {
            Label("Compare", systemImage: "square.on.square")
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .popOut(.hero, in: Capsule())
        .hoverEffect(.lift)
        .keyboardShortcut(.return, modifiers: [])
    }

    private var comparePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            labelsPart
            if attempts.count > 1 { pastAttempts }
            fadeRow
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // the screen's bottom slab, floating like every study bar's
        .popOut(.floating, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var labelsPart: some View {
        if figure.labels.isEmpty {
            Text("No labels are saved with this figure, so judge it by eye: shape, position, what connects to what.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Tick the labels you got \u{2014} \(got.count) of \(figure.labels.count)")
                .font(.caption.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(figure.labels, id: \.self) { label in
                        RecallLabelTick(label: label, ticked: got.contains(label)) { toggle(label) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 176)
        }
    }

    /// The panel's bottom row, under the thumbs: the fade between the two,
    /// and Draw again - the hero - at the trailing end.
    private var fadeRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 2) {
                Slider(value: $fade, in: 0...1)
                    .accessibilityLabel("Fade between your drawing and the original")
                HStack {
                    Text("Yours")
                    Spacer(minLength: 8)
                    Text("Original")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            Button("Draw again") { startAgain() }
                .buttonStyle(BigButtonStyle(weight: .primary, fills: false))
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    private var pastAttempts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Earlier attempts").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attempts) { attempt in
                        Button { load(attempt) } label: { thumbnail(attempt) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func thumbnail(_ attempt: RecallAttempt) -> some View {
        let here = attempt.id == attemptID
        return VStack(spacing: 2) {
            Group {
                if let picture = Self.picture(of: attempt) {
                    Image(uiImage: picture).resizable().scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: 64, height: 44)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(here ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), lineWidth: here ? 2 : 1))
            Text(attempt.date.formatted(.dateTime.day().month(.abbreviated)))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if attempt.labelCount > 0 {
                Text("\(attempt.got.count)/\(attempt.labelCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Attempt from \(attempt.date.formatted(date: .abbreviated, time: .shortened))")
    }

    // MARK: - What the buttons do

    private func measured(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return }
        paperSize = size
        openPendingIfReady()
    }

    /// Opens the attempt asked for once the paper has a size to scale it to.
    private func openPendingIfReady() {
        guard let attempt = pendingOpen, paperSize.width > 0 else { return }
        pendingOpen = nil
        load(attempt, comparing: false)
    }

    /// Keeps the drawing as an attempt and shows the original over it.
    private func compare() {
        if !drawing.strokes.isEmpty, paperSize.width > 0 {
            let id = attemptID ?? UUID()
            let earlier = attempts.first { $0.id == id }
            let attempt = RecallAttempt(id: id, date: earlier?.date ?? Date(),
                                        drawing: drawing.dataRepresentation(),
                                        width: Double(paperSize.width), height: Double(paperSize.height),
                                        got: Array(got), labelCount: figure.labels.count)
            RecallAttempts.save(attempt, for: figure.key)
            attemptID = id
            attempts = RecallAttempts.load(figure.key)
        }
        // taken now, while the paper is still the size it was drawn on
        let whole = CGRect(origin: .zero, size: paperSize)
        drawnPicture = Self.render(drawing, in: whole, scale: 2)
        fade = 0.5
        comparing = true
    }

    private func toggle(_ label: String) {
        if got.contains(label) { got.remove(label) } else { got.insert(label) }
        guard let id = attemptID, var attempt = attempts.first(where: { $0.id == id }) else { return }
        attempt.got = figure.labels.filter { got.contains($0) }
        attempt.labelCount = figure.labels.count
        RecallAttempts.save(attempt, for: figure.key)
        attempts = RecallAttempts.load(figure.key)
    }

    private func clearDrawing() {
        drawing = PKDrawing()
        canvasVersion = UUID()
    }

    private func startAgain() {
        drawing = PKDrawing()
        drawnPicture = nil
        canvasVersion = UUID()
        attemptID = nil
        got = []
        showTitle = false
        comparing = false
    }

    /// Puts a kept attempt back on the paper, scaled to this screen. When it
    /// opens in Compare, its picture is taken on the paper it was drawn on,
    /// so it lines up with the original whatever size the paper is now.
    private func load(_ attempt: RecallAttempt, comparing showOriginal: Bool = true) {
        guard !attempt.drawing.isEmpty,
              let kept = try? PKDrawing(data: attempt.drawing) else { return }
        var fitted: PKDrawing = kept
        if attempt.width > 0, paperSize.width > 0 {
            let scale: CGFloat = paperSize.width / CGFloat(attempt.width)
            if scale.isFinite, scale > 0 {
                fitted = kept.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
            }
        }
        drawing = fitted
        canvasVersion = UUID()
        attemptID = attempt.id
        got = Set(attempt.got)
        if showOriginal {
            let drawnOn = CGRect(x: 0, y: 0, width: attempt.width, height: attempt.height)
            let here = CGRect(origin: .zero, size: paperSize)
            let own: UIImage? = Self.render(kept, in: drawnOn, scale: 2)
            drawnPicture = own ?? Self.render(fitted, in: here, scale: 2)
            fade = 0.5
            comparing = true
        }
    }

    /// Draws strokes as a picture of `frame`, clear where nothing is drawn.
    /// The ink stays black in dark mode, as it is on the canvas. Nil for an
    /// empty drawing or a frame with no usable size.
    static func render(_ strokes: PKDrawing, in frame: CGRect, scale: CGFloat) -> UIImage? {
        guard !strokes.strokes.isEmpty else { return nil }
        guard frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0 else { return nil }
        guard scale.isFinite, scale > 0 else { return nil }
        var made: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            made = strokes.image(from: frame, scale: scale)
        }
        return made
    }

    /// A small picture of an attempt, framed on the paper it was drawn on.
    static func picture(of attempt: RecallAttempt) -> UIImage? {
        guard !attempt.drawing.isEmpty,
              let kept = try? PKDrawing(data: attempt.drawing) else { return nil }
        guard attempt.width.isFinite, attempt.height.isFinite,
              attempt.width > 0, attempt.height > 0 else { return nil }
        let frame = CGRect(x: 0, y: 0, width: attempt.width, height: attempt.height)
        // a thumbnail 64 points wide, at twice the pixels for a sharp screen
        let perPoint: CGFloat = 64 / frame.width
        let scale: CGFloat = perPoint * 2
        return render(kept, in: frame, scale: scale)
    }
}

/// What Compare lays on the paper: the drawing as a picture, and the original
/// over it. Both are fitted to the paper the same way, so they line up, and
/// the fade runs from one to the other.
private struct RecallCompareLayers: View {
    let drawn: UIImage?
    let original: UIImage
    /// 0 is only the drawing, 1 only the original.
    let fade: Double

    var body: some View {
        let yours: Double = min(1, 2 * (1 - fade))
        ZStack {
            if let drawn {
                Image(uiImage: drawn)
                    .resizable()
                    .scaledToFit()
                    .opacity(yours)
                    .accessibilityLabel("Your drawing")
            }
            Image(uiImage: original)
                .resizable()
                .scaledToFit()
                .opacity(fade)
                .accessibilityLabel("The original figure")
        }
        .allowsHitTesting(false)
    }
}

/// One figure label in the compare panel, ticked when the student got it.
private struct RecallLabelTick: View {
    let label: String
    let ticked: Bool
    let toggle: () -> Void

    var body: some View {
        let symbol: String = ticked ? "checkmark.circle.fill" : "circle"
        let ink: AnyShapeStyle = ticked ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)
        Button(action: toggle) {
            Label(label, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(ink)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityAddTraits(ticked ? [.isSelected] : [])
    }
}

/// PencilKit's canvas, for SwiftUI: draws with a Pencil or a finger, and
/// shows the system tool picker while drawing is allowed.
///
/// The tool picker is the fragile part. It may only be shown for a canvas that
/// is already on screen in a window, and the canvas may only be made first
/// responder then; asking earlier - while SwiftUI is still building the view,
/// or while a screen is being pushed or presented - is what used to bring the
/// app down. So nothing about the picker happens in `makeUIView`: it is set up
/// when the canvas arrives in a window (`didMoveToWindow`) and on later
/// updates only while it is still in one, and taken down when it leaves.
struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var enabled: Bool
    /// Changes when the drawing is replaced from outside - cleared, or an
    /// earlier attempt loaded - so the canvas takes the new one.
    var version: UUID
    /// Reported back: where the tool picker covers the window while it is
    /// docked, in window points; null while it floats or is hidden.
    @Binding var pickerFrame: CGRect

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> RecallCanvasView {
        let canvas = RecallCanvasView()
        // a finger draws as well as a Pencil, on iPhone and iPad alike
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // ink stays black on the white paper in dark mode too, so the drawing
        // and the original are the same colours when laid over each other
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.drawing = drawing
        canvas.isUserInteractionEnabled = enabled
        let coordinator = context.coordinator
        coordinator.version = version
        coordinator.enabled = enabled
        coordinator.canvas = canvas
        canvas.delegate = coordinator
        // weak both ways: the canvas must not keep its coordinator alive
        canvas.onWindowChange = { [weak coordinator] view in
            coordinator?.windowChanged(view)
        }
        return canvas
    }

    func updateUIView(_ canvas: RecallCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.version != version {
            coordinator.version = version
            coordinator.applying = true
            canvas.drawing = drawing
            coordinator.applying = false
        }
        canvas.isUserInteractionEnabled = enabled
        coordinator.enabled = enabled
        // only once it is on screen; before that didMoveToWindow does it
        if canvas.window != nil {
            coordinator.showPicker(on: canvas)
        }
    }

    static func dismantleUIView(_ canvas: RecallCanvasView, coordinator: Coordinator) {
        canvas.onWindowChange = nil
        canvas.delegate = nil
        coordinator.hidePicker(from: canvas)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver {
        var parent: PencilCanvas
        var version: UUID?
        var enabled = true
        /// The canvas looked after, to measure the tool picker against.
        weak var canvas: PKCanvasView?
        /// True while the drawing is being set from outside, so that is not
        /// reported back as the student drawing.
        var applying = false
        /// Held here, strongly: a tool picker nobody holds disappears. Made
        /// the first time the canvas is on screen, not before.
        private var picker: PKToolPicker?
        private var observing = false
        private var focusQueued = false

        init(_ parent: PencilCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !applying else { return }
            parent.drawing = canvasView.drawing
        }

        /// The canvas arrived in a window or left one.
        func windowChanged(_ canvas: PKCanvasView) {
            if canvas.window == nil {
                hidePicker(from: canvas)
            } else {
                showPicker(on: canvas)
            }
        }

        /// Shows the tool picker while drawing is allowed and hides it while
        /// comparing. Does nothing unless the canvas is in a window.
        func showPicker(on canvas: PKCanvasView) {
            guard canvas.window != nil else { return }
            let tools: PKToolPicker
            if let existing = picker {
                tools = existing
            } else {
                tools = PKToolPicker()
                picker = tools
            }
            if !observing {
                tools.addObserver(canvas)
                tools.addObserver(self)
                observing = true
            }
            tools.setVisible(enabled, forFirstResponder: canvas)
            if enabled {
                focus(canvas)
            } else if canvas.isFirstResponder {
                _ = canvas.resignFirstResponder()
            }
        }

        /// Takes the tool picker down and lets go of the keyboard focus. Safe
        /// to call more than once.
        func hidePicker(from canvas: PKCanvasView) {
            if let tools = picker {
                tools.setVisible(false, forFirstResponder: canvas)
                if observing {
                    tools.removeObserver(canvas)
                    tools.removeObserver(self)
                    observing = false
                }
            }
            if canvas.isFirstResponder {
                _ = canvas.resignFirstResponder()
            }
        }

        // MARK: where the tool picker sits

        /// The picker was docked, undocked, resized or moved. Measured on the
        /// next turn of the main loop, never in the middle of a SwiftUI
        /// update, whichever thread PencilKit calls from.
        nonisolated func toolPickerFramesObscuredDidChange(_ toolPicker: PKToolPicker) {
            Task { @MainActor [weak self] in self?.reportPickerFrame() }
        }

        nonisolated func toolPickerVisibilityDidChange(_ toolPicker: PKToolPicker) {
            Task { @MainActor [weak self] in self?.reportPickerFrame() }
        }

        /// Tells the screen where the docked picker covers the window, so
        /// Compare can stay clear of it.
        private func reportPickerFrame() {
            var frame: CGRect = .null
            if let tools = picker, tools.isVisible, let window = canvas?.window {
                frame = tools.frameObscured(in: window)
            }
            if parent.pickerFrame != frame { parent.pickerFrame = frame }
        }

        /// Makes the canvas first responder - which is what brings the tool
        /// picker up - on the next turn of the main loop, not in the middle
        /// of a SwiftUI update, and only if it is still on screen by then.
        private func focus(_ canvas: PKCanvasView) {
            guard !canvas.isFirstResponder, !focusQueued else { return }
            focusQueued = true
            DispatchQueue.main.async { [weak self, weak canvas] in
                self?.focusQueued = false
                guard let self, let canvas, self.enabled,
                      canvas.window != nil, !canvas.isFirstResponder else { return }
                _ = canvas.becomeFirstResponder()
            }
        }
    }
}

/// A PencilKit canvas that says when it arrives in a window or leaves one,
/// because that is the only safe moment to attach the tool picker.
final class RecallCanvasView: PKCanvasView {
    var onWindowChange: (@MainActor (RecallCanvasView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(self)
    }
}

/// "Draw it from memory" under a figure, and the drawing screen it opens.
struct DrawFromMemoryButton: View {
    let set: StudySet
    let imageIndex: Int
    let caption: String
    @EnvironmentObject private var store: Store
    @State private var figure: RecallFigure?

    init(set: StudySet, imageIndex: Int, caption: String) {
        self.set = set
        self.imageIndex = imageIndex
        self.caption = caption
    }

    var body: some View {
        Button {
            figure = RecallFigure(set: set, index: imageIndex, caption: caption, library: store.library)
        } label: {
            Label("Draw it from memory", systemImage: "pencil.and.scribble")
                .font(.caption.weight(.semibold))
                // a whole finger's worth of target, not just the words
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .fullScreenCover(item: $figure) { DrawRecallView(figure: $0) }
    }
}

/// The Examples tour's "Draw it from memory" row.
///
/// It presents the drawing screen full screen rather than pushing it: the
/// drawing screen has its own navigation bar, and a navigation stack pushed
/// inside another one - with a tool picker on top - is what crashed. The
/// example attempt is saved to disk when the row is tapped, not while the
/// list is being drawn.
struct DrawRecallExampleRow: View {
    @State private var figure: RecallFigure?
    @State private var opening: RecallAttempt?

    var body: some View {
        Button {
            opening = RecallExamples.seedIfNeeded()
            figure = RecallExamples.figure
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "pencil.and.scribble")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Draw it from memory").font(.body.weight(.semibold))
                    Text("An inguinal canal drawing ready to Compare")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("example-draw")
        .fullScreenCover(item: $figure) { shown in
            DrawRecallView(figure: shown, opening: opening)
        }
    }
}
