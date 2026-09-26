import Foundation

// The Ward pocket: the bedside formulas a student meets on the wards and in
// the exam - body size, the anion gap, corrected calcium and sodium,
// osmolality, the A-a gradient, kidney function, MAP, QTc, maintenance fluids,
// a child's weight, a unit converter and MELD-Na. The scores (GCS, Wells,
// CURB-65 and the rest) are in WardPocketScores.swift.
//
// For learning only: every screen that shows these says so (App Store
// guideline 1.4.1). The coefficients are the published ones, each cited
// beside its formula, and checked against worked examples in
// Tests/WardPocketTests.swift.
//
// Foundation only, so every formula can be tested on Linux.

enum WardPocket {
    /// The line every Ward pocket screen carries.
    static let disclaimer: String = "For learning only \u{2014} not for patient care"

    /// A longer form of it, for the foot of a calculator or score.
    static let disclaimerDetail: String = "Built to help you learn how these are worked out and what they mean. It is not a medical device: never use it to make decisions about a real patient."

    /// `x` with `places` decimals ("7.25").
    static func format(_ x: Double, places: Int) -> String {
        guard x.isFinite else { return "\u{2014}" }
        let pattern: String = "%." + String(places) + "f"
        return String(format: pattern, x)
    }

    /// The material for "Practise this": New set writes exam questions from
    /// it with the student's own generation settings.
    static func practiceNotes(for calc: WardCalc) -> String {
        var lines: [String] = []
        lines.append("Write exam questions that test \(calc.title.lowercased()): when it is used, how it is worked out from a vignette's numbers, and what the result means for the next step.")
        lines.append("How it is worked out: " + calc.formula)
        if !calc.note.isEmpty { lines.append(calc.note) }
        lines.append("Source: " + calc.source)
        return lines.joined(separator: "\n\n")
    }
}

// MARK: - units

/// A quantity whose unit is not the same in SI and US conventional units.
/// Values are kept in SI; `usPerSI` is how many US units make one SI unit.
struct WardUnit: Hashable {
    let si: String
    let us: String
    let usPerSI: Double

    func name(us useUS: Bool) -> String { useUS ? us : si }

    /// A value typed in the unit shown, as SI.
    func toSI(_ value: Double, us useUS: Bool) -> Double { useUS ? value / usPerSI : value }

    /// An SI value in the unit shown.
    func fromSI(_ value: Double, us useUS: Bool) -> Double { useUS ? value * usPerSI : value }

    /// A unit that reads the same in both systems.
    static func plain(_ unit: String) -> WardUnit { WardUnit(si: unit, us: unit, usPerSI: 1) }

    // Molar masses: glucose 180.16 g/mol, creatinine 113.12, calcium 40.08,
    // cholesterol 386.65, triolein 885.7, bilirubin 584.66; urea nitrogen is
    // two nitrogens, 28.014 mg per mmol of urea (BUN).
    static let glucose = WardUnit(si: "mmol/L", us: "mg/dL", usPerSI: 18.016)
    static let creatinine = WardUnit(si: "\u{00B5}mol/L", us: "mg/dL", usPerSI: 1 / 88.42)
    static let urea = WardUnit(si: "mmol/L urea", us: "mg/dL BUN", usPerSI: 2.8014)
    static let calcium = WardUnit(si: "mmol/L", us: "mg/dL", usPerSI: 4.008)
    static let cholesterol = WardUnit(si: "mmol/L", us: "mg/dL", usPerSI: 38.67)
    static let triglycerides = WardUnit(si: "mmol/L", us: "mg/dL", usPerSI: 88.57)
    static let bilirubin = WardUnit(si: "\u{00B5}mol/L", us: "mg/dL", usPerSI: 1 / 17.1)
    static let albumin = WardUnit(si: "g/L", us: "g/dL", usPerSI: 0.1)
    /// Sodium, chloride, bicarbonate: the same number, a different name.
    static let electrolyte = WardUnit(si: "mmol/L", us: "mEq/L", usPerSI: 1)
    /// Blood gas tensions: 1 kPa = 7.50062 mmHg.
    static let gas = WardUnit(si: "kPa", us: "mmHg", usPerSI: 7.50062)
}

/// The unit converter's substances.
enum WardSubstance: Int, CaseIterable {
    case glucose, creatinine, urea, calcium, cholesterol, triglycerides

    var name: String {
        switch self {
        case .glucose: return "Glucose"
        case .creatinine: return "Creatinine"
        case .urea: return "Urea / BUN"
        case .calcium: return "Calcium"
        case .cholesterol: return "Cholesterol"
        case .triglycerides: return "Triglycerides"
        }
    }

    var unit: WardUnit {
        switch self {
        case .glucose: return .glucose
        case .creatinine: return .creatinine
        case .urea: return .urea
        case .calcium: return .calcium
        case .cholesterol: return .cholesterol
        case .triglycerides: return .triglycerides
        }
    }
}

// MARK: - the formulas

/// Each formula in the units it was published in.
enum WardFormula {

