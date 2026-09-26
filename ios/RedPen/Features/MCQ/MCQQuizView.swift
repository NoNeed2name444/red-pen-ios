import SwiftUI

/// The quiz screen — matches the web app's `renderQuestion()` /
/// `selectOption()` / `paintOptions()` / the `el.checkBtn` handler: pick an
/// option, check it (reveals correct/incorrect coloring + explanation),
/// then Next / See results. `state.answers[i]` becomes `answers[i]` here.
struct MCQQuizView: View {
    let studySet: StudySet
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.windowSpan) private var span
    /// Differentiate Without Colour: right and wrong are said in words beside
    /// their marks, not only in green and red.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var noColour
    /// The option's letter disc, growing with the text size.
    @ScaledMetric(relativeTo: .body) private var letterSide: CGFloat = 32
    /// At the accessibility text sizes the one-line headings wrap instead.
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var current: Int = 0
    @State private var answers: [MCQAnswer]
    /// Per-question option order: displayed slot i shows the original option
    /// `orders[q][i]` — the web app's `shuffleOptions()`, applied per session
    /// so the answer letter can't be memorised.
    @State private var orders: [[Int]]
    @State private var showSummary = false
    @State private var pendingResume: QuizProgress?
    /// Timed exam mode: the whole paper against the clock, with nothing
    /// said about right or wrong until the results. Off unless asked for.
    @State private var examMode = false
    /// When the paper's time runs out; nil once it is over.
    @State private var examEndsAt: Date?
    /// How sure the student said they were before checking, by question id.
    /// Optional for every question: an answer can be checked without it.
    @State private var confidences: [UUID: AnswerConfidence] = [:]
    /// Settings > Review: whether to show the Sure / Maybe / Guess row.
    @AppStorage(ConfidenceSetting.key) private var asksConfidence = true
    /// Why a wrong answer was wrong, as picked this sitting, by question id -
    /// kept here only to show which chip is on; the store has the record.
    @State private var reasons: [UUID: MistakeReason] = [:]
    /// True while the slow reading drill is still holding the answer back.
    @State private var holding = false
    /// The sitting's questions once a re-test has been slotted in after a
    /// miss; nil while they are the set's own, in its own order.
    @State private var reordered: [MCQQuestion]?
    /// Questions already given their one immediate re-test this sitting.
    @State private var retested: Set<UUID> = []
    /// Options crossed out, by position in the sitting, as the option's own
    /// index (not the shuffled slot) - dimmed, and never chosen by a stray tap.
    @State private var struck: [Int: Set<Int>] = [:]
    /// Pieces of each stem the highlighter marked, by position in the sitting.
    @State private var highlights: [Int: Set<Int>] = [:]
    /// Whether a tap on the stem highlights rather than reads.
    @State private var highlighting = false
    @State private var toolSheet: ExamToolSheet?
    /// The attending's hints shown this sitting; an empty string while one is
    /// being written.
    @State private var hints: [UUID: String] = [:]
    /// What came of asking for a twin, by the missed question's id.
    @State private var twinNotes: [UUID: String] = [:]
    @State private var writingTwin: Set<UUID> = []
    /// Seconds each question must be on screen before it can be answered -
    /// the slow reading drill. 0 for every other quiz.
    private let minReadSeconds: Int
    /// Opens straight into timed exam mode - the timed drill.
    private let startsTimed: Bool
    private let shuffle: Bool
    /// False for a quiz put together on the spot - flagged questions, a
    /// drill, a mix of sets - which is not in the library and so has no
    /// place to be resumed from. Saving its position would leave a row
    /// keyed by a set that will never be opened again.
    private let keepsProgress: Bool
    /// True for a just-generated set that isn't in the library yet (the
    /// web app's equivalent: a quiz opened straight from generation, with
    /// its own "Save to library" button in the header, rather than one
    /// opened from an already-saved set in the Library list). `saved` is a
    /// binding — shared with MCQSummaryView — rather than local state, so
    /// saving from either screen is reflected on both and never double-adds
    /// the set to the library.
    private let isUnsaved: Bool
    private var saved: Binding<Bool>
    private let onSave: (() -> Void)?

    /// `initialAnswers` is only used by the CI screenshot launch (see
    /// PreviewLaunch) to open the quiz with an answer already checked; it
    /// also switches shuffling off so the screenshots are stable.
    init(set studySet: StudySet, initialAnswers: [MCQAnswer]? = nil, isUnsaved: Bool = false,
         saved: Binding<Bool> = .constant(false), onSave: (() -> Void)? = nil,
         keepsProgress: Bool = true, minReadSeconds: Int = 0, startsTimed: Bool = false) {
        self.studySet = studySet
        self.minReadSeconds = max(0, minReadSeconds)
        self.startsTimed = startsTimed
        self.shuffle = initialAnswers == nil
        self.keepsProgress = keepsProgress
        self.isUnsaved = isUnsaved
        self.saved = saved
        self.onSave = onSave
        var answers = Array(repeating: MCQAnswer(), count: studySet.questions.count)
        if let initialAnswers {
            for (i, a) in initialAnswers.enumerated() where i < answers.count { answers[i] = a }
        }
        _answers = State(initialValue: answers)
        _orders = State(initialValue: Self.makeOrders(for: studySet, shuffle: initialAnswers == nil))
    }

    private static func makeOrders(for set: StudySet, shuffle: Bool) -> [[Int]] {
        set.questions.map { q in
            OptionOrder.make(count: q.options.count, shuffle: shuffle)
        }
    }

    /// The questions as they are being sat: the set's own, with any re-test
    /// slotted in.
    private var questions: [MCQQuestion] { reordered ?? studySet.questions }
    private var q: MCQQuestion { questions[current] }
    private var a: MCQAnswer { answers[current] }
    /// Question `qi`'s option order, checked against its options: a stale
    /// order (the question edited while the quiz was open) falls back to the
    /// written order rather than pointing past the end or at the wrong option.
    private func order(_ qi: Int) -> [Int] {
        let count: Int = questions[qi].options.count
        let saved: [Int]? = orders.indices.contains(qi) ? orders[qi] : nil
        return OptionOrder.valid(saved, count: count)
    }
    /// The displayed slot that holds the correct option for `question`, or
    /// -1 when its key is missing (so no slot is painted right).
    private func correctSlot(_ qi: Int) -> Int {
        OptionOrder.slot(of: questions[qi].correctIndex, in: order(qi)) ?? -1
    }
    /// Whether the answer to question `qi` is right. `selected` is a slot;
    /// it is turned back into the option's own index before it is compared
    /// with `correctIndex`, the one comparison every mark goes through.
    private func isRight(_ qi: Int) -> Bool {
        guard answers.indices.contains(qi) else { return false }
        let correctIndex: Int = questions[qi].correctIndex
        return OptionOrder.isCorrect(slot: answers[qi].selected, correctIndex: correctIndex, order: order(qi))
    }
    private func optionText(_ qi: Int, slot: Int) -> String {
        let opts = questions[qi].options
        guard let orig = OptionOrder.original(ofSlot: slot, in: order(qi)) else { return "" }
        return opts.indices.contains(orig) ? opts[orig] : ""
    }
    /// Answers translated back to original option indices — what the
    /// summary and the store expect.
    private var originalAnswers: [MCQAnswer] {
        answers.enumerated().map { qi, ans in
            var out = ans
            if qi < questions.count {
                out.selected = OptionOrder.original(ofSlot: ans.selected, in: order(qi))
            }
            return out
        }
    }

    private var scoreSoFar: (correct: Int, checked: Int) {
        var correct = 0, checked = 0
        for (i, ans) in answers.enumerated() where ans.checked {
            checked += 1
            if isRight(i) { correct += 1 }
        }
        return (correct, checked)
    }

    var body: some View {
        // a set with no questions has nothing to index into: say so rather
        // than crash on questions[0]
        if studySet.questions.isEmpty {
            ContentUnavailableView("No questions", systemImage: "questionmark.square.dashed",
                                   description: Text("This set has no questions yet."))
        } else {
            quiz
        }
    }

    private var quiz: some View {
        VStack(spacing: 0) {
            header
            questionScroll
        }
        .modeScreen(.mcq)
        // Exam mode, Check accuracy and Turn into, all in the one More menu.
        // Turn into is not for a quiz that is not saved yet, nor in the middle
        // of a timed paper.
        .studyMoreMenu(for: studySet, turnInto: !isUnsaved && examEndsAt == nil, check: accuracyAsk) {
            if canStartExam { examMenuItem }
            ExamToolMenuItems(sheet: $toolSheet, highlighting: $highlighting)
        }
        .examToolSheets($toolSheet)
        .navigationTitle(studySet.subject.isEmpty ? "MCQ" : studySet.subject)
        .diagnosticsScreen("screen:mcq_quiz")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isUnsaved {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave?(); withAnimation(.snappy) { saved.wrappedValue = true }
                    } label: {
                        Label(saved.wrappedValue ? "Saved" : "Save", systemImage: saved.wrappedValue ? "checkmark" : "square.and.arrow.down")
                            .labelStyle(.titleAndIcon)
                    }
                    // a ternary between .glass and .glassProminent won't type-check
                    // (each is a different opaque `some ButtonStyle`) — one fixed
                    // style plus .disabled() conveys the "already saved" state instead
                    .buttonStyle(.glassProminent)
                    .disabled(saved.wrappedValue)
                }
            }
        }
        // Wakes once, when the paper's time is up. Keyed by the end time, so
        // finishing early (which clears it) cancels the wait.
        .task(id: examEndsAt) {
            guard let ends = examEndsAt else { return }
            let wait = ends.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, examEndsAt == ends else { return }
            timeUp()
        }
        .navigationDestination(isPresented: $showSummary) {
            MCQSummaryView(set: sittingSet, answers: originalAnswers, onRetake: { retake() },
                           isUnsaved: isUnsaved, saved: saved, onSave: onSave)
        }
        // the slow reading drill: the answer waits until the question has
        // been on screen long enough to be read properly
        .task(id: current) {
            guard minReadSeconds > 0, answers.indices.contains(current), !answers[current].checked else {
                holding = false
                return
            }
            holding = true
            try? await Task.sleep(for: .seconds(minReadSeconds))
            if !Task.isCancelled { holding = false }
        }
        // twins asked for while offline are written now, quietly
        .task {
            guard shuffle, !ExamStore.shared.pending.isEmpty else { return }
            await TwinWriter.retryPending(store: store)
        }
        .onAppear {
            checkForResume()
            // the timed drill starts its clock at once; coming back from the
            // results finds answers checked, so it does not start again
            if startsTimed && canStartExam { startExam() }
        }
    }

    // MARK: resume / retake — the web app's resumeBanner and retakeBtn

    private func checkForResume() {
        guard shuffle, let p = store.quizProgress[studySet.id],
              p.questionIds == studySet.questions.map(\.id),
              // an option added or removed since then would leave the saved
              // order pointing past the end of the list
              p.optionOrders.count == studySet.questions.count,
              p.answers.count == studySet.questions.count,
              zip(p.optionOrders, studySet.questions).allSatisfy({ $0.count == $1.options.count }),
              p.answers.contains(where: \.checked) else { return }
        pendingResume = p
    }

    /// One quiet line over the question while the bar asks whether to pick
    /// up where the student left off.
    private func resumeBanner(_ p: QuizProgress) -> some View {
        let done: Int = p.answers.filter(\.checked).count
        let total: Int = studySet.questions.count
        let when: String = p.savedAt.formatted(.relative(presentation: .named))
        let line: String = "You left off \(when) \u{00B7} \(done) of \(total) answered"
        return Label(line, systemImage: "clock.arrow.circlepath")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(oneLine)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.slideFade(.top))
    }

    /// The bar while a saved place is waiting: Start again beside the big
    /// Resume.
    private func resumeButtons(_ p: QuizProgress) -> some View {
        let done: Int = p.answers.filter(\.checked).count
        let total: Int = studySet.questions.count
        let title: String = "Resume (\(done) of \(total))"
        return HStack(spacing: 12) {
            Button("Start again") { startAgain() }
                .buttonStyle(.bigCompanion)
                .accessibilityLabel("Start again instead")
                .accessibilityHint("Forgets where you left off and starts from the first question")
            if span == .broad { Spacer(minLength: 16) }
            Button { resume(p) } label: {
                Label(title, systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityLabel("Resume, \(done) of \(total) answered")
        }
    }

    private func resume(_ p: QuizProgress) {
        withAnimation(.snappy) {
            answers = p.answers; orders = p.optionOrders
            current = min(p.current, max(0, studySet.questions.count - 1))
            pendingResume = nil
        }
    }

    private func startAgain() {
        store.clearProgress(for: studySet.id)
        withAnimation(.snappy) { pendingResume = nil }
    }

    /// Whether `persist()` really writes. Never from the screenshot launch,
    /// never for a quiz with no place in the library - and never in exam
    /// mode: a timed paper is sat in one go, and resumed later it would carry
    /// on without its clock, with the answers it had been hiding.
    private var keepsPosition: Bool { shuffle && keepsProgress && !examMode && reordered == nil }

    /// The set as sat, re-tests and all, for the results.
    private var sittingSet: StudySet {
        guard let reordered else { return studySet }
        var out: StudySet = studySet
        out.questions = reordered
        return out
    }

    private func persist() {
        guard keepsPosition else { return }
        store.saveProgress(QuizProgress(current: current, answers: answers,
                                        questionIds: studySet.questions.map(\.id), optionOrders: orders),
                           for: studySet.id)
    }

    private func retake() {
        answers = Array(repeating: MCQAnswer(), count: studySet.questions.count)
        orders = Self.makeOrders(for: studySet, shuffle: shuffle)
        current = 0
        examMode = false
        examEndsAt = nil
        confidences = [:]
        reasons = [:]
        reordered = nil
        retested = []
        struck = [:]
        highlights = [:]
        hints = [:]
        store.clearProgress(for: studySet.id)
    }

    // MARK: timed exam mode

    /// Only before the first answer: a clock started half way through a
    /// quiz already answered with the explanations showing is not a paper.
    private var canStartExam: Bool {
        shuffle && !examMode && !answers.contains(where: \.checked)
    }

    /// The whole paper's time: the exam's pace per question times the
    /// number of questions.
    private var examSeconds: Int {
        ExamTrack.current.secondsPerQuestion * studySet.questions.count
    }

    /// The More menu's timed exam item, with how it works as its heading -
    /// a section title is the one piece of text a menu reliably shows.
    private var examMenuItem: some View {
        let track = ExamTrack.current
        let pace: String = track == .general ? "revision" : track.title
        let note: String = "\(track.secondsPerQuestion) seconds a question (\(pace) pace). Answers wait until the end."
        let title: String = "Start timed exam \u{00B7} \(Self.clock(examSeconds))"
        return Section(note) {
            Button(title, systemImage: "timer") {
                startExam()
            }
        }
    }

    /// What Report a problem sends: the question on screen, answered or not
    /// (a report shows nothing of the answer).
    private func reportItem() -> AccuracyItem? {
        guard questions.indices.contains(current) else { return nil }
        return AccuracyItem.mcq(questions[current])
    }

    /// What Check accuracy looks at: the question on screen, and only once it
    /// has been answered, because the check shows the answer.
    private var accuracyAsk: AccuracyAsk {
        AccuracyAsk(instruction: "Write a single-best-answer medical exam question, with its answer and explanation, from the source.",
                    item: reportItem) {
            guard !examMode, questions.indices.contains(current),
                  answers.indices.contains(current), answers[current].checked else { return nil }
            let question = questions[current]
            let letters: [String] = ["A", "B", "C", "D", "E", "F"]
            let options: [String] = question.options.enumerated()
                .map { "\(letters[min($0.offset, 5)]). \($0.element)" }
            let answerLine: String = "Answer: " + letters[min(max(question.correctIndex, 0), 5)]
            let explanationLine: String = "Explanation: " + question.explanation
            let lines: [String] = [question.stem] + options + [answerLine, explanationLine]
            let reasoning: String = AccuracyChecker.differentialBlock(question.differential)
            return lines.joined(separator: "\n") + reasoning
        }
    }

    /// Time left, ticking once a second, red for the last minute - a chip
    /// in the header, where it is glanced at.
    private func examClock(_ ends: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left: Int = max(0, Int(ends.timeIntervalSince(context.date).rounded(.up)))
            let ink: Color = left <= 60 ? Color.red : Color.primary
            Label(Self.clock(left), systemImage: "timer")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(ink)
                .accessibilityLabel(SpokenText.duration(seconds: left) + " left")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .liquidGlassChip(plane: .raised)
    }

    /// Before the first answer: one tap turns this into a timed paper. The
    /// same as More's Start timed exam.
    private var timedChip: some View {
        let track = ExamTrack.current
        let hint: String = "The whole paper against the clock, \(track.secondsPerQuestion) seconds a question. Answers wait until the end."
        return Button(action: startExam) {
            Label("Timed", systemImage: "timer")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Capsule())
                .liquidGlassChip()
        }
        // lifted by the style, so it sinks flat under the finger
        .buttonStyle(PopPressStyle(plane: .raised, shape: Capsule()))
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.highlight)
        .accessibilityLabel("Start a timed exam, \(Self.clock(examSeconds))")
        .accessibilityHint(hint)
    }

    /// The header's one control: the clock during a paper, or the way to
    /// start one before the first answer.
    @ViewBuilder
    private var headerAccessory: some View {
        if let ends = examEndsAt {
            examClock(ends)
        } else if canStartExam && pendingResume == nil {
            timedChip
        }
    }

    private func startExam() {
        store.clearProgress(for: studySet.id)
        withAnimation(.snappy) {
            pendingResume = nil
            examMode = true
            examEndsAt = Date().addingTimeInterval(TimeInterval(examSeconds))
        }
    }

    private func timeUp() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        // an answer chosen but not yet moved on from still counts when the
        // time runs out, as it would on the paper - marked and recorded like
        // the rest, rather than scored in the results but never recorded
        for qi in answers.indices where !answers[qi].checked && answers[qi].selected != nil {
            commit(qi)
        }
        finish()
    }

    /// "1:05:00" or "12:30".
    private static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: flags

    /// Whether this question is one the library keeps, and so can be flagged
    /// and found again. A quiz made on the spot from a deck of cards has
    /// questions that exist only for this sitting.
    private func inLibrary(_ id: UUID) -> Bool {
        store.library.contains { set in
            set.kind == .mcq && set.questions.contains { $0.id == id }
        }
    }

    private var flagButton: some View {
        let on = store.flagged.contains(q.id)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy) { store.toggleFlag(q.id) }
        } label: {
            Label(on ? "Flagged" : "Flag", systemImage: on ? "flag.fill" : "flag")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Color.orange : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PopPressStyle(plane: .raised, shape: Capsule()))
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.highlight)
        .accessibilityLabel(on ? "Remove flag" : "Flag this question")
    }

    /// "Question 3 of 20", with the running score under it - or, in exam
    /// mode, only how many are answered, since the score is what it holds back.
    private var header: some View {
        let s = scoreSoFar
        let total = questions.count
        let detail: String
        if examMode {
            detail = "\(s.checked) answered"
        } else if pendingResume != nil {
            detail = "Pick up where you left off?"
        } else if s.checked == 0 {
            detail = "Tap the answer you think is right"
        } else {
            detail = "\(s.correct) of \(s.checked) right so far"
        }
        let status: String = "Question \(current + 1) of \(total)"
        let fraction: Double = Double(current) / Double(max(1, total))
        return StudyProgressHeader(status, detail: detail, fraction: fraction) {
            headerAccessory
        }
    }

    /// The question itself, with its picture if it has one.
    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                cardTitle
                Spacer(minLength: 8)
                if canHint { HintChip(used: hints[q.id] != nil, action: askHint) }
                if inLibrary(q.id) { flagButton }
            }
            // once answered: Verified / Check this / Flagged, and why
            if a.checked && !examMode {
                AccuracyBadge(set: studySet, itemID: q.id.uuidString)
            }
            HighlightableStem(stem: q.stem, plain: stemText, marked: highlightBinding,
                              highlighting: highlighting)
                .font(.title3.weight(.semibold))
                .lineSpacing(3)
            if minReadSeconds > 0 && !a.checked {
                Label("Slow reading: the key words are marked, and you can answer after \(minReadSeconds) seconds.",
                      systemImage: "eye")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let idx = q.imageIndex, idx >= 0, idx < studySet.images.count,
               let data = Data(base64Encoded: stripDataPrefix(studySet.images[idx])),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFit().frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .contentCard()
        .riseIn()
        .id("stem-\(current)")
    }

    /// "Pick the one best answer", shortened when the chips beside it need
    /// the room - or, on a re-test, saying so.
    private var cardTitle: some View {
        let again: Bool = isRetest(current)
        let full: String = again ? "Second try \u{00B7} pick the best answer" : "Pick the one best answer"
        let short: String = again ? "Second try" : "Best answer"
        return ViewThatFits(in: .horizontal) {
            Text(full)
            Text(short)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.tint)
        .lineLimit(oneLine)
    }

    /// One line, or as many as the words need at the accessibility sizes.
    private var oneLine: Int? { typeSize.isAccessibilitySize ? nil : 1 }

    private var stemText: AttributedString {
        minReadSeconds > 0 ? Self.highlighted(q.stem) : AttributedString(q.stem)
    }

    private var highlightBinding: Binding<Set<Int>> {
        let at: Int = current
        return Binding(get: { highlights[at] ?? [] }, set: { highlights[at] = $0 })
    }

    /// Whether the question at `index` is a re-test: the same question
    /// came earlier in this sitting.
    private func isRetest(_ index: Int) -> Bool {
        guard reordered != nil, questions.indices.contains(index) else { return false }
        let id: UUID = questions[index].id
        return questions[..<index].contains { $0.id == id }
    }

    // MARK: the attending's hint

    /// Before the answer, outside a timed paper.
    private var canHint: Bool { !a.checked && !examMode && pendingResume == nil }

    private func askHint() {
        let question: MCQQuestion = q
        guard hints[question.id] == nil else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy) { hints[question.id] = "" }
        let answer: String = question.options.indices.contains(question.correctIndex)
            ? question.options[question.correctIndex] : ""
        Task {
            let text: String = await HintWriter.hint(id: question.id, stem: question.stem, options: question.options,
                                                     answer: answer, differential: question.differential)
            withAnimation(.snappy) { hints[question.id] = text }
        }
    }

    @ViewBuilder
    private var hintCard: some View {
        if let text = hints[q.id], !examMode {
            AttendingHintCard(text: text.isEmpty ? nil : text)
        }
    }

    private func optionRow(_ idx: Int) -> some View {
        let state = optionState(idx)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        // the chosen answer stands a little out of the glass; the rest lie on it
        let plane: PopOutPlane = idx == a.selected ? .raised : .screen
        let out: Bool = isStruck(idx)
        // a crossed-out option is dimmed; after checking the right one shows
        // at full strength whatever was done to it
        let dim: Double = out && (!a.checked || idx != correctSlot(current)) ? 0.45 : 1
        // the chosen option's edge is thicker with Differentiate Without Colour
        let picked: Bool = idx == a.selected
        let edge: CGFloat = noColour && picked ? 3 : 1.5
        return Button {
            // a crossed-out option is never chosen by a stray tap: restore it first
            guard !a.checked, !out else { return }
            withAnimation(.snappy(duration: 0.2)) { answers[current].selected = idx }
        } label: {
            HStack(spacing: 12) {
                Text(letter(idx))
                    .font(.body.weight(.bold).monospaced())
                    .foregroundStyle(state.badgeFg)
                    .frame(width: letterSide, height: letterSide)
                    .background(state.badgeBg, in: Circle())
                    .accessibilityHidden(true)
                // wraps, at any text size, rather than cutting an option off
                Text(optionText(current, slot: idx))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .strikethrough(out, color: .secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                optionMark(state)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .background(state.fill, in: shape)
            .overlay(shape.strokeBorder(state.border, lineWidth: edge))
            .opacity(dim)
        }
        // the chosen answer is lifted by the style, so it sinks under the finger
        .buttonStyle(PopPressStyle(plane: plane, shape: shape))
        .contentShape(.hoverEffect, shape)
        .hoverEffect(.highlight)
        .numberKey(idx + 1)
        .strikeOutGestures(struck: out, enabled: !a.checked) { toggleStrike(idx) }
        .accessibilityLabel("Answer \(letter(idx)): \(optionText(current, slot: idx))" + (out ? ", crossed out" : ""))
        .accessibilityValue(optionSpoken(idx))
        .accessibilityAddTraits(idx == a.selected ? .isSelected : [])
        // the action already ignores taps once checked — no .disabled(), which
        // would dim the correct answer along with everything else
    }

    /// The mark after an option once it is checked; with Differentiate
    /// Without Colour, its word too.
    @ViewBuilder
    private func optionMark(_ state: OptionState) -> some View {
        if let mark = state.mark {
            HStack(spacing: 4) {
                if noColour, let word = state.word {
                    Text(word).font(.caption.weight(.semibold))
                }
                Image(systemName: mark).font(.body.weight(.semibold))
            }
            .foregroundStyle(state.badgeBg)
            .accessibilityHidden(true)
        }
    }

    /// What VoiceOver says after the option's text: chosen, or - once
    /// checked, outside a paper - right or wrong.
    private func optionSpoken(_ slot: Int) -> String {
        let revealed: Bool = a.checked && !examMode
        let chosen: Bool = slot == a.selected
        let right: Bool = slot == correctSlot(current)
        return SpokenText.optionState(checked: revealed, isCorrect: right, isChosen: chosen)
    }

    /// Whether the option in `slot` is crossed out.
    private func isStruck(_ slot: Int) -> Bool {
        guard let original = OptionOrder.original(ofSlot: slot, in: order(current)) else { return false }
        return struck[current]?.contains(original) ?? false
    }

    /// Crosses an option out, or brings it back. Crossing out the chosen
    /// option un-chooses it.
    private func toggleStrike(_ slot: Int) {
        guard !a.checked, let original = OptionOrder.original(ofSlot: slot, in: order(current)) else { return }
        var set: Set<Int> = struck[current] ?? []
        let on: Bool = set.contains(original)
        if on { set.remove(original) } else { set.insert(original) }
        withAnimation(.snappy(duration: 0.2)) {
            struck[current] = set
            if !on && answers[current].selected == slot { answers[current].selected = nil }
        }
    }

    /// Whether the right answer was crossed out before checking - worth saying.
    private var struckTheAnswer: Bool {
        struck[current]?.contains(q.correctIndex) ?? false
    }

    private struct OptionState {
        var fill: Color, border: Color, badgeBg: Color, badgeFg: Color, mark: String?
        /// The mark in a word, shown beside it with Differentiate Without Colour.
        var word: String? = nil
    }

    private func optionState(_ idx: Int) -> OptionState {
        let tint = StudySetKind.mcq.tint
        let card = Color(.secondarySystemGroupedBackground)
        // exam mode keeps showing only what was chosen: right and wrong
        // wait for the results
        if !a.checked || examMode {
            let on = idx == a.selected
            return OptionState(fill: on ? tint.opacity(0.10) : card,
                               border: on ? tint : .clear,
                               badgeBg: on ? tint : Color.primary.opacity(0.07),
                               badgeFg: on ? .white : .primary, mark: nil)
        }
        if idx == correctSlot(current) {
            return OptionState(fill: .green.opacity(0.12), border: .green, badgeBg: .green, badgeFg: .white,
                               mark: "checkmark.circle.fill", word: "Right")
        }
        if idx == a.selected {
            return OptionState(fill: .red.opacity(0.10), border: .red, badgeBg: .red, badgeFg: .white,
                               mark: "xmark.circle.fill", word: "Your pick")
        }
        return OptionState(fill: card.opacity(0.7), border: .clear, badgeBg: Color.primary.opacity(0.06), badgeFg: .secondary, mark: nil)
    }

    private var explanationBox: some View {
        let correct = isRight(current)
        return VStack(alignment: .leading, spacing: 8) {
            Label(correct ? "Right!" : "Not quite", systemImage: correct ? "checkmark.seal.fill" : "info.circle.fill")
                .font(.headline)
                .foregroundStyle(correct ? Color.green : Color.red)
                .accessibilityAddTraits(.isHeader)
            if struckTheAnswer {
                Label("You crossed out the right answer. What made you rule it out?",
                      systemImage: "line.diagonal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text(q.explanation).font(.body).lineSpacing(3)
            if let tiers = q.differential, !tiers.isEmpty {
                HowToReachCard(differential: tiers, lecture: q.source)
            }
        }
        .contentCard()
        .transition(.growFade(0.96, anchor: .top))
    }

    // MARK: confidence and why a mark was lost

    /// Sure / Maybe / Guess, before checking. None is chosen to begin with,
    /// and tapping the chosen one again clears it. Marked optional, so
    /// nobody thinks they have to answer it before they can check.
    private var confidencePicker: some View {
        let chosen = confidences[q.id]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("How sure are you?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                OptionalTag()
            }
            HStack(spacing: 8) {
                ForEach(AnswerConfidence.allCases) { level in
                    chip(level.title, symbol: nil, on: chosen == level) {
                        confidences[q.id] = chosen == level ? nil : level
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Why?" under a wrong answer: one tap files the mistake under a reason
    /// for the Progress screen. Skippable - Next simply moves on.
    private var whyChooser: some View {
        let chosen = reasons[q.id]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Why did you miss it?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                OptionalTag()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MistakeReason.allCases) { reason in
                        let on = chosen == reason
                        chip(reason.title, symbol: reason.symbol, on: on) {
                            let id = q.id
                            reasons[id] = on ? nil : reason
                            store.noteMistake(on ? nil : reason, for: id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            // the chips stand out of the glass; nothing of them is cut off
            .scrollClipDisabled()
        }
        .transition(.opacity)
    }

    // MARK: fixing a miss: a re-test now, a twin later

    /// Under a wrong answer: one re-test of this question a few questions on,
    /// and a twin - the same point in a different patient - for a day or two
    /// from now. A confident mistake says why it matters most.
    private var twinOffer: some View {
        let id: UUID = q.id
        let wasSure: Bool = confidences[id] == .sure
        let canRetest: Bool = !retested.contains(id) && !isRetest(current)
        let writing: Bool = writingTwin.contains(id)
        let note: String? = twinNotes[id]
        let lead: String = wasSure
            ? "You were sure, so this is the kind of mistake that comes back. Fix it now:"
            : "Fix it while it\u{2019}s fresh:"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(lead)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                OptionalTag()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if canRetest {
                        chip("Re-test me soon", symbol: "arrow.uturn.forward", on: false) { insertRetest() }
                            .accessibilityHint("Asks this question again, re-shuffled, a few questions from now")
                    }
                    if note == nil && !writing {
                        chip("Write a twin", symbol: "square.on.square.badge.person.crop", on: false) { writeTwin() }
                            .accessibilityHint("A new question on the same point, in a different patient, for a day or two from now")
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            if retested.contains(id) && !isRetest(current) {
                Label("It comes back, re-shuffled, a few questions from now.", systemImage: "arrow.uturn.forward")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if writing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Writing a twin\u{2026}").font(.footnote).foregroundStyle(.secondary)
                }
            } else if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .transition(.opacity)
    }

    /// Slots this question in again a few questions on, options re-shuffled.
    private func insertRetest() {
        let question: MCQQuestion = q
        guard !retested.contains(question.id) else { return }
        var list: [MCQQuestion] = questions
        let slot: Int = TwinRetest.slot(after: current, count: list.count)
        list.insert(question, at: slot)
        let fresh: [Int] = OptionOrder.make(count: question.options.count, shuffle: true)
        reordered = list
        answers.insert(MCQAnswer(), at: slot)
        orders.insert(fresh, at: slot)
        struck = Self.shifted(struck, from: slot)
        highlights = Self.shifted(highlights, from: slot)
        retested.insert(question.id)
        confidences[question.id] = nil
    }

    /// Keys at or past `slot` moved one along, for a question slotted in.
    private static func shifted(_ marks: [Int: Set<Int>], from slot: Int) -> [Int: Set<Int>] {
        var out: [Int: Set<Int>] = [:]
        for (key, value) in marks {
            let moved: Int = key >= slot ? key + 1 : key
            out[moved] = value
        }
        return out
    }

    /// Asks the writer for a twin; offline it waits and is written later.
    private func writeTwin() {
        let question: MCQQuestion = q
        let id: UUID = question.id
        guard !writingTwin.contains(id) else { return }
        let picked: Int? = OptionOrder.original(ofSlot: a.selected, in: order(current))
        let confident: Bool = store.confidentMistakeIds.contains(id)
        let guessed: Bool = confidences[id] == .guess
        let request = PendingTwin(parentId: id, picked: picked, reason: reasons[id]?.title,
                                  confident: confident, guessed: guessed)
        writingTwin.insert(id)
        Task {
            let outcome: TwinOutcome = await TwinWriter.write(request, store: store)
            let days: Int = TwinQueue.delayDays(confident: confident, guessed: guessed)
            let when: String = days == 1 ? "tomorrow" : "in \(days) days"
            let said: String
            switch outcome {
            case .made: said = "Twin written. It comes back \(when), under Questions \u{2192} Twins."
            case .unavailable(let why): said = why
            case .later(let why): said = why
            }
            withAnimation(.snappy) {
                writingTwin.remove(id)
                twinNotes[id] = said
            }
        }
    }

    /// One small choice in the confidence and "why" rows: 44 points tall, so
    /// it is easy to hit, but quiet, so it never looks like the main button.
    private func chip(_ title: String, symbol: String?, on: Bool, action: @escaping () -> Void) -> some View {
        let tint = StudySetKind.mcq.tint
        let fill: Color = on ? tint : Color.primary.opacity(0.07)
        let ink: Color = on ? Color.white : Color.primary
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PopPressStyle(plane: .raised, shape: Capsule()))
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.highlight)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The stem with the words that change the answer drawn in the tint and
    /// in bold, for the slow reading drill.
    private static func highlighted(_ stem: String) -> AttributedString {
        var out = AttributedString(stem)
        for range in StemKeyWords.ranges(in: stem) {
            guard let marked = Range<AttributedString.Index>(range, in: out) else { continue }
            out[marked].foregroundColor = StudySetKind.mcq.tint
            out[marked].inlinePresentationIntent = .stronglyEmphasized
        }
        return out
    }

    /// The question, the options and what follows them, scrolling under the
    /// bar at the bottom.
    private var questionScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let p = pendingResume { resumeBanner(p) }
                questionCard
                hintCard

                VStack(spacing: 12) {
                    ForEach(q.options.indices, id: \.self) { idx in
                        optionRow(idx)
                            .riseIn(index: idx + 1)
                            .id("\(current)-\(idx)")
                    }
                }

                // in exam mode the explanation waits for the results,
                // as it would in the real paper
                if a.checked && !examMode { explanationBox }

                if a.checked && !examMode && !isRight(current)
                    && shuffle && inLibrary(q.id) {
                    whyChooser
                    twinOffer
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .readableColumn()
        }
        .studyBar { footer }
    }

    /// While a saved place waits, Start again and Resume; otherwise Back on
    /// the left, small, and the one big button - Check, then Next - in the
    /// same place for every question.
    @ViewBuilder
    private var footer: some View {
        if let p = pendingResume {
            resumeButtons(p)
        } else {
            // inside the bar, above the buttons, so it is never hidden under
            // the bar and is where the thumb already is
            if !a.checked && shuffle && asksConfidence { confidencePicker }
            answerButtons
        }
    }

    private var answerButtons: some View {
        let symbol: String = a.checked ? "arrow.right" : "checkmark"
        let waiting: Bool = !a.checked && (a.selected == nil || holding)
        return HStack(spacing: 12) {
            Button { if current > 0 { current -= 1 } } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.bigCompanion)
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(current == 0)
            .accessibilityLabel("Previous question")

            if span == .broad { Spacer(minLength: 16) }

            Button {
                withAnimation(.snappy) { onCheckOrNext() }
            } label: {
                Label(checkButtonTitle, systemImage: symbol)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(waiting)
        }
    }

    private var checkButtonTitle: String {
        let last = current == questions.count - 1
        if holding && !a.checked { return "Keep reading" }
        // says what to do, rather than sitting there grey with no reason
        if !a.checked && a.selected == nil { return "Pick an answer" }
        if examMode && !a.checked { return last ? "Finish paper" : "Next" }
        if !a.checked { return "Check answer" }
        return last ? "See results" : "Next"
    }

    private func onCheckOrNext() {
        if !a.checked {
            let right = commit(current)
            if examMode {
                // nothing to read after answering in a paper, so one tap
                // answers and moves on - and the buzz gives nothing away
                UISelectionFeedbackGenerator().selectionChanged()
                advance()
                return
            }
            // felt as well as seen (and, with Sounds on, heard): right and
            // wrong answers buzz differently - and said, with VoiceOver
            SpaceFeedback.play(right ? .correct : .wrong)
            announceResult(right)
            persist()
            return
        }
        advance()
    }

    /// Checks question `qi` and records it: marked right or wrong, and the
    /// option chosen, as its index in the question's own options (not the
    /// slot on screen) - the same space as `correctIndex`. Returns whether it
    /// was right.
    @discardableResult
    private func commit(_ qi: Int) -> Bool {
        answers[qi].checked = true
        let right: Bool = isRight(qi)
        StudyLog.shared.record()
        // the save that follows writes the history too, when there is one
        if shuffle {
            let question: MCQQuestion = questions[qi]
            let picked: Int? = OptionOrder.original(ofSlot: answers[qi].selected, in: order(qi))
            let sure: AnswerConfidence? = confidences[question.id]
            // the hint was shown first: right "with help"
            let helped: Bool = hints[question.id] != nil
            store.recordAnswer(question.id, correct: right, confidence: sure,
                               picked: picked, hinted: helped, saving: !keepsPosition)
            // a twin answered moves along its own queue
            ExamStore.shared.twinAnswered(question.id, correct: right)
        }
        return right
    }

    /// "Correct." or "Incorrect. The answer is C: ..." for VoiceOver, the
    /// moment the colours change.
    private func announceResult(_ right: Bool) {
        let slot: Int = correctSlot(current)
        let key: String = slot >= 0 ? letter(slot) : ""
        let answer: String = slot >= 0 ? optionText(current, slot: slot) : ""
        Announce.say(SpokenText.answerResult(correct: right, letter: key, answer: answer))
    }

    private func advance() {
        if current < questions.count - 1 {
            current += 1
            persist()
        } else {
            finish()
        }
    }

    private func finish() {
        store.clearProgress(for: studySet.id)
        // the paper is over: coming back from the results shows the
        // answers and explanations it was holding back
        examEndsAt = nil
        examMode = false
        showSummary = true
    }

    private func letter(_ idx: Int) -> String {
        String(Character(Unicode.Scalar(UInt8(65 + idx))))
    }

    private func stripDataPrefix(_ s: String) -> String {
        guard s.hasPrefix("data:"), let commaIdx = s.firstIndex(of: ",") else { return s }
        return String(s[s.index(after: commaIdx)...])
    }
}

/// A control that stands out of the glass at `plane` and sinks flat under the
/// finger, the way BigButtonStyle and PopTileStyle do: the chosen answer, the
/// confidence and why chips, Flag and Timed. A disabled one sits flat too
/// (popOut reads isEnabled).
struct PopPressStyle<S: InsettableShape>: ButtonStyle {
    let plane: PopOutPlane
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        let pressed: Bool = configuration.isPressed
        let scale: CGFloat = pressed ? 0.975 : 1
        return configuration.label
            .scaleEffect(scale)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
            .popOut(plane, in: shape, pressed: pressed)
    }
}
