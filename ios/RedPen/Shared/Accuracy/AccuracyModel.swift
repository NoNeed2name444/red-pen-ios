import Foundation

/// Verified / Check this / Flagged - or not checked yet.
enum AccuracyGrade: String, Codable, CaseIterable {
    case verified, check, flagged, unchecked

    var title: String {
        switch self {
        case .verified: return "Verified"
        case .check: return "Check this"
        case .flagged: return "Flagged"
        case .unchecked: return "Not checked yet"
        }
    }

    var symbol: String {
        switch self {
        case .verified: return "checkmark.seal.fill"
        case .check: return "questionmark.diamond.fill"
        case .flagged: return "exclamationmark.triangle.fill"
        case .unchecked: return "clock"
        }
    }
}

/// One checker model's vote on one item, as the server returns it.
struct AccuracyVote: Codable, Hashable {
    var model: String = ""
    var risk: Int
    var answer: String? = nil
    /// "supports", "contradicts" or "none"
    var evidence: String = "none"
    var cites: [String] = []
    var issues: [String] = []
    var fix: AccuracySuggestion? = nil

    enum CodingKeys: String, CodingKey { case model, risk, answer, evidence, cites, issues, fix }

    init(model: String = "", risk: Int, answer: String? = nil, evidence: String = "none",
         cites: [String] = [], issues: [String] = [], fix: AccuracySuggestion? = nil) {
        self.model = model; self.risk = risk; self.answer = answer; self.evidence = evidence
        self.cites = cites; self.issues = issues; self.fix = fix
    }

    /// Anything the server leaves out takes its default, so a reply from a
    /// newer or older server still decodes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        risk = try c.decode(Int.self, forKey: .risk)
        answer = try c.decodeIfPresent(String.self, forKey: .answer)
        evidence = try c.decodeIfPresent(String.self, forKey: .evidence) ?? "none"
        cites = try c.decodeIfPresent([String].self, forKey: .cites) ?? []
        issues = try c.decodeIfPresent([String].self, forKey: .issues) ?? []
        fix = try c.decodeIfPresent(AccuracySuggestion.self, forKey: .fix)
    }
}

/// A correction the checkers offered: a new key letter, or new wording for
/// the explanation, the answer or the text.
struct AccuracySuggestion: Codable, Hashable {
    var field: String
    var value: String
    var by: [String]? = nil
}

/// A source the checkers were shown, to cite in the "why" sheet.
struct AccuracyEvidence: Codable, Hashable {
    var id: String
    var source: String
    var title: String
    var url: String
}

/// The weights the app scores with: bundled below, replaced by whatever the
/// last training run published (server /accuracy/model).
struct AccuracyWeights: Codable, Hashable {
    struct Thresholds: Codable, Hashable {
        var verified: Double
        var flagged: Double
    }
    var version: String
    var features: [String]
    var weights: [Double]
    var thresholds: Thresholds

    var isValid: Bool {
        features.count == weights.count && features.allSatisfy { AccuracyModel.features.contains($0) }
            && weights.allSatisfy { $0.isFinite } && thresholds.flagged < thresholds.verified
            && thresholds.verified <= 1 && thresholds.flagged >= 0
    }
}

/// The app's accuracy model: every signal about an item - the checker
/// models' votes, the literature they were shown, the rule checks, how much
/// of the item its lecture contains - into one calibrated P(accurate).
///
/// The same logistic regression as server/accuracy-model.js, trained on
/// GitHub Actions (server/bench/train-accuracy.mjs); the phone keeps each
/// item's raw features, so new weights re-score the library without a single
/// new check.
enum AccuracyModel {

    static let features: [String] = [
        "bias", "rule_severe", "rule_minor", "risk_max", "risk_mean", "flag_frac", "disagree", "voters",
        "key_disagree", "ev_support", "ev_contradict", "ev_count", "source_match", "no_source", "no_models",
        "kind_mcq", "kind_card", "kind_case", "kind_osce", "kind_page",
    ]

    // BEGIN DEFAULT WEIGHTS (kept identical to server/accuracy-model.js)
    /// One weight a line, by feature name (the server keeps them as a list
    /// in `features` order).
    static let defaultJSON: String = """
        {"version": "prior-1",
         "weights": {
            "bias": 3.0,
            "rule_severe": -2.5,
            "rule_minor": -0.4,
            "risk_max": -2.5,
            "risk_mean": -1.5,
            "flag_frac": -2.0,
            "disagree": -0.5,
            "voters": 0.3,
            "key_disagree": -2.5,
            "ev_support": 0.8,
            "ev_contradict": -2.5,
            "ev_count": 0.1,
            "source_match": 0.8,
            "no_source": -0.3,
            "no_models": -1.5,
            "kind_mcq": 0,
            "kind_card": 0,
            "kind_case": 0,
            "kind_osce": 0,
            "kind_page": 0
         },
         "thresholds": {"verified": 0.85, "flagged": 0.4}}
        """
    // END DEFAULT WEIGHTS

