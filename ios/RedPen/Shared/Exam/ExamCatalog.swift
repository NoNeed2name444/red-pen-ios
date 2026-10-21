import Foundation

// The most common medical exams, each with its format and blueprint, so the
// whole app can put one first: how questions are written (options, stem
// length, lead-ins, units), which topics a generated set leans on, what to
// study next, the coverage map, the mock paper and its clock, and how strict
// the accuracy engine is.
//
// Every blueprint cites where it comes from. Where the exam publishes ranges
// (USMLE, COMLEX), the weights are the ranges' midpoints, normalised to 100%.
// Where it publishes a content map but no percentages (PLAB / MLA, MCC, AMC,
// SCFHS, the Gulf regulators, NBEMS "indicative" numbers), the weights are
// OUR approximation and `blueprintIsApproximate` says so on screen. Exams
// change their formats: every entry was checked against what was public in
// 2025-2026 and the screen always tells the student to confirm with the exam.
//
// Foundation only: tested on Linux (Tests/ExamCatalogTests.swift). The server
// keeps the prompt-relevant half (server/exams.js) and a test checks the two
// agree.

/// A topic area a blueprint is written in. Organ systems for the clinical
/// exams, subjects for the Indian ones, sciences for the basic-science ones -
/// one list, so any two exams can be compared and combined.
enum ExamDomain: String, CaseIterable, Identifiable, Codable {
    case anatomy, physiology, biochemistry, pathology, pharmacology, microbiology, immunology
    case genetics, multisystem, biostatistics, ethics, forensic, community
    case cardio, resp, gi, endocrine, renal, neuro, msk, heme, id, derm, psychiatry
    case peds, obstetrics, gynaecology, ent, ophthalmology, oncology, surgery, orthopaedics
    case anaesthesia, radiology, emergency, geriatrics, palliative, sexualHealth, omm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anatomy: return "Anatomy"
        case .physiology: return "Physiology"
        case .biochemistry: return "Biochemistry"
        case .pathology: return "Pathology"
        case .pharmacology: return "Pharmacology"
        case .microbiology: return "Microbiology"
        case .immunology: return "Immunology"
        case .genetics: return "Genetics"
        case .multisystem: return "Multisystem processes"
        case .biostatistics: return "Biostatistics and epidemiology"
        case .ethics: return "Ethics, law and communication"
        case .forensic: return "Forensic medicine"
        case .community: return "Community and public health"
        case .cardio: return "Cardiovascular"
        case .resp: return "Respiratory"
        case .gi: return "Gastrointestinal and liver"
        case .endocrine: return "Endocrine and metabolic"
        case .renal: return "Renal and urinary"
        case .neuro: return "Nervous system"
        case .msk: return "Musculoskeletal and rheumatology"
        case .heme: return "Blood and haematology"
        case .id: return "Infectious disease"
        case .derm: return "Skin"
        case .psychiatry: return "Psychiatry and behavioural health"
        case .peds: return "Paediatrics"
        case .obstetrics: return "Obstetrics"
        case .gynaecology: return "Gynaecology and breast"
        case .ent: return "Ear, nose and throat"
        case .ophthalmology: return "Ophthalmology"
        case .oncology: return "Oncology"
        case .surgery: return "General surgery"
        case .orthopaedics: return "Orthopaedics"
        case .anaesthesia: return "Anaesthesia and perioperative"
        case .radiology: return "Radiology"
        case .emergency: return "Acute and emergency"
        case .geriatrics: return "Older adults"
        case .palliative: return "Palliative care"
        case .sexualHealth: return "Sexual health"
        case .omm: return "Osteopathic principles (OMM)"
        }
    }
}

/// One line of a blueprint: a topic area and its weight. `weight` is as the
/// source gives it (a range's midpoint, questions out of 200...); the exam
/// normalises the whole blueprint to percent.
struct BlueprintShare: Hashable {
    let domain: ExamDomain
    let weight: Double
    /// The exam's own name for the area, when it differs from the domain's.
    let label: String?

    var title: String { label ?? domain.title }
}

/// Where the exam is sat, for grouping the picker.
enum ExamRegion: String, CaseIterable, Identifiable {
    case usa, uk, canada, australia, india, gulf, egypt, international

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usa: return "United States"
        case .uk: return "United Kingdom"
        case .canada: return "Canada"
        case .australia: return "Australia"
        case .india: return "India"
        case .gulf: return "Saudi Arabia and the Gulf"
        case .egypt: return "Egypt"
        case .international: return "International"
        }
    }
}

/// The exams sat in one region, for the picker.
struct ExamRegionGroup: Identifiable {
    let region: ExamRegion
    let exams: [TargetExam]
    var id: String { region.rawValue }
}

/// The openly licensed bank whose items show this exam's style
/// (ExamExemplars; server/bench/exam-exemplars.mjs).
enum ExemplarSource: String, Codable {
    /// MedQA's Step 1 items (MIT): long vignettes, mechanism lead-ins.
    case medqaStep1 = "medqa-step1"
    /// MedQA's Step 2 and 3 items: long vignettes, diagnosis and management.
    case medqaStep23 = "medqa-step23"
    /// MedMCQA (Apache-2.0): AIIMS / NEET-PG one-liners, four options.
    case medmcqa
}

