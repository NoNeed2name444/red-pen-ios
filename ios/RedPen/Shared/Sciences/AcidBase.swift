import Foundation

/// Reads an arterial blood gas the way the stepwise method teaches it:
/// acidaemia or alkalaemia, the primary disorder, whether the compensation
/// is what the rules expect, the anion gap (corrected for albumin), and the
/// delta ratio when the gap is raised.
///
/// The rules are the standard bedside ones:
/// - Henderson-Hasselbalch, pH = 6.1 + log10(HCO3 / (0.03 × PaCO2)), to
///   check the three numbers belong together;
/// - metabolic acidosis: Winter's formula, PaCO2 = 1.5 × HCO3 + 8 (± 2);
/// - metabolic alkalosis: PaCO2 = 0.7 × HCO3 + 21 (± 2);
/// - respiratory acidosis: HCO3 rises 1 per 10 mmHg of PaCO2 above 40
///   when acute, 3.5 when chronic;
/// - respiratory alkalosis: HCO3 falls 2 per 10 mmHg when acute, 5 when
///   chronic;
/// - anion gap = Na − (Cl + HCO3), about 8 to 12, plus 2.5 for every 10 g/L
///   of albumin below 40;
/// - delta ratio = (gap − 12) / (24 − HCO3).
///
/// Pressures are in mmHg (`kPa` converts); concentrations in mmol/L,
/// albumin in g/L. Foundation only.
enum AcidBase {

    struct Gas: Hashable {
        var pH: Double
        var paco2: Double
        var hco3: Double
        var sodium: Double? = nil
        var chloride: Double? = nil
        var albumin: Double? = nil
    }

    /// mmHg from kPa.
    static func mmHg(kPa: Double) -> Double { kPa * LungGas.mmHgPerKPa }

    enum Disorder: String, Hashable, CaseIterable {
        case metabolicAcidosis, metabolicAlkalosis, respiratoryAcidosis, respiratoryAlkalosis

        var name: String {
            switch self {
            case .metabolicAcidosis: return "metabolic acidosis"
            case .metabolicAlkalosis: return "metabolic alkalosis"
            case .respiratoryAcidosis: return "respiratory acidosis"
            case .respiratoryAlkalosis: return "respiratory alkalosis"
            }
        }
    }

    struct Reading: Hashable {
        /// Every disorder found, the primary first.
        var disorders: [Disorder]
        /// For a respiratory disorder: acute, chronic, or between.
        var timing: String?
        var anionGap: Double?
        var correctedGap: Double?
        var deltaRatio: Double?
        /// pH the three numbers predict.
        var predictedPH: Double
        /// Whether the gas's own pH agrees with it (within 0.05).
        var consistent: Bool
        /// The method's steps, in order, in the student's words.
        var steps: [String]

        var primary: Disorder? { disorders.first }
        var isNormal: Bool { disorders.isEmpty }
        var highGap: Bool { (correctedGap ?? anionGap ?? 0) > 12 }
    }

    static func predictedPH(hco3: Double, paco2: Double) -> Double {
        guard hco3 > 0, paco2 > 0 else { return .nan }
        return 6.1 + log10(hco3 / (0.03 * paco2))
    }

    static func anionGap(sodium: Double, chloride: Double, hco3: Double) -> Double {
        sodium - (chloride + hco3)
    }

    /// The gap corrected for albumin (g/L): + 2.5 per 10 g/L below 40.
    static func correctedGap(_ gap: Double, albumin: Double) -> Double {
        gap + 2.5 * (40 - albumin) / 10
    }

    static func winters(hco3: Double) -> Double { 1.5 * hco3 + 8 }
    static func expectedPaCO2InAlkalosis(hco3: Double) -> Double { 0.7 * hco3 + 21 }
    static func expectedHCO3(paco2: Double, acidosis: Bool, chronic: Bool) -> Double {
        let per10: Double = acidosis ? (chronic ? 3.5 : 1) : (chronic ? 5 : 2)
        return 24 + (paco2 - 40) / 10 * per10
    }

    private static func f(_ x: Double, _ digits: Int = 0) -> String {
        String(format: "%.\(digits)f", x)
    }

