import SwiftUI
import AVFoundation
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

/// Study Lens: point the camera at exam questions - a past paper, a textbook,
/// a slide, a friend's screen - and each question found gets a small chip
/// where it sits. Tapping a chip opens the question answered and explained in
/// the way its type needs, with a button to keep it in any study mode.
///
/// The camera's pictures are read on this device and never leave it. Only the
/// words of a question the student taps are sent to answer it.
struct StudyLensView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var notes: NoteStore
    @Environment(\.graphics) private var graphics
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = LensModel(smooth: false)
    @State private var camera = LensCaptureCamera()
    @State private var kind: LensCameraKind = LensCameraKind.best
    @State private var access: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var still: LensStill?
    @State private var reading = false
    @State private var problem: String?
    @State private var selected: DetectedQuestion?
    @State private var photoItem: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var choosingFile = false

    private var smooth: Bool { graphics.tier == .smooth }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let still {
                LensStillView(still: still, reduceMotion: reduceMotion) { selected = $0 }
            } else {
                liveLayer
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .overlay(alignment: .top) { statusBanner }
        .navigationTitle("Study Lens")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $selected) { question in
            LensAnswerSheet(question: question, model: model)
                .environmentObject(store)
                .environmentObject(notes)
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photoItem, matching: .images)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.pdf, .image]) { result in
            if case .success(let url) = result { readFile(url) }
        }
        .onChange(of: photoItem) { _, item in
            if let item { readPhoto(item) }
        }
        .onChange(of: smooth) { _, value in
            model.setSmooth(value)
            syncCamera()
        }
        .onChange(of: model.paused) { _, _ in syncCamera() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startLive() } else { stopLive() }
        }
        .onAppear {
            model.setSmooth(smooth)
            prepareCamera()
        }
        .onDisappear { stopLive() }
    }

    // MARK: live

    @ViewBuilder
    private var liveLayer: some View {
        switch (access, kind) {
        case (_, .unavailable):
            noCamera
        case (.authorized, .scanner):
            scannerLayer
        case (.authorized, .capture):
            LensCameraPreview(camera: camera)
                .ignoresSafeArea()
                .overlay { LensChipLayer(chips: model.chips, frame: model.frameSize, fill: true,
                                         outlines: true, reduceMotion: reduceMotion) { selected = $0 } }
        case (.notDetermined, _):
            ProgressView().tint(.white)
        default:
            noCamera
        }
    }

    @ViewBuilder
    private var scannerLayer: some View {
        #if canImport(VisionKit) && !SWIFT_PACKAGE
        LensDataScanner(smooth: smooth, paused: model.paused,
                        shouldRead: { model.shouldRead() },
                        onBlocks: { blocks, size in model.ingest(blocks, frame: size) })
            .ignoresSafeArea()
            .overlay { LensChipLayer(chips: model.chips, frame: model.frameSize, fill: false,
                                     outlines: false, reduceMotion: reduceMotion) { selected = $0 } }
        #else
        EmptyView()
        #endif
    }

    private var noCamera: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
                .accessibilityHidden(true)
            Text(access == .denied || access == .restricted
                 ? "Study Lens needs the camera to read questions. Nothing it sees is kept or sent."
                 : "There is no camera to use here. Read a photo or a PDF instead.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            if access == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.glass)
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
    }

    private func prepareCamera() {
        kind = LensCameraKind.best
        guard kind != .unavailable else { return }
        if access == .notDetermined {
            Task {
                let granted: Bool = await AVCaptureDevice.requestAccess(for: .video)
                access = granted ? .authorized : .denied
                startLive()
            }
        } else {
            startLive()
        }
    }

    private func startLive() {
        guard access == .authorized, still == nil else { return }
        model.start()
        guard kind == .capture else { return }
        guard camera.configure(smooth: smooth) else {
            kind = .unavailable
            return
        }
        camera.onBlocks = { blocks, size in model.ingest(blocks, frame: size) }
        syncCamera()
        camera.start()
    }

    private func stopLive() {
        model.stop()
        if kind == .capture { camera.stop() }
    }

    private func syncCamera() {
        guard kind == .capture else { return }
        camera.setReading(active: !model.paused, interval: model.readInterval, fast: smooth)
    }

    // MARK: status and controls

    @ViewBuilder
    private var statusBanner: some View {
        if reading {
            banner(Label("Reading\u{2026}", systemImage: "text.viewfinder"))
        } else if let problem {
            banner(Label(problem, systemImage: "exclamationmark.triangle"))
                .onTapGesture { self.problem = nil }
        } else if model.paused && still == nil && access == .authorized {
            Button {
                model.resume()
            } label: {
                banner(Label("Paused to save battery \u{2013} move or tap to resume", systemImage: "pause.circle"))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts reading questions again")
        }
    }

    private func banner<L: View>(_ label: L) -> some View {
        label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassEffect(.regular.tint(.black.opacity(0.25)), in: .capsule)
            .padding(.top, 8)
            .padding(.horizontal, 16)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Label("Pictures stay on this device. Only a question you tap is sent to be answered.",
                  systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                if still != nil {
                    Button { backToLive() } label: {
                        Label("Live", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(.glass)
                }
                Button { choosingPhoto = true } label: {
                    Label("Scan a photo", systemImage: "photo")
                }
                .buttonStyle(.glass)
                Button { choosingFile = true } label: {
                    Label("PDF or file", systemImage: "doc.viewfinder")
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            if let still, still.pageCount > 1 { pageStepper(still) }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func pageStepper(_ still: LensStill) -> some View {
        HStack(spacing: 16) {
            Button { showPage(still.page - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(still.page <= 0)
                .accessibilityLabel("Previous page")
            Text("Page \(still.page + 1) of \(still.pageCount)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.white)
            Button { showPage(still.page + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(still.page + 1 >= still.pageCount)
                .accessibilityLabel("Next page")
        }
        .buttonStyle(.glass)
    }

    // MARK: stills

    private func backToLive() {
        still = nil
        model.reset()
        startLive()
    }

    private func readPhoto(_ item: PhotosPickerItem) {
        photoItem = nil
        reading = true
        problem = nil
        Task {
            let data: Data? = try? await item.loadTransferable(type: Data.self)
            let image: CGImage? = data.flatMap { PhotoOcclusionReader.thumbnail($0) }.flatMap { PhotoOcclusionReader.flattened($0) }
            await show(image, pdf: nil, page: 0, count: 1)
        }
    }

    private func readFile(_ url: URL) {
        reading = true
        problem = nil
        Task {
            // a copy of our own, so later pages can still be read after the
            // borrowed file is handed back
            let local: URL = FileManager.default.temporaryDirectory.appendingPathComponent("lens-" + url.lastPathComponent)
            let scoped: Bool = url.startAccessingSecurityScopedResource()
            try? FileManager.default.removeItem(at: local)
            try? FileManager.default.copyItem(at: url, to: local)
            if scoped { url.stopAccessingSecurityScopedResource() }
            if let pdf = PDFDocument(url: local) {
                let image: CGImage? = LensStill.render(pdf, page: 0)
                await show(image, pdf: pdf, page: 0, count: pdf.pageCount)
            } else {
                let data: Data? = try? Data(contentsOf: local)
                let image: CGImage? = data.flatMap { PhotoOcclusionReader.thumbnail($0) }.flatMap { PhotoOcclusionReader.flattened($0) }
                await show(image, pdf: nil, page: 0, count: 1)
            }
        }
    }

    private func showPage(_ page: Int) {
        guard let current = still, let pdf = current.pdf, page >= 0, page < pdf.pageCount else { return }
        reading = true
        Task {
            let image: CGImage? = LensStill.render(pdf, page: page)
            await show(image, pdf: pdf, page: page, count: pdf.pageCount)
        }
    }

    /// Reads a still picture off the main thread and shows it with its chips.
    private func show(_ image: CGImage?, pdf: PDFDocument?, page: Int, count: Int) async {
        guard let image else {
            reading = false
            problem = "That picture could not be opened."
            return
        }
        stopLive()
        let found: [DetectedQuestion] = await Task.detached(priority: .userInitiated) { () -> [DetectedQuestion] in
            let lines: [OCRLine] = (try? RedPenOCR.read(image)) ?? []
            let blocks: [LensTextBlock] = lines.map { LensTextBlock($0.text, LensLayout.flipped($0.box)) }
            return QuestionDetector.detect(blocks)
        }.value
        reading = false
        still = LensStill(image: UIImage(cgImage: image), questions: found, pdf: pdf, page: page, pageCount: count)
        if found.isEmpty { problem = "No questions found on this page." }
    }
}

// MARK: - A still page

/// A photo or a PDF page being read, with the questions found on it.
struct LensStill {
    var image: UIImage
    var questions: [DetectedQuestion]
    var pdf: PDFDocument?
    var page: Int
    var pageCount: Int

    /// One PDF page drawn at up to 2,048 pixels on its long side, on white.
    static func render(_ pdf: PDFDocument, page: Int) -> CGImage? {
        guard let p = pdf.page(at: page) else { return nil }
        let bounds: CGRect = p.bounds(for: .mediaBox)
        let long: CGFloat = max(bounds.width, bounds.height, 1)
        let scale: CGFloat = 2048 / long
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let picture: UIImage = p.thumbnail(of: size, for: .mediaBox)
        guard let cg = picture.cgImage else { return nil }
        return PhotoOcclusionReader.flattened(cg)
    }
}

/// A still picture shown whole, with a chip on each question.
struct LensStillView: View {
    let still: LensStill
    let reduceMotion: Bool
    let open: (DetectedQuestion) -> Void

    var body: some View {
        let tracks: [LensTrack] = still.questions.prefix(12).enumerated().map { pair in
            LensTrack(id: pair.offset, question: pair.element, box: pair.element.box, hits: 1, misses: 0)
        }
        Image(uiImage: still.image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("The page being read")
            .overlay {
                LensChipLayer(chips: tracks, frame: still.image.size, fill: false, outlines: true,
                              reduceMotion: reduceMotion, open: open)
            }
            .padding(.top, 8)
    }
}

// MARK: - Chips

/// The collapsed chips over the picture, one per question, each at its
/// question's top left and moving with it.
struct LensChipLayer: View {
    let chips: [LensTrack]
    /// The size of the picture the boxes are fractions of.
    let frame: CGSize
    /// Drawn aspect-fill (the live camera) or aspect-fit (a still).
    let fill: Bool
    /// Faint outlines round each question, where nothing else marks them.
    let outlines: Bool
    let reduceMotion: Bool
    let open: (DetectedQuestion) -> Void

    @ScaledMetric(relativeTo: .caption) private var chipHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .caption) private var chipWidth: CGFloat = 104

    var body: some View {
        GeometryReader { geo in
            let rects: [CGRect] = chips.map { place($0.box, in: geo.size) }
            let normal: [CGRect] = rects.map { LensLayout.normalised($0, in: geo.size) }
            let origins: [CGPoint] = LensLayout.chipOrigins(normal, chip: CGSize(width: chipWidth, height: chipHeight),
                                                            in: geo.size)
            ZStack(alignment: .topLeading) {
                if outlines {
                    ForEach(Array(chips.enumerated()), id: \.element.id) { pair in
                        outline(rects[pair.offset])
                    }
                }
                ForEach(Array(chips.enumerated()), id: \.element.id) { pair in
                    LensChip(question: pair.element.question) { open(pair.element.question) }
                        .offset(x: origins[pair.offset].x, y: origins[pair.offset].y)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: chips)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Questions found")
    }

    private func place(_ box: CGRect, in size: CGSize) -> CGRect {
        guard frame.width > 0, frame.height > 0 else {
            return CGRect(x: box.minX * size.width, y: box.minY * size.height,
                          width: box.width * size.width, height: box.height * size.height)
        }
        return fill ? LensLayout.fill(box, image: frame, view: size) : LensLayout.fit(box, image: frame, view: size)
    }

    private func outline(_ rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .offset(x: rect.minX, y: rect.minY)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// One collapsed chip: "Q · MCQ".
struct LensChip: View {
    let question: DetectedQuestion
    let action: () -> Void

    var body: some View {
        let tint: Color = LensStyle.tint(question.type)
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: question.type.symbol)
                    .font(.caption.weight(.bold))
                Text(label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .fixedSize()
            .glassEffect(.regular.tint(tint.opacity(0.55)).interactive(), in: .capsule)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(question.type.spokenName + ": " + question.preview)
        .accessibilityHint("Opens the answer and explanation")
    }

    private var label: String {
        let number: String = question.number.map { "Q" + $0 } ?? "Q"
        return number + " \u{00B7} " + question.type.chipLabel
    }
}

/// Colours for the lens, by question type: the colour of the mode the type
/// belongs to.
enum LensStyle {
    static func tint(_ type: LensQuestionType) -> Color {
        let destination: LensDestination = LensDestination.suggested(for: type)
        return tint(destination)
    }

    static func tint(_ destination: LensDestination) -> Color {
        guard let kind = destination.kind else { return Color.yellow }
        return kind.tint
    }
}
