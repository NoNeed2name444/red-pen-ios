import Foundation

// How a diagnosis is reached, kept beside the item it was reached for: a case,
// a clue-by-clue case, or a question's explanation.
//
// Borrowed from how Glass Health lays out clinical reasoning: the differential
// in three tiers - the most likely diagnosis, reasonable alternatives, and the
// dangerous ones that must not be missed - each with the findings for and
// against it and the test that settles it. The writer is asked to reason
// through it BEFORE committing to an answer, and it is kept so the student can
// see the route, not only the destination.
//
// Optional on every item that carries it, so sets saved before it existed
// decode unchanged. Foundation only, so the parsing can be tested on Linux.

/// One diagnosis in a differential, with the case's own findings for and
/// against it and the test that would confirm or exclude it.
struct DifferentialEntry: Codable, Hashable {
    var name: String
    var supporting: [String] = []
    var against: [String] = []
    var test: String = ""

    enum CodingKeys: String, CodingKey { case name, supporting, against, test }

    init(name: String, supporting: [String] = [], against: [String] = [], test: String = "") {
        self.name = name
        self.supporting = supporting
        self.against = against
        self.test = test
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        supporting = try c.decodeIfPresent([String].self, forKey: .supporting) ?? []
        against = try c.decodeIfPresent([String].self, forKey: .against) ?? []
        test = try c.decodeIfPresent(String.self, forKey: .test) ?? ""
    }

    var hasDetail: Bool { !supporting.isEmpty || !against.isEmpty || !test.isEmpty }
}

/// A source a check actually read: an item from the evidence lookup
/// (Europe PMC, MedlinePlus, openFDA). Never written by the model - only ever
/// copied from what the lookup returned, so nothing here can be invented.
struct EvidenceRef: Codable, Hashable, Sendable {
    var id: String
    var source: String
    var title: String
    var url: String

    enum CodingKeys: String, CodingKey { case id, source, title, url }

    init(id: String, source: String, title: String, url: String) {
        self.id = id
        self.source = source
        self.title = title
        self.url = url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
    }

    /// "Europe PMC: Groin hernia repair (Hernia, 2023)".
    var label: String {
        let head: String = source.isEmpty ? "" : source + ": "
        return head + (title.isEmpty ? url : title)
    }
}

/// The three tiers.
enum DifferentialTier: String, CaseIterable, Identifiable {
    case mostLikely, expanded, cantMiss
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostLikely: return "Most likely"
        case .expanded: return "Expanded"
        case .cantMiss: return "Can\u{2019}t miss"
        }
    }
}

/// A differential in three tiers, and the evidence it was checked against.
struct DifferentialTiers: Codable, Hashable {
    var mostLikely: [DifferentialEntry] = []
    var expanded: [DifferentialEntry] = []
    var cantMiss: [DifferentialEntry] = []
    /// Evidence items the accuracy check's lookup returned for this item.
    /// Empty unless a cloud check ran; the lecture page is cited separately.
    var evidence: [EvidenceRef] = []

    enum CodingKeys: String, CodingKey { case mostLikely, expanded, cantMiss, evidence }

    init(mostLikely: [DifferentialEntry] = [], expanded: [DifferentialEntry] = [],
         cantMiss: [DifferentialEntry] = [], evidence: [EvidenceRef] = []) {
        self.mostLikely = mostLikely
        self.expanded = expanded
        self.cantMiss = cantMiss
        self.evidence = evidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mostLikely = try c.decodeIfPresent([DifferentialEntry].self, forKey: .mostLikely) ?? []
        expanded = try c.decodeIfPresent([DifferentialEntry].self, forKey: .expanded) ?? []
        cantMiss = try c.decodeIfPresent([DifferentialEntry].self, forKey: .cantMiss) ?? []
        evidence = try c.decodeIfPresent([EvidenceRef].self, forKey: .evidence) ?? []
    }

    func entries(_ tier: DifferentialTier) -> [DifferentialEntry] {
        switch tier {
        case .mostLikely: return mostLikely
        case .expanded: return expanded
        case .cantMiss: return cantMiss
        }
    }

