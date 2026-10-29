import Foundation

/// The evidence-based medicine arithmetic: a diagnostic test's 2 × 2 table,
/// likelihood ratios and post-test probability, and a trial's risks.
/// Foundation only.
enum Biostatistics {

    /// A diagnostic test against the reference standard.
    struct TwoByTwo: Hashable {
        var truePositive: Double, falsePositive: Double
        var falseNegative: Double, trueNegative: Double

        var total: Double { truePositive + falsePositive + falseNegative + trueNegative }
        var sensitivity: Double? { ratio(truePositive, truePositive + falseNegative) }
        var specificity: Double? { ratio(trueNegative, trueNegative + falsePositive) }
        var positivePredictive: Double? { ratio(truePositive, truePositive + falsePositive) }
        var negativePredictive: Double? { ratio(trueNegative, trueNegative + falseNegative) }
        var prevalence: Double? { ratio(truePositive + falseNegative, total) }
        var accuracy: Double? { ratio(truePositive + trueNegative, total) }
        var positiveLikelihood: Double? {
            guard let se = sensitivity, let sp = specificity, sp < 1 else { return nil }
            return se / (1 - sp)
        }
        var negativeLikelihood: Double? {
            guard let se = sensitivity, let sp = specificity, sp > 0 else { return nil }
            return (1 - se) / sp
        }

        private func ratio(_ a: Double, _ b: Double) -> Double? { b > 0 ? a / b : nil }

        /// The table for a test of `sensitivity` and `specificity` in
        /// `population` people with `prevalence` of the disease.
        static func from(sensitivity: Double, specificity: Double, prevalence: Double,
                         population: Double = 1000) -> TwoByTwo {
            let ill: Double = population * prevalence, well: Double = population - ill
            return TwoByTwo(truePositive: ill * sensitivity, falsePositive: well * (1 - specificity),
                            falseNegative: ill * (1 - sensitivity), trueNegative: well * specificity)
        }
    }

    /// Post-test probability from pre-test probability and a likelihood
    /// ratio, through odds: odds = p / (1 − p), post odds = odds × LR.
    static func postTest(pretest p: Double, likelihoodRatio lr: Double) -> Double {
        guard p > 0 else { return 0 }
        guard p < 1 else { return 1 }
        let odds: Double = p / (1 - p) * lr
        return odds / (1 + odds)
    }

    /// A trial's outcome in two groups.
    struct Trial: Hashable {
        var treatedEvents: Double, treatedTotal: Double
        var controlEvents: Double, controlTotal: Double

        var experimentalRate: Double? { treatedTotal > 0 ? treatedEvents / treatedTotal : nil }
        var controlRate: Double? { controlTotal > 0 ? controlEvents / controlTotal : nil }
        var relativeRisk: Double? {
            guard let e = experimentalRate, let c = controlRate, c > 0 else { return nil }
            return e / c
        }
        var absoluteRiskReduction: Double? {
            guard let e = experimentalRate, let c = controlRate else { return nil }
            return c - e
        }
        var relativeRiskReduction: Double? {
            guard let arr = absoluteRiskReduction, let c = controlRate, c > 0 else { return nil }
            return arr / c
        }
        /// Number needed to treat (harm, when negative), 1 / ARR.
        var numberNeededToTreat: Double? {
            guard let arr = absoluteRiskReduction, arr != 0 else { return nil }
            return 1 / arr
        }
        /// The odds ratio, (a/b) / (c/d) with b and d the non-events.
        var oddsRatio: Double? {
            let b: Double = treatedTotal - treatedEvents, d: Double = controlTotal - controlEvents
            guard b > 0, d > 0, controlEvents > 0 else { return nil }
            return (treatedEvents / b) / (controlEvents / d)
        }
    }
}
