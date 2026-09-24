import SwiftUI

// The spoken side of a Cases consultation, in two pieces that live where
// they are used: the station clock up in the header, where it is glanced at,
// and the speaker and microphone down in the composer, under the thumb,
// beside the box a question is typed into.
//
// Both drive the simulator the same way the text box does - what is said is
// sent exactly as a typed question would be - so the case, its checking and
// its marking are untouched.

/// The station clock for a consultation. It starts when the consultation
/// does, and says when time is up.
struct CaseStationClock: View {
    @State private var endsAt = Date().addingTimeInterval(TimeInterval(StationTimerChip.stationSeconds))

    var body: some View {
        StationTimerChip(endsAt: endsAt, totalSeconds: StationTimerChip.stationSeconds)
    }
}

/// The consultation's composer: the typed question at the leading end, then
/// the speaker (read the patient's replies aloud, or not), then one round
/// button that is the microphone while the box is empty and Send once there
/// is something typed in it.
///
/// `field` is the text box, passed in by the screen that owns the draft.
/// While listening, what has been heard so far shows above the row; if the
/// microphone or speech recognition is not allowed, the note saying how to
/// allow it shows there instead.
struct CaseVoiceButtons<Field: View>: View {
    @ObservedObject var simulator: CaseSimulator
    /// True when the typed box has something to send.
    let hasDraft: Bool
    /// Sends what is typed.
    let onSend: () -> Void
    private let field: Field

    @StateObject private var speaker = VoiceSpeaker()
    @StateObject private var listener = VoiceListener()
    @State private var voiceOn = false
    @State private var hearing: VoiceAccess.Hearing?

    init(simulator: CaseSimulator, hasDraft: Bool, onSend: @escaping () -> Void,
         @ViewBuilder field: () -> Field) {
        self.simulator = simulator
        self.hasDraft = hasDraft
        self.onSend = onSend
        self.field = field()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if listener.listening {
                heardLine
            }
            if let message = hearing?.message {
                VoicePermissionNote(message: message)
            }
            HStack(alignment: .bottom, spacing: 8) {
                field
                speakerButton
                if hasDraft && !listener.listening {
                    sendButton
                } else {
                    micButton
                }
            }
        }
        .onChange(of: simulator.messages.count) { _, _ in speakLatest() }
        .onDisappear {
            speaker.stop()
            listener.stop()
            VoiceAccess.deactivate()
        }
    }

    private var heardLine: some View {
        let words: String = listener.text.isEmpty ? "Listening\u{2026}" : listener.text
        return Label(words, systemImage: "waveform")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
    }

    private var speakerButton: some View {
        let symbol: String = voiceOn ? "speaker.wave.2.fill" : "speaker.slash"
        let label: String = voiceOn ? "Stop reading replies aloud" : "Read replies aloud"
        return Button(action: toggleVoice) {
            Image(systemName: symbol)
        }
        .buttonStyle(VoiceCircleStyle(prominent: false, tint: StudySetKind.qa.tint))
        .accessibilityLabel(label)
    }

    private var micButton: some View {
        let listening: Bool = listener.listening
        let symbol: String = listening ? "stop.fill" : "mic.fill"
        let label: String = listening ? "Stop and send" : "Ask out loud"
        let tint: Color = listening ? Color.red : StudySetKind.qa.tint
        return Button(action: talk) {
            Image(systemName: symbol)
        }
        .buttonStyle(VoiceCircleStyle(prominent: true, tint: tint))
        .disabled(simulator.busy && !listening)
        .accessibilityLabel(label)
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up")
        }
        .buttonStyle(VoiceCircleStyle(prominent: true, tint: StudySetKind.qa.tint))
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(simulator.busy)
        .accessibilityLabel("Send")
    }

    private func toggleVoice() {
        voiceOn.toggle()
        if !voiceOn { speaker.stop() }
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

/// A round 48-point button for the composer. The prominent one - the
/// microphone, or Send - is filled with its colour and stands highest out of
/// the glass; the quiet one - the speaker - is lightly tinted and raised.
/// Pressed or disabled, either sinks flat.
private struct VoiceCircleStyle: ButtonStyle {
    let prominent: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        VoiceCircleFace(label: configuration.label, isPressed: configuration.isPressed,
                        prominent: prominent, tint: tint)
    }
}

private struct VoiceCircleFace: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let prominent: Bool
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    private var fill: Color {
        if !isEnabled { return Color.primary.opacity(0.08) }
        if prominent { return tint }
        return tint.opacity(0.14)
    }

    private var ink: Color {
        if !isEnabled { return Color.secondary }
        if prominent { return Color.white }
        return tint
    }

    var body: some View {
        let plane: PopOutPlane = prominent ? .hero : .raised
        let slabTint: Color? = prominent && isEnabled ? tint : nil
        let sunk: Bool = isPressed || !isEnabled
        let scale: CGFloat = isPressed ? 0.94 : 1
        label
            .font(.title3.weight(.semibold))
            .foregroundStyle(ink)
            .frame(width: 48, height: 48)
            .background(fill, in: Circle())
            .contentShape(Circle())
            .scaleEffect(scale)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            .popOut(plane, in: Circle(), tint: slabTint, pressed: sunk)
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(.lift)
    }
}
