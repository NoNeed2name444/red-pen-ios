import SwiftUI

/// The quiz screen — matches the web app's `renderQuestion()` /
/// `selectOption()` / `paintOptions()` / the `el.checkBtn` handler: pick an
/// option, check it (reveals correct/incorrect coloring + explanation),
/// then Next / See results. `state.answers[i]` becomes `answers[i]` here.
struct MCQQuizView: View {
    let studySet: StudySet
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

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
    /// Why a wrong answer was wrong, as picked this sitting, by question id -
    /// kept here only to show which chip is on; the store has the record.
    @State private var reasons: [UUID: MistakeReason] = [:]
    /// True while the slow reading drill is still holding the answer back.
    @State private var holding = false
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

    private var q: MCQQuestion { studySet.questions[current] }
    private var a: MCQAnswer { answers[current] }
    /// Question `qi`'s option order, checked against its options: a stale
    /// order (the question edited while the quiz was open) falls back to the
    /// written order rather than pointing past the end or at the wrong option.
    private func order(_ qi: Int) -> [Int] {
        let count: Int = studySet.questions[qi].options.count
        let saved: [Int]? = orders.indices.contains(qi) ? orders[qi] : nil
        return OptionOrder.valid(saved, count: count)
    }
    /// The displayed slot that holds the correct option for `question`, or
    /// -1 when its key is missing (so no slot is painted right).
    private func correctSlot(_ qi: Int) -> Int {
        OptionOrder.slot(of: studySet.questions[qi].correctIndex, in: order(qi)) ?? -1
    }
    /// Whether the answer to question `qi` is right. `selected` is a slot;
    /// it is turned back into the option's own index before it is compared
    /// with `correctIndex`, the one comparison every mark goes through.
    private func isRight(_ qi: Int) -> Bool {
        guard answers.indices.contains(qi) else { return false }
        let correctIndex: Int = studySet.questions[qi].correctIndex
        return OptionOrder.isCorrect(slot: answers[qi].selected, correctIndex: correctIndex, order: order(qi))
    }
    private func optionText(_ qi: Int, slot: Int) -> String {
        let opts = studySet.questions[qi].options
        guard let orig = OptionOrder.original(ofSlot: slot, in: order(qi)) else { return "" }
        return opts.indices.contains(orig) ? opts[orig] : ""
    }
    /// Answers translated back to original option indices — what the
    /// summary and the store expect.
    private var originalAnswers: [MCQAnswer] {
        answers.enumerated().map { qi, ans in
            var out = ans
            if qi < studySet.questions.count {
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let p = pendingResume { resumeBanner(p) }
                    questionCard

                    VStack(spacing: 12) {
                        ForEach(q.options.indices, id: \.self) { idx in
                            optionRow(idx)
                                .riseIn(index: idx + 1)
                                .id("\(current)-\(idx)")
                        }
                    }

                    if !a.checked && shuffle { confidencePicker }

                    // in exam mode the explanation waits for the results,
                    // as it would in the real paper
                    if a.checked && !examMode { explanationBox }

                    if a.checked && !examMode && !isRight(current)
                        && shuffle && inLibrary(q.id) {
                        whyChooser
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .readableColumn()
            }
            footer
        }
        .modeScreen(.mcq)
        // Exam mode, Check accuracy and Turn into, all in the one More menu.
        // Turn into is not for a quiz that is not saved yet, nor in the middle
        // of a timed paper.
        .studyMoreMenu(for: studySet, turnInto: !isUnsaved && examEndsAt == nil, check: accuracyAsk) {
            if canStartExam { examMenuItem }
        }
        .navigationTitle(studySet.subject.isEmpty ? "MCQ" : studySet.subject)
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
            if let ends = examEndsAt {
                ToolbarItem(placement: .topBarTrailing) { examClock(ends) }
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
            MCQSummaryView(set: studySet, answers: originalAnswers, onRetake: { retake() },
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

    private func resumeBanner(_ p: QuizProgress) -> some View {
        let done = p.answers.filter(\.checked).count
        return HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath").font(.title3).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pick up where you left off?").font(.headline)
                Text("\(done) of \(studySet.questions.count) answered · \(p.savedAt.formatted(.relative(presentation: .named)))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Resume") {
                withAnimation(.snappy) {
                    answers = p.answers; orders = p.optionOrders
                    current = min(p.current, max(0, studySet.questions.count - 1))
                    pendingResume = nil
                }
            }
            .buttonStyle(.glassProminent)
            Button {
                store.clearProgress(for: studySet.id)
                withAnimation(.snappy) { pendingResume = nil }
            } label: { Image(systemName: "xmark") }
            .buttonStyle(.glass)
            .accessibilityLabel("Start again instead")
        }
        .contentCard()
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Whether `persist()` really writes. Never from the screenshot launch,
    /// never for a quiz with no place in the library - and never in exam
    /// mode: a timed paper is sat in one go, and resumed later it would carry
    /// on without its clock, with the answers it had been hiding.
    private var keepsPosition: Bool { shuffle && keepsProgress && !examMode }

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

    /// What Check accuracy looks at: the question on screen, and only once it
    /// has been answered, because the check shows the answer.
    private var accuracyAsk: AccuracyAsk {
        AccuracyAsk(instruction: "Write a single-best-answer medical exam question, with its answer and explanation, from the source.") {
            guard !examMode, studySet.questions.indices.contains(current),
                  answers.indices.contains(current), answers[current].checked else { return nil }
            let question = studySet.questions[current]
            let letters: [String] = ["A", "B", "C", "D", "E", "F"]
            let options: [String] = question.options.enumerated()
                .map { "\(letters[min($0.offset, 5)]). \($0.element)" }
            let answerLine: String = "Answer: " + letters[min(max(question.correctIndex, 0), 5)]
            let explanationLine: String = "Explanation: " + question.explanation
            let lines: [String] = [question.stem] + options + [answerLine, explanationLine]
            return lines.joined(separator: "\n")
        }
    }

    /// Time left, ticking once a second, red for the last minute.
    private func examClock(_ ends: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, Int(ends.timeIntervalSince(context.date).rounded(.up)))
            Label(Self.clock(left), systemImage: "timer")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(left <= 60 ? Color.red : Color.primary)
                .accessibilityLabel("\(left / 60) minutes \(left % 60) seconds left")
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
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Remove flag" : "Flag this question")
    }

    /// "Question 3 of 20", with the running score under it - or, in exam
    /// mode, only how many are answered, since the score is what it holds back.
    private var header: some View {
        let s = scoreSoFar
        let total = studySet.questions.count
        let detail: String
        if examMode {
            detail = "\(s.checked) answered"
        } else if s.checked == 0 {
            detail = "Tap the answer you think is right"
        } else {
            detail = "\(s.correct) of \(s.checked) right so far"
        }
        return StudyProgressHeader("Question \(current + 1) of \(total)", detail: detail,
                                   fraction: Double(current) / Double(max(1, total)))
    }

    /// The question itself, with its picture if it has one.
    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Pick the one best answer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer(minLength: 8)
                if inLibrary(q.id) { flagButton }
            }
            Text(minReadSeconds > 0 ? Self.highlighted(q.stem) : AttributedString(q.stem))
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

    private func optionRow(_ idx: Int) -> some View {
        let state = optionState(idx)
        return Button {
            guard !a.checked else { return }
            withAnimation(.snappy(duration: 0.2)) { answers[current].selected = idx }
        } label: {
            HStack(spacing: 12) {
                Text(letter(idx))
                    .font(.body.weight(.bold).monospaced())
                    .foregroundStyle(state.badgeFg)
                    .frame(width: 32, height: 32)
                    .background(state.badgeBg, in: Circle())
                    .accessibilityHidden(true)
                Text(optionText(current, slot: idx))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let mark = state.mark {
                    Image(systemName: mark).foregroundStyle(state.badgeBg).font(.body.weight(.semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .background(state.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(state.border, lineWidth: 1.5))
        }
        .buttonStyle(.pressableRow)
        .numberKey(idx + 1)
        .accessibilityLabel("Answer \(letter(idx)): \(optionText(current, slot: idx))")
        .accessibilityAddTraits(idx == a.selected ? .isSelected : [])
        // the action already ignores taps once checked — no .disabled(), which
        // would dim the correct answer along with everything else
    }

    private struct OptionState {
        var fill: Color, border: Color, badgeBg: Color, badgeFg: Color, mark: String?
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
            return OptionState(fill: .green.opacity(0.12), border: .green, badgeBg: .green, badgeFg: .white, mark: "checkmark.circle.fill")
        }
        if idx == a.selected {
            return OptionState(fill: .red.opacity(0.10), border: .red, badgeBg: .red, badgeFg: .white, mark: "xmark.circle.fill")
        }
        return OptionState(fill: card.opacity(0.7), border: .clear, badgeBg: Color.primary.opacity(0.06), badgeFg: .secondary, mark: nil)
    }

    private var explanationBox: some View {
        let correct = isRight(current)
        return VStack(alignment: .leading, spacing: 8) {
            Label(correct ? "Right!" : "Not quite", systemImage: correct ? "checkmark.seal.fill" : "info.circle.fill")
                .font(.headline)
                .foregroundStyle(correct ? Color.green : Color.red)
            Text(q.explanation).font(.body).lineSpacing(3)
        }
        .contentCard()
        .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
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
        .padding(.top, 4)
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
            }
        }
        .transition(.opacity)
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
        }
        .buttonStyle(.plain)
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

    /// Back on the left, small; the one big button - Check, then Next -
    /// filling the rest, in the same place for every question.
    private var footer: some View {
        StudyActionBar {
            HStack(spacing: 12) {
                Button { if current > 0 { current -= 1 } } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bigCompanion)
                .disabled(current == 0)
                .accessibilityLabel("Previous question")

                Button {
                    withAnimation(.snappy) { onCheckOrNext() }
                } label: {
                    Label(checkButtonTitle, systemImage: a.checked ? "arrow.right" : "checkmark")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bigPrimary)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!a.checked && (a.selected == nil || holding))
            }
        }
    }

    private var checkButtonTitle: String {
        let last = current == studySet.questions.count - 1
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
            // felt as well as seen: right and wrong answers buzz differently
            UINotificationFeedbackGenerator().notificationOccurred(right ? .success : .error)
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
            let question: MCQQuestion = studySet.questions[qi]
            let picked: Int? = OptionOrder.original(ofSlot: answers[qi].selected, in: order(qi))
            let sure: AnswerConfidence? = confidences[question.id]
            store.recordAnswer(question.id, correct: right, confidence: sure,
                               picked: picked, saving: !keepsPosition)
        }
        return right
    }

    private func advance() {
        if current < studySet.questions.count - 1 {
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
