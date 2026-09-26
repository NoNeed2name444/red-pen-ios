// The Ward pocket's formulas and scores, each against worked examples from
// the original papers or the standard calculators (MDCalc, the NKF eGFR
// calculator, OPTN's MELD policy), with the boundary values where a
// threshold or a band changes. Also: every score's bands cover every total
// it can reach exactly once, and the unit conversions go both ways.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Double?, _ b: Double, _ tolerance: Double = 0.05) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

// MARK: - units

check("glucose 180 mg/dL is about 10 mmol/L", near(WardUnit.glucose.toSI(180, us: true), 9.99, 0.01))
check("creatinine 1 mg/dL is 88.4 umol/L", near(WardUnit.creatinine.toSI(1, us: true), 88.42, 0.01))
check("BUN 28 mg/dL is urea 10 mmol/L", near(WardUnit.urea.toSI(28.014, us: true), 10, 0.001))
check("calcium 2.5 mmol/L is 10 mg/dL", near(WardUnit.calcium.fromSI(2.5, us: true), 10.02, 0.01))
check("cholesterol 5 mmol/L is 193 mg/dL", near(WardUnit.cholesterol.fromSI(5, us: true), 193.35, 0.01))
check("albumin 3.5 g/dL is 35 g/L", near(WardUnit.albumin.toSI(3.5, us: true), 35, 0.0001))
check("bilirubin 17.1 umol/L is 1 mg/dL", near(WardUnit.bilirubin.fromSI(17.1, us: true), 1, 0.0001))
check("PaCO2 5.33 kPa is 40 mmHg", near(WardUnit.gas.fromSI(5.333, us: true), 40, 0.01))
var roundTrips: Bool = true
for s in WardSubstance.allCases {
    let back: Double = s.unit.toSI(s.unit.fromSI(7.3, us: true), us: true)
    if abs(back - 7.3) > 1e-9 { roundTrips = false }
}
check("every converter unit goes there and back", roundTrips)
check("SI values stay as typed in SI", WardUnit.glucose.toSI(5.5, us: false) == 5.5)

let toUS: WardOutcome? = WardCalc.convert.compute(["what": 0, "dir": 0, "value": 10], us: false)
check("converter: glucose 10 mmol/L -> 180 mg/dL", toUS?.lines.first?.value == "180 mg/dL", "\(String(describing: toUS))")
let toSI: WardOutcome? = WardCalc.convert.compute(["what": 1, "dir": 1, "value": 1.2], us: false)
check("converter: creatinine 1.2 mg/dL -> 106 umol/L", toSI?.lines.first?.value == "106 \u{00B5}mol/L", "\(String(describing: toSI))")

// MARK: - body size

check("BMI 70 kg, 175 cm = 22.9", near(WardFormula.bmi(weightKg: 70, heightCm: 175), 22.86, 0.01))
check("BSA (Mosteller) 70 kg, 170 cm = 1.82 m2", near(WardFormula.bsaMosteller(weightKg: 70, heightCm: 170), 1.818, 0.001))
check("BMI 18.4 underweight, 18.5 healthy", WardFormula.bmiClass(18.4).hasPrefix("Underweight") && WardFormula.bmiClass(18.5).hasPrefix("Healthy"))
check("BMI 24.9 healthy, 25 overweight", WardFormula.bmiClass(24.9).hasPrefix("Healthy") && WardFormula.bmiClass(25).hasPrefix("Overweight"))
check("BMI 30 class I, 35 class II, 40 class III",
      WardFormula.bmiClass(30).contains("class I ") && WardFormula.bmiClass(35).contains("class II ")
      && WardFormula.bmiClass(40).contains("class III"))
let body: WardOutcome? = WardCalc.bodySize.compute(["wt": 70, "ht": 175], us: false)
check("body size shows BMI and BSA", body?.lines.map(\.value) == ["22.9 kg/m\u{00B2}", "1.84 m\u{00B2}"], "\(String(describing: body))")
check("no answer without a height", WardCalc.bodySize.compute(["wt": 70], us: false) == nil)

// MARK: - anion gap

check("anion gap 140 - (104 + 24) = 12", WardFormula.anionGap(sodium: 140, chloride: 104, bicarbonate: 24) == 12)
check("albumin 20 g/L adds 5 to the gap (Figge)", WardFormula.albuminCorrectedGap(12, albuminGL: 20) == 17)
check("albumin 40 g/L adds nothing", WardFormula.albuminCorrectedGap(12, albuminGL: 40) == 12)
check("gap 12 is within range, 13 raised, 7 low",
      WardCalc.gapVerdict(12).hasPrefix("Within") && WardCalc.gapVerdict(13).hasPrefix("Raised") && WardCalc.gapVerdict(7).hasPrefix("Low"))
let gapUS: WardOutcome? = WardCalc.anionGap.compute(["na": 140, "cl": 104, "hco3": 24, "alb": 20], us: true)
check("gap in US units says mEq/L and judges the corrected gap",
      gapUS?.lines.map(\.value) == ["12 mEq/L", "17.0 mEq/L"] && gapUS?.verdict?.hasPrefix("Raised") == true, "\(String(describing: gapUS))")

