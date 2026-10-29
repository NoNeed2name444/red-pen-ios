import Foundation

/// The lecture recorder as a state machine: what it is doing, and which
/// moves from there are allowed (T0146).
///
/// Foundation only, so it runs in the Linux suite and compiles into the
/// widget extension, which reads it from the shared file (RecorderShelf).
/// The same machine, case for case, is android/.../audio/RecorderState.kt.
///
/// Times are seconds since 1970, not Date, so the shared file reads the same
/// on both platforms and a watch or widget never has to know which wrote it.
enum RecorderState: Equatable {
    case idle
    /// The permission sheet or the system prompt is up.
    case asking
    /// Recording since `startedAt`, with `banked` seconds recorded before it.
    case recording(startedAt: Double, banked: Double)
    /// Paused with `banked` seconds recorded; `reason` when something else
    /// paused it (a call), nil when the student did.
    case paused(banked: Double, reason: String?)
    /// Stopped: the file is being finished and handed on.
    case saving
    case failed(reason: String)

    // MARK: moves (nil: not allowed from here)

    /// The first Record tap, before the microphone has been allowed.
    func ask() -> RecorderState? {
        switch self {
        case .idle, .failed: return .asking
        default: return nil
        }
    }

    /// The permission was refused or the sheet closed.
    func cancel() -> RecorderState? {
        self == .asking ? .idle : nil
    }

    func start(at now: Double) -> RecorderState? {
        switch self {
        case .idle, .asking, .failed: return .recording(startedAt: now, banked: 0)
        default: return nil
        }
    }

    func pause(at now: Double) -> RecorderState? {
        guard case .recording = self else { return nil }
        return .paused(banked: elapsed(at: now), reason: nil)
    }

    /// The student's Resume, after their own Pause or after a call.
    func resume(at now: Double) -> RecorderState? {
        guard case .paused(let banked, _) = self else { return nil }
        return .recording(startedAt: now, banked: banked)
    }

    func stop(at now: Double) -> RecorderState? {
        switch self {
        case .recording, .paused: return .saving
        default: return nil
        }
    }

    /// Something else took the microphone (a call): paused, saying why. It
    /// does not resume on its own.
    func interrupt(at now: Double, reason: String) -> RecorderState? {
        guard case .recording = self else { return nil }
        return .paused(banked: elapsed(at: now), reason: reason)
    }

    /// Resuming once the interruption has ended: only from a pause an
    /// interruption made, so a pause the student chose is never undone by a
    /// call ending.
    func resumeAfterInterruption(at now: Double) -> RecorderState? {
        guard case .paused(let banked, let reason) = self, reason != nil else { return nil }
        return .recording(startedAt: now, banked: banked)
    }

    func fail(_ reason: String) -> RecorderState? {
        switch self {
        case .idle, .failed: return nil
        default: return .failed(reason: reason)
        }
    }

    /// The file was handed on, or a failure was read: back to the start.
    func finish() -> RecorderState? {
        switch self {
        case .saving, .failed: return .idle
        default: return nil
        }
    }

    // MARK: reading it

    /// Seconds recorded: running while recording, frozen while paused.
    func elapsed(at now: Double) -> Double {
        switch self {
        case .recording(let startedAt, let banked): return banked + max(0, now - startedAt)
        case .paused(let banked, _): return banked
        default: return 0
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    /// Recording or paused: a recording is open.
    var isActive: Bool { isRecording || isPaused }

    var phase: String {
        switch self {
        case .idle: return "idle"
        case .asking: return "asking"
        case .recording: return "recording"
        case .paused: return "paused"
        case .saving: return "saving"
        case .failed: return "failed"
        }
    }
}

// MARK: - Names

/// The recording's file name and the set's default title (T0146 item 1).
enum RecorderNames {
    /// The clock fields of a moment in the student's own time zone.
    struct Moment: Equatable {
        var year: Int, month: Int, day: Int, hour: Int, minute: Int

        init(year: Int, month: Int, day: Int, hour: Int, minute: Int) {
            self.year = year; self.month = month; self.day = day; self.hour = hour; self.minute = minute
        }

        init(_ date: Date, timeZone: TimeZone = .current) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1, hour: c.hour ?? 0, minute: c.minute ?? 0)
        }
    }