    /// Body mass index, kg/m\u{00B2}.
    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let metres: Double = heightCm / 100
        return weightKg / (metres * metres)
    }

    /// The WHO adult class of a BMI (WHO Technical Report Series 894, 2000).
    static func bmiClass(_ bmi: Double) -> String {
        if bmi < 18.5 { return "Underweight (below 18.5)" }
        if bmi < 25 { return "Healthy weight (18.5\u{2013}24.9)" }
        if bmi < 30 { return "Overweight (25\u{2013}29.9)" }
        if bmi < 35 { return "Obesity class I (30\u{2013}34.9)" }
        if bmi < 40 { return "Obesity class II (35\u{2013}39.9)" }
        return "Obesity class III (40 or more)"
    }

    /// Body surface area, m\u{00B2}: Mosteller, sqrt(height cm \u{00D7} weight kg / 3600).
    /// Mosteller RD. N Engl J Med 1987;317:1098.
    static func bsaMosteller(weightKg: Double, heightCm: Double) -> Double {
        (heightCm * weightKg / 3600).squareRoot()
    }

    /// Anion gap, Na - (Cl + HCO3), without potassium.
    static func anionGap(sodium: Double, chloride: Double, bicarbonate: Double) -> Double {
        sodium - (chloride + bicarbonate)
    }

    /// The gap corrected for a low albumin: + 0.25 for each g/L of albumin
    /// below 40 (2.5 per g/dL below 4.0). The factor is Figge's (Figge J et
    /// al. Crit Care Med 1998;26:1807); Figge measured from a normal albumin
    /// of 44 g/L, while 40 g/L is the reference MDCalc and most teaching use.
    static func albuminCorrectedGap(_ gap: Double, albuminGL: Double) -> Double {
        gap + 0.25 * (40 - albuminGL)
    }

    /// Adjusted calcium, mmol/L: Ca + 0.02 \u{00D7} (40 - albumin g/L), the same as
    /// Ca + 0.8 \u{00D7} (4.0 - albumin g/dL) in mg/dL - the simplified form of
    /// Payne's regression (Payne RB et al. BMJ 1973;4:643) that is taught.
    static func correctedCalcium(calciumMmol: Double, albuminGL: Double) -> Double {
        calciumMmol + 0.02 * (40 - albuminGL)
    }

    /// Sodium corrected for hyperglycaemia: + `factor` mmol/L for each
    /// 100 mg/dL of glucose above 100. Katz MA. N Engl J Med 1973;289:843
    /// (factor 1.6); Hillier TA et al. Am J Med 1999;106:399 (factor 2.4).
    /// No correction at a glucose of 100 mg/dL (5.6 mmol/L) or below.
    static func correctedSodium(sodium: Double, glucoseMgdl: Double, factor: Double) -> Double {
        let excess: Double = max(0, glucoseMgdl - 100)
        return sodium + factor * excess / 100
    }

    /// Calculated serum osmolality, mOsm/kg: 2Na + glucose + urea, all in
    /// mmol/L (2Na + glucose/18 + BUN/2.8 in mg/dL). Dorwart WV, Chalmers L.
    /// Clin Chem 1975;21:190.
    static func osmolality(sodium: Double, glucoseMmol: Double, ureaMmol: Double) -> Double {
        2 * sodium + glucoseMmol + ureaMmol
    }

    /// Alveolar oxygen, mmHg, from the alveolar gas equation at sea level:
    /// FiO2 \u{00D7} (760 - 47) - PaCO2 / 0.8 (water vapour 47 mmHg at 37 \u{00B0}C,
    /// respiratory quotient 0.8).
    static func alveolarO2(fio2: Double, paco2: Double) -> Double {
        fio2 * (760 - 47) - paco2 / 0.8
    }

    /// The A-a gradient, mmHg.
    static func aaGradient(fio2: Double, pao2: Double, paco2: Double) -> Double {
        alveolarO2(fio2: fio2, paco2: paco2) - pao2
    }

    /// The usual bedside estimate of the upper limit of a normal A-a gradient
    /// breathing air, mmHg: age / 4 + 4.
    static func expectedAaGradient(age: Double) -> Double { age / 4 + 4 }

    /// Creatinine clearance, mL/min: (140 - age) \u{00D7} weight / (72 \u{00D7} Cr mg/dL),
    /// \u{00D7} 0.85 for a woman. Cockcroft DW, Gault MH. Nephron 1976;16:31.
    static func cockcroftGault(age: Double, weightKg: Double, creatinineMgdl: Double, female: Bool) -> Double {
        let men: Double = (140 - age) * weightKg / (72 * creatinineMgdl)
        return female ? men * 0.85 : men
    }

    /// eGFR, mL/min/1.73 m\u{00B2}, by the race-free CKD-EPI creatinine equation
    /// (2021): 142 \u{00D7} min(Scr/\u{03BA}, 1)^\u{03B1} \u{00D7} max(Scr/\u{03BA}, 1)^-1.200 \u{00D7} 0.9938^age
    /// \u{00D7} 1.012 if female; \u{03BA} 0.7 (F) / 0.9 (M), \u{03B1} -0.241 (F) / -0.302 (M).
    /// Inker LA et al. N Engl J Med 2021;385:1737.
    static func ckdEpi2021(age: Double, creatinineMgdl: Double, female: Bool) -> Double {
        let kappa: Double = female ? 0.7 : 0.9
        let alpha: Double = female ? -0.241 : -0.302
        let ratio: Double = creatinineMgdl / kappa
        let low: Double = pow(min(ratio, 1), alpha)
        let high: Double = pow(max(ratio, 1), -1.200)
        let aging: Double = pow(0.9938, age)
        let sex: Double = female ? 1.012 : 1
        return 142 * low * high * aging * sex
    }

    /// The KDIGO 2012 GFR category.
    static func gfrCategory(_ gfr: Double) -> String {
        if gfr >= 90 { return "G1: normal or high (90 or more)" }
        if gfr >= 60 { return "G2: mildly decreased (60\u{2013}89)" }
        if gfr >= 45 { return "G3a: mildly to moderately decreased (45\u{2013}59)" }
        if gfr >= 30 { return "G3b: moderately to severely decreased (30\u{2013}44)" }
        if gfr >= 15 { return "G4: severely decreased (15\u{2013}29)" }
        return "G5: kidney failure (below 15)"
    }

    /// Mean arterial pressure, mmHg: DBP + (SBP - DBP) / 3.
    static func meanArterialPressure(systolic: Double, diastolic: Double) -> Double {
        diastolic + (systolic - diastolic) / 3
    }

    /// QTc, ms, by Bazett: QT / sqrt(RR in s). Bazett HC. Heart 1920;7:353.
    static func qtcBazett(qtMs: Double, heartRate: Double) -> Double {
        let rr: Double = 60 / heartRate
        return qtMs / rr.squareRoot()
    }

    /// QTc, ms, by Fridericia: QT / cube root(RR in s). Fridericia LS. Acta
    /// Med Scand 1920;53:469.
    static func qtcFridericia(qtMs: Double, heartRate: Double) -> Double {
        let rr: Double = 60 / heartRate
        return qtMs / cbrt(rr)
    }

    /// Maintenance fluid, mL/h, by the 4-2-1 rule: 4 mL/kg/h for the first
    /// 10 kg, 2 for the next 10, 1 for each kg above 20. Holliday MA, Segar
    /// WE. Pediatrics 1957;19:823.
    static func maintenancePerHour(weightKg: Double) -> Double {
        let first: Double = min(weightKg, 10)
        let second: Double = min(max(weightKg - 10, 0), 10)
        let rest: Double = max(weightKg - 20, 0)
        return 4 * first + 2 * second + rest
    }

    /// The same rule per day, mL: 100 / 50 / 20 mL/kg/day.
    static func maintenancePerDay(weightKg: Double) -> Double {
        let first: Double = min(weightKg, 10)
        let second: Double = min(max(weightKg - 10, 0), 10)
        let rest: Double = max(weightKg - 20, 0)
        return 100 * first + 50 * second + 20 * rest
    }

    /// A child's weight, kg, by the APLS formulas (Advanced Life Support
    /// Group, APLS 5th edition, 2011): 0-12 months (0.5 \u{00D7} months) + 4;
    /// 1-5 years (2 \u{00D7} years) + 8; 6-12 years (3 \u{00D7} years) + 7. Nil past
    /// 12 years, where the formulas stop. Whole completed years are used.
    static func childWeight(ageMonths: Double) -> Double? {
        guard ageMonths >= 0 else { return nil }
        if ageMonths <= 12 { return 0.5 * ageMonths + 4 }
        let years: Double = (ageMonths / 12).rounded(.down)
        if years <= 5 { return 2 * years + 8 }
        if years <= 12 { return 3 * years + 7 }
        return nil
    }

    /// Which APLS formula `childWeight` used.
    static func childWeightRule(ageMonths: Double) -> String {
        if ageMonths <= 12 { return "0\u{2013}12 months: (0.5 \u{00D7} age in months) + 4" }
        let years: Double = (ageMonths / 12).rounded(.down)
        if years <= 5 { return "1\u{2013}5 years: (2 \u{00D7} age in years) + 8" }
        return "6\u{2013}12 years: (3 \u{00D7} age in years) + 7"
    }

    /// MELD and MELD-Na as UNOS/OPTN computed them from January 2016 to July
    /// 2023 (OPTN policy 9.1; Kim WR et al. N Engl J Med 2008;359:1018).
    /// Bilirubin, INR and creatinine below 1 count as 1; creatinine is
    /// capped at 4, and set to 4 after dialysis twice in the past week;
    /// sodium is held between 125 and 137. MELD(i) = 0.957 ln Cr + 0.378
    /// ln bilirubin + 1.120 ln INR + 0.643, rounded to the tenth and \u{00D7} 10.
    /// Above 11 it becomes MELD(i) + 1.32 (137 - Na) - 0.033 MELD(i) (137 - Na).
    /// The result is a whole number from 6 to 40.
    static func meld(bilirubinMgdl: Double, inr: Double, creatinineMgdl: Double,
                     sodium: Double, dialysis: Bool) -> (meld: Double, meldNa: Double) {
        let bili: Double = max(bilirubinMgdl, 1)
        let clot: Double = max(inr, 1)
        let cr: Double = dialysis ? 4 : min(max(creatinineMgdl, 1), 4)
        let na: Double = min(max(sodium, 125), 137)
        let a: Double = 0.957 * log(cr)
        let b: Double = 0.378 * log(bili)
        let c: Double = 1.120 * log(clot)
        let raw: Double = a + b + c + 0.643
        let initial: Double = (raw * 10).rounded() / 10 * 10
        var withNa: Double = initial
        if initial > 11 {
            let gap: Double = 137 - na
            withNa = initial + 1.32 * gap - 0.033 * initial * gap
        }
        let meld: Double = min(max(initial.rounded(), 6), 40)
        let meldNa: Double = min(max(withNa.rounded(), 6), 40)
        return (meld, meldNa)
    }

    /// Three-month mortality by MELD, hospitalised patients (Wiesner R et al.
    /// Gastroenterology 2003;124:91).
    static func meldMortality(_ score: Double) -> String {
        if score <= 9 { return "9 or less: about 1.9% three-month mortality" }
        if score <= 19 { return "10\u{2013}19: about 6.0% three-month mortality" }
        if score <= 29 { return "20\u{2013}29: about 19.6% three-month mortality" }
        if score <= 39 { return "30\u{2013}39: about 52.6% three-month mortality" }
        return "40 or more: about 71.3% three-month mortality"
    }
}