// MARK: - calcium

check("Ca 2.00 mmol/L, albumin 25 g/L -> 2.30 (Payne)", near(WardFormula.correctedCalcium(calciumMmol: 2.0, albuminGL: 25), 2.30, 0.0001))
let caUS: WardOutcome? = WardCalc.calcium.compute(["ca": WardUnit.calcium.toSI(8.0, us: true),
                                                   "alb": WardUnit.albumin.toSI(2.0, us: true)], us: true)
check("Ca 8.0 mg/dL, albumin 2.0 g/dL -> 9.6 mg/dL", caUS?.lines.first?.value == "9.6 mg/dL", "\(String(describing: caUS))")
check("calcium bands at 2.20 and 2.60", WardCalc.calciumVerdict(2.2).hasPrefix("Within") && WardCalc.calciumVerdict(2.19).hasPrefix("Low")
      && WardCalc.calciumVerdict(2.6).hasPrefix("Within") && WardCalc.calciumVerdict(2.61).hasPrefix("High"))

// MARK: - sodium

check("Na 130, glucose 600 mg/dL -> 138 (Katz)", near(WardFormula.correctedSodium(sodium: 130, glucoseMgdl: 600, factor: 1.6), 138, 0.0001))
check("Na 130, glucose 600 mg/dL -> 142 (Hillier)", near(WardFormula.correctedSodium(sodium: 130, glucoseMgdl: 600, factor: 2.4), 142, 0.0001))
check("no correction at glucose 100 mg/dL or below", WardFormula.correctedSodium(sodium: 130, glucoseMgdl: 80, factor: 1.6) == 130)
let naSI: WardOutcome? = WardCalc.sodium.compute(["na": 130, "glu": 600 / 18.016], us: false)
check("sodium calculator from mmol/L glucose", naSI?.lines.map(\.value) == ["138.0 mmol/L", "142.0 mmol/L"], "\(String(describing: naSI))")

// MARK: - osmolality

check("2 x 140 + 5 + 5 = 290", WardFormula.osmolality(sodium: 140, glucoseMmol: 5, ureaMmol: 5) == 290)
let osmUS: WardOutcome? = WardCalc.osmolality.compute(["na": 140, "glu": WardUnit.glucose.toSI(90, us: true),
                                                       "urea": WardUnit.urea.toSI(14, us: true), "measured": 310], us: true)
check("MDCalc-style: Na 140, glucose 90, BUN 14 -> 290; gap 20", osmUS?.lines.map(\.value) == ["290 mOsm/kg", "20 mOsm/kg"]
      && osmUS?.verdict?.hasPrefix("Osmolar gap above 10") == true, "\(String(describing: osmUS))")
let osmTen: WardOutcome? = WardCalc.osmolality.compute(["na": 140, "glu": 5, "urea": 5, "measured": 300], us: false)
check("an osmolar gap of exactly 10 is not raised", osmTen?.verdict?.hasPrefix("Osmolar gap 10 or less") == true)

// MARK: - A-a gradient

check("PAO2 on air with PaCO2 40 = 99.7 mmHg", near(WardFormula.alveolarO2(fio2: 0.21, paco2: 40), 99.73, 0.01))
check("A-a gradient: air, PaCO2 40, PaO2 90 -> 9.7", near(WardFormula.aaGradient(fio2: 0.21, pao2: 90, paco2: 40), 9.73, 0.01))
check("expected A-a at 40 years = 14", WardFormula.expectedAaGradient(age: 40) == 14)
let aaUS: WardOutcome? = WardCalc.aaGradient.compute(["fio2": 21, "pao2": WardUnit.gas.toSI(90, us: true),
                                                      "paco2": WardUnit.gas.toSI(40, us: true), "age": 40], us: true)
check("A-a in mmHg, normal for age", aaUS?.lines.map(\.value) == ["100 mmHg", "10 mmHg", "14 mmHg"]
      && aaUS?.verdict?.hasPrefix("Normal") == true, "\(String(describing: aaUS))")
let aaSI: WardOutcome? = WardCalc.aaGradient.compute(["fio2": 21, "pao2": 8, "paco2": 5.3, "age": 40], us: false)
// 0.21 x 713 - 39.75/0.8 = 100.04; minus 60.0 = 40.0 mmHg = 5.3 kPa
check("A-a in kPa: PaO2 8, PaCO2 5.3 -> 5.3 kPa, raised", aaSI?.lines[1].value == "5.3 kPa"
      && aaSI?.verdict?.hasPrefix("Raised") == true, "\(String(describing: aaSI))")
check("an FiO2 over 100% is refused", WardCalc.aaGradient.compute(["fio2": 150, "pao2": 8, "paco2": 5], us: false) == nil)

// MARK: - kidney function

