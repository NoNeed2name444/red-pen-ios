import SwiftUI
import AVFoundation
import Vision
#if canImport(VisionKit) && !SWIFT_PACKAGE
import VisionKit
#endif

// Study Lens's two cameras. Both read text on this device and nowhere else;
// no frame is kept or sent.
//
// - VisionKit's live scanner (DataScannerViewController), in the Xcode build
//   on devices that support it: Apple's own text finding and tracking, with
//   the recognised text highlighted as it is found.
// - Everywhere else (the Swift Playgrounds build, older devices): the camera
//   through AVCaptureSession, a frame read by Vision now and then - how often
//   set by the Graphics setting, and not at all while nothing moves.

// MARK: - The capture-session camera

/// The camera and its reader for the fallback path. Frames arrive on the
/// camera's own queue; at most one is read at a time, no more often than
/// the interval allows, and none while reading is paused.
final class LensCaptureCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "study.lens.camera", qos: .userInitiated)
    private let lock = NSLock()
    private var active = true
    private var interval: Double = 0.3
    private var fast = false
    private var busy = false
    private var lastRead: Double = 0
    private(set) var device: AVCaptureDevice?
    private var configured = false

    /// Called on the main thread with each read frame's text and the frame's
    /// size (upright).
    var onBlocks: (([LensTextBlock], CGSize) -> Void)?

    static var hasCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    /// Sets the session up once. False when there is no usable camera.
    func configure(smooth: Bool) -> Bool {
        if configured { return true }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return false }
        session.beginConfiguration()
        session.sessionPreset = smooth ? .hd1280x720 : .hd1920x1080
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        session.commitConfiguration()
        if camera.isFocusModeSupported(.continuousAutoFocus), (try? camera.lockForConfiguration()) != nil {
            camera.focusMode = .continuousAutoFocus
            camera.unlockForConfiguration()
        }
        device = camera
        configured = true
        return true
    }

    func start() {
        queue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// How reading goes now: paused or not, how often, and whether to read
    /// fast (Smooth) or accurately.
    func setReading(active: Bool, interval: Double, fast: Bool) {
        lock.lock()
        self.active = active
        self.interval = interval
        self.fast = fast
        lock.unlock()
    }

    /// Turns the frames upright for the way the phone is held.
    func setCaptureAngle(_ angle: CGFloat) {
        queue.async {
            guard let connection = self.output.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }

    /// Whether this frame may be read, and marks it taken.
    private func claim(at time: Double) -> (ok: Bool, fast: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard active, !busy, time - lastRead >= interval else { return (false, fast) }
        busy = true
        lastRead = time
        return (true, fast)
    }

    private func release() {
        lock.lock()
        busy = false
        lock.unlock()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let time: Double = ProcessInfo.processInfo.systemUptime
        let claimed = claim(at: time)
        guard claimed.ok else { return }
        defer { release() }
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels))
        let blocks: [LensTextBlock] = Self.read(pixels, fast: claimed.fast)
        DispatchQueue.main.async { [weak self] in
            self?.onBlocks?(blocks, size)
        }
    }

    /// The text in one frame, boxes flipped to a top-left origin.
    static func read(_ pixels: CVPixelBuffer, fast: Bool) -> [LensTextBlock] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.012
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        let found: [VNRecognizedTextObservation] = request.results ?? []
        return found.compactMap { observation -> LensTextBlock? in
            guard let best = observation.topCandidates(1).first else { return nil }
            return LensTextBlock(best.string, LensLayout.flipped(observation.boundingBox))
        }
    }
}

/// The capture session's live picture, kept upright as the device turns.
struct LensCameraPreview: UIViewRepresentable {
    let camera: LensCaptureCamera

    func makeUIView(context: Context) -> LensPreviewView {
        let view = LensPreviewView()
        view.attach(camera)
        return view
    }

    func updateUIView(_ view: LensPreviewView, context: Context) {}
}

