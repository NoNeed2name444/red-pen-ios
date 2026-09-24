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
         keepsProgress: Bool = true) {
        self.studySet = studySet
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
            let identity = Array(q.options.indices)
            return shuffle ? identity.shuffled() : identity
        }
    }

    private var q: MCQQuestion { studySet.questions[current] }
    private var a: MCQAnswer { answers[current] }
    /// The displayed slot that holds the correct option for `question`.
    private func correctSlot(_ qi: Int) -> Int {
        orders[qi].firstIndex(of: studySet.questions[qi].correctIndex) ?? studySet.questions[qi].correctIndex
    }
    private func optionText(_ qi: Int, slot: Int) -> String {
        let opts = studySet.questions[qi].options
        let orig = orders[qi][slot]
        return opts.indices.contains(orig) ? opts[orig] : ""
    }
    /// Answers translated back to original option indices — what the
    /// summary and the store expect.
    private var originalAnswers: [MCQAnswer] {
        answers.enumerated().map { qi, ans in
            var out = ans
            if let sel = ans.selected, orders[qi].indices.contains(sel) { out.selected = orders[qi][sel] }
            return out
        }
    }

    private var scoreSoFar: (correct: Int, checked: Int) {
        var correct = 0, checked = 0
        for (i, ans) in answers.enumerated() where ans.checked {
            checked += 1
            if ans.selected == correctSlot(i) { correct += 1 }
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
                VStack(alignment: .leading, spacing: 14) {
                    if let p = pendingResume { resumeBanner(p) }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Question \(current + 1) · single best answer")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                                .textCase(.uppercase)
                            Spacer(minLength: 8)
                            if inLibrary(q.id) { flagButton }
                        }
                        Text(q.stem)
                            .font(.title3.weight(.semibold))
                            .lineSpacing(3)
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

                    VStack(spacing: 8) {
                        ForEach(q.options.indices, id: \.self) { idx in
                            optionRow(idx)
                                .riseIn(index: idx + 1)
                                .id("\(current)-\(idx)")
                        }
                    }

                    // in exam mode the explanation waits for the results,
                    // as it would in the real paper
                    if a.checked && !examMode { explanationBox }
                }
                .padding(.horizontal)
                .padding(.top, 6)
                .padding(.bottom, 24)
                .readableColumn()
            }
            footer
        }
        .modeScreen(.mcq)
        // not for a quiz that is not saved yet, nor in the middle of a timed paper
        .turnIntoButton(studySet, shown: !isUnsaved && examEndsAt == nil)
        .accuracyCheck(set: studySet,
                       instruction: "Write a single-best-answer medical exam question, with its answer and explanation, from the source.") {
            // only once answered: the check shows the answer
            guard !examMode, studySet.questions.indices.contains(current),
                  answers.indices.contains(current), answers[current].checked else { return nil }
            let question = studySet.questions[current]
            let letters = ["A", "B", "C", "D", "E", "F"]
            let options = question.options.enumerated()
                .map { "\(letters[min($0.offset, 5)]). \($0.element)" }
            return ([question.stem] + options
                    + ["Answer: \(letters[min(max(question.correctIndex, 0), 5)])",
                       "Explanation: \(question.explanation)"]).joined(separator: "\n")
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
            } else if canStartExam {
                ToolbarItem(placement: .topBarTrailing) { examMenu }
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
        .onAppear(perform: checkForResume)
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
                Text("Pick up where you left off?").font(.subheadline.weight(.semibold))
                Text("\(done) of \(studySet.questions.count) answered · \(p.savedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
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

    private var examMenu: some View {
        let track = ExamTrack.current
        let pace: String = track == .general ? "revision" : track.title
        let note = "\(track.secondsPerQuestion) seconds a question (\(pace) pace); answers and explanations wait for the results"
        return Menu {
            // A section title is the one piece of text a menu reliably shows.
            Section(note) {
                Button("Start timed exam \u{00B7} \(Self.clock(examSeconds))", systemImage: "timer") {
                    startExam()
                }
            }
        } label: {
            Label("Exam mode", systemImage: "timer")
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
            Image(systemName: on ? "flag.fill" : "flag")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Color.orange : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Remove flag" : "Flag this question")
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(current + 1) of \(studySet.questions.count)")
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                let s = scoreSoFar
                HStack(spacing: 5) {
                    Image(systemName: examMode ? "pencil.circle.fill" : "checkmark.circle.fill").font(.caption)
                    // how many are right is part of what exam mode holds back
                    Text(examMode ? "\(s.checked) answered" : "\(s.correct) / \(s.checked)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .liquidGlassChip()
            }
            ThinProgress(fraction: Double(current) / Double(max(1, studySet.questions.count)))
        }
        .padding(.horizontal).padding(.top, 8).padding(.bottom, 6)
    }

    private func optionRow(_ idx: Int) -> some View {
        let state = optionState(idx)
        return Button {
            guard !a.checked else { return }
            withAnimation(.snappy(duration: 0.2)) { answers[current].selected = idx }
        } label: {
            HStack(spacing: 12) {
                Text(letter(idx))
                    .font(.subheadline.weight(.bold).monospaced())
                    .foregroundStyle(state.badgeFg)
                    .frame(width: 30, height: 30)
                    .background(state.badgeBg, in: Circle())
                Text(optionText(current, slot: idx))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let mark = state.mark {
                    Image(systemName: mark).foregroundStyle(state.badgeBg).font(.body.weight(.semibold))
                }
            }
            .padding(12)
            .background(state.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(state.border, lineWidth: 1.2))
        }
        .buttonStyle(.pressableRow)
        .numberKey(idx + 1)
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
        let correct = a.selected == correctSlot(current)
        return VStack(alignment: .leading, spacing: 8) {
            Label(correct ? "Correct" : "Not quite", systemImage: correct ? "checkmark.seal.fill" : "info.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(correct ? Color.green : Color.red)
            Text(q.explanation).font(.subheadline).lineSpacing(3)
        }
        .contentCard()
        .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
    }

    private var footer: some View {
        GlassEffectContainer(spacing: 12) {
            HStack {
                Button("Previous") { if current > 0 { current -= 1 } }
                    .buttonStyle(.glass)
                    .disabled(current == 0)
                Spacer()
                Button {
                    withAnimation(.snappy) { onCheckOrNext() }
                } label: {
                    Label(checkButtonTitle, systemImage: a.checked ? "arrow.right" : "checkmark")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!a.checked && a.selected == nil)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var checkButtonTitle: String {
        let last = current == studySet.questions.count - 1
        if examMode && !a.checked { return last ? "Finish paper" : "Next" }
        if !a.checked { return "Check answer" }
        return last ? "See results" : "Next"
    }

    private func onCheckOrNext() {
        if !a.checked {
            answers[current].checked = true
            // `selected` is the slot on screen, which after shuffling is not
            // the option's place in the question - compare slot with slot
            let right = answers[current].selected == correctSlot(current)
            StudyLog.shared.record()
            // the save that follows writes the history too, when there is one
            if shuffle { store.recordAnswer(q.id, correct: right, saving: !keepsPosition) }
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
