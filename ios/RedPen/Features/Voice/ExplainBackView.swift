import SwiftUI

/// Explain it back: pick a topic, explain it out loud as if teaching it, and
/// have the explanation marked against the lecture it came from - what was
/// covered, what was missed, what was wrong - with the gaps turned into cards.
///
/// Explaining is the hardest test of knowing something: a card can be
/// recognised, but an explanation has to be produced, in order, with nothing
/// to prompt it. This makes that test something a student can take alone.
///
/// Layout: what to explain is chosen at the top; the explanation fills the
/// middle; the microphone and Mark sit in the floating bar under the thumbs.
/// Past attempts are a History button away in the top corner.
struct ExplainBackView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var llm: LocalLLMService
    @StateObject private var listener = VoiceListener()

    @State private var setID: UUID?
    @State private var topic = ""
    @State private var transcript = ""
    @State private var hearing: VoiceAccess.Hearing?
    @State private var marking = false
    @State private var failure: String?
    @State private var shown: ExplainAttempt?
    @State private var showModels = false
    @State private var showHistory = false
    @FocusState private var focus: ExplainField?
    /// Whether the page is showing: a permission answered after leaving must
    /// not switch the microphone on behind the next screen.
    @State private var onScreen = false

    private var chosenSet: StudySet? { store.library.first { $0.id == setID } }

    /// What has been said so far, including the words still being heard.
    private var liveText: String {
        guard listener.listening, !listener.text.isEmpty else { return transcript }
        return transcript.isEmpty ? listener.text : transcript + " " + listener.text
    }

    var body: some View {
        page
            .modeScreen(.narrate)
            .navigationTitle("Explain it back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .navigationDestination(item: $shown) { attempt in
                ExplainResultView(attempt: attempt)
            }
            .sheet(isPresented: $showModels) { ModelSettingsView() }
            .sheet(isPresented: $showHistory) {
                ExplainHistorySheet()
                    .environmentObject(store)
                    .environmentObject(llm)
            }
            // a recognition that stopped by itself (a pause too long, a server
            // limit) keeps what it heard
            .onChange(of: listener.listening) { was, now in
                if was && !now { commitHeard() }
            }
            .onChange(of: setID) { _, _ in fillTopic() }
            .onAppear { onScreen = true }
            .onDisappear {
                onScreen = false
                if listener.listening { listener.stop() }
                VoiceAccess.deactivate()
            }
            // the microphone is listening: the camera stays off
            .popOutFacePaused()
            // and speech is playing or being heard: no answer tones over it
            .spaceSoundsHushed()
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                stopListening()
                showHistory = true
            } label: {
                Label("History", systemImage: "clock")
            }
            .accessibilityHint("Your marked explanations")
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }
        }
    }

    private var page: some View {
        let writing: Bool = focus == .transcript
        return VStack(alignment: .leading, spacing: 12) {
            // while typing the explanation, the keyboard needs the room: the
            // topic folds away until the keyboard goes
            if !writing {
                topicBar
            }
            if let message = hearing?.message {
                VoicePermissionNote(message: message)
            }
            transcriptBox
            notes
        }
        .animation(.snappy(duration: 0.2), value: writing)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
        .studyBar { recordBar }
    }

    // MARK: what to explain

    private var topicBar: some View {
        let field = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            setMenu
            TextField("Topic, e.g. the inguinal canal", text: $topic)
                .focused($focus, equals: .topic)
                .submitLabel(.next)
                .onSubmit { focus = .transcript }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(.regularMaterial, in: field)
                .popOut(.raised, in: field, cues: .translateOnly)
            Text(sourceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    /// The set the explanation is marked against, as a glass chip.
    private var setMenu: some View {
        let title: String = chosenSet?.name ?? "No set - standard teaching"
        return Menu {
            Picker("Marked against", selection: $setID) {
                Text("No set - standard teaching").tag(UUID?.none)
                ForEach(store.library) { set in
                    Text(set.name).tag(UUID?.some(set.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            ExplainSetChipLabel(title: title)
        }
        .liquidGlassChip(plane: .raised)
        .hoverEffect(.highlight)
        .accessibilityLabel("Marked against")
        .accessibilityValue(title)
    }

    private func fillTopic() {
        guard topic.isEmpty, let set = chosenSet else { return }
        topic = set.name.replacingOccurrences(of: "Example: ", with: "")
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

    private static let placeholder = "Tap the microphone and explain it as if teaching a friend: what it is, how it works, why it matters clinically. Or type it here."

    /// The explanation: it lies on the screen, it is read and corrected, so
    /// it never moves with the pop-out.
    private var transcriptBox: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            ExplainBoxHeader(words: wordCount)
            transcriptBody
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: shape)
    }

    @ViewBuilder
    private var transcriptBody: some View {
        if listener.listening {
            let words: String = liveText.isEmpty ? "Listening\u{2026} start explaining." : liveText
            ScrollView {
                Text(words)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
        } else {
            ZStack(alignment: .topLeading) {
                // a reading surface, read back and corrected: it stays on the
                // screen plane with its box (see transcriptBox), never lifted
                TextEditor(text: $transcript)
                    .focused($focus, equals: .transcript)
                    .scrollContentBackground(.hidden)
                if transcript.isEmpty {
                    Text(Self.placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.horizontal, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// Short lines under the explanation: why marking waits, and what went
    /// wrong, if anything.
    @ViewBuilder
    private var notes: some View {
        if listener.listening && !listener.onDevice {
            Text("This iPhone recognises speech on Apple's servers, which stop after about a minute. Stop and carry on in parts - each part is added to the end.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let heardFailure = listener.failure {
            Text(heardFailure).font(.caption).foregroundStyle(.orange)
        }
        if let failure {
            Text(failure).font(.footnote).foregroundStyle(.red)
        }
        if needsMore {
            Text("Say a little more first - at least a few sentences.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toggleRecording() {
        if listener.listening {
            listener.stop()
            return
        }
        focus = nil
        Task {
            let allowed = await VoiceAccess.request()
            hearing = allowed
            // nor behind a sheet opened while the permission was asked
            let covered: Bool = showHistory || showModels
            guard allowed.canHear, onScreen, !covered else { return }
            listener.start(hints: Array(CardQuality.terms(topic)))
        }
    }

    /// A sheet over this page does not fire its onDisappear, so the
    /// microphone is stopped by hand before one opens - what was heard so far
    /// is kept, as with the stop button.
    private func stopListening() {
        if listener.listening { listener.stop() }
    }

    /// Adds what was just heard to the transcript.
    private func commitHeard() {
        let heard = listener.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else { return }
        transcript = transcript.isEmpty ? heard : transcript + " " + heard
        VoiceAccess.deactivate()
    }

    // MARK: the bar

    /// The microphone at the leading end, Mark at the trailing end. The
    /// microphone is the screen's one hero until there is enough to mark;
    /// then Mark is, and the microphone steps down.
    private var recordBar: some View {
        HStack(spacing: 14) {
            micButton
            markButton
        }
    }

    private var micButton: some View {
        let listening: Bool = listener.listening
        let symbol: String = listening ? "stop.fill" : "mic.fill"
        let label: String = listening ? "Stop recording" : "Start explaining"
        let tint: Color? = listening ? Color.red : nil
        let plane: PopOutPlane = markIsNext ? .raised : .hero
        return Button(action: toggleRecording) {
            Image(systemName: symbol)
                .scaledFont(30, relativeTo: .title, weight: .bold, maxSize: 44)
                .frame(width: 76, height: 76)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(tint)
        .popOut(plane, in: Circle())
        .hoverEffect(.lift)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var markButton: some View {
        if llm.writerOrApple() == nil {
            let weight: BigButtonStyle.Weight = markIsNext ? .primary : .secondary
            Button("Choose a model") {
                stopListening()
                showModels = true
            }
                .buttonStyle(BigButtonStyle(weight: weight))
                .accessibilityHint("A model is needed to mark the explanation")
        } else {
            Button(action: mark) {
                ExplainMarkLabel(marking: marking)
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!canMark)
        }
    }

    // MARK: marking

    private var wordCount: Int {
        transcript.split { $0.isWhitespace }.count
    }

    private var hasTopic: Bool {
        !topic.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Enough said, on a named topic, and not still talking.
    private var markIsNext: Bool {
        !listener.listening && wordCount >= 15 && hasTopic
    }

    private var canMark: Bool { markIsNext && !marking }

    private var needsMore: Bool {
        wordCount < 15 && !transcript.isEmpty && !listener.listening
    }

    private func mark() {
        guard let backend = llm.writerOrApple() else { showModels = true; return }
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let set = chosenSet
        let notes = set.map { Self.notes(for: $0, about: subject + " " + spoken, limit: backend.promptBudgetChars / 2) }
        focus = nil
        marking = true
        failure = nil
        Task {
            defer { marking = false }
            do {
                let result = try await VoiceMarking.markExplanation(topic: subject, transcript: spoken,
                                                                    notes: notes, using: backend)
                let attempt = ExplainAttempt(topic: subject, setName: set?.name ?? "Standard teaching",
                                             transcript: spoken, result: result)
                VoiceHistory.shared.add(attempt)
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
}

/// Which box the keyboard is in.
private enum ExplainField: Hashable {
    case topic, transcript
}

/// The set chip's face: which set, and that it can be changed.
private struct ExplainSetChipLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "books.vertical")
            Text(title).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .contentShape(Capsule())
    }
}

/// "Your explanation", and how long it is so far.
private struct ExplainBoxHeader: View {
    let words: Int

    var body: some View {
        let count: String = words == 1 ? "1 word" : "\(words) words"
        HStack {
            Text("Your explanation")
                .font(.footnote.weight(.semibold))
            Spacer(minLength: 8)
            Text(count)
                .font(.footnote.monospacedDigit())
        }
        .foregroundStyle(.secondary)
    }
}

/// Mark's words, with a spinner while the examiner is at work.
private struct ExplainMarkLabel: View {
    let marking: Bool

    var body: some View {
        let title: String = marking ? "Marking\u{2026}" : "Mark my explanation"
        HStack(spacing: 8) {
            if marking {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
            Text(title)
        }
    }
}

/// The History sheet: every marked explanation, newest first. Tap one to
/// read it; swipe, or hold (right-click with a pointer), to delete it.
private struct ExplainHistorySheet: View {
    @ObservedObject private var history = VoiceHistory.shared
    @Environment(\.dismiss) private var dismiss
    @State private var open: ExplainAttempt?

    var body: some View {
        NavigationStack {
            List {
                if history.explainList.isEmpty {
                    Text("Your marked explanations appear here.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(history.explainList) { attempt in
                    ExplainHistoryRow(attempt: attempt,
                                      open: { open = attempt },
                                      delete: deleteAction(for: attempt))
                }
            }
            .scrollContentBackground(.hidden)
            .modeScreen(.narrate)
            .navigationTitle("Past attempts")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $open) { attempt in
                ExplainResultView(attempt: attempt)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Shipped examples can't be deleted.
    private func deleteAction(for attempt: ExplainAttempt) -> (() -> Void)? {
        if attempt.isExample { return nil }
        let id: UUID = attempt.id
        let kept = history
        return { kept.delete(explain: id) }
    }
}

private struct ExplainHistoryRow: View {
    let attempt: ExplainAttempt
    let open: () -> Void
    let delete: (() -> Void)?

    var body: some View {
        Button(action: open) {
            ExplainAttemptLabel(attempt: attempt)
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

private struct ExplainAttemptLabel: View {
    let attempt: ExplainAttempt

    var body: some View {
        let score: Int = attempt.result.score
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
            Text("\(score)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(ExplainResultView.scoreColor(score))
        }
    }
}

/// One marked explanation: the score, the three lists, the tip, and the way
/// to turn the gaps into cards - in the floating bar at the bottom.
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
                        .scaledFont(54, relativeTo: .largeTitle, weight: .bold, design: .rounded)
                        .monospacedDigit()
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

            Section("What you said") {
                Text(attempt.transcript).font(.callout).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .modeScreen(.narrate)
        .navigationTitle("Marked")
        .navigationBarTitleDisplayMode(.inline)
        // the same floating slab as .studyBar, shown only when there are
        // gaps to make cards from
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !gaps.isEmpty {
                StudyActionBar { makeCardsBar }
            }
        }
        .popOutFacePaused()
    }

    @ViewBuilder
    private var makeCardsBar: some View {
        let note: String = madeMessage ?? "One card for each point missed or wrong, saved as a new deck."
        let title: String = making ? "Writing cards\u{2026}" : "Make cards from what I missed"
        Text(note)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        Button(action: makeCards) {
            HStack(spacing: 8) {
                if making {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Label(title, systemImage: "rectangle.stack.badge.plus")
            }
        }
        .buttonStyle(.bigPrimary)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(making || madeMessage != nil)
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
            let plural: String = cards.count == 1 ? "" : "s"
            madeMessage = "Saved \(cards.count) card\(plural) as \u{201C}\(deck.name)\u{201D}. They're due now."
        }
    }

    static func scoreColor(_ score: Int) -> Color {
        score >= 75 ? .green : (score >= 50 ? .orange : .red)
    }
}
