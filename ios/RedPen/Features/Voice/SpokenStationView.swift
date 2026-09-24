import SwiftUI

/// Practising an OSCE station with a patient who talks back.
///
/// The recall drill asks "what comes next?"; this asks the student to do the
/// station, out loud, against the clock, with somebody to do it to. The writer
/// model plays the patient from the station's own checklist and then marks the
/// transcript against it.
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
                // no model yet: say how to get one, and still show past marks
                List {
                    Section {
                        Label("Choose a model to play the patient", systemImage: "person.wave.2")
                            .font(.headline)
                        Text("The patient and the examiner are played by your writer model. With Pro, use \(Brand.name) Cloud or a model on this device; Apple's own model works for free where Apple Intelligence is on.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("AI models") { showModels = true }
                    }
                    StationPastAttempts(title: station.title, shown: $shown)
                }
                .scrollContentBackground(.hidden)
                .navigationDestination(item: $shown) { attempt in
                    StationReportView(attempt: attempt)
                }
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
                ProgressView("The examiner is marking\u{2026}").frame(maxHeight: .infinity)
            case .marked:
                if let attempt = session.attempt {
                    StationReportView(attempt: attempt)
                        .safeAreaInset(edge: .bottom) {
                            Button("Try the station again") { session.restart() }
                                .buttonStyle(.glassProminent)
                                .padding(.bottom, 8)
                        }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't mark the station", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    if session.hasStudentLines {
                        Button("Mark again") { Task { await session.finish() } }
                            .buttonStyle(.glassProminent)
                    }
                    Button("Start again") { session.restart() }
                        .buttonStyle(.glass)
                }
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
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("The patient speaks in a different voice from the examiner. Tap the microphone to speak; it sends when you pause. If the microphone is off you can type instead.")
            }
            Section {
                Button {
                    Task { await session.begin() }
                } label: {
                    Label("Start the station", systemImage: "play.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .listRowBackground(Color.clear)
            }
            StationPastAttempts(title: session.station.title, shown: $shown)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: during the station

    private var running: some View {
        VStack(spacing: 0) {
            HStack {
                StationTimerChip(endsAt: session.endsAt, totalSeconds: session.minutes * 60)
                Spacer()
                Button {
                    session.voiceOn.toggle()
                    if !session.voiceOn { session.speaker.stop() }
                } label: {
                    Image(systemName: session.voiceOn ? "speaker.wave.2.fill" : "speaker.slash")
                }
                .buttonStyle(.glass)
                .accessibilityLabel(session.voiceOn ? "Stop reading the patient aloud" : "Read the patient aloud")
                Button("End & mark") { Task { await session.finish() } }
                    .buttonStyle(.glass)
            }
            .padding(.horizontal).padding(.vertical, 8)

            if let message = session.hearing?.message {
                VoicePermissionNote(message: message).padding(.horizontal)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(session.lines) { line in
                            SpokenLineBubble(line: line).id(line.id)
                        }
                        if session.busy {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("The patient is answering\u{2026}").font(.footnote).foregroundStyle(.secondary)
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

            SpokenStationComposer(session: session, listener: session.listener, draft: $draft)
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
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(attempts) { attempt in
                Button { shown = attempt } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(attempt.title).foregroundStyle(.primary).lineLimit(2)
                                if attempt.isExample { VoiceExampleTag() }
                            }
                            Text(attempt.date, format: .dateTime.day().month().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(attempt.mark.done.count)/\(attempt.steps.count)")
                            .font(.headline.monospacedDigit())
                    }
                }
                .swipeActions {
                    if !attempt.isExample {
                        Button("Delete", role: .destructive) { history.delete(station: attempt.id) }
                    }
                }
            }
        }
    }
}

/// The microphone, and a text box for when it can't be used.
private struct SpokenStationComposer: View {
    @ObservedObject var session: SpokenStationSession
    @ObservedObject var listener: VoiceListener
    @Binding var draft: String

    var body: some View {
        VStack(spacing: 6) {
            if listener.listening {
                Text(listener.text.isEmpty ? "Listening\u{2026}" : listener.text)
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                TextField("Or type what you say", text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(10)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        let text = draft
                        draft = ""
                        Task { await session.send(text) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(session.busy)
                    .accessibilityLabel("Send")
                } else {
                    Button { Task { await session.talk() } } label: {
                        Image(systemName: listener.listening ? "stop.fill" : "mic.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(listener.listening ? Color.red : nil)
                    .disabled(session.busy || session.hearing?.canHear != true)
                    .accessibilityLabel(listener.listening ? "Stop and send" : "Speak")
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }
}

private struct SpokenLineBubble: View {
    let line: SpokenLine

    var body: some View {
        switch line.speaker {
        case .examiner:
            Text(line.text)
                .font(.callout.italic())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .student:
            HStack {
                Spacer(minLength: 40)
                Text(line.text)
                    .padding(10)
                    .foregroundStyle(.white)
                    .background(StudySetKind.osce.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        case .patient:
            Text(line.text)
                .padding(10)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                        .font(.system(size: 54, weight: .bold, design: .rounded).monospacedDigit())
                    Text("of \(attempt.steps.count) steps").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    if attempt.isExample { VoiceExampleTag() }
                }
                HStack {
                    Text("Communication")
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= attempt.mark.communication ? "star.fill" : "star")
                                .foregroundStyle(i <= attempt.mark.communication ? Color.yellow : Color.secondary)
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

            if let spikes = attempt.mark.spikes, attempt.isCommunication {
                Section("SPIKES") {
                    ForEach(SpokenAnswer.spikes.indices, id: \.self) { index in
                        let stage = SpokenAnswer.spikes[index]
                        let done = spikes[stage.key] ?? false
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stage.name)
                                Text(stage.meaning).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: done ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(done ? Color.green : Color.red)
                        }
                    }
                }
            }

            Section("Checklist") {
                ForEach(Array(attempt.steps.enumerated()), id: \.offset) { index, step in
                    let done = attempt.mark.done.contains(index)
                    Label {
                        Text(step)
                    } icon: {
                        Image(systemName: done ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(done ? Color.green : Color.red)
                    }
                    .font(.callout)
                }
            }

            if !attempt.mark.missedNotes.isEmpty {
                Section("The examiner's notes") {
                    ForEach(Array(attempt.mark.missedNotes.enumerated()), id: \.offset) { _, note in
                        Text(note).font(.callout)
                    }
                }
            }

            Section("Transcript") {
                ForEach(attempt.lines) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.speaker.rawValue.capitalized)
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(line.text).font(.callout)
                    }
                }
            }

            Section {
                Text("A study aid, not an exam result. Marked by a model from a speech-recognition transcript, which can mishear.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .modeScreen(.osce)
        .navigationTitle("Station marks")
        .navigationBarTitleDisplayMode(.inline)
    }
}
