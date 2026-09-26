import Foundation

// The Ward pocket's clinical scores: each one's items and points, its
// interpretation bands and where it comes from, as published. MELD-Na is a
// formula rather than a table, so it lives with the calculators
// (WardPocket.swift, WardCalc.meldNa) and is listed beside these.
//
// For learning only. Every table here is checked item by item and band by
// band in Tests/WardPocketTests.swift.
//
// Foundation only, so the tables can be tested on Linux.

/// One answer to an item and what it scores.
struct WardChoice: Hashable {
    let label: String
    let points: Double
}

/// One item of a score: yes/no, or one of several answers.
struct WardItem: Identifiable, Hashable {
    let id: String
    let label: String
    let choices: [WardChoice]

    /// A plain yes/no item: shown as a switch rather than a list.
    var isYesNo: Bool { choices.count == 2 && choices[0].label == "No" && choices[0].points == 0 }

    var maxPoints: Double { choices.map(\.points).max() ?? 0 }
    var minPoints: Double { choices.map(\.points).min() ?? 0 }
}

/// A range of totals and what it means. Both ends are included.
struct WardBand: Hashable {
    let low: Double
    let high: Double
    let title: String
    let detail: String

    func contains(_ total: Double) -> Bool { total >= low - 1e-9 && total <= high + 1e-9 }
}

/// A rule outside the total: any one item scoring `points` or more, while
/// the total is below `below`, gives `band` instead (NEWS2's single red score).
struct WardRedFlag: Hashable {
    let points: Double
    let below: Double
    let band: WardBand
}

/// A clinical score: items, bands, source.
struct WardScore: Identifiable, Hashable {
    let id: String
    let name: String
    /// What it is for, in one line.
    let purpose: String
    let items: [WardItem]
    let bands: [WardBand]
    let source: String
    var note: String = ""
    var redFlag: WardRedFlag?

    /// The total for these answers (item id to choice index; an item left
    /// out counts as its first answer).
    func total(_ picks: [String: Int]) -> Double {
        var sum: Double = 0
        for item in items {
            let index: Int = picks[item.id] ?? 0
            let safe: Int = min(max(index, 0), item.choices.count - 1)
            sum += item.choices[safe].points
        }
        return sum
    }

    func band(for total: Double) -> WardBand? { bands.first { $0.contains(total) } }

    /// What these answers mean, the red-flag rule included.
    func verdict(_ picks: [String: Int]) -> WardBand? {
        let sum: Double = total(picks)
        if let flag = redFlag, sum < flag.below, highestItem(picks) >= flag.points { return flag.band }
        return band(for: sum)
    }

    private func highestItem(_ picks: [String: Int]) -> Double {
        var top: Double = 0
        for item in items {
            let index: Int = min(max(picks[item.id] ?? 0, 0), item.choices.count - 1)
            top = max(top, item.choices[index].points)
        }
        return top
    }

    var lowest: Double { items.reduce(0) { $0 + $1.minPoints } }
    var highest: Double { items.reduce(0) { $0 + $1.maxPoints } }

    /// Every total the items can make.
    var reachableTotals: Set<Double> {
        var sums: Set<Double> = [0]
        for item in items {
            var next: Set<Double> = []
            for s in sums {
                for c in item.choices { next.insert(s + c.points) }
            }
            sums = next
        }
        return sums
    }

    /// The material for "Practise this".
    var practiceNotes: String {
        var lines: [String] = []
        lines.append("Write exam questions that test the \(name): \(purpose) Give a vignette with the findings needed to score it, and ask for the score, its meaning or the next step.")
        for item in items {
            let answers: [String] = item.choices.map { $0.label + " = " + WardScores.points($0.points) }
            lines.append(item.label + ": " + answers.joined(separator: "; "))
        }
        for band in bands {
            let range: String = WardScores.points(band.low) + " to " + WardScores.points(band.high)
            lines.append(range + ": " + band.title + ". " + band.detail)
        }
        if !note.isEmpty { lines.append(note) }
        lines.append("Source: " + source)
        return lines.joined(separator: "\n")
    }
}

/// What the Scores tab lists: a table score, or MELD-Na's formula.
enum WardScoreEntry: Identifiable, Hashable {
    case table(WardScore)
    case formula(WardCalc)

    var id: String {
        switch self {
        case .table(let score): return score.id
        case .formula(let calc): return calc.rawValue
        }
    }

