import Foundation

/// The exam the student is sitting, so questions and stations are written in
/// that exam's shape: its question style, its units, whose guidelines, and
/// how its clinical stations are run and marked.
///
/// The same fact is a different question in Boston and in Birmingham: a
/// USMLE vignette gives a glucose in mg/dL and expects US guidelines, a PLAB
/// one gives mmol/L and expects NICE and the BNF.
///
/// Foundation only, so the prompts that use it can be tested without a model.
enum ExamTrack: String, CaseIterable, Identifiable {
    case general, usmle, plab, mrcp, mrcs

    var id: String { rawValue }

    static let storageKey = "examTrack"

    /// The one the student picked, or general revision.
    /// Where the exam date is kept (seconds since 1970, 0 for none).
    static let dateKey = "exam.date"

    static var current: ExamTrack {
        ExamTrack(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .general
    }

    var title: String {
        switch self {
        case .general: return "General revision"
        case .usmle: return "USMLE Step 1 / Step 2 CK"
        case .plab: return "PLAB 1 & 2"
        case .mrcp: return "MRCP(UK) Part 1, 2 & PACES"
        case .mrcs: return "MRCS Part A & B"
        }
    }

    /// Seconds a question gets in this exam's written paper, for timed exam
    /// mode: the paper's length divided by its questions, rounded. General
    /// revision gets a middling pace that is neither exam's.
    var secondsPerQuestion: Int {
        switch self {
        case .general: return 75
        case .usmle: return 90   // 40 questions in an hour-long block
        case .plab: return 60    // 180 questions in three hours
        case .mrcp: return 108   // 100 questions in three hours
        case .mrcs: return 60    // Part A's pace, near enough
        }
    }

    /// Minutes with the patient in one of this exam's clinical stations, for
    /// the OSCE station timer.
    var stationMinutes: Int {
        switch self {
        case .plab: return 8     // PLAB 2
        case .mrcp: return 10    // a PACES encounter
        case .mrcs: return 9     // MRCS Part B
        case .usmle, .general: return 15
        }
    }

    /// The opening line of the MCQ writer's instructions.
    var mcqStyle: String {
        switch self {
        case .general:
            return "You are writing single-best-answer multiple-choice questions for a medical student's exam revision, in the NBME/USMLE \"one-best-answer\" style."
        case .usmle:
            return "You are writing USMLE Step 1 / Step 2 CK single-best-answer questions in the NBME style: most are clinical vignettes (age, sex, setting, history, vitals, examination, labs) that end in one clear question. Use US conventional units (mg/dL, \u{00B0}F alongside \u{00B0}C), US generic drug names (acetaminophen, epinephrine) and current US guidelines (e.g. ACC/AHA, ADA, USPSTF, IDSA). Step 1 questions lean on mechanism, pathology and pharmacology; Step 2 CK questions on diagnosis, next best step and management."
        case .plab:
            return "You are writing PLAB 1 single-best-answer questions (the GMC's exam) at the level of a UK foundation-year doctor: short clinical scenarios set in UK practice (GP surgery, A&E, wards) with one best answer from five. Use SI units (mmol/L, \u{00B5}mol/L), UK drug names (paracetamol, adrenaline), and current NICE guidance, NICE CKS and the BNF; where UK and US practice differ, the UK answer is correct. Favour common and dangerous presentations, safe prescribing, ethics and GMC Good Medical Practice."
        case .mrcp:
            return "You are writing MRCP(UK) Part 1 / Part 2 written best-of-five questions at the level of a UK core medical trainee: detailed clinical scenarios with investigation results to interpret (blood tests, ECG and imaging descriptions, blood gases). Use SI units, UK drug names and current UK practice (NICE, BTS, BSG, ESC as used in the UK). Part 1 leans on the science and mechanism behind the medicine; Part 2 on diagnosis, investigation and management decisions."
        case .mrcs:
            return "You are writing MRCS Part A single-best-answer questions (Royal Colleges of Surgeons): applied basic sciences - applied surgical anatomy, physiology and pathology - and the principles of surgery in general (perioperative care, trauma, surgical oncology, infection). Use SI units, UK drug names and UK surgical practice (NICE, ATLS). Anatomy questions should test relations, nerve and blood supply, and the clinical consequence of an injury."
        }
    }

    /// What is added to the OSCE writer's instructions: how this exam's
    /// clinical stations are run and marked.
    var osceStyle: String? {
        switch self {
        case .general: return nil
        case .usmle:
            return "Write each station as a USMLE-style patient encounter: focused history, focused physical examination, counselling, and the patient note (history, examination, differential diagnosis with supporting findings, first investigations)."
        case .plab:
            return "Write each station as a PLAB 2 station: 8 minutes with the patient after 1.5 minutes' reading, set in UK practice, marked on data gathering, clinical management and interpersonal skills. Include safety-netting, checking understanding, and follow-up that a UK foundation doctor would arrange."
        case .mrcp:
            return "Write each station as an MRCP PACES station (history taking, communication and ethics, or a clinical examination station), marked on the PACES skills: physical examination, identifying physical signs, clinical communication, differential diagnosis, clinical judgement, managing patients' concerns and maintaining patient welfare."
        case .mrcs:
            return "Write each station as an MRCS Part B OSCE station (anatomy and surgical pathology, applied physiology and critical care, clinical and procedural skills, or communication skills), with the surgical-safety steps examiners mark: consent, WHO checklist items, asepsis and documentation."
        }
    }
}