/// One exam, as the app puts it first.
struct TargetExam: Identifiable, Hashable {
    let id: String
    /// "USMLE Step 2 CK": in the picker and on the dashboard.
    let name: String
    /// "Step 2 CK": on a set's badge.
    let shortName: String
    let region: ExamRegion
    /// The existing track whose units, guidelines and OSCE style it shares.
    let family: ExamTrack
    /// Options per question: 5 for single-best-of-five, 4 where the exam uses A-D.
    let options: Int
    /// A typical stem's length, in words.
    let stemWords: ClosedRange<Int>
    /// How this exam asks: its usual lead-ins.
    let leadIns: String
    /// Units, drug names, whose guidelines.
    let conventions: String
    /// Roughly how many questions are pure recall rather than a clinical case.
    let recallShare: Double
    let blueprint: [BlueprintShare]
    /// The published document the blueprint follows.
    let blueprintSource: String
    /// True when the weights are our estimate rather than the exam's numbers.
    let blueprintIsApproximate: Bool
    /// The written paper as sat: sections, each with its count and clock.
    let sections: [MockSectionSpec]
    /// USMLE-style blocks: the student chooses how many to sit.
    let sitsBlockwise: Bool
    /// Each section is its own paper, sat on its own (MRCP's two papers).
    let sitsSeparately: Bool
    /// How the real exam runs, in a line.
    let paperNote: String
    /// A rough pass mark as a fraction, for the readiness estimate only.
    let passMark: Double
    let passNote: String
    /// Marks lost for a wrong answer, when the exam takes them.
    let negativeMarking: String?
    let exemplars: ExemplarSource
    /// 0-1: how much stricter the accuracy engine is on this exam's
    /// management questions (AccuracyModel.stricter). Step 2 CK and 3 are
    /// mostly "next best step", where a subtly wrong key does the most harm.
    let accuracyStrictness: Double
    /// False when the exam publishes too little to be sure of the format.
    let formatConfirmed: Bool

    /// Seconds per question across the whole paper.
    var secondsPerQuestion: Int {
        let q: Int = sections.reduce(0) { $0 + $1.questions }
        let m: Int = sections.reduce(0) { $0 + $1.minutes }
        guard q > 0 else { return 60 }
        return Int((Double(m * 60) / Double(q)).rounded())
    }

    var totalWeight: Double { blueprint.reduce(0) { $0 + $1.weight } }

    /// The blueprint in percent, largest first; sums to 100.
    var shares: [(domain: ExamDomain, title: String, percent: Double)] {
        let total: Double = max(totalWeight, 0.0001)
        let rows: [(domain: ExamDomain, title: String, percent: Double)] = blueprint.map {
            (domain: $0.domain, title: $0.title, percent: $0.weight / total * 100)
        }
        return rows.sorted { $0.percent > $1.percent }
    }

    /// Percent for one domain (0 when the exam does not test it by name).
    func percent(_ domain: ExamDomain) -> Double {
        let total: Double = max(totalWeight, 0.0001)
        let w: Double = blueprint.filter { $0.domain == domain }.reduce(0) { $0 + $1.weight }
        return w / total * 100
    }
}

// MARK: - The catalogue

enum ExamCatalog {

    static var all: [TargetExam] {
        [step1, step2ck, step3, comlex1, comlex2, plab1, mrcp1, mrcsA, mccqe1, amc,
         neetpg, inicet, fmge, smle, dha, doh, mohap, qchp, omsb, emle, ifom]
    }

    static func exam(_ id: String?) -> TargetExam? {
        guard let id, !id.isEmpty else { return nil }
        return all.first { $0.id == id }
    }

    /// The catalogue in the picker's order: by region, as listed.
    static var byRegion: [ExamRegionGroup] {
        let list: [TargetExam] = all
        return ExamRegion.allCases.compactMap { region -> ExamRegionGroup? in
            let exams: [TargetExam] = list.filter { $0.region == region }
            return exams.isEmpty ? nil : ExamRegionGroup(region: region, exams: exams)
        }
    }

    private static func s(_ domain: ExamDomain, _ weight: Double, _ label: String? = nil) -> BlueprintShare {
        BlueprintShare(domain: domain, weight: weight, label: label)
    }

    private static func blocks(_ count: Int, questions: Int, minutes: Int, name: String = "Block") -> [MockSectionSpec] {
        (1...count).map { MockSectionSpec(title: "\(name) \($0)", questions: questions, minutes: minutes) }
    }

    static let usUnits: String = "US conventional units (mg/dL, \u{00B0}F alongside \u{00B0}C), US generic drug names (acetaminophen, epinephrine) and current US guidelines"
    static let ukUnits: String = "SI units (mmol/L), UK drug names (paracetamol, adrenaline) and current NICE / BNF guidance; where UK and US practice differ, the UK answer is correct"
    static let intlUnits: String = "SI units, international generic drug names and current international guidelines (WHO and the major specialty societies)"
    static let indiaUnits: String = "SI units, and the answers given by the standard Indian postgraduate textbooks"

    // MARK: United States

