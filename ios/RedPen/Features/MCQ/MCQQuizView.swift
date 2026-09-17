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
    private let shuffle: Bool
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
         saved: Binding<Bool> = .constant(false), onSave: (() -> Void)? = nil) {
        self.studySet = studySet
        self.shuffle = initialAnswers == nil
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
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let p = pendingResume { resumeBanner(p) }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Question \(current + 1) · single best answer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                            .textCase(.uppercase)
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

                    if a.checked { explanationBox }
                }
                .padding(.horizontal)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            footer
        }
        .modeScreen(.mcq)
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

    private func persist() {
        guard shuffle else { return } // never from the screenshot launch
        store.saveProgress(QuizProgress(current: current, answers: answers,
                                        questionIds: studySet.questions.map(\.id), optionOrders: orders),
                           for: studySet.id)
    }

    private func retake() {
        answers = Array(repeating: MCQAnswer(), count: studySet.questions.count)
        orders = Self.makeOrders(for: studySet, shuffle: shuffle)
        current = 0
        store.clearProgress(for: studySet.id)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(current + 1) of \(studySet.questions.count)")
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                let s = scoreSoFar
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").font(.caption)
                    Text("\(s.correct) / \(s.checked)")
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
        // the action already ignores taps once checked — no .disabled(), which
        // would dim the correct answer along with everything else
    }

    private struct OptionState {
        var fill: Color, border: Color, badgeBg: Color, badgeFg: Color, mark: String?
    }

    private func optionState(_ idx: Int) -> OptionState {
        let tint = StudySetKind.mcq.tint
        let card = Color(.secondarySystemGroupedBackground)
        if !a.checked {
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
                .disabled(!a.checked && a.selected == nil)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var checkButtonTitle: String {
        if !a.checked { return "Check answer" }
        return current == studySet.questions.count - 1 ? "See results" : "Next"
    }

    private func onCheckOrNext() {
        if !a.checked {
            answers[current].checked = true
            persist()
            return
        }
        if current < studySet.questions.count - 1 {
            current += 1
            persist()
        } else {
            store.clearProgress(for: studySet.id)
            showSummary = true
        }
    }

    private func letter(_ idx: Int) -> String {
        String(Character(Unicode.Scalar(UInt8(65 + idx))))
    }

    private func stripDataPrefix(_ s: String) -> String {
        guard s.hasPrefix("data:"), let commaIdx = s.firstIndex(of: ",") else { return s }
        return String(s[s.index(after: commaIdx)...])
    }
}
