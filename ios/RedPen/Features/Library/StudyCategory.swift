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
            return [.mixed, .mistakes, .flagged, .timed, .mock, .twins, .symptomBlocks, .weakest, .confident, .slow,
                    .one, .bedtime]
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
        case .questions: return [.lens, .examPlan, .examKit, .rules, .coverage, .subjects, .add, .turn]
        case .cards: return [.lens, .add, .turn]
        case .cases: return [.lens, .reasoning, .add, .turn]
        case .osce: return [.lens, .add, .turn]
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
    case mixed, mistakes, flagged, timed, weakest, confident, slow, one, rules, coverage, subjects, mock, twins
    // Questions: the learning screens LearnRouter shows in a sheet of its own
    case symptomBlocks, examPlan, examKit, bedtime
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
    // Questions, Cards, Cases, OSCE: the camera that answers questions
    case lens

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
        /// A new lecture, opened on its audio file picker.
        case audioLecture
        /// One of the learning screens, in LearnRouter's sheet.
        case learn(LearnRoute)
    }

    var action: Action {
        switch self {
        case .multipleChoice: return .shelf(.mcq)
        case .flashcards, .pictures: return .shelf(.anki)
        case .textbooks: return .shelf(.book)
        case .qaCases: return .shelf(.qa)
        case .stations: return .shelf(.osce)
        case .lectures: return .shelf(.narrate)
        case .mixed, .mistakes, .flagged, .timed, .weakest, .confident, .slow, .one, .twins: return .quiz
        case .due: return .due
        case .record: return .audioLecture
        case .subjects: return .support(.progress)
        case .add: return .addMaterial
        case .symptomBlocks: return .learn(.symptomBlocks)
        case .examPlan: return .learn(.examPlan)
        case .examKit: return .learn(.examKit)
        case .bedtime: return .learn(.bedtime)
        case .rules, .coverage, .draw, .clues, .duels, .scripts, .reasoning,
             .patient, .commute, .explain, .turn, .mock, .lens: return .page
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
        case .mock: return "Mock paper"
        case .twins: return "Twins"
        case .symptomBlocks: return "Symptom blocks"
        case .examPlan: return "Exam plan"
        case .examKit: return "Exam-day kit"
        case .bedtime: return "Bedtime re-read"
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
        case .record: return "Add an audio file"
        case .add: return "Paste or import"
        case .turn: return "Turn into\u{2026}"
        case .lens: return "Study Lens"
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
        case .mock: return "Your exam\u{2019}s real paper"
        case .twins: return "Missed points, new patients"
        case .symptomBlocks: return "One complaint, every cause, mixed"
        case .examPlan: return "Forecast, due days, locked in"
        case .examKit: return "What to bring and do on the day"
        case .bedtime: return "Today\u{2019}s misses, calmly, before sleep"
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
        case .record: return "A lecture recording, written out and read along"
        case .add: return "Type, paste, or open Anki, Quizlet or CSV"
        case .turn: return "Make a set another mode"
        case .lens: return "Point the camera at questions to answer and keep them"
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
        case .mock: return "doc.text.fill"
        case .twins: return "square.on.square"
        case .symptomBlocks: return "stethoscope"
        case .examPlan: return "calendar"
        case .examKit: return "checklist"
        case .bedtime: return "moon.zzz.fill"
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
        case .record: return "waveform.badge.plus"
        case .add: return "square.and.arrow.down"
        case .turn: return "arrow.triangle.2.circlepath"
        case .lens: return "camera.viewfinder"
        }
    }

    /// Said when a quiz has nothing to practise yet.
    var emptyText: String {
        switch self {
        case .due: return "No cards are due right now. Come back later."
        case .flagged: return "Flag a question while you answer it and it will wait here."
        case .mistakes, .confident: return "Answer a few questions first. Anything you get wrong comes back here."
        case .twins: return "When you miss a question, tap \u{201C}Write a twin\u{201D} under it. The twin - the same point in a different patient - waits here for a day or two."
        case .bedtime: return "Nothing missed today. Anything you get wrong comes back here tonight, to re-read before sleep."
        case .symptomBlocks: return "Make a question set first. Blocks gather questions that start from the same complaint."
        case .examPlan, .examKit: return "Set your exam date in Settings \u{2192} Your exam, and the plan fills in."
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
        case .mock: MockPaperView()
        case .lens: StudyLensView()
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
        case .twins:
            return InsightQuiz(set: store.twinsQuiz())
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
        .accessibleGlass(.regular.tint(tint.opacity(0.14)), in: shape, wash: tint.opacity(0.14))
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

/// Ideas: the idea dump, its board and the 3D map - a place of its own in
/// the dock, beside the five categories rather than one of them. It holds no
/// sets, so it is not a StudyCategory; the library shows IdeasView in its
/// place when it is chosen.
enum IdeasPlace {
    static let title: String = "Ideas"
    static let symbol: String = "lightbulb"
    static let chosenSymbol: String = "lightbulb.fill"
    /// Golden, so the page and the dock say "somewhere else" at a glance.
    static let tint: Color = Color(red: 0.86, green: 0.64, blue: 0.10)
    /// Where Ideas sits along the dock: after the five categories.
    static var order: Int { StudyCategory.allCases.count }
}

/// The floating dock: the five categories, each a symbol over its name, in
/// one glass panel, and Ideas in a glass pill of its own beside it.
///
/// On a phone (and a narrow iPad window) it runs along the bottom, under the
/// thumb: five equal slots in the panel - on a 375-point iPhone about 52
/// points each, room for "Questions" at caption2 size, which shrinks a touch
/// rather than truncating at the largest text sizes - and the 64-point Ideas
/// pill. On a wide iPad it stands on end as a rail on the leading edge, under
/// the left hand, with Ideas last after a divider.
///
/// The chosen one takes its own colour and a lifted capsule that travels
/// between them. The panel stands out of the glass as ONE unit: the items and
/// the capsule inside it never move on their own.
///
/// At the accessibility text sizes six names cannot share one strip without
/// shrinking past reading, so the dock folds into one wide glass button that
/// names where you are, and opens a list of every place as a sheet - the same
/// identifiers on its rows, so everything that finds a dock item still does.
struct CategoryDock: View {
    @Binding var selection: StudyCategory
    /// Whether Ideas, rather than a category, is the page on show.
    @Binding var inIdeas: Bool
    /// Along the bottom, or on end as the wide iPad's rail.
    var axis: Axis = .horizontal
    /// How many sets sit in each category.
    var count: (StudyCategory) -> Int

    @Namespace private var lift
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The list of places, open at the accessibility text sizes.
    @State private var listing = false

    init(selection: Binding<StudyCategory>, inIdeas: Binding<Bool>, axis: Axis = .horizontal,
         count: @escaping (StudyCategory) -> Int) {
        self._selection = selection
        self._inIdeas = inIdeas
        self.axis = axis
        self.count = count
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            listButton
        } else if axis == .vertical {
            rail
        } else {
            bar
        }
    }

    /// A category change: the lifted capsule travels, unless Reduce Motion.
    private var change: Animation? { reduceMotion ? nil : .snappy(duration: 0.3) }

    // MARK: at the accessibility text sizes

    /// One wide glass button: where you are, and a tap for every place.
    private var listButton: some View {
        let shape: RoundedRectangle = panelShape
        let here: String = inIdeas ? IdeasPlace.title : selection.title
        let symbol: String = inIdeas ? IdeasPlace.chosenSymbol : selection.symbol
        let ink: Color = inIdeas ? IdeasPlace.tint : selection.tint
        return Button { listing = true } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ink)
                    .accessibilityHidden(true)
                Text(here)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sections, now \(here)")
        .accessibilityHint("Lists every section to choose from")
        .accessibilityIdentifier("dockList")
        .accessibleGlass(.regular.interactive(), in: shape)
        .popOut(.floating, in: shape)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .sheet(isPresented: $listing) {
            DockListSheet(selection: $selection, inIdeas: $inIdeas, count: count)
        }
    }

    // MARK: along the bottom

    private var bar: some View {
        HStack(spacing: 8) {
            categoriesPanel
            ideasPill
        }
        // the pill as tall as the panel, whatever the text size
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 560)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var categoriesPanel: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(StudyCategory.allCases) { category in
                    item(category)
                }
            }
            .padding(5)
        }
        .liquidGlassPanel(cornerRadius: 28)
        .popOut(.floating, in: panelShape)
    }

    /// Ideas, in a glass pill of its own beside the panel.
    private var ideasPill: some View {
        let chosen: Bool = inIdeas
        let shape: RoundedRectangle = panelShape
        let wash: Color = chosen ? IdeasPlace.tint.opacity(0.22) : Color.clear
        return Button(action: chooseIdeas) {
            ideasFace(chosen: chosen)
                .frame(width: 64)
                .frame(minHeight: 56, maxHeight: .infinity)
                .contentShape(shape)
                .contentShape(.hoverEffect, shape)
                .hoverEffect(.highlight)
        }
        .buttonStyle(.plain)
        // on the button itself, before the interactive glass and the
        // pop-out wrap it, so UI tests find (and can tap) the button
        .accessibilityLabel(IdeasPlace.title)
        .accessibilityHint("Your idea dump, board and 3D map")
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
        .accessibilityIdentifier("dockCategory-ideas")
        .accessibleGlass(.regular.tint(wash).interactive(), in: shape, wash: wash)
        .popOut(.floating, in: shape)
        .keyboardShortcut(CategoryDock.digit(IdeasPlace.order + 1), modifiers: .command)
    }

    // MARK: on end, the wide iPad's rail

    private var rail: some View {
        GlassEffectContainer(spacing: 4) {
            VStack(spacing: 2) {
                ForEach(StudyCategory.allCases) { category in
                    item(category)
                }
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                ideasRailItem
            }
            .padding(5)
        }
        .frame(width: 76)
        .liquidGlassPanel(cornerRadius: 28)
        .popOut(.floating, in: panelShape)
        .padding(.leading, 12)
        .frame(maxHeight: .infinity)
    }

    /// Ideas in the rail: an item like the others, after the divider.
    private var ideasRailItem: some View {
        let chosen: Bool = inIdeas
        return Button(action: chooseIdeas) {
            ideasFace(chosen: chosen)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.vertical, 2)
                .background {
                    if chosen {
                        Capsule()
                            .fill(IdeasPlace.tint.opacity(0.14))
                            .matchedGeometryEffect(id: "chosen", in: lift)
                    }
                }
                .contentShape(Capsule())
                .contentShape(.hoverEffect, Capsule())
                .hoverEffect(.highlight)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(CategoryDock.digit(IdeasPlace.order + 1), modifiers: .command)
        .accessibilityLabel(IdeasPlace.title)
        .accessibilityHint("Your idea dump, board and 3D map")
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
        .accessibilityIdentifier("dockCategory-ideas")
    }

    // MARK: the pieces

    private func chooseIdeas() {
        withAnimation(change) { inIdeas = true }
    }

    /// The lightbulb over the word Ideas, golden when chosen.
    private func ideasFace(chosen: Bool) -> some View {
        let symbol: String = chosen ? IdeasPlace.chosenSymbol : IdeasPlace.symbol
        let ink: Color = chosen ? IdeasPlace.tint : Color.secondary
        let glow: Color? = chosen ? IdeasPlace.tint : nil
        return DockItemFace(symbol: symbol, title: IdeasPlace.title, ink: ink, glow: glow)
    }

    private func item(_ category: StudyCategory) -> some View {
        let chosen: Bool = !inIdeas && category == selection
        let ink: Color = chosen ? category.tint : Color.secondary
        let wash: Color = category.tint.opacity(0.14)
        let number: Int = (StudyCategory.allCases.firstIndex(of: category) ?? 0) + 1
        return Button {
            withAnimation(change) { selection = category }
        } label: {
            DockItemFace(symbol: category.symbol, title: category.title, ink: ink,
                         glow: chosen ? category.tint : nil)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.vertical, 2)
                .background {
                    // One capsule that moves between the categories rather
                    // than one per category shown and hidden: it travels with
                    // the choice instead of blinking out here and in again
                    // there.
                    if chosen {
                        Capsule()
                            .fill(wash)
                            .matchedGeometryEffect(id: "chosen", in: lift)
                    }
                }
                .contentShape(Capsule())
                .contentShape(.hoverEffect, Capsule())
                .hoverEffect(.highlight)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(CategoryDock.digit(number), modifiers: .command)
        .accessibilityLabel(spoken(category))
        .accessibilityHint("Shows these sets and ways to practise")
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
        .accessibilityIdentifier("dockCategory-\(category.rawValue)")
    }

    /// Command 1 to 5 for the categories, Command 6 for Ideas.
    private static func digit(_ number: Int) -> KeyEquivalent {
        let text: String = String(number)
        let character: Character = text.first ?? "1"
        return KeyEquivalent(character)
    }

    private func spoken(_ category: StudyCategory) -> String {
        "\(category.title), " + SpokenText.count(count(category), "set")
    }
}

