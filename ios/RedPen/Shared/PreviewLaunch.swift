import SwiftUI

/// Screenshot hooks for the CI preview pipeline (.github/workflows/ios-preview.yml).
///
/// The workflow builds the app for the iOS Simulator and launches it once
/// per screen with `-uiPreviewScreen <name>`, then grabs a screenshot. In
/// that mode the app runs against an in-memory store seeded with the
/// sample sets below (nothing is written to the user's library) and opens
/// straight onto the requested screen. A normal launch has no such
/// argument and takes the ordinary path in `RedPenApp`.
enum PreviewLaunch {
    /// The screen named on the command line, or nil for a normal launch.
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiPreviewScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static let screens = ["library", "new", "quiz", "quiz-checked", "summary", "anki", "anki-revealed"]

    /// A store that never touches the real library file.
    @MainActor
    static func seededStore() -> Store {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("redpen-preview-\(UUID().uuidString).json")
        let store = Store(fileURL: url)
        store.library = SampleData.sets
        return store
    }
}

/// Example content, clearly not the user's data — the same two sets the
/// browser mock uses, so the real screenshots and the mock line up.
enum SampleData {
    static let nephrology = StudySet(
        name: "Nephrology — glomerular disease",
        subject: "Nephrology",
        kind: .mcq,
        questions: [
            MCQQuestion(
                stem: "A 34-year-old presents with frothy urine, periorbital oedema and 6 g/day proteinuria. Serum albumin is 22 g/L. Which finding on light microscopy is most consistent with the most common primary cause in adults?",
                options: ["Normal glomeruli", "Segmental sclerosis in some glomeruli", "Diffuse thickening of the basement membrane", "Mesangial IgA deposits"],
                correctIndex: 1,
                explanation: "Focal segmental glomerulosclerosis is the most common primary nephrotic syndrome in adults; light microscopy shows sclerosis in some (focal) glomeruli, affecting part (segmental) of the tuft."
            ),
            MCQQuestion(
                stem: "Which glomerular disease is classically associated with hepatitis C infection?",
                options: ["Minimal change disease", "Membranous nephropathy", "Membranoproliferative glomerulonephritis", "Post-streptococcal GN"],
                correctIndex: 2,
                explanation: "Hepatitis C causes cryoglobulinaemia, which produces an MPGN pattern with low complement."
            ),
            MCQQuestion(
                stem: "Anti-PLA2R antibodies are most specific for which condition?",
                options: ["Primary membranous nephropathy", "Lupus nephritis class V", "IgA nephropathy", "Anti-GBM disease"],
                correctIndex: 0,
                explanation: "Anti-phospholipase A2 receptor antibodies are found in roughly 70–80% of primary membranous nephropathy and are useful for diagnosis and monitoring."
            ),
        ]
    )

    static let cardiology = StudySet(
        name: "Cardiology — heart failure",
        subject: "Cardiology",
        kind: .anki,
        cards: [
            AnkiCard(
                type: .qa,
                front: "Four drug classes with mortality benefit in HFrEF?",
                bullets: ["**ACEi / ARB / ARNI**", "**Beta-blockers** (bisoprolol, carvedilol, metoprolol succinate)", "**MRA** (spironolactone, eplerenone)", "**SGLT2 inhibitors**"],
                why: "These form the ‘four pillars’; loop diuretics relieve congestion but do not improve survival."
            ),
            AnkiCard(
                type: .cloze,
                clozeText: "An ejection fraction of {{c1::≤ 40%}} defines HFrEF, while {{c1::≥ 50%}} defines HFpEF.",
                why: "41–49% is the ‘mildly reduced’ band (HFmrEF)."
            ),
            AnkiCard(
                type: .qa,
                front: "First-line investigation when heart failure is suspected in primary care?",
                bullets: ["**NT-proBNP** (or BNP)"],
                why: "A normal natriuretic peptide makes heart failure unlikely; a raised one triggers echocardiography."
            ),
        ]
    )

    static let sets: [StudySet] = [nephrology, cardiology]
}

/// Opens the requested screen directly, with the sample data in place.
struct PreviewRoot: View {
    let screen: String

    var body: some View {
        switch screen {
        case "new":
            NewSetView()
        case "quiz":
            NavigationStack { MCQQuizView(set: SampleData.nephrology) }
        case "quiz-checked":
            NavigationStack {
                MCQQuizView(set: SampleData.nephrology, initialAnswers: [MCQAnswer(selected: 2, checked: true), MCQAnswer(), MCQAnswer()])
            }
        case "summary":
            NavigationStack {
                MCQSummaryView(set: SampleData.nephrology, answers: [MCQAnswer(selected: 1, checked: true), MCQAnswer(selected: 0, checked: true), MCQAnswer(selected: 0, checked: true)])
            }
        case "anki":
            NavigationStack { AnkiReviewView(set: SampleData.cardiology) }
        case "anki-revealed":
            NavigationStack { AnkiReviewView(set: SampleData.cardiology, startRevealed: true) }
        default:
            LibraryView()
        }
    }
}
