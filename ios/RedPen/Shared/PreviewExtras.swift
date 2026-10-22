import SwiftUI

/// Screens added after the original preview harness was written.
///
/// PreviewLaunch.swift holds the first fifteen; this holds the ones for work
/// done since. They are kept apart rather than appended because a screenshot
/// harness is the one place where adding a case must never risk disturbing the
/// screens already being compared week to week.
///
/// A screen only earns a place here if it shows something a still picture can
/// actually prove.
enum PreviewExtras {

    static let screens = ["anki-quizable", "quiz-from-cards", "narrate-fixing", "occlusion-example",
                          "quiz-folded", "quiz-scrolled", "library-end", "library-loading", "signin", "account-deleted",
                          "settings", "sheet", "mode-switch", "section-switch", "home-ideas", "mode-switch-quiz", "lens"]
                          + tourScreens

    /// Posted by the "section-switch" preview: home moves one place along
    /// its dock (LibraryView).
    static let dockStep = Notification.Name("PreviewExtras.dockStep")

    @MainActor @ViewBuilder
    static func view(for screen: String) -> some View {
        switch screen {
        case "library-end":
            // The library at the end of its list, where the last row has to clear the dock.
            LibraryView()
        case "anki-quizable":
            // the same review screen, on a deck big enough for the toolbar's
            // Quiz me button to be enabled
            NavigationStack { AnkiReviewView(set: PreviewDecks.lupus) }
        case "quiz-from-cards":
            NavigationStack { MCQQuizView(set: PreviewDecks.lupusQuiz) }
        case "quiz-folded", "quiz-scrolled":
            // The quiz with its folded button, or rows under both open-deck edges.
            NavigationStack { MCQQuizView(set: SampleData.nephrology) }
        case "narrate-fixing":
            // a real Egyptian-mix lecture line, with the fix sheet open on the
            // word the recogniser got wrong
            NavigationStack { NarrateReviewView(set: PreviewDecks.lecture, startFixing: 3) }
        case "occlusion-example":
            // the heart diagram, read and covered by the real route
            NavigationStack { OcclusionExampleView() }
        case "library-loading":
            // what a launch shows once the splash gives up waiting for a big
            // library to be read (RedPenApp, Store)
            LibraryLoadingView()
        case "signin":
            // the doors, signed out: no Google door in a build without a
            // Google client id (launch checklist GAP 2)
            PreviewSignIn(deleted: false)
        case "account-deleted":
            // after an Apple-linked account is deleted: Apple's steps for
            // removing the app from Sign in with Apple (GAP 1)
            PreviewSignIn(deleted: true)
        case "settings":
            // Settings, for the Ward design pass's light and dark pairs
            NavigationStack { SettingsPage() }
        case "sheet":
            // a sheet over home: New set, as the dock's writing modes open it
            LibraryView().sheet(isPresented: .constant(true)) { NewSetView() }
        case "lens":
            // Study Lens's answer sheet on a sample multiple-choice question,
            // answered: how its option rows are marked has never been shown
            LensSheetPreview()
        case "mode-switch":
            // home turning dark and back every 2.5 s through Always night
            // sky, the app's own switch, for a recording of the shift
            PreviewModeSwitch { LibraryView() }
        case "mode-switch-quiz":
            // the same switch on a study screen, whose bar carries buttons
            PreviewModeSwitch { NavigationStack { MCQQuizView(set: SampleData.nephrology) } }
        case "section-switch":
            // home stepping along its dock every 2 s, each place's hue
            // shifting to the next, for a recording
            PreviewSectionSwitch()
        case "home-ideas":
            // home on Ideas, in its hue
            LibraryView()
                .task {
                    try? await Task.sleep(for: .seconds(1))
                    NotificationCenter.default.post(name: PreviewExtras.dockStep, object: "ideas")
                }
        default:
            // the whole-app tour (below, and tools/tour_screens.txt)
            tourView(for: screen)
        }
    }

    static func handles(_ screen: String) -> Bool { screens.contains(screen) }
}

/// The sign-in screen on an account store of its own, signed out, with the
/// steps after an Apple account's deletion due when `deleted`.
private struct PreviewSignIn: View {
    let deleted: Bool
    @StateObject private var account = AccountStore()

