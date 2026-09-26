import SwiftUI

/// Guess first: five quick questions the first time a textbook, lecture or
/// narrate set is opened, before any reading. Skippable, and wrong guesses
/// are the point - trying first and then seeing the answer makes the reading
/// stick better.
///
/// The questions come from the set's own text (Pretest), or from a deck's
/// own cards. Nothing is recorded in the answer history: these are guesses,
/// not a measure of anything.
struct GuessFirstView: View {
    let set: StudySet
    @Environment(\.dismiss) private var dismiss
    @State private var questions: [MCQQuestion] = []
    @State private var started = false
    @State private var index = 0
    @State private var picked: Int?
    @State private var right = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if questions.isEmpty {
                Text("Nothing to ask from this one yet.").font(.body).foregroundStyle(.secondary)
            } else if !started {
                intro
            } else if index < questions.count {
                question(questions[index])
            } else {
                finish
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity)
        .modeScreen(set.kind)
        .studyBar { bar }
        .navigationTitle("Guess first")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            LearnMarks.markPretestSeen(set.id)
            if questions.isEmpty { questions = GuessFirst.questions(for: set) }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Take a guess").font(.largeTitle.weight(.bold))
            Text("\(questions.count) quick questions on \(set.name), before you read it. It\u{2019}s fine to be wrong.")
                .font(.body)
            Text(Pretest.why)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func question(_ q: MCQQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(index + 1) of \(questions.count)")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(q.stem).font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(q.options.enumerated()), id: \.offset) { item in
                optionButton(q, item.offset, item.element)
            }
            if picked != nil {
                Text(q.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentCard()
            }
        }
    }

    private func optionButton(_ q: MCQQuestion, _ i: Int, _ text: String) -> some View {
        let answered: Bool = picked != nil
        let isRight: Bool = i == q.correctIndex
        let isPicked: Bool = picked == i
        let symbol: String = !answered ? StudyRhythm.letter(i).lowercased() + ".circle"
            : (isRight ? "checkmark.circle.fill" : (isPicked ? "xmark.circle.fill" : "circle"))
        let tint: Color = !answered ? .secondary : (isRight ? .green : (isPicked ? .red : .secondary))
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            guard picked == nil else { return }
            picked = i
            if isRight { right += 1 }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(tint).font(.title3).accessibilityHidden(true)
                Text(text).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(.regularMaterial, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .popOut(.raised, in: shape, pressed: answered)
        .disabled(answered)
        .accessibilityLabel("\(StudyRhythm.letter(i)): \(text)")
        .accessibilityValue(SpokenText.optionState(checked: answered, isCorrect: isRight, isChosen: isPicked))
        .accessibilityAddTraits(isPicked ? [.isSelected] : [])
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(right) of \(questions.count)").font(.largeTitle.weight(.bold)).monospacedDigit()
            Text("Whatever the score, you now know what to look out for. Watch for these as you read.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var bar: some View {
        if questions.isEmpty || index >= questions.count {
            Button("Start reading") { dismiss() }.buttonStyle(.bigPrimary)
        } else if !started {
            HStack(spacing: 12) {
                Button("Skip") { dismiss() }.buttonStyle(.bigCompanion)
                Button("Guess") { started = true }.buttonStyle(.bigPrimary)
            }
        } else {
            let nextTitle: String = index + 1 < questions.count ? "Next" : "Done"
            HStack(spacing: 12) {
                Button("Skip") { dismiss() }.buttonStyle(.bigCompanion)
                Button(nextTitle) {
                    picked = nil
                    index += 1
                }
                .buttonStyle(.bigPrimary)
                .disabled(picked == nil)
            }
        }
    }
}

/// Which sets get a pretest, and its questions.
@MainActor
enum GuessFirst {
    /// Textbooks and narrate sets (a lecture read line by line): the sets
    /// that are read rather than answered.
    static func offers(_ set: StudySet) -> Bool {
        set.kind == .book || set.kind == .narrate
    }

    /// The text a set is read from.
    static func text(of set: StudySet) -> String {
        switch set.kind {
        case .book: return set.bookMarkdown
        case .narrate: return set.narrateSegments.map(\.text).joined(separator: " ")
        default:
            return set.sources.flatMap { $0.pages.map(\.text) }.joined(separator: "\n")
        }
    }

    static func questions(for set: StudySet) -> [MCQQuestion] {
        if set.kind == .anki {
            let built = QuizFromCards.build(from: set.cards).questions
            if built.count >= 3 { return Array(built.shuffled().prefix(Pretest.count)) }
        }
        // from the id's own characters, so the same set asks the same
        // questions on every launch (hashValue changes between launches)
        var seed: UInt64 = 1_469_598_103_934_665_603
        for byte in set.id.uuidString.utf8 {
            seed = (seed ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Pretest.questions(from: text(of: set), seed: seed)
    }

    /// Whether this set should get its pretest now: first opening, and
    /// enough text to ask about.
    static func isDue(_ set: StudySet) -> Bool {
        offers(set) && !LearnMarks.pretestSeen(set.id) && !questions(for: set).isEmpty
    }
}

extension View {
    /// Offers Guess first the first time `set` is opened. For the textbook
    /// reader and the narrate screen:
    /// `.guessFirst(set)` on their outermost view.
    func guessFirst(_ set: StudySet) -> some View {
        onAppear {
            guard GuessFirst.isDue(set) else { return }
            LearnRouter.shared.open(.pretest(set.id))
        }
    }
}
