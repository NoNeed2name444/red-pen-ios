import SwiftUI

/// The quiz screen — matches the web app's `renderQuestion()` /
/// `selectOption()` / `paintOptions()` / the `el.checkBtn` handler: pick an
/// option, check it (reveals correct/incorrect coloring + explanation),
/// then Next / See results. `state.answers[i]` becomes `answers[i]` here.
struct MCQQuizView: View {
    let set: StudySet
    @Environment(\.dismiss) private var dismiss

    @State private var current: Int = 0
    @State private var answers: [MCQAnswer]
    @State private var showSummary = false

    /// `initialAnswers` is only used by the CI screenshot launch (see
    /// PreviewLaunch) to open the quiz with an answer already checked.
    init(set: StudySet, initialAnswers: [MCQAnswer]? = nil) {
        self.set = set
        var answers = Array(repeating: MCQAnswer(), count: set.questions.count)
        if let initialAnswers {
            for (i, a) in initialAnswers.enumerated() where i < answers.count { answers[i] = a }
        }
        _answers = State(initialValue: answers)
    }

    private var q: MCQQuestion { set.questions[current] }
    private var a: MCQAnswer { answers[current] }

    private var scoreSoFar: (correct: Int, checked: Int) {
        var correct = 0, checked = 0
        for (i, ans) in answers.enumerated() where ans.checked {
            checked += 1
            if ans.selected == set.questions[i].correctIndex { correct += 1 }
        }
        return (correct, checked)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ProgressView(value: Double(current), total: Double(set.questions.count))
                .tint(.accentColor)
                .padding(.horizontal)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Q\(current + 1) · single best answer")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(q.stem).font(.title3.weight(.semibold))

                    if let idx = q.imageIndex, idx >= 0, idx < set.images.count,
                       let data = Data(base64Encoded: stripDataPrefix(set.images[idx])),
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage).resizable().scaledToFit().frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(spacing: 8) {
                        ForEach(q.options.indices, id: \.self) { idx in
                            optionRow(idx)
                        }
                    }

                    if a.checked {
                        explanationBox
                    }
                }
                .padding()
            }
            footer
        }
        .navigationTitle(set.subject.isEmpty ? "MCQ" : set.subject)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showSummary) {
            MCQSummaryView(set: set, answers: answers)
        }
    }

    private var header: some View {
        HStack {
            Text("Question \(current + 1) of \(set.questions.count)")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            let s = scoreSoFar
            Text("\(s.correct) / \(s.checked)")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal).padding(.top, 8)
    }

    private func optionRow(_ idx: Int) -> some View {
        Button {
            guard !a.checked else { return }
            answers[current].selected = idx
        } label: {
            HStack {
                Text(letter(idx)).font(.subheadline.monospaced().weight(.bold))
                    .frame(width: 24)
                Text(q.options[idx]).font(.subheadline)
                Spacer()
                if a.checked {
                    if idx == q.correctIndex {
                        Text("best answer").font(.caption).foregroundStyle(.green)
                    } else if idx == a.selected {
                        Text("your answer").font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .padding(10)
            .background(optionBackground(idx), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(optionBorder(idx), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(a.checked)
    }

    private func optionBackground(_ idx: Int) -> Color {
        guard a.checked else {
            return idx == a.selected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground)
        }
        if idx == q.correctIndex { return .green.opacity(0.15) }
        if idx == a.selected { return .red.opacity(0.15) }
        return Color(.secondarySystemBackground)
    }

    private func optionBorder(_ idx: Int) -> Color {
        guard a.checked else {
            return idx == a.selected ? .accentColor : .clear
        }
        if idx == q.correctIndex { return .green }
        if idx == a.selected { return .red }
        return .clear
    }

    private var explanationBox: some View {
        let correct = a.selected == q.correctIndex
        return (
            Text(correct ? "Correct — " : "Not quite — ").fontWeight(.bold)
                .foregroundStyle(correct ? Color.green : Color.red)
            + Text(q.explanation)
        )
        .font(.subheadline)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            Button("Previous") { if current > 0 { current -= 1 } }
                .disabled(current == 0)
            Spacer()
            Button(checkButtonTitle) { onCheckOrNext() }
                .buttonStyle(.borderedProminent)
                .disabled(!a.checked && a.selected == nil)
        }
        .padding()
        .background(.bar)
    }

    private var checkButtonTitle: String {
        if !a.checked { return "Check answer" }
        return current == set.questions.count - 1 ? "See results" : "Next question"
    }

    private func onCheckOrNext() {
        if !a.checked {
            answers[current].checked = true
            return
        }
        if current < set.questions.count - 1 {
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
