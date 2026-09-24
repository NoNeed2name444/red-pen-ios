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

    init(figure: RecallFigure, opening: RecallAttempt? = nil) {
        self.figure = figure
        self.opening = opening
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                prompt
                paper
                if comparing {
                    comparePanel
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(comparing ? "Compare" : "Draw from memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if comparing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Draw again") { startAgain() }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            drawing = PKDrawing()
                            canvasVersion = UUID()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Clear the drawing")
                        .disabled(drawing.strokes.isEmpty)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Compare") { compare() }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
        }
        .onAppear {
            attempts = RecallAttempts.load(figure.key)
            pendingOpen = opening
            openPendingIfReady()
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var prompt: some View {
        HStack(alignment: .firstTextBaseline) {
            if showTitle || comparing {
                Text(figure.title.isEmpty ? "Untitled figure" : figure.title)
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("Draw it as you remember it, labels and all.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !comparing && !figure.title.isEmpty {
                Button(showTitle ? "Hide title" : "Show title") { showTitle.toggle() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.top, 6)
    }

    /// The drawing, with the original over it when comparing. Both share the
    /// picture's proportions, so what is drawn lines up with what is there.
    private var paper: some View {
        ZStack {
            Color.white
            PencilCanvas(drawing: $drawing, enabled: !comparing, version: canvasVersion)
                .opacity(comparing ? min(1, 2 * (1 - fade)) : 1)
            if comparing {
                Image(uiImage: figure.image)
                    .resizable()
                    .scaledToFit()
                    .opacity(fade)
                    .allowsHitTesting(false)
                    .accessibilityLabel("The original figure")
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

    private var comparePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Yours").font(.caption.weight(.semibold))
                Slider(value: $fade, in: 0...1)
                    .accessibilityLabel("Fade between your drawing and the original")
                Text("Original").font(.caption.weight(.semibold))
            }
            if figure.labels.isEmpty {
                Text("No labels are saved with this figure, so judge it by eye: shape, position, what connects to what.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tick the labels you got \u{2014} \(got.count) of \(figure.labels.count)")
                    .font(.caption.weight(.semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(figure.labels, id: \.self) { label in
                            Button { toggle(label) } label: {
                                Label(label, systemImage: got.contains(label) ? "checkmark.circle.fill" : "circle")
                                    .font(.subheadline)
                                    .foregroundStyle(got.contains(label) ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(got.contains(label) ? [.isSelected] : [])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            if attempts.count > 1 { pastAttempts }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private func startAgain() {
        drawing = PKDrawing()
        canvasVersion = UUID()
        attemptID = nil
        got = []
        showTitle = false
        comparing = false
    }

    /// Puts a kept attempt back on the paper, scaled to this screen.
    private func load(_ attempt: RecallAttempt, comparing showOriginal: Bool = true) {
        guard !attempt.drawing.isEmpty,
              var kept = try? PKDrawing(data: attempt.drawing) else { return }
        if attempt.width > 0, paperSize.width > 0 {
            let scale: CGFloat = paperSize.width / CGFloat(attempt.width)
            if scale.isFinite, scale > 0 {
                kept = kept.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
            }
        }
        drawing = kept
        canvasVersion = UUID()
        attemptID = attempt.id
        got = Set(attempt.got)
        if showOriginal {
            fade = 0.5
            comparing = true
        }
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
        guard scale.isFinite, scale > 0 else { return nil }
        return kept.image(from: frame, scale: scale)
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
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvas
        var version: UUID?
        var enabled = true
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
                    observing = false
                }
            }
            if canvas.isFirstResponder {
                _ = canvas.resignFirstResponder()
            }
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