// MARK: - the calculators

/// One input on a calculator.
struct WardField: Identifiable, Hashable {
    enum Kind: Hashable {
        /// A number, typed in the unit shown and kept in SI.
        case number(WardUnit)
        /// Yes or no, kept as 1 or 0.
        case toggle
        /// One of these, kept as its index.
        case choice([String])
    }

    let id: String
    let label: String
    let kind: Kind
    /// Left empty, the calculator still gives what it can without it.
    var optional: Bool = false
}

/// One line of a calculator's answer: "Anion gap", "18 mmol/L".
struct WardLine: Hashable {
    let label: String
    let value: String
}

/// A calculator's answer: its numbers, and what they mean.
struct WardOutcome: Hashable {
    var lines: [WardLine]
    var verdict: String?
}

/// The Ward pocket's calculators. MELD-Na is listed with the scores.
enum WardCalc: String, CaseIterable, Identifiable {
    case bodySize, anionGap, calcium, sodium, osmolality, aaGradient, crcl, egfr, map, qtc
    case fluids, childWeight, convert, meldNa

    var id: String { rawValue }

    /// Shown in the Calculators tab; MELD-Na is shown in Scores.
    static let calculators: [WardCalc] = allCases.filter { $0 != .meldNa }

    var title: String {
        switch self {
        case .bodySize: return "BMI and body surface area"
        case .anionGap: return "Anion gap"
        case .calcium: return "Corrected calcium"
        case .sodium: return "Corrected sodium for glucose"
        case .osmolality: return "Osmolality and osmolar gap"
        case .aaGradient: return "A\u{2013}a gradient"
        case .crcl: return "Creatinine clearance (Cockcroft\u{2013}Gault)"
        case .egfr: return "eGFR (CKD-EPI 2021)"
        case .map: return "Mean arterial pressure"
        case .qtc: return "QTc (Bazett and Fridericia)"
        case .fluids: return "Maintenance fluids (4-2-1)"
        case .childWeight: return "Child\u{2019}s weight from age"
        case .convert: return "Unit converter"
        case .meldNa: return "MELD-Na"
        }
    }

