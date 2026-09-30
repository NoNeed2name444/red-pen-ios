import Foundation

// Study Lens: finding exam questions in what the camera reads.
//
// The recogniser (VisionKit's live scanner, or Vision on a still photo) hands
// over pieces of text and where each sits. Here they are put back into
// reading order - column by column on a two-column page, line by line, wrapped
// lines joined - then cut into questions at their numbers and option letters,
// and each question is given a type: multiple choice, single best answer,
// true/false, fill in the blank, calculation, clinical case, OSCE instruction,
// image labelling, or short answer.
//
// Foundation only, so every layout it promises to handle is run on Linux
// (Tests/LensTests.swift). Boxes are normalised 0...1 with the origin at the
// TOP left, the way a screen is drawn; the camera side flips Vision's boxes
// before they arrive.

/// One piece of recognised text and where it sits.
struct LensTextBlock: Hashable {
    var text: String
    var box: CGRect

    init(_ text: String, _ box: CGRect) {
        self.text = text
        self.box = box
    }

    init(_ text: String, x: Double, y: Double, w: Double, h: Double) {
        self.text = text
        self.box = CGRect(x: x, y: y, width: w, height: h)
    }
}

/// What kind of question a detection is, which decides its chip, its prompt
/// and the popup it opens.
enum LensQuestionType: String, Codable, CaseIterable, Identifiable, Hashable {
    case mcq, bestAnswer, trueFalse, cloze, shortAnswer, calculation, clinicalCase, osce, imageLabel

    var id: String { rawValue }

    /// The word on the collapsed chip: "Q · MCQ".
    var chipLabel: String {
        switch self {
        case .mcq: return "MCQ"
        case .bestAnswer: return "SBA"
        case .trueFalse: return "T/F"
        case .cloze: return "Blank"
        case .shortAnswer: return "Short"
        case .calculation: return "Calc"
        case .clinicalCase: return "Case"
        case .osce: return "OSCE"
        case .imageLabel: return "Image"
        }
    }

    /// What VoiceOver says before the question's first words.
    var spokenName: String {
        switch self {
        case .mcq: return "Multiple choice question"
        case .bestAnswer: return "Single best answer question"
        case .trueFalse: return "True or false question"
        case .cloze: return "Fill in the blank"
        case .shortAnswer: return "Short answer question"
        case .calculation: return "Calculation"
        case .clinicalCase: return "Clinical case"
        case .osce: return "OSCE station"
        case .imageLabel: return "Image labelling question"
        }
    }

    var title: String {
        switch self {
        case .mcq: return "Multiple choice"
        case .bestAnswer: return "Single best answer"
        case .trueFalse: return "True or false"
        case .cloze: return "Fill in the blank"
        case .shortAnswer: return "Short answer"
        case .calculation: return "Calculation"
        case .clinicalCase: return "Clinical case"
        case .osce: return "OSCE station"
        case .imageLabel: return "Image labelling"
        }
    }

    var symbol: String {
        switch self {
        case .mcq, .bestAnswer: return "checklist.checked"
        case .trueFalse: return "checkmark.circle.badge.xmark"
        case .cloze: return "text.insert"
        case .shortAnswer: return "text.bubble"
        case .calculation: return "function"
        case .clinicalCase: return "stethoscope"
        case .osce: return "list.clipboard"
        case .imageLabel: return "photo.badge.checkmark"
        }
    }

    /// Answered by choosing one of printed options.
    var hasOptions: Bool { self == .mcq || self == .bestAnswer }
}

/// One printed option: its marker as printed ("B", "3") and its words.
struct LensOption: Hashable, Codable {
    var marker: String
    var text: String
}

/// One question found on the page.
struct DetectedQuestion: Hashable, Identifiable {
    var type: LensQuestionType
    /// The printed question number, when there was one.
    var number: String?
    var stem: String
    var options: [LensOption]
    /// Where the whole question sits, normalised, origin top left.
    var box: CGRect
    /// Stable across frames for the same words (LensHash.key).
    var key: String

    var id: String { key }

    /// The question as it is sent for answering and kept: the stem, then each
    /// option lettered A, B, C in order.
    var fullText: String {
        guard !options.isEmpty else { return stem }
        var lines: [String] = [stem]
        for (i, option) in options.enumerated() {
            lines.append(LensHash.letter(i) + ". " + option.text)
        }
        return lines.joined(separator: "\n")
    }

