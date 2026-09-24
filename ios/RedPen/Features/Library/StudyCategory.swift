import SwiftUI

/// The five kinds of studying, and the only choice on the first screen.
///
/// The app used to open on six modes, a Practice page of eight quick modes and
/// six more cards, and a tab bar besides: every way in, all at once. Now the
/// floating dock at the bottom of the library holds five big words -
/// Questions, Cards, Cases, OSCE, Audio - and choosing one shows that one's
/// sets and, under them, everything that can be done with them.
enum StudyCategory: String, CaseIterable, Identifiable, Hashable {
    case questions, cards, cases, osce, audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .questions: return "Questions"
        case .cards: return "Cards"
        case .cases: return "Cases"
        case .osce: return "OSCE"
        case .audio: return "Audio"
        }
    }

    var symbol: String {
        switch self {
        case .questions: return "checklist.checked"
        case .cards: return "rectangle.on.rectangle.angled"
        case .cases: return "stethoscope"
        case .osce: return "list.clipboard"
        case .audio: return "waveform"
        }
    }

    /// The kinds of set that live here, the main one first.
    var kinds: [StudySetKind] {
        switch self {
        case .questions: return [.mcq]
        case .cards: return [.anki, .book]
        case .cases: return [.qa]
        case .osce: return [.osce]
        case .audio: return [.narrate]
        }
    }

    /// The kind "+ New set" starts on from here.
    var mainKind: StudySetKind { kinds.first ?? .mcq }

    var tint: Color { mainKind.tint }

    /// Where a set of this kind lives.
    init(kind: StudySetKind) {
        switch kind {
        case .mcq: self = .questions
        case .anki, .book: self = .cards
        case .qa: self = .cases
        case .osce: self = .osce
        case .narrate: self = .audio
        }
    }

    /// The heading over this category's sets.
    var setsHeading: String {
        switch self {
        case .questions: return "Your question sets"
        case .cards: return "Your decks and books"
        case .cases: return "Your cases"
        case .osce: return "Your OSCE stations"
        case .audio: return "Your lectures"
        }
    }

    /// Said where the sets would be, when there are none yet.
    var emptySets: String {
        switch self {
        case .questions: return "No question sets yet."
        case .cards: return "No flashcards or books yet."
        case .cases: return "No cases yet."
        case .osce: return "No OSCE stations yet."
        case .audio: return "No lectures yet."
        }
    }

    /// Everything this category can do besides opening a set.
    var features: [CategoryFeature] {
        switch self {
        case .questions:
            return [.mixed, .mistakes, .flagged, .timed, .weakest, .confident, .one, .rules, .coverage]
        case .cards: return [.due, .pictures, .draw]
        case .cases: return [.reasoning]
        case .osce: return [.patient]
        case .audio: return [.commute, .explain, .record]
        }
    }
}

// MARK: - What each category can do

/// One thing a category can do besides opening a set: a quiz built on the
/// spot, a page of its own, or New set with the right kind already chosen.
enum CategoryFeature: String, CaseIterable, Identifiable, Hashable {
    // Questions
    case mixed, mistakes, flagged, timed, weakest, confident, one, rules, coverage
    // Cards
    case due, pictures, draw
    // Cases
    case reasoning
    // OSCE
    case patient
    // Audio
    case commute, explain, record

    var id: String { rawValue }

    /// What a tap does.
    enum Action {
        /// Builds a quiz from the library and opens it.
        case quiz
        /// Opens the cards due today.
        case due
        /// Pushes `page`.
        case page
        /// Opens New set on this kind.
        case newSet(StudySetKind)
    }

    var action: Action {
        switch self {
        case .mixed, .mistakes, .flagged, .timed, .weakest, .confident, .one: return .quiz
        case .due: return .due
        case .pictures: return .newSet(.anki)
        case .record: return .newSet(.narrate)
        case .rules, .coverage, .draw, .reasoning, .patient, .commute, .explain: return .page
        }
    }

    var title: String {
        switch self {
        case .mixed: return "Mixed quiz"
        case .mistakes: return "My mistakes"
        case .flagged: return "Flagged"
        case .timed: return "Timed exam"
        case .weakest: return "Weakest topic"
        case .confident: return "Sure but wrong"
        case .one: return "Just one"
        case .rules: return "Rule sheet"
        case .coverage: return "Syllabus check"
        case .due: return "Due cards"
        case .pictures: return "Picture cards"
        case .draw: return "Draw from memory"
        case .reasoning: return "Clue cases & duels"
        case .patient: return "Talking patient"
        case .commute: return "Commute mode"
        case .explain: return "Explain it back"
        case .record: return "Record a lecture"
        }
    }

    var detail: String {
        switch self {
        case .mixed: return "20 from every set"
        case .mistakes: return "Last got wrong"
        case .flagged: return "The ones you flagged"
        case .timed: return "10 against the clock"
        case .weakest: return "Your lowest subject"
        case .confident: return "Fix the misconceptions"
        case .one: return "A single question"
        case .rules: return "One rule per mistake"
        case .coverage: return "What you haven't studied"
        case .due: return "Cards waiting today"
        case .pictures: return "Hide labels on a diagram"
        case .draw: return "Sketch, then compare"
        case .reasoning: return "One clue at a time"
        case .patient: return "Talk, then get marked"
        case .commute: return "Listen and answer aloud"
        case .explain: return "Say it, get it marked"
        case .record: return "Write out what was said"
        }
    }