    var symbol: String {
        switch self {
        case .bodySize: return "figure.stand"
        case .anionGap, .osmolality: return "drop.halffull"
        case .calcium, .sodium: return "testtube.2"
        case .aaGradient: return "lungs"
        case .crcl, .egfr: return "cross.vial"
        case .map: return "heart"
        case .qtc: return "waveform.path.ecg"
        case .fluids: return "ivfluid.bag"
        case .childWeight: return "figure.and.child.holdinghands"
        case .convert: return "arrow.left.arrow.right"
        case .meldNa: return "list.number"
        }
    }

    var fields: [WardField] {
        switch self {
        case .bodySize: return [Self.weight, Self.height]
        case .anionGap:
            return [Self.salt("na", "Sodium"), Self.salt("cl", "Chloride"), Self.salt("hco3", "Bicarbonate"),
                    WardField(id: "alb", label: "Albumin", kind: .number(.albumin), optional: true)]
        case .calcium:
            return [WardField(id: "ca", label: "Total calcium", kind: .number(.calcium)),
                    WardField(id: "alb", label: "Albumin", kind: .number(.albumin))]
        case .sodium:
            return [Self.salt("na", "Sodium"), WardField(id: "glu", label: "Glucose", kind: .number(.glucose))]
        case .osmolality:
            return [Self.salt("na", "Sodium"), WardField(id: "glu", label: "Glucose", kind: .number(.glucose)),
                    WardField(id: "urea", label: "Urea", kind: .number(.urea)),
                    WardField(id: "measured", label: "Measured osmolality", kind: .number(.plain("mOsm/kg")), optional: true)]
        case .aaGradient:
            return [WardField(id: "fio2", label: "FiO\u{2082}", kind: .number(.plain("%"))),
                    WardField(id: "pao2", label: "PaO\u{2082}", kind: .number(.gas)),
                    WardField(id: "paco2", label: "PaCO\u{2082}", kind: .number(.gas)),
                    WardField(id: "age", label: "Age", kind: .number(.plain("years")), optional: true)]
        case .crcl: return [Self.age, Self.weight, Self.female, Self.creatinine]
        case .egfr: return [Self.age, Self.female, Self.creatinine]
        case .map:
            return [WardField(id: "sbp", label: "Systolic", kind: .number(.plain("mmHg"))),
                    WardField(id: "dbp", label: "Diastolic", kind: .number(.plain("mmHg")))]
        case .qtc:
            return [WardField(id: "qt", label: "QT interval", kind: .number(.plain("ms"))),
                    WardField(id: "hr", label: "Heart rate", kind: .number(.plain("/min"))), Self.female]
        case .fluids: return [Self.weight]
        case .childWeight:
            return [WardField(id: "age", label: "Age", kind: .number(.plain(""))),
                    WardField(id: "per", label: "Age in", kind: .choice(["Months", "Years"]))]
        case .convert:
            let names: [String] = WardSubstance.allCases.map(\.name)
            return [WardField(id: "what", label: "Substance", kind: .choice(names)),
                    WardField(id: "dir", label: "Direction", kind: .choice(["SI \u{2192} US", "US \u{2192} SI"])),
                    WardField(id: "value", label: "Value", kind: .number(.plain("")))]
        case .meldNa:
            return [WardField(id: "bili", label: "Bilirubin", kind: .number(.bilirubin)),
                    WardField(id: "inr", label: "INR", kind: .number(.plain(""))), Self.creatinine,
                    Self.salt("na", "Sodium"),
                    WardField(id: "dialysis", label: "Dialysis twice (or 24 h CVVHD) in the past week", kind: .toggle)]
        }
    }

    private static let weight = WardField(id: "wt", label: "Weight", kind: .number(.plain("kg")))
    private static let height = WardField(id: "ht", label: "Height", kind: .number(.plain("cm")))
    private static let age = WardField(id: "age", label: "Age", kind: .number(.plain("years")))
    private static let female = WardField(id: "female", label: "Female", kind: .toggle)
    private static let creatinine = WardField(id: "cr", label: "Creatinine", kind: .number(.creatinine))

    private static func salt(_ id: String, _ label: String) -> WardField {
        WardField(id: id, label: label, kind: .number(.electrolyte))
    }