check("Cockcroft-Gault: 60 y, 72 kg, Cr 1.0, man -> 80", near(WardFormula.cockcroftGault(age: 60, weightKg: 72, creatinineMgdl: 1, female: false), 80, 0.0001))
check("Cockcroft-Gault: the same woman -> 68", near(WardFormula.cockcroftGault(age: 60, weightKg: 72, creatinineMgdl: 1, female: true), 68, 0.0001))
let crclSI: WardOutcome? = WardCalc.crcl.compute(["age": 60, "wt": 72, "cr": 88.42, "female": 0], us: false)
check("Cockcroft-Gault from umol/L", crclSI?.lines.first?.value == "80 mL/min", "\(String(describing: crclSI))")
// NKF CKD-EPI 2021 calculator values
check("CKD-EPI 2021: man 50 y, Cr 1.0 -> 92", near(WardFormula.ckdEpi2021(age: 50, creatinineMgdl: 1.0, female: false), 91.69, 0.01))
check("CKD-EPI 2021: woman 50 y, Cr 0.7 -> 105", near(WardFormula.ckdEpi2021(age: 50, creatinineMgdl: 0.7, female: true), 105.30, 0.01))
check("CKD-EPI 2021: man 70 y, Cr 2.0 -> 35", near(WardFormula.ckdEpi2021(age: 70, creatinineMgdl: 2.0, female: false), 35.24, 0.01))
check("CKD-EPI 2021: woman 60 y, Cr 0.5 (below kappa) -> 107", near(WardFormula.ckdEpi2021(age: 60, creatinineMgdl: 0.5, female: true), 107.31, 0.01))
check("CKD-EPI 2021: woman 80 y, Cr 1.5 -> 35", near(WardFormula.ckdEpi2021(age: 80, creatinineMgdl: 1.5, female: true), 35.01, 0.01))
let atKappa: Double = WardFormula.ckdEpi2021(age: 40, creatinineMgdl: 0.9, female: false)
check("CKD-EPI 2021 at Scr = kappa is 142 x 0.9938^age", near(atKappa, 142 * pow(0.9938, 40), 1e-9))
check("KDIGO categories at 90, 60, 45, 30, 15",
      WardFormula.gfrCategory(90).hasPrefix("G1") && WardFormula.gfrCategory(89).hasPrefix("G2")
      && WardFormula.gfrCategory(60).hasPrefix("G2") && WardFormula.gfrCategory(59).hasPrefix("G3a")
      && WardFormula.gfrCategory(45).hasPrefix("G3a") && WardFormula.gfrCategory(44).hasPrefix("G3b")
      && WardFormula.gfrCategory(30).hasPrefix("G3b") && WardFormula.gfrCategory(29).hasPrefix("G4")
      && WardFormula.gfrCategory(15).hasPrefix("G4") && WardFormula.gfrCategory(14).hasPrefix("G5"))
let egfrSI: WardOutcome? = WardCalc.egfr.compute(["age": 50, "cr": 88.42, "female": 0], us: false)
check("eGFR from umol/L, G1", egfrSI?.lines.first?.value == "92 mL/min/1.73 m\u{00B2}" && egfrSI?.verdict?.hasPrefix("G1") == true,
      "\(String(describing: egfrSI))")
let child: WardOutcome? = WardCalc.egfr.compute(["age": 12, "cr": 50], us: false)
check("eGFR says it is for adults", child?.verdict?.hasPrefix("For adults only") == true)

// MARK: - MAP and QTc

check("MAP 120/80 = 93.3", near(WardFormula.meanArterialPressure(systolic: 120, diastolic: 80), 93.33, 0.01))
let mapLow: WardOutcome? = WardCalc.map.compute(["sbp": 85, "dbp": 55], us: false)
check("MAP 85/55 = 65 is at target", mapLow?.lines.first?.value == "65 mmHg" && mapLow?.verdict == "65 mmHg or more")
check("MAP 84/55 = 64.7 is below target", WardCalc.map.compute(["sbp": 84, "dbp": 55], us: false)?.verdict?.hasPrefix("Below 65") == true)
check("QTc at 60/min equals QT", WardFormula.qtcBazett(qtMs: 400, heartRate: 60) == 400 && near(WardFormula.qtcFridericia(qtMs: 400, heartRate: 60), 400, 1e-9))
check("QT 360 at 100/min: Bazett 465", near(WardFormula.qtcBazett(qtMs: 360, heartRate: 100), 464.76, 0.01))
check("QT 360 at 100/min: Fridericia 427", near(WardFormula.qtcFridericia(qtMs: 360, heartRate: 100), 426.83, 0.01))
check("QTc 449 man not prolonged, 450 prolonged",
      WardCalc.qtcVerdict(449, female: false).hasPrefix("Not") && WardCalc.qtcVerdict(450, female: false).hasPrefix("Prolonged"))
check("QTc 459 woman not prolonged, 460 prolonged",
      WardCalc.qtcVerdict(459, female: true).hasPrefix("Not") && WardCalc.qtcVerdict(460, female: true).hasPrefix("Prolonged"))
check("QTc 501 markedly prolonged", WardCalc.qtcVerdict(501, female: false).hasPrefix("Above 500"))

// MARK: - fluids and children

