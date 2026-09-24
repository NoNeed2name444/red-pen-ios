import SwiftUI

/// Practice: every way to study, on one page.
///
/// At the top, one-tap modes - each builds a quiz from what the library
/// already holds and opens it (the same builders Analytics and the Today card
/// use). Under them, a few big cards, one per kind of practice, each opening
/// the screen that already does it.
///
/// Kept deliberately plain: a picture, a name and one line on each, so the
/// page can be read by somebody who has never opened the app before.
struct PracticeView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore

    /// A quiz started from a one-tap mode.
    @State private var quiz: InsightQuiz?
    @State private var showingDue = false
    /// What to say when a mode has nothing to practise yet.
    @State private var nothingYet: QuickMode?

    private let tileColumns: [GridItem] = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    private let cardColumns: [GridItem] = [GridItem(.adaptive(minimum: 320), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                quickSection
                categorySection
            }
            .padding(16)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(LibraryBackdrop())
        .navigationTitle("Practice")
        .navigationDestination(item: $quiz) { quiz in
            MCQQuizView(set: quiz.set, keepsProgress: false,
                        minReadSeconds: quiz.minReadSeconds, startsTimed: quiz.timed)
        }
        .navigationDestination(isPresented: $showingDue) { DueTodayView() }
        // sets opened from "Questions & cards"
        .navigationDestination(for: StudySet.self) { StudySetScreen(set: $0) }
        .alert("Nothing here yet", isPresented: nothingYetShown, presenting: nothingYet) { _ in
            Button("OK", role: .cancel) {}
        } message: { mode in
            Text(mode.emptyText)
        }
    }

    private var nothingYetShown: Binding<Bool> {
        Binding(get: { nothingYet != nil }, set: { if !$0 { nothingYet = nil } })
    }

    // MARK: one-tap modes

    private var quickSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PracticeHeading(title: "Start now", detail: "One tap and you are in.")
            LazyVGrid(columns: tileColumns, spacing: 12) {
                ForEach(QuickMode.allCases) { mode in
                    Button { start(mode) } label: { QuickModeTile(mode: mode) }
                        .buttonStyle(.pressableRow)
                        .accessibilityIdentifier("quickMode-\(mode.rawValue)")
                }
            }
        }
    }

    private func start(_ mode: QuickMode) {
        if mode == .due {
            let due: Int = reviews.dueAcross(store.library).count
            if due > 0 { showingDue = true } else { nothingYet = mode }
            return
        }
        guard let made = mode.quiz(from: store), !made.set.questions.isEmpty else {
            nothingYet = mode
            return
        }
        quiz = made
    }

    // MARK: the kinds of practice

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PracticeHeading(title: "Ways to practise", detail: "Pick one.")
            LazyVGrid(columns: cardColumns, spacing: 12) {
                ForEach(PracticeCategory.allCases) { category in
                    NavigationLink {
                        category.destination
                    } label: {
                        PracticeCategoryCard(category: category)
                    }
                    .buttonStyle(.pressableRow)
                    .accessibilityIdentifier("practiceCategory-\(category.rawValue)")
                }
            }
        }
    }
}

/// A heading over one part of the Practice page.
struct PracticeHeading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.weight(.bold))
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - One-tap modes

/// The quick-start modes: each one a quiz the Store can already build.
enum QuickMode: String, CaseIterable, Identifiable {
    case due, mixed, mistakes, flagged, timed, weakest, confident, one

    var id: String { rawValue }

    var title: String {
        switch self {
        case .due: return "Due cards"
        case .mixed: return "Mixed quiz"
        case .mistakes: return "My mistakes"
        case .flagged: return "Flagged"
        case .timed: return "Timed exam"
        case .weakest: return "Weakest topic"
        case .confident: return "Sure but wrong"
        case .one: return "Just one"
        }
    }

    var detail: String {
        switch self {
        case .due: return "Cards waiting today"
        case .mixed: return "20 from every set"
        case .mistakes: return "Last got wrong"
        case .flagged: return "The ones you flagged"
        case .timed: return "10 against the clock"
        case .weakest: return "Your lowest subject"
        case .confident: return "Fix the misconceptions"
        case .one: return "A single question"
        }
    }

    var symbol: String {
        switch self {
        case .due: return "tray.full.fill"
        case .mixed: return "shuffle"
        case .mistakes: return "xmark.circle.fill"
        case .flagged: return "flag.fill"
        case .timed: return "timer"
        case .weakest: return "target"
        case .confident: return "exclamationmark.triangle.fill"
        case .one: return "1.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .due: return StudySetKind.anki.tint
        case .mixed: return StudySetKind.narrate.tint
        case .mistakes: return StudySetKind.mcq.tint
        case .flagged: return StudySetKind.qa.tint
        case .timed: return StudySetKind.book.tint
        case .weakest: return StudySetKind.osce.tint
        case .confident: return Color.orange
        case .one: return Color.accentColor
        }
    }

