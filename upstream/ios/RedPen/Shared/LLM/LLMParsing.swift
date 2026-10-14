import Foundation

// The parts of the model layer that are pure text in, text out: stripping a
// reasoning model's working, pulling JSON out of a chatty reply, slicing a
// lecture into windows, and choosing which part of it a check is made
// against. Foundation only, so Tests/LLMTests.swift can compile and RUN
// them without a model, a phone or a network.

// MARK: - text helpers shared by every backend

enum LLMText {
    /// Doctor-R1 is a reasoning model: its answer follows a
    /// `<think>...</think>` block that is working, not output.
    static func stripThinking(_ raw: String) -> String {
        var text = raw
        if let end = text.range(of: "</think>", options: .backwards) {
            text = String(text[end.upperBound...])
        } else if text.contains("<think>") {
            // cut off mid-thought: nothing after it is an answer
            text = ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Doctor-R1 is a Qwen3 model: "/no_think" on the last user
    /// turn skips the hidden reasoning. On a phone that reasoning can use the
    /// whole length budget before the answer starts, so on-device calls always
    /// skip it; the prompts already say exactly what to produce.
    static func noThinking(_ turns: [ChatTurn]) -> [ChatTurn] {
        guard let last = turns.lastIndex(where: { $0.role == .user }),
              !turns[last].text.contains("/no_think") else { return turns }
        var out = turns
        out[last].text += "\n/no_think"
        return out
    }

    /// The outermost `{...}` in a reply, for models that wrap JSON in prose or
    /// a code fence even when told not to.
    static func jsonObject(in raw: String) -> Data? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"),
              start < end else { return nil }
        return String(raw[start...end]).data(using: .utf8)
    }

    /// Each object in the `list` array of a JSON reply, read one at a time,
    /// so one malformed item costs only itself rather than the whole reply.
    /// A reply cut off mid-array (the length limit hit) still gives back
    /// every item that was complete.
    static func jsonItems(in raw: String, list key: String) -> [[String: Any]] {
        if let data = jsonObject(in: raw),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let list = object[key] as? [Any] {
            return list.compactMap { $0 as? [String: Any] }
        }
        return completeItems(in: raw, list: key)
    }

    /// The complete `{...}` objects inside a `"list": [` array that may
    /// never close. Braces inside strings are not counted.
    static func completeItems(in raw: String, list key: String) -> [[String: Any]] {
        guard let named = raw.range(of: "\"" + key + "\""),
              let open = raw[named.upperBound...].firstIndex(of: "[") else { return [] }
        var out: [[String: Any]] = []
        var depth = 0
        var inString = false
        var escaped = false
        var start: String.Index? = nil
        var i: String.Index = raw.index(after: open)
        while i < raw.endIndex {
            let c: Character = raw[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                if depth == 0 { start = i }
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth < 0 { break }
                if depth == 0, let from = start {
                    let piece: String = String(raw[from...i])
                    if let data = piece.data(using: .utf8),
                       let item = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                        out.append(item)
                    }
                    start = nil
                }
            } else if c == "]" && depth == 0 {
                break
            }
            i = raw.index(after: i)
        }
        return out
    }

    /// The keyed option however a model wrote it - 2, "2", "C", or the
    /// option's own text. Nil when it names no option.
    static func keyIndex(_ value: Any?, options: [String]) -> Int? {
        var index: Int? = nil
        if let number = value as? Int {
            index = number
        } else if let text = value as? String {
            let t: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let upper: [Unicode.Scalar] = Array(t.uppercased().unicodeScalars)
            if let number = Int(t) {
                index = number
            } else if upper.count == 1, let only = upper.first, (65...90).contains(only.value) {
                index = Int(only.value) - 65
            } else {
                index = options.firstIndex { $0.compare(t, options: .caseInsensitive) == .orderedSame }
            }
        }
        guard let index, options.indices.contains(index) else { return nil }
        return index
    }
}

/// Choosing text by overlap, and cutting it into pieces.
enum TextSlicing {

    /// A source longer than one prompt can hold, as windows that each fit,
    /// cut at a paragraph, line or sentence end where one is near, so every
    /// part of a lecture is read by some batch (audit #90: only the first
    /// 40-45k characters ever were, 8-10k on a phone).
    static func windows(_ text: String, maxChars: Int) -> [String] {
        let limit: Int = max(500, maxChars)
        guard text.count > limit else { return [text] }
        var out: [String] = []
        var rest: Substring = Substring(text)
        while !rest.isEmpty {
            if rest.count <= limit { out.append(String(rest)); break }
            let hard: String.Index = rest.index(rest.startIndex, offsetBy: limit)
            let head: Substring = rest[rest.startIndex..<hard]
            // a paragraph end in the last third of the window, else a line
            // or sentence end in its last fifth, else a hard cut
            var cut: String.Index = hard
            for (mark, share) in [("\n\n", 2), ("\n", 4), (". ", 4)] {
                let floor: String.Index = rest.index(rest.startIndex, offsetBy: limit * share / (share + 1))
                if let r = head.range(of: mark, options: .backwards), r.lowerBound >= floor {
                    cut = r.upperBound
                    break
                }
            }
            out.append(String(rest[rest.startIndex..<cut]).trimmingCharacters(in: .whitespacesAndNewlines))
            rest = rest[cut...]
        }
        return out.filter { !$0.isEmpty }
    }