    /// The formula in words, as shown under "How it is worked out".
    var formula: String {
        switch self {
        case .bodySize: return "BMI = weight (kg) \u{00F7} height (m)\u{00B2}. BSA (Mosteller) = \u{221A}(height cm \u{00D7} weight kg \u{00F7} 3600)."
        case .anionGap: return "Anion gap = Na \u{2212} (Cl + HCO\u{2083}). Albumin-corrected gap = gap + 0.25 \u{00D7} (40 \u{2212} albumin g/L), or + 2.5 \u{00D7} (4.0 \u{2212} albumin g/dL)."
        case .calcium: return "Adjusted Ca (mmol/L) = Ca + 0.02 \u{00D7} (40 \u{2212} albumin g/L); in US units Ca (mg/dL) + 0.8 \u{00D7} (4.0 \u{2212} albumin g/dL)."
        case .sodium: return "Corrected Na = Na + 1.6 \u{00D7} (glucose mg/dL \u{2212} 100) \u{00F7} 100 (Katz), or with 2.4 in place of 1.6 (Hillier). 100 mg/dL is 5.6 mmol/L."
        case .osmolality: return "Calculated osmolality = 2 \u{00D7} Na + glucose + urea (all mmol/L), or 2 \u{00D7} Na + glucose \u{00F7} 18 + BUN \u{00F7} 2.8 (mg/dL). Osmolar gap = measured \u{2212} calculated."
        case .aaGradient: return "PAO\u{2082} = FiO\u{2082} \u{00D7} (760 \u{2212} 47) \u{2212} PaCO\u{2082} \u{00F7} 0.8 (mmHg, sea level). A\u{2013}a gradient = PAO\u{2082} \u{2212} PaO\u{2082}. Upper limit of normal on air \u{2248} age \u{00F7} 4 + 4 mmHg."
        case .crcl: return "CrCl (mL/min) = (140 \u{2212} age) \u{00D7} weight (kg) \u{00F7} (72 \u{00D7} creatinine mg/dL), \u{00D7} 0.85 if female."
        case .egfr: return "eGFR = 142 \u{00D7} min(Scr/\u{03BA}, 1)^\u{03B1} \u{00D7} max(Scr/\u{03BA}, 1)^\u{2212}1.200 \u{00D7} 0.9938^age \u{00D7} 1.012 if female, with Scr in mg/dL; \u{03BA} = 0.7 (female) or 0.9 (male), \u{03B1} = \u{2212}0.241 (female) or \u{2212}0.302 (male)."
        case .map: return "MAP = diastolic + (systolic \u{2212} diastolic) \u{00F7} 3."
        case .qtc: return "RR (s) = 60 \u{00F7} heart rate. Bazett QTc = QT \u{00F7} \u{221A}RR. Fridericia QTc = QT \u{00F7} \u{221B}RR."
        case .fluids: return "4 mL/kg/h for the first 10 kg, 2 mL/kg/h for the next 10 kg, 1 mL/kg/h for every kg above 20 (per day: 100, 50 and 20 mL/kg)."
        case .childWeight: return "APLS: 0\u{2013}12 months (0.5 \u{00D7} months) + 4; 1\u{2013}5 years (2 \u{00D7} years) + 8; 6\u{2013}12 years (3 \u{00D7} years) + 7."
        case .convert: return "Glucose 1 mmol/L = 18.016 mg/dL; creatinine 1 mg/dL = 88.42 \u{00B5}mol/L; urea 1 mmol/L = 2.8014 mg/dL BUN; calcium 1 mmol/L = 4.008 mg/dL; cholesterol 1 mmol/L = 38.67 mg/dL; triglycerides 1 mmol/L = 88.57 mg/dL."
        case .meldNa: return "MELD(i) = 0.957 \u{00D7} ln(Cr) + 0.378 \u{00D7} ln(bilirubin) + 1.120 \u{00D7} ln(INR) + 0.643, rounded to the tenth and \u{00D7} 10 (mg/dL; values below 1 count as 1; Cr at most 4, and 4 after dialysis). If MELD(i) > 11: MELD-Na = MELD(i) + 1.32 \u{00D7} (137 \u{2212} Na) \u{2212} 0.033 \u{00D7} MELD(i) \u{00D7} (137 \u{2212} Na), with Na held between 125 and 137."
        }
    }

    /// What to keep in mind, beside the answer.
    var note: String {
        switch self {
        case .bodySize: return "WHO adult classes. NICE lowers the thresholds for people of South Asian, Chinese, other Asian, Middle Eastern, Black African or African-Caribbean family background: overweight from 23, obesity from 27.5."
        case .anionGap: return "Laboratories differ: the classic range without potassium is 8\u{2013}12 mmol/L, and many modern analysers read lower. Each 10 g/L fall in albumin lowers the gap by about 2.5 (Figge); this uses 40 g/L as normal albumin, as MDCalc does, where Figge used 44."
        case .calcium: return "An estimate: ionised calcium is the measurement when it matters. Many laboratories now report an adjusted calcium with their own formula."
        case .sodium: return "Katz\u{2019}s 1.6 is the classic teaching; Hillier found 2.4 a better overall factor: sodium falls more steeply once glucose is above about 400 mg/dL (22 mmol/L)."
        case .osmolality: return "An osmolar gap above about 10 mOsm/kg suggests an unmeasured osmole: methanol, ethylene glycol, ethanol, mannitol."
        case .aaGradient: return "Assumes sea level, 37 \u{00B0}C and a respiratory quotient of 0.8. Enter FiO\u{2082} as a percentage (21 on air) or a fraction (0.21)."
        case .crcl: return "Uses actual body weight, as the original did; many drug references prefer ideal or adjusted weight in obesity. Drug doses are often still labelled by Cockcroft\u{2013}Gault."
        case .egfr: return "For adults (18 and over) with a stable creatinine. Race-free: the 2021 equation dropped the race coefficient. Categories are KDIGO 2012."
        case .map: return "The Surviving Sepsis Campaign (2021) targets a MAP of at least 65 mmHg in septic shock."
        case .qtc: return "Prolonged: 450 ms or more in men, 460 ms or more in women (AHA/ACCF/HRS 2009); above 500 ms the risk of torsades rises sharply. Bazett over-corrects at fast heart rates, where Fridericia is preferred."
        case .fluids: return "Holliday\u{2013}Segar is a paediatric rule. NICE CG174 gives adults 25\u{2013}30 mL/kg/day of water. Real prescriptions also weigh losses, sodium and illness."
        case .childWeight: return "A rough estimate for when a child cannot be weighed; weigh them as soon as you can."
        case .convert: return "Urea in mmol/L is urea itself; in US units it is reported as blood urea nitrogen (BUN)."
        case .meldNa: return "The UNOS/OPTN MELD-Na used for US liver allocation from 2016; MELD 3.0 replaced it in July 2023. For ages 12 and over."
        }
    }

