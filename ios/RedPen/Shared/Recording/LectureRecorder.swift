#if canImport(AVFoundation) && os(iOS)
import AVFoundation
import Foundation

/// Records a lecture in the app (T0146 item 2).
///
/// AVAudioRecorder writes AAC into a .caf while it runs: a .caf is readable
/// up to its last packet even if the app is killed mid-lecture, where an
/// .m4a is unreadable until its index is written at the end. On Stop it is
/// exported to .m4a (`lecture-<yyyyMMdd-HHmm>.m4a`) and handed on. With the
/// audio background mode the recording carries on with the app in the
/// background and the screen off; it can only be started from the app.
///
/// A call pauses it and it stays paused ("Paused for a call"); a
/// headset taken out keeps it going on the built-in microphone; under 200 MB
/// free it stops and keeps what it recorded. The state goes to the shared file
/// (RecorderShelf) on every move, for widgets and the watch.
@MainActor
final class LectureRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = LectureRecorder()

    @Published private(set) var state: RecorderState = .idle
    /// 0...1, for the meter, ten times a second while recording.
    @Published private(set) var level: Double = 0
    /// Set when the recorder stopped by itself (low disk).
    @Published var note: String?
    /// The finished .m4a, once Stop has exported it. It stays here until it
    /// is saved to a set, so a cancelled choice or a closed screen loses
    /// nothing (the screen offers it again when it appears).
    @Published var finished: URL?
    /// A recording the app was killed during, found when this recorder was
    /// made at launch (RecorderRecovery): keep or discard it.
    @Published var recovered: URL?

    private var recorder: AVAudioRecorder?
    private var working: URL?
    /// When this recording began, for its file name and its set's title.
    private(set) var startedDate = Date()
    private var ticker: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// Made once per process, at its first use: nothing is recording yet, so
    /// a shared file still saying recording is a recording cut off by a kill.
    override init() {
        super.init()
        recovered = RecorderRecovery.recover(shelf: RecorderShelf.fileURL, folder: Self.folder)
    }

    /// The in-progress and finished recordings: Documents/recordings, out of
    /// the backup like the lectures folder.
    static var folder: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        LectureAudio.keepOutOfBackup(dir)
        return dir
    }

    private func move(_ next: RecorderState?) {
        guard let next else { return }
        state = next
        RecorderShelf.write(next)
    }

    private var now: Double { Date().timeIntervalSince1970 }

    // MARK: the controls

    func start() {
        guard !state.isActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
            startedDate = Date()
            let name = RecorderNames.fileName(RecorderNames.Moment(startedDate), ext: "caf")
            let url = Self.folder.appendingPathComponent(name)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ]
            let made = try AVAudioRecorder(url: url, settings: settings)
            made.delegate = self
            made.isMeteringEnabled = true
            guard made.record() else { throw CocoaError(.fileWriteUnknown) }
            recorder = made
            working = url
            note = nil
            finished = nil
            watch()
            move(state.start(at: now))
        } catch {
            move(state.fail(error.localizedDescription) ?? .failed(reason: error.localizedDescription))
        }
    }

    func pause() {
        guard state.isRecording else { return }
        recorder?.pause()
        move(state.pause(at: now))
    }

    func resume() {
        guard state.isPaused else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        guard recorder?.record() == true else {
            move(state.fail("The microphone could not be opened again."))
            return
        }
        move(state.resume(at: now))
    }

    /// Stops, exports the .m4a and publishes it in `finished`.
    func stop() async {
        guard state.isActive, let recorder, let working else { return }
        move(state.stop(at: now))
        recorder.stop()
        self.recorder = nil
        unwatch()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let out = Self.folder.appendingPathComponent(RecorderNames.fileName(RecorderNames.Moment(startedDate)))
        do {
            try await Self.export(working, to: out)
            try? FileManager.default.removeItem(at: working)
            self.working = nil
            finished = out
        } catch {
            // the .caf is still a whole recording: hand that on instead
            finished = working
        }
    }

    /// The finished file was handed to the lecture flow.
    func handedOn() {
        finished = nil
        move(state.finish())
    }

    /// A failure was read.
    func clearFailure() {
        if case .failed = state { move(state.finish()) }
    }

    static func export(_ caf: URL, to m4a: URL) async throws {
        try? FileManager.default.removeItem(at: m4a)
        let asset = AVURLAsset(url: caf)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try await session.export(to: m4a, as: .m4a)
    }

    // MARK: watching the session, the level and the disk

    private func watch() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in self?.interrupted(began: raw == AVAudioSession.InterruptionType.began.rawValue) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.routeChanged() }
        })
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            var beats = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                self.tick(checkDisk: beats % 50 == 0)
                beats += 1
            }
        }
    }

    private func unwatch() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        ticker?.cancel()
        ticker = nil
        level = 0
    }

    private func tick(checkDisk: Bool) {
        guard let recorder, state.isRecording else { level = 0; return }
        recorder.updateMeters()
        level = RecorderMeter.level(decibels: Double(recorder.averagePower(forChannel: 0)))
        if checkDisk, let free = Self.freeBytes(), RecorderMeter.diskTooLow(freeBytes: free) {
            note = RecorderWords.lowDisk
            Task { await stop() }
        }
    }

    static func freeBytes() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// A call: paused, and it stays paused when the call ends.
    private func interrupted(began: Bool) {
        guard began, state.isRecording else { return }
        recorder?.pause()
        move(state.interrupt(at: now, reason: RecorderWords.callPaused))
    }

    /// A headset taken out: the session falls back to the built-in
    /// microphone; if the recorder stopped with the route, it goes on.
    private func routeChanged() {
        guard state.isRecording, let recorder, !recorder.isRecording else { return }
        if !recorder.record() { lost(RecorderWords.micLost) }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.lost(error?.localizedDescription ?? "The recording could not be written.") }
    }

    /// The microphone failed: the recorder is let go and the recording ends
    /// as failed. The .caf written up to then is readable, so it is handed on
    /// to be saved (Save the recording), as Android does; an empty one is dropped.
    private func lost(_ reason: String) {
        guard state.isActive else { return }
        recorder?.stop()
        recorder = nil
        unwatch()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let kept = RecorderLoss.handOn(working)
        working = nil
        move(state.fail(reason))
        if let kept { finished = kept }
    }
}

/// The system's microphone permission (AVAudioApplication), for RecordFlow.
/// Its request is reached only through RecordFlow.continueFromSheet.
final class SystemMicGate: PermissionGate {
    var status: MicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    func request() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
#endif