    var name: String {
        switch self {
        case .table(let score): return score.name
        case .formula(let calc): return calc.title
        }
    }
}

enum WardScores {

    /// "2", "1.5", "\u{2212}1".
    static func points(_ x: Double) -> String {
        let whole: Bool = x == x.rounded()
        let text: String = whole ? String(Int(x)) : WardPocket.format(x, places: 1)
        return text.replacingOccurrences(of: "-", with: "\u{2212}")
    }

    // MARK: building blocks

    static func c(_ label: String, _ points: Double) -> WardChoice { WardChoice(label: label, points: points) }

    static func yes(_ id: String, _ label: String, _ points: Double = 1) -> WardItem {
        WardItem(id: id, label: label, choices: [c("No", 0), c("Yes", points)])
    }

    static func pick(_ id: String, _ label: String, _ choices: [WardChoice]) -> WardItem {
        WardItem(id: id, label: label, choices: choices)
    }

    static func band(_ low: Double, _ high: Double, _ title: String, _ detail: String) -> WardBand {
        WardBand(low: low, high: high, title: title, detail: detail)
    }

    /// In the order the Scores tab lists them, MELD-Na after Child-Pugh.
    static var entries: [WardScoreEntry] {
        var out: [WardScoreEntry] = all.map { .table($0) }
        let after: Int = (all.firstIndex { $0.id == "childPugh" } ?? all.count - 1) + 1
        out.insert(.formula(.meldNa), at: after)
        return out
    }

    static let all: [WardScore] = [gcs, wellsDVT, wellsPE, perc, curb65, qsofa, chads, hasbled, childPugh,
                                   centor, blatchford, ranson, apgar, alvarado, news2, timi, heart, bishop, abcd2]

    static func named(_ id: String) -> WardScore? { all.first { $0.id == id } }

    // MARK: - neurology and trauma

    /// Teasdale G, Jennett B. Lancet 1974;2:81; the current wording from
    /// Teasdale G et al. Lancet Neurol 2014;13:844.
    static let gcs = WardScore(
        id: "gcs", name: "Glasgow Coma Scale",
        purpose: "Level of consciousness, from the best eye, verbal and motor responses.",
        items: [
            pick("eye", "Eye opening", [c("Spontaneous", 4), c("To sound", 3), c("To pressure", 2), c("None", 1)]),
            pick("verbal", "Verbal response", [c("Orientated", 5), c("Confused", 4), c("Words", 3), c("Sounds", 2), c("None", 1)]),
            pick("motor", "Motor response", [c("Obeys commands", 6), c("Localising", 5), c("Normal flexion (withdraws)", 4),
                                             c("Abnormal flexion", 3), c("Extension", 2), c("None", 1)])
        ],
        bands: [
            band(3, 8, "Severe", "8 or less: coma; the airway may not be protected"),
            band(9, 12, "Moderate", "9\u{2013}12"),
            band(13, 15, "Mild", "13\u{2013}15")
        ],
        source: "Teasdale G, Jennett B. Lancet 1974;2:81; Teasdale G et al. Lancet Neurol 2014;13:844.",
        note: "Report the parts as well as the total (E4 V5 M6). A part that cannot be tested (intubated, eyes swollen) is recorded as NT, not scored as 1. The mild/moderate/severe bands are the usual head-injury classification.")

    /// Johnston SC et al. Lancet 2007;369:283.
    static let abcd2 = WardScore(
        id: "abcd2", name: "ABCD\u{00B2} score",
        purpose: "Short-term stroke risk after a transient ischaemic attack.",
        items: [
            yes("age", "Age 60 or over"),
            yes("bp", "BP 140/90 mmHg or higher at first assessment"),
            pick("clinical", "Clinical features", [c("Other", 0), c("Speech disturbance without weakness", 1), c("Unilateral weakness", 2)]),
            pick("duration", "Duration", [c("Under 10 minutes", 0), c("10\u{2013}59 minutes", 1), c("60 minutes or more", 2)]),
            yes("diabetes", "Diabetes")
        ],
        bands: [
            band(0, 3, "Low risk", "2-day stroke risk about 1.0%"),
            band(4, 5, "Moderate risk", "2-day stroke risk about 4.1%"),
            band(6, 7, "High risk", "2-day stroke risk about 8.1%")
        ],
        source: "Johnston SC et al. Lancet 2007;369:283.",
        note: "NICE (NG128, 2019) no longer uses ABCD\u{00B2} to triage: everyone with a suspected TIA is seen by a specialist within 24 hours. It still appears in exams.")

