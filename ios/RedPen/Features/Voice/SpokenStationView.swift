import SwiftUI

/// Practising an OSCE station with a patient who talks back.
///
/// The recall drill asks "what comes next?"; this asks the student to do the
/// station, out loud, against the clock, with somebody to do it to. The writer
/// model plays the patient from the station's own checklist and then marks the
/// transcript against it.
///
/// Layout: the station and its clock are read at the top; everything the
/// thumb does - start, speak, type, send, try again - is in one floating bar
/// at the bottom. Ending the station early is rare, so End & mark waits in
/// the top corner.
struct SpokenStationView: View {
    let station: OsceChecklist

    @EnvironmentObject private var llm: LocalLLMService
    @State private var session: SpokenStationSession?
    @State private var showModels = false
    @State private var shown: StationAttempt?

    var body: some View {
        Group {
            if let session {
                SpokenStationScreen(session: session)
            } else {
                noModel
            }
        }
        .modeScreen(.osce)
        .navigationTitle("Spoken station")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showModels) { ModelSettingsView() }
        .task(id: llm.writerChoice) {
            guard session == nil, let backend = llm.writerOrApple() else { return }
            session = SpokenStationSession(station: station, backend: backend)
        }
        .onDisappear { session?.end() }
        // the microphone is listening: the camera stays off
        .popOutFacePaused()
        // and speech is playing or being heard: no answer tones over it
        .spaceSoundsHushed()
    }

    /// No model yet: say how to get one, and still show past marks.
    private var noModel: some View {
        List {
            Section {
                Label("Choose a model to play the patient", systemImage: "person.wave.2")
                    .font(.headline)
                Text("The patient and the examiner are played by your writer model. With Pro, use \(Brand.name) Cloud or a model on this device; Apple's own model works for free where Apple Intelligence is on.")
                    .font(.callout).foregroundStyle(Color.wardInkSecondary)
            }
            .wardRowBackground()
            StationPastAttempts(title: station.title, shown: $shown)
        }
        .scrollContentBackground(.hidden)
        .navigationDestination(item: $shown) { attempt in
            StationReportView(attempt: attempt)
        }
        .studyBar {
            Button {
                showModels = true
            } label: {
                Label("AI models", systemImage: "cpu")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.return, modifiers: [])
        }
    }
}

private struct SpokenStationScreen: View {
    @ObservedObject var session: SpokenStationSession
    @State private var draft = ""
    @State private var shown: StationAttempt?

    var body: some View {
        Group {
            switch session.phase {
            case .briefing:
                briefing
            case .running:
                running
            case .marking:
                VStack(spacing: WardSpace.m) {
                    EcgLoader()
                    Text("The examiner is marking\u{2026}")
                        .font(.subheadline)
                        .foregroundStyle(Color.wardInkSecondary)
                }
                .frame(maxHeight: .infinity)
            case .marked:
                if let attempt = session.attempt {
                    StationReportView(attempt: attempt)
                        .studyBar { tryAgainButton }
                }
            case .failed(let message):
                failed(message)
            }
        }
        .navigationDestination(item: $shown) { attempt in
            StationReportView(attempt: attempt)
        }
    }

    // MARK: before the station

