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

    /// Posted by the "section-switch" preview: home moves one place along
    /// its dock (LibraryView).
    static let dockStep = Notification.Name("PreviewExtras.dockStep")

    @ViewBuilder
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
        case let science where science.hasPrefix("science-"):
            // the Sciences: the hub, its pages, a few tools and the atlas
            // (SciencePreviewScreen; SciencesUITests photographs them)
            SciencePreviewScreen(name: science)
        case "home-ideas":
            // home on Ideas, in its hue
            LibraryView()
                .task {
                    try? await Task.sleep(for: .seconds(1))
                    NotificationCenter.default.post(name: PreviewExtras.dockStep, object: "ideas")
                }
        default:
            EmptyView()
        }
    }

    static func handles(_ screen: String) -> Bool { screens.contains(screen) || screen.hasPrefix("science-") }
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
