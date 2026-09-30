import Foundation

/// The text of an Anki note's fields.
///
/// Anki shows a field as HTML, in its desktop app and on the phone alike, so
/// everything a card says is escaped before it goes in - a cloze sentence as
/// much as a question. A set can arrive from another phone or from a model, and
/// an unescaped `<img src=x onerror=...>` in one would run in the student's
/// Anki; an ordinary "Na < 135" would lose the rest of its sentence to a tag
/// that is not one. Ported from the web app's ankiFieldBold / plainTextForSort.
///
/// Foundation only, so it is tested.
enum AnkiFields {

    /// `**term**` → <b>term</b>, everything else HTML-escaped.
    static func bold(_ s: String) -> String {
        var out = "", rest = Substring(s), on = false
        while let r = rest.range(of: "**") {
            out += esc(String(rest[..<r.lowerBound])) + (on ? "</b>" : "<b>")
            on.toggle(); rest = rest[r.upperBound...]
        }
        out += esc(String(rest))
        return on ? out + "</b>" : out
    }

    /// A cloze sentence as a field: escaped like any other, bold and all.
    /// The {{c1::...}} markers come through untouched - Anki reads those
    /// itself, and they hold no <, > or & for escaping to change.
    static func cloze(_ s: String) -> String { bold(s) }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func plain(_ s: String) -> String { s.replacingOccurrences(of: "**", with: "") }

    /// Which cards a cloze note makes: one per distinct cN, counted from 0.
    static func clozeOrdinals(_ text: String) -> [Int] {
        let re = try? NSRegularExpression(pattern: #"\{\{c(\d+)::"#)
        let ns = text as NSString
        let matches = re?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
        let nums = matches.compactMap { Int(ns.substring(with: $0.range(at: 1))) }
        let ords = Set(nums.map { $0 - 1 }).filter { $0 >= 0 }.sorted()
        return ords.isEmpty ? [0] : ords
    }

    /// A field as Anki reads it for its duplicate check: the HTML gone and
    /// the entities turned back into the characters they stand for. Checksums
    /// taken over the escaped form would never match the ones Anki takes.
    static func stripped(_ field: String) -> String {
        let bare = field.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        guard bare.contains("&") else { return bare }
        var out = bare
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                                    ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: character)
        }
        // last, or an escaped entity would be decoded twice
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }
}