    var body: some View {
        SignInView()
            .environmentObject(account)
            .task { if deleted { account.appleStepsDue = true } }
    }
}

/// A deck with enough single-answer cards for a quiz to be built from it.
///
/// The cards are deliberately all about one topic. That is the hard case and
/// the honest one: distractors drawn from the same lecture are terms you must
/// actually tell apart, which is the whole reason the quiz is built from your
/// own deck rather than invented.
enum PreviewDecks {

    static func card(_ front: String, _ answer: String, _ why: String) -> AnkiCard {
        AnkiCard(type: .qa, front: front, bullets: [answer], why: why)
    }

    static let lupus = StudySet(
        name: "Rheumatology — SLE",
        subject: "Rheumatology",
        kind: .anki,
        cards: [
            card("Which drug lowers mortality in SLE and is given to almost every patient?",
                 "Hydroxychloroquine",
                 "It lowers flares, damage accrual and mortality, so it is background therapy rather than a step on a ladder."),
            card("Which antibody is most specific for SLE?",
                 "Anti-double-stranded DNA",
                 "Specific, and its titre tracks lupus nephritis activity."),
            card("Which drug is used to induce remission in lupus nephritis?",
                 "Mycophenolate mofetil",
                 "As effective as cyclophosphamide for induction, with less gonadal toxicity."),
            card("Which blood tests fall during an active lupus flare?",
                 "Complement C3 and C4",
                 "They are consumed by immune complexes, so a fall suggests active disease."),
            card("Which skin sign of SLE spares the nasolabial folds?",
                 "The malar rash",
                 "Sparing the folds is what separates it from rosacea at the bedside."),
            card("Which antibody is associated with neonatal heart block in a pregnant patient?",
                 "Anti-Ro antibody",
                 "It crosses the placenta and can damage the fetal conducting system."),
            card("Which scarring rash of lupus can cause permanent hair loss?",
                 "Discoid lupus",
                 "It scars, so treating it early is what preserves the follicles."),
        ]
    )

    /// The quiz the app builds from that deck, exactly as the Quiz me button
    /// does - not a hand-written set of questions. If the builder ever stops
    /// producing usable questions, this screenshot goes empty and says so.
    static var lupusQuiz: StudySet {
        var set = lupus
        set.questions = QuizFromCards.build(from: lupus.cards, seed: 7).questions
        set.kind = .mcq
        return set
    }

    /// A transcript in the register these lectures are actually delivered in:
    /// Egyptian Arabic carrying English medical terms, written the way the
    /// recogniser writes them - phonetically, in Arabic letters. The fourth
    /// word of the first line is ميكو, which is where `mucocutaneous` starts and
    /// where a student would hold to fix it.
    static let lecture = StudySet(
        name: "محاضرة — SLE",
        subject: "Rheumatology",
        kind: .narrate,
        narrateSegments: [
            NarrateSegment(text: "طيب في حاجه ميكو كوتينيوس دي مهمه جدا", lang: "ar"),
            NarrateSegment(text: "الـ مالار ريش بيسيب الـ نازولابيال فولد", lang: "ar"),
            NarrateSegment(text: "وده اللي بيفرقه عن الـ روزاشيا", lang: "ar"),
            NarrateSegment(text: "والعلاج هو الـ هيدوكسيكلوكوين لكل المرضى", lang: "ar"),
            NarrateSegment(text: "والـ ميكو كوتينياس تاني في الـ كرايتيريا", lang: "ar"),
        ]
    )
}

/// Home, switching light and dark by itself (the "mode-switch" preview)
/// through the app's own path: the Always night sky setting, which turns
/// the window dark at the root (SkyRoot), so the window's bars, the search
/// field and every Ward colour take the same switch a user's would.
private struct PreviewModeSwitch<Content: View>: View {
    @ViewBuilder var content: Content
    @AppStorage(SpaceSettings.alwaysNightKey) private var night = false

    var body: some View {
        content
            .task {
                night = false
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.5))
                    night.toggle()
                }
            }
    }
}