final class LensPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var watching: [NSKeyValueObservation] = []
    private weak var camera: LensCaptureCamera?

    func attach(_ camera: LensCaptureCamera) {
        self.camera = camera
        guard let previewLayer else { return }
        previewLayer.session = camera.session
        previewLayer.videoGravity = .resizeAspectFill
        guard let device = camera.device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotation = coordinator
        let preview = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyRotation() }
        }
        let capture = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyRotation() }
        }
        watching = [preview, capture]
        applyRotation()
    }

    private func applyRotation() {
        guard let rotation else { return }
        let previewAngle: CGFloat = rotation.videoRotationAngleForHorizonLevelPreview
        if let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(previewAngle) {
            connection.videoRotationAngle = previewAngle
        }
        camera?.setCaptureAngle(rotation.videoRotationAngleForHorizonLevelCapture)
    }
}

// MARK: - VisionKit's live scanner

#if canImport(VisionKit) && !SWIFT_PACKAGE
/// Apple's live text scanner, with its own highlighting. Reports the text it
/// is tracking whenever it changes, as often as the lens wants it.
struct LensDataScanner: UIViewControllerRepresentable {
    var smooth: Bool
    var paused: Bool
    var shouldRead: () -> Bool
    var onBlocks: ([LensTextBlock], CGSize) -> Void

    static var isUsable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let quality: DataScannerViewController.QualityLevel = smooth ? .balanced : .accurate
        let scanner = DataScannerViewController(recognizedDataTypes: [.text()],
                                                qualityLevel: quality,
                                                recognizesMultipleItems: true,
                                                isHighFrameRateTrackingEnabled: !smooth,
                                                isPinchToZoomEnabled: true,
                                                isGuidanceEnabled: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        if paused && scanner.isScanning {
            scanner.stopScanning()
        } else if !paused && !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: LensDataScanner

        init(parent: LensDataScanner) {
            self.parent = parent
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            take(scanner, allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            take(scanner, allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didRemove removedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            take(scanner, allItems)
        }

        private func take(_ scanner: DataScannerViewController, _ items: [RecognizedItem]) {
            guard parent.shouldRead() else { return }
            let size: CGSize = scanner.view.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            let blocks: [LensTextBlock] = items.flatMap { Self.blocks(of: $0, in: size) }
            parent.onBlocks(blocks, size)
        }

        /// One recognised item as blocks, one per line of its text, each given
        /// its share of the item's height.
        static func blocks(of item: RecognizedItem, in size: CGSize) -> [LensTextBlock] {
            guard case .text(let text) = item else { return [] }
            let b = item.bounds
            let xs: [CGFloat] = [b.topLeft.x, b.topRight.x, b.bottomLeft.x, b.bottomRight.x]
            let ys: [CGFloat] = [b.topLeft.y, b.topRight.y, b.bottomLeft.y, b.bottomRight.y]
            let minX: CGFloat = xs.min() ?? 0
            let minY: CGFloat = ys.min() ?? 0
            let rect = CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
            let box: CGRect = LensLayout.normalised(rect, in: size)
            let lines: [String] = text.transcript.components(separatedBy: .newlines).filter { !$0.isEmpty }
            guard lines.count > 1 else { return [LensTextBlock(text.transcript, box)] }
            let share: CGFloat = box.height / CGFloat(lines.count)
            return lines.enumerated().map { pair -> LensTextBlock in
                let y: CGFloat = box.minY + share * CGFloat(pair.offset)
                return LensTextBlock(pair.element, CGRect(x: box.minX, y: y, width: box.width, height: share))
            }
        }
    }
}
#endif

/// Which live camera this device gets.
enum LensCameraKind {
    case scanner, capture, unavailable

    @MainActor static var best: LensCameraKind {
        #if canImport(VisionKit) && !SWIFT_PACKAGE
        if LensDataScanner.isUsable { return .scanner }
        #endif
        return LensCaptureCamera.hasCamera ? .capture : .unavailable
    }
}