    // MARK: - venous thromboembolism

    /// Wells PS et al. N Engl J Med 2003;349:1227 (the two-level score with
    /// previous DVT).
    static let wellsDVT = WardScore(
        id: "wellsDVT", name: "Wells score for DVT",
        purpose: "Clinical probability of a deep vein thrombosis.",
        items: [
            yes("cancer", "Active cancer (treatment ongoing, within 6 months, or palliative)"),
            yes("paralysis", "Paralysis, paresis or recent plaster immobilisation of the leg"),
            yes("bedridden", "Bedridden 3 days or more, or major surgery within 12 weeks"),
            yes("tender", "Localised tenderness along the deep veins"),
            yes("leg", "Entire leg swollen"),
            yes("calf", "Calf swelling 3 cm or more than the other leg (10 cm below the tibial tuberosity)"),
            yes("pitting", "Pitting oedema confined to the symptomatic leg"),
            yes("collateral", "Collateral superficial veins (not varicose)"),
            yes("previous", "Previously documented DVT"),
            yes("alternative", "An alternative diagnosis at least as likely as DVT", -2)
        ],
        bands: [
            band(-2, 1, "DVT unlikely", "1 or less: D-dimer; if positive, proximal leg ultrasound"),
            band(2, 9, "DVT likely", "2 or more: proximal leg ultrasound (within 4 hours, or interim anticoagulation)")
        ],
        source: "Wells PS et al. N Engl J Med 2003;349:1227; NICE NG158 (2020).",
        note: "The older three-level version (Wells 1997): 0 or less low, 1\u{2013}2 moderate, 3 or more high probability.")

    /// Wells PS et al. Thromb Haemost 2000;83:416.
    static let wellsPE = WardScore(
        id: "wellsPE", name: "Wells score for PE",
        purpose: "Clinical probability of a pulmonary embolism.",
        items: [
            yes("dvt", "Clinical signs and symptoms of DVT", 3),
            yes("likely", "PE is the most likely diagnosis (an alternative is less likely)", 3),
            yes("hr", "Heart rate over 100/min", 1.5),
            yes("immobile", "Immobilisation 3 days or more, or surgery in the previous 4 weeks", 1.5),
            yes("previous", "Previous DVT or PE", 1.5),
            yes("haemoptysis", "Haemoptysis"),
            yes("cancer", "Malignancy (treatment within 6 months, or palliative)")
        ],
        bands: [
            band(0, 4, "PE unlikely", "4 or less: D-dimer; if positive, CT pulmonary angiogram"),
            band(4.5, 12.5, "PE likely", "More than 4: CT pulmonary angiogram (interim anticoagulation if delayed)")
        ],
        source: "Wells PS et al. Thromb Haemost 2000;83:416; NICE NG158 (2020).",
        note: "The three-level version: below 2 low, 2\u{2013}6 moderate, above 6 high probability.")

    /// Kline JA et al. J Thromb Haemost 2004;2:1247.
    static let perc = WardScore(
        id: "perc", name: "PERC rule",
        purpose: "Rules out PE without a D-dimer when the pre-test probability is already low.",
        items: [
            yes("age", "Age 50 or over"),
            yes("hr", "Heart rate 100/min or more"),
            yes("sat", "SaO\u{2082} below 95% on air"),
            yes("leg", "Unilateral leg swelling"),
            yes("haemoptysis", "Haemoptysis"),
            yes("surgery", "Surgery or trauma within 4 weeks (needing a general anaesthetic or admission)"),
            yes("previous", "Previous PE or DVT"),
            yes("hormones", "Hormone use (oral contraceptive, HRT or oestrogen)")
        ],
        bands: [
            band(0, 0, "PERC negative", "No criteria: with a low clinical probability (under 15%), PE is ruled out without testing"),
            band(1, 8, "PERC positive", "Any criterion: PERC cannot rule PE out; go on to Wells and D-dimer")
        ],
        source: "Kline JA et al. J Thromb Haemost 2004;2:1247.",
        note: "Use only when the clinician\u{2019}s gestalt already puts the probability of PE below 15%.")

    // MARK: - infection and sepsis