    /// Said when the mode has nothing to practise.
    var emptyText: String {
        switch self {
        case .due: return "No cards are due right now. Come back later."
        case .flagged: return "Flag a question while you answer it and it will wait here."
        case .mistakes, .confident: return "Answer a few questions first. Anything you get wrong comes back here."
        case .mixed, .timed, .weakest, .one: return "Make a question set in the Library first."
        }
    }

    /// The quiz this mode opens, built now from the library; nil for Due
    /// cards, which opens its own screen.
    func quiz(from store: Store) -> InsightQuiz? {
        switch self {
        case .due:
            return nil
        case .mixed:
            let picks: [QuestionPick] = Array(store.mcqPicks { _ in true }.shuffled().prefix(20))
            return InsightQuiz(set: Store.temporaryQuiz(named: "Mixed quiz", subject: "Mixed", from: picks))
        case .mistakes:
            return InsightQuiz(set: Self.mistakesQuiz(store))
        case .flagged:
            let picks: [QuestionPick] = store.flaggedQuestions.shuffled()
            return InsightQuiz(set: Store.temporaryQuiz(named: "Flagged questions", subject: "Flagged", from: picks))
        case .timed:
            return InsightQuiz(set: store.timedDrill(), timed: true)
        case .weakest:
            return Self.weakestQuiz(store)
        case .confident:
            return InsightQuiz(set: store.confidentMistakesQuiz())
        case .one:
            let picks: [QuestionPick] = Array(store.mcqPicks { _ in true }.shuffled().prefix(1))
            return InsightQuiz(set: Store.temporaryQuiz(named: "One question", subject: "One question", from: picks))
        }
    }

    /// The questions whose most recent answer was wrong, up to twenty.
    private static func mistakesQuiz(_ store: Store) -> StudySet {
        let history: [UUID: [Bool]] = store.answerHistory
        let wrong: [QuestionPick] = store.mcqPicks { pick in history[pick.question.id]?.last == false }
        let picks: [QuestionPick] = Array(wrong.shuffled().prefix(20))
        return Store.temporaryQuiz(named: "My mistakes", subject: "Mistakes", from: picks)
    }

    /// A drill in the weakest subject that has been answered at all.
    private static func weakestQuiz(_ store: Store) -> InsightQuiz? {
        let stats: [SubjectStats] = store.subjectStats()
        let answered: SubjectStats? = stats.first { $0.answered > 0 }
        guard let weakest = answered ?? stats.first else { return nil }
        return InsightQuiz(set: store.drill(subject: weakest.subject))
    }
}

/// One small square on the "Start now" grid.
struct QuickModeTile: View {
    let mode: QuickMode

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: mode.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(mode.tint)
                .frame(height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .glassEffect(.regular.tint(mode.tint.opacity(0.14)), in: shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The kinds of practice

/// The big cards: every kind of practice the app has, each opening the
/// screen that already does it.
enum PracticeCategory: String, CaseIterable, Identifiable {
    case sets, reasoning, voice, draw, rules, coverage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sets: return "Questions & cards"
        case .reasoning: return "Clinical reasoning"
        case .voice: return "Voice"
        case .draw: return "Draw from memory"
        case .rules: return "Learn from mistakes"
        case .coverage: return "Syllabus coverage"
        }
    }

    var detail: String {
        switch self {
        case .sets: return "Quizzes, flashcards, OSCE checklists and books"
        case .reasoning: return "Clue-by-clue cases and lookalike duels"
        case .voice: return "Commute mode, explain it back, a talking OSCE patient"
        case .draw: return "Sketch a figure, then compare"
        case .rules: return "One rule for every mistake, by subject"
        case .coverage: return "What your exam asks that you haven't studied"
        }
    }

    var symbol: String {
        switch self {
        case .sets: return "rectangle.stack.fill"
        case .reasoning: return "brain.head.profile"
        case .voice: return "waveform"
        case .draw: return "pencil.and.scribble"
        case .rules: return "list.bullet.rectangle.fill"
        case .coverage: return "checklist"
        }
    }

    var tint: Color {
        switch self {
        case .sets: return StudySetKind.mcq.tint
        case .reasoning: return StudySetKind.osce.tint
        case .voice: return StudySetKind.narrate.tint
        case .draw: return StudySetKind.qa.tint
        case .rules: return StudySetKind.anki.tint
        case .coverage: return StudySetKind.book.tint
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .sets: PracticeSetsView()
        case .reasoning: ReasoningView()
        case .voice: VoicePracticeView()
        case .draw: DrawPracticeView()
        case .rules: RuleSheetView()
        case .coverage: CoverageView()
        }
    }
}

/// One big card on the Practice page.
struct PracticeCategoryCard: View {
    let category: PracticeCategory

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let badge = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(spacing: 16) {
            Image(systemName: category.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: 56, height: 56)
                .background(category.tint.gradient, in: badge)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text(category.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(category.tint.opacity(0.28), lineWidth: 1))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}
