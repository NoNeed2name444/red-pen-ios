import Foundation

/// The verification layer's first stage on newly generated material, before
/// it is saved. It replaces the single-model accuracy checker (MedVAL) the
/// generators used to wait on (the owner, 1 Oct): the same sensors the Worker
/// runs (AccuracyRules), on the device and instant.
///
/// An item broken in its structure is removed, since it cannot be learned
/// from: no key, a key its own explanation contradicts or calls wrong, a
/// distractor that copies the key, "all of the above" keyed beside "none of
/// the above" (DNA brief: an unrecoverable item is removed cleanly, with its
/// reason). Everything else is kept. A medical red flag - a dose outside any
/// usual range, a retired practice, a look-alike drug, an impossible result -
/// grades the item Flagged, which holds it out of review and mock papers
/// until the checkers clear it (AccuracyHolds). The rest of the layer - two
/// model families solving blind, the literature, the calibrated verdict -
/// takes the set as soon as it is saved: AccuracyStore watches the library.
enum VerificationScreen {
    /// Hits that make an item unusable as written.
    static func breaks(_ hit: AccuracyRules.Hit) -> Bool {
        switch hit.rule {
        case "no-key", "key-explanation-conflict", "key-called-wrong", "all-above-contradiction": return true
        case "duplicate-option": return hit.isSevere
        default: return false
        }
    }

    /// Why an item was removed, in words.
    static func reason(_ rule: String) -> String {
        switch rule {
        case "no-key": return "no answer key"
        case "key-explanation-conflict", "key-called-wrong": return "key contradicted by its explanation"
        case "duplicate-option": return "two identical correct options"
        case "all-above-contradiction": return "contradictory \u{201C}of the above\u{201D} options"
        default: return rule
        }
    }

    struct Outcome<Item> {
        var kept: [Item] = []
        /// Removed items, counted by reason, in the order first met.
        var removed: [(reason: String, count: Int)] = []
        /// Kept but held for the checkers: a severe medical red flag.
        var held: Int = 0
        var removedCount: Int { removed.reduce(0) { $0 + $1.count } }
    }

    static func questions(_ questions: [MCQQuestion]) -> Outcome<MCQQuestion> {
        screen(questions) { AccuracyItem.mcq($0) }
    }

    static func stations(_ stations: [OsceChecklist]) -> Outcome<OsceChecklist> {
        screen(stations) { AccuracyItem.osce($0) }
    }

    static func cards(_ cards: [AnkiCard]) -> Outcome<AnkiCard> {
        screen(cards) { AccuracyItem.card($0) }
    }

    static func screen<Item>(_ items: [Item], as item: (Item) -> AccuracyItem?) -> Outcome<Item> {
        var out = Outcome<Item>()
        for thing in items {
            guard let checked = item(thing) else { out.kept.append(thing); continue }
            let hits: [AccuracyRules.Hit] = AccuracyRules.hits(checked)
            if let broken = hits.first(where: breaks) {
                let why: String = reason(broken.rule)
                if let at = out.removed.firstIndex(where: { $0.reason == why }) { out.removed[at].count += 1 }
                else { out.removed.append((why, 1)) }
                continue
            }
            if hits.contains(where: { $0.isSevere }) { out.held += 1 }
            out.kept.append(thing)
        }
        return out
    }

    /// The status line's sentence: what the on-device checks did, and that
    /// the independent checkers are on the rest. Empty when nothing was made.
    static func note<Item>(_ outcome: Outcome<Item>) -> String {
        guard !outcome.kept.isEmpty || outcome.removedCount > 0 else { return "" }
        var parts: [String] = []
        if outcome.removedCount > 0 {
            let reasons: String = outcome.removed.map { "\($0.count) \($0.reason)" }.joined(separator: ", ")
            parts.append("\(outcome.removedCount) removed (\(reasons))")
        }
        if outcome.held > 0 { parts.append("\(outcome.held) held for a red flag") }
        let device: String = parts.isEmpty ? " On-device checks passed." : " On-device checks: " + parts.joined(separator: "; ") + "."
        return device + " The independent checkers are verifying the rest now."
    }
}