check("4-2-1: 10 kg = 40 mL/h", WardFormula.maintenancePerHour(weightKg: 10) == 40)
check("4-2-1: 20 kg = 60 mL/h", WardFormula.maintenancePerHour(weightKg: 20) == 60)
check("4-2-1: 25 kg = 65 mL/h", WardFormula.maintenancePerHour(weightKg: 25) == 65)
check("4-2-1: 70 kg = 110 mL/h", WardFormula.maintenancePerHour(weightKg: 70) == 110)
check("4-2-1: 5 kg = 20 mL/h", WardFormula.maintenancePerHour(weightKg: 5) == 20)
check("100-50-20: 25 kg = 1600 mL/day", WardFormula.maintenancePerDay(weightKg: 25) == 1600)
check("100-50-20: 10 kg = 1000, 20 kg = 1500",
      WardFormula.maintenancePerDay(weightKg: 10) == 1000 && WardFormula.maintenancePerDay(weightKg: 20) == 1500)
let fluid: WardOutcome? = WardCalc.fluids.compute(["wt": 70], us: false)
check("adult water 25-30 mL/kg/day at 70 kg", fluid?.lines.last?.value == "1750\u{2013}2100 mL/day", "\(String(describing: fluid))")

check("APLS: newborn 4 kg", WardFormula.childWeight(ageMonths: 0) == 4)
check("APLS: 6 months 7 kg", WardFormula.childWeight(ageMonths: 6) == 7)
check("APLS: 12 months 10 kg", WardFormula.childWeight(ageMonths: 12) == 10)
check("APLS: 3 years 14 kg", WardFormula.childWeight(ageMonths: 36) == 14)
check("APLS: 5 years 18 kg", WardFormula.childWeight(ageMonths: 60) == 18)
check("APLS: 5 years 11 months still (2 x 5) + 8", WardFormula.childWeight(ageMonths: 71) == 18)
check("APLS: 6 years 25 kg", WardFormula.childWeight(ageMonths: 72) == 25)
check("APLS: 10 years 37 kg", WardFormula.childWeight(ageMonths: 120) == 37)
check("APLS: 12 years 43 kg", WardFormula.childWeight(ageMonths: 144) == 43)
check("APLS: none past 12 years", WardFormula.childWeight(ageMonths: 156) == nil)
let inYears: WardOutcome? = WardCalc.childWeight.compute(["age": 3, "per": 1], us: false)
check("child weight typed in years", inYears?.lines.first?.value == "14.0 kg" && inYears?.verdict?.hasPrefix("1\u{2013}5 years") == true)

// MARK: - MELD-Na (OPTN 2016)

let meldA = WardFormula.meld(bilirubinMgdl: 2, inr: 1.5, creatinineMgdl: 1.2, sodium: 130, dialysis: false)
check("MELD: bili 2, INR 1.5, Cr 1.2 -> 15", meldA.meld == 15, "\(meldA)")
check("MELD-Na: with Na 130 -> 21", meldA.meldNa == 21, "\(meldA)")
let meldLow = WardFormula.meld(bilirubinMgdl: 0.5, inr: 0.9, creatinineMgdl: 0.6, sodium: 120, dialysis: false)
check("values below 1 count as 1: MELD 6, and no sodium term at 11 or less", meldLow.meld == 6 && meldLow.meldNa == 6, "\(meldLow)")
let meldTwelve = WardFormula.meld(bilirubinMgdl: 1.8, inr: 1.3, creatinineMgdl: 1.0, sodium: 135, dialysis: false)
check("MELD(i) 12 takes the sodium term: 12 + 2.64 - 0.792 -> 14", meldTwelve.meld == 12 && meldTwelve.meldNa == 14, "\(meldTwelve)")
let meldClamp = WardFormula.meld(bilirubinMgdl: 5, inr: 2.5, creatinineMgdl: 3, sodium: 110, dialysis: false)
let meldAt125 = WardFormula.meld(bilirubinMgdl: 5, inr: 2.5, creatinineMgdl: 3, sodium: 125, dialysis: false)
check("sodium below 125 counts as 125: MELD 33 -> 36", meldClamp.meld == 33 && meldClamp.meldNa == 36 && meldClamp == meldAt125, "\(meldClamp)")
let meldDialysis = WardFormula.meld(bilirubinMgdl: 2, inr: 1.5, creatinineMgdl: 1.2, sodium: 137, dialysis: true)
let meldCap = WardFormula.meld(bilirubinMgdl: 2, inr: 1.5, creatinineMgdl: 9, sodium: 137, dialysis: false)
check("dialysis sets creatinine to 4, as does a creatinine over 4", meldDialysis == meldCap && meldCap.meld == 27, "\(meldCap)")
check("MELD is capped at 40", WardFormula.meld(bilirubinMgdl: 40, inr: 8, creatinineMgdl: 6, sodium: 120, dialysis: true).meldNa == 40)
check("MELD mortality bands at 9/10, 19/20, 29/30, 39/40",
      WardFormula.meldMortality(9).contains("1.9%") && WardFormula.meldMortality(10).contains("6.0%")
      && WardFormula.meldMortality(19).contains("6.0%") && WardFormula.meldMortality(20).contains("19.6%")
      && WardFormula.meldMortality(29).contains("19.6%") && WardFormula.meldMortality(30).contains("52.6%")
      && WardFormula.meldMortality(39).contains("52.6%") && WardFormula.meldMortality(40).contains("71.3%"))
