import Foundation

// "Save to Ideas": a question's explanation, a card's back, a case's answer,
// an OSCE station or a passage of a lecture kept as a note in Ideas - like a
// notebook beside a question bank. The note is titled from the question or
// the card's front, filed in a folder named after the set's subject, and
// remembers where it came from (NoteSource), so its chip can open the
// question again in its set. Saving the same item twice offers to add to the
// note already there rather than making a second one.
//
// Foundation only; tested in Tests/SaveToIdeasTests.swift. The buttons, the
// toast and the selection menu are in SaveToIdeasUI.swift.

/// Where a note saved from studying came from. Stored on the note (optional,
/// so notes written before it, or by hand, have none) and read by its chip.
struct NoteSource: Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case question, card, caseCard, osce, lecture

        /// How the chip names it: "Question", "Card"...
        var label: String {
            switch self {
            case .question: return "Question"
            case .card: return "Card"
            case .caseCard: return "Case"
            case .osce: return "OSCE station"
            case .lecture: return "Lecture"
            }
        }

        /// The same word inside a sentence.
        var noun: String {
            switch self {
            case .osce: return "OSCE station"
            default: return label.lowercased()
            }
        }

        var symbol: String {
            switch self {
            case .question: return "list.bullet.rectangle"
            case .card: return "rectangle.on.rectangle"
            case .caseCard: return "stethoscope"
            case .osce: return "list.clipboard"
            case .lecture: return "doc.richtext"
            }
        }
    }

    var kind: Kind
    /// The set it was saved from.
    var setID: UUID
    /// The question, card, case card, station or lecture; nil when only the
    /// set is known.
    var itemID: UUID? = nil
    /// The lecture page, from 1; nil for everything but a lecture.
    var page: Int? = nil
    /// The set's name when it was saved, for the chip: the set may be renamed
    /// or deleted later, and the chip should still say something.
    var setName: String = ""

    init(kind: Kind, setID: UUID, itemID: UUID? = nil, page: Int? = nil, setName: String = "") {
        self.kind = kind
        self.setID = setID
        self.itemID = itemID
        self.page = page
        self.setName = setName
    }

    private enum Keys: String, CodingKey { case kind, setID, itemID, page, setName }

    /// The kind and the set are needed; the rest may be missing. A kind this
    /// version does not know throws, and the note reads it as no source
    /// rather than losing the note.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        setID = try c.decode(UUID.self, forKey: .setID)
        itemID = try c.decodeIfPresent(UUID.self, forKey: .itemID)
        page = try c.decodeIfPresent(Int.self, forKey: .page)
        setName = try c.decodeIfPresent(String.self, forKey: .setName) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(setID, forKey: .setID)
        try c.encodeIfPresent(itemID, forKey: .itemID)
        try c.encodeIfPresent(page, forKey: .page)
        if !setName.isEmpty { try c.encode(setName, forKey: .setName) }
    }

    /// One note per item: a question's id is the same in every set it has
    /// been copied into (a Mistakes set, a quiz put together on the spot), so
    /// the item decides, not the set. A lecture is one note however many of
    /// its pages were saved into it.
    var dedupeKey: String {
        let id: UUID = itemID ?? setID
        return kind.rawValue + ":" + id.uuidString.lowercased()
    }

    /// "Question · Cardiology"
    var chipLabel: String {
        let name: String = setName.trimmingCharacters(in: .whitespacesAndNewlines)
        var label: String = kind.label
        if let page { label += " p. \(page)" }
        return name.isEmpty ? label : label + " \u{00B7} " + name
    }

    // MARK: the link form

    /// The schemes AppLink answers to; `stethoscore` is the one people see.
    static let scheme = "stethoscore"
    static let host = "item"

    /// `stethoscore://item/question/<set>/<item>?page=3&set=Cardiology` -
    /// what AppLink routes, so a Shortcut or a link can open the same place
    /// the chip does. An item-less source writes "-" for the item.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        let item: String = itemID?.uuidString ?? "-"
        components.path = "/" + kind.rawValue + "/" + setID.uuidString + "/" + item
        var query: [URLQueryItem] = []
        if let page { query.append(URLQueryItem(name: "page", value: String(page))) }
        if !setName.isEmpty { query.append(URLQueryItem(name: "set", value: setName)) }
        components.queryItems = query.isEmpty ? nil : query
        return components.url ?? URL(string: "stethoscore://item")!
    }

    /// The source a link names, or nil when it is not one (any scheme; the
    /// caller has already decided the link is the app's).
    init?(url: URL) {
        guard (url.host ?? "").lowercased() == Self.host else { return nil }
        let parts: [String] = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, let kind = Kind(rawValue: parts[0]),
              let set = UUID(uuidString: parts[1]) else { return nil }
        let item: UUID? = parts.count >= 3 ? UUID(uuidString: parts[2]) : nil
        let items: [URLQueryItem] = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let pageText: String? = items.first(where: { $0.name == "page" })?.value
        let page: Int? = pageText.flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
        let name: String = items.first(where: { $0.name == "set" })?.value ?? ""
        self.init(kind: kind, setID: set, itemID: item, page: page, setName: name)
    }
}