    /// USMLE Step 1 Content Outline and Specifications (usmle.org, "Step 1
    /// Content Outline", 2024-2026 edition): system ranges, midpoints here.
    /// Human development 1-3%; blood, lymphoreticular and immune 9-13%;
    /// behavioural health and nervous system / special senses 10-14%;
    /// musculoskeletal, skin 6-10%; cardiovascular 6-10%; respiratory and
    /// renal 11-15%; gastrointestinal 6-10%; reproductive and endocrine 12-16%;
    /// multisystem 8-12%; biostatistics and epidemiology 4-6%; social
    /// sciences (communication, ethics) 6-9%. Split within a shared range is
    /// ours. Seven 60-minute blocks of up to 40 items; pass/fail since 2022.
    static let step1 = TargetExam(
        id: "step1", name: "USMLE Step 1", shortName: "Step 1", region: .usa, family: .usmle,
        options: 5, stemWords: 90...200,
        leadIns: "mechanism, most likely cause, underlying pathophysiology, the drug's mechanism or adverse effect, the expected lab or histology finding",
        conventions: usUnits, recallShare: 0.1,
        blueprint: [s(.genetics, 3, "Human development and genetics"), s(.heme, 7, "Blood and lymphoreticular"), s(.immunology, 4, "Immune system"),
                    s(.psychiatry, 5, "Behavioural health"), s(.neuro, 7, "Nervous system and special senses"),
                    s(.msk, 5), s(.derm, 3), s(.cardio, 8), s(.resp, 6.5), s(.renal, 6.5), s(.gi, 8),
                    s(.endocrine, 7), s(.obstetrics, 3, "Pregnancy"), s(.gynaecology, 4, "Reproductive system and breast"),
                    s(.multisystem, 10, "Multisystem processes and disorders"), s(.biostatistics, 5),
                    s(.ethics, 8, "Social sciences: communication and ethics")],
        blueprintSource: "USMLE Step 1 Content Outline and Specifications (usmle.org): published ranges, midpoints",
        blueprintIsApproximate: false,
        sections: blocks(7, questions: 40, minutes: 60), sitsBlockwise: true, sitsSeparately: false,
        paperNote: "Up to 280 questions in seven 60-minute blocks of up to 40, with break time, in one 8-hour day.",
        passMark: 0.60, passNote: "Pass/fail since January 2022; USMLE does not publish a percent-correct pass mark (about 60% is a common rough guide).",
        negativeMarking: nil, exemplars: .medqaStep1, accuracyStrictness: 0, formatConfirmed: true)

    /// USMLE Step 2 CK Content Outline (usmle.org): immune 3-5%, blood 4-6%,
    /// behavioural 8-10%, nervous 6-10%, skin 4-6%, musculoskeletal 6-10%,
    /// cardiovascular 7-11%, respiratory 7-11%, gastrointestinal 7-11%, renal
    /// and male reproductive 4-6%, pregnancy 4-6%, female reproductive and
    /// breast 4-6%, endocrine 5-9%, multisystem 7-9%, biostatistics 3-5%,
    /// social sciences (ethics, patient safety) 10-15%. Midpoints sum to
    /// 112.5 and are normalised. Eight 60-minute blocks of up to 40 items.
    static let step2ck = TargetExam(
        id: "step2ck", name: "USMLE Step 2 CK", shortName: "Step 2 CK", region: .usa, family: .usmle,
        options: 5, stemWords: 100...220,
        leadIns: "most likely diagnosis, next best step in management, most appropriate pharmacotherapy, most appropriate initial investigation, most likely complication",
        conventions: usUnits, recallShare: 0.05,
        blueprint: [s(.immunology, 4), s(.heme, 5), s(.psychiatry, 9), s(.neuro, 8), s(.derm, 5), s(.msk, 8), s(.cardio, 9),
                    s(.resp, 9), s(.gi, 9), s(.renal, 5, "Renal, urinary and male reproductive"), s(.obstetrics, 5),
                    s(.gynaecology, 5), s(.endocrine, 7), s(.multisystem, 8, "Multisystem processes and disorders"),
                    s(.biostatistics, 4), s(.ethics, 12.5, "Social sciences: ethics, law and patient safety")],
        blueprintSource: "USMLE Step 2 CK Content Outline (usmle.org): published ranges, midpoints normalised",
        blueprintIsApproximate: false,
        sections: blocks(8, questions: 40, minutes: 60), sitsBlockwise: true, sitsSeparately: false,
        paperNote: "Up to 318 questions in eight 60-minute blocks of up to 40, in one 9-hour day.",
        passMark: 0.62, passNote: "A three-digit score; the passing standard is set by USMLE (around 214-218 in recent years). The percent here is a rough guide.",
        negativeMarking: nil, exemplars: .medqaStep23, accuracyStrictness: 0.5, formatConfirmed: true)

    /// USMLE Step 3 (usmle.org, Step 3 Content Outline): the same systems as
    /// Step 2 CK with more weight on biostatistics / interpreting the
    /// literature (5-10%) and on ambulatory management. Our midpoints.
    /// Day 1, Foundations of Independent Practice: 232 items in six 60-minute
    /// blocks; day 2, Advanced Clinical Medicine: 180 items in six 45-minute
    /// blocks, then 13 computer-based case simulations (not mocked here).
    static let step3 = TargetExam(
        id: "step3", name: "USMLE Step 3", shortName: "Step 3", region: .usa, family: .usmle,
        options: 5, stemWords: 100...230,
        leadIns: "most appropriate next step, screening and prevention, long-term and ambulatory management, prognosis, interpreting a study's results",
        conventions: usUnits, recallShare: 0.05,
        blueprint: [s(.immunology, 4), s(.heme, 4), s(.psychiatry, 9), s(.neuro, 7), s(.derm, 4), s(.msk, 7), s(.cardio, 10),
                    s(.resp, 9), s(.gi, 8), s(.renal, 5), s(.obstetrics, 5), s(.gynaecology, 5), s(.endocrine, 7),
                    s(.multisystem, 7, "Multisystem processes and disorders"), s(.biostatistics, 8, "Biostatistics and the medical literature"),
                    s(.ethics, 8, "Social sciences: ethics, law and patient safety")],
        blueprintSource: "USMLE Step 3 Content Outline (usmle.org): approximate midpoints",
        blueprintIsApproximate: true,
        sections: blocks(6, questions: 39, minutes: 60, name: "FIP block") + blocks(6, questions: 30, minutes: 45, name: "ACM block"),
        sitsBlockwise: true, sitsSeparately: false,
        paperNote: "Two days: Foundations of Independent Practice (about 232 questions, six 60-minute blocks), then Advanced Clinical Medicine (180 questions, six 45-minute blocks) and 13 case simulations.",
        passMark: 0.60, passNote: "A three-digit score; the passing standard is set by USMLE (about 200). The percent here is a rough guide.",
        negativeMarking: nil, exemplars: .medqaStep23, accuracyStrictness: 0.6, formatConfirmed: true)

