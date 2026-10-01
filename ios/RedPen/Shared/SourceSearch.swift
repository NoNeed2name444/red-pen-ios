import Foundation

/// Finding a word in a lecture, and finding the page a card came off.
///
/// Both are pure functions over text, which is why they are here rather than
/// inside the preview screen: the awkward cases - a citation written by an
/// earlier version of the app, a search that matches a hundred times, a page
/// whose match sits in the very first characters - are all worth testing, and
/// none of them need a screen to happen.
enum SourceSearch {

    /// One place a search term appears, with enough text around it to read.
    struct Hit: Identifiable, Equatable {
        var page: Int
        /// Where the match starts within `snippet`, so the view can mark it
        /// without searching the text a second time and finding a different
        /// occurrence.
        var range: Range<Int>
        var snippet: String
        var id: String { "\(page)-\(range.lowerBound)-\(snippet.count)" }
    }

    /// Every appearance of `term`, in reading order.
    ///
    /// Case and accent insensitive, because nobody hunting for "oedema" wants
    /// to be told there is no such word when the slide says "Oedema" - and a
    /// student typing on a phone will not reproduce the source's diacritics.
    static func hits(for term: String, in pages: [SourceDoc.Page],
                     context: Int = 40, limit: Int = 200) -> [Hit] {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return [] }

        var found: [Hit] = []
        for page in pages {
            let text = page.text
            var searchFrom = text.startIndex
            while found.count < limit,
                  let match = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive],
                                         range: searchFrom..<text.endIndex) {
                let (snippet, offset) = window(text, around: match, context: context)
                let start = offset
                let length = text.distance(from: match.lowerBound, to: match.upperBound)
                found.append(Hit(page: page.number,
                                 range: start..<(start + length),
                                 snippet: snippet))
                // Past the END of this match, never one character on from its
                // start: a search for "aa" in "aaaa" would otherwise report
                // overlapping matches for ever.
                searchFrom = match.upperBound
                if match.upperBound == text.endIndex { break }
            }
            if found.count >= limit { break }
        }
        return found
    }

    /// A readable amount of text either side of a match, and where the match
    /// sits inside it.
    ///
    /// The offset is returned rather than recomputed because the snippet may
    /// contain the term more than once - "the oedema was pitting oedema" - and
    /// searching the snippet again would mark the wrong one.
    private static func window(_ text: String, around match: Range<String.Index>,
                               context: Int) -> (String, Int) {
        let before = text.index(match.lowerBound, offsetBy: -context,
                                limitedBy: text.startIndex) ?? text.startIndex
        let after = text.index(match.upperBound, offsetBy: context,
                               limitedBy: text.endIndex) ?? text.endIndex
        var snippet = String(text[before..<after]).replacingOccurrences(of: "\n", with: " ")
        var offset = text.distance(from: before, to: match.lowerBound)

        // Leading and trailing ellipses are part of the snippet, so anything
        // trimmed from the front has to move the offset with it.
        let trimmedFront = snippet.count - snippet.drop(while: { $0 == " " }).count
        snippet = String(snippet.drop(while: { $0 == " " }))
        offset -= trimmedFront
        while snippet.hasSuffix(" ") { snippet.removeLast() }

        if before > text.startIndex {
            snippet = "…" + snippet
            offset += 1
        }
        if after < text.endIndex { snippet += "…" }
        return (snippet, max(0, offset))
    }

    /// How many pages a term appears on, for a result header that says
    /// something useful rather than just a number.
    static func pagesMatched(_ hits: [Hit]) -> Int {
        Set(hits.map(\.page)).count
    }
}

/// A card's citation, read back apart.
///
/// The app writes these as "Immunology, p. 12" (see Provenance.label) and then
/// shows them as text. Reading one back is what turns it into somewhere to go:
/// tapping the citation on a card can open the lecture at that page instead of
/// leaving the student to find it.
///
/// Deliberately forgiving. Citations written by earlier versions, or typed by
/// hand, or carrying a page range, all still name a page - and a citation that
/// cannot be parsed is not an error, just one that is shown as plain text.
enum Citation {

    struct Reference: Equatable {
        var name: String
        var page: Int
    }

    /// The document a citation is pointing at, and the page in it.
    ///
    /// Matching is by name, except when there is only one source - in which
    /// case the citation can only mean that one, whatever an earlier version of
    /// the app wrote in it or however the file has since been renamed. That
    /// case is also the common one: most sets are made from a single lecture.
    static func resolve(_ label: String?, in sources: [SourceDoc]) -> (source: SourceDoc, page: Int)? {
        guard let reference = read(label), !sources.isEmpty else { return nil }

        let named = sources.first {
            $0.name.compare(reference.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard let source = named ?? (sources.count == 1 ? sources[0] : nil) else { return nil }
        // A citation to a page the document does not have is not somewhere to
        // go. It happens when a source is replaced by a shorter one, and
        // silently opening the last page instead would be a quiet lie.
        guard source.page(reference.page) != nil else { return nil }
        return (source, reference.page)
    }

    static func read(_ label: String?) -> Reference? {
        guard let label, !label.isEmpty else { return nil }

        // The page marker, in the forms the app has used and the ones people
        // type: "p. 12", "p12", "page 12", "pp. 12-14" - the first number of a
        // range being the page to open.
        let pattern = #"(?:^|[,\s(])p{1,2}\.?\s*(\d+)|(?:^|[,\s(])pages?\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label))
        else { return nil }

        var page: Int?
        for group in 1...2 {
            if let range = Range(match.range(at: group), in: label) {
                page = Int(label[range])
                break
            }
        }
        guard let page, page > 0 else { return nil }

        // Whatever came before the page marker is the document's name, minus
        // the comma that joined them.
        let upTo = Range(match.range, in: label)!.lowerBound
        let name = String(label[label.startIndex..<upTo])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,(-–—"))
        return Reference(name: name, page: page)
    }
}