    /// Lim WS et al. Thorax 2003;58:377.
    static let curb65 = WardScore(
        id: "curb65", name: "CURB-65",
        purpose: "Severity of community-acquired pneumonia, for where to treat it.",
        items: [
            yes("confusion", "Confusion (new)"),
            yes("urea", "Urea over 7 mmol/L (BUN over 19 mg/dL)"),
            yes("rr", "Respiratory rate 30/min or more"),
            yes("bp", "Systolic BP below 90 or diastolic 60 mmHg or less"),
            yes("age", "Age 65 or over")
        ],
        bands: [
            band(0, 1, "Low severity", "30-day mortality about 1.5%: consider treatment at home"),
            band(2, 2, "Moderate severity", "30-day mortality about 9.2%: consider hospital treatment"),
            band(3, 5, "High severity", "30-day mortality about 22%: treat in hospital as severe; with 4\u{2013}5, assess for critical care")
        ],
        source: "Lim WS et al. Thorax 2003;58:377; Lim WS et al. BTS CAP guideline, Thorax 2009;64 Suppl 3:iii1.",
        note: "CRB-65 (without urea) is the version for the community.")

    /// Seymour CW et al. JAMA 2016;315:762; Singer M et al. JAMA 2016;315:801.
    static let qsofa = WardScore(
        id: "qsofa", name: "qSOFA",
        purpose: "Bedside prompt for sepsis with a poor outcome, outside intensive care.",
        items: [
            yes("rr", "Respiratory rate 22/min or more"),
            yes("mentation", "Altered mentation (GCS below 15)"),
            yes("sbp", "Systolic BP 100 mmHg or less")
        ],
        bands: [
            band(0, 1, "Not positive", "0\u{2013}1: does not rule sepsis out"),
            band(2, 3, "qSOFA positive", "2 or more: higher risk of death or a long ICU stay; look for organ dysfunction")
        ],
        source: "Seymour CW et al. JAMA 2016;315:762; Singer M et al. (Sepsis-3) JAMA 2016;315:801.",
        note: "The Surviving Sepsis Campaign (2021) recommends against qSOFA alone as a screening tool, compared with SIRS, NEWS or MEWS.")

    /// Centor RM et al. Med Decis Making 1981;1:239; McIsaac WJ et al. CMAJ
    /// 1998;158:75.
    static let centor = WardScore(
        id: "centor", name: "Centor score (McIsaac)",
        purpose: "Likelihood of group A streptococcal pharyngitis.",
        items: [
            yes("temp", "Temperature over 38 \u{00B0}C"),
            yes("cough", "Cough absent"),
            yes("nodes", "Tender or swollen anterior cervical nodes"),
            yes("tonsils", "Tonsillar swelling or exudate"),
            pick("age", "Age (McIsaac)", [c("15\u{2013}44 years", 0), c("3\u{2013}14 years", 1), c("45 or over", -1)])
        ],
        bands: [
            band(-1, 0, "Very low", "Strep about 1\u{2013}2.5%: no test, no antibiotic"),
            band(1, 1, "Low", "Strep about 5\u{2013}10%: no test, no antibiotic"),
            band(2, 2, "Intermediate", "Strep about 11\u{2013}17%: test (rapid antigen or culture)"),
            band(3, 3, "Intermediate", "Strep about 28\u{2013}35%: test (rapid antigen or culture)"),
            band(4, 5, "High", "Strep about 51\u{2013}53%: test, or treat empirically")
        ],
        source: "Centor RM et al. Med Decis Making 1981;1:239; McIsaac WJ et al. CMAJ 1998;158:75 and JAMA 2004;291:1587.",
        note: "NICE (NG84) uses FeverPAIN or Centor without the age item: Centor 3\u{2013}4 suggests a back-up or immediate antibiotic.")

    // MARK: - cardiology

    /// Lip GYH et al. Chest 2010;137:263.
    static let chads = WardScore(
        id: "chads", name: "CHA\u{2082}DS\u{2082}-VASc",
        purpose: "Stroke risk in non-valvular atrial fibrillation.",
        items: [
            yes("chf", "Congestive heart failure (or LV dysfunction)"),
            yes("htn", "Hypertension"),
            pick("age", "Age", [c("Under 65", 0), c("65\u{2013}74", 1), c("75 or over", 2)]),
            yes("dm", "Diabetes"),
            yes("stroke", "Stroke, TIA or thromboembolism", 2),
            yes("vascular", "Vascular disease (previous MI, peripheral arterial disease, aortic plaque)"),
            yes("female", "Female sex")
        ],
        bands: [
            band(0, 0, "Low risk", "No anticoagulation"),
            band(1, 1, "Low to moderate", "A man: consider anticoagulation. A woman scoring 1 for sex alone: low risk, no anticoagulation"),
            band(2, 2, "Moderate", "A man: anticoagulation recommended. A woman: consider anticoagulation"),
            band(3, 9, "High risk", "Anticoagulation recommended (weigh the bleeding risk, HAS-BLED)")
        ],
        source: "Lip GYH et al. Chest 2010;137:263; ESC AF guideline 2020 (Hindricks G et al. Eur Heart J 2021;42:373); NICE NG196 (2021).",
        note: "The ESC 2024 guideline drops the sex point (CHA\u{2082}DS\u{2082}-VA): anticoagulation recommended from 2, considered at 1.")

