import Foundation

/// A batch the engine sends to /accuracy/check: up to four items of one set.
struct AccuracyBatch: Hashable {
    var setID: UUID
    var items: [AccuracyItem]
    /// "foreground" for content just made or edited (checked before the
    /// student studies it, on the day's main allowance), "background" for the
    /// rest of the library (a smaller share, low priority).
    var priority: String
}

/// Which items to check next, and in what order. Pure, so it is tested.
///
/// New and just-edited sets first - their items are what the student is about
/// to study - then the rest of the library, most-studied first, then newest.
/// Nothing is sent twice: an item a model has already voted on (by content
/// hash) is skipped, and one whose last check failed waits a few hours.
/// Notes are never in here; they are checked only when the student asks.
enum AccuracySchedule {

    static let batchSize = 4
    /// How recent a change still counts as "just made": checked in the foreground.
    static let freshWindow: TimeInterval = 15 * 60
    /// How recent a set is to count as new in the background order.
    static let newWindow: TimeInterval = 7 * 24 * 3600

    static func plan(sets: [StudySet],
                     items: (StudySet) -> [AccuracyItem],
                     ledger: AccuracyLedger,
                     studied: [UUID: Int] = [:],
                     now: Date = Date(),
                     limit: Int = 40) -> [AccuracyBatch] {
        let ordered: [StudySet] = order(sets, studied: studied, now: now)
        var out: [AccuracyBatch] = []
        var planned = 0
        var hashes = Set<String>()
        for set in ordered {
            if planned >= limit { break }
            let fresh: Bool = now.timeIntervalSince(set.updatedAt) < freshWindow
            var pending: [AccuracyItem] = []
            for item in items(set) {
                if planned + pending.count >= limit { break }
                let hash: String = item.contentHash
                if ledger.isChecked(hash) || !ledger.mayRetry(hash, now: now) || hashes.contains(hash) { continue }
                hashes.insert(hash)
                pending.append(item)
            }
            planned += pending.count
            var start = 0
            while start < pending.count {
                let end: Int = min(start + batchSize, pending.count)
                out.append(AccuracyBatch(setID: set.id, items: Array(pending[start..<end]),
                                         priority: fresh ? "foreground" : "background"))
                start = end
            }
        }
        // just-made content first, whatever the order above
        let foreground: [AccuracyBatch] = out.filter { $0.priority == "foreground" }
        let background: [AccuracyBatch] = out.filter { $0.priority != "foreground" }
        return foreground + background
    }

    /// New sets (changed this week) first, then by how much they are
    /// studied, then newest.
    static func order(_ sets: [StudySet], studied: [UUID: Int], now: Date) -> [StudySet] {
        sets.sorted { a, b in
            let aNew: Bool = now.timeIntervalSince(a.updatedAt) < newWindow
            let bNew: Bool = now.timeIntervalSince(b.updatedAt) < newWindow
            if aNew != bNew { return aNew }
            let sa: Int = studied[a.id] ?? 0
            let sb: Int = studied[b.id] ?? 0
            if sa != sb { return sa > sb }
            return a.updatedAt > b.updatedAt
        }
    }
}

/// A checker's correction, applied to the item it is about. Pure.
enum AccuracyFix {

    /// Whether this suggestion can be applied to this kind of item with one tap.
    static func canApply(_ s: AccuracySuggestion, to item: AccuracyItem) -> Bool {
        switch (item.kind, s.field) {
        case (.mcq, "key"): return keyIndex(s.value, count: item.options.count) != nil
        case (.mcq, "explanation"), (.card, "explanation"), (.card, "answer"), (.case, "answer"): return true
        case (.osce, "text"), (.osce, "answer"): return lines(s.value).count >= 2
        default: return false
        }
    }

    static func keyIndex(_ value: String, count: Int) -> Int? {
        let trimmed: String = value.trimmingCharacters(in: .whitespaces).uppercased()
        guard let scalar = trimmed.unicodeScalars.first, trimmed.count == 1 else { return nil }
        let i: Int = Int(scalar.value) - 65
        return i >= 0 && i < count ? i : nil
    }

    static func lines(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•\t")) }
            .filter { !$0.isEmpty }
    }

    /// The set with the correction made to the item `itemID`, or nil when it
    /// does not apply. Editing the item changes its hash, so it is checked again.
    static func apply(_ s: AccuracySuggestion, toItem itemID: String, in set: StudySet) -> StudySet? {
        var out: StudySet = set
        let value: String = s.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let i = out.questions.firstIndex(where: { $0.id.uuidString == itemID }) {
            switch s.field {
            case "key":
                guard let k = keyIndex(value, count: out.questions[i].options.count) else { return nil }
                out.questions[i].correctIndex = k
            case "explanation":
                out.questions[i].explanation = value
            default:
                return nil
            }
            return out
        }
        if let i = out.cards.firstIndex(where: { $0.id.uuidString == itemID }) {
            switch s.field {
            case "explanation": out.cards[i].why = value
            case "answer":
                if out.cards[i].type == .cloze { out.cards[i].clozeText = value } else { out.cards[i].bullets = lines(value) }
            default: return nil
            }
            return out
        }
        if let i = out.qaCards.firstIndex(where: { $0.id.uuidString == itemID }) {
            guard s.field == "answer" else { return nil }
            out.qaCards[i].answer = lines(value)
            return out
        }
        if let i = out.osceChecklists.firstIndex(where: { $0.id.uuidString == itemID }) {
            let steps: [String] = lines(value)
            guard steps.count >= 2, s.field == "text" || s.field == "answer" else { return nil }
            out.osceChecklists[i].steps = steps
            return out
        }
        return nil
    }
}
