import SwiftUI
import CoreMotion

/// Where one question's answer is.
enum LensAnswerState: Equatable {
    case loading
    case done(LensAnswer)
    case failed(String)
}

/// Study Lens's state: the questions being followed in the live view, whether
/// reading is paused, and the answers asked for.
///
/// Everything the camera recognises stays on the device. A question's words
/// go to a model only when the student taps its chip, and only those words.
@MainActor
final class LensModel: ObservableObject {
    /// The chips on screen, in reading order.
    @Published private(set) var chips: [LensTrack] = []
    /// The size of the picture the chips' boxes are fractions of: the camera
    /// frame (drawn aspect-fill), or the scanner's own view.
    @Published private(set) var frameSize: CGSize = .zero
    /// Reading stopped because nothing moved or changed for a while.
    @Published private(set) var paused = false
    @Published private(set) var answers: [String: LensAnswerState] = [:]

    private var tracker = LensTracker()
    private var gate: LensActivityGate
    private let motion = CMMotionManager()
    private var detecting = false
    private var ticker: Timer?
    private var tasks: [String: Task<Void, Never>] = [:]
    private(set) var smooth: Bool

    static let noModel: String = "No model is ready to answer with. Apple Intelligence answers for free on devices that have it; otherwise choose one in AI models."

    init(smooth: Bool) {
        self.smooth = smooth
        self.gate = LensActivityGate(smooth: smooth)
    }

    /// The Graphics setting changed: Smooth reads less often.
    func setSmooth(_ value: Bool) {
        guard value != smooth else { return }
        smooth = value
        gate.interval = LensActivityGate.interval(smooth: value)
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    // MARK: live reading

    /// Starts watching for movement, which is what wakes reading after a
    /// pause. Without a motion sensor, reading never pauses on its own.
    func start() {
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.2
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                let magnitude: Double = LensModel.magnitude(data)
                // delivered on the main queue, as asked
                MainActor.assumeIsolated { self?.noteMotion(magnitude) }
            }
        } else {
            gate.stillAfter = .infinity
        }
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func noteMotion(_ magnitude: Double) {
        gate.noteMotion(magnitude, at: now)
    }

    /// How much the device is moving: acceleration (g) plus a quarter of
    /// its turning (rad/s).
    nonisolated static func magnitude(_ data: CMDeviceMotion) -> Double {
        let a = data.userAcceleration
        let r = data.rotationRate
        let accel: Double = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        let turn: Double = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        return accel + turn * 0.25
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        let still: Bool = !gate.isActive(at: now)
        if still != paused { paused = still }
    }

    /// Wakes reading at once.
    func resume() {
        gate.wake(at: now)
        paused = false
    }

    /// Whether the camera should read the frame it has now.
    func shouldRead() -> Bool {
        !detecting && gate.shouldRead(at: now)
    }

    /// Whether reading is live at all, for the camera's own throttle.
    var readInterval: Double { gate.interval }

    /// One frame's recognised text. Grouping runs off the main thread; a
    /// frame arriving while the last is still being grouped is dropped.
    func ingest(_ blocks: [LensTextBlock], frame: CGSize) {
        guard !detecting else { return }
        detecting = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let found: [DetectedQuestion] = QuestionDetector.detect(blocks)
            await MainActor.run {
                self?.apply(found, frame: frame)
            }
        }
    }

    private func apply(_ found: [DetectedQuestion], frame: CGSize) {
        detecting = false
        let before: Set<String> = tracker.visibleKeys
        tracker.update(found)
        let shown: [LensTrack] = tracker.visible
        gate.noteRead(changed: tracker.visibleKeys != before, at: now)
        if frame != frameSize { frameSize = frame }
        if shown != chips { chips = shown }
    }

    /// Forgets the chips (the camera closed, the source changed).
    func reset() {
        tracker.reset()
        chips = []
    }

    // MARK: answers

    func state(for q: DetectedQuestion) -> LensAnswerState? {
        answers[LensHash.answerKey(q)]
    }

    /// Asks for the answer to `q`, unless it is known or on its way. Cached
    /// by the question's words, so the same question seen again - or on
    /// another day - is answered at once. `again` asks afresh.
    func answer(_ q: DetectedQuestion, again: Bool = false) {
        let key: String = LensHash.answerKey(q)
        if !again {
            // known or on its way; a failure is tried again
            if let state = answers[key] {
                if case .failed = state {} else { return }
            }
            if let cached = LensAnswerCache.shared.answer(for: key) {
                answers[key] = .done(cached)
                return
            }
        }
        guard let backend = LocalLLMService.shared.writerOrApple() else {
            answers[key] = .failed(Self.noModel)
            return
        }
        tasks[key]?.cancel()
        answers[key] = .loading
        tasks[key] = Task { [weak self] in
            let result: Result<LensAnswer, Error> = await Self.ask(q, using: backend)
            guard !Task.isCancelled, let self else { return }
            switch result {
            case .success(var answer):
                answer.answeredBy = backend.label
                self.answers[key] = .done(answer)
                LensAnswerCache.shared.keep(answer, for: key)
            case .failure(let error):
                let text: String = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.answers[key] = .failed(text)
            }
            self.tasks[key] = nil
        }
    }

    /// One question to one model: the typed prompt, and once more with a
    /// nudge if the first reply was not the JSON asked for.
    nonisolated static func ask(_ q: DetectedQuestion, using backend: LLMBackend) async -> Result<LensAnswer, Error> {
        var turns: [ChatTurn] = [.system(LensPrompt.system), .user(LensPrompt.user(for: q))]
        do {
            let reply: String = try await backend.complete(turns, maxTokens: 1400, temperature: 0.2)
            if let parsed = LensAnswerParser.parse(reply, for: q) { return .success(parsed) }
            turns.append(.assistant(reply))
            turns.append(.user(LensPrompt.retry))
            let second: String = try await backend.complete(turns, maxTokens: 1400, temperature: 0.1)
            if let parsed = LensAnswerParser.parse(second, for: q) { return .success(parsed) }
            return .failure(LLMError.badResponse)
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - Answers kept between launches

/// Answers kept by the question's words in the Caches folder, so a question
/// met again is answered without asking a model. The system may clear it;
/// nothing depends on it being there.
@MainActor
final class LensAnswerCache {
    static let shared = LensAnswerCache()
    static let limit: Int = 300

    private struct Entry: Codable {
        var key: String
        var answer: LensAnswer
    }

    private var entries: [Entry] = []
    private var loaded = false

    private var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("study-lens-answers.json")
    }

    func answer(for key: String) -> LensAnswer? {
        load()
        return entries.last { $0.key == key }?.answer
    }

    func keep(_ answer: LensAnswer, for key: String) {
        load()
        entries.removeAll { $0.key == key }
        entries.append(Entry(key: key, answer: answer))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        guard let url = fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        DispatchQueue.global(qos: .utility).async {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }
}