    /// Pisters R et al. Chest 2010;138:1093.
    static let hasbled = WardScore(
        id: "hasbled", name: "HAS-BLED",
        purpose: "Major bleeding risk on anticoagulation for atrial fibrillation.",
        items: [
            yes("htn", "Hypertension: uncontrolled, systolic over 160 mmHg"),
            yes("renal", "Abnormal renal function: dialysis, transplant, or creatinine 200 \u{00B5}mol/L (2.26 mg/dL) or more"),
            yes("liver", "Abnormal liver function: cirrhosis, or bilirubin over 2\u{00D7} and AST/ALT/ALP over 3\u{00D7} normal"),
            yes("stroke", "Stroke"),
            yes("bleeding", "Bleeding history or predisposition"),
            yes("inr", "Labile INR (time in range below 60%)"),
            yes("elderly", "Elderly: over 65"),
            yes("drugs", "Drugs: antiplatelets or NSAIDs"),
            yes("alcohol", "Alcohol: 8 or more drinks a week")
        ],
        bands: [
            band(0, 2, "Low to moderate", "Bleeding risk not high"),
            band(3, 9, "High risk", "3 or more: correct what can be corrected and review more often \u{2014} not by itself a reason to withhold anticoagulation")
        ],
        source: "Pisters R et al. Chest 2010;138:1093; ESC AF guideline 2020.")

    /// Antman EM et al. JAMA 2000;284:835.
    static let timi = WardScore(
        id: "timi", name: "TIMI score (UA/NSTEMI)",
        purpose: "Short-term risk in unstable angina or NSTEMI.",
        items: [
            yes("age", "Age 65 or over"),
            yes("risk", "3 or more CAD risk factors (family history, hypertension, high cholesterol, diabetes, current smoker)"),
            yes("known", "Known coronary stenosis of 50% or more"),
            yes("aspirin", "Aspirin taken in the past 7 days"),
            yes("angina", "Severe angina: 2 or more episodes in 24 hours"),
            yes("st", "ST deviation of 0.5 mm or more"),
            yes("marker", "Raised cardiac marker")
        ],
        bands: [
            band(0, 1, "Low", "14-day death, MI or urgent revascularisation about 4.7%"),
            band(2, 2, "Low", "About 8.3%"),
            band(3, 3, "Intermediate", "About 13.2%"),
            band(4, 4, "Intermediate", "About 19.9%"),
            band(5, 5, "High", "About 26.2%"),
            band(6, 7, "High", "About 40.9%")
        ],
        source: "Antman EM et al. JAMA 2000;284:835.")

    /// Six AJ et al. Neth Heart J 2008;16:191; Backus BE et al. Int J
    /// Cardiol 2013;168:2153.
    static let heart = WardScore(
        id: "heart", name: "HEART score",
        purpose: "Major adverse cardiac events within 6 weeks, for chest pain in the emergency department.",
        items: [
            pick("history", "History", [c("Slightly suspicious", 0), c("Moderately suspicious", 1), c("Highly suspicious", 2)]),
            pick("ecg", "ECG", [c("Normal", 0), c("Non-specific repolarisation change", 1), c("Significant ST deviation", 2)]),
            pick("age", "Age", [c("Under 45", 0), c("45\u{2013}64", 1), c("65 or over", 2)]),
            pick("risk", "Risk factors", [c("None known", 0), c("1\u{2013}2", 1), c("3 or more, or known atherosclerotic disease", 2)]),
            pick("troponin", "Troponin", [c("At or below the normal limit", 0), c("1\u{2013}3\u{00D7} the normal limit", 1), c("Over 3\u{00D7} the normal limit", 2)])
        ],
        bands: [
            band(0, 3, "Low", "6-week MACE about 0.9\u{2013}1.7%: early discharge may be considered"),
            band(4, 6, "Moderate", "6-week MACE about 12\u{2013}16.6%: admit for observation and further tests"),
            band(7, 10, "High", "6-week MACE about 50\u{2013}65%: early invasive strategy")
        ],
        source: "Six AJ et al. Neth Heart J 2008;16:191; Backus BE et al. Int J Cardiol 2013;168:2153.",
        note: "Risk factors: hypertension, high cholesterol, diabetes, obesity (BMI over 30), smoking (current or stopped within 3 months), family history. Atherosclerotic disease: previous MI, PCI or CABG, stroke or TIA, peripheral arterial disease.")

