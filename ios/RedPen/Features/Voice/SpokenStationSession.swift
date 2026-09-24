import Foundation
import Combine

/// One OSCE station played out loud: the writer model plays the patient from
/// the station's own mark sheet, the student talks, the clock runs, and at the
/// end the same model - now the examiner - marks what the student said
/// against the checklist (and against SPIKES, for a communication station).
@MainActor
final class SpokenStationSession: ObservableObject {

    enum Phase: Equatable {
        case briefing
        case running
        case marking
        case marked
        case failed(String)
    }

    @Published private(set) var phase: Phase = .briefing
    @Published private(set) var lines: [SpokenLine] = []
    /// The patient is thinking of a reply.
    @Published private(set) var busy = false
    @Published private(set) var hearing: VoiceAccess.Hearing?
    @Published private(set) var endsAt: Date?
    @Published private(set) var attempt: StationAttempt?
    /// Read the patient's replies aloud.
    @Published var voiceOn = true

    let station: OsceChecklist
    let isCommunication: Bool
    let speaker = VoiceSpeaker()
    let listener = VoiceListener()

    private let backend: LLMBackend
    private var clock: Task<Void, Never>?

    init(station: OsceChecklist, backend: LLMBackend) {
        self.station = station
        self.backend = backend
        self.isCommunication = SpokenAnswer.isCommunicationStation(station.title)
    }

    var minutes: Int { ExamTrack.current.stationMinutes }

    /// What the examiner reads out at the start, as candidate instructions do.
    var instructions: String {
        let task = isCommunication
            ? "This is a communication station. Speak to the patient as you would in the exam; you'll be marked on the checklist and on how well you follow SPIKES."
            : "Take it as you would in the exam: talk to the patient, and say out loud anything you would do or examine."
        return "Station: \(station.title). You have \(minutes) minutes. \(task) The examiner marks you when you end the station or the time runs out."
    }

    var hasStudentLines: Bool { lines.contains { $0.speaker == .student } }

    // MARK: running

    func begin() async {
        guard phase == .briefing else { return }
        phase = .running
        hearing = await VoiceAccess.request()
        VoiceAccess.activate()
        endsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        startClock()
        add(.examiner, instructions)
        if voiceOn { await speaker.say(instructions, as: .narrator) }
    }

    /// Listens for one thing the student says, then sends it. Tapping the
    /// microphone again while listening sends straight away.
    func talk() async {
        guard phase == .running, !busy else { return }
        if listener.listening {
            listener.stop()
            return
        }
        guard hearing?.canHear == true else { return }
        speaker.stop()
        guard let said = await listener.listenOnce(patience: 15, silence: 2.0), !said.isEmpty else { return }
        await send(said)
    }

    /// Sends what the student said (or typed) and waits for the patient.
    func send(_ text: String) async {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .running, !busy, !said.isEmpty else { return }
        add(.student, said)
        busy = true
        defer { busy = false }
        do {
            let reply = try await VoiceMarking.patientReply(title: station.title, steps: station.steps,
                                                             lines: lines, using: backend)
            guard phase == .running else { return }
            add(.patient, reply)
            if voiceOn { await speaker.say(reply, as: .patient) }
        } catch {
            add(.examiner, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Ends the station and has it marked.
    func finish() async {
        guard phase == .running || phaseIsFailed else { return }
        stopEverything()
        guard hasStudentLines else {
            phase = .failed("Nothing you said was heard, so there is nothing to mark. Start the station again and talk to the patient - or type if the microphone is off.")
            return
        }
        phase = .marking
        do {
            let mark = try await VoiceMarking.markStation(title: station.title, steps: station.steps,
                                                          lines: lines, using: backend)
            let made = StationAttempt(title: station.title, steps: station.steps, lines: lines,
                                      mark: mark, isCommunication: isCommunication)
            VoiceHistory.shared.add(made)
            StudyLog.shared.record()
            attempt = made
            phase = .marked
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// From the start again, same station.
    func restart() {
        stopEverything()
        lines = []
        attempt = nil
        endsAt = nil
        phase = .briefing
    }

    func end() {
        stopEverything()
        VoiceAccess.deactivate()
    }

    private var phaseIsFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func stopEverything() {
        clock?.cancel()
        clock = nil
        speaker.stop()
        listener.stop()
    }

    private func add(_ speaker: SpokenLine.Speaker, _ text: String) {
        lines.append(SpokenLine(speaker: speaker, text: text))
    }

    // MARK: the clock

    /// A minute's warning and the end, both said aloud by the examiner, as in
    /// the exam. At the end the station is marked whatever is happening.
    private func startClock() {
        clock?.cancel()
        guard let ends = endsAt else { return }
        clock = Task { [weak self] in
            let untilWarning = ends.timeIntervalSinceNow - 60
            if untilWarning > 0 {
                try? await Task.sleep(for: .seconds(untilWarning))
                guard !Task.isCancelled, let self, self.phase == .running else { return }
                self.add(.examiner, "One minute remaining.")
                if !self.speaker.speaking, !self.listener.listening, self.voiceOn {
                    await self.speaker.say("One minute remaining.", as: .narrator)
                }
            }
            let rest = ends.timeIntervalSinceNow
            if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
            guard !Task.isCancelled, let self, self.phase == .running else { return }
            self.listener.stop()
            self.add(.examiner, "Time's up. Please stop there.")
            if self.voiceOn { await self.speaker.say("Time's up. Please stop there.", as: .narrator) }
            // this task is the clock: forgotten, not cancelled, or the marking
            // it starts would be cancelled with it
            self.clock = nil
            await self.finish()
        }
    }
}