    /// COMLEX-USA Level 1 (NBOME, nbome.org "COMLEX-USA Master Blueprint"):
    /// NBOME weights competency domains and clinical presentations, not organ
    /// systems; Osteopathic Principles and Practice is its own domain. The
    /// system split is OUR approximation. Pass/fail since 2022.
    static let comlex1 = TargetExam(
        id: "comlex1", name: "COMLEX-USA Level 1", shortName: "COMLEX 1", region: .usa, family: .usmle,
        options: 5, stemWords: 80...200,
        leadIns: "mechanism, most likely cause, the osteopathic structural finding, the most appropriate osteopathic manipulative treatment",
        conventions: usUnits, recallShare: 0.1,
        blueprint: [s(.omm, 12), s(.cardio, 8), s(.resp, 7), s(.gi, 7), s(.renal, 6), s(.neuro, 8), s(.psychiatry, 5),
                    s(.msk, 7), s(.derm, 3), s(.heme, 5), s(.immunology, 4), s(.endocrine, 7), s(.obstetrics, 3),
                    s(.gynaecology, 3), s(.multisystem, 8), s(.biostatistics, 4), s(.ethics, 3)],
        blueprintSource: "NBOME COMLEX-USA Master Blueprint (nbome.org): our system split of its domains",
        blueprintIsApproximate: true,
        sections: blocks(8, questions: 44, minutes: 60, name: "Section"), sitsBlockwise: true, sitsSeparately: false,
        paperNote: "One day, two 4-hour sessions of hour-long sections (about 352 questions); check nbome.org for the current count.",
        passMark: 0.60, passNote: "Pass/fail; NBOME does not publish a percent-correct pass mark.",
        negativeMarking: nil, exemplars: .medqaStep1, accuracyStrictness: 0, formatConfirmed: true)

    /// COMLEX-USA Level 2-CE (NBOME Master Blueprint): as Level 1, our system
    /// split, with the clinical disciplines' management emphasis.
    static let comlex2 = TargetExam(
        id: "comlex2", name: "COMLEX-USA Level 2-CE", shortName: "COMLEX 2", region: .usa, family: .usmle,
        options: 5, stemWords: 90...220,
        leadIns: "most likely diagnosis, next best step, most appropriate management including osteopathic treatment",
        conventions: usUnits, recallShare: 0.05,
        blueprint: [s(.omm, 12), s(.cardio, 9), s(.resp, 8), s(.gi, 8), s(.renal, 5), s(.neuro, 7), s(.psychiatry, 8),
                    s(.msk, 7), s(.derm, 4), s(.heme, 4), s(.immunology, 2), s(.endocrine, 6), s(.obstetrics, 5),
                    s(.gynaecology, 5), s(.multisystem, 5), s(.emergency, 3), s(.biostatistics, 3), s(.ethics, 4)],
        blueprintSource: "NBOME COMLEX-USA Master Blueprint (nbome.org): our system split of its domains",
        blueprintIsApproximate: true,
        sections: blocks(8, questions: 44, minutes: 60, name: "Section"), sitsBlockwise: true, sitsSeparately: false,
        paperNote: "One day of hour-long sections (about 352 questions); check nbome.org for the current count.",
        passMark: 0.62, passNote: "A three-digit score with a minimum pass set by NBOME. The percent here is a rough guide.",
        negativeMarking: nil, exemplars: .medqaStep23, accuracyStrictness: 0.5, formatConfirmed: true)

    // MARK: United Kingdom

    /// PLAB 1 (GMC, gmc-uk.org): 180 single-best-answer questions in 3 hours,
    /// set against the MLA content map. The GMC publishes the areas of
    /// clinical practice but NOT percentages: these weights are ours, leaning
    /// on acute care, common presentations and prescribing as the GMC's
    /// guidance does.
    static let plab1 = TargetExam(
        id: "plab1", name: "PLAB 1 (UKMLA)", shortName: "PLAB 1", region: .uk, family: .plab,
        options: 5, stemWords: 50...120,
        leadIns: "most likely diagnosis, most appropriate initial or immediate management, most appropriate investigation, what should be done next",
        conventions: ukUnits, recallShare: 0.1,
        blueprint: [s(.emergency, 9), s(.cardio, 7), s(.resp, 6), s(.gi, 6), s(.endocrine, 5), s(.renal, 4), s(.neuro, 5),
                    s(.psychiatry, 6, "Mental health"), s(.msk, 4), s(.heme, 3), s(.id, 4), s(.derm, 3), s(.ent, 3),
                    s(.ophthalmology, 3), s(.peds, 6, "Child health"), s(.obstetrics, 4), s(.gynaecology, 4),
                    s(.oncology, 3, "Cancer"), s(.surgery, 5), s(.geriatrics, 2), s(.palliative, 2), s(.sexualHealth, 2),
                    s(.pharmacology, 4, "Clinical pharmacology and prescribing"), s(.ethics, 3, "Professional knowledge and ethics"),
                    s(.community, 2, "Social and population health")],
        blueprintSource: "GMC MLA content map (gmc-uk.org): areas as published, weights ours",
        blueprintIsApproximate: true,
        sections: [MockSectionSpec(title: "PLAB 1", questions: 180, minutes: 180)], sitsBlockwise: false, sitsSeparately: false,
        paperNote: "180 single-best-answer questions in 3 hours, as the GMC sets it.",
        passMark: 0.63, passNote: "Set for each sitting by standard setting; usually a little over 60%.",
        negativeMarking: nil, exemplars: .medqaStep23, accuracyStrictness: 0.3, formatConfirmed: true)