let meldSI: WardOutcome? = WardCalc.meldNa.compute(["bili": 34.2, "inr": 1.5, "cr": 106.1, "na": 130], us: false)
check("MELD-Na from SI units", meldSI?.lines.map(\.value) == ["15", "21"], "\(String(describing: meldSI))")

// MARK: - every calculator

for calc in WardCalc.allCases {
    let ids: [String] = calc.fields.map(\.id)
    check("\(calc.rawValue): field ids are unique", Set(ids).count == ids.count)
    check("\(calc.rawValue): has a formula, a source and a title",
          !calc.formula.isEmpty && !calc.source.isEmpty && !calc.title.isEmpty)
    check("\(calc.rawValue): nothing from nothing", calc.compute([:], us: false) == nil || calc == .childWeight || calc == .convert)
    let notes: String = WardPocket.practiceNotes(for: calc)
    check("\(calc.rawValue): practice notes carry the formula and source", notes.contains(calc.formula) && notes.contains(calc.source))
}
check("MELD-Na is listed with the scores, not the calculators", !WardCalc.calculators.contains(.meldNa)
      && WardScores.entries.contains(.formula(.meldNa)))
check("the disclaimer says learning only", WardPocket.disclaimer.hasPrefix("For learning only") && WardPocket.disclaimer.contains("not for patient care"))

// MARK: - every score's table

check("twenty scores in the tab", WardScores.entries.count == 20, "\(WardScores.entries.count)")
check("score ids are unique", Set(WardScores.all.map(\.id)).count == WardScores.all.count)
for score in WardScores.all {
    let ids: [String] = score.items.map(\.id)
    check("\(score.id): item ids unique", Set(ids).count == ids.count)
    check("\(score.id): every item has two or more answers", score.items.allSatisfy { $0.choices.count >= 2 })
    check("\(score.id): has a source", score.source.count > 10)
    // every reachable total falls in exactly one band
    var badTotals: [Double] = []
    for total in score.reachableTotals.sorted() {
        let hits: Int = score.bands.filter { $0.contains(total) }.count
        if hits != 1 { badTotals.append(total) }
    }
    check("\(score.id): bands cover every total exactly once", badTotals.isEmpty, "\(badTotals)")
    let first: Double = score.bands.first?.low ?? .nan
    let last: Double = score.bands.last?.high ?? .nan
    check("\(score.id): bands run from the lowest to the highest total",
          first == score.lowest && last == score.highest, "\(first)...\(last) vs \(score.lowest)...\(score.highest)")
    check("\(score.id): practice notes carry the source", score.practiceNotes.contains(score.source))
}

func points(_ score: WardScore, _ item: String) -> [Double] {
    score.items.first { $0.id == item }?.choices.map(\.points) ?? []
}

func picks(_ score: WardScore, yes ids: [String]) -> [String: Int] {
    var out: [String: Int] = [:]
    for id in ids { out[id] = 1 }
    return out
}

func verdict(_ score: WardScore, _ picks: [String: Int]) -> String {
    score.verdict(picks)?.title ?? "none"
}

// GCS: E4 V5 M6 = 15; E1 V1 M1 = 3; E2 V2 M4 = 8 severe; E3 V3 M3 = 9 moderate;
// E4 V4 M4 = 12 moderate; E4 V4 M5 = 13 mild
let gcs: WardScore = WardScores.gcs
check("GCS parts are 4, 5 and 6", points(gcs, "eye") == [4, 3, 2, 1] && points(gcs, "verbal") == [5, 4, 3, 2, 1]
      && points(gcs, "motor") == [6, 5, 4, 3, 2, 1])
check("GCS 15 by default, 3 at worst", gcs.total([:]) == 15 && gcs.total(["eye": 3, "verbal": 4, "motor": 5]) == 3)
check("GCS 8 severe, 9 moderate, 12 moderate, 13 mild",
      verdict(gcs, ["eye": 2, "verbal": 3, "motor": 2]) == "Severe"
      && verdict(gcs, ["eye": 1, "verbal": 2, "motor": 3]) == "Moderate"
      && gcs.total(["eye": 0, "verbal": 1, "motor": 2]) == 12
      && verdict(gcs, ["eye": 0, "verbal": 1, "motor": 2]) == "Moderate"
      && verdict(gcs, ["eye": 0, "verbal": 1, "motor": 1]) == "Mild")

// Wells DVT: range -2..9; 1 unlikely, 2 likely
let dvt: WardScore = WardScores.wellsDVT
check("Wells DVT: nine items of 1 and one of -2", dvt.items.count == 10 && dvt.lowest == -2 && dvt.highest == 9
      && points(dvt, "alternative") == [0, -2])
check("Wells DVT 1 unlikely, 2 likely",
      verdict(dvt, picks(dvt, yes: ["cancer"])) == "DVT unlikely"
      && verdict(dvt, picks(dvt, yes: ["cancer", "calf"])) == "DVT likely"
      && verdict(dvt, picks(dvt, yes: ["cancer", "calf", "leg", "alternative"])) == "DVT unlikely")