    /// The moment a recording began, read back from its file name (a
    /// recovered one has nothing else); nil for a name that is not ours.
    static func moment(fileName: String) -> Moment? {
        guard fileName.hasPrefix("lecture-") else { return nil }
        let rest = Array(fileName.dropFirst("lecture-".count))
        guard rest.count > 14, rest[8] == "-", rest[13] == "." else { return nil }
        func number(_ from: Int, _ count: Int) -> Int? {
            let part = rest[from..<(from + count)]
            guard part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(String(part))
        }
        guard let y = number(0, 4), let mo = number(4, 2), let d = number(6, 2),
              let h = number(9, 2), let mi = number(11, 2) else { return nil }
        return Moment(year: y, month: mo, day: d, hour: h, minute: mi)
    }

    /// `lecture-20261023-1405.m4a`: Western digits always, so it sorts.
    static func fileName(_ m: Moment, ext: String = "m4a") -> String {
        "lecture-" + pad(m.year, 4) + pad(m.month, 2) + pad(m.day, 2) + "-" + pad(m.hour, 2) + pad(m.minute, 2) + "." + ext
    }

    static let monthsEnglish = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let monthsArabic = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
                               "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]

    /// "Lecture, 23 Oct 14:05" / "محاضرة، ٢٣ أكتوبر ١٤:٠٥". Written out here
    /// rather than by a date formatter so the phone, the Linux suite and
    /// Android all say exactly the same.
    static func defaultTitle(_ m: Moment, language: String) -> String {
        let month = max(1, min(12, m.month)) - 1
        if language.lowercased().hasPrefix("ar") {
            let clock = arabicDigits(pad(m.hour, 2) + ":" + pad(m.minute, 2))
            return "محاضرة، " + arabicDigits(String(m.day)) + " " + monthsArabic[month] + " " + clock
        }
        return "Lecture, \(m.day) \(monthsEnglish[month]) " + pad(m.hour, 2) + ":" + pad(m.minute, 2)
    }

    static func arabicDigits(_ text: String) -> String {
        let digits: [Character] = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
        return String(text.map { c -> Character in
            if let v = c.wholeNumberValue, c.isASCII { return digits[v] }
            return c
        })
    }

    /// The elapsed clock: "12:03", "1:02:03", in Western digits (the screen
    /// formats its own through L10nFormat.clock).
    static func clock(_ seconds: Double) -> String {
        let total = seconds.isFinite && seconds > 0 ? Int(seconds) : 0
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? "\(h):" + pad(m, 2) + ":" + pad(s, 2) : "\(m):" + pad(s, 2)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}

// MARK: - The level meter

enum RecorderMeter {
    /// A meter's power (dBFS, -160...0) as 0...1 for the bar: -50 dB and
    /// below is silence, 0 dB is full.
    static func level(decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return max(0, min(1, (decibels + 50) / 50))
    }

    /// Free space below which a recording is stopped and saved (200 MB).
    static let lowDiskBytes: Int64 = 200 * 1024 * 1024

    static func diskTooLow(freeBytes: Int64) -> Bool { freeBytes < lowDiskBytes }
}

// MARK: - The microphone permission, asked once, on the first Record tap

enum MicPermission: Equatable { case undetermined, granted, denied }

/// The system's microphone permission. The app's is in LectureRecorder; the
/// suite passes a fake.
protocol PermissionGate: AnyObject {
    var status: MicPermission { get }
    /// Shows the system prompt. Called only by RecordFlow.continueFromSheet.
    func request() async -> Bool
}

/// What a Record tap leads to. The permission is never asked at launch or in
/// onboarding: only a Record tap reaches the sheet, and only Continue on the
/// sheet reaches the system prompt.
@MainActor
final class RecordFlow {
    enum Step: Equatable {
        /// "Record your lecture": the plain sheet before the system prompt.
        case sheet
        /// Allowed: start recording.
        case record
        /// Refused: "Microphone is off" with Open Settings.
        case settingsRow
    }

    let gate: PermissionGate
    init(gate: PermissionGate) { self.gate = gate }

    func tapRecord() -> Step {
        switch gate.status {
        case .undetermined: return .sheet
        case .granted: return .record
        case .denied: return .settingsRow
        }
    }