    /// MRCP(UK) Part 1 blueprint (mrcpuk.org), questions out of 200:
    /// cardiology 15, haematology and oncology 15, clinical pharmacology 16,
    /// clinical sciences 25, dermatology 8, endocrinology 15, gastroenterology
    /// 15, geriatrics 4, infectious disease 15, nephrology 15, neurology 15,
    /// ophthalmology 4, psychiatry 8, respiratory 15, rheumatology 15. The
    /// splits inside "haematology and oncology" and "clinical sciences" are ours.
    static let mrcp1 = TargetExam(
        id: "mrcp1", name: "MRCP(UK) Part 1", shortName: "MRCP 1", region: .uk, family: .mrcp,
        options: 5, stemWords: 80...200,
        leadIns: "most likely diagnosis, underlying mechanism, most likely explanation for these results, most appropriate investigation",
        conventions: ukUnits, recallShare: 0.15,
        blueprint: [s(.cardio, 15), s(.heme, 9), s(.oncology, 6), s(.pharmacology, 16, "Clinical pharmacology and toxicology"),
                    s(.immunology, 6), s(.genetics, 4), s(.biostatistics, 5), s(.biochemistry, 5, "Biochemistry and metabolism"),
                    s(.physiology, 5, "Physiology and cell biology"), s(.derm, 8), s(.endocrine, 15), s(.gi, 15), s(.geriatrics, 4),
                    s(.id, 15, "Infectious diseases and GU medicine"), s(.renal, 15, "Nephrology"), s(.neuro, 15), s(.ophthalmology, 4),
                    s(.psychiatry, 8), s(.resp, 15), s(.msk, 15, "Rheumatology")],
        blueprintSource: "MRCP(UK) Part 1 blueprint (mrcpuk.org): questions per specialty out of 200",
        blueprintIsApproximate: false,
        sections: [MockSectionSpec(title: "Paper 1", questions: 100, minutes: 180),
                   MockSectionSpec(title: "Paper 2", questions: 100, minutes: 180)],
        sitsBlockwise: false, sitsSeparately: true,
        paperNote: "Two papers of 100 best-of-five questions, 3 hours each, on one day. Sit one now and the other later.",
        passMark: 0.60, passNote: "Standard-set for each diet; reported as a scaled score. About 60% is a rough guide.",
        negativeMarking: nil, exemplars: .medqaStep23, accuracyStrictness: 0.2, formatConfirmed: true)

    /// MRCS Part A (Intercollegiate, intercollegiatemrcsexams.org.uk): Paper 1
    /// Applied Basic Sciences, Paper 2 Principles of Surgery-in-General. The
    /// colleges publish the syllabus and times, not weights: ours.
    static let mrcsA = TargetExam(
        id: "mrcsA", name: "MRCS Part A", shortName: "MRCS A", region: .uk, family: .mrcs,
        options: 5, stemWords: 30...110,
        leadIns: "which structure is most likely injured, the nerve or vessel at risk, the physiological change, the most appropriate perioperative step",
        conventions: ukUnits, recallShare: 0.3,
        blueprint: [s(.anatomy, 30, "Applied surgical anatomy"), s(.physiology, 15, "Applied physiology"),
                    s(.pathology, 15, "Applied pathology"), s(.anaesthesia, 10, "Perioperative care"),
                    s(.emergency, 8, "Trauma"), s(.oncology, 6, "Surgical oncology"), s(.multisystem, 6, "Critical care"),
                    s(.peds, 3, "Paediatric surgery"), s(.surgery, 4, "Surgical technique"), s(.ethics, 3, "Professional practice")],
        blueprintSource: "Intercollegiate MRCS Part A syllabus: areas as published, weights ours",
        blueprintIsApproximate: true,
        sections: [MockSectionSpec(title: "Applied Basic Sciences", questions: 180, minutes: 180),
                   MockSectionSpec(title: "Principles of Surgery", questions: 120, minutes: 120)],
        sitsBlockwise: false, sitsSeparately: true,
        paperNote: "Applied Basic Sciences (3 hours) and Principles of Surgery-in-General (2 hours) on one day, at about a question a minute.",
        passMark: 0.70, passNote: "Standard-set each sitting; the colleges publish the mark with the results.",
        negativeMarking: nil, exemplars: .medmcqa, accuracyStrictness: 0.2, formatConfirmed: true)

    // MARK: Canada and Australia