/// Something about to be saved: the note's title, what goes in its body, and
/// where it came from.
struct IdeaClip: Equatable, Sendable {
    var title: String
    /// Markdown, as the note body is.
    var text: String
    var source: NoteSource
    /// The set's subject, which names the folder.
    var subject: String
    /// A passage chosen by selecting it, rather than the whole explanation.
    var isExcerpt: Bool = false
}

enum SaveToIdeas {
    /// A title longer than this is cut at a word and given an ellipsis.
    static let titleLimit = 80
    /// A subject-less set files its notes here, as it is shelved elsewhere.
    static let generalFolder = "General"

    // MARK: titles

    /// A note title from a question stem, a card's front or a case: the
    /// first sentence, with card markup (`**bold**`, `{{c1::cloze}}`) taken
    /// out, on one line, cut at a word if it is long. `fallback` when there
    /// are no words at all.
    static func title(from text: String, fallback: String = "Saved idea") -> String {
        let plain: String = oneLine(stripMarkup(text))
        guard !plain.isEmpty else { return fallback }
        let sentence: String = firstSentence(plain)
        // `[[` and `]]` would read as a link to another note
        let safe: String = sentence
            .replacingOccurrences(of: "[[", with: "[")
            .replacingOccurrences(of: "]]", with: "]")
        return clipped(safe, to: titleLimit)
    }

    /// Everything up to and including the first full stop, question mark or
    /// exclamation mark that ends a sentence - not the one in "e.g." or in a
    /// number like 7.4. The whole text when there is none.
    static func firstSentence(_ text: String) -> String {
        let chars: [Character] = Array(text)
        var i: Int = 0
        while i < chars.count {
            let c: Character = chars[i]
            if c == "?" || c == "!" || c == "." {
                let atEnd: Bool = i + 1 >= chars.count
                let spaced: Bool = !atEnd && chars[i + 1] == " "
                if atEnd { return text }
                if spaced && !(c == "." && isAbbreviation(chars, before: i)) {
                    return String(chars[0...i])
                }
            }
            i += 1
        }
        return text
    }

    /// Whether the full stop at `index` ends a short abbreviation ("e.g.",
    /// "i.e.", "Dr.", "vs.") rather than a sentence. A lone capital is a
    /// sentence's end ("hepatitis B.", "vitamin K."), not an initial: stems
    /// name those far more often than people.
    private static func isAbbreviation(_ chars: [Character], before index: Int) -> Bool {
        var start: Int = index
        while start > 0 && chars[start - 1] != " " { start -= 1 }
        let raw: String = String(chars[start..<index])
        let word: String = raw.lowercased()
        let known: Set<String> = ["e.g", "i.e", "dr", "vs", "approx", "etc", "mr", "mrs", "st", "cf"]
        if known.contains(word) { return true }
        return raw.count == 1 && raw.first?.isLowercase == true
    }

