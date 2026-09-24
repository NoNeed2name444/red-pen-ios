import SwiftUI

/// Hands-free study: the phone reads out today's due cards and questions from
/// the sets chosen, listens for the answer, says whether it was right, and
/// moves on - on a bus, walking, or with the phone locked in a pocket.
///
/// Cards are rated through the same ReviewStore as Due today (right is Good,
/// wrong is Again), so the drive counts as a review.
///
/// Layout: what to play is chosen in a list; Start sits in the floating bar
/// at the bottom, under the thumb. While playing, the count is at the top and
/// Skip and the big Play/Pause circle are at the bottom. Starting a new list
/// mid-way is rare, so it waits in the top corner behind a confirmation; once
/// the list is finished, New list takes over the bottom bar.
struct CommuteModeView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore
    @StateObject private var session = CommuteSession()

    @State private var includeDue = true
    @State private var chosenSets: Set<UUID> = []
    @State private var perSet = 10
    @State private var confirmNewList = false
    /// Read by VoiceSpeaker everywhere the app speaks, not only here.
    @AppStorage(CloudVoiceSetting.key) private var naturalVoice = true

    var body: some View {
        Group {
            if session.items.isEmpty {
                setupScreen
            } else {
                player
            }
        }
        .modeScreen(.anki)
        .navigationTitle("Commute mode")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { session.end() }
        // the microphone is listening: the camera stays off
        .popOutFacePaused()
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

    /// The list and its floating Start bar. The cards worked out here are
    /// the ones Start plays.
    private var setupScreen: some View {
        let due: [ReviewPlan.Due] = dueCards
        let stand: [ReviewPlan.Due] = due.isEmpty ? exampleCards : []
        let cards: [ReviewPlan.Due] = due.isEmpty ? stand : due
        let ready: Bool = hasSomething(cards: cards)
        return setupForm(due: due, stand: stand)
            .studyBar {
                CommuteStartBar(ready: ready) { start(due: cards) }
            }
    }

    private func setupForm(due: [ReviewPlan.Due], stand: [ReviewPlan.Due]) -> some View {
        Form {
            Section {
                Toggle(isOn: $includeDue) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cards due today")
                        Text(dueLine(due: due, stand: stand))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Read aloud")
            } footer: {
                Text("Right rates Good, wrong rates Again.")
            }

            if !questionSets.isEmpty {
                questionsSection
            }

            voiceSection

            Section {
                NavigationLink {
                    ExplainBackView()
                } label: {
                    Label("Explain it back", systemImage: "person.wave.2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func dueLine(due: [ReviewPlan.Due], stand: [ReviewPlan.Due]) -> String {
        if !due.isEmpty { return "\(due.count) ready to read aloud" }
        if stand.isEmpty { return "Nothing due right now." }
        return "Nothing due - \(stand.count) example cards instead."
    }

    private var questionsSection: some View {
        Section {
            ForEach(questionSets) { set in
                Toggle(isOn: chosen(set.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(set.name).lineLimit(2)
                        Text(questionCount(in: set))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Stepper("Up to \(perSet) from each", value: $perSet, in: 5...50, step: 5)
        } header: {
            Text("Questions")
        } footer: {
            Text("Say the letter, A to E.")
        }
    }

    /// The voice choice, folded away: it is set once and rarely changed.
    private var voiceSection: some View {
        Section {
            DisclosureGroup {
                Toggle(isOn: $naturalVoice) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Natural cloud voice")
                        Text("A human-sounding voice, made online")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(voiceNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } label: {
                CommuteVoiceLabel(natural: naturalVoice)
            }
        } footer: {
            Text("Works with the screen locked.")
        }
    }

    private var voiceNote: String {
        let phone = "For the most natural voice on this iPhone alone, download a Premium or Enhanced English voice in Settings \u{203A} Accessibility \u{203A} Spoken Content \u{203A} Voices."
        let hands = "Headphone play/pause works too; where this iPhone can, your voice is turned into text on the phone itself."
        let cloud = "Part of Pro. Used for commute mode and spoken OSCE stations; with no connection, this iPhone's own voice reads instead."
        let own = "This iPhone's own voice reads everything."
        let say = "Say \u{201C}skip\u{201D}, \u{201C}repeat\u{201D} or \u{201C}I don't know\u{201D} any time."
        let first: String = naturalVoice ? cloud : own
        let parts: [String] = [say, first, phone, hands]
        return parts.joined(separator: " ")
    }

    /// How many questions of a set are read out; ones built on a picture
    /// are left out, and the line says so.
    private func questionCount(in set: StudySet) -> String {
        let readable: Int = readableQuestions(in: set).count
        let pictures: Int = set.questions.filter { $0.imageIndex != nil }.count
        let count: String = readable == 1 ? "1 question" : "\(readable) questions"
        if pictures == 0 { return count }
        let note: String = pictures == 1 ? "1 on a picture left out" : "\(pictures) on a picture left out"
        return count + " \u{00B7} " + note
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

    /// Whether Start would have anything to play, without shuffling a list.
    private func hasSomething(cards: [ReviewPlan.Due]) -> Bool {
        if includeDue && !cards.isEmpty { return true }
        return questionSets.contains { set in
            chosenSets.contains(set.id) && !readableQuestions(in: set).isEmpty
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
        let items: [CommuteSession.Item] = playlist(due: due)
        guard !items.isEmpty else { return }
        session.load(items, reviews: reviews)
        session.start()
    }

    // MARK: playing

    private var player: some View {
        VStack(spacing: 0) {
            progressHeader

            if let message = session.hearing?.message {
                VoicePermissionNote(message: message)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            transcript
        }
        .studyBar {
            CommuteHeard(listener: session.listener)
            CommutePlayerBar(session: session)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New list") { askNewList() }
                    .accessibilityHint("Stops this list and goes back to choosing what to play")
            }
        }
        .confirmationDialog("Start a new list?", isPresented: $confirmNewList, titleVisibility: .visible) {
            Button("New list", role: .destructive) { session.clear() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("This list stops here. Cards already answered keep their ratings.")
        }
    }

    private var progressHeader: some View {
        let total: Int = session.items.count
        let done: Int = min(session.position, total)
        let fraction: Double = total > 0 ? Double(done) / Double(total) : 0
        let status: String = session.finished ? "Finished" : "\(session.remaining) to go"
        let detail: String = "\(session.right) right \u{00B7} \(session.wrong) wrong"
        return StudyProgressHeader(status, detail: detail, fraction: fraction)
    }

    /// Nothing to lose once the list is finished, so no question then.
    private func askNewList() {
        if session.finished {
            session.clear()
        } else {
            confirmNewList = true
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
}

/// The setup screen's floating bar: Start, the one thing to do.
private struct CommuteStartBar: View {
    let ready: Bool
    let start: () -> Void

    var body: some View {
        if !ready {
            Text("Turn on due cards or choose a question set.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        Button(action: start) {
            Label("Start", systemImage: "play.fill")
        }
        .buttonStyle(.bigPrimary)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(!ready)
    }
}

/// The player's floating bar: Skip under the left thumb, the big Play/Pause
/// circle - the screen's hero - under the right. Once the list is finished
/// there is nothing left to skip or play, so New list takes the bar's place,
/// still under the thumb.
private struct CommutePlayerBar: View {
    @ObservedObject var session: CommuteSession

    var body: some View {
        let finished: Bool = session.finished
        if finished {
            CommuteNewListButton { session.clear() }
        } else {
            CommutePlayControls(session: session)
        }
    }
}

/// Skip and the big Play/Pause circle, while the list is still playing.
private struct CommutePlayControls: View {
    @ObservedObject var session: CommuteSession

    var body: some View {
        let running: Bool = session.running
        let symbol: String = running ? "pause.fill" : "play.fill"
        let label: String = running ? "Pause" : "Start"
        HStack(spacing: 14) {
            Button("Skip") { session.skip() }
                .buttonStyle(.bigSecondary)
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button {
                session.toggle()
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 84, height: 84)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .popOut(.hero, in: Circle())
            .hoverEffect(.lift)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(label)
        }
    }
}

/// The finished list's one action: back to choosing what to play. Nothing is
/// lost by then, so it asks nothing.
private struct CommuteNewListButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New list", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.bigPrimary)
        .keyboardShortcut(.return, modifiers: [])
        .accessibilityHint("Goes back to choosing what to play")
    }
}

/// The folded voice row: what it is, and which voice is on.
private struct CommuteVoiceLabel: View {
    let natural: Bool

    var body: some View {
        let chosen: String = natural ? "Natural" : "This iPhone"
        HStack {
            Label("Voice", systemImage: "speaker.wave.2")
            Spacer(minLength: 8)
            Text(chosen)
                .foregroundStyle(.secondary)
        }
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

/// What the microphone is hearing right now, while it listens: a line at the
/// top of the floating bar, just above the controls.
private struct CommuteHeard: View {
    @ObservedObject var listener: VoiceListener

    var body: some View {
        if listener.listening {
            let words: String = listener.text.isEmpty ? "Listening\u{2026}" : listener.text
            HStack(spacing: 8) {
                Image(systemName: "waveform").symbolEffect(.variableColor.iterative)
                Text(words)
                    .lineLimit(2)
                    .truncationMode(.head)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }
}