    /// MCCQE Part I (Medical Council of Canada, mcc.ca blueprint): weighted
    /// by dimensions of care and physician activities, not disciplines; the
    /// discipline split here is OURS. 210 MCQs plus clinical decision-making
    /// cases (the cases are not mocked here).
    static let mccqe1 = TargetExam(
        id: "mccqe1", name: "MCCQE Part I", shortName: "MCCQE I", region: .canada, family: .general,
        options: 5, stemWords: 60...150,
        leadIns: "most likely diagnosis, most appropriate next step, most appropriate management, counselling and prevention",
        conventions: "SI units, Canadian drug names and current Canadian guidelines", recallShare: 0.05,
        blueprint: [s(.cardio, 4), s(.resp, 4), s(.gi, 4), s(.endocrine, 3), s(.renal, 3), s(.neuro, 3), s(.heme, 2), s(.id, 3),
                    s(.msk, 2), s(.derm, 1), s(.emergency, 3), s(.surgery, 12), s(.peds, 12), s(.obstetrics, 6), s(.gynaecology, 6),
                    s(.psychiatry, 12), s(.community, 10, "Population health"), s(.ethics, 8, "Ethical, legal and organisational")],
        blueprintSource: "MCC blueprint (mcc.ca): our discipline split",
        blueprintIsApproximate: true,
        sections: [MockSectionSpec(title: "Multiple-choice", questions: 210, minutes: 240)], sitsBlockwise: false, sitsSeparately: false,
        paperNote: "One day: 210 multiple-choice questions, then clinical decision-making cases (not included here).",
        passMark: 0.60, passNote: "A scaled score with a pass score set by the MCC. The percent here is a rough guide.",
        negativeMarking: nil, exemplars: .medqaStep23, accuracyStrictness: 0.4, formatConfirmed: true)

    /// AMC CAT MCQ (Australian Medical Council, amc.org.au): 150 items (120
    /// scored) in 3.5 hours across adult health (medicine, surgery), women's
    /// health, child health, mental health and population health. The
    /// proportions are ours.
    static let amc = TargetExam(
        id: "amc", name: "AMC CAT MCQ", shortName: "AMC", region: .australia, family: .general,
        options: 5, stemWords: 60...150,
        leadIns: "most likely diagnosis, most appropriate next step, most appropriate management",
        conventions: "SI units, Australian drug names and current Australian guidelines (Therapeutic Guidelines, RACGP)", recallShare: 0.05,
        blueprint: [s(.cardio, 5), s(.resp, 4), s(.gi, 4), s(.endocrine, 4), s(.renal, 3), s(.neuro, 4), s(.heme, 2), s(.id, 3),
                    s(.msk, 2), s(.derm, 2), s(.emergency, 2), s(.surgery, 15, "Adult health: surgery"), s(.obstetrics, 7.5),
                    s(.gynaecology, 7.5), s(.peds, 12.5, "Child health"), s(.psychiatry, 12.5, "Mental health"),
                    s(.community, 5, "Population health"), s(.ethics, 5)],
        blueprintSource: "AMC MCQ examination specifications (amc.org.au): areas as published, proportions ours",
        blueprintIsApproximate: true,
        sections: [MockSectionSpec(title: "CAT MCQ", questions: 150, minutes: 210)], sitsBlockwise: false, sitsSeparately: false,
        paperNote: "150 questions (120 scored) in 3.5 hours, computer-adaptive.",
        passMark: 0.60, passNote: "A scaled score (pass 250 on a 0-500 scale). The percent here is a rough guide.",
        negativeMarking: nil, exemplars: .medqaStep23, accuracyStrictness: 0.3, formatConfirmed: true)

    // MARK: India

    /// NEET-PG (NBEMS, natboard.edu.in information bulletin): 200 MCQs in
    /// 3.5 hours, four options, +4 / -1. The bulletin's subject distribution
    /// is "indicative"; ours, out of 200: anatomy 10, physiology 10,
    /// biochemistry 10, pathology 14, pharmacology 14, microbiology 13,
    /// forensic 6, PSM 16, medicine 25 (split by system), surgery 25, OBG 17,
    /// paediatrics 8, ENT 6, ophthalmology 6, orthopaedics 6, anaesthesia 3,
    /// radiology 3, dermatology 4, psychiatry 4.
    static let neetBlueprint: [BlueprintShare] = [
        s(.anatomy, 10), s(.physiology, 10), s(.biochemistry, 10), s(.pathology, 14), s(.pharmacology, 14),
        s(.microbiology, 13), s(.forensic, 6), s(.community, 16, "Social and preventive medicine"),
        s(.cardio, 4), s(.resp, 3), s(.gi, 3), s(.endocrine, 3), s(.renal, 3), s(.neuro, 3), s(.heme, 3), s(.id, 3),
        s(.surgery, 25), s(.obstetrics, 9), s(.gynaecology, 8), s(.peds, 8), s(.ent, 6), s(.ophthalmology, 6),
        s(.orthopaedics, 6), s(.anaesthesia, 3), s(.radiology, 3), s(.derm, 4), s(.psychiatry, 4)]

    static let neetpg = TargetExam(
        id: "neetpg", name: "NEET-PG", shortName: "NEET-PG", region: .india, family: .general,
        options: 4, stemWords: 8...60,
        leadIns: "direct one-line recall (\"drug of choice for...\", \"most common site of...\", \"all of the following are true EXCEPT\"), short clinical one-liners, investigation of choice",
        conventions: indiaUnits, recallShare: 0.6,
        blueprint: neetBlueprint,
        blueprintSource: "NBEMS NEET-PG information bulletin (natboard.edu.in): indicative subject distribution, approximate",
        blueprintIsApproximate: true,
        sections: [MockSectionSpec(title: "NEET-PG", questions: 200, minutes: 210)], sitsBlockwise: false, sitsSeparately: false,
        paperNote: "200 four-option questions in 3.5 hours; +4 for right, -1 for wrong.",
        passMark: 0.50, passNote: "Qualifying is by percentile (50th for the general category), not a fixed percent.",
        negativeMarking: "-1 of +4 for a wrong answer", exemplars: .medmcqa, accuracyStrictness: 0.1, formatConfirmed: true)