// Wells PE: 4 unlikely, 4.5 likely (Wells 2000)
let pe: WardScore = WardScores.wellsPE
check("Wells PE weights 3, 3, 1.5, 1.5, 1.5, 1, 1", pe.items.map(\.maxPoints) == [3, 3, 1.5, 1.5, 1.5, 1, 1] && pe.highest == 12.5)
check("Wells PE 4.0 unlikely", verdict(pe, picks(pe, yes: ["dvt", "cancer"])) == "PE unlikely" && pe.total(picks(pe, yes: ["dvt", "cancer"])) == 4)
check("Wells PE 4.5 likely", verdict(pe, picks(pe, yes: ["dvt", "hr"])) == "PE likely")
check("Wells PE 3 + 1.5 + 1.5 + 1.5 = 7.5", pe.total(picks(pe, yes: ["likely", "hr", "immobile", "previous"])) == 7.5)

// PERC: eight criteria; 0 negative, 1 positive
let perc: WardScore = WardScores.perc
check("PERC has eight criteria", perc.items.count == 8 && perc.highest == 8)
check("PERC 0 negative, 1 positive", verdict(perc, [:]) == "PERC negative" && verdict(perc, picks(perc, yes: ["hormones"])) == "PERC positive")

// CURB-65 (Lim 2003): 0-1, 2, 3-5
let curb: WardScore = WardScores.curb65
check("CURB-65 five items of 1", curb.items.count == 5 && curb.highest == 5)
check("CURB-65 1 low, 2 moderate, 3 high",
      verdict(curb, picks(curb, yes: ["age"])) == "Low severity"
      && verdict(curb, picks(curb, yes: ["age", "urea"])) == "Moderate severity"
      && verdict(curb, picks(curb, yes: ["age", "urea", "confusion"])) == "High severity")
check("CURB-65 bands carry Lim's 1.5%, 9.2% and 22%", curb.bands.map(\.detail).joined().contains("1.5%")
      && curb.bands[1].detail.contains("9.2%") && curb.bands[2].detail.contains("22%"))

// qSOFA: 1 not positive, 2 positive
let qsofa: WardScore = WardScores.qsofa
check("qSOFA 1 / 2", verdict(qsofa, picks(qsofa, yes: ["rr"])) == "Not positive" && verdict(qsofa, picks(qsofa, yes: ["rr", "sbp"])) == "qSOFA positive")

// CHA2DS2-VASc: a 76-year-old woman with hypertension = 2 + 1 + 1 = 4
let chads: WardScore = WardScores.chads
check("CHA2DS2-VASc weights", points(chads, "age") == [0, 1, 2] && points(chads, "stroke") == [0, 2] && chads.highest == 9)
check("CHA2DS2-VASc: woman 76 with hypertension = 4, high", chads.total(["age": 2, "female": 1, "htn": 1]) == 4
      && verdict(chads, ["age": 2, "female": 1, "htn": 1]) == "High risk")
check("CHA2DS2-VASc: 0 low, 1 low-moderate, 2 moderate, 3 high",
      verdict(chads, [:]) == "Low risk" && verdict(chads, ["female": 1]) == "Low to moderate"
      && verdict(chads, ["age": 2]) == "Moderate" && verdict(chads, ["age": 2, "dm": 1]) == "High risk")

// HAS-BLED: nine of 1; 2 / 3
let hasbled: WardScore = WardScores.hasbled
check("HAS-BLED nine items", hasbled.items.count == 9 && hasbled.highest == 9)
check("HAS-BLED 2 not high, 3 high", verdict(hasbled, picks(hasbled, yes: ["elderly", "drugs"])) == "Low to moderate"
      && verdict(hasbled, picks(hasbled, yes: ["elderly", "drugs", "alcohol"])) == "High risk")

// Child-Pugh: 5-6 A, 7-9 B, 10-15 C
let cp: WardScore = WardScores.childPugh
check("Child-Pugh: 5 at best, 15 at worst", cp.lowest == 5 && cp.highest == 15 && cp.total([:]) == 5)
check("Child-Pugh 6 A, 7 B, 9 B, 10 C",
      verdict(cp, ["bili": 1]) == "Class A" && verdict(cp, ["bili": 1, "alb": 1]) == "Class B"
      && verdict(cp, ["bili": 2, "alb": 2]) == "Class B" && verdict(cp, ["bili": 2, "alb": 2, "inr": 1]) == "Class C")
check("Child-Pugh bilirubin cut-offs 34 and 50 umol/L (2 and 3 mg/dL)",
      cp.items[0].choices[1].label.hasPrefix("34\u{2013}50") && cp.items[0].choices[1].label.contains("2\u{2013}3 mg/dL"))
check("Child-Pugh INR cut-offs 1.7 and 2.3", cp.items[2].choices.map(\.label) == ["Below 1.7", "1.7\u{2013}2.3", "Above 2.3"])