    private var briefing: some View {
        List {
            Section {
                Text(session.station.title).font(.title3.weight(.semibold))
                Text(session.instructions).font(.callout)
                if session.isCommunication {
                    Label("Also marked on SPIKES: setting, perception, invitation, knowledge, emotions, strategy and summary.",
                          systemImage: "bubble.left.and.bubble.right")
                        .font(.footnote).foregroundStyle(Color.wardInkSecondary)
                }
            } footer: {
                Text("Tap the microphone to speak; it sends when you pause. The patient answers in their own voice. You can type instead.")
            }
            .wardRowBackground()
            StationPastAttempts(title: session.station.title, shown: $shown)
        }
        .scrollContentBackground(.hidden)
        .studyBar {
            Button {
                Task { await session.begin() }
            } label: {
                Label("Start the station", systemImage: "play.fill")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    // MARK: during the station

    private var running: some View {
        VStack(spacing: 0) {
            StudyProgressHeader(session.station.title) {
                StationTimerChip(endsAt: session.endsAt, totalSeconds: session.minutes * 60)
            }

            if let message = session.hearing?.message {
                VoicePermissionNote(message: message)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            SpokenTranscript(session: session)
        }
        .studyBar {
            SpokenStationComposer(session: session, listener: session.listener, draft: $draft)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("End & mark") { Task { await session.finish() } }
                .buttonStyle(.wardCompact)
                    .accessibilityHint("Ends the station now and has it marked")
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    // MARK: after the station

    private var tryAgainButton: some View {
        Button {
            session.restart()
        } label: {
            Label("Try the station again", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.bigPrimary)
        .keyboardShortcut(.return, modifiers: [])
    }

    private func failed(_ message: String) -> some View {
        WardEmptyState(symbol: "exclamationmark.triangle", title: "Couldn't mark the station",
                       message: message, tone: .danger)
            .frame(maxHeight: .infinity)
            .studyBar {
                StationFailedBar(session: session)
            }
    }
}

/// Marking failed: mark the same transcript again (the hero, right thumb),
/// or start the station over (left thumb). With nothing said, only the
/// second makes sense.
private struct StationFailedBar: View {
    @ObservedObject var session: SpokenStationSession

    var body: some View {
        if session.hasStudentLines {
            HStack(spacing: 12) {
                Button("Start again") { session.restart() }
                    .buttonStyle(.bigCompanion)
                Button("Mark again") { Task { await session.finish() } }
                    .buttonStyle(.bigPrimary)
                    .keyboardShortcut(.return, modifiers: [])
            }
        } else {
            Button {
                session.restart()
            } label: {
                Label("Try the station again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.return, modifiers: [])
        }
    }
}

/// What has been said, scrolling under the composer.
private struct SpokenTranscript: View {
    @ObservedObject var session: SpokenStationSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(session.lines) { line in
                        SpokenLineBubble(line: line).id(line.id)
                    }
                    if session.busy {
                        HStack(spacing: 8) {
                            EcgLoader()
                            Text("The patient is answering\u{2026}").font(.footnote).foregroundStyle(Color.wardInkSecondary)
                        }
                    }
                }
                .padding()
                .readableColumn()
            }
            .onChange(of: session.lines.count) { _, _ in
                if let last = session.lines.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }
}

/// The station's earlier marked attempts, and the examples in a personal build.
private struct StationPastAttempts: View {
    let title: String
    @Binding var shown: StationAttempt?
    @ObservedObject private var history = VoiceHistory.shared

    private var attempts: [StationAttempt] {
        history.stationList.filter { $0.isExample || $0.title == title }
    }

    var body: some View {
        Section("Past attempts") {
            if attempts.isEmpty {
                Text("Your marked stations appear here.")
                    .font(.footnote).foregroundStyle(Color.wardInkSecondary)
            }
            ForEach(attempts) { attempt in
                StationAttemptRow(attempt: attempt,
                                  open: { shown = attempt },
                                  delete: deleteAction(for: attempt))
            }
        }
        .wardRowBackground()
    }

    /// Shipped examples can't be deleted.
    private func deleteAction(for attempt: StationAttempt) -> (() -> Void)? {
        if attempt.isExample { return nil }
        let id: UUID = attempt.id
        let kept = history
        return { kept.delete(station: id) }
    }
}

/// One past attempt. Swipe, or hold (right-click with a pointer), to delete.
private struct StationAttemptRow: View {
    let attempt: StationAttempt
    let open: () -> Void
    let delete: (() -> Void)?

    var body: some View {
        let score: String = "\(attempt.mark.done.count)/\(attempt.steps.count)"
        Button(action: open) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(attempt.title).foregroundStyle(Color.wardInk).lineLimit(2)
                        if attempt.isExample { VoiceExampleTag() }
                    }
                    Text(attempt.date, format: .dateTime.day().month().hour().minute())
                        .font(.caption).foregroundStyle(Color.wardInkSecondary)
                }
                Spacer()
                Text(score)
                    .font(.system(.headline, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.wardInk)
            }
        }
        .swipeActions {
            if let delete {
                Button("Delete", role: .destructive, action: delete)
            }
        }
        .contextMenu {
            Button("Open", systemImage: "doc.text.magnifyingglass", action: open)
            if let delete {
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            }
        }
    }
}

/// The composer, as the floating bar's content: what the microphone is
/// hearing on top, then the typed box, the speaker, and one round button that
/// is the microphone while the box is empty and Send once something is typed.
private struct SpokenStationComposer: View {
    @ObservedObject var session: SpokenStationSession
    @ObservedObject var listener: VoiceListener
    @Binding var draft: String

    private var hasDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if listener.listening {
                heardLine
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
    }

    private var heardLine: some View {
        let words: String = listener.text.isEmpty ? "Listening\u{2026}" : listener.text
        return Label(words, systemImage: "waveform")
            .font(.caption)
            .foregroundStyle(Color.wardInkSecondary)
            .lineLimit(1)
            .truncationMode(.head)
    }

    /// The typed box: a well pressed into the bar.
    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return TextField("Or type what you say", text: $draft, axis: .vertical)
            .lineLimit(1...4)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .wardInset(in: shape)
    }

    private var speakerButton: some View {
        let on: Bool = session.voiceOn
        let symbol: String = on ? "speaker.wave.2.fill" : "speaker.slash"
        let label: String = on ? "Stop reading the patient aloud" : "Read the patient aloud"
        return Button(action: toggleVoice) {
            Image(systemName: symbol)
        }
        .buttonStyle(StationCircleStyle(prominent: false, tint: Color.wardPrimaryInk, on: on))
        .accessibilityLabel(label)
    }

    private var micButton: some View {
        let listening: Bool = listener.listening
        let symbol: String = listening ? "stop.fill" : "mic.fill"
        let label: String = listening ? "Stop and send" : "Speak"
        let tint: Color = listening ? Color.wardDanger : Color.wardPrimaryInk
        let blocked: Bool = session.busy || session.hearing?.canHear != true
        return Button(action: talk) {
            Image(systemName: symbol)
        }
        .buttonStyle(StationCircleStyle(prominent: true, tint: tint, on: listening))
        .disabled(blocked)
        .accessibilityLabel(label)
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
        }
        .buttonStyle(StationCircleStyle(prominent: true, tint: Color.wardPrimaryInk))
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(session.busy)
        .accessibilityLabel("Send")
    }

    private func toggleVoice() {
        session.voiceOn.toggle()
        if !session.voiceOn { session.speaker.stop() }
    }

    private func talk() {
        Task { await session.talk() }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await session.send(text) }
    }
}

/// A round 48-point composer button: a soft circle raised off the bar with
/// its glyph in its colour, never a fill. The prominent one - the
/// microphone, or Send - is the screen's hero and stands a step higher; the
/// quiet one - the speaker - is raised low. Held, or on (the speaker reading
/// aloud, the microphone listening), it is pressed in; disabled, it lies low
/// with its glyph in Chart Ink.
private struct StationCircleStyle: ButtonStyle {
    let prominent: Bool
    let tint: Color
    var on = false

