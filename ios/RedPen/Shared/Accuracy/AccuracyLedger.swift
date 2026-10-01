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
    /// The server's claim gate (server/claims.js): what the item says that
    /// contradicts its own lecture - "negation", "dose", "frequency",
    /// "percentage" - or "gate_failed" when the gate could not tell. Any of
    /// them and the item is never Verified, whatever the votes say. Nil when
    /// the gate found nothing (or the check predates it).
    var claimHolds: [String]? = nil
}

/// What the server's /accuracy/check answers, as much of it as the device
/// keeps: per item, in the order sent, the votes, evidence, correction and
/// features, and the claim gate's hard findings. Everything is optional, so
/// an older or newer server's reply still decodes.
struct AccuracyCheckReply: Decodable {
    struct Finding: Decodable { var code: String? }
    struct Claims: Decodable {
        var hard: [Finding]?
        var partial: Bool?
    }
    struct Item: Decodable {
        var id: String?
        var votes: [AccuracyVote]?
        var evidence: [AccuracyEvidence]?
        var fix: AccuracySuggestion?
        var features: [String: Double]?
        var reason: String?
        var claims: Claims?
    }
    var items: [Item]?
    var limit: String?
    var message: String?
    /// true when no checker answered: nothing was checked (the server gave
    /// the allowance back) and the app should wait before the next batch
    var busy: Bool?

    /// The gate's code for "it failed on this item": held at Check this, and
    /// the item is asked about again later (its votes come from the cache).
    static let gateFailed = "gate_failed"
}

/// One item's standing, ready to show.
struct AccuracyAssessment: Hashable {
    var grade: AccuracyGrade
    var probability: Double
    var rules: [AccuracyRules.Hit]
    var record: AccuracyRecord?
    var features: [String: Double]

    /// Which rules, which of the claim gate's findings and which models
    /// raised a concern, in words.
    var reasons: [String] {
        var out: [String] = rules.map { $0.detail }
        for code in record?.claimHolds ?? [] { out.append(AccuracyAssessment.holdReason(code)) }
        for v in record?.votes ?? [] where v.risk >= 3 {
            let issue: String = v.issues.first ?? "Judged it likely to mislead (risk \(v.risk) of 4)."
            out.append(v.model + ": " + issue)
        }
        return out
    }

    static func holdReason(_ code: String) -> String {
        switch code {
        case "negation": return "Says the opposite of its own lecture."
        case "dose": return "Gives a different dose from its own lecture."
        case "frequency": return "Gives a different dosing frequency from its own lecture."
        case "percentage": return "Gives a different percentage from its own lecture."
        case AccuracyCheckReply.gateFailed: return "Couldn't be compared with its lecture yet; it will be checked again."
        default: return "Differs from its own lecture."
        }
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
        // the oath check: a dose, a diagnosis or a treatment needs evidence behind it
        var grade: AccuracyGrade = AccuracyModel.grade(p, f, weights: cutoffs, oath: AccuracyModel.isOath(item.checkedText))
        // the student said it is wrong: never shown as Verified to them again
        if record?.reported == true && grade == .verified { grade = .check }
        // it contradicts its own lecture (or the claim gate could not tell):
        // never Verified on the votes alone
        if !(record?.claimHolds ?? []).isEmpty && grade == .verified { grade = .check }
        return AccuracyAssessment(grade: grade, probability: p, rules: rules, record: record, features: f)
    }

    func summary(of items: [AccuracyItem], weights: AccuracyWeights = AccuracyModel.bundled) -> AccuracySummary {
        var s = AccuracySummary()
        for item in items { s.add(assess(item, weights: weights).grade) }
        return s
    }

    /// Checked already: a model voted on exactly this content, and the claim
    /// gate did not fail on it (an item it failed on is asked about again).
    func isChecked(_ hash: String) -> Bool {
        guard let record = records[hash], !record.votes.isEmpty else { return false }
        return !(record.claimHolds ?? []).contains(AccuracyCheckReply.gateFailed)
    }

    /// Worth trying again: never failed, or failed more than `after` ago.
    func mayRetry(_ hash: String, now: Date = Date(), after: TimeInterval = 6 * 3600) -> Bool {
        guard let when = failed[hash] else { return true }
        return now.timeIntervalSince(when) > after
    }

    /// A vote from a check made elsewhere - MedVAL screening a generated set,
    /// or the server's batch check - added to the item's record.
    /// `holds`: the claim gate's hard findings from that check, which replace
    /// any earlier ones (the server works them out afresh for every reply);
    /// nil from a check that has no gate, leaving them as they were.
    mutating func add(votes: [AccuracyVote], evidence: [AccuracyEvidence] = [], sourceMatch: Double? = nil,
                      fix: AccuracySuggestion? = nil, holds: [String]? = nil, for hash: String, at now: Date = Date()) {
        var record: AccuracyRecord = records[hash] ?? AccuracyRecord(hash: hash)
        for v in votes {
            record.votes.removeAll { $0.model == v.model }
            record.votes.append(v)
        }
        if !evidence.isEmpty { record.evidence = evidence }
        if let sourceMatch { record.sourceMatch = sourceMatch }
        if let fix { record.fix = fix }
        if let holds { record.claimHolds = holds.isEmpty ? nil : holds }
        record.checkedAt = now
        records[hash] = record
        if !votes.isEmpty { failed[hash] = nil }
    }

    /// The server's answer to a batch, item by item in the order sent: the
    /// votes and the claim gate's findings kept; an item with no vote marked
    /// failed (tried again later) unless the day's checks ran out; an item
    /// the gate failed on kept, held at Check this, and tried again later too.
    mutating func record(_ reply: AccuracyCheckReply?, for hashes: [String], at now: Date = Date()) {
        let replied: [AccuracyCheckReply.Item] = reply?.items ?? []
        for (n, hash) in hashes.enumerated() {
            guard n < replied.count, let votes = replied[n].votes, !votes.isEmpty else {
                if reply?.limit != "day" { failed[hash] = now }
                continue
            }
            let got: AccuracyCheckReply.Item = replied[n]
            let noSource: Bool = (got.features?["no_source"] ?? 1) > 0
            let match: Double? = noSource ? nil : got.features?["source_match"]
            let holds: [String] = (got.claims?.hard ?? []).map { $0.code ?? AccuracyCheckReply.gateFailed }
            add(votes: votes, evidence: got.evidence ?? [], sourceMatch: match, fix: got.fix, holds: holds, for: hash, at: now)
            if holds.contains(AccuracyCheckReply.gateFailed) { failed[hash] = now }
        }
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