// Centor / McIsaac
let centor: WardScore = WardScores.centor
check("McIsaac age: 3-14 +1, 45+ -1", points(centor, "age") == [0, 1, -1] && centor.lowest == -1 && centor.highest == 5)
check("Centor 4 in a 10-year-old = 5, high", centor.total(["temp": 1, "cough": 1, "nodes": 1, "tonsils": 1, "age": 1]) == 5
      && verdict(centor, ["temp": 1, "cough": 1, "nodes": 1, "tonsils": 1, "age": 1]) == "High")
check("McIsaac 0 very low, 1 low, 3 intermediate 28-35%",
      verdict(centor, ["temp": 1, "age": 2]) == "Very low" && verdict(centor, ["temp": 1]) == "Low"
      && centor.verdict(["temp": 1, "cough": 1, "nodes": 1])?.detail.contains("28\u{2013}35%") == true)

// Glasgow-Blatchford (Blatchford 2000)
let gbs: WardScore = WardScores.blatchford
check("GBS urea points 0, 2, 3, 4, 6", points(gbs, "urea") == [0, 2, 3, 4, 6])
check("GBS Hb points: men 1 / 3 / 6, women 1 / 6", points(gbs, "hb") == [0, 1, 1, 3, 6])
check("GBS systolic 1 / 2 / 3", points(gbs, "sbp") == [0, 1, 2, 3])
check("GBS others 1, 1, 2, 2, 2", ["pulse", "melaena", "syncope", "liver", "heart"].map { points(gbs, $0).last ?? 0 } == [1, 1, 2, 2, 2])
check("GBS maximum 23", gbs.highest == 23)
check("GBS 0 very low, 1 not low, 5 not low, 6 high",
      verdict(gbs, [:]) == "Very low risk" && verdict(gbs, ["pulse": 1]) == "Not low risk"
      && verdict(gbs, ["urea": 3, "pulse": 1]) == "Not low risk" && verdict(gbs, ["urea": 4]) == "High risk")
check("GBS urea labels carry 6.5, 8, 10 and 25 mmol/L", gbs.items[0].choices[1].label.hasPrefix("6.5")
      && gbs.items[0].choices[2].label.hasPrefix("8.0") && gbs.items[0].choices[3].label.hasPrefix("10.0")
      && gbs.items[0].choices[4].label.hasPrefix("25"))

// Ranson on admission
let ranson: WardScore = WardScores.ranson
check("Ranson: five admission criteria", ranson.items.count == 5 && ranson.items[0].label.contains("55")
      && ranson.items[1].label.contains("16") && ranson.items[2].label.contains("200 mg/dL")
      && ranson.items[3].label.contains("350") && ranson.items[4].label.contains("250"))
check("Ranson 2 / 3", verdict(ranson, picks(ranson, yes: ["age", "wbc"])) == "Fewer than 3"
      && verdict(ranson, picks(ranson, yes: ["age", "wbc", "ldh"])) == "3 or more")

// APGAR
let apgar: WardScore = WardScores.apgar
check("APGAR 10 by default, five items of 0-2", apgar.total([:]) == 10 && apgar.items.allSatisfy { $0.maxPoints == 2 && $0.minPoints == 0 })
let apgar3: [String: Int] = ["appearance": 2, "pulse": 1, "grimace": 2, "activity": 1, "respiration": 1]
let apgar4: [String: Int] = ["appearance": 2, "pulse": 1, "grimace": 1, "activity": 1, "respiration": 1]
check("APGAR 7 reassuring, 6 moderately abnormal, 4 moderately abnormal, 3 low",
      verdict(apgar, ["appearance": 1, "activity": 1, "respiration": 1]) == "Reassuring"
      && verdict(apgar, ["appearance": 1, "activity": 1, "respiration": 1, "grimace": 1]) == "Moderately abnormal"
      && apgar.total(apgar4) == 4 && verdict(apgar, apgar4) == "Moderately abnormal"
      && apgar.total(apgar3) == 3 && verdict(apgar, apgar3) == "Low")

// Alvarado: MANTRELS, tenderness and white cells 2 each
let alvarado: WardScore = WardScores.alvarado
check("Alvarado maximum 10, tenderness and leucocytosis 2", alvarado.highest == 10
      && points(alvarado, "tender") == [0, 2] && points(alvarado, "wbc") == [0, 2])
check("Alvarado 4 / 5 / 7 / 9",
      verdict(alvarado, picks(alvarado, yes: ["tender", "wbc"])) == "Unlikely"
      && verdict(alvarado, picks(alvarado, yes: ["tender", "wbc", "temp"])) == "Possible"
      && verdict(alvarado, picks(alvarado, yes: ["tender", "wbc", "temp", "shift", "rebound"])) == "Probable"
      && verdict(alvarado, picks(alvarado, yes: ["tender", "wbc", "temp", "shift", "rebound", "migration", "anorexia"])) == "Very probable")