    // MARK: - gastroenterology and hepatology

    /// Pugh RNH et al. Br J Surg 1973;60:646.
    static let childPugh = WardScore(
        id: "childPugh", name: "Child\u{2013}Pugh score",
        purpose: "Severity of chronic liver disease (cirrhosis).",
        items: [
            pick("bili", "Bilirubin", [c("Below 34 \u{00B5}mol/L (below 2 mg/dL)", 1), c("34\u{2013}50 \u{00B5}mol/L (2\u{2013}3 mg/dL)", 2), c("Above 50 \u{00B5}mol/L (above 3 mg/dL)", 3)]),
            pick("alb", "Albumin", [c("Above 35 g/L (above 3.5 g/dL)", 1), c("28\u{2013}35 g/L (2.8\u{2013}3.5 g/dL)", 2), c("Below 28 g/L (below 2.8 g/dL)", 3)]),
            pick("inr", "INR", [c("Below 1.7", 1), c("1.7\u{2013}2.3", 2), c("Above 2.3", 3)]),
            pick("ascites", "Ascites", [c("None", 1), c("Mild (or controlled with diuretics)", 2), c("Moderate to severe (or refractory)", 3)]),
            pick("enceph", "Encephalopathy", [c("None", 1), c("Grade 1\u{2013}2 (or controlled with treatment)", 2), c("Grade 3\u{2013}4 (or refractory)", 3)])
        ],
        bands: [
            band(5, 6, "Class A", "Well-compensated disease"),
            band(7, 9, "Class B", "Significant functional compromise"),
            band(10, 15, "Class C", "Decompensated disease")
        ],
        source: "Child CG, Turcotte JG. 1964; Pugh RNH et al. Br J Surg 1973;60:646.",
        note: "Commonly quoted survival: about 100% at 1 year and 85% at 2 years for class A, 80% and 60% for B, 45% and 35% for C. MELD-Na predicts short-term mortality better.")

    /// Blatchford O et al. Lancet 2000;356:1318.
    static let blatchford = WardScore(
        id: "blatchford", name: "Glasgow\u{2013}Blatchford score",
        purpose: "Need for intervention in an upper GI bleed, at presentation, before endoscopy.",
        items: [
            pick("urea", "Blood urea", [c("Below 6.5 mmol/L (BUN below 18.2 mg/dL)", 0), c("6.5\u{2013}7.9 mmol/L (BUN 18.2\u{2013}22.3)", 2),
                                        c("8.0\u{2013}9.9 mmol/L (BUN 22.4\u{2013}27.9)", 3), c("10.0\u{2013}24.9 mmol/L (BUN 28\u{2013}69.9)", 4),
                                        c("25 mmol/L or more (BUN 70 or more)", 6)]),
            pick("hb", "Haemoglobin", [c("Men 130 g/L or more; women 120 or more", 0), c("Men 120\u{2013}129 g/L (12.0\u{2013}12.9 g/dL)", 1),
                                        c("Women 100\u{2013}119 g/L (10.0\u{2013}11.9 g/dL)", 1), c("Men 100\u{2013}119 g/L (10.0\u{2013}11.9 g/dL)", 3),
                                        c("Either sex below 100 g/L (below 10 g/dL)", 6)]),
            pick("sbp", "Systolic BP", [c("110 mmHg or more", 0), c("100\u{2013}109", 1), c("90\u{2013}99", 2), c("Below 90", 3)]),
            yes("pulse", "Pulse 100/min or more"),
            yes("melaena", "Presentation with melaena"),
            yes("syncope", "Presentation with syncope", 2),
            yes("liver", "Hepatic disease", 2),
            yes("heart", "Cardiac failure", 2)
        ],
        bands: [
            band(0, 0, "Very low risk", "May be suitable for outpatient management and endoscopy"),
            band(1, 5, "Not low risk", "Admit for endoscopy; some guidelines accept 1 as low risk"),
            band(6, 23, "High risk", "6 or more: over 50% need an intervention (transfusion, endoscopic therapy or surgery)")
        ],
        source: "Blatchford O et al. Lancet 2000;356:1318; Stanley AJ et al. BMJ 2017;356:i6432; NICE CG141.",
        note: "Women with Hb 120\u{2013}129 g/L score 0; the man-only bands apply only to men.")

