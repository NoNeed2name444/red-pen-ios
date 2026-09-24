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

    /// Everything on this category's page besides its list of sets, in the
    /// order the groups are shown.
    var features: [CategoryFeature] {
        FeatureGroup.allCases.flatMap { features(in: $0) }
    }

    /// The tiles under one small heading.
    func features(in group: FeatureGroup) -> [CategoryFeature] {
        switch group {
        case .modes: return modeTiles
        case .practise: return practiseTiles
        case .tools: return toolTiles
        }
    }

    /// One tile for every kind of set that lives here - the modes the dock
    /// used to have a tab each for, so each is still one tap away.
    private var modeTiles: [CategoryFeature] {
        switch self {
        case .questions: return [.multipleChoice]
        case .cards: return [.flashcards, .textbooks, .pictures]
        case .cases: return [.qaCases]
        case .osce: return [.stations]
        case .audio: return [.lectures]
        }
    }

    /// The ways to practise what is in the sets.
    private var practiseTiles: [CategoryFeature] {
        switch self {
        case .questions:
            return [.mixed, .mistakes, .flagged, .timed, .weakest, .confident, .slow, .one]
        case .cards: return [.due, .draw]
        case .cases: return [.clues, .duels, .scripts]
        case .osce: return [.patient]
        case .audio: return [.commute, .explain]
        }
    }

    /// Everything else: making, bringing in and changing sets, and the pages
    /// about how the studying is going.
    private var toolTiles: [CategoryFeature] {
        switch self {
        case .questions: return [.rules, .coverage, .subjects, .add, .turn]
        case .cards: return [.add, .turn]
        case .cases: return [.reasoning, .add, .turn]
        case .osce: return [.add, .turn]
        case .audio: return [.record, .add, .turn]
        }
    }
}

/// The three small headings a category's tiles sit under.
enum FeatureGroup: String, CaseIterable, Identifiable {
    case modes, practise, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modes: return "Modes"
        case .practise: return "Practise"
        case .tools: return "Tools"
        }
    }
}

// MARK: - What each category can do