    var source: String {
        switch self {
        case .bodySize: return "WHO Technical Report Series 894 (2000); NICE obesity guidance (ethnicity thresholds, 2022); Mosteller RD. N Engl J Med 1987;317:1098."
        case .anionGap: return "Emmett M, Narins RG. Medicine 1977;56:38; Figge J et al. Crit Care Med 1998;26:1807."
        case .calcium: return "Payne RB et al. BMJ 1973;4:643 (the simplified formula in common use)."
        case .sodium: return "Katz MA. N Engl J Med 1973;289:843; Hillier TA et al. Am J Med 1999;106:399."
        case .osmolality: return "Dorwart WV, Chalmers L. Clin Chem 1975;21:190."
        case .aaGradient: return "The alveolar gas equation (West, Respiratory Physiology); age estimate as used by MDCalc."
        case .crcl: return "Cockcroft DW, Gault MH. Nephron 1976;16:31."
        case .egfr: return "Inker LA et al. N Engl J Med 2021;385:1737; KDIGO CKD guideline 2012."
        case .map: return "Evans L et al. Surviving Sepsis Campaign guidelines 2021. Intensive Care Med 2021;47:1181."
        case .qtc: return "Bazett HC. Heart 1920;7:353; Fridericia LS. Acta Med Scand 1920;53:469; Rautaharju PM et al. (AHA/ACCF/HRS) Circulation 2009;119:e241."
        case .fluids: return "Holliday MA, Segar WE. Pediatrics 1957;19:823; NICE NG29 (2015) and CG174 (2013)."
        case .childWeight: return "Advanced Life Support Group. Advanced Paediatric Life Support, 5th edition (2011)."
        case .convert: return "Molar masses; SI conversion factors as in the AMA Manual of Style."
        case .meldNa: return "Kim WR et al. N Engl J Med 2008;359:1018; OPTN policy 9.1 (2016); Wiesner R et al. Gastroenterology 2003;124:91."
        }
    }

    // MARK: working it out

    /// The answer, from values in SI (numbers), 0/1 (toggles) or an index
    /// (choices); nil while something needed is missing or impossible.
    /// `us` chooses the units the answer is written in.
    func compute(_ v: [String: Double], us: Bool) -> WardOutcome? {
        switch self {
        case .bodySize: return Self.bodySize(v)
        case .anionGap: return Self.anionGap(v, us: us)
        case .calcium: return Self.calcium(v, us: us)
        case .sodium: return Self.sodium(v, us: us)
        case .osmolality: return Self.osmolality(v)
        case .aaGradient: return Self.aaGradient(v, us: us)
        case .crcl: return Self.crcl(v)
        case .egfr: return Self.egfr(v)
        case .map: return Self.map(v)
        case .qtc: return Self.qtc(v)
        case .fluids: return Self.fluids(v)
        case .childWeight: return Self.childWeight(v)
        case .convert: return Self.convert(v)
        case .meldNa: return Self.meldNa(v)
        }
    }

    private static func positive(_ v: [String: Double], _ key: String) -> Double? {
        guard let x = v[key], x.isFinite, x > 0 else { return nil }
        return x
    }

    private static func line(_ label: String, _ x: Double, _ places: Int, _ unit: String) -> WardLine {
        let number: String = WardPocket.format(x, places: places)
        return WardLine(label: label, value: unit.isEmpty ? number : number + " " + unit)
    }

    private static func bodySize(_ v: [String: Double]) -> WardOutcome? {
        guard let wt = positive(v, "wt"), let ht = positive(v, "ht") else { return nil }
        let bmi: Double = WardFormula.bmi(weightKg: wt, heightCm: ht)
        let bsa: Double = WardFormula.bsaMosteller(weightKg: wt, heightCm: ht)
        let lines: [WardLine] = [line("BMI", bmi, 1, "kg/m\u{00B2}"), line("Body surface area", bsa, 2, "m\u{00B2}")]
        return WardOutcome(lines: lines, verdict: WardFormula.bmiClass(bmi))
    }

    private static func anionGap(_ v: [String: Double], us: Bool) -> WardOutcome? {
        guard let na = positive(v, "na"), let cl = positive(v, "cl"), let hco3 = positive(v, "hco3") else { return nil }
        let unit: String = WardUnit.electrolyte.name(us: us)
        let gap: Double = WardFormula.anionGap(sodium: na, chloride: cl, bicarbonate: hco3)
        var lines: [WardLine] = [line("Anion gap", gap, 0, unit)]
        var judged: Double = gap
        if let alb = positive(v, "alb") {
            let corrected: Double = WardFormula.albuminCorrectedGap(gap, albuminGL: alb)
            lines.append(line("Corrected for albumin", corrected, 1, unit))
            judged = corrected
        }
        return WardOutcome(lines: lines, verdict: gapVerdict(judged))
    }

    /// Against the classic 8-12 range without potassium.
    static func gapVerdict(_ gap: Double) -> String {
        if gap > 12 { return "Raised (above 12): a high anion gap acidosis if the bicarbonate is low \u{2014} think MUDPILES / GOLDMARK" }
        if gap < 8 { return "Low (below 8): hypoalbuminaemia, paraproteins, or a laboratory error" }
        return "Within the classic range (8\u{2013}12)"
    }