    static func read(_ g: Gas) -> Reading {
        var steps: [String] = []
        var disorders: [Disorder] = []
        var timing: String? = nil
        let predicted: Double = predictedPH(hco3: g.hco3, paco2: g.paco2)
        let consistent: Bool = abs(predicted - g.pH) <= 0.05
        if !consistent {
            steps.append("Check: these values predict a pH of \(f(predicted, 2)), not \(f(g.pH, 2)). Recheck the numbers before reading on.")
        }
        let acidaemia: Bool = g.pH < 7.35, alkalaemia: Bool = g.pH > 7.45
        let highCO2: Bool = g.paco2 > 45, lowCO2: Bool = g.paco2 < 35
        let lowHCO3: Bool = g.hco3 < 22, highHCO3: Bool = g.hco3 > 26
        steps.append(acidaemia ? "pH \(f(g.pH, 2)) is acidaemia."
                     : alkalaemia ? "pH \(f(g.pH, 2)) is alkalaemia."
                     : "pH \(f(g.pH, 2)) is within 7.35 to 7.45.")

        if acidaemia {
            if highCO2 && lowHCO3 {
                disorders = [.respiratoryAcidosis, .metabolicAcidosis]
                steps.append("Both the PaCO2 (\(f(g.paco2))) and the bicarbonate (\(f(g.hco3))) push the pH down: a mixed respiratory and metabolic acidosis.")
            } else if lowHCO3 {
                disorders = [.metabolicAcidosis]
                steps.append("Bicarbonate \(f(g.hco3)) is low and explains the acidaemia: a primary metabolic acidosis.")
            } else if highCO2 {
                disorders = [.respiratoryAcidosis]
                steps.append("PaCO2 \(f(g.paco2)) is high and explains the acidaemia: a primary respiratory acidosis.")
            }
        } else if alkalaemia {
            if lowCO2 && highHCO3 {
                disorders = [.respiratoryAlkalosis, .metabolicAlkalosis]
                steps.append("Both a low PaCO2 and a high bicarbonate push the pH up: a mixed respiratory and metabolic alkalosis.")
            } else if highHCO3 {
                disorders = [.metabolicAlkalosis]
                steps.append("Bicarbonate \(f(g.hco3)) is high and explains the alkalaemia: a primary metabolic alkalosis.")
            } else if lowCO2 {
                disorders = [.respiratoryAlkalosis]
                steps.append("PaCO2 \(f(g.paco2)) is low and explains the alkalaemia: a primary respiratory alkalosis.")
            }
        } else {
            if lowHCO3 && lowCO2 {
                disorders = [.metabolicAcidosis, .respiratoryAlkalosis]
                steps.append("A normal pH with a low bicarbonate and a low PaCO2: two disorders cancelling, a metabolic acidosis with a respiratory alkalosis (full compensation is rare).")
            } else if highHCO3 && highCO2 {
                disorders = [.respiratoryAcidosis, .metabolicAlkalosis]
                steps.append("A normal pH with a high bicarbonate and a high PaCO2: a respiratory acidosis with a metabolic alkalosis, or a long-standing respiratory acidosis fully compensated.")
            } else if lowHCO3 || highHCO3 || lowCO2 || highCO2 {
                steps.append("Only one value is outside its range and the pH is normal: look at the anion gap and the history.")
            } else {
                steps.append("PaCO2 and bicarbonate are in range: no acid-base disorder on this gas.")
            }
        }

        // Compensation, for a single primary disorder.
        if disorders.count == 1, let primary = disorders.first {
            switch primary {
            case .metabolicAcidosis:
                let e: Double = winters(hco3: g.hco3)
                steps.append("Winter's formula expects a PaCO2 of \(f(e)) ± 2 (1.5 × \(f(g.hco3)) + 8).")
                if g.paco2 > e + 2 {
                    disorders.append(.respiratoryAcidosis)
                    steps.append("PaCO2 \(f(g.paco2)) is higher than that: a respiratory acidosis as well (the lungs are not keeping up).")
                } else if g.paco2 < e - 2 {
                    disorders.append(.respiratoryAlkalosis)
                    steps.append("PaCO2 \(f(g.paco2)) is lower than that: a respiratory alkalosis as well.")
                } else {
                    steps.append("PaCO2 \(f(g.paco2)) fits: the breathing is compensating as expected.")
                }
            case .metabolicAlkalosis:
                let e: Double = expectedPaCO2InAlkalosis(hco3: g.hco3)
                steps.append("Expected PaCO2 is \(f(e)) ± 2 (0.7 × \(f(g.hco3)) + 21).")
                if g.paco2 > e + 2 {
                    disorders.append(.respiratoryAcidosis)
                    steps.append("PaCO2 \(f(g.paco2)) is higher: a respiratory acidosis as well.")
                } else if g.paco2 < e - 2 {
                    disorders.append(.respiratoryAlkalosis)
                    steps.append("PaCO2 \(f(g.paco2)) is lower: a respiratory alkalosis as well.")
                } else {
                    steps.append("PaCO2 \(f(g.paco2)) fits the expected compensation.")
                }
            case .respiratoryAcidosis, .respiratoryAlkalosis:
                let acid: Bool = primary == .respiratoryAcidosis
                let acute: Double = expectedHCO3(paco2: g.paco2, acidosis: acid, chronic: false)
                let chronic: Double = expectedHCO3(paco2: g.paco2, acidosis: acid, chronic: true)
                steps.append("Expected bicarbonate: \(f(acute)) if acute, \(f(chronic)) if chronic.")
                let low: Double = min(acute, chronic) - 2, high: Double = max(acute, chronic) + 2
                if abs(g.hco3 - acute) <= 2 {
                    timing = "acute"
                    steps.append("Bicarbonate \(f(g.hco3)) fits an acute disorder: the kidneys have not had time to respond.")
                } else if abs(g.hco3 - chronic) <= 2 {
                    timing = "chronic"
                    steps.append("Bicarbonate \(f(g.hco3)) fits a chronic disorder: the kidneys have compensated over days.")
                } else if g.hco3 > low && g.hco3 < high {
                    timing = "between"
                    steps.append("Bicarbonate \(f(g.hco3)) lies between: acute on chronic, or still compensating.")
                } else if g.hco3 > high {
                    disorders.append(.metabolicAlkalosis)
                    steps.append("Bicarbonate \(f(g.hco3)) is higher than either: a metabolic alkalosis as well.")
                } else {
                    disorders.append(.metabolicAcidosis)
                    steps.append("Bicarbonate \(f(g.hco3)) is lower than either: a metabolic acidosis as well.")
                }
            }
        }

        // The anion gap, whenever the electrolytes are given.
        var gap: Double? = nil, corrected: Double? = nil, delta: Double? = nil
        if let na = g.sodium, let cl = g.chloride {
            let ag: Double = anionGap(sodium: na, chloride: cl, hco3: g.hco3)
            gap = ag
            var used: Double = ag
            var line: String = "Anion gap = \(f(na)) − (\(f(cl)) + \(f(g.hco3))) = \(f(ag))"
            if let alb = g.albumin {
                let c: Double = correctedGap(ag, albumin: alb)
                corrected = c
                used = c
                line += ", \(f(c)) corrected for albumin \(f(alb)) g/L"
            }
            line += "."
            steps.append(line)
            if used > 12 {
                steps.append("The gap is raised: unmeasured acids (lactate, ketones, toxic alcohols, salicylate, uraemia).")
                if !disorders.contains(.metabolicAcidosis) { disorders.append(.metabolicAcidosis) }
                if g.hco3 < 24 {
                    let d: Double = (used - 12) / (24 - g.hco3)
                    delta = d
                    let meaning: String
                    if d < 0.4 { meaning = "a normal-gap (hyperchloraemic) acidosis is most of the picture" }
                    else if d < 0.8 { meaning = "a raised-gap and a normal-gap acidosis together" }
                    else if d <= 2 { meaning = "a pure raised-gap acidosis" }
                    else { meaning = "a raised-gap acidosis with a metabolic alkalosis (or a chronic respiratory acidosis) underneath" }
                    steps.append("Delta ratio \(f(d, 1)): \(meaning).")
                } else {
                    steps.append("A raised gap with a bicarbonate that has not fallen: a raised-gap acidosis hidden by a metabolic alkalosis.")
                }
            } else if disorders.contains(.metabolicAcidosis) {
                steps.append("The gap is normal: a hyperchloraemic acidosis (diarrhoea, renal tubular acidosis, saline).")
            }
        }
        return Reading(disorders: disorders, timing: timing, anionGap: gap, correctedGap: corrected,
                       deltaRatio: delta, predictedPH: predicted, consistent: consistent, steps: steps)
    }
}