/// Home stepping along its dock by itself (the "section-switch" preview).
private struct PreviewSectionSwitch: View {
    var body: some View {
        LibraryView()
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    NotificationCenter.default.post(name: PreviewExtras.dockStep, object: nil)
                }
            }
    }
}

// MARK: - The tour

#if !SWIFT_PACKAGE
/// The whole-app tour: one still for every screen a person can reach that a
/// still can show, in tour order (tools/tour_screens.txt, where each name
/// carries its inventory row). ios-preview shoots the list in light and dark
/// when it is passed as the `screens` input.
///
/// Every case starts from the throwaway seeded store and the example
/// seeders; anything that would outlive the launch (a mock sitting, a case
/// run) is cleared first, and settings a still needs are registered, never
/// written, so no screen leaves anything behind for the next one.
///
/// Kept out of the Playgrounds packages: they leave out several of these
/// screens.
extension PreviewExtras {

    static let tourScreens: [String] = [
        // launch, gates, account
        "link-device", "recording-terms", "exam-onboarding", "first-run-date", "first-run-goal",
        "first-run-reminders", "first-run-examples", "app-lock", "account",
        // home and the dock places
        "home-cards", "home-cases", "home-osce", "home-audio", "library-empty", "category-empty",
        "search-empty", "found-card", "custom-session", "library-select", "name-sheet", "library-delete",
        "nothing-yet", "ward-round", "ward-round-panel", "sections", "shelf", "shelf-empty",
        // new set, import, editors
        "new-material", "new-make", "new-preset", "new-writer", "generated-quiz", "import-preview",
        "import-inbox", "picture-from-photo", "cards-editor", "card-edit", "question-edit", "turn-into",
        "turn-into-list",
        // questions, mock, plan
        "quiz-timed", "lab-values", "calculator", "ward-pocket", "ward-calc", "ward-score", "accuracy-check",
        "report-error", "mock-paper", "mock-too-few", "mock-sitting", "mock-results", "symptom-blocks",
        "exam-plan", "exam-kit", "bedtime", "morning-check", "learn-question", "learn-question-gone",
        "exam-picker",
        // cards, textbook, reasoning, lens
        "anki-empty", "due-today", "due-none", "book-contents", "guess-first", "draw-practice",
        "draw-recall", "reasoning", "reasoning-set", "duels", "scripts", "duel", "duel-table", "lens-add",
        // OSCE, cases
        "spoken-patients", "station-report", "case-ward", "case-differential", "case-decision",
        "case-debrief",
        // audio
        "narrate-sections", "narrate-empty", "commute", "explain-back", "explain-result",
        // ideas
        "ideas", "ideas-board", "ideas-map", "ideas-million", "note-editor", "link-picker", "idea-name",
        // vitals
        "vitals", "insight-questions", "rules", "coverage", "stats",
        // settings, support, platform
        "ai-models", "ai-provider", "diagnostics", "lectures", "set-credits", "licences", "help", "faq",
        "examples", "generation-hud",
        // step by step (T0133): Write a twin, and a picture card revealed
        "twin-written", "occlusion-revealed",
    ]