    private static func calcium(_ v: [String: Double], us: Bool) -> WardOutcome? {
        guard let ca = positive(v, "ca"), let alb = positive(v, "alb") else { return nil }
        let adjusted: Double = WardFormula.correctedCalcium(calciumMmol: ca, albuminGL: alb)
        let shown: Double = WardUnit.calcium.fromSI(adjusted, us: us)
        let places: Int = us ? 1 : 2
        let lines: [WardLine] = [line("Adjusted calcium", shown, places, WardUnit.calcium.name(us: us))]
        return WardOutcome(lines: lines, verdict: calciumVerdict(adjusted))
    }

    /// Against 2.20-2.60 mmol/L (8.8-10.4 mg/dL).
    static func calciumVerdict(_ mmol: Double) -> String {
        if mmol < 2.2 { return "Low: below 2.20 mmol/L (8.8 mg/dL)" }
        if mmol > 2.6 { return "High: above 2.60 mmol/L (10.4 mg/dL)" }
        return "Within 2.20\u{2013}2.60 mmol/L (8.8\u{2013}10.4 mg/dL)"
    }

    private static func sodium(_ v: [String: Double], us: Bool) -> WardOutcome? {
        guard let na = positive(v, "na"), let glu = positive(v, "glu") else { return nil }
        let mgdl: Double = WardUnit.glucose.fromSI(glu, us: true)
        let unit: String = WardUnit.electrolyte.name(us: us)
        let katz: Double = WardFormula.correctedSodium(sodium: na, glucoseMgdl: mgdl, factor: 1.6)
        let hillier: Double = WardFormula.correctedSodium(sodium: na, glucoseMgdl: mgdl, factor: 2.4)
        let lines: [WardLine] = [line("Corrected (Katz, 1.6)", katz, 1, unit), line("Corrected (Hillier, 2.4)", hillier, 1, unit)]
        return WardOutcome(lines: lines, verdict: sodiumVerdict(katz))
    }

    static func sodiumVerdict(_ na: Double) -> String {
        if na < 135 { return "Below 135: a true hyponatraemia once glucose is allowed for" }
        if na > 145 { return "Above 145: hypernatraemic once glucose is allowed for (a free water deficit)" }
        return "Within 135\u{2013}145 once glucose is allowed for"
    }

    private static func osmolality(_ v: [String: Double]) -> WardOutcome? {
        guard let na = positive(v, "na"), let glu = positive(v, "glu"), let urea = positive(v, "urea") else { return nil }
        let calc: Double = WardFormula.osmolality(sodium: na, glucoseMmol: glu, ureaMmol: urea)
        var lines: [WardLine] = [line("Calculated osmolality", calc, 0, "mOsm/kg")]
        var verdict: String = calc < 275 ? "Calculated value below 275: hypo-osmolar"
            : (calc > 295 ? "Calculated value above 295: hyperosmolar" : "Calculated value within 275\u{2013}295")
        if let measured = positive(v, "measured") {
            let gap: Double = measured - calc
            lines.append(line("Osmolar gap", gap, 0, "mOsm/kg"))
            verdict = gap > 10 ? "Osmolar gap above 10: look for an unmeasured osmole (toxic alcohols, ethanol, mannitol)"
                : "Osmolar gap 10 or less: no unmeasured osmole suggested"
        }
        return WardOutcome(lines: lines, verdict: verdict)
    }

    private static func aaGradient(_ v: [String: Double], us: Bool) -> WardOutcome? {
        guard let typedFiO2 = positive(v, "fio2"), let pao2 = positive(v, "pao2"),
              let paco2 = positive(v, "paco2") else { return nil }
        // 0.21 typed as a fraction means 21%
        let fio2: Double = typedFiO2 <= 1 ? typedFiO2 * 100 : typedFiO2
        guard fio2 <= 100 else { return nil }
        let gas: WardUnit = .gas
        let pao2mm: Double = gas.fromSI(pao2, us: true)
        let paco2mm: Double = gas.fromSI(paco2, us: true)
        let alveolar: Double = WardFormula.alveolarO2(fio2: fio2 / 100, paco2: paco2mm)
        let gradient: Double = alveolar - pao2mm
        // worked in mmHg; shown in kPa for SI
        let scale: Double = us ? 1 : 1 / gas.usPerSI
        let places: Int = us ? 0 : 1
        let name: String = gas.name(us: us)
        var lines: [WardLine] = [line("Alveolar O\u{2082} (PAO\u{2082})", alveolar * scale, places, name),
                                 line("A\u{2013}a gradient", gradient * scale, places, name)]
        var verdict: String?
        if let age = positive(v, "age") {
            let upper: Double = WardFormula.expectedAaGradient(age: age)
            lines.append(line("Expected on air, up to", upper * scale, places, name))
            if fio2 > 21.5 {
                verdict = "The age estimate is for air; on added oxygen the normal gradient is wider"
            } else {
                verdict = gradient > upper ? "Raised for age: V/Q mismatch, shunt or a diffusion defect"
                    : "Normal for age: hypoxaemia, if any, is from hypoventilation or low inspired oxygen"
            }
        }
        // a PaO2 above the alveolar value cannot happen: a typing slip
        if gradient < -1 { verdict = "PaO\u{2082} is above the alveolar value, which is impossible: check the FiO\u{2082} and the units" }
        return WardOutcome(lines: lines, verdict: verdict)
    }

    private static func crcl(_ v: [String: Double]) -> WardOutcome? {
        guard let age = positive(v, "age"), age < 140, let wt = positive(v, "wt"), let cr = positive(v, "cr") else { return nil }
        let mgdl: Double = WardUnit.creatinine.fromSI(cr, us: true)
        let female: Bool = (v["female"] ?? 0) > 0.5
        let clearance: Double = WardFormula.cockcroftGault(age: age, weightKg: wt, creatinineMgdl: mgdl, female: female)
        let lines: [WardLine] = [line("Creatinine clearance", clearance, 0, "mL/min")]
        return WardOutcome(lines: lines, verdict: nil)
    }