    /// The first few words, for a chip's spoken label and a list row.
    var preview: String { LensHash.firstWords(stem, count: 9) }
}

// MARK: - Detection

enum QuestionDetector {

    /// A reading line: the text of one row of one column.
    struct Line: Hashable {
        var text: String
        var box: CGRect
    }

    /// Every question in what was read, in reading order.
    static func detect(_ blocks: [LensTextBlock]) -> [DetectedQuestion] {
        let cleaned: [LensTextBlock] = blocks.compactMap(clean)
        guard !cleaned.isEmpty else { return [] }
        var lines: [Line] = []
        var breaks: Set<Int> = []
        for group in columns(cleaned) {
            if !lines.isEmpty { breaks.insert(lines.count) }
            lines.append(contentsOf: rows(group))
        }
        let expanded: (lines: [Line], breaks: Set<Int>) = splitInline(lines, breaks: breaks)
        return group(expanded.lines, columnBreaks: expanded.breaks)
    }

    // MARK: cleaning

    /// A block with tidy text, or nil for noise: page numbers, stray marks,
    /// copyright lines.
    static func clean(_ block: LensTextBlock) -> LensTextBlock? {
        var text: String = normalise(block.text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, block.box.width > 0, block.box.height > 0 else { return nil }
        let letters: Int = text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        guard letters >= 1 else { return nil }
        let lower: String = text.lowercased()
        if lower.range(of: #"^page \d+( of \d+)?$"#, options: .regularExpression) != nil { return nil }
        if lower.range(of: #"^\d{1,3}$"#, options: .regularExpression) != nil { return nil }
        if lower.hasPrefix("©") || lower.hasPrefix("(c) 20") { return nil }
        return LensTextBlock(text, block.box)
    }

    /// Curly quotes straight, odd dashes plain, bullets gone, runs of spaces
    /// one - so the patterns below see one spelling of everything.
    static func normalise(_ raw: String) -> String {
        var t: String = raw
        let swaps: [(String, String)] = [
            ("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\""),
            ("\u{2013}", "-"), ("\u{2014}", " - "), ("\u{2022}", " "), ("\u{00A0}", " "),
            ("\t", " "), ("\n", " "),
        ]
        for (from, to) in swaps { t = t.replacingOccurrences(of: from, with: to) }
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t
    }

    // MARK: columns

    /// The blocks in reading groups: one group for a single-column page; for
    /// two columns, anything full-width above them, the left column, the right
    /// column, then anything full-width below.
    static func columns(_ blocks: [LensTextBlock], depth: Int = 0) -> [[LensTextBlock]] {
        guard depth < 2, blocks.count >= 6, let split = gutter(blocks) else { return [blocks] }
        let left: [LensTextBlock] = blocks.filter { $0.box.maxX <= split + 0.004 }
        let right: [LensTextBlock] = blocks.filter { $0.box.minX >= split - 0.004 }
        let wide: [LensTextBlock] = blocks.filter { $0.box.minX < split - 0.004 && $0.box.maxX > split + 0.004 }
        let top: Double = Double(max(minY(left), minY(right)))
        let above: [LensTextBlock] = wide.filter { Double($0.box.midY) < top }
        let below: [LensTextBlock] = wide.filter { Double($0.box.midY) >= top }
        var out: [[LensTextBlock]] = []
        if !above.isEmpty { out.append(above) }
        out.append(contentsOf: columns(left, depth: depth + 1))
        out.append(contentsOf: columns(right, depth: depth + 1))
        if !below.isEmpty { out.append(below) }
        return out
    }

    private static func minY(_ blocks: [LensTextBlock]) -> CGFloat {
        blocks.map { $0.box.minY }.min() ?? 0
    }

    private static func maxY(_ blocks: [LensTextBlock]) -> CGFloat {
        blocks.map { $0.box.maxY }.max() ?? 0
    }

    /// The x of a gutter between two columns, or nil. A gutter is a gap no
    /// block crosses within the band both columns share, with at least three
    /// blocks on each side and the band tall enough to be columns rather than
    /// two options printed side by side.
    static func gutter(_ blocks: [LensTextBlock]) -> Double? {
        var best: (x: Double, gap: Double)? = nil
        let edges: [CGFloat] = blocks.map { $0.box.maxX }.sorted()
        for edge in edges {
            let s: CGFloat = edge + 0.002
            let left: [LensTextBlock] = blocks.filter { $0.box.maxX <= s }
            let right: [LensTextBlock] = blocks.filter { $0.box.minX >= s }
            guard left.count >= 3, right.count >= 3 else { continue }
            let bandTop: CGFloat = max(minY(left), minY(right))
            let bandBottom: CGFloat = min(maxY(left), maxY(right))
            guard bandBottom - bandTop >= 0.15 else { continue }
            let crossing: Bool = blocks.contains { b in
                b.box.minX < s && b.box.maxX > s && b.box.maxY > bandTop + 0.01 && b.box.minY < bandBottom - 0.01
            }
            guard !crossing else { continue }
            let nextLeft: CGFloat = right.map { $0.box.minX }.min() ?? s
            let gap: Double = Double(nextLeft - edge)
            guard gap >= 0.015 else { continue }
            if best == nil || gap > best!.gap { best = (x: Double(s), gap: gap) }
        }
        return best?.x
    }

    // MARK: rows

    /// The blocks of one column as lines, top to bottom, pieces sharing a
    /// row joined left to right.
    static func rows(_ blocks: [LensTextBlock]) -> [Line] {
        let sorted: [LensTextBlock] = blocks.sorted { $0.box.minY < $1.box.minY }
        var rows: [[LensTextBlock]] = []
        for block in sorted {
            if let last = rows.last, sameRow(last, block) {
                rows[rows.count - 1].append(block)
            } else {
                rows.append([block])
            }
        }
        return rows.map { row -> Line in
            let ordered: [LensTextBlock] = row.sorted { $0.box.minX < $1.box.minX }
            let text: String = ordered.map(\.text).joined(separator: " ")
            let box: CGRect = ordered.dropFirst().reduce(ordered[0].box) { $0.union($1.box) }
            return Line(text: text, box: box)
        }
    }

    private static func sameRow(_ row: [LensTextBlock], _ block: LensTextBlock) -> Bool {
        guard let first = row.first else { return false }
        let h: CGFloat = min(first.box.height, block.box.height)
        let dy: CGFloat = abs(first.box.midY - block.box.midY)
        return dy < h * 0.5
    }

    // MARK: markers

    /// What a line starts with.
    enum Marker: Hashable {
        /// A question number: "12.", "Q3", "Question 4:".
        case question(String)
        /// An option: its index (A or 1 is 0) and whether it was a number.
        case option(Int, numbered: Bool)
    }

    /// The marker a line starts with, and the words after it.
    static func marker(_ text: String) -> (marker: Marker, rest: String)? {
        if let circled = circledOption(text) { return circled }
        if let m = match(#"^(?:Q(?:uestion)?\s*)(\d{1,3})\s*[\.\):]?\s*(.*)$"#, text, caseInsensitive: true) {
            return (.question(m[0]), m[1])
        }
        if let m = match(#"^[\(\[]?([A-Fa-f])\s?[\.\)\]:,]\s*(.+)$"#, text) {
            guard let index = letterIndex(m[0]) else { return nil }
            return (.option(index, numbered: false), m[1])
        }
        // OCR reads a printed "B." as "8."
        if let m = match(#"^8[\.\)]\s+([A-Za-z].*)$"#, text) {
            return (.option(1, numbered: false), m[0])
        }
        if let m = match(#"^\((\d)\)\s*(.+)$"#, text), let n = Int(m[0]), n >= 1 {
            return (.option(n - 1, numbered: true), m[1])
        }
        if let m = match(#"^(\d{1,3})\s*(?:\.(?!\d)|\))\s*(.+)$"#, text) {
            return (.question(m[0]), m[1])
        }
        return nil
    }

    /// ① to ⑥, Ⓐ to Ⓕ and ⓐ to ⓕ.
    static func circledOption(_ text: String) -> (marker: Marker, rest: String)? {
        guard let first = text.unicodeScalars.first else { return nil }
        let v: UInt32 = first.value
        var index: Int? = nil
        var numbered = false
        if v >= 0x2460 && v <= 0x2465 { index = Int(v - 0x2460); numbered = true }
        if v >= 0x24B6 && v <= 0x24BB { index = Int(v - 0x24B6) }
        if v >= 0x24D0 && v <= 0x24D5 { index = Int(v - 0x24D0) }
        guard let index else { return nil }
        let rest: String = String(text.unicodeScalars.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return (.option(index, numbered: numbered), rest)
    }

    static func letterIndex(_ letter: String) -> Int? {
        guard let scalar = letter.uppercased().unicodeScalars.first else { return nil }
        let v: Int = Int(scalar.value)
        guard v >= 65 && v <= 70 else { return nil }
        return v - 65
    }

    /// The capture groups of `pattern` in `text`, or nil when it does not match.
    static func match(_ pattern: String, _ text: String, caseInsensitive: Bool = false) -> [String]? {
        guard let regex = compiled(pattern, caseInsensitive: caseInsensitive) else { return nil }
        let ns: NSString = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let found = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        var out: [String] = []
        for i in 1..<found.numberOfRanges {
            let r: NSRange = found.range(at: i)
            out.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return out
    }

    private static let regexLock = NSLock()
    nonisolated(unsafe) private static var regexCache: [String: NSRegularExpression] = [:]

    /// Each pattern compiled once: the live camera runs these on every line
    /// of every frame it reads.
    static func compiled(_ pattern: String, caseInsensitive: Bool) -> NSRegularExpression? {
        let key: String = (caseInsensitive ? "i:" : "c:") + pattern
        regexLock.lock()
        defer { regexLock.unlock() }
        if let hit = regexCache[key] { return hit }
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let made = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        regexCache[key] = made
        return made
    }

    // MARK: options on one line

    /// Lines holding several options ("A. Aspirin  B. Heparin  C. Warfarin"),
    /// or a stem with its options run on after it, cut into one line each.
    /// Each piece keeps the whole line's box, cut across in proportion.
    static func splitInline(_ lines: [Line], breaks: Set<Int>) -> (lines: [Line], breaks: Set<Int>) {
        var out: [Line] = []
        var moved: Set<Int> = []
        for (i, line) in lines.enumerated() {
            if breaks.contains(i) { moved.insert(out.count) }
            let pieces: [String] = inlinePieces(line.text)
            guard pieces.count > 1 else { out.append(line); continue }
            let total: Double = Double(max(1, line.text.count))
            var start: Double = 0
            for piece in pieces {
                let share: Double = Double(piece.count) / total
                let x: Double = Double(line.box.minX) + start * Double(line.box.width)
                let w: Double = share * Double(line.box.width)
                let box = CGRect(x: x, y: Double(line.box.minY), width: max(w, 0.001), height: Double(line.box.height))
                out.append(Line(text: piece, box: box))
                start += share
            }
        }
        return (out, moved)
    }

    /// The pieces of one line at each option marker inside it, in sequence.
    static func inlinePieces(_ text: String) -> [String] {
        let lead: (marker: Marker, rest: String)? = marker(text)
        var expected: Int = 0
        if let lead, case .option(let i, let numbered) = lead.marker, !numbered { expected = i + 1 }
        let pattern: String = #"(?:^|\s)[\(\[]?([A-Fa-f])[\.\)\]]\s+"#
        guard let regex = compiled(pattern, caseInsensitive: false) else { return [text] }
        let ns: NSString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var cuts: [Int] = []
        for m in matches {
            let letter: String = ns.substring(with: m.range(at: 1))
            guard let index = letterIndex(letter), index == expected else { continue }
            let at: Int = m.range.location
            if at == 0 { expected += 1; continue }
            cuts.append(at)
            expected += 1
        }
        // a stem with options run on needs at least A and B to be sure
        let needed: Int = lead == nil ? 2 : 1
        guard cuts.count >= needed else { return [text] }
        var pieces: [String] = []
        var from: Int = 0
        for cut in cuts + [ns.length] {
            let piece: String = ns.substring(with: NSRange(location: from, length: cut - from))
            let trimmed: String = piece.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { pieces.append(trimmed) }
            from = cut
        }
        return pieces
    }

    // MARK: grouping into questions

    private struct Builder {
        var number: String?
        var stem: String = ""
        var options: [(index: Int, marker: String, text: String)] = []
        var numbered: Bool? = nil
        var box: CGRect
        var lastBox: CGRect

        init(number: String?, stem: String, box: CGRect) {
            self.number = number
            self.stem = stem
            self.box = box
            self.lastBox = box
        }

        var lastIndex: Int { options.last?.index ?? -1 }

        mutating func add(_ box: CGRect) {
            self.box = self.box.union(box)
            lastBox = box
        }

        /// Whether an option `index` fits the sequence so far: the first one
        /// is A (or 1); after that the next, allowing one the camera missed.
        func accepts(_ index: Int, numbered: Bool) -> Bool {
            if let mode = self.numbered, mode != numbered { return false }
            if options.isEmpty {
                // numbered options start at 1, and only after a stem that
                // asks for a choice; a letter may start at B (A missed)
                if numbered { return index == 0 && QuestionDetector.asksForChoice(stem) }
                return index <= 1
            }
            let used: Bool = options.contains { $0.index == index }
            return !used && index > lastIndex && index <= lastIndex + 2
        }
    }

    /// Whether a stem reads as one that is followed by choices.
    static func asksForChoice(_ stem: String) -> Bool {
        let t: String = stem.trimmingCharacters(in: .whitespaces)
        guard t.count >= 8 else { return false }
        if t.hasSuffix("?") || t.hasSuffix(":") { return true }
        let lower: String = t.lowercased()
        return lower.contains("following") || lower.contains("which ") || hasBlank(lower)
    }

    private static func group(_ lines: [Line], columnBreaks: Set<Int>) -> [DetectedQuestion] {
        let heights: [CGFloat] = lines.map { $0.box.height }.sorted()
        let lineH: CGFloat = heights.isEmpty ? 0.02 : max(heights[heights.count / 2], 0.005)
        var done: [DetectedQuestion] = []
        var current: Builder? = nil
        var previous: Line? = nil

        func flush() {
            if let b = current, let q = finish(b) { done.append(q) }
            current = nil
        }

        for (i, line) in lines.enumerated() {
            let newColumn: Bool = columnBreaks.contains(i)
            let gap: CGFloat = (newColumn || previous == nil) ? 0 : line.box.minY - (previous?.box.maxY ?? 0)
            previous = line
            let found: (marker: Marker, rest: String)? = marker(line.text)

            if let found, case .option(let index, let numbered) = found.marker,
               var b = current, b.accepts(index, numbered: numbered) {
                let label: String = numbered ? String(index + 1) : LensHash.letter(index)
                b.options.append((index: index, marker: label, text: found.rest))
                if b.numbered == nil { b.numbered = numbered }
                b.add(line.box)
                current = b
                continue
            }
            if let found, case .question(let number) = found.marker {
                // a number that continues a numbered option list is an option
                // - only inside an unnumbered question, and without a gap
                if var b = current, b.number == nil || b.numbered == true, gap <= lineH * 1.6,
                   let n = Int(number), n >= 1, b.accepts(n - 1, numbered: true) {
                    b.options.append((index: n - 1, marker: number, text: found.rest))
                    b.numbered = true
                    b.add(line.box)
                    current = b
                    continue
                }
                flush()
                current = Builder(number: number, stem: found.rest, box: line.box)
                continue
            }
            // plain words: a wrapped line, or the start of an unnumbered question
            guard var b = current else {
                current = Builder(number: nil, stem: line.text, box: line.box)
                continue
            }
            if startsNewQuestion(b, line: line, gap: gap, lineH: lineH) {
                flush()
                current = Builder(number: nil, stem: line.text, box: line.box)
                continue
            }
            if b.options.isEmpty {
                b.stem = joinWrapped(b.stem, line.text)
            } else {
                let last: Int = b.options.count - 1
                b.options[last].text = joinWrapped(b.options[last].text, line.text)
            }
            b.add(line.box)
            current = b
        }
        flush()
        return done
    }

    /// Whether plain words after a question begin another one rather than
    /// carry on the last line.
    private static func startsNewQuestion(_ b: Builder, line: Line, gap: CGFloat, lineH: CGFloat) -> Bool {
        let bigGap: Bool = gap > lineH * 1.6
        if !b.options.isEmpty {
            if bigGap { return true }
            let words: Int = line.text.split(separator: " ").count
            let capital: Bool = line.text.first?.isUppercase ?? false
            return capital && words >= 8 && line.text.contains("?")
        }
        guard gap > lineH * 2.4 else { return false }
        let stem: String = b.stem.trimmingCharacters(in: .whitespaces)
        return stem.hasSuffix("?") || hasBlank(stem.lowercased()) || stem.hasSuffix(".")
    }

    /// Two lines joined as one: a word split by a hyphen at the line's end is
    /// put back together.
    static func joinWrapped(_ a: String, _ b: String) -> String {
        let left: String = a.trimmingCharacters(in: .whitespaces)
        let right: String = b.trimmingCharacters(in: .whitespaces)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        let lowerNext: Bool = right.first?.isLowercase ?? false
        if left.hasSuffix("-") && lowerNext && !left.hasSuffix(" -") {
            return String(left.dropLast()) + right
        }
        return left + " " + right
    }

    private static func finish(_ b: Builder) -> DetectedQuestion? {
        var stem: String = b.stem.trimmingCharacters(in: .whitespaces)
        var opts: [(index: Int, marker: String, text: String)] = b.options.sorted { $0.index < $1.index }
        // one lonely "option" is more likely part of the stem
        if opts.count == 1 {
            let only = opts[0]
            stem = joinWrapped(stem, only.marker + ". " + only.text)
            opts = []
        }
        let options: [LensOption] = opts.map { LensOption(marker: $0.marker, text: $0.text.trimmingCharacters(in: .whitespaces)) }
        guard stem.count >= 6, let type = classify(stem: stem, options: options) else { return nil }
        let key: String = LensHash.key(stem: stem, options: options.map(\.text))
        return DetectedQuestion(type: type, number: b.number, stem: stem, options: options, box: b.box, key: key)
    }

    // MARK: classifying

    /// The question's type, or nil when the words are not a question at all.
    static func classify(stem: String, options: [LensOption]) -> LensQuestionType? {
        let lower: String = stem.lowercased()
        if options.count >= 2 {
            if options.allSatisfy({ isTruthWord($0.text) }) { return .trueFalse }
            return isBestAnswer(lower) ? .bestAnswer : .mcq
        }
        if isTrueFalse(lower) { return .trueFalse }
        if hasBlank(lower) { return .cloze }
        if isCalculation(lower) { return .calculation }
        if isOsce(lower) { return .osce }
        if isImageLabel(lower) { return .imageLabel }
        if isVignette(lower) && asks(lower) { return .clinicalCase }
        if asks(lower) && lower.split(separator: " ").count >= 2 { return .shortAnswer }
        return nil
    }

    static func isTruthWord(_ text: String) -> Bool {
        let t: String = text.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        return ["true", "false", "t", "f", "yes", "no"].contains(t)
    }

    static func isBestAnswer(_ lower: String) -> Bool {
        let cues: [String] = ["most likely", "best ", "most appropriate", "next step", "most accurate",
                              "most common", "single best", "initial", "first-line", "first line",
                              "most useful", "most important"]
        return cues.contains { lower.contains($0) } || isVignette(lower)
    }

    static func isTrueFalse(_ lower: String) -> Bool {
        if lower.hasPrefix("true or false") || lower.hasPrefix("t/f") { return true }
        let cues: [String] = ["true or false", "(t/f)", " t/f", "true/false", "(true/false)"]
        return cues.contains { lower.contains($0) }
    }

    static func hasBlank(_ lower: String) -> Bool {
        if lower.contains("___") || lower.contains("[blank]") || lower.contains("( )") { return true }
        if lower.contains("\u{2026}\u{2026}") || lower.contains(".....") { return true }
        return lower.range(of: #"_{2,}|\(\s{1,3}\)"#, options: .regularExpression) != nil
    }

    /// A number with a clinical or physical unit: "70 kg", "4.5 mmol/L", "15%".
    static let unitPattern: String = #"\d+(?:\.\d+)?\s?(?:(?:mg/kg|mcg|µg|ug|mg|kg|g/dl|g/l|g|ml/min|ml/h|ml|l/min|l|mmol/l|mmol|mmhg|meq|iu|units?|bpm|cm|mm|m2|mosm|hours?|hrs?|min|drops?)\b|%)"#

    static func isCalculation(_ lower: String) -> Bool {
        let cues: [String] = ["calculate", "compute", "work out", "estimate the", "what dose", "how many ml",
                              "how many mg", "how many drops", "infusion rate", "anion gap", "creatinine clearance",
                              " bmi", "osmolality", "a-a gradient", "drip rate", "how much"]
        let hasCue: Bool = cues.contains { lower.contains($0) }
        let units: Int = count(unitPattern, in: lower)
        if hasCue && units >= 1 { return true }
        if hasCue && lower.range(of: #"\d"#, options: .regularExpression) != nil && lower.contains("calculat") { return true }
        return units >= 2 && lower.contains("?") && (lower.contains("what is the") || lower.contains("how many"))
    }

    static func count(_ pattern: String, in text: String) -> Int {
        guard let regex = compiled(pattern, caseInsensitive: true) else { return 0 }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }

    static func isOsce(_ lower: String) -> Bool {
        let starts: [String] = ["take a", "examine", "perform", "demonstrate", "counsel", "explain to", "obtain consent",
                                "carry out", "assess this", "break the news", "insert a", "you are the", "you are a",
                                "you are an", "station", "this patient has come", "please take", "please examine"]
        if starts.contains(where: { lower.hasPrefix($0) }) { return true }
        let inside: [String] = ["take a history", "take a focused history", "examine the", "examination of the",
                                "you have 5 minutes", "you have 8 minutes", "you have 10 minutes", "osce"]
        return inside.contains { lower.contains($0) }
    }

    static func isImageLabel(_ lower: String) -> Bool {
        let cues: [String] = ["label", "structure marked", "structures marked", "identify the structure", " arrow",
                              "shown in the image", "shown in the figure", "shown in the picture", "in the image",
                              "in the figure", "in the diagram", "what is shown", "this x-ray", "this radiograph",
                              "this ecg", "this image", "this picture", "this slide", "name the parts"]
        return cues.contains { lower.contains($0) }
    }

    static func isVignette(_ lower: String) -> Bool {
        let age: Bool = lower.range(of: #"\b\d{1,3}[- ]?(year|yr|month|week|day)s?[- ]?old\b"#,
                                    options: .regularExpression) != nil
        let cues: [String] = ["presents with", "presents to", "presented with", "presented to", "is brought",
                              "comes to", "attends", "complains of", "history of"]
        let cue: Bool = cues.contains { lower.contains($0) }
        let words: Int = lower.split(separator: " ").count
        return (age || cue) && words >= 18
    }

    /// Whether the words ask something: a question mark, or a question or
    /// instruction word at the start.
    static func asks(_ lower: String) -> Bool {
        if lower.contains("?") { return true }
        let heads: [String] = ["what", "which", "why", "how", "when", "where", "who", "define", "list", "name",
                               "describe", "explain", "outline", "state", "give", "compare", "differentiate",
                               "mention", "enumerate", "discuss", "identify", "classify", "write"]
        let first: String = lower.split(separator: " ").first.map(String.init) ?? ""
        let word: String = first.trimmingCharacters(in: CharacterSet.letters.inverted)
        if heads.contains(word) { return true }
        let cues: [String] = ["diagnosis", "next step", "management", "investigation"]
        return cues.contains { lower.contains($0) } && isVignette(lower)
    }
}

// MARK: - Keys

/// Text keys that stay the same for the same words, across frames and
/// launches (FNV-1a, not Swift's Hasher, which changes every launch).
enum LensHash {

    /// The words that matter, lower case, letters and digits only.
    static func words(_ text: String) -> [String] {
        let lower: String = text.lowercased()
        let parts = lower.split { ch in !(ch.isLetter || ch.isNumber) }
        return parts.map(String.init)
    }

    /// A question's key: its stem's first 30 words and its options.
    static func key(stem: String, options: [String]) -> String {
        let stemWords: [String] = Array(words(stem).prefix(30))
        let optionWords: [String] = options.map { words($0).joined(separator: " ") }
        let body: String = stemWords.joined(separator: " ") + "|" + optionWords.joined(separator: "|")
        return fnv(body)
    }

    /// The key an answer is cached under: the whole question's words.
    static func answerKey(_ q: DetectedQuestion) -> String {
        "a1-" + q.type.rawValue + "-" + fnv(words(q.fullText).joined(separator: " "))
    }

    static func fnv(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    /// Word overlap, 0...1 (Jaccard).
    static func similarity(_ a: String, _ b: String) -> Double {
        let x: Set<String> = Set(words(a))
        let y: Set<String> = Set(words(b))
        guard !x.isEmpty || !y.isEmpty else { return 1 }
        let shared: Double = Double(x.intersection(y).count)
        let all: Double = Double(x.union(y).count)
        return shared / all
    }

    static func letter(_ index: Int) -> String {
        guard index >= 0, index < 26 else { return "?" }
        return String(UnicodeScalar(UInt8(65 + index)))
    }

    static func firstWords(_ text: String, count: Int) -> String {
        let parts: [Substring] = text.split(separator: " ")
        let head: String = parts.prefix(count).joined(separator: " ")
        return parts.count > count ? head + "\u{2026}" : head
    }
}