    /// INI-CET (AIIMS New Delhi, aiimsexams.ac.in): 200 MCQs in 3 hours, four
    /// options, -1/3 for a wrong answer. AIIMS publishes no subject
    /// distribution: NEET-PG's is used, approximate.
    static let inicet = TargetExam(
        id: "inicet", name: "INI-CET", shortName: "INI-CET", region: .india, family: .general,
        options: 4, stemWords: 10...80,
        leadIns: "short clinical one-liners and direct recall, drug of choice, investigation of choice, next step",
        conventions: indiaUnits, recallShare: 0.5,
        blueprint: neetBlueprint,
        blueprintSource: "No published distribution: NEET-PG's, approximate",
        blueprintIsApproximate: true,
        sections: [MockSectionSpec(title: "INI-CET", questions: 200, minutes: 180)], sitsBlockwise: false, sitsSeparately: false,
        paperNote: "200 four-option questions in 3 hours; a third of a mark off for a wrong answer.",
        passMark: 0.50, passNote: "Qualifying is by percentile (50th for the general category).",
        negativeMarking: "-1/3 for a wrong answer", exemplars: .medmcqa, accuracyStrictness: 0.1, formatConfirmed: true)

    /// FMGE (NBEMS information bulletin): 300 MCQs in two parts of 150, 150
    /// minutes each, four options, no negative marking, pass 150/300. Subject
    /// distribution out of 300 as the bulletin gives it (medicine split by
    /// system by us); it adds to 295, normalised.
    static let fmge = TargetExam(
        id: "fmge", name: "FMGE", shortName: "FMGE", region: .india, family: .general,
        options: 4, stemWords: 8...50,
        leadIns: "direct one-line recall, drug of choice, most common cause, investigation of choice",
        conventions: indiaUnits, recallShare: 0.6,
        blueprint: [s(.anatomy, 17), s(.physiology, 17), s(.biochemistry, 17), s(.pathology, 13), s(.microbiology, 13),
                    s(.pharmacology, 13), s(.forensic, 10), s(.community, 30, "Community medicine"),
                    s(.cardio, 5), s(.resp, 4), s(.gi, 4), s(.endocrine, 4), s(.renal, 3), s(.neuro, 4), s(.heme, 3), s(.id, 6),
                    s(.psychiatry, 5), s(.derm, 5), s(.surgery, 32), s(.orthopaedics, 5), s(.anaesthesia, 5), s(.radiology, 5),
                    s(.peds, 15), s(.ophthalmology, 15), s(.ent, 15), s(.obstetrics, 15), s(.gynaecology, 15)],
        blueprintSource: "NBEMS FMGE information bulletin (natboard.edu.in): subject-wise questions, approximate",
        blueprintIsApproximate: true,
        sections: [MockSectionSpec(title: "Part A", questions: 150, minutes: 150),
                   MockSectionSpec(title: "Part B", questions: 150, minutes: 150)],
        sitsBlockwise: false, sitsSeparately: true,
        paperNote: "300 four-option questions in two parts of 150 minutes each, on one day. No negative marking.",
        passMark: 0.50, passNote: "150 out of 300 to pass.",
        negativeMarking: nil, exemplars: .medmcqa, accuracyStrictness: 0.1, formatConfirmed: true)

    // MARK: Saudi Arabia and the Gulf

    /// SMLE (Saudi Commission for Health Specialties, scfhs.org.sa, sat at
    /// Prometric): the SCFHS blueprint weights medicine, surgery, paediatrics
    /// and obstetrics & gynaecology, with basic sciences applied within them.
    /// The split and the paper here are approximate - check the current SCFHS
    /// candidate guide.
    static let smle = TargetExam(
        id: "smle", name: "SMLE (Saudi Medical Licensing Exam)", shortName: "SMLE", region: .gulf, family: .general,
        options: 4, stemWords: 30...100,
        leadIns: "most likely diagnosis, most appropriate next step, most appropriate management, best initial investigation",
        conventions: intlUnits, recallShare: 0.2,
        blueprint: [s(.cardio, 5), s(.resp, 4), s(.gi, 4), s(.endocrine, 4), s(.renal, 3), s(.neuro, 3), s(.heme, 2), s(.id, 3),
                    s(.psychiatry, 2), s(.surgery, 12), s(.orthopaedics, 3), s(.ent, 2), s(.ophthalmology, 2), s(.emergency, 5),
                    s(.peds, 20), s(.obstetrics, 10), s(.gynaecology, 10), s(.ethics, 5, "Ethics and professionalism")],
        blueprintSource: "SCFHS SMLE blueprint (scfhs.org.sa): disciplines as published, split approximate",
        blueprintIsApproximate: true,
        sections: blocks(4, questions: 75, minutes: 90, name: "Section"), sitsBlockwise: true, sitsSeparately: false,
        paperNote: "About 300 four-option questions in timed sections at a Prometric centre; check the current SCFHS guide.",
        passMark: 0.60, passNote: "A scaled score with a pass mark set by SCFHS. About 60% is a rough guide.",
        negativeMarking: nil, exemplars: .medqaStep23, accuracyStrictness: 0.2, formatConfirmed: false)

    /// The Gulf regulators' general-practitioner licensing exams (Prometric):
    /// no public blueprint gives percentages; this is OUR general-practice
    /// weighting, the same for each.
    static let gulfBlueprint: [BlueprintShare] = [
        s(.cardio, 6), s(.resp, 5), s(.gi, 5), s(.endocrine, 5), s(.renal, 3), s(.neuro, 4), s(.heme, 2), s(.id, 5),
        s(.surgery, 12), s(.emergency, 8), s(.peds, 13), s(.obstetrics, 7), s(.gynaecology, 6), s(.psychiatry, 5),
        s(.derm, 3), s(.ent, 2), s(.ophthalmology, 2), s(.orthopaedics, 3), s(.ethics, 2), s(.community, 2)]

