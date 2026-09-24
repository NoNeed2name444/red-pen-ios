import SwiftUI

/// Explain it back: pick a topic, explain it out loud as if teaching it, and
/// have the explanation marked against the lecture it came from - what was
/// covered, what was missed, what was wrong - with the gaps turned into cards.
///
/// Explaining is the hardest test of knowing something: a card can be
/// recognised, but an explanation has to be produced, in order, with nothing
/// to prompt it. This makes that test something a student can take alone.
struct ExplainBackView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var llm: LocalLLMService
    @StateObject private var listener = VoiceListener()
    @ObservedObject private var history = VoiceHistory.shared

    @State private var setID: UUID?
    @State private var topic = ""
    @State private var transcript = ""
    @State private var hearing: VoiceAccess.Hearing?
    @State private var marking = false
    @State private var failure: String?
    @State private var shown: ExplainAttempt?
    @State private var showModels = false

    private var chosenSet: StudySet? { store.library.first { $0.id == setID } }

    /// What has been said so far, including the words still being heard.
    private var liveText: String {
        guard listener.listening, !listener.text.isEmpty else { return transcript }
        return transcript.isEmpty ? listener.text : transcript + " " + listener.text
    }

    var body: some View {
        Form {
            topicSection
            recordSection
            markSection
            pastSection
        }
        .scrollContentBackground(.hidden)
        .modeScreen(.narrate)
        .navigationTitle("Explain it back")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $shown) { attempt in
            ExplainResultView(attempt: attempt)
        }
        .sheet(isPresented: $showModels) { ModelSettingsView() }
        // a recognition that stopped by itself (a pause too long, a server
        // limit) keeps what it heard
        .onChange(of: listener.listening) { was, now in
            if was && !now { commitHeard() }
        }
        .onDisappear {
            if listener.listening { listener.stop() }
            VoiceAccess.deactivate()
        }
    }

    // MARK: what to explain

    private var topicSection: some View {
        Section {
            Picker("From", selection: $setID) {
                Text("No set - standard teaching").tag(UUID?.none)
                ForEach(store.library) { set in
                    Text(set.name).tag(UUID?.some(set.id))
                }
            }
            TextField("Topic, e.g. the inguinal canal", text: $topic)
        } header: {
            Text("What to explain")
        } footer: {
            Text(sourceNote)
        }
        .onChange(of: setID) { _, _ in
            if topic.isEmpty, let set = chosenSet { topic = set.name.replacingOccurrences(of: "Example: ", with: "") }
        }
    }

    private var sourceNote: String {
        guard let set = chosenSet else {
            return "Without a set, it is marked against standard teaching, which is a weaker check."
        }
        if set.sources.isEmpty {
            return "\(set.name) has no lecture kept with it, so it is marked against the set's own content."
        }
        let names = set.sources.map(\.name).joined(separator: ", ")
        return "Marked against the pages of \(names) that match what you say."
    }

    // MARK: talking

    private var recordSection: some View {
        Section {
            if let message = hearing?.message {
                VoicePermissionNote(message: message)
                    .listRowBackground(Color.clear)
            }
            HStack {
                Spacer()
                Button(action: toggleRecording) {
                    Image(systemName: listener.listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .bold))
                        .frame(width: 76, height: 76)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(listener.listening ? Color.red : nil)
                .accessibilityLabel(listener.listening ? "Stop recording" : "Start explaining")
                Spacer()
            }
            .listRowBackground(Color.clear)

            if listener.listening {
                Text(liveText.isEmpty ? "Listening\u{2026} start explaining." : liveText)
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            } else {
                TextEditor(text: $transcript)
                    .frame(minHeight: 140)
            }
            if let failure = listener.failure {
                Text(failure).font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Your explanation")
        } footer: {
            Text(listener.listening && !listener.onDevice
                 ? "This iPhone recognises speech on Apple's servers, which stop after about a minute. Stop and carry on in parts - each part is added to the end."
                 : "Explain it as if teaching a friend: definition, then how it works, then why it matters clinically. Tap the microphone again to add more. You can correct the text, or type the whole thing.")
        }
    }

    private func toggleRecording() {
        if listener.listening {
            listener.stop()
            return
        }
        Task {
            let allowed = await VoiceAccess.request()
            hearing = allowed
            guard allowed.canHear else { return }
            listener.start(hints: Array(CardQuality.terms(topic)))
        }
    }

    /// Adds what was just heard to the transcript.
    private func commitHeard() {
        let heard = listener.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else { return }
        transcript = transcript.isEmpty ? heard : transcript + " " + heard
        VoiceAccess.deactivate()
    }

    // MARK: marking

    private var markSection: some View {
        Section {
            if llm.writerOrApple() == nil {
                Button("Choose a model to mark it") { showModels = true }
            } else {
                Button(action: mark) {
                    HStack {
                        if marking { ProgressView().controlSize(.small) }
                        Text(marking ? "Marking against the lecture\u{2026}" : "Mark my explanation")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(marking || listener.listening || wordCount < 15 || topic.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowBackground(Color.clear)
            }
            if let failure {
                Text(failure).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            if wordCount < 15 && !transcript.isEmpty {
                Text("Say a little more first - at least a few sentences.")
            }
        }
    }

    private var wordCount: Int {
        transcript.split { $0.isWhitespace }.count
    }

    private func mark() {
        guard let backend = llm.writerOrApple() else { showModels = true; return }
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let set = chosenSet
        let notes = set.map { Self.notes(for: $0, about: subject + " " + spoken, limit: backend.promptBudgetChars / 2) }
        marking = true
        failure = nil
        Task {
            defer { marking = false }
            do {
                let result = try await VoiceMarking.markExplanation(topic: subject, transcript: spoken,
                                                                    notes: notes, using: backend)
                let attempt = ExplainAttempt(topic: subject, setName: set?.name ?? "Standard teaching",
                                             transcript: spoken, result: result)
                history.add(attempt)
                StudyLog.shared.record()
                shown = attempt
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// The text a set's explanation is marked against: the kept lecture pages
    /// nearest to what was said, or, for a set with no lecture, the set's own
    /// content.
    static func notes(for set: StudySet, about text: String, limit: Int) -> String {
        if let pages = AccuracyChecker.reference(for: text, in: set, limit: limit) { return pages }
        return TextSlicing.nearest(content(of: set), to: text, limit: limit)
    }

    static func content(of set: StudySet) -> String {
        switch set.kind {
        case .mcq:
            return set.questions.map { AccuracyChecker.checkText($0) }.joined(separator: "\n\n")
        case .anki:
            return set.cards.map { card -> String in
                let front = card.type == .cloze ? CardQuality.clozeBare(card.clozeText) : card.displayFront
                return ([front] + card.bullets + [card.why]).map(Highlight.plain)
                    .filter { !$0.isEmpty }.joined(separator: "\n")
            }.joined(separator: "\n\n")
        case .book:
            return set.bookMarkdown
        case .qa:
            return set.qaCards.map { ([$0.topic, $0.stem] + $0.answer).map(Highlight.plain).joined(separator: "\n") }
                .joined(separator: "\n\n")
        case .osce:
            return set.osceChecklists.map { AccuracyChecker.checkText($0) }.joined(separator: "\n\n")
        case .narrate:
            return set.narrateSegments.map(\.text).joined(separator: "\n")
        }
    }

    // MARK: before

    private var pastSection: some View {
        Section("Past attempts") {
            if history.explainList.isEmpty {
                Text("Your marked explanations appear here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(history.explainList) { attempt in
                Button { shown = attempt } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(attempt.topic).foregroundStyle(.primary)
                                if attempt.isExample { VoiceExampleTag() }
                            }
                            Text(attempt.date, format: .dateTime.day().month().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(attempt.result.score)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(ExplainResultView.scoreColor(attempt.result.score))
                    }
                }
                .swipeActions {
                    if !attempt.isExample {
                        Button("Delete", role: .destructive) { history.delete(explain: attempt.id) }
                    }
                }
            }
        }
    }
}

/// One marked explanation: the score, the three lists, the tip, and the way
/// to turn the gaps into cards.
struct ExplainResultView: View {
    let attempt: ExplainAttempt

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var llm: LocalLLMService
    @State private var making = false
    @State private var madeMessage: String?

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(attempt.result.score)")
                        .font(.system(size: 54, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Self.scoreColor(attempt.result.score))
                    Text("/ 100").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    if attempt.isExample { VoiceExampleTag() }
                }
                if !attempt.result.oneTip.isEmpty {
                    Label(attempt.result.oneTip, systemImage: "lightbulb")
                        .font(.callout)
                }
            } header: {
                Text(attempt.topic)
            }

            points("Covered", attempt.result.covered, symbol: "checkmark.circle.fill", color: .green)
            points("Missed", attempt.result.missed, symbol: "circle.dashed", color: .orange)
            points("Wrong", attempt.result.wrong, symbol: "xmark.circle.fill", color: .red)

            if !gaps.isEmpty {
                Section {
                    Button(action: makeCards) {
                        HStack {
                            if making { ProgressView().controlSize(.small) }
                            Label(making ? "Writing cards\u{2026}" : "Make cards from what I missed",
                                  systemImage: "rectangle.stack.badge.plus")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(making || madeMessage != nil)
                    .listRowBackground(Color.clear)
                    if let madeMessage {
                        Text(madeMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("One card for each point missed or got wrong, saved as a new deck in your library.")
                }
            }

            Section("What you said") {
                Text(attempt.transcript).font(.callout).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .modeScreen(.narrate)
        .navigationTitle("Marked")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func points(_ title: String, _ items: [String], symbol: String, color: Color) -> some View {
        Section("\(title) (\(items.count))") {
            if items.isEmpty {
                Text("Nothing").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Label {
                    Text(item)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(color)
                }
                .font(.callout)
            }
        }
    }

    private var gaps: [String] { attempt.result.missed + attempt.result.wrong }

    private func makeCards() {
        making = true
        let backend = llm.writerOrApple()
        Task {
            defer { making = false }
            let cards = await VoiceMarking.cards(from: gaps, topic: attempt.topic, using: backend)
            guard !cards.isEmpty else { madeMessage = "Nothing to make cards from."; return }
            let source = store.library.first { $0.name == attempt.setName }
            var deck = StudySet(name: "\(attempt.topic) \u{2014} gaps", kind: .anki)
            deck.subject = source?.subject ?? "General"
            deck.cards = cards
            store.addSet(deck)
            madeMessage = "Saved \(cards.count) card\(cards.count == 1 ? "" : "s") as \u{201C}\(deck.name)\u{201D}. They're due now."
        }
    }

    static func scoreColor(_ score: Int) -> Color {
        score >= 75 ? .green : (score >= 50 ? .orange : .red)
    }
}