    var isEmpty: Bool { mostLikely.isEmpty && expanded.isEmpty && cantMiss.isEmpty }

    /// The differential as one block of text, for the accuracy checker - the
    /// same wording the server's jobs.js writes (`differentialText`).
    var checkText: String {
        var lines: [String] = []
        for tier in DifferentialTier.allCases {
            let items: [DifferentialEntry] = entries(tier)
            guard !items.isEmpty else { continue }
            let described: [String] = items.map { Self.describe($0) }
            lines.append("- " + tier.title + ": " + described.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ e: DifferentialEntry) -> String {
        var parts: [String] = []
        if !e.supporting.isEmpty { parts.append("for: " + e.supporting.joined(separator: ", ")) }
        if !e.against.isEmpty { parts.append("against: " + e.against.joined(separator: ", ")) }
        if !e.test.isEmpty { parts.append("test: " + e.test) }
        return parts.isEmpty ? e.name : e.name + " (" + parts.joined(separator: "; ") + ")"
    }
}

// MARK: - reading a differential out of a model's reply

extension DifferentialTiers {

    /// From a reply as a whole: a JSON object that is the differential or
    /// holds one under "differential", or else the one-line form. Nil when
    /// there is no differential in it.
    static func parse(reply: String) -> DifferentialTiers? {
        let text: String = LLMTextLite.stripFences(reply)
        // a JSON reply is read as JSON only: a question's own words ("the most
        // likely diagnosis") must not be taken for a tier label
        if let data = LLMTextLite.outerObject(text),
           let object = try? JSONSerialization.jsonObject(with: data) {
            return parse(json: object)
        }
        return parse(line: text)
    }

    /// From decoded JSON: `{"mostLikely":[...],"expanded":[...],"cantMiss":[...]}`,
    /// the same under "differential", or a list of entries each naming its
    /// tier. Keys are read tolerantly: models write "most_likely",
    /// "Most Likely", "cant_miss", "canNotMiss".
    static func parse(json: Any?) -> DifferentialTiers? {
        if let dict = json as? [String: Any] {
            for key in ["differential", "ddx", "differentialDiagnosis", "reasoning"] {
                if let inner = value(dict, key), let found = parse(json: inner) { return found }
            }
            var tiers = DifferentialTiers()
            for (key, raw) in dict {
                guard let tier = tier(named: key) else { continue }
                let found: [DifferentialEntry] = entries(from: raw)
                tiers.append(found, to: tier)
            }
            return tiers.tidied()
        }
        if let list = json as? [Any] {
            var tiers = DifferentialTiers()
            for item in list {
                guard let d = item as? [String: Any] else { continue }
                let label: String = text(d, "tier", "category", "level")
                guard let tier = tier(named: label), let entry = entry(from: d) else { continue }
                tiers.append([entry], to: tier)
            }
            return tiers.tidied()
        }
        return nil
    }

    /// Each item's differential in a reply like `{"questions":[{..., "differential":{...}}]}`,
    /// by position, read on its own so a malformed one costs only itself.
    static func perItem(in data: Data, list key: String) -> [DifferentialTiers?] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = object[key] as? [Any] else { return [] }
        return list.map { item -> DifferentialTiers? in
            guard let d = item as? [String: Any], let raw = d["differential"] else { return nil }
            return parse(json: raw)
        }
    }

    /// The one-line form, as a Cases line's fifth field carries it:
    /// `Most likely: X (for: a, b; against: c; test: d) / Expanded: Y (...); Z (...) / Can't miss: W (...)`
    static func parse(line: String) -> DifferentialTiers? {
        let marks: [(tier: DifferentialTier, start: String.Index, end: String.Index)] = tierMarks(in: line)
        guard !marks.isEmpty else { return nil }
        var tiers = DifferentialTiers()
        for (i, mark) in marks.enumerated() {
            let stop: String.Index = i + 1 < marks.count ? marks[i + 1].start : line.endIndex
            let body: String = String(line[mark.end..<stop])
            var found: [DifferentialEntry] = []
            for piece in splitTop(body, at: [";", ","]) {
                if let entry = entry(fromLine: piece) { found.append(entry) }
            }
            tiers.append(found, to: mark.tier)
        }
        return tiers.tidied()
    }

    // MARK: helpers

    private mutating func append(_ found: [DifferentialEntry], to tier: DifferentialTier) {
        switch tier {
        case .mostLikely: mostLikely += found
        case .expanded: expanded += found
        case .cantMiss: cantMiss += found
        }
    }

    /// Nil when nothing was found; each tier capped, blanks and repeats dropped.
    private func tidied() -> DifferentialTiers? {
        var out = DifferentialTiers(evidence: evidence)
        var seen: Set<String> = []
        for tier in DifferentialTier.allCases {
            var kept: [DifferentialEntry] = []
            for e in entries(tier) {
                let key: String = e.name.lowercased()
                let blank: Bool = key.isEmpty || ["none", "n/a", "nil", "null"].contains(key)
                guard !blank, seen.insert(key).inserted else { continue }
                kept.append(e)
            }
            out.append(Array(kept.prefix(4)), to: tier)
        }
        return out.isEmpty ? nil : out
    }

    /// Which tier a label names, or nil.
    static func tier(named raw: String) -> DifferentialTier? {
        let letters: String = raw.lowercased().filter { $0.isLetter }
        if letters.hasPrefix("mostlikely") || letters == "likely" || letters == "leading" { return .mostLikely }
        if letters.hasPrefix("expanded") || letters.hasPrefix("alternative") || letters == "other" { return .expanded }
        let dangerous: [String] = ["cantmiss", "cannotmiss", "cantbemissed", "mustnotmiss", "dontmiss", "redflag", "dangerous"]
        if dangerous.contains(where: { letters.hasPrefix($0) }) { return .cantMiss }
        return nil
    }

    private static func entries(from raw: Any) -> [DifferentialEntry] {
        if let list = raw as? [Any] {
            return list.compactMap { item -> DifferentialEntry? in
                if let d = item as? [String: Any] { return entry(from: d) }
                if let s = item as? String { return entry(fromLine: s) }
                return nil
            }
        }
        if let d = raw as? [String: Any], let one = entry(from: d) { return [one] }
        if let s = raw as? String {
            return splitTop(s, at: [";"]).compactMap { entry(fromLine: $0) }
        }
        return []
    }

    private static func entry(from d: [String: Any]) -> DifferentialEntry? {
        let name: String = text(d, "name", "diagnosis", "dx", "condition")
        guard !name.isEmpty else { return nil }
        let pro: [String] = list(d, "for", "supporting", "findingsFor", "pro", "support")
        let con: [String] = list(d, "against", "findingsAgainst", "con", "contra")
        let test: String = text(d, "test", "discriminatingTest", "discriminator", "confirm", "investigation")
        return DifferentialEntry(name: name, supporting: pro, against: con, test: test)
    }

    /// "Femoral hernia (for: groin lump; against: above the tubercle; test: ultrasound)"
    private static func entry(fromLine raw: String) -> DifferentialEntry? {
        let piece: String = raw.trimmingCharacters(in: tidySet)
        guard !piece.isEmpty else { return nil }
        guard let open = piece.firstIndex(of: "(") else {
            return DifferentialEntry(name: piece)
        }
        let name: String = String(piece[..<open]).trimmingCharacters(in: tidySet)
        guard !name.isEmpty else { return nil }
        var inside: String = String(piece[piece.index(after: open)...])
        if inside.hasSuffix(")") { inside.removeLast() }
        var entry = DifferentialEntry(name: name)
        for part in splitTop(inside, at: [";"]) {
            let (label, body) = labelled(part)
            let items: [String] = splitTop(body, at: [","]).map { $0.trimmingCharacters(in: tidySet) }.filter { !$0.isEmpty }
            switch label {
            case "for", "supporting", "pro": entry.supporting += items
            case "against", "con": entry.against += items
            case "test", "confirm", "discriminator": entry.test = body.trimmingCharacters(in: tidySet)
            default: break
            }
        }
        return entry
    }

    /// "for: a, b" -> ("for", "a, b").
    private static func labelled(_ part: String) -> (String, String) {
        guard let colon = part.firstIndex(of: ":") else { return ("", part) }
        let label: String = String(part[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
        let body: String = String(part[part.index(after: colon)...])
        return (label, body)
    }

    /// Where each tier's label sits in a one-line differential, outside brackets.
    private static func tierMarks(in line: String) -> [(tier: DifferentialTier, start: String.Index, end: String.Index)] {
        let labels: [(String, DifferentialTier)] = [
            ("most likely", .mostLikely), ("expanded", .expanded),
            ("can't miss", .cantMiss), ("can\u{2019}t miss", .cantMiss),
            ("cannot miss", .cantMiss), ("can not miss", .cantMiss), ("cant miss", .cantMiss),
        ]
        var marks: [(tier: DifferentialTier, start: String.Index, end: String.Index)] = []
        var depth: Int = 0
        var i: String.Index = line.startIndex
        while i < line.endIndex {
            let ch: Character = line[i]
            if ch == "(" { depth += 1 } else if ch == ")" { depth = max(0, depth - 1) }
            if depth == 0 {
                let rest: Substring = line[i...]
                for (label, tier) in labels {
                    guard let found = rest.range(of: label, options: [.caseInsensitive, .anchored]) else { continue }
                    var end: String.Index = found.upperBound
                    while end < line.endIndex, line[end] == " " || line[end] == ":" || line[end] == "=" {
                        end = line.index(after: end)
                    }
                    marks.append((tier, i, end))
                    i = found.upperBound
                    break
                }
            }
            if i < line.endIndex { i = line.index(after: i) }
        }
        return marks
    }

    /// Splits at any of `marks` outside brackets.
    static func splitTop(_ text: String, at marks: Set<Character>) -> [String] {
        var out: [String] = []
        var current: String = ""
        var depth: Int = 0
        for ch in text {
            if ch == "(" { depth += 1 }
            if ch == ")" { depth = max(0, depth - 1) }
            if depth == 0 && marks.contains(ch) {
                out.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        out.append(current)
        let trimmed: [String] = out.map { $0.trimmingCharacters(in: tidySet) }
        return trimmed.filter { !$0.isEmpty }
    }

    private static let tidySet: CharacterSet = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "/.-*\u{2022}"))

    private static func value(_ d: [String: Any], _ key: String) -> Any? {
        if let v = d[key] { return v }
        let wanted: String = key.lowercased()
        for (k, v) in d where k.lowercased() == wanted { return v }
        return nil
    }

    private static func text(_ d: [String: Any], _ keys: String...) -> String {
        for key in keys {
            if let s = value(d, key) as? String {
                let t: String = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
            if let items = value(d, key) as? [Any] {
                let joined: String = items.compactMap { $0 as? String }.joined(separator: "; ")
                if !joined.isEmpty { return joined }
            }
        }
        return ""
    }

    private static func list(_ d: [String: Any], _ keys: String...) -> [String] {
        for key in keys {
            var found: [String] = []
            if let items = value(d, key) as? [Any] {
                found = items.compactMap { $0 as? String }
            } else if let s = value(d, key) as? String {
                found = splitTop(s, at: [";", ","])
            }
            let tidy: [String] = found.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !tidy.isEmpty { return Array(tidy.prefix(5)) }
        }
        return []
    }
}

/// The two bits of reply-tidying the model files need, kept here so this
/// file depends on nothing else.
enum LLMTextLite {
    static func stripFences(_ raw: String) -> String {
        var text: String = raw
        if let end = text.range(of: "</think>", options: .backwards) {
            text = String(text[end.upperBound...])
        }
        text = text.replacingOccurrences(of: "```json", with: "")
        text = text.replacingOccurrences(of: "```", with: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func outerObject(_ raw: String) -> Data? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else { return nil }
        return String(raw[start...end]).data(using: .utf8)
    }
}