    /// Ranson JH et al. Surg Gynecol Obstet 1974;139:69 (the admission
    /// criteria, non-gallstone pancreatitis).
    static let ranson = WardScore(
        id: "ranson", name: "Ranson criteria (on admission)",
        purpose: "Severity of acute pancreatitis: the five criteria at admission.",
        items: [
            yes("age", "Age over 55"),
            yes("wbc", "White cells over 16 \u{00D7}10\u{2079}/L"),
            yes("glucose", "Glucose over 11.1 mmol/L (200 mg/dL)"),
            yes("ldh", "LDH over 350 IU/L"),
            yes("ast", "AST over 250 IU/L")
        ],
        bands: [
            band(0, 2, "Fewer than 3", "Severe pancreatitis less likely so far; the 48-hour criteria complete the score"),
            band(3, 5, "3 or more", "Predicts severe pancreatitis")
        ],
        source: "Ranson JH et al. Surg Gynecol Obstet 1974;139:69; Ranson JH. Am J Gastroenterol 1982;77:633.",
        note: "At 48 hours: haematocrit fall over 10 points, urea (BUN) rise over 1.8 mmol/L (5 mg/dL), calcium below 2 mmol/L (8 mg/dL), PaO\u{2082} below 8 kPa (60 mmHg), base deficit over 4, fluid sequestration over 6 L. Across all 11, mortality was about 1% with 0\u{2013}2, 15% with 3\u{2013}4, 40% with 5\u{2013}6 and near 100% with 7 or more. Gallstone pancreatitis (1982) uses age over 70, white cells over 18, glucose over 12.2 mmol/L (220 mg/dL), LDH over 400.")

    /// Alvarado A. Ann Emerg Med 1986;15:557.
    static let alvarado = WardScore(
        id: "alvarado", name: "Alvarado score",
        purpose: "Likelihood of acute appendicitis (MANTRELS).",
        items: [
            yes("migration", "Migration of pain to the right iliac fossa"),
            yes("anorexia", "Anorexia"),
            yes("nausea", "Nausea or vomiting"),
            yes("tender", "Tenderness in the right iliac fossa", 2),
            yes("rebound", "Rebound tenderness"),
            yes("temp", "Temperature 37.3 \u{00B0}C or more"),
            yes("wbc", "White cells over 10 \u{00D7}10\u{2079}/L", 2),
            yes("shift", "Left shift (neutrophils over 75%)")
        ],
        bands: [
            band(0, 4, "Unlikely", "Appendicitis unlikely"),
            band(5, 6, "Possible", "Compatible with appendicitis: observe, image"),
            band(7, 8, "Probable", "Appendicitis probable"),
            band(9, 10, "Very probable", "Appendicitis very probable")
        ],
        source: "Alvarado A. Ann Emerg Med 1986;15:557.")

    // MARK: - acute care