    /// One tour screen. A plain switch over AnyView rather than a view
    /// builder: a hundred-case builder nests a hundred generic types.
    @MainActor
    static func tourView(for screen: String) -> AnyView {
        // a still starts from the device's own mode, as PreviewRoot's do
        UserDefaults.standard.set(false, forKey: SpaceSettings.alwaysNightKey)
        let quiz: StudySet = SampleData.nephrology
        let question: MCQQuestion = SampleData.nephrology.questions[0]
        let patient: CaseFile = CaseSamples.all[0]
        switch screen {
        // MARK: launch, gates, account
        case "link-device":
            return AnyView(LinkDeviceView())
        case "recording-terms":
            return AnyView(RecordingTermsView(onAccept: {}))
        case "exam-onboarding":
            // also the first page of First run, which shows the same picker
            return AnyView(ExamOnboardingView(onDone: {}))
        case "first-run-date", "first-run-goal", "first-run-reminders", "first-run-examples":
            // FirstRunView opens on the page the name ends with
            return AnyView(FirstRunView(accountId: "preview", onDone: {}))
        case "app-lock":
            // the shield over home, as reopening a locked app shows it (AppLock)
            return AnyView(LibraryView())
        case "account":
            return AnyView(NavigationStack { AccountView(embedded: true) })

        // MARK: home and the dock places
        case "home-cards":
            return AnyView(LibraryView(category: .cards))
        case "home-cases":
            return AnyView(LibraryView(category: .cases))
        case "home-osce":
            return AnyView(LibraryView(category: .osce))
        case "home-audio":
            return AnyView(LibraryView(category: .audio))
        case "library-empty":
            return AnyView(TourStore({ TourData.store([]) }) { LibraryView() })
        case "category-empty":
            return AnyView(TourStore({ TourData.store(SampleData.sets.filter { $0.kind != .osce }) }) {
                LibraryView(category: .osce)
            })
        case "search-empty":
            return AnyView(LibraryView(query: "Kawasaki"))
        case "found-card":
            return AnyView(LibraryView(foundCard: FoundCard(set: SampleData.cardiology,
                                                            card: SampleData.cardiology.cards[0])))
        case "custom-session":
            return AnyView(LibraryView(buildingSession: true))
        case "library-select":
            return AnyView(LibraryView(selecting: true, selected: [quiz.id]))
        case "name-sheet":
            return AnyView(LibraryView(naming: .folder))
        case "library-delete":
            return AnyView(LibraryView(pendingDelete: [quiz.id]))
        case "nothing-yet":
            return AnyView(LibraryView(nothingYet: .twins))
        case "ward-round":
            return AnyView(LibraryView().task { @MainActor in WardRoundClock.shared.start(.standard) })
        case "ward-round-panel":
            return AnyView(LibraryView().task { @MainActor in
                WardRoundClock.shared.start(.standard)
                try? await Task.sleep(for: .seconds(1))
                WardRoundOverlay.shared.open()
            })
        case "sections":
            // the dock's Sections list, which the accessibility text sizes use
            // (StudyCategory opens it for this name)
            return AnyView(LibraryView().environment(\.dynamicTypeSize, .accessibility2))
        case "shelf":
            return AnyView(NavigationStack { KindShelfView(feature: .multipleChoice) })
        case "shelf-empty":
            return AnyView(NavigationStack { KindShelfView(feature: .pictures) })

        // MARK: new set, import, editors
        case "new-material":
            return AnyView(NewSetView(kind: .mcq, startingAt: .material))
        case "new-make":
            // typed questions on the Make step (NewSetView fills them in)
            return AnyView(NewSetView(kind: .mcq, startingAt: .material))
        case "new-preset":
            return AnyView(NewSetView(preset: NewSetPreset(turning: quiz, into: .anki)))
        case "new-writer":
            let area: String = Syllabus.areas(for: .plab).first?.name ?? quiz.subject
            return AnyView(NewSetView(preset: NewSetPreset(blueprintArea: area, exam: ExamCatalog.plab1)))
        case "generated-quiz":
            return AnyView(NavigationStack {
                MCQQuizView(set: quiz, isUnsaved: true, saved: .constant(false), onSave: {})
            })
        case "import-preview":
            return AnyView(NewSetView(kind: .anki, startingAt: .material)
                .sheet(isPresented: .constant(true)) {
                    ImportPreviewSheet(preview: TourData.importPreview(), onImport: {})
                })
        case "import-inbox":
            return AnyView(LibraryView().sheet(isPresented: .constant(true)) {
                ImportInboxSheet(file: TourData.sharedSet())
            })
        case "picture-from-photo":
            return AnyView(NavigationStack { PictureFromPhotoView() })
        case "cards-editor":
            return AnyView(CardsEditorView(set: SampleData.cardiology))
        case "card-edit":
            return AnyView(CardEditSheet(card: SampleData.cardiology.cards[0], onSave: { _ in }))
        case "question-edit":
            return AnyView(QuestionEditSheet(question: question, onSave: { _ in }))
        case "turn-into":
            return AnyView(LibraryView(turning: quiz))
        case "turn-into-list":
            return AnyView(NavigationStack { TurnIntoListView(kinds: StudyCategory.questions.kinds) })

        // MARK: questions, mock, plan
        case "quiz-timed":
            return AnyView(NavigationStack { MCQQuizView(set: quiz, keepsProgress: false, startsTimed: true) })
        case "twin-written":
            // a miss, Write a twin tapped, and what the quiz says once the twin is written
            return AnyView(NavigationStack {
                MCQQuizView(set: quiz, initialAnswers: [MCQAnswer(selected: 2, checked: true)], keepsProgress: false,
                            twinNote: TwinDraft.madeNote(days: 2))
            })
        case "occlusion-revealed":
            // the heart example's first card after Reveal: its own label shows, every other stays grey
            return AnyView(NavigationStack { OcclusionExampleView(startRevealed: true) })
        case "lab-values":
            return AnyView(TourChecked().sheet(isPresented: .constant(true)) { LabRangesSheet() })
        case "calculator":
            return AnyView(TourChecked().sheet(isPresented: .constant(true)) { CalculatorSheet() })
        case "ward-pocket":
            return AnyView(TourChecked().sheet(isPresented: .constant(true)) { WardPocketSheet() })
        case "ward-calc":
            return AnyView(NavigationStack {
                WardCalcView(calc: .egfr, conventional: .constant(false), practice: .constant(nil))
            })
        case "ward-score":
            return AnyView(NavigationStack { WardScoreView(score: WardScores.wellsPE, practice: .constant(nil)) })
        case "accuracy-check":
            return AnyView(TourChecked().sheet(isPresented: .constant(true)) {
                AccuracyWhySheet(item: .mcq(question), checksWhenUnchecked: false)
            })
        case "report-error":
            return AnyView(TourChecked().sheet(isPresented: .constant(true)) {
                QuestionReportSheet(report: QuestionReport(set: quiz, item: .mcq(question)))
            })
        case "mock-paper":
            // ten questions: the samples and the quiz built from the lupus deck
            return AnyView(TourSetup({ MockSittingStore.clear() }) {
                TourStore({ TourData.store(SampleData.sets + [PreviewDecks.lupusQuiz]) }) {
                    NavigationStack { MockPaperView() }
                }
            })
        case "mock-too-few":
            return AnyView(TourSetup({ MockSittingStore.clear() }) { NavigationStack { MockPaperView() } })
        case "mock-sitting":
            return AnyView(TourSetup({ MockSittingStore.clear() }) { MockSittingView(sitting: TourData.sitting()) })
        case "mock-results":
            let sitting: MockSitting = TourData.sitting()
            let picks: [QuestionPick] = sitting.picks.flatMap { $0 }
            // every third one missed
            var selected: [UUID: Int] = [:]
            for (i, pick) in picks.enumerated() {
                let right: Int = pick.question.correctIndex
                selected[pick.question.id] = i % 3 == 2 ? (right + 1) % max(1, pick.question.options.count) : right
            }
            let chosen: [UUID: Int] = selected
            let marks: [MockMark] = picks.map { pick in
                MockMark(questionId: pick.question.id, subject: pick.set.subject,
                         picked: chosen[pick.question.id],
                         correct: chosen[pick.question.id] == pick.question.correctIndex, seconds: 50)
            }
            return AnyView(TourSetup({ MockSittingStore.clear() }) {
                NavigationStack {
                    MockResultsView(result: MockResult(marks: marks, passMark: 0.6), sitting: sitting,
                                    selected: chosen, minutesUsed: 9, onDone: {})
                }
            })
        case "symptom-blocks":
            return AnyView(TourLearn(route: .symptomBlocks))
        case "exam-plan":
            // with an exam and its date, so the plan and the exam card show
            return AnyView(TourSetup({ TourData.chooseExam() }) { TourLearn(route: .examPlan) })
        case "exam-kit":
            return AnyView(TourSetup({ TourData.chooseExam() }) { TourLearn(route: .examKit) })
        case "bedtime":
            return AnyView(TourLearn(route: .bedtime))
        case "morning-check":
            return AnyView(TourLearn(route: .morningCheck))
        case "learn-question":
            return AnyView(TourLearn(route: .question(question.id)))
        case "learn-question-gone":
            return AnyView(TourLearn(route: .question(UUID())))
        case "exam-picker":
            return AnyView(NavigationStack { ExamPickerView() })

        // MARK: cards, textbook, reasoning, lens
        case "anki-empty":
            var empty: StudySet = SampleData.cardiology
            empty.id = UUID()
            empty.cards = []
            return AnyView(NavigationStack { AnkiReviewView(set: empty) })
        case "due-today":
            return AnyView(NavigationStack { DueTodayView() })
        case "due-none":
            return AnyView(TourStore({ TourData.store(SampleData.sets.filter { $0.kind != .anki }) }) {
                NavigationStack { DueTodayView() }
            })
        case "book-contents":
            // BookReaderView opens its contents for this name
            return AnyView(NavigationStack { BookReaderView(set: SampleData.endocrine, page: 1) })
        case "guess-first":
            return AnyView(NavigationStack { GuessFirstView(set: SampleData.endocrine) })
        case "draw-practice":
            return AnyView(NavigationStack { DrawPracticeView() })
        case "draw-recall":
            return AnyView(DrawRecallView(figure: RecallExamples.figure))
        case "reasoning":
            return AnyView(NavigationStack { ReasoningView() })
        case "reasoning-set":
            return AnyView(NavigationStack { ReasoningSetView(set: ReasoningExamples.set) })
        case "duels":
            return AnyView(NavigationStack { DuelsView(set: ReasoningExamples.set) })
        case "scripts":
            return AnyView(NavigationStack { ScriptsView(set: ReasoningExamples.set) })
        case "duel":
            return AnyView(NavigationStack {
                DuelView(pair: ReasoningExamples.duels[0], setId: ReasoningExamples.setId)
            })
        case "duel-table":
            return AnyView(NavigationStack { ComparisonTableView(pair: ReasoningExamples.duels[0]) })
        case "lens-add":
            return AnyView(LensAddSheet(question: LensSheetPreview.question, answer: LensSheetPreview.answer))

        // MARK: OSCE, cases
        case "spoken-patients":
            return AnyView(NavigationStack { SpokenPatientsView() })
        case "station-report":
            return AnyView(NavigationStack { StationReportView(attempt: VoiceExamples.breakingBadNews) })
        case "case-ward", "case-differential":
            // a fresh patient; CaseWardView opens the differential for its name
            return AnyView(TourSetup({ CaseRunStore.shared.reset(patient) }) {
                NavigationStack { CaseWardView(file: patient, setID: SampleData.cases.id) }
            })
        case "case-decision":
            return AnyView(CaseDecisionView(file: patient, leading: patient.diagnosis.name, decide: { _ in }))
        case "case-debrief":
            return AnyView(NavigationStack {
                CaseDebriefView(file: patient, setID: SampleData.cases.id, run: TourData.finishedRun(patient),
                                again: {})
            })

        // MARK: audio
        case "narrate-sections":
            let lecture: StudySet = SampleData.narrate
            let sections: [AudioChapter] = AudioChapters.derive(lines: lecture.narrateSegments.map(\.text))
            return AnyView(NavigationStack { NarrateReviewView(set: lecture, startIndex: 3) }
                .sheet(isPresented: .constant(true)) {
                    SectionListSheet(sections: sections, current: 0, onPick: { _ in })
                })
        case "narrate-empty":
            var empty: StudySet = SampleData.narrate
            empty.id = UUID()
            empty.narrateSegments = []
            return AnyView(NavigationStack { NarrateReviewView(set: empty) })
        case "commute":
            return AnyView(NavigationStack { CommuteModeView() })
        case "explain-back":
            return AnyView(NavigationStack { ExplainBackView() })
        case "explain-result":
            return AnyView(NavigationStack { ExplainResultView(attempt: VoiceExamples.inguinalCanal) })

        // MARK: ideas, on the example notes
        case "ideas":
            return AnyView(TourNotes { _ in LibraryView(inIdeas: true) })
        case "ideas-board":
            return AnyView(TourSetup({ TourData.register(["vignette.ideas.mode": IdeasMode.board.rawValue]) }) {
                TourNotes { _ in LibraryView(inIdeas: true) }
            })
        case "ideas-map":
            return AnyView(TourSetup({ TourData.register(["vignette.ideas.mode": IdeasMode.space.rawValue]) }) {
                TourNotes { _ in LibraryView(inIdeas: true) }
            })
        case "ideas-million":
            return AnyView(TourSetup({
                TourData.register(["vignette.ideas.mode": IdeasMode.space.rawValue,
                                   GraphPerfDemo.key: GraphPerfDemo.million])
            }) {
                TourNotes { _ in LibraryView(inIdeas: true) }
            })
        case "note-editor":
            return AnyView(TourNotes { notes in
                LibraryView(inIdeas: true).sheet(isPresented: .constant(true)) {
                    NoteEditorView(noteID: TourData.hub(in: notes))
                }
            })
        case "link-picker":
            return AnyView(TourNotes { notes in
                LibraryView(inIdeas: true).sheet(isPresented: .constant(true)) {
                    LinkPickerView(noteID: TourData.hub(in: notes))
                }
            })
        case "idea-name":
            return AnyView(TourSetup({ TourData.register(["vignette.ideas.mode": IdeasMode.board.rawValue]) }) {
                TourNotes { _ in
                    LibraryView(inIdeas: true).sheet(isPresented: .constant(true)) {
                        NameSheet(title: "New idea", prompt: "The idea", initial: "", confirm: "Add", onConfirm: { _ in })
                    }
                }
            })

        // MARK: vitals (a preview build has no answer history to show)
        case "vitals":
            return AnyView(NavigationStack { AnalyticsView() })
        case "insight-questions":
            let picks: [QuestionPick] = quiz.questions.map { QuestionPick(set: quiz, question: $0) }
            return AnyView(NavigationStack {
                InsightQuestionList(title: MistakeReason.misread.title, tip: nil, picks: picks)
            })
        case "rules":
            return AnyView(NavigationStack { RuleSheetView() })
        case "coverage":
            return AnyView(TourSetup({ TourData.chooseExam() }) { NavigationStack { CoverageView() } })
        case "stats":
            return AnyView(NavigationStack { StatsView() })

        // MARK: settings, support, platform
        case "ai-models", "ai-provider":
            // ModelSettingsView opens the add screen for "ai-provider"
            return AnyView(ModelSettingsView())
        case "diagnostics":
            return AnyView(NavigationStack { DiagnosticsSettingsView() })
        case "lectures":
            return AnyView(NavigationStack { SourcesLibraryView() })
        case "set-credits":
            return AnyView(NavigationStack { SetCreditsView(set: quiz) })
        case "licences":
            return AnyView(NavigationStack { ContentLicencesView() })
        case "help":
            return AnyView(NavigationStack { HelpPage() })
        case "faq":
            return AnyView(NavigationStack { FAQPage() })
        case "examples":
            return AnyView(NavigationStack { ExamplesHubView() })
        case "generation-hud":
            // the writing card over a screen that shows it (GenerationHUD
            // shows a job part-way through for this name)
            return AnyView(NavigationStack { ReasoningView() })
        default:
            return AnyView(EmptyView())
        }
    }
}