    private static func egfr(_ v: [String: Double]) -> WardOutcome? {
        guard let age = positive(v, "age"), let cr = positive(v, "cr") else { return nil }
        let mgdl: Double = WardUnit.creatinine.fromSI(cr, us: true)
        let female: Bool = (v["female"] ?? 0) > 0.5
        let gfr: Double = WardFormula.ckdEpi2021(age: age, creatinineMgdl: mgdl, female: female)
        let lines: [WardLine] = [line("eGFR", gfr, 0, "mL/min/1.73 m\u{00B2}")]
        let verdict: String = age < 18 ? "For adults only: children need a paediatric equation (bedside Schwartz)"
            : WardFormula.gfrCategory(gfr.rounded())
        return WardOutcome(lines: lines, verdict: verdict)
    }

    private static func map(_ v: [String: Double]) -> WardOutcome? {
        guard let sbp = positive(v, "sbp"), let dbp = positive(v, "dbp"), sbp >= dbp else { return nil }
        let pressure: Double = WardFormula.meanArterialPressure(systolic: sbp, diastolic: dbp)
        let verdict: String = pressure < 65 ? "Below 65 mmHg: under the usual target in septic shock"
            : "65 mmHg or more"
        return WardOutcome(lines: [line("MAP", pressure, 0, "mmHg")], verdict: verdict)
    }

    private static func qtc(_ v: [String: Double]) -> WardOutcome? {
        guard let qt = positive(v, "qt"), let hr = positive(v, "hr") else { return nil }
        let female: Bool = (v["female"] ?? 0) > 0.5
        let bazett: Double = WardFormula.qtcBazett(qtMs: qt, heartRate: hr)
        let fridericia: Double = WardFormula.qtcFridericia(qtMs: qt, heartRate: hr)
        let lines: [WardLine] = [line("QTc, Bazett", bazett, 0, "ms"), line("QTc, Fridericia", fridericia, 0, "ms")]
        return WardOutcome(lines: lines, verdict: qtcVerdict(bazett.rounded(), female: female))
    }

    /// AHA/ACCF/HRS 2009: prolonged at 450 ms or more (men), 460 or more
    /// (women); above 500 ms, a high risk of torsades.
    static func qtcVerdict(_ qtc: Double, female: Bool) -> String {
        let limit: Double = female ? 460 : 450
        if qtc > 500 { return "Above 500 ms (Bazett): markedly prolonged, a high risk of torsades de pointes" }
        if qtc >= limit {
            let number: String = WardPocket.format(limit, places: 0)
            return "Prolonged (Bazett): \(number) ms or more"
        }
        return "Not prolonged (Bazett)"
    }

    private static func fluids(_ v: [String: Double]) -> WardOutcome? {
        guard let wt = positive(v, "wt") else { return nil }
        let hourly: Double = WardFormula.maintenancePerHour(weightKg: wt)
        let daily: Double = WardFormula.maintenancePerDay(weightKg: wt)
        let low: String = WardPocket.format(wt * 25, places: 0)
        let high: String = WardPocket.format(wt * 30, places: 0)
        let lines: [WardLine] = [line("4-2-1 rule", hourly, 0, "mL/h"), line("100-50-20 rule", daily, 0, "mL/day"),
                                 WardLine(label: "Adult water (NICE, 25\u{2013}30 mL/kg/day)", value: low + "\u{2013}" + high + " mL/day")]
        return WardOutcome(lines: lines, verdict: nil)
    }

    private static func childWeight(_ v: [String: Double]) -> WardOutcome? {
        guard let age = v["age"], age >= 0, age.isFinite else { return nil }
        let inYears: Bool = (v["per"] ?? 0) > 0.5
        let months: Double = inYears ? age * 12 : age
        guard let kg = WardFormula.childWeight(ageMonths: months) else {
            return WardOutcome(lines: [], verdict: "The APLS formulas stop at 12 years")
        }
        let lines: [WardLine] = [line("Estimated weight", kg, 1, "kg")]
        return WardOutcome(lines: lines, verdict: WardFormula.childWeightRule(ageMonths: months))
    }

    private static func convert(_ v: [String: Double]) -> WardOutcome? {
        guard let value = v["value"], value.isFinite, value >= 0 else { return nil }
        let index: Int = Int(v["what"] ?? 0)
        guard let substance = WardSubstance(rawValue: index) else { return nil }
        let toUS: Bool = (v["dir"] ?? 0) < 0.5
        let unit: WardUnit = substance.unit
        let out: Double = toUS ? unit.fromSI(value, us: true) : unit.toSI(value, us: true)
        let places: Int = out >= 100 ? 0 : (out >= 10 ? 1 : 2)
        let from: String = unit.name(us: !toUS)
        let to: String = unit.name(us: toUS)
        let head: String = WardPocket.format(value, places: value >= 100 ? 0 : 2) + " " + from
        return WardOutcome(lines: [line(head, out, places, to)], verdict: nil)
    }

    private static func meldNa(_ v: [String: Double]) -> WardOutcome? {
        guard let bili = positive(v, "bili"), let inr = positive(v, "inr"),
              let cr = positive(v, "cr"), let na = positive(v, "na") else { return nil }
        let dialysis: Bool = (v["dialysis"] ?? 0) > 0.5
        let biliMg: Double = WardUnit.bilirubin.fromSI(bili, us: true)
        let crMg: Double = WardUnit.creatinine.fromSI(cr, us: true)
        let result = WardFormula.meld(bilirubinMgdl: biliMg, inr: inr, creatinineMgdl: crMg, sodium: na, dialysis: dialysis)
        let lines: [WardLine] = [line("MELD", result.meld, 0, ""), line("MELD-Na", result.meldNa, 0, "")]
        return WardOutcome(lines: lines, verdict: WardFormula.meldMortality(result.meldNa))
    }
}