    /// Continue on the sheet: the one place the system prompt is asked for.
    func continueFromSheet() async -> Step {
        guard gate.status == .undetermined else { return tapRecord() }
        return await gate.request() ? .record : .settingsRow
    }
}

/// A microphone lost mid-recording (iOS's side of Android's
/// LectureRecorder.lost): what was written is a .caf, readable up to its last
/// packet, so it is handed on to be saved; an empty one is dropped.
enum RecorderLoss {
    static func handOn(_ working: URL?) -> URL? {
        guard let working else { return nil }
        let size = (try? FileManager.default.attributesOfItem(atPath: working.path)[.size] as? NSNumber)?.int64Value ?? 0
        if size > 0 { return working }
        try? FileManager.default.removeItem(at: working)
        return nil
    }
}

/// The words on the permission sheet and the refused row.
enum RecorderWords {
    static let sheetTitle = "Record your lecture"
    static let sheetBody = "Stethoscore uses the microphone to record the lecture. The recording stays on this phone until you choose to transcribe it."
    static let sheetContinue = "Continue"
    static let micOff = "Microphone is off for Stethoscore"
    static let openSettings = "Open Settings"
    static let callPaused = "Paused for a call"
    static let lowDisk = "Stopped because this phone is almost full."
    static let screenTitle = "Record a lecture"
    static let recording = "Recording"
    static let paused = "Paused"
    static let start = "Start recording"
    static let pause = "Pause"
    static let resume = "Resume"
    static let stop = "Stop"
    static let saveTo = "Save the recording to"
    static let saving = "Saving the recording…"
    static func newSet(_ title: String) -> String { "New set: " + title }
    static func savedTo(_ set: String) -> String { "Saved to " + set }
    static func failed(_ reason: String) -> String { "Couldn't keep recording. " + reason }
    static let sheetCancel = "Cancel"
    static let saveBody = "It stays on this phone until you choose to transcribe it."
    static let saveAgain = "Save the recording"
    static let transcribe = "Transcribe"
    static let recoverTitle = "Keep the unfinished recording?"
    static let recoverBody = "Stethoscore closed while recording. You can keep what it recorded up to then."
    static let keep = "Keep"
    static let discard = "Delete"
    /// The recorder's own catalog keys for Keep and Delete: the shared "Keep"
    /// and "Delete" name other buttons across the app, and stay as they are.
    static let keepKey = "recorder.keep"
    static let discardKey = "recorder.delete"
    static let micLost = "The microphone stopped working."
}

// MARK: - Saving a stopped recording

/// A stopped recording on its way to a set (T0146 repair; Android
/// RecordingSave). Saving only saves: `save` copies the file in under the set
/// on this phone and sends nothing. Transcribing is its own action, on the
/// saved file. A cancelled choice keeps the file, so it can be saved again.
struct RecordingSave: Equatable {
    /// Stopped and not yet saved.
    private(set) var file: URL?
    /// "Save the recording to" is showing; the dialog's Cancel sets it false.
    var choosing = false
    /// The copy under the set, once saved.
    private(set) var kept: URL?
    private(set) var setID: UUID?
    /// The copy is being made: nothing else may start one.
    private(set) var copying = false

    mutating func offer(_ stopped: URL) {
        self = RecordingSave(file: stopped, choosing: true, kept: nil, setID: nil)
    }

    mutating func cancel() { choosing = false }

    mutating func reopen() { if file != nil && !copying { choosing = true } }

    /// Cancelled: the Save the recording button.
    var waiting: Bool { file != nil && !choosing }
    /// The Save the recording button can be tapped: not while a copy runs.
    var canSave: Bool { waiting && !copying }

    /// `keep` copies the file in under `setID`, or returns nil (then it can
    /// be saved again). Nothing here sends anything. A copy already running
    /// starts no second one.
    @discardableResult
    mutating func save(into setID: UUID, keep: (URL, UUID) -> URL?) -> URL? {
        guard let stopped = file, !copying else { return nil }
        choosing = false
        copying = true
        guard let made = keep(stopped, setID) else { copying = false; return nil }
        self = RecordingSave(file: nil, choosing: false, kept: made, setID: setID)
        return made
    }

    /// Transcribe, the student's own action: `send` gets the saved copy.
    func transcribe(_ send: (URL, UUID) async -> Void) async {
        guard let kept, let setID else { return }
        await send(kept, setID)
    }
}