/// The checked quiz, for the sheets the quiz opens over itself.
private struct TourChecked: View {
    var body: some View {
        NavigationStack {
            MCQQuizView(set: SampleData.nephrology,
                        initialAnswers: [MCQAnswer(selected: 2, checked: true), MCQAnswer(), MCQAnswer()])
        }
    }
}

/// Runs `setup` before the content is made: clearing what a launch would
/// otherwise inherit, or registering the settings a still needs.
private struct TourSetup<Content: View>: View {
    private let content: Content

    init(_ setup: () -> Void, @ViewBuilder content: () -> Content) {
        setup()
        self.content = content()
    }

    var body: some View { content }
}

/// The content on a library of its own, in place of the seeded one.
private struct TourStore<Content: View>: View {
    @StateObject private var store: Store
    private let content: Content

    init(_ make: () -> Store, @ViewBuilder content: () -> Content) {
        let made: Store = make()
        _store = StateObject(wrappedValue: made)
        self.content = content()
    }

    var body: some View { content.environmentObject(store) }
}

/// The content on a throwaway notes store holding the example ideas
/// (NoteExamples): the preview's own notes store is empty.
private struct TourNotes<Content: View>: View {
    @StateObject private var notes: NoteStore
    private let content: (NoteStore) -> Content

    init(@ViewBuilder content: @escaping (NoteStore) -> Content) {
        let made = NoteStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("redpen-preview-\(UUID().uuidString).json"))
        NoteExamples.seed(into: made)
        _notes = StateObject(wrappedValue: made)
        self.content = content
    }

    var body: some View { content(notes).environmentObject(notes) }
}