    func makeBody(configuration: Configuration) -> some View {
        StationCircleFace(label: configuration.label, isPressed: configuration.isPressed,
                          prominent: prominent, tint: tint, on: on)
    }
}

private struct StationCircleFace: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let prominent: Bool
    let tint: Color
    let on: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let down: Bool = isEnabled && (isPressed || on)
        let rest: WardLift = prominent ? .mid : .low
        let ink: Color = isEnabled ? tint : Color.wardInk
        label
            .font(.title3.weight(.semibold))
            .foregroundStyle(ink)
            .frame(width: 48, height: 48)
            .background {
                WardPressFace(shape: Circle(), lift: isEnabled ? rest : .low, pressed: down)
            }
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .wardShade(down: down), value: down)
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(.highlight)
            .capPop(isPressed)
    }
}

/// One line said: the two speaking raised off the base (the student on the
/// right, in Theatre Blue words; the patient on the left, in ink), the
/// examiner's asides pressed into it.
private struct SpokenLineBubble: View {
    let line: SpokenLine

    var body: some View {
        let bubble = RoundedRectangle(cornerRadius: 14, style: .continuous)
        switch line.speaker {
        case .examiner:
            Text(line.text)
                .font(.callout.italic())
                .foregroundStyle(Color.wardInkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .wardInset(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .student:
            HStack {
                Spacer(minLength: 40)
                Text(line.text)
                    .padding(10)
                    .foregroundStyle(Color.wardPrimaryInk)
                    .wardRaised(in: bubble, lift: .low)
            }
        case .patient:
            Text(line.text)
                .foregroundStyle(Color.wardInk)
                .padding(10)
                .wardRaised(in: bubble, lift: .low)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 40)
        }
    }
}

/// The examiner's marks for one spoken station.
struct StationReportView: View {
    let attempt: StationAttempt

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(attempt.mark.done.count)")
                        .scaledFont(54, relativeTo: .largeTitle, weight: .bold, design: .monospaced)
                        .monospacedDigit()
                        .foregroundStyle(Color.wardInk)
                    Text("of \(attempt.steps.count) steps").font(.title3).foregroundStyle(Color.wardInkSecondary)
                    Spacer()
                    if attempt.isExample { VoiceExampleTag() }
                }
                HStack {
                    Text("Communication")
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= attempt.mark.communication ? "star.fill" : "star")
                                .foregroundStyle(i <= attempt.mark.communication ? Color.wardBeam : Color.wardInkSecondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Communication \(attempt.mark.communication) out of 5")
                }
                if !attempt.mark.feedback.isEmpty {
                    Text(attempt.mark.feedback).font(.callout)
                }
            } header: {
                Text(attempt.title)
            }
            .wardRowBackground()

            if let spikes = attempt.mark.spikes, attempt.isCommunication {
                Section("SPIKES") {
                    ForEach(SpokenAnswer.spikes.indices, id: \.self) { index in
                        let stage = SpokenAnswer.spikes[index]
                        let done = spikes[stage.key] ?? false
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stage.name)
                                Text(stage.meaning).font(.caption).foregroundStyle(Color.wardInkSecondary)
                            }
                        } icon: {
                            Image(systemName: done ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(done ? Color.wardSuccess : Color.wardDanger)
                                .accessibilityLabel(done ? "Done" : "Missed")
                        }
                    }
                }
                .wardRowBackground()
            }

            Section("Checklist") {
                ForEach(Array(attempt.steps.enumerated()), id: \.offset) { index, step in
                    let done = attempt.mark.done.contains(index)
                    Label {
                        Text(step)
                    } icon: {
                        Image(systemName: done ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(done ? Color.wardSuccess : Color.wardDanger)
                            .accessibilityLabel(done ? "Done" : "Missed")
                    }
                    .font(.callout)
                }
            }
            .wardRowBackground()

            if !attempt.mark.missedNotes.isEmpty {
                Section("The examiner's notes") {
                    ForEach(Array(attempt.mark.missedNotes.enumerated()), id: \.offset) { _, note in
                        Text(note).font(.callout)
                    }
                }
                .wardRowBackground()
            }

            Section("Transcript") {
                ForEach(attempt.lines) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.speaker.rawValue.capitalized)
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.wardInkSecondary)
                        Text(line.text).font(.callout)
                    }
                }
            }
            .wardRowBackground()

            Section {
                Text("A study aid, not an exam result. Marked by a model from a speech-recognition transcript, which can mishear.")
                    .font(.caption).foregroundStyle(Color.wardInkSecondary)
            }
            .wardRowBackground()
        }
        .scrollContentBackground(.hidden)
        .modeScreen(.osce)
        .navigationTitle("Station marks")
        .navigationBarTitleDisplayMode(.inline)
    }
}
