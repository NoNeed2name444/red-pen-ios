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

    static let screens = ["anki-quizable", "quiz-from-cards", "narrate-fixing", "occlusion-example"]

    @ViewBuilder
    static func view(for screen: String) -> some View {
        switch screen {
        case "anki-quizable":
            // the same review screen, on a deck big enough for the toolbar's
            // Quiz me button to be enabled
            NavigationStack { AnkiReviewView(set: PreviewDecks.lupus) }
        case "quiz-from-cards":
            NavigationStack { MCQQuizView(set: PreviewDecks.lupusQuiz) }
        case "narrate-fixing":
            // a real Egyptian-mix lecture line, with the fix sheet open on the
            // word the recogniser got wrong
            NavigationStack { NarrateReviewView(set: PreviewDecks.lecture, startFixing: 3) }
        case "occlusion-example":
            // the heart diagram, read and covered by the real route
            NavigationStack { OcclusionExampleView() }
        default:
            EmptyView()
        }
    }

    static func handles(_ screen: String) -> Bool { screens.contains(screen) }
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