/// Home with a learning screen open over it, the way LearnRouter opens one.
private struct TourLearn: View {
    let route: LearnRoute

    var body: some View {
        LibraryView()
            .learnRoutes()
            .task { @MainActor in LearnRouter.shared.open(route) }
    }
}

/// What the tour's cases are made from: the example seeders only.
@MainActor
private enum TourData {
    /// A throwaway library holding `sets`.
    static func store(_ sets: [StudySet]) -> Store {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("redpen-preview-\(UUID().uuidString).json")
        let store = Store(fileURL: url)
        store.library = sets
        return store
    }

    /// Settings for this launch only: registered, so nothing is written.
    static func register(_ values: [String: Any]) {
        UserDefaults.standard.register(defaults: values)
    }

    /// PLAB, six weeks away.
    static func chooseExam() {
        register([ExamTrack.storageKey: ExamTrack.plab.rawValue,
                  ExamTrack.dateKey: Date().addingTimeInterval(42 * 86_400).timeIntervalSince1970])
    }

    /// The example ideas' hub note.
    static func hub(in notes: NoteStore) -> UUID {
        (notes.notes.first { $0.title == "Groin hernia" } ?? notes.notes.first)?.id ?? UUID()
    }

    /// The samples' questions and the lupus quiz, as a short PLAB paper.
    static func sitting() -> MockSitting {
        let sets: [StudySet] = [SampleData.nephrology, PreviewDecks.lupusQuiz]
        let picks: [QuestionPick] = sets.flatMap { set in set.questions.map { QuestionPick(set: set, question: $0) } }
        let paper: MockPaperSpec = MockFormat.papers(for: .plab)[0]
        return MockSitting(title: paper.title, specs: MockAssembler.fitted(paper.sections, to: picks.count),
                           picks: [picks], wanted: picks.count, track: .plab)
    }