// NEWS2 (RCP 2017)
let news: WardScore = WardScores.news2
check("NEWS2 respiration 12-20 0, 9-11 1, 21-24 2, <=8 3, >=25 3", points(news, "rr") == [0, 1, 2, 3, 3])
check("NEWS2 SpO2 scale 1: >=96 0, 94-95 1, 92-93 2, <=91 3", points(news, "spo2") == [0, 1, 2, 3])
check("NEWS2 oxygen 2", points(news, "air") == [0, 2])
check("NEWS2 systolic 0, 1, 2, 3, 3", points(news, "sbp") == [0, 1, 2, 3, 3])
check("NEWS2 pulse 0, 1, 1, 2, 3, 3", points(news, "pulse") == [0, 1, 1, 2, 3, 3])
check("NEWS2 consciousness 0 / 3", points(news, "acvpu") == [0, 3])
check("NEWS2 temperature 0, 1, 1, 2, 3", points(news, "temp") == [0, 1, 1, 2, 3])
check("NEWS2 maximum 20", news.highest == 20)
check("NEWS2 0 low, 4 low, 5 medium, 6 medium, 7 high",
      verdict(news, [:]) == "Low" && verdict(news, ["rr": 2, "air": 1]) == "Low"
      && verdict(news, ["rr": 2, "air": 1, "pulse": 1]) == "Medium"
      && verdict(news, ["rr": 2, "air": 1, "pulse": 3]) == "Medium"
      && verdict(news, ["rr": 2, "air": 1, "pulse": 3, "temp": 1]) == "High")
check("NEWS2 a single 3 with a total of 3 is low-medium", verdict(news, ["acvpu": 1]) == "Low\u{2013}medium")
check("NEWS2 a single 3 with a total of 5 stays medium", verdict(news, ["acvpu": 1, "air": 1]) == "Medium")
check("NEWS2 a total of 3 without any single 3 stays low", verdict(news, ["air": 1, "temp": 1]) == "Low")

// TIMI UA/NSTEMI (Antman 2000)
let timi: WardScore = WardScores.timi
check("TIMI seven items", timi.items.count == 7 && timi.highest == 7)
let timiDetails: [String] = [0, 1, 2, 3, 4, 5, 6, 7].map { timi.band(for: Double($0))?.detail ?? "" }
check("TIMI risks 4.7, 4.7, 8.3, 13.2, 19.9, 26.2, 40.9, 40.9",
      timiDetails[0].contains("4.7%") && timiDetails[1].contains("4.7%") && timiDetails[2].contains("8.3%")
      && timiDetails[3].contains("13.2%") && timiDetails[4].contains("19.9%") && timiDetails[5].contains("26.2%")
      && timiDetails[6].contains("40.9%") && timiDetails[7].contains("40.9%"))

// HEART (Six 2008; Backus 2013)
let heartScore: WardScore = WardScores.heart
check("HEART five items of 0-2", heartScore.items.count == 5 && heartScore.highest == 10)
check("HEART 3 low, 4 moderate, 6 moderate, 7 high",
      verdict(heartScore, ["history": 1, "age": 2]) == "Low" && verdict(heartScore, ["history": 2, "age": 2]) == "Moderate"
      && verdict(heartScore, ["history": 2, "age": 2, "risk": 2]) == "Moderate"
      && verdict(heartScore, ["history": 2, "age": 2, "risk": 2, "ecg": 1]) == "High")

// Bishop (Bishop 1964)
let bishop: WardScore = WardScores.bishop
check("Bishop maximum 13", bishop.highest == 13 && points(bishop, "dilation") == [0, 1, 2, 3]
      && points(bishop, "consistency") == [0, 1, 2] && points(bishop, "position") == [0, 1, 2])
check("Bishop 6 unfavourable, 7 favourable, 8 favourable, 9 very favourable",
      verdict(bishop, ["dilation": 2, "effacement": 2, "station": 2]) == "Unfavourable"
      && verdict(bishop, ["dilation": 2, "effacement": 2, "station": 2, "position": 1]) == "Favourable"
      && verdict(bishop, ["dilation": 2, "effacement": 2, "station": 2, "position": 2]) == "Favourable"
      && verdict(bishop, ["dilation": 2, "effacement": 2, "station": 2, "position": 2, "consistency": 1]) == "Very favourable")

// ABCD2 (Johnston 2007)
let abcd: WardScore = WardScores.abcd2
check("ABCD2 weights", points(abcd, "clinical") == [0, 1, 2] && points(abcd, "duration") == [0, 1, 2] && abcd.highest == 7)
check("ABCD2 3 low, 4 moderate, 5 moderate, 6 high",
      verdict(abcd, ["age": 1, "clinical": 2]) == "Low risk" && verdict(abcd, ["age": 1, "bp": 1, "clinical": 2]) == "Moderate risk"
      && verdict(abcd, ["age": 1, "bp": 1, "clinical": 2, "diabetes": 1]) == "Moderate risk"
      && verdict(abcd, ["age": 1, "bp": 1, "clinical": 2, "duration": 2]) == "High risk")
check("ABCD2 2-day risks 1.0, 4.1, 8.1", abcd.bands[0].detail.contains("1.0%") && abcd.bands[1].detail.contains("4.1%")
      && abcd.bands[2].detail.contains("8.1%"))

check("points read with a real minus", WardScores.points(-2) == "\u{2212}2" && WardScores.points(1.5) == "1.5")

print(failures.isEmpty ? "\nALL WARD POCKET TESTS PASS"
                       : "\n\(failures.count) WARD POCKET TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