    /// Royal College of Physicians. National Early Warning Score (NEWS) 2,
    /// December 2017. SpO2 scale 1.
    static let news2 = WardScore(
        id: "news2", name: "NEWS2",
        purpose: "Early warning score for acute illness in adults (not in pregnancy or under 16).",
        items: [
            pick("rr", "Respiratory rate (/min)", [c("12\u{2013}20", 0), c("9\u{2013}11", 1), c("21\u{2013}24", 2), c("8 or less", 3), c("25 or more", 3)]),
            pick("spo2", "SpO\u{2082} (scale 1, %)", [c("96 or more", 0), c("94\u{2013}95", 1), c("92\u{2013}93", 2), c("91 or less", 3)]),
            pick("air", "Air or oxygen", [c("Air", 0), c("Oxygen", 2)]),
            pick("sbp", "Systolic BP (mmHg)", [c("111\u{2013}219", 0), c("101\u{2013}110", 1), c("91\u{2013}100", 2), c("90 or less", 3), c("220 or more", 3)]),
            pick("pulse", "Pulse (/min)", [c("51\u{2013}90", 0), c("41\u{2013}50", 1), c("91\u{2013}110", 1), c("111\u{2013}130", 2), c("40 or less", 3), c("131 or more", 3)]),
            pick("acvpu", "Consciousness", [c("Alert", 0), c("New confusion, or responds to voice or pain, or unresponsive", 3)]),
            pick("temp", "Temperature (\u{00B0}C)", [c("36.1\u{2013}38.0", 0), c("35.1\u{2013}36.0", 1), c("38.1\u{2013}39.0", 1), c("39.1 or more", 2), c("35.0 or less", 3)])
        ],
        bands: [
            band(0, 0, "Low", "Routine monitoring, at least 12-hourly"),
            band(1, 4, "Low", "Inform the nurse in charge; at least 4\u{2013}6-hourly"),
            band(5, 6, "Medium", "Key threshold: urgent review by a clinician competent in acute illness; at least hourly"),
            band(7, 20, "High", "Emergency response by a critical-care team; continuous monitoring")
        ],
        source: "Royal College of Physicians. National Early Warning Score (NEWS) 2. London: RCP, 2017.",
        note: "Scale 2 replaces the SpO\u{2082} row for a patient with confirmed hypercapnic respiratory failure and a prescribed target of 88\u{2013}92% (not built in here).",
        redFlag: WardRedFlag(points: 3, below: 5,
                             band: band(3, 4, "Low\u{2013}medium", "A single parameter scoring 3: urgent ward-based review by a clinician; at least hourly")))

    // MARK: - obstetrics and neonates

    /// Apgar V. Curr Res Anesth Analg 1953;32:260.
    static let apgar = WardScore(
        id: "apgar", name: "APGAR score",
        purpose: "A newborn\u{2019}s condition at 1 and 5 minutes after birth.",
        items: [
            pick("appearance", "Appearance (colour)", [c("Pink all over", 2), c("Body pink, hands and feet blue", 1), c("Blue or pale all over", 0)]),
            pick("pulse", "Pulse", [c("100/min or more", 2), c("Below 100/min", 1), c("Absent", 0)]),
            pick("grimace", "Grimace (reflex irritability)", [c("Cries, coughs or pulls away", 2), c("Grimace", 1), c("No response", 0)]),
            pick("activity", "Activity (tone)", [c("Active movement", 2), c("Some flexion", 1), c("Limp", 0)]),
            pick("respiration", "Respiration", [c("Good, strong cry", 2), c("Slow, irregular or weak", 1), c("Absent", 0)])
        ],
        bands: [
            band(0, 3, "Low", "0\u{2013}3"),
            band(4, 6, "Moderately abnormal", "4\u{2013}6"),
            band(7, 10, "Reassuring", "7\u{2013}10")
        ],
        source: "Apgar V. Curr Res Anesth Analg 1953;32:260; AAP/ACOG Committee Opinion 644 (2015).",
        note: "Resuscitation is never delayed for the 1-minute score. A score under 7 at 5 minutes is repeated every 5 minutes to 20 minutes.")

    /// Bishop EH. Obstet Gynecol 1964;24:266.
    static let bishop = WardScore(
        id: "bishop", name: "Bishop score",
        purpose: "How ready the cervix is for induction of labour.",
        items: [
            pick("dilation", "Dilatation (cm)", [c("Closed", 0), c("1\u{2013}2", 1), c("3\u{2013}4", 2), c("5 or more", 3)]),
            pick("effacement", "Effacement (%)", [c("0\u{2013}30", 0), c("40\u{2013}50", 1), c("60\u{2013}70", 2), c("80 or more", 3)]),
            pick("station", "Station", [c("\u{2212}3", 0), c("\u{2212}2", 1), c("\u{2212}1 or 0", 2), c("+1 or +2", 3)]),
            pick("consistency", "Consistency", [c("Firm", 0), c("Medium", 1), c("Soft", 2)]),
            pick("position", "Position", [c("Posterior", 0), c("Mid", 1), c("Anterior", 2)])
        ],
        bands: [
            band(0, 6, "Unfavourable", "6 or less: cervical ripening first (prostaglandin or a balloon)"),
            band(7, 8, "Favourable", "More than 6 (NICE): amniotomy and oxytocin can be considered"),
            band(9, 13, "Very favourable", "More than 8 (ACOG): induction about as likely to succeed as spontaneous labour")
        ],
        source: "Bishop EH. Obstet Gynecol 1964;24:266; NICE NG207 (2021); ACOG Practice Bulletin 107 (2009).")
}