    /// Cut at the last word that fits, with an ellipsis.
    static func clipped(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head: String = String(text.prefix(limit))
        let cut: String
        if let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) > limit / 2 {
            cut = String(head[..<space])
        } else {
            cut = head
        }
        let trimmed: String = cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
        return trimmed + "\u{2026}"
    }

    /// `**term**` as term, `{{c1::term::hint}}` as term.
    static func stripMarkup(_ text: String) -> String {
        var out: String = ""
        var rest: Substring = Substring(text)
        while let open = rest.range(of: "{{"), let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
            out += rest[rest.startIndex..<open.lowerBound]
            let inner: String = String(rest[open.upperBound..<close.lowerBound])
            let pieces: [String] = inner.components(separatedBy: "::")
            // c1::term::hint - the term; a bare {{term}} is kept whole
            out += pieces.count >= 2 ? pieces[1] : inner
            rest = rest[close.upperBound...]
        }
        out += rest
        return out.replacingOccurrences(of: "**", with: "")
    }

    /// White space of every kind folded to single spaces.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    // MARK: folders

    /// The folder a subject's notes go in: the subject as written, or
    /// General for a set with none.
    static func folderName(subject: String) -> String {
        let trimmed: String = oneLine(subject)
        return trimmed.isEmpty ? generalFolder : trimmed
    }

    /// A folder, as far as choosing one needs.
    struct FolderRef: Equatable {
        var id: UUID
        var name: String
        var parentId: UUID?
    }

    /// The folder already there for this name, ignoring case, accents and
    /// spacing: one at the top level first (it is what colours a cluster in
    /// the map), then one the student has moved inside another. Nil: make it.
    static func folder(named name: String, in folders: [FolderRef]) -> UUID? {
        let wanted: String = folded(name)
        guard !wanted.isEmpty else { return nil }
        let same: [FolderRef] = folders.filter { folded($0.name) == wanted }
        if let top = same.first(where: { $0.parentId == nil }) { return top.id }
        return same.first?.id
    }

    static func folded(_ text: String) -> String {
        let plain: String = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return oneLine(plain)
    }

    // MARK: bodies

    /// The body of a new note: the text - a passage as a quote, so it reads
    /// as something kept - then a line saying where it came from. The line
    /// is a link to the item too, so a note read as Markdown can go back to
    /// it wherever the note is opened, not only where the chip is shown. It
    /// goes last so the note's first line (the Ideas list's preview) is the
    /// idea itself rather than a link.
    static func body(for clip: IdeaClip) -> String {
        entry(for: clip) + "\n\n" + fromLine(clip.source)
    }

    /// "_From [a question in Cardiology](stethoscore://item/...)_"
    static func fromLine(_ source: NoteSource) -> String {
        "_From " + fromLink(source) + "_"
    }

    /// Whether a paragraph is the line `body` ends a note with.
    static func isFromLine(_ paragraph: String) -> Bool {
        let line: String = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        let linked: Bool = line.contains("](" + NoteSource.scheme + "://" + NoteSource.host + "/")
        return line.hasPrefix("_From [") && line.hasSuffix(")_") && linked
    }

    /// "[a question in Cardiology](stethoscore://item/question/...)": the
    /// link without the set's name, which the words already say.
    static func fromLink(_ source: NoteSource) -> String {
        var bare: NoteSource = source
        bare.setName = ""
        return "[" + fromPhrase(source) + "](" + bare.url.absoluteString + ")"
    }

    /// What one save adds: the text, or the passage quoted with its page.
    static func entry(for clip: IdeaClip) -> String {
        let text: String = clip.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clip.isExcerpt else { return text }
        let lines: [String] = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var quoted: String = lines.map { "> " + $0 }.joined(separator: "\n")
        if let page = clip.source.page { quoted += "\n\n\u{2014} p. \(page)" }
        return quoted
    }

    /// "a question in Cardiology", "page 4 of Lupus lecture".
    static func fromPhrase(_ source: NoteSource) -> String {
        let name: String = source.setName.trimmingCharacters(in: .whitespacesAndNewlines)
        let article: String = source.kind == .osce ? "an " : "a "
        let what: String = article + source.kind.noun
        return name.isEmpty ? what : what + " in " + name
    }

    /// The note's body with this save added at the end - above the "From"
    /// line when the note still ends with it - or nil when the note already
    /// holds it (compared on its words, so a re-wrapped copy still counts)
    /// and there is nothing to add.
    static func appending(_ clip: IdeaClip, to body: String) -> String? {
        let adding: String = entry(for: clip)
        let plainAdd: String = folded(stripQuotes(adding))
        guard !plainAdd.isEmpty else { return nil }
        if folded(stripQuotes(body)).contains(plainAdd) { return nil }
        let kept: String = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kept.isEmpty else { return adding }
        var paragraphs: [String] = kept.components(separatedBy: "\n\n")
        guard let last = paragraphs.last, paragraphs.count > 1, isFromLine(last) else {
            return kept + "\n\n" + adding
        }
        paragraphs.insert(adding, at: paragraphs.count - 1)
        return paragraphs.joined(separator: "\n\n")
    }

    /// Quote marks and the page line, so a passage compares by its words.
    private static func stripQuotes(_ text: String) -> String {
        let lines: [String] = text.components(separatedBy: .newlines).map { line in
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\u{2014} p. ") { return "" }
            return trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : trimmed
        }
        return lines.joined(separator: " ")
    }

    // MARK: what each screen saves

    /// A question: titled from its stem; the answer, then the explanation.
    static func question(stem: String, answer: String?, explanation: String,
                         source: NoteSource, subject: String) -> IdeaClip {
        var parts: [String] = []
        if let answer, !answer.isEmpty { parts.append("**Answer:** " + oneLine(answer)) }
        let why: String = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !why.isEmpty { parts.append(why) }
        let title: String = Self.title(from: stem, fallback: "Saved question")
        return IdeaClip(title: title, text: parts.joined(separator: "\n\n"), source: source, subject: subject)
    }

    /// A card: titled from its front (a cloze card from its sentence, blanks
    /// filled); the answer bullets, then the why.
    static func card(front: String, cloze: String, bullets: [String], why: String,
                     source: NoteSource, subject: String) -> IdeaClip {
        let asked: String = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading: String = asked.isEmpty ? cloze : asked
        var parts: [String] = []
        let points: [String] = bullets.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !points.isEmpty { parts.append(points.map { "- " + $0 }.joined(separator: "\n")) }
        if asked.isEmpty && !cloze.isEmpty { parts.append(stripMarkup(cloze)) }
        let reason: String = why.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reason.isEmpty { parts.append(reason) }
        let title: String = Self.title(from: heading, fallback: "Saved card")
        return IdeaClip(title: title, text: parts.joined(separator: "\n\n"), source: source, subject: subject)
    }

    /// A case card: titled from its topic, or its stem; the answer points.
    static func caseCard(topic: String, stem: String, answer: [String],
                         source: NoteSource, subject: String) -> IdeaClip {
        let named: String = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String = Self.title(from: named.isEmpty ? stem : named, fallback: "Saved case")
        let points: [String] = answer.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var parts: [String] = []
        if !named.isEmpty { parts.append(oneLine(stem)) }
        if !points.isEmpty { parts.append(points.map { "- " + $0 }.joined(separator: "\n")) }
        return IdeaClip(title: title, text: parts.joined(separator: "\n\n"), source: source, subject: subject)
    }

    /// An OSCE station: its title; the steps in order, the ones started over
    /// at marked.
    static func osce(title: String, steps: [String], weak: Set<Int>,
                     source: NoteSource, subject: String) -> IdeaClip {
        var lines: [String] = []
        for (index, step) in steps.enumerated() {
            let mark: String = weak.contains(index) ? " _(started over here)_" : ""
            lines.append("\(index + 1). " + oneLine(step) + mark)
        }
        let name: String = Self.title(from: title, fallback: "Saved station")
        return IdeaClip(title: name, text: lines.joined(separator: "\n"), source: source, subject: subject)
    }

    /// A passage of a lecture: the note is the lecture's, and each passage
    /// goes in as a quote with its page.
    static func passage(_ text: String, lecture: String,
                        source: NoteSource, subject: String) -> IdeaClip {
        let title: String = Self.title(from: lecture, fallback: "Lecture notes")
        return IdeaClip(title: title, text: text, source: source, subject: subject, isExcerpt: true)
    }

    /// A pretend patient's debrief for a case: the diagnosis and the
    /// checklist points missed, added under the case's own note (the same
    /// title and source as saving the case card itself).
    static func caseDebrief(diagnosis: String, missed: [String], covered: Int, total: Int,
                            of clip: IdeaClip) -> IdeaClip {
        var lines: [String] = ["**Pretend patient:** \(covered) of \(total) checklist points covered"]
        let named: String = oneLine(diagnosis)
        if !named.isEmpty { lines.append("**Diagnosis:** " + named) }
        let gaps: [String] = missed.map { oneLine($0) }.filter { !$0.isEmpty }
        if !gaps.isEmpty {
            lines.append("Missed:\n" + gaps.map { "- " + $0 }.joined(separator: "\n"))
        }
        var out: IdeaClip = clip
        out.text = lines.joined(separator: "\n\n")
        out.isExcerpt = false
        return out
    }

    /// A passage chosen from an explanation or a card: the same note as the
    /// whole (titled the same), with just the passage in it.
    static func excerpt(_ text: String, of clip: IdeaClip) -> IdeaClip {
        var out: IdeaClip = clip
        out.text = text
        out.isExcerpt = true
        return out
    }
}