    private struct Prior: Decodable {
        var version: String
        var weights: [String: Double]
        var thresholds: AccuracyWeights.Thresholds
    }

    static let bundled: AccuracyWeights = {
        let data = Data(defaultJSON.utf8)
        let prior: Prior? = try? JSONDecoder().decode(Prior.self, from: data)
        let values: [Double] = features.map { prior?.weights[$0] ?? 0 }
        return AccuracyWeights(version: prior?.version ?? "prior-1", features: features, weights: values,
                               thresholds: prior?.thresholds ?? .init(verified: 0.85, flagged: 0.4))
    }()

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// The feature values for one item (the same as features() on the server).
    static func featureValues(kind: AccuracyKind, rules: [AccuracyRules.Hit], votes: [AccuracyVote],
                              evidenceCount: Int, sourceMatch: Double?, keyLetter: String?) -> [String: Double] {
        let risks: [Double] = votes.map { clamp01(Double($0.risk - 1) / 3) }
        let flags: [Bool] = votes.map { $0.risk >= 3 }
        let answered: [AccuracyVote] = votes.filter { v in
            guard let a = v.answer, a.count == 1 else { return false }
            return "ABCDEFGHIJ".contains(a)
        }
        let n: Double = Double(votes.count)
        let flagCount: Double = Double(flags.filter { $0 }.count)
        var f: [String: Double] = [:]
        f["bias"] = 1
        f["rule_severe"] = Double(min(2, rules.filter(\.isSevere).count))
        f["rule_minor"] = Double(min(3, rules.filter { !$0.isSevere }.count))
        f["risk_max"] = risks.max() ?? 0
        f["risk_mean"] = risks.isEmpty ? 0 : risks.reduce(0, +) / n
        f["flag_frac"] = flags.isEmpty ? 0 : flagCount / n
        let split: Bool = flags.count > 1 && flags.contains(true) && flags.contains(false)
        f["disagree"] = split ? 1 : 0
        f["voters"] = Double(min(3, votes.count)) / 3
        var keyDisagree: Double = 0
        if kind == .mcq, let keyLetter, !answered.isEmpty {
            let other: Int = answered.filter { $0.answer != keyLetter }.count
            keyDisagree = Double(other) / Double(answered.count)
        }
        f["key_disagree"] = keyDisagree
        f["ev_support"] = votes.isEmpty ? 0 : Double(votes.filter { $0.evidence == "supports" }.count) / n
        f["ev_contradict"] = votes.isEmpty ? 0 : Double(votes.filter { $0.evidence == "contradicts" }.count) / n
        f["ev_count"] = Double(min(5, evidenceCount)) / 5
        f["source_match"] = sourceMatch.map(clamp01) ?? 0
        f["no_source"] = sourceMatch == nil ? 1 : 0
        f["no_models"] = votes.isEmpty ? 1 : 0
        f["kind_mcq"] = kind == .mcq ? 1 : 0
        f["kind_card"] = kind == .card ? 1 : 0
        f["kind_case"] = kind == .case ? 1 : 0
        f["kind_osce"] = kind == .osce ? 1 : 0
        let pageLike: Bool = kind == .page || kind == .fact || kind == .note
        f["kind_page"] = pageLike ? 1 : 0
        return f
    }

    static func probability(_ f: [String: Double], weights w: AccuracyWeights = bundled) -> Double {
        var z: Double = 0
        for (i, name) in w.features.enumerated() where i < w.weights.count {
            z += (f[name] ?? 0) * w.weights[i]
        }
        z = max(-40, min(40, z))
        return 1 / (1 + exp(-z))
    }

    /// Rules alone can flag an item but never verify one; a severe rule hit
    /// keeps an item from Verified whatever the models said.
    static func grade(_ p: Double, _ f: [String: Double], weights w: AccuracyWeights = bundled) -> AccuracyGrade {
        let severe: Bool = (f["rule_severe"] ?? 0) > 0
        if (f["no_models"] ?? 1) > 0 { return severe ? .flagged : .unchecked }
        if p < w.thresholds.flagged { return .flagged }
        if p >= w.thresholds.verified && !severe { return .verified }
        return .check
    }
}
