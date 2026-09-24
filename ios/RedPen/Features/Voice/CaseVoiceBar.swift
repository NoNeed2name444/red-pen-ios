import SwiftUI

/// The spoken side of a Cases consultation: a station clock, a microphone
/// that asks the patient a question out loud, and the patient answering out
/// loud in a voice of their own.
///
/// It sits under the consultation's header and drives the simulator the same
/// way the text box does - what is said is sent exactly as a typed question
/// would be - so the case, its checking and its marking are untouched.
struct CaseVoiceBar: View {
    @ObservedObject var simulator: CaseSimulator

    @StateObject private var speaker = VoiceSpeaker()
    @StateObject private var listener = VoiceListener()
    @State private var voiceOn = false
    @State private var hearing: VoiceAccess.Hearing?
    /// The station clock starts when the consultation does.
    @State private var endsAt = Date().addingTimeInterval(TimeInterval(StationTimerChip.stationSeconds))

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                StationTimerChip(endsAt: endsAt, totalSeconds: StationTimerChip.stationSeconds)
                Spacer()
                if listener.listening {
                    Text(listener.text.isEmpty ? "Listening\u{2026}" : listener.text)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                }
                Button {
                    voiceOn.toggle()
                    if !voiceOn { speaker.stop() }
                } label: {
                    Image(systemName: voiceOn ? "speaker.wave.2.fill" : "speaker.slash")
                }
                .buttonStyle(.glass)
                .accessibilityLabel(voiceOn ? "Stop reading replies aloud" : "Read replies aloud")
                Button(action: talk) {
                    Image(systemName: listener.listening ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(listener.listening ? Color.red : nil)
                .disabled(simulator.busy && !listener.listening)
                .accessibilityLabel(listener.listening ? "Stop and send" : "Ask out loud")
            }
            if let message = hearing?.message {
                VoicePermissionNote(message: message)
            }
        }
        .padding(.horizontal).padding(.bottom, 6)
        .onChange(of: simulator.messages.count) { _, _ in speakLatest() }
        .onDisappear {
            speaker.stop()
            listener.stop()
            VoiceAccess.deactivate()
        }
    }

    /// Listens for one question, then sends it as the typed one would be.
    /// Tapping again while listening sends at once.
    private func talk() {
        if listener.listening {
            listener.stop()
            return
        }
        Task {
            let allowed = await VoiceAccess.request()
            hearing = allowed
            guard allowed.canHear else { return }
            speaker.stop()
            voiceOn = true
            guard let question = await listener.listenOnce(patience: 12, silence: 1.8),
                  !question.isEmpty else { return }
            await simulator.send(question)
        }
    }

    /// The patient in the patient's voice; examination findings in the
    /// examiner's.
    private func speakLatest() {
        guard voiceOn, let last = simulator.messages.last, last.speaker != .doctor else { return }
        let role: VoiceSpeaker.Role = last.speaker == .patient ? .patient : .narrator
        VoiceAccess.activate()
        Task { await speaker.say(last.text, as: role) }
    }
}
