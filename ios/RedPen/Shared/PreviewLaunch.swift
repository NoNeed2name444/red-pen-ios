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

    static let screens = ["library", "new", "quiz", "quiz-checked", "summary", "anki", "anki-revealed", "book", "qa", "qa-revealed", "osce", "osce-revealed", "osce-complete", "narrate", "narrate-finished"]

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

    static let endocrine = StudySet(
        name: "Endocrinology — thyroid",
        subject: "Endocrinology",
        kind: .book,
        bookMarkdown: """
        # Hyperthyroidism

        **Thyrotoxicosis** is the clinical state of excess thyroid hormone; **hyperthyroidism** is the subset caused by overproduction by the gland itself.

        ## Causes

        | Cause | Clue |
        |---|---|
        | **Graves disease** | Diffuse goitre, eye signs, pretibial myxoedema, TRAb positive |
        | Toxic multinodular goitre | Older patient, nodular gland, no eye signs |
        | Toxic adenoma | Single hot nodule on uptake scan |
        | Thyroiditis | Tender gland, *low* uptake, transient |

        ## Investigations

        - **TSH** suppressed, free T4 (± T3) raised
        - TSH-receptor antibodies confirm Graves
        - Radioiodine uptake: high and diffuse in Graves, patchy in MNG, low in thyroiditis

        ## Management

        - Symptom control: **propranolol**
        - Antithyroid drugs: **carbimazole** first line (propylthiouracil in the first trimester)
        - Definitive: radioiodine or thyroidectomy
        - Warn every patient on antithyroid drugs to report a sore throat or fever — **agranulocytosis**
        """
    )

    static let respiratory = StudySet(
        name: "Respiratory — cases",
        subject: "Respiratory",
        kind: .qa,
        qaCards: [
            QACard(topic: "Pneumonia", type: .case, stem: "A 72-year-old with fever, productive cough and right basal crackles. RR 32, BP 88/56, urea 9 mmol/L, confused. What is the CURB-65 score and where should she be managed?",
                   answer: ["CURB-65 = **4** (confusion, urea > 7, RR ≥ 30, BP < 90/60)", "Score ≥ 3 → **admit, consider ICU**", "IV co-amoxiclav + clarithromycin per local policy"]),
            QACard(topic: "Asthma", type: .recall, stem: "Features of a life-threatening asthma attack?",
                   answer: ["PEF < **33%** of best", "SpO₂ < **92%**, PaO₂ < 8 kPa, *normal* PaCO₂", "Silent chest, cyanosis, poor effort", "Exhaustion, arrhythmia, hypotension, altered consciousness"]),
            QACard(topic: "COPD", type: .case, stem: "Known COPD, acutely breathless, drowsy. ABG on 15 L O₂: pH 7.28, PaCO₂ 9.5 kPa, PaO₂ 14 kPa. Next step?",
                   answer: ["Controlled oxygen — target SpO₂ **88–92%** (Venturi 24–28%)", "Nebulised salbutamol + ipratropium, steroids, antibiotics if purulent", "Repeat ABG in 30–60 min; **NIV** if pH < 7.35 with PaCO₂ > 6.5 despite treatment"]),
        ]
    )

    static let osce = StudySet(
        name: "Skills — venepuncture & catheterisation",
        subject: "Clinical skills",
        kind: .osce,
        osceChecklists: [
            OsceChecklist(title: "Venepuncture", steps: [
                "Wash hands and don gloves",
                "Confirm patient identity and explain the procedure, gain consent",
                "Select and clean the venepuncture site",
                "Apply tourniquet",
                "Insert needle at 15–30° and advance until flashback",
                "Release tourniquet before withdrawing needle",
                "Withdraw needle, apply pressure, dispose of sharps safely",
                "Label samples at the bedside and thank the patient",
            ]),
            OsceChecklist(title: "Male urinary catheterisation", steps: [
                "Wash hands, explain procedure and gain consent",
                "Position patient supine, expose and drape",
                "Clean the glans with antiseptic, retracting the foreskin if present",
                "Instil local anaesthetic gel and allow it to take effect",
                "Insert catheter fully to the hilt",
                "Inflate balloon only once urine is seen draining",
                "Withdraw gently until resistance is felt, reduce foreskin",
                "Connect to drainage bag and document the procedure",
            ]),
        ]
    )

    static let narrate = StudySet(
        name: "Lecture — acid–base physiology",
        subject: "Renal physiology",
        kind: .narrate,
        narrateSegments: [
            NarrateSegment(text: "Today we're covering how the body defends its blood pH.", lang: "en"),
            NarrateSegment(text: "Three systems do the work: buffers, the lungs, and the kidneys.", lang: "en"),
            NarrateSegment(text: "Buffers act in seconds, the lungs in minutes, the kidneys over hours to days.", lang: "en"),
            NarrateSegment(text: "The bicarbonate buffer system is the one you'll use clinically most often.", lang: "en"),
            NarrateSegment(text: "Remember the Henderson–Hasselbalch equation links pH to the ratio of bicarbonate to CO2.", lang: "en"),
            NarrateSegment(text: "A rise in CO2 lowers pH — that's a respiratory acidosis.", lang: "en"),
            NarrateSegment(text: "The kidneys compensate slowly, by reabsorbing more bicarbonate.", lang: "en"),
        ]
    )

    static let sets: [StudySet] = [nephrology, cardiology, endocrine, respiratory, osce, narrate]
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
        case "book":
            NavigationStack { BookReaderView(set: SampleData.endocrine, page: 1) }
        case "qa":
            NavigationStack { QACardsView(set: SampleData.respiratory) }
        case "qa-revealed":
            NavigationStack { QACardsView(set: SampleData.respiratory, startRevealed: true) }
        case "osce":
            NavigationStack { OsceReviewView(set: SampleData.osce) }
        case "osce-revealed":
            NavigationStack { OsceReviewView(set: SampleData.osce, startRevealed: true) }
        case "osce-complete":
            NavigationStack { OsceReviewView(set: SampleData.osce, startComplete: true, startMissed: [2]) }
        case "narrate":
            NavigationStack { NarrateReviewView(set: SampleData.narrate, startIndex: 3) }
        case "narrate-finished":
            NavigationStack { NarrateReviewView(set: SampleData.narrate, startIndex: SampleData.narrate.narrateSegments.count - 1, startFinished: true) }
        default:
            LibraryView()
        }
    }
}