    var symbol: String {
        switch self {
        case .mixed: return "shuffle"
        case .mistakes: return "xmark.circle.fill"
        case .flagged: return "flag.fill"
        case .timed: return "timer"
        case .weakest: return "target"
        case .confident: return "exclamationmark.triangle.fill"
        case .one: return "1.circle.fill"
        case .rules: return "list.bullet.rectangle.fill"
        case .coverage: return "checklist"
        case .due: return "tray.full.fill"
        case .pictures: return "photo.on.rectangle.angled"
        case .draw: return "pencil.and.scribble"
        case .reasoning: return "brain.head.profile"
        case .patient: return "person.wave.2.fill"
        case .commute: return "car.fill"
        case .explain: return "text.bubble.fill"
        case .record: return "mic.fill"
        }
    }

    /// Said when a quiz has nothing to practise yet.
    var emptyText: String {
        switch self {
        case .due: return "No cards are due right now. Come back later."
        case .flagged: return "Flag a question while you answer it and it will wait here."
        case .mistakes, .confident: return "Answer a few questions first. Anything you get wrong comes back here."
        default: return "Make a question set first."
        }
    }

    /// The page this feature opens, for the `.page` ones.
    @ViewBuilder
    var page: some View {
        switch self {
        case .rules: RuleSheetView()
        case .coverage: CoverageView()
        case .draw: DrawPracticeView()
        case .reasoning: ReasoningView()
        case .patient: SpokenPatientsView()
        case .commute: CommuteModeView()
        case .explain: ExplainBackView()
        default: EmptyView()
        }
    }

    /// The quiz this feature opens, built now from the library; nil for the
    /// ones that are not quizzes, or when there is nothing to build one from.
    @MainActor func quiz(from store: Store) -> InsightQuiz? {
        switch self {
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
        default:
            return nil
        }
    }

    /// The questions whose most recent answer was wrong, up to twenty.
    @MainActor private static func mistakesQuiz(_ store: Store) -> StudySet {
        let history: [UUID: [Bool]] = store.answerHistory
        let wrong: [QuestionPick] = store.mcqPicks { pick in history[pick.question.id]?.last == false }
        let picks: [QuestionPick] = Array(wrong.shuffled().prefix(20))
        return Store.temporaryQuiz(named: "My mistakes", subject: "Mistakes", from: picks)
    }

    /// A drill in the weakest subject that has been answered at all.
    @MainActor private static func weakestQuiz(_ store: Store) -> InsightQuiz? {
        let stats: [SubjectStats] = store.subjectStats()
        let answered: SubjectStats? = stats.first { $0.answered > 0 }
        guard let weakest = answered ?? stats.first else { return nil }
        return InsightQuiz(set: store.drill(subject: weakest.subject))
    }
}

// MARK: - The pieces on screen

/// One feature, as a big tile: a coloured symbol, a name, one line.
struct FeatureTile: View {
    let feature: CategoryFeature
    let tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: feature.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(feature.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .glassEffect(.regular.tint(tint.opacity(0.14)), in: shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

/// A heading over one part of a category's page.
struct CategoryHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The floating dock: the five categories, each a symbol over its name, in
/// one glass capsule.
///
/// Five equal slots across the width, so each is as wide as a phone allows:
/// on a 375-point iPhone the pane is 351 points, which leaves about 67 for
/// each - room for "Questions" at caption size, which shrinks a touch rather
/// than truncating at the largest text sizes. The chosen one takes the accent
/// and a lifted capsule that travels between them.
struct CategoryDock: View {
    @Binding var selection: StudyCategory
    /// How many sets sit in each category.
    var count: (StudyCategory) -> Int

    @Namespace private var lift

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(StudyCategory.allCases) { category in
                    item(category)
                }
            }
            .padding(5)
        }
        .liquidGlassPanel(cornerRadius: 28)
        .frame(maxWidth: 560)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func item(_ category: StudyCategory) -> some View {
        let chosen: Bool = category == selection
        let ink: AnyShapeStyle = chosen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)
        return Button {
            withAnimation(.snappy(duration: 0.3)) { selection = category }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: category.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(height: 24)
                Text(category.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.vertical, 2)
            .background {
                // One capsule that moves between the categories rather than
                // one per category shown and hidden: it travels with the
                // choice instead of blinking out here and in again there.
                if chosen {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.12))
                        .matchedGeometryEffect(id: "chosen", in: lift)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken(category))
        .accessibilityHint("Shows these sets and ways to practise")
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
        .accessibilityIdentifier("dockCategory-\(category.rawValue)")
    }

    private func spoken(_ category: StudyCategory) -> String {
        let n: Int = count(category)
        let plural: String = n == 1 ? "" : "s"
        return "\(category.title), \(n) set\(plural)"
    }
}