/// One thing a category can do besides opening a set: one mode's sets, a quiz
/// built on the spot, a page of its own, or New set with the right kind
/// already chosen.
enum CategoryFeature: String, CaseIterable, Identifiable, Hashable {
    // The modes: one per kind of set (and the picture cards among the decks)
    case multipleChoice, flashcards, textbooks, pictures, qaCases, stations, lectures
    // Questions
    case mixed, mistakes, flagged, timed, weakest, confident, slow, one, rules, coverage, subjects
    // Cards
    case due, draw
    // Cases
    case clues, duels, scripts, reasoning
    // OSCE
    case patient
    // Audio
    case commute, explain, record
    // Every category
    case add, turn

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
        /// Lists this kind's sets - or, with none yet, opens New set on it.
        case shelf(StudySetKind)
        /// Pushes one of the gear menu's pages.
        case support(SupportPage)
        /// New set on the category's kind, at the step that asks where the
        /// material comes from: typing, a lecture, or a saved set.
        case addMaterial
    }

    var action: Action {
        switch self {
        case .multipleChoice: return .shelf(.mcq)
        case .flashcards, .pictures: return .shelf(.anki)
        case .textbooks: return .shelf(.book)
        case .qaCases: return .shelf(.qa)
        case .stations: return .shelf(.osce)
        case .lectures: return .shelf(.narrate)
        case .mixed, .mistakes, .flagged, .timed, .weakest, .confident, .slow, .one: return .quiz
        case .due: return .due
        case .record: return .newSet(.narrate)
        case .subjects: return .support(.progress)
        case .add: return .addMaterial
        case .rules, .coverage, .draw, .clues, .duels, .scripts, .reasoning,
             .patient, .commute, .explain, .turn: return .page
        }
    }

    /// The kind of set a mode tile lists; nil for every other tile.
    var shelfKind: StudySetKind? {
        if case .shelf(let kind) = action { return kind }
        return nil
    }

    var title: String {
        switch self {
        case .multipleChoice: return "Multiple choice"
        case .flashcards: return "Flashcards"
        case .textbooks: return "Textbooks"
        case .pictures: return "Picture cards"
        case .qaCases: return "Q&A cases"
        case .stations: return "OSCE stations"
        case .lectures: return "Narrated lectures"
        case .mixed: return "Mixed quiz"
        case .mistakes: return "My mistakes"
        case .flagged: return "Flagged"
        case .timed: return "Timed exam"
        case .weakest: return "Weakest topic"
        case .confident: return "Sure but wrong"
        case .slow: return "Slow reading"
        case .one: return "Just one"
        case .rules: return "Rule sheet"
        case .coverage: return "Syllabus check"
        case .subjects: return "By subject"
        case .due: return "Due cards"
        case .draw: return "Draw from memory"
        case .clues: return "Clue-by-clue cases"
        case .duels: return "Lookalike duels"
        case .scripts: return "Disease scripts"
        case .reasoning: return "Reasoning by set"
        case .patient: return "Talking patient"
        case .commute: return "Commute mode"
        case .explain: return "Explain it back"
        case .record: return "Record a lecture"
        case .add: return "Paste or import"
        case .turn: return "Turn into\u{2026}"
        }
    }

    var detail: String {
        switch self {
        case .multipleChoice: return "Exam-style questions"
        case .flashcards: return "Cards that come back in time"
        case .textbooks: return "Your lecture as pages"
        case .pictures: return "Hide labels on a diagram"
        case .qaCases: return "Patient cases to talk through"
        case .stations: return "Step-by-step checklists"
        case .lectures: return "Read along with the lecture"
        case .mixed: return "20 from every set"
        case .mistakes: return "Last got wrong"
        case .flagged: return "The ones you flagged"
        case .timed: return "10 against the clock"
        case .weakest: return "Your lowest subject"
        case .confident: return "Fix the misconceptions"
        case .slow: return "Key words marked, 15 s each"
        case .one: return "A single question"
        case .rules: return "One rule per mistake"
        case .coverage: return "What you haven't studied"
        case .subjects: return "Your score in each subject"
        case .due: return "Cards waiting today"
        case .draw: return "Sketch, then compare"
        case .clues: return "Commit as early as you dare"
        case .duels: return "Tell two lookalikes apart"
        case .scripts: return "A whole disease on one screen"
        case .reasoning: return "All three tools for one set"
        case .patient: return "Talk, then get marked"
        case .commute: return "Listen and answer aloud"
        case .explain: return "Say it, get it marked"
        case .record: return "Write out what was said"
        case .add: return "Type it in, or open a saved set"
        case .turn: return "Make a set another mode"
        }
    }

    var symbol: String {
        switch self {
        case .multipleChoice: return StudySetKind.mcq.symbol
        case .flashcards: return StudySetKind.anki.symbol
        case .textbooks: return StudySetKind.book.symbol
        case .pictures: return "photo.on.rectangle.angled"
        case .qaCases: return StudySetKind.qa.symbol
        case .stations: return StudySetKind.osce.symbol
        case .lectures: return StudySetKind.narrate.symbol
        case .mixed: return "shuffle"
        case .mistakes: return "xmark.circle.fill"
        case .flagged: return "flag.fill"
        case .timed: return "timer"
        case .weakest: return "target"
        case .confident: return "exclamationmark.triangle.fill"
        case .slow: return "eye.fill"
        case .one: return "1.circle.fill"
        case .rules: return "list.bullet.rectangle.fill"
        case .coverage: return "checklist"
        case .subjects: return "chart.bar.xaxis"
        case .due: return "tray.full.fill"
        case .draw: return "pencil.and.scribble"
        case .clues: return "text.magnifyingglass"
        case .duels: return "arrow.left.arrow.right"
        case .scripts: return "rectangle.stack.fill"
        case .reasoning: return "brain.head.profile"
        case .patient: return "person.wave.2.fill"
        case .commute: return "car.fill"
        case .explain: return "text.bubble.fill"
        case .record: return "mic.fill"
        case .add: return "square.and.arrow.down"
        case .turn: return "arrow.triangle.2.circlepath"
        }
    }

    /// Said when a quiz has nothing to practise yet.
    var emptyText: String {
        switch self {
        case .due: return "No cards are due right now. Come back later."
        case .flagged: return "Flag a question while you answer it and it will wait here."
        case .mistakes, .confident: return "Answer a few questions first. Anything you get wrong comes back here."
        case .slow: return "When you get one wrong, tap \u{201C}Misread the question\u{201D} under it and it comes back here, to read slowly."
        default: return "Make a question set first."
        }
    }

    /// The page this feature opens, for the `.page` and `.shelf` ones.
    /// (Turn into needs the category's kinds, so the library builds it.)
    @ViewBuilder
    var page: some View {
        switch self {
        case .multipleChoice, .flashcards, .textbooks, .pictures, .qaCases, .stations, .lectures:
            KindShelfView(feature: self)
        case .clues, .duels, .scripts:
            ReasoningToolPicker(feature: self)
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

    /// A mode tile's sets, newest first: every set of its kind, or for the
    /// picture cards only the decks that hold any.
    @MainActor func shelfSets(_ store: Store) -> [StudySet] {
        guard let kind: StudySetKind = shelfKind else { return [] }
        let all: [StudySet] = store.library.filter { $0.kind == kind }
        let kept: [StudySet] = self == .pictures ? all.filter(Self.hasPictureCards) : all
        return kept.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Whether a deck holds any image occlusion card.
    static func hasPictureCards(_ set: StudySet) -> Bool {
        set.cards.contains { $0.type == .occlusion }
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
        case .slow:
            let drill: StudySet = store.reasonQuiz(.misread, named: "Slow reading drill")
            return InsightQuiz(set: drill, minReadSeconds: 15)
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
    /// Said in place of the feature's own line - a mode's count of sets.
    var detail: String? = nil

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
                Text(detail ?? feature.detail)
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
