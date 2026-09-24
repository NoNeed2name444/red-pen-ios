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
        .aspectRatio(figure.image.size, contentMode: .fit)
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
        guard size.width > 0, size.height > 0 else { return }
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
        guard var kept = try? PKDrawing(data: attempt.drawing) else { return }
        if attempt.width > 0, paperSize.width > 0 {
            let scale = paperSize.width / CGFloat(attempt.width)
            kept = kept.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
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
        guard let kept = try? PKDrawing(data: attempt.drawing) else { return nil }
        let frame = CGRect(x: 0, y: 0, width: attempt.width, height: attempt.height)
        guard frame.width > 0, frame.height > 0 else { return nil }
        return kept.image(from: frame, scale: 64 / frame.width * 2)
    }
}

/// PencilKit's canvas, for SwiftUI: draws with a Pencil or a finger, and
/// shows the system tool picker while drawing is allowed.
struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var enabled: Bool
    /// Changes when the drawing is replaced from outside - cleared, or an
    /// earlier attempt loaded - so the canvas takes the new one.
    var version: UUID

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // ink stays black on the white paper in dark mode too, so the drawing
        // and the original are the same colours when laid over each other
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        context.coordinator.version = version
        context.coordinator.picker.addObserver(canvas)
        context.coordinator.picker.setVisible(enabled, forFirstResponder: canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.version != version {
            context.coordinator.version = version
            context.coordinator.applying = true
            canvas.drawing = drawing
            context.coordinator.applying = false
        }
        canvas.isUserInteractionEnabled = enabled
        context.coordinator.picker.setVisible(enabled, forFirstResponder: canvas)
        if enabled && !canvas.isFirstResponder {
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.picker.setVisible(false, forFirstResponder: canvas)
        coordinator.picker.removeObserver(canvas)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvas
        /// Kept here: a tool picker nobody holds disappears.
        let picker = PKToolPicker()
        var version: UUID?
        /// True while the drawing is being set from outside, so that is not
        /// reported back as the student drawing.
        var applying = false

        init(_ parent: PencilCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !applying else { return }
            parent.drawing = canvasView.drawing
        }
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