    private static func gulf(_ id: String, _ name: String, _ short: String, _ body: String) -> TargetExam {
        TargetExam(
            id: id, name: name, shortName: short, region: .gulf, family: .general,
            options: 4, stemWords: 30...100,
            leadIns: "most likely diagnosis, most appropriate next step, most appropriate management",
            conventions: intlUnits, recallShare: 0.2,
            blueprint: gulfBlueprint,
            blueprintSource: "\(body): no published percentages; our general-practice weighting",
            blueprintIsApproximate: true,
            sections: [MockSectionSpec(title: short, questions: 150, minutes: 180)], sitsBlockwise: false, sitsSeparately: false,
            paperNote: "A Prometric computer-based exam, typically 100-150 four-option questions in 2.5-3 hours depending on the licence category; check with \(body).",
            passMark: 0.60, passNote: "Commonly reported as 60%; set by \(body).",
            negativeMarking: nil, exemplars: .medqaStep23, accuracyStrictness: 0.2, formatConfirmed: false)
    }

    static let dha: TargetExam = gulf("dha", "DHA licensing exam (Dubai)", "DHA", "the Dubai Health Authority")
    static let doh: TargetExam = gulf("doh", "DOH licensing exam (Abu Dhabi, formerly HAAD)", "DOH", "the Department of Health Abu Dhabi")
    static let mohap: TargetExam = gulf("mohap", "MOHAP licensing exam (UAE)", "MOHAP", "the UAE Ministry of Health and Prevention")
    static let qchp: TargetExam = gulf("qchp", "QCHP / DHP licensing exam (Qatar)", "QCHP", "Qatar's Department of Healthcare Professions")
    static let omsb: TargetExam = gulf("omsb", "OMSB licensing exam (Oman)", "OMSB", "the Oman Medical Specialty Board")

    // MARK: Egypt

    /// The Egyptian Medical Licensing Exam for new graduates (announced by the
    /// Supreme Council of Universities / Ministry of Health): its full format
    /// and blueprint are not published in detail. This is a general clinical
    /// single-best-answer blueprint, four options, marked unconfirmed.
    /// (The Egyptian Fellowship's written exams are specialty by specialty
    /// with no public blueprint, so they are not listed.)
    static let emle = TargetExam(
        id: "emle", name: "Egyptian Medical Licensing Exam", shortName: "Egypt MLE", region: .egypt, family: .general,
        options: 4, stemWords: 20...90,
        leadIns: "most likely diagnosis, most appropriate next step, most appropriate management, direct recall",
        conventions: "SI units, international generic drug names, and current guidelines as taught in Egyptian faculties of medicine", recallShare: 0.3,
        blueprint: [s(.cardio, 6), s(.resp, 5), s(.gi, 5), s(.endocrine, 5), s(.renal, 4), s(.neuro, 4), s(.heme, 3), s(.id, 5),
                    s(.surgery, 14), s(.emergency, 5), s(.peds, 13), s(.obstetrics, 8), s(.gynaecology, 7), s(.psychiatry, 3),
                    s(.pharmacology, 5), s(.community, 5, "Community medicine"), s(.ethics, 3)],
        blueprintSource: "Not published in detail: a general clinical blueprint, ours",
        blueprintIsApproximate: true,
        sections: [MockSectionSpec(title: "Paper", questions: 100, minutes: 120)], sitsBlockwise: false, sitsSeparately: false,
        paperNote: "The format is not fully published: practise at about a question every 70 seconds and check the official announcements.",
        passMark: 0.60, passNote: "Not published; 60% is a placeholder.",
        negativeMarking: nil, exemplars: .medqaStep23, accuracyStrictness: 0.2, formatConfirmed: false)

    // MARK: International

    /// IFOM Clinical Science Examination (NBME, nbme.org): 160 items in four
    /// sections; content medicine 30-40%, surgery 15-20%, paediatrics
    /// 15-20%, obstetrics and gynaecology 10-15%, psychiatry 10-15% (our
    /// reading of NBME's outline; midpoints, medicine split by system).
    static let ifom = TargetExam(
        id: "ifom", name: "IFOM Clinical Science (NBME)", shortName: "IFOM", region: .international, family: .general,
        options: 5, stemWords: 90...200,
        leadIns: "most likely diagnosis, next best step in management, most appropriate pharmacotherapy",
        conventions: "SI units with conventional units alongside, and current international guidelines", recallShare: 0.05,
        blueprint: [s(.cardio, 6), s(.resp, 5), s(.gi, 5), s(.endocrine, 4), s(.renal, 4), s(.neuro, 4), s(.heme, 3), s(.id, 4),
                    s(.surgery, 17.5), s(.peds, 17.5), s(.obstetrics, 6.5), s(.gynaecology, 6), s(.psychiatry, 12.5)],
        blueprintSource: "NBME IFOM Clinical Science content outline (nbme.org): midpoints, approximate",
        blueprintIsApproximate: true,
        sections: blocks(4, questions: 40, minutes: 65, name: "Section"), sitsBlockwise: true, sitsSeparately: false,
        paperNote: "160 questions in four sections, about 4.5 hours in all.",
        passMark: 0.60, passNote: "Scaled scores; the pass standard is set by whoever uses the exam.",
        negativeMarking: nil, exemplars: .medqaStep23, accuracyStrictness: 0.4, formatConfirmed: true)
}
