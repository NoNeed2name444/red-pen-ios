import SwiftUI

/// Hands-free study: the phone reads out today's due cards and questions from
/// the sets chosen, listens for the answer, says whether it was right, and
/// moves on - on a bus, walking, or with the phone locked in a pocket.
///
/// Cards are rated through the same ReviewStore as Due today (right is Good,
/// wrong is Again), so the drive counts as a review.
struct CommuteModeView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore
    @StateObject private var session = CommuteSession()

    @State private var includeDue = true
    @State private var chosenSets: Set<UUID> = []
    @State private var perSet = 10
    /// Read by VoiceSpeaker everywhere the app speaks, not only here.
    @AppStorage(CloudVoiceSetting.key) private var naturalVoice = true

    var body: some View {
        Group {
            if session.items.isEmpty {
                setup
            } else {
                player
            }
        }
        .modeScreen(.anki)
        .navigationTitle("Commute mode")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { session.end() }
    }

    // MARK: choosing what is played

    /// Cards that can be read aloud: an image occlusion card is a picture.
    private var dueCards: [ReviewPlan.Due] {
        reviews.dueAcross(store.library).filter {
            $0.card.type != .occlusion && !QuizFromCards.stem(of: $0.card).isEmpty
        }
    }

    private var questionSets: [StudySet] {
        store.library.filter { $0.kind == .mcq && !$0.questions.isEmpty }
    }

    /// A personal build has example decks: when nothing is due, a few of their
    /// cards stand in, so the mode can be tried at once.
    private var exampleCards: [ReviewPlan.Due] {
        guard PersonalBuild.isOn else { return [] }
        let decks = store.library.filter { $0.kind == .anki && $0.name.hasPrefix("Example") }
        return decks.flatMap { deck in
            reviews.everything(deck.cards)
                .filter { $0.card.type != .occlusion && !QuizFromCards.stem(of: $0.card).isEmpty }
                .map { ReviewPlan.Due(setID: deck.id, setName: deck.name, card: $0.card, due: $0.due) }
        }
        .prefix(6).map { $0 }
    }

    private var setup: some View {
        let due = dueCards
        let stand = due.isEmpty ? exampleCards : []
        return Form {
            Section {
                Toggle(isOn: $includeDue) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cards due today")
                        Text(due.isEmpty
                             ? (stand.isEmpty ? "Nothing due right now." : "Nothing due - \(stand.count) example cards instead.")
                             : "\(due.count) ready to read aloud")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Read aloud")
            } footer: {
                Text("Say the answer after each card. Right is rated Good, wrong is rated Again, exactly as on Due today.")
            }

            if !questionSets.isEmpty {
                Section {
                    ForEach(questionSets) { set in
                        Toggle(isOn: chosen(set.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(set.name).lineLimit(2)
                                Text("\(readableQuestions(in: set).count) questions")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Stepper("Up to \(perSet) from each", value: $perSet, in: 5...50, step: 5)
                } header: {
                    Text("Questions")
                } footer: {
                    Text("Options are read as A to E; say the letter. Questions built on an image are left out.")
                }
            }

            Section {
                Toggle(isOn: $naturalVoice) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Natural cloud voice")
                        Text("A human-sounding voice, made online")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Voice")
            } footer: {
                Text(voiceFooter)
            }

            Section {
                Button {
                    start(due: due.isEmpty ? stand : due)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .disabled(playlist(due: due.isEmpty ? stand : due).isEmpty)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Keeps going with the screen locked. Headphone play/pause works too. Where this iPhone can, your voice is turned into text on the phone itself. Say \u{201C}skip\u{201D}, \u{201C}repeat\u{201D} or \u{201C}I don't know\u{201D} at any time.")
            }

            Section {
                NavigationLink {
                    ExplainBackView()
                } label: {
                    Label("Explain it back", systemImage: "person.wave.2")
                }
            } footer: {
                Text("Explain a topic out loud and have it marked against the lecture.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var voiceFooter: String {
        let phone = "For the most natural voice on this iPhone alone, download a Premium or Enhanced English voice in Settings \u{203A} Accessibility \u{203A} Spoken Content \u{203A} Voices."
        if naturalVoice {
            return "Part of Pro. Used for commute mode and spoken OSCE stations; with no connection, this iPhone's own voice reads instead. " + phone
        }
        return "This iPhone's own voice reads everything. " + phone
    }

    private func chosen(_ id: UUID) -> Binding<Bool> {
        Binding(get: { chosenSets.contains(id) },
                set: { on in if on { chosenSets.insert(id) } else { chosenSets.remove(id) } })
    }

    /// Questions that can be asked aloud and answered by letter: no
    /// picture, and a key among the options read out (A to E) - a key past
    /// E, or missing, would make every spoken answer wrong.
    private func readableQuestions(in set: StudySet) -> [MCQQuestion] {
        let spoken: Int = SpokenAnswer.letters.count
        return set.questions.filter { q in
            q.imageIndex == nil && q.options.count >= 2
                && q.options.indices.contains(q.correctIndex) && q.correctIndex < spoken
        }
    }

    private func playlist(due: [ReviewPlan.Due]) -> [CommuteSession.Item] {
        var items: [CommuteSession.Item] = includeDue ? due.map { CommuteSession.Item.card($0) } : []
        for set in questionSets where chosenSets.contains(set.id) {
            items += readableQuestions(in: set).shuffled().prefix(perSet)
                .map { CommuteSession.Item.question($0, setName: set.name) }
        }
        return items
    }

    private func start(due: [ReviewPlan.Due]) {
        session.load(playlist(due: due), reviews: reviews)
        session.start()
    }

    // MARK: playing

    private var player: some View {
        VStack(spacing: 0) {
            HStack {
                Text(session.finished ? "Finished" : "\(session.remaining) to go")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Label("\(session.right)", systemImage: "checkmark")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.green)
                Label("\(session.wrong)", systemImage: "xmark")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.red)
            }
            .padding(.horizontal).padding(.vertical, 8)

            if let message = session.hearing?.message {
                VoicePermissionNote(message: message)
                    .padding(.horizontal)
            }

            transcript

            CommuteHeard(listener: session.listener)

            controls
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(session.lines) { line in
                    CommuteLineRow(line: line).id(line.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: session.lines.count) { _, _ in
                if let last = session.lines.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button("New list") { session.clear() }
                .buttonStyle(.glass)
            Button {
                session.toggle()
            } label: {
                Image(systemName: session.running ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 84, height: 84)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(session.finished)
            .accessibilityLabel(session.running ? "Pause" : "Start")
            Button("Skip") { session.skip() }
                .buttonStyle(.glass)
                .disabled(session.finished)
        }
        .padding(.vertical, 14)
    }
}

/// One line of the running transcript.
private struct CommuteLineRow: View {
    let line: CommuteSession.Line

    var body: some View {
        switch line.kind {
        case .app:
            Text(line.text).font(.callout)
        case .you:
            Label(line.text, systemImage: "mic.fill")
                .font(.callout.italic()).foregroundStyle(.tint)
        case .right:
            Label(line.text, systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.green)
        case .wrong:
            Label(line.text, systemImage: "xmark.circle.fill")
                .font(.callout).foregroundStyle(.red)
        case .note:
            Text(line.text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// What the microphone is hearing right now, while it listens.
private struct CommuteHeard: View {
    @ObservedObject var listener: VoiceListener

    var body: some View {
        if listener.listening {
            HStack(spacing: 8) {
                Image(systemName: "waveform").symbolEffect(.variableColor.iterative)
                Text(listener.text.isEmpty ? "Listening\u{2026}" : listener.text)
                    .lineLimit(2)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal).padding(.top, 6)
        }
    }
}
