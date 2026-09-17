import SwiftUI

/// The quiz screen — matches the web app's `renderQuestion()` /
/// `selectOption()` / `paintOptions()` / the `el.checkBtn` handler: pick an
/// option, check it (reveals correct/incorrect coloring + explanation),
/// then Next / See results. `state.answers[i]` becomes `answers[i]` here.
struct MCQQuizView: View {
    let studySet: StudySet
    @Environment(\.dismiss) private var dismiss

    @State private var current: Int = 0
    @State private var answers: [MCQAnswer]
    @State private var showSummary = false

    /// `initialAnswers` is only used by the CI screenshot launch (see
    /// PreviewLaunch) to open the quiz with an answer already checked.
    init(set studySet: StudySet, initialAnswers: [MCQAnswer]? = nil) {
        self.studySet = studySet
        var answers = Array(repeating: MCQAnswer(), count: studySet.questions.count)
        if let initialAnswers {
            for (i, a) in initialAnswers.enumerated() where i < answers.count { answers[i] = a }
        }
        _answers = State(initialValue: answers)
    }

    private var q: MCQQuestion { studySet.questions[current] }
    private var a: MCQAnswer { answers[current] }

    private var scoreSoFar: (correct: Int, checked: Int) {
        var correct = 0, checked = 0
        for (i, ans) in answers.enumerated() where ans.checked {
            checked += 1
            if ans.selected == studySet.questions[i].correctIndex { correct += 1 }
        }
        return (correct, checked)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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

                    VStack(spacing: 8) {
                        ForEach(q.options.indices, id: \.self) { idx in
                            optionRow(idx)
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
        .navigationDestination(isPresented: $showSummary) {
            MCQSummaryView(set: studySet, answers: answers)
        }
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
                Text(q.options[idx])
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
        .buttonStyle(.plain)
        .disabled(a.checked)
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
        if idx == q.correctIndex {
            return OptionState(fill: .green.opacity(0.12), border: .green, badgeBg: .green, badgeFg: .white, mark: "checkmark.circle.fill")
        }
        if idx == a.selected {
            return OptionState(fill: .red.opacity(0.10), border: .red, badgeBg: .red, badgeFg: .white, mark: "xmark.circle.fill")
        }
        return OptionState(fill: card.opacity(0.7), border: .clear, badgeBg: Color.primary.opacity(0.06), badgeFg: .secondary, mark: nil)
    }

    private var explanationBox: some View {
        let correct = a.selected == q.correctIndex
        return VStack(alignment: .leading, spacing: 8) {
            Label(correct ? "Correct" : "Not quite", systemImage: correct ? "checkmark.seal.fill" : "info.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(correct ? Color.green : Color.red)
            Text(q.explanation).font(.subheadline).lineSpacing(3)
        }
        .contentCard()
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
            return
        }
        if current < studySet.questions.count - 1 {
            current += 1
        } else {
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