    /// Up to `limit` of `count` windows, spread evenly from the first to the
    /// last, for a check that cannot afford to read them all: a sample of
    /// the whole rather than its opening.
    static func spread(_ count: Int, upTo limit: Int) -> [Int] {
        guard count > 0, limit > 0 else { return [] }
        guard count > limit else { return Array(0..<count) }
        guard limit > 1 else { return [0] }
        var picked: [Int] = []
        for i in 0..<limit {
            let at = Int((Double(i) * Double(count - 1) / Double(limit - 1)).rounded())
            if picked.last != at { picked.append(at) }
        }
        return picked
    }

    /// The window a batch reads: each batch the next one, round and round.
    static func window(_ windows: [String], round: Int) -> String {
        guard !windows.isEmpty else { return "" }
        return windows[((round % windows.count) + windows.count) % windows.count]
    }

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 })
    }

    /// The paragraphs of a long source that share the most words with `text`.
    static func nearest(_ source: String, to text: String, limit: Int) -> String {
        guard source.count > limit else { return source }
        let wanted = words(text)
        // A paragraph too long to fit is taken line by line instead: a Word
        // file's text is one page with a line per paragraph and no blank
        // lines, so as one paragraph it could never be chosen at all.
        var paragraphs: [String] = []
        for paragraph in source.components(separatedBy: "\n\n") {
            if paragraph.count > limit {
                paragraphs.append(contentsOf: paragraph.components(separatedBy: "\n"))
            } else {
                paragraphs.append(paragraph)
            }
        }
        let ranked = paragraphs.enumerated()
            .map { ($0.offset, words($0.element).intersection(wanted).count) }
            .sorted { $0.1 > $1.1 }
        var chosen: [Int] = []
        var size = 0
        for (index, score) in ranked where score > 0 {
            // the blank line each one is joined with counts too
            let length: Int = paragraphs[index].count + (chosen.isEmpty ? 0 : 2)
            if size + length > limit { continue }
            chosen.append(index)
            size += length
        }
        guard !chosen.isEmpty else { return String(source.prefix(limit)) }
        // back in reading order, so the check reads the source as written
        return chosen.sorted().map { paragraphs[$0] }.joined(separator: "\n\n")
    }

    /// The pages that share the most words with `text`, best first, up to
    /// `limit` characters; nil when no page shares a word with it.
    ///
    /// A page bigger than the room left is cut down to its own nearest
    /// paragraphs rather than ending the search: a Word file is kept as ONE
    /// page, so stopping at the first page that does not fit meant a Word
    /// lecture was never used at all, and the check fell back to "no source".
    static func nearestPages(_ pages: [(heading: String, text: String)], to text: String,
                             limit: Int) -> String? {
        let wanted = words(text)
        let ranked = pages.map { page -> (heading: String, text: String, score: Int) in
            (page.heading, page.text, words(page.text).intersection(wanted).count)
        }.sorted { $0.score > $1.score }
        // less than this left is not worth a page
        let smallest: Int = min(200, max(1, limit / 4))
        var out = ""
        for page in ranked where page.score > 0 {
            let room: Int = limit - out.count - page.heading.count - 2
            guard room >= smallest else { break }
            let body: String = page.text.count <= room ? page.text : nearest(page.text, to: text, limit: room)
            out += page.heading + body + "\n\n"
        }
        return out.isEmpty ? nil : out
    }

    /// Paragraph-aligned slices of roughly equal length.
    static func slice(_ text: String, into count: Int, maxChars: Int) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !paragraphs.isEmpty else { return [] }
        let target = min(maxChars, max(800, text.count / max(1, count)))
        var slices: [String] = []
        var current = ""
        for p in paragraphs {
            if !current.isEmpty && current.count + p.count > target {
                slices.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n\n") + String(p.prefix(maxChars))
        }
        if !current.isEmpty { slices.append(current) }
        let wanted = max(1, count)
        guard slices.count > wanted else { return slices }
        // More pieces than pages: neighbours are merged rather than the tail
        // dropped, so the last chapter of a lecture is never silently lost.
        // Only a source bigger than the whole budget loses anything, and
        // then evenly, not from the end.
        var merged: [String] = []
        for bucket in 0..<wanted {
            let from = bucket * slices.count / wanted
            let to = (bucket + 1) * slices.count / wanted
            merged.append(String(slices[from..<to].joined(separator: "\n\n").prefix(maxChars)))
        }
        return merged
    }
}

// MARK: - what the checker is shown for a question

enum CheckedQuestion {
    /// "A", "B" ... "Z" for any number of options, the same lettering the
    /// deck and the quiz show; past Z, the option's number.
    static func letter(_ index: Int) -> String {
        guard index >= 0, index < 26, let scalar = UnicodeScalar(65 + index) else { return "\(index + 1)" }
        return String(Character(scalar))
    }

    /// A question as the checker reads it. A sixth option is F, not a second
    /// E, and the key names the option that is actually keyed; a key that
    /// points at no option (a hand-written or imported file's -1) is said to
    /// be missing rather than read out of range.
    static func text(stem: String, options: [String], correctIndex: Int, explanation: String) -> String {
        let lines: [String] = options.enumerated().map { letter($0.offset) + ". " + $0.element }
        let key: String = options.indices.contains(correctIndex) ? letter(correctIndex) : "none keyed"
        return stem + "\n" + lines.joined(separator: "\n") + "\nAnswer: " + key + "\nExplanation: " + explanation
    }
}
