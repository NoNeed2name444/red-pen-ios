import SwiftUI
import UIKit

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

    /// The orientation named on the command line, for the iPad job.
    ///
    /// simctl cannot rotate a simulator, so without this a "landscape" pass
    /// silently produces more portrait screenshots - pictures that look like
    /// evidence and are not. The app turns itself instead, through the window
    /// scene, which is the only part of the system that can.
    static var landscape: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiPreviewOrientation"), i + 1 < args.count else { return false }
        return args[i + 1].lowercased().hasPrefix("land")
    }

    /// A pretend window width, for photographing the multitasking sizes.
    ///
    /// A simulator cannot be put into Slide Over from the command line, so a
    /// pass that claims to show the app at 320 points has to get that width
    /// some other way: the root view is simply given it. What is photographed
    /// is then the app's own layout at that size - which is the thing being
    /// checked - over a plain grey surround standing in for whatever the
    /// student has open behind it.
    static var pretendWidth: CGFloat? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiPreviewWidth"), i + 1 < args.count,
              let w = Double(args[i + 1]), w > 100 else { return nil }
        return CGFloat(w)
    }

    /// Asks the window to turn, and keeps asking until it does.
    ///
    /// One attempt in `.task` was not enough: the first landscape pass came
    /// back as six portrait screenshots. A scene may not be attached yet when
    /// the first view appears, and iOS refuses the request outright while the
    /// app is multitasking-capable - so this tries repeatedly for a few
    /// seconds and writes down what happened, because a silent failure here
    /// produces screenshots that look like evidence and are not.
    @MainActor
    static func applyOrientation() async {
        guard landscape else { return }
        var notes: [String] = []
        for attempt in 1...12 {
            guard let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene }).first else {
                notes.append("attempt \(attempt): no window scene yet")
                try? await Task.sleep(for: .milliseconds(400))
                continue
            }
            if scene.interfaceOrientation.isLandscape {
                notes.append("attempt \(attempt): already landscape")
                break
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
                notes.append("attempt \(attempt): refused - \(error.localizedDescription)")
            }
            try? await Task.sleep(for: .milliseconds(400))
            if scene.interfaceOrientation.isLandscape {
                notes.append("attempt \(attempt): turned")
                break
            }
        }
        // Written where the screenshot job can fish it out of the app
        // container, since a print from a simctl launch goes nowhere.
        let log = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rotation.log")
        let text = notes.joined(separator: "\n") + "\n"
        try? text.write(to: log, atomically: true, encoding: .utf8)
    }

    static let screens = ["library", "new", "quiz", "quiz-checked", "summary", "anki", "anki-revealed", "book", "qa", "qa-revealed", "osce", "osce-revealed", "osce-complete", "narrate", "narrate-finished"]

    /// A store that never touches the real library file.
    @MainActor
    static func seededStore() -> Store {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("redpen-preview-\(UUID().uuidString).json")
        let store = Store(fileURL: url)
        store.library = SampleData.sets
        // group the two cardiology-ish sets so the library screenshot shows a folder
        let folder = StudyFolder(name: "Cardiology block")
        store.folders = [folder]
        for i in store.library.indices where ["Cardiology", "Respiratory"].contains(store.library[i].subject) {
            store.library[i].folderId = folder.id
        }
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
        ## Hyperthyroidism

        ### Definition

        **Thyrotoxicosis** is the clinical state of excess thyroid hormone; **hyperthyroidism** is the subset caused by overproduction by the gland itself.

        ### Causes and risk factors

        | Cause | Clue |
        |---|---|
        | **Graves disease** | Diffuse goitre, eye signs, pretibial myxoedema, TRAb positive |
        | Toxic multinodular goitre | Older patient, nodular gland, no eye signs |
        | Toxic adenoma | Single hot nodule on uptake scan |
        | Thyroiditis | Tender gland, *low* uptake, transient |

        > **Exam tip:** Eye signs and pretibial myxoedema point to **Graves** - no other cause gives them.

        ### Investigations

        - **TSH** suppressed, free T4 (± T3) raised
        - TSH-receptor antibodies confirm Graves
        - Radioiodine uptake: high and diffuse in Graves, patchy in MNG, low in thyroiditis

        ```flow
        Suspected hyperthyroidism
        TSH and free T4
        If TSH low and FT4 high → primary hyperthyroidism
        TSH-receptor antibodies
        If positive → Graves disease
        If negative → uptake scan to find the cause
        ```

        ### Management

        - Symptom control: **propranolol**
        - Antithyroid drugs: **carbimazole** first line (propylthiouracil in the first trimester)
        - Definitive: radioiodine or thyroidectomy

        > **Red flag:** Warn every patient on antithyroid drugs to report a sore throat or fever at once - **agranulocytosis**.

        > **Mnemonic:** Graves' eye signs - **NO SPECS** (No signs, Only signs, Soft tissue, Proptosis, Extraocular muscles, Corneal, Sight loss).

        ## Hypothyroidism

        ### Definition

        Too little thyroid hormone; in iodine-sufficient countries most often from **Hashimoto's thyroiditis**.

        ### Clinical features

        - Tiredness, weight gain, cold intolerance, constipation
        - **Slow-relaxing reflexes**, dry skin, bradycardia

        ### Management

        - **Levothyroxine**, adjusted to keep TSH in range
        - Start low in the elderly and in ischaemic heart disease

        > **Key point:** Recheck TSH 6-8 weeks after any dose change - that is how long it takes to settle.
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

    /// Adds a copy of every example set, once, to a personal build's library -
    /// never to the App Store app, whose students start with their own.
    @MainActor
    static func seedPersonalBuild(into store: Store) {
        let key = "sampleLibrary.v3"
        guard PersonalBuild.isOn,
              !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let folder = StudyFolder(name: "Examples - try every mode")
        store.folders.append(folder)
        for sample in sets {
            var copy = sample
            copy.id = UUID()
            copy.name = "Example: " + sample.name
            copy.folderId = folder.id
            store.addSet(copy)
        }
    }
}

/// Opens the requested screen directly, with the sample data in place.
struct PreviewRoot: View {
    let screen: String

    var body: some View {
        Group {
            if let w = PreviewLaunch.pretendWidth {
                ZStack {
                    Color(.systemGray4).ignoresSafeArea()
                    content
                        .frame(width: w)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 6)
                        .padding(.vertical, 28)
                }
            } else {
                content
            }
        }
        .task {
            // After the first layout, so there is a scene to turn.
            await PreviewLaunch.applyOrientation()
        }
    }

    @ViewBuilder
    private var content: some View {
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