/// The dock as a list, at the accessibility text sizes: every section and
/// Ideas, one to a row, with room for the whole name at any size.
private struct DockListSheet: View {
    @Binding var selection: StudyCategory
    @Binding var inIdeas: Bool
    var count: (StudyCategory) -> Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(StudyCategory.allCases) { category in
                    let chosen: Bool = !inIdeas && category == selection
                    let detail: String = SpokenText.count(count(category), "set")
                    row(title: category.title, detail: detail, symbol: category.symbol,
                        tint: category.tint, chosen: chosen, id: "dockCategory-\(category.rawValue)") {
                        selection = category
                        inIdeas = false
                    }
                }
                row(title: IdeasPlace.title, detail: "Your idea dump, board and 3D map",
                    symbol: IdeasPlace.symbol, tint: IdeasPlace.tint, chosen: inIdeas,
                    id: "dockCategory-ideas") {
                    inIdeas = true
                }
            }
            .navigationTitle("Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(title: String, detail: String, symbol: String, tint: Color, chosen: Bool,
                     id: String, choose: @escaping () -> Void) -> some View {
        Button {
            choose()
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if chosen {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
        .accessibilityIdentifier(id)
    }
}

/// One dock item's face: a symbol over its name. The chosen one's symbol
/// sits in a soft coronal glow in its own colour - a small star.
private struct DockItemFace: View {
    let symbol: String
    let title: String
    let ink: Color
    var glow: Color? = nil

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .scaledFont(19, relativeTo: .body, weight: .semibold, maxSize: 30)
                .frame(minHeight: 24)
                .background {
                    if let glow {
                        CoronaGlow(tint: glow, reach: 0.5, strength: 0.45)
                            .frame(width: 44, height: 44)
                            .transition(.opacity)
                    }
                }
            Text(title)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(ink)
    }
}