    /// The first example patient, worked through and discharged.
    static func finishedRun(_ file: CaseFile) -> CaseRun {
        var run = CaseRun(caseID: file.id, started: Date().addingTimeInterval(-900))
        for step in file.steps.prefix(4) { run.take(step.id, in: file) }
        run.setLadder([file.diagnosis.name] + file.differentials.prefix(2).map(\.name))
        run.decide(CaseRun.Decision(diagnosis: file.diagnosis.name, nextStep: file.nextStep.key), in: file)
        return run
    }

    /// The lupus deck as a spreadsheet, read by the app's own table import.
    static func importPreview() -> ImportPreview {
        let deck: StudySet = PreviewDecks.lupus
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(deck.name).tsv")
        let rows: [String] = deck.cards.map { "\($0.front)\t\($0.bullets.first ?? "")" }
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        if let read = try? LibraryImport.table(url, kind: .anki, subject: deck.subject) { return read }
        return ImportPreview(title: deck.name, source: .table, sets: [deck], folderNames: [nil])
    }

    /// The cardiology set as a file another app shared.
    static func sharedSet() -> IncomingFile {
        let set: StudySet = SampleData.cardiology
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(set.name).\(ImportKind.setExtension)")
        let data: Data = (try? JSONEncoder.redPen.encode(set)) ?? Data()
        try? data.write(to: url)
        return IncomingFile(id: UUID(), url: url, name: url.lastPathComponent, kind: .studySet,
                            byteCount: data.count)
    }
}
#else
extension PreviewExtras {
    static let tourScreens: [String] = []
    static func tourView(for screen: String) -> AnyView { AnyView(EmptyView()) }
}
#endif
