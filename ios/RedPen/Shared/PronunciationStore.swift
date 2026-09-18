// Red Pen · what the phone learns about this lecturer, on the phone
//
// The recogniser is never retrained. Its hearing is already good: given a whole
// window it writes a faithful phonetic spelling of what was said, in Arabic
// letters. What it cannot know is how those sounds are SPELLED in English, and
// that is the only thing learned here.
//
// A mapping is applied as an exact lookup, so it cannot make the mistakes the
// fuzzy matcher makes - `risk` and `rosacea` share a consonant skeleton and the
// matcher picked the disease; a learned entry picks neither, it knows.
import Foundation

public enum Evidence: String, Codable, CaseIterable, Sendable {
    case slide          // the spelling was on a slide of this lecture
    case correction     // the student wrote it
    case repetition     // the same mapping recurred within a lecture

    /// How many independent sightings before the entry may rewrite a
    /// transcript. A slide or a correction is already a person's own spelling,
    /// so one is enough; repetition is the recogniser agreeing with itself,
    /// which is weaker and has to happen more than once.
    var needed: Int {
        switch self {
        case .slide, .correction: return 1
        case .repetition: return 3
        }
    }
}

public struct Pronunciation: Codable, Equatable, Sendable {
    public var key: String           // the sound
    public var spelling: String      // how it is written in English
    public var heardAs: String       // one Arabic spelling, kept for the audit
    public var counts: [String: Int] // evidence kind -> sightings

    public var isTrusted: Bool {
        Evidence.allCases.contains { counts[$0.rawValue, default: 0] >= $0.needed }
    }
    public var strongest: Evidence? {
        Evidence.allCases.first { counts[$0.rawValue, default: 0] >= $0.needed }
    }
}

public struct PronunciationStore: Codable, Sendable {
    public private(set) var entries: [String: Pronunciation] = [:]
    /// sound-with-the-space-removed -> the key it was stored under
    private var joined: [String: String] = [:]

    public init() {}

    private mutating func index(_ key: String) {
        joined[SoundKey.collapsed(key)] = key
    }

    private func entry(for key: String) -> Pronunciation? {
        if let hit = entries[key] { return hit }
        if let primary = joined[SoundKey.collapsed(key)] { return entries[primary] }
        return nil
    }

    /// A conflicting spelling for the same sound never silently wins: the
    /// better-evidenced one is kept, and a tie keeps what was already there,
    /// so a new guess cannot displace a slide or a correction.
    @discardableResult
    public mutating func add(sound key: String, spelling: String, heardAs: String,
                             evidence: Evidence) -> Bool {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty,
              !spelling.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if var existing = entry(for: key) {
            if existing.spelling.caseInsensitiveCompare(spelling) == .orderedSame {
                existing.counts[evidence.rawValue, default: 0] += 1
                entries[existing.key] = existing
                index(existing.key)
                return true
            }
            let incoming = Pronunciation(key: key, spelling: spelling, heardAs: heardAs,
                                         counts: [evidence.rawValue: 1])
            guard incoming.isTrusted, !existing.isTrusted else { return false }
            entries.removeValue(forKey: existing.key)
            entries[key] = incoming
            index(key)
            return true
        }
        entries[key] = Pronunciation(key: key, spelling: spelling, heardAs: heardAs,
                                     counts: [evidence.rawValue: 1])
        index(key)
        return true
    }

    public func spelling(for span: [String]) -> String? {
        guard let hit = entry(for: SoundKey.of(span: span)), hit.isTrusted else { return nil }
        return hit.spelling
    }

    /// Replace every span the store knows. Longest span first, so a two-word
    /// term is never broken by the one-word entry that is its first half.
    public func apply(to text: String, maxSpan: Int = 3) -> (text: String, hits: [(String, String)]) {
        let tokens = text.split(separator: " ").map(String.init)
        var out: [String] = []
        var hits: [(String, String)] = []
        var i = 0
        while i < tokens.count {
            var matched = false
            var n = min(maxSpan, tokens.count - i)
            while n >= 1 {
                let span = Array(tokens[i..<(i + n)])
                if span.contains(where: SoundKey.hasArabic), let english = spelling(for: span) {
                    let head = tokens[i]
                    let article = SoundKey.stripArticle(head) != head && head.count > 3
                    out.append(article ? "الـ " + english : english)
                    hits.append((span.joined(separator: " "), english))
                    i += n
                    matched = true
                    break
                }
                n -= 1
            }
            if !matched {
                out.append(tokens[i])
                i += 1
            }
        }
        return (out.joined(separator: " "), hits)
    }

    // MARK: file format - the same tab-separated table the pipeline uses, so
    // what the phone learns and what a committee run learns are one thing.

    public func tsv() -> String {
        entries.values
            .sorted { $0.spelling < $1.spelling }
            .map { e in
                let ev = Evidence.allCases
                    .filter { e.counts[$0.rawValue, default: 0] > 0 }
                    .map { "\($0.rawValue):\(e.counts[$0.rawValue, default: 0])" }
                    .joined(separator: ",")
                return "\(e.heardAs)\t\(e.spelling)\t\(ev)"
            }
            .joined(separator: "\n")
    }

    public static func fromTSV(_ text: String) -> PronunciationStore {
        var store = PronunciationStore()
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.prefix { $0 != "#" }
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { continue }
            let heard = parts[0].trimmingCharacters(in: .whitespaces)
            let spelling = parts[1].trimmingCharacters(in: .whitespaces)
            guard !heard.isEmpty, !spelling.isEmpty else { continue }
            var counts: [String: Int] = [:]
            if parts.count >= 3 {
                for token in parts[2].split(separator: ",") {
                    let kv = token.split(separator: ":")
                    if kv.count == 2, let n = Int(kv[1]) { counts[String(kv[0])] = n }
                    else if let n = Int(token) { counts[Evidence.repetition.rawValue] = n }
                }
            }
            if counts.isEmpty { counts[Evidence.correction.rawValue] = 1 }
            let key = SoundKey.of(span: heard.split(separator: " ").map(String.init))
            guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            store.entries[key] = Pronunciation(key: key, spelling: spelling,
                                               heardAs: heard, counts: counts)
            store.index(key)
        }
        return store
    }
}
