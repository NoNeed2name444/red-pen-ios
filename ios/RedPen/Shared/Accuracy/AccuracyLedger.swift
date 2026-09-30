import Foundation

/// What was found about one item, kept by its content hash: the checker
/// models' votes, the evidence they were shown, how much of it the lecture
/// contains, and the correction they offered. Never the verdict itself - that
/// is worked out from these whenever it is shown, so new model weights
/// re-score everything without a new check.
struct AccuracyRecord: Codable, Hashable {
    var hash: String
    var votes: [AccuracyVote] = []
    var evidence: [AccuracyEvidence] = []
    var sourceMatch: Double? = nil
    var fix: AccuracySuggestion? = nil
    var checkedAt: Date = Date()
    /// The student reported this item as wrong.
    var reported: Bool = false
}

/// One item's standing, ready to show.
struct AccuracyAssessment: Hashable {
    var grade: AccuracyGrade
    var probability: Double
    var rules: [AccuracyRules.Hit]
    var record: AccuracyRecord?
    var features: [String: Double]

    /// Which rules and which models raised a concern, in words.
    var reasons: [String] {
        var out: [String] = rules.map { $0.detail }
        for v in record?.votes ?? [] where v.risk >= 3 {
            let issue: String = v.issues.first ?? "Judged it likely to mislead (risk \(v.risk) of 4)."
            out.append(v.model + ": " + issue)
        }
        return out
    }
}

/// Counts of each grade in a set.
struct AccuracySummary: Hashable {
    var verified = 0, check = 0, flagged = 0, unchecked = 0
    var total: Int { verified + check + flagged + unchecked }
    var checked: Int { verified + check + flagged }

    mutating func add(_ grade: AccuracyGrade) {
        switch grade {
        case .verified: verified += 1
        case .check: check += 1
        case .flagged: flagged += 1
        case .unchecked: unchecked += 1
        }
    }

    /// "12 verified · 2 to check · 1 flagged", or nil before anything is checked.
    var line: String? {
        guard checked > 0 || flagged > 0 else { return nil }
        var parts: [String] = []
        if verified > 0 { parts.append("\(verified) verified") }
        if check > 0 { parts.append("\(check) to check") }
        if flagged > 0 { parts.append("\(flagged) flagged") }
        if unchecked > 0 { parts.append("\(unchecked) not yet checked") }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The badge for the whole set: flagged if anything is, verified only
    /// when everything is.
    var grade: AccuracyGrade {
        if flagged > 0 { return .flagged }
        if check > 0 { return .check }
        if verified > 0 && unchecked == 0 { return .verified }
        return .unchecked
    }
}

/// Every record on this device, and what each means. Pure, so the whole of
/// it is tested on Linux; AccuracyStore keeps it on disk.
struct AccuracyLedger: Codable {
    var records: [String: AccuracyRecord] = [:]
    /// Items whose check came back with no vote, and when: tried again after
    /// a while rather than on every pass.
    var failed: [String: Date] = [:]

    func assess(_ item: AccuracyItem, weights: AccuracyWeights = AccuracyModel.bundled) -> AccuracyAssessment {
        let hash: String = item.contentHash
        let record: AccuracyRecord? = records[hash]
        let rules: [AccuracyRules.Hit] = AccuracyRules.hits(item)
        let key: String? = item.kind == .mcq && item.options.indices.contains(item.key) ? AccuracyItem.letter(item.key) : nil
        let match: Double? = record?.sourceMatch ?? AccuracyRules.sourceMatch(item)
        let f: [String: Double] = AccuracyModel.featureValues(kind: item.kind, rules: rules, votes: record?.votes ?? [],
                                                             evidenceCount: record?.evidence.count ?? 0,
                                                             sourceMatch: match, keyLetter: key)
        let p: Double = AccuracyModel.probability(f, weights: weights)
        // the chosen exam's management questions need more to be Verified
        var cutoffs: AccuracyWeights = weights
        let strict: Double = AccuracyModel.examStrictness(for: item)
        if strict > 0 { cutoffs.thresholds = AccuracyModel.stricter(weights.thresholds, by: strict) }
        var grade: AccuracyGrade = AccuracyModel.grade(p, f, weights: cutoffs)
        // the student said it is wrong: never shown as Verified to them again
        if record?.reported == true && grade == .verified { grade = .check }
        return AccuracyAssessment(grade: grade, probability: p, rules: rules, record: record, features: f)
    }

    func summary(of items: [AccuracyItem], weights: AccuracyWeights = AccuracyModel.bundled) -> AccuracySummary {
        var s = AccuracySummary()
        for item in items { s.add(assess(item, weights: weights).grade) }
        return s
    }

    /// Checked already: a model voted on exactly this content.
    func isChecked(_ hash: String) -> Bool {
        !(records[hash]?.votes.isEmpty ?? true)
    }

    /// Worth trying again: never failed, or failed more than `after` ago.
    func mayRetry(_ hash: String, now: Date = Date(), after: TimeInterval = 6 * 3600) -> Bool {
        guard let when = failed[hash] else { return true }
        return now.timeIntervalSince(when) > after
    }

    /// A vote from a check made elsewhere - MedVAL screening a generated set,
    /// or the server's batch check - added to the item's record.
    mutating func add(votes: [AccuracyVote], evidence: [AccuracyEvidence] = [], sourceMatch: Double? = nil,
                      fix: AccuracySuggestion? = nil, for hash: String, at now: Date = Date()) {
        var record: AccuracyRecord = records[hash] ?? AccuracyRecord(hash: hash)
        for v in votes {
            record.votes.removeAll { $0.model == v.model }
            record.votes.append(v)
        }
        if !evidence.isEmpty { record.evidence = evidence }
        if let sourceMatch { record.sourceMatch = sourceMatch }
        if let fix { record.fix = fix }
        record.checkedAt = now
        records[hash] = record
        if !votes.isEmpty { failed[hash] = nil }
    }

    mutating func markReported(_ hash: String) {
        var record: AccuracyRecord = records[hash] ?? AccuracyRecord(hash: hash)
        record.reported = true
        records[hash] = record
    }

    /// Only the records some item still has: an edited or deleted item's old
    /// record would otherwise stay for ever.
    mutating func prune(keeping live: Set<String>) {
        records = records.filter { live.contains($0.key) }
        failed = failed.filter { live.contains($0.key) }
    }
}
