import Foundation

/// One cover per label, and the answer is exactly what is under it.
///
/// Vision reads a diagram a word (or a run of words) at a time. Covering each
/// piece on its own is what made the old covers bad: "Superior vena" and
/// "cava" became two covers, one of them often thrown away by the filter so
/// half the label stayed readable, and the padding the screen added round
/// every piece made neighbouring covers overlap. The card's answer was the
/// text of one OCR line, which need not be what the cover hid.
///
/// So the words are first grouped into label phrases:
///   - words on one line join when the space between them is under about a
///     letter-height and they are the same size;
///   - the lines of a wrapped label join when they sit right under each other,
///     overlap or line up (left, centre or right), are the same size, carry on
///     from one another, and no leader line runs between them;
///   - boxes that overlap are always one label.
/// A phrase gets ONE cover: the union of its words, padded, and never over
/// another cover or over a word that is not part of it. The answer is the
/// words under the cover in reading order, and `problems` re-checks all of it.
///
/// Plain geometry and text, no Vision and no UIKit, so all of it is tested.
enum OcclusionPhrases {

    /// One piece of text as OCR read it: a word, or a run of words when OCR
    /// could not say where each word is. The box is fractions of the picture,
    /// origin top left, like every stored box.
    struct Word: Equatable {
        var text: String
        var box: OcclusionBox
        var confidence: Double = 1
    }

    /// Words that belong to one label. `lines` are indices into the words
    /// grouped, top line first and each line left to right.
    struct Phrase: Equatable {
        var lines: [[Int]]
        var text: String
        var box: OcclusionBox
        var confidence: Double
        /// The height of one line of the label, as a fraction of the picture.
        var lineHeight: Double

        var members: [Int] { lines.flatMap { $0 } }
    }

    /// What one card hides: a single rectangle and the words under it.
    struct Cover: Equatable {
        var box: OcclusionBox
        var answer: String
        var lines: [[Int]]

        var members: [Int] { lines.flatMap { $0 } }
    }

    // MARK: thresholds, in letter-heights

    /// Words on one line are one label when the space between them is at most
    /// this many letter-heights.
    static let lineGap = 1.2
    /// Pieces taller than this many times the other are a heading beside a
    /// label, not part of it.
    static let lineHeightRatio = 1.5
    /// The lines of a wrapped label are at most this far apart.
    static let wrapGap = 0.6
    /// A next line that starts with a capital is only a continuation when the
    /// lines are set this tight; looser, it is the next label in a list.
    static let capitalWrapGap = 0.25
    /// The lines of one label are set in one size.
    static let wrapHeightRatio = 1.35
    /// How far edges may differ and still count as lined up.
    static let alignSlack = 0.75
    /// The most lines one label wraps onto.
    static let maximumLines = 3
    /// How far a cover reaches past the glyphs when nothing is in the way.
    static let padding = 0.3

    // MARK: grouping

    /// The label phrases among `words`, in reading order.
    ///
    /// `aspect` is the picture's width over its height, so distances across
    /// and down are measured in the same letter-heights. `separated` is asked
    /// about the strip between two lines that might be one label; it answers
    /// true when figure ink (a leader line) runs through it.
    static func group(_ words: [Word], aspect: Double = 1,
                      separated: ((OcclusionBox) -> Bool)? = nil) -> [Phrase] {
        let scale: Double = max(aspect, 0.01)
        var usable: [Int] = []
        for i in words.indices where isGroupable(words[i]) { usable.append(i) }
        let rects: [Rect] = words.map { Rect($0.box, aspect: scale) }

        // words on one line, and boxes that overlap
        var parent: [Int] = Array(words.indices)
        for a in 0..<usable.count {
            for b in (a + 1)..<usable.count {
                let i: Int = usable[a]
                let j: Int = usable[b]
                let overlapping: Bool = rects[i].overlaps(rects[j]) && similarSize(rects[i], rects[j])
                if overlapping || sameLine(rects[i], words[i].text, rects[j], words[j].text) {
                    union(&parent, i, j)
                }
            }
        }
        var lines: [[Int]] = components(usable, parent: &parent)
        lines = lines.map { sortedAcross($0, rects: rects) }

        // the lines of a wrapped label
        var lineParent: [Int] = Array(lines.indices)
        let order: [Int] = lines.indices.sorted { lineRect(lines[$0], rects).minY < lineRect(lines[$1], rects).minY }
        for a in 0..<order.count {
            for b in 0..<order.count where b != a {
                let upper: Int = order[a]
                let lower: Int = order[b]
                let top: Rect = lineRect(lines[upper], rects)
                let bottom: Rect = lineRect(lines[lower], rects)
                guard top.midY < bottom.midY else { continue }
                let rootA: Int = find(&lineParent, upper)
                let rootB: Int = find(&lineParent, lower)
                guard rootA != rootB else { continue }
                let countA: Int = lineParent.indices.filter { find(&lineParent, $0) == rootA }.count
                let countB: Int = lineParent.indices.filter { find(&lineParent, $0) == rootB }.count
                guard countA + countB <= maximumLines else { continue }
                let upperText: String = lineText(lines[upper], words)
                let lowerText: String = lineText(lines[lower], words)
                guard wraps(top, upperText, bottom, lowerText) else { continue }
                if let separated, gapHasInk(top, bottom, aspect: scale, separated) { continue }
                union(&lineParent, upper, lower)
            }
        }
        let blocks: [[Int]] = components(Array(lines.indices), parent: &lineParent)

        var phrases: [Phrase] = []
        for block in blocks {
            let ordered: [[Int]] = block.map { lines[$0] }.sorted {
                lineRect($0, rects).minY < lineRect($1, rects).minY
            }
            let kept: [[Int]] = ordered
            let text: String = answer(for: kept, words: words)
            guard !text.isEmpty else { continue }
            let all: [Int] = kept.flatMap { $0 }
            let box: OcclusionBox = union(all.map { words[$0].box })
            let sure: Double = all.map { words[$0].confidence }.min() ?? 1
            let heights: [Double] = all.map { words[$0].box.h }.sorted()
            let lineHeight: Double = heights.isEmpty ? box.h : heights[heights.count / 2]
            phrases.append(Phrase(lines: kept, text: text, box: box,
                                  confidence: sure, lineHeight: lineHeight))
        }
        return phrases.sorted { a, b in
            if abs(a.box.y - b.box.y) > min(a.lineHeight, b.lineHeight) * 0.5 { return a.box.y < b.box.y }
            return a.box.x < b.box.x
        }
    }

    /// Two readings of the same text are about the same height. A box many
    /// times taller than a word it overlaps is OCR boxing half the picture,
    /// not another reading of the word.
    static func similarSize(_ a: Rect, _ b: Rect) -> Bool {
        let tall: Double = max(a.height, b.height)
        let short: Double = min(a.height, b.height)
        return short > 0 && tall <= short * 2
    }

    /// Whether `right` carries on the line `left` is on: the same size, level
    /// with it, and at most `lineGap` letter-heights along.
    static func sameLine(_ a: Rect, _ aText: String, _ b: Rect, _ bText: String) -> Bool {
        let tall: Double = max(a.height, b.height)
        let short: Double = min(a.height, b.height)
        guard short > 0, tall <= short * lineHeightRatio else { return false }
        guard abs(a.midY - b.midY) <= short * 0.5 else { return false }
        let gapRight: Double = b.minX - a.maxX
        let gapLeft: Double = a.minX - b.maxX
        let gap: Double = max(gapRight, gapLeft)
        guard gap <= tall * lineGap else { return false }
        // a number beside a label is not part of it
        return hasLetters(aText) && hasLetters(bText)
    }

    /// Whether `lower` is the rest of the label `upper` starts: directly
    /// under it, the same size, lined up, and reading on from it.
    static func wraps(_ upper: Rect, _ upperText: String, _ lower: Rect, _ lowerText: String) -> Bool {
        let tall: Double = max(upper.height, lower.height)
        let short: Double = min(upper.height, lower.height)
        guard short > 0, tall <= short * wrapHeightRatio else { return false }
        guard hasLetters(upperText), hasLetters(lowerText) else { return false }
        let gap: Double = lower.minY - upper.maxY
        guard gap >= -0.25 * short, gap <= wrapGap * tall else { return false }
        guard linedUp(upper, lower, slack: alignSlack * tall) else { return false }
        if carriesOn(upperText, lowerText) { return true }
        // a new capital after a looser gap is the next label in a list
        return gap <= capitalWrapGap * tall
            && wordCount(upperText) <= 3 && wordCount(lowerText) <= 3
    }

    /// Left, centre or right edges within `slack`, or one line mostly over
    /// the other.
    static func linedUp(_ a: Rect, _ b: Rect, slack: Double) -> Bool {
        if abs(a.minX - b.minX) <= slack { return true }
        if abs(a.maxX - b.maxX) <= slack { return true }
        if abs(a.midX - b.midX) <= slack { return true }
        let shared: Double = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let narrower: Double = min(a.width, b.width)
        return narrower > 0 && shared >= narrower * 0.5
    }

    /// Whether the next line reads as the rest of this one: it starts in
    /// lower case, or this one ends mid-phrase.
    static func carriesOn(_ upper: String, _ lower: String) -> Bool {
        let trimmed: String = upper.trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last, "-\u{2010}/&,+".contains(last) { return true }
        let lastWord: String = trimmed.split(separator: " ").last.map { String($0).lowercased() } ?? ""
        if ["of", "and", "the", "to", "for", "with", "or"].contains(lastWord) { return true }
        guard let first = lower.first(where: { $0.isLetter }) else { return false }
        return first.isLowercase
    }

    /// Whether figure ink runs across the gap between two lines.
    static func gapHasInk(_ upper: Rect, _ lower: Rect, aspect: Double,
                          _ separated: (OcclusionBox) -> Bool) -> Bool {
        let top: Double = upper.maxY
        let bottom: Double = lower.minY
        guard bottom > top else { return false }
        var left: Double = max(upper.minX, lower.minX)
        var right: Double = min(upper.maxX, lower.maxX)
        if right <= left {
            left = min(upper.minX, lower.minX)
            right = max(upper.maxX, lower.maxX)
        }
        let strip = OcclusionBox(x: left / aspect, y: top, w: (right - left) / aspect, h: bottom - top)
        return separated(strip)
    }

    /// A line's words in one box.
    static func lineRect(_ line: [Int], _ rects: [Rect]) -> Rect {
        var out: Rect = rects[line[0]]
        for i in line.dropFirst() { out = out.union(rects[i]) }
        return out
    }

    static func lineText(_ line: [Int], _ words: [Word]) -> String {
        line.map { words[$0].text }.joined(separator: " ")
    }

    /// The same word read twice - two OCR boxes on top of each other with the
    /// same text, or a line read whole and then word by word - is said once
    /// in the answer (every reading stays under the cover).
    static func withoutRepeats(_ lines: [[Int]], words: [Word]) -> [[Int]] {
        let rects: [Rect] = words.map { Rect($0.box, aspect: 1) }
        var seen: [Int] = []
        var out: [[Int]] = []
        for line in lines {
            var kept: [Int] = []
            for i in line {
                let text: String = compact(words[i].text)
                // already said by a reading on top of it: the same word, or
                // the whole line it is part of
                let twin: Bool = seen.contains { j in
                    compact(words[j].text).contains(text) && rects[i].overlapShare(rects[j]) > 0.6
                }
                if twin { continue }
                seen.append(i)
                kept.append(i)
            }
            if !kept.isEmpty { out.append(kept) }
        }
        return out
    }

    // MARK: the answer

    /// The words under a cover as one phrase: each line's words joined with
    /// spaces, lines joined the same way except where a word was broken with
    /// a hyphen, and bullets, leader dots and stray punctuation trimmed.
    static func answer(for lines: [[Int]], words: [Word]) -> String {
        var out: String = ""
        for line in withoutRepeats(lines, words: words) {
            let text: String = tidy(line.map { words[$0].text }.joined(separator: " "))
            guard !text.isEmpty else { continue }
            if out.isEmpty {
                out = text
            } else if mendsHyphen(out, text) {
                out = String(out.dropLast()) + text
            } else {
                out += " " + text
            }
        }
        return trimEnds(out)
    }

    /// "Pulmo-" then "nary": one word broken over a line.
    static func mendsHyphen(_ before: String, _ after: String) -> Bool {
        guard let last = before.last, last == "-" || last == "\u{2010}" else { return false }
        let beforeLast: Character? = before.dropLast().last
        guard let letter = beforeLast, letter.isLetter else { return false }
        guard let first = after.first else { return false }
        return first.isLetter && first.isLowercase
    }

    /// Bullets and leader dots off the ends, whitespace collapsed.
    static func trimEnds(_ text: String) -> String {
        let junk: Set<Character> = ["\u{2022}", "\u{00B7}", "\u{2023}", "\u{25E6}", "\u{25AA}", "\u{25CF}",
                                    "*", ".", "\u{2026}", ":", ";", ",", "-", "\u{2013}", "\u{2014}",
                                    "_", "\u{2192}", "\u{2190}", ">", "<", "|"]
        var chars: [Character] = Array(tidy(text))
        while let first = chars.first, junk.contains(first) || first.isWhitespace { chars.removeFirst() }
        while let last = chars.last, junk.contains(last) || last.isWhitespace { chars.removeLast() }
        return tidy(String(chars))
    }

    static func tidy(_ text: String) -> String {
        text.split { $0.isWhitespace }.joined(separator: " ")
    }

    /// Letters and digits only, lower case: what two readings of a word share.
    static func compact(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Text worth grouping: it has a letter or a digit (a bullet or a run of
    /// leader dots is not text) and a box of some size.
    static func isText(_ word: Word) -> Bool {
        guard word.box.w > 0, word.box.h > 0 else { return false }
        return word.text.contains { $0.isLetter || $0.isNumber }
    }

    /// OCR sure enough of itself to be part of a label.
    static func isGroupable(_ word: Word) -> Bool {
        isText(word) && word.confidence >= OcclusionFilter.minimumConfidence
    }

    static func hasLetters(_ text: String) -> Bool { text.contains { $0.isLetter } }

    static func wordCount(_ text: String) -> Int { text.split { $0.isWhitespace }.count }

    // MARK: covers

    /// One cover for each phrase in `kept`.
    ///
    /// A cover starts as the union of its phrase's words and grows by
    /// `padding` letter-heights on each side, but never onto another word or
    /// another cover: where two would meet, each stops halfway across the gap
    /// between them. Two phrases whose words overlap are one label and share
    /// one cover.
    static func covers(for kept: [Phrase], words: [Word], aspect: Double = 1) -> [Cover] {
        let scale: Double = max(aspect, 0.01)
        let merged: [Phrase] = mergedOverlaps(kept, words: words, aspect: scale)
        let bases: [Rect] = merged.map { Rect($0.box, aspect: scale) }
        let wanted: [Double] = merged.map { $0.lineHeight * padding }
        let full: [Rect] = bases.indices.map { bases[$0].grown(wanted[$0]) }

        var out: [Cover] = []
        for i in merged.indices {
            let base: Rect = bases[i]
            var pads = Pads(all: wanted[i])
            let mine: Set<Int> = Set(merged[i].members)
            // every other piece of text on the picture, covered or not
            for k in words.indices where !mine.contains(k) && isText(words[k]) {
                let other = Rect(words[k].box, aspect: scale)
                if full[i].overlaps(other) { pads.limit(base, by: other) }
            }
            for j in merged.indices where j != i {
                if full[i].overlaps(full[j]) { pads.limit(base, by: bases[j]) }
            }
            let grown: Rect = base.padded(pads).clamped(width: scale)
            out.append(Cover(box: grown.box(aspect: scale), answer: merged[i].text,
                             lines: merged[i].lines))
        }
        return out
    }

    /// Phrases whose boxes overlap are one label: two OCR readings of it.
    static func mergedOverlaps(_ phrases: [Phrase], words: [Word], aspect: Double) -> [Phrase] {
        var out: [Phrase] = phrases
        var changed: Bool = true
        while changed {
            changed = false
            search: for i in out.indices {
                for j in out.indices where j > i {
                    let a = Rect(out[i].box, aspect: aspect)
                    let b = Rect(out[j].box, aspect: aspect)
                    guard a.overlaps(b) else { continue }
                    out[i] = joined(out[i], out[j], words: words, aspect: aspect)
                    out.remove(at: j)
                    changed = true
                    break search
                }
            }
        }
        return out
    }

    static func joined(_ a: Phrase, _ b: Phrase, words: [Word], aspect: Double) -> Phrase {
        let first: [[Int]] = a.box.y <= b.box.y ? a.lines : b.lines
        let second: [[Int]] = a.box.y <= b.box.y ? b.lines : a.lines
        let lines: [[Int]] = first + second
        let all: [Int] = lines.flatMap { $0 }
        return Phrase(lines: lines, text: answer(for: lines, words: words),
                      box: union(all.map { words[$0].box }),
                      confidence: min(a.confidence, b.confidence),
                      lineHeight: max(a.lineHeight, b.lineHeight))
    }

    // MARK: checking

    /// Everything wrong with a set of covers, as sentences; empty when every
    /// cover is sound:
    ///   - no two covers overlap;
    ///   - every word a cover claims lies wholly inside it, and inside no
    ///     other cover;
    ///   - no other word lies under any cover (more than a 5% sliver of it);
    ///   - each answer is exactly its words, in reading order, and every one
    ///     of them is in it.
    static func problems(_ covers: [Cover], words: [Word], aspect: Double = 1) -> [String] {
        let scale: Double = max(aspect, 0.01)
        let rects: [Rect] = covers.map { Rect($0.box, aspect: scale) }
        var found: [String] = []
        for i in covers.indices {
            for j in covers.indices where j > i && rects[i].overlaps(rects[j]) {
                found.append("covers \"\(covers[i].answer)\" and \"\(covers[j].answer)\" overlap")
            }
        }
        var owner: [Int: Int] = [:]
        for i in covers.indices {
            for k in covers[i].members {
                guard words.indices.contains(k) else {
                    found.append("\"\(covers[i].answer)\" claims a word that does not exist")
                    continue
                }
                if let other = owner[k] {
                    found.append("\"\(words[k].text)\" is in both \"\(covers[other].answer)\" and \"\(covers[i].answer)\"")
                }
                owner[k] = i
            }
        }
        for k in words.indices where isText(words[k]) {
            let box = Rect(words[k].box, aspect: scale)
            for i in covers.indices where rects[i].hides(box) || owner[k] == i {
                if owner[k] == i {
                    if !rects[i].contains(box) {
                        found.append("\"\(words[k].text)\" sticks out of its cover")
                    }
                } else {
                    found.append("\"\(words[k].text)\" is under \"\(covers[i].answer)\" but not in its answer")
                }
            }
        }
        for cover in covers {
            let expected: String = answer(for: cover.lines, words: words)
            if cover.answer.isEmpty { found.append("a cover has no answer") }
            if cover.answer != expected {
                found.append("\"\(cover.answer)\" is not the text under it, \"\(expected)\"")
            }
            let whole: String = compact(cover.answer)
            for k in cover.members where words.indices.contains(k) && !whole.contains(compact(words[k].text)) {
                found.append("\"\(words[k].text)\" is under \"\(cover.answer)\" but missing from it")
            }
        }
        return found
    }

    // MARK: the whole route

    /// From every piece of text OCR read on a picture to the covers worth
    /// making cards from: grouped into phrases, each phrase put through
    /// OcclusionFilter whole, then covered. A cover that fails `problems` is
    /// left off rather than drawn wrong.
    ///
    /// `hasInk` is asked whether there is writing under a phrase's box when
    /// the picture is at hand.
    static func layout(_ words: [Word], figure: OcclusionBox?, pageBands: Bool = true,
                       aspect: Double = 1,
                       separated: ((OcclusionBox) -> Bool)? = nil,
                       hasInk: ((OcclusionBox) -> Bool)? = nil) -> [Cover] {
        let phrases: [Phrase] = group(words, aspect: aspect, separated: separated)
        let lines: [OcclusionFilter.Line] = phrases.map {
            OcclusionFilter.Line(text: $0.text, box: $0.box, confidence: $0.confidence,
                                 lineHeight: $0.lineHeight)
        }
        let passing: [Int] = OcclusionFilter.keptIndices(lines, figure: figure, pageBands: pageBands)
        var kept: [Phrase] = []
        for index in passing {
            if let hasInk, !hasInk(phrases[index].box) { continue }
            kept.append(phrases[index])
        }
        let made: [Cover] = covers(for: kept, words: words, aspect: aspect)
        return made.filter { cover in problems([cover] + made.filter { $0 != cover },
                                               words: words, aspect: aspect).isEmpty }
    }

    /// One occlusion card per label, masking exactly that label.
    ///
    /// The same term labelled twice on one picture is one card, but both of
    /// its places stay covered on every card, so neither gives the other away.
    /// `minimumLabels` is how many labels a picture needs before it is a
    /// labelled diagram at all.
    static func cards(from covers: [Cover], imageIndex: Int,
                      question: String = "What is labelled here?",
                      minimumLabels: Int = 2) -> [AnkiCard] {
        guard !covers.isEmpty, covers.count >= minimumLabels else { return [] }
        var asked: [String] = []
        var cards: [AnkiCard] = []
        for i in covers.indices {
            let key: String = compact(covers[i].answer)
            if asked.contains(key) { continue }
            asked.append(key)
            var card = AnkiCard(type: .occlusion, front: question,
                                bullets: [covers[i].answer], why: "",
                                imageIndex: imageIndex, occlusion: covers[i].box)
            card.siblings = covers.indices.filter { $0 != i }.map { covers[$0].box }
            cards.append(card)
        }
        return cards
    }

    // MARK: geometry

    /// A box measured in picture-heights both ways, so a gap across and a gap
    /// down can be compared.
    struct Rect: Equatable {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double

        init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }

        init(_ box: OcclusionBox, aspect: Double) {
            minX = box.x * aspect
            maxX = (box.x + box.w) * aspect
            minY = box.y
            maxY = box.y + box.h
        }

        var width: Double { maxX - minX }
        var height: Double { maxY - minY }
        var midX: Double { (minX + maxX) / 2 }
        var midY: Double { (minY + maxY) / 2 }

        /// Sharing some area, not merely touching.
        func overlaps(_ other: Rect) -> Bool {
            let across: Double = min(maxX, other.maxX) - max(minX, other.minX)
            let down: Double = min(maxY, other.maxY) - max(minY, other.minY)
            return across > 1e-9 && down > 1e-9
        }

        /// Whether this, as a cover, hides some of `other`: more than a sliver
        /// of the other's area. (Measured on the other box, so a word lying
        /// inside a box OCR drew round half the picture is not "hidden" by
        /// the word's own cover.)
        func hides(_ other: Rect) -> Bool {
            let across: Double = min(maxX, other.maxX) - max(minX, other.minX)
            let down: Double = min(maxY, other.maxY) - max(minY, other.minY)
            guard across > 1e-9, down > 1e-9 else { return false }
            let area: Double = other.width * other.height
            return area <= 0 || (across * down) / area > 0.05
        }

        func contains(_ other: Rect) -> Bool {
            other.minX >= minX - 1e-9 && other.maxX <= maxX + 1e-9
                && other.minY >= minY - 1e-9 && other.maxY <= maxY + 1e-9
        }

        /// The share of the smaller box the two have in common.
        func overlapShare(_ other: Rect) -> Double {
            let across: Double = min(maxX, other.maxX) - max(minX, other.minX)
            let down: Double = min(maxY, other.maxY) - max(minY, other.minY)
            guard across > 0, down > 0 else { return 0 }
            let smaller: Double = min(width * height, other.width * other.height)
            return smaller > 0 ? (across * down) / smaller : 0
        }

        func union(_ other: Rect) -> Rect {
            Rect(minX: min(minX, other.minX), minY: min(minY, other.minY),
                 maxX: max(maxX, other.maxX), maxY: max(maxY, other.maxY))
        }

        func grown(_ by: Double) -> Rect {
            Rect(minX: minX - by, minY: minY - by, maxX: maxX + by, maxY: maxY + by)
        }

        func padded(_ pads: Pads) -> Rect {
            Rect(minX: minX - pads.left, minY: minY - pads.top,
                 maxX: maxX + pads.right, maxY: maxY + pads.bottom)
        }

        /// Kept on the picture, which is `width` picture-heights across.
        func clamped(width: Double) -> Rect {
            Rect(minX: max(0, minX), minY: max(0, minY),
                 maxX: min(width, maxX), maxY: min(1, maxY))
        }

        func box(aspect: Double) -> OcclusionBox {
            OcclusionBox(x: minX / aspect, y: minY, w: width / aspect, h: height)
        }
    }

    /// How far a cover reaches past its words on each side.
    struct Pads {
        var left: Double
        var top: Double
        var right: Double
        var bottom: Double

        init(all: Double) {
            left = all
            top = all
            right = all
            bottom = all
        }

        /// Stop halfway to `other`, on the side facing it, along whichever
        /// axis the two are further apart - that alone keeps them apart.
        mutating func limit(_ base: Rect, by other: Rect) {
            let rightGap: Double = other.minX - base.maxX
            let leftGap: Double = base.minX - other.maxX
            let downGap: Double = other.minY - base.maxY
            let upGap: Double = base.minY - other.maxY
            let across: Double = max(rightGap, leftGap)
            let down: Double = max(downGap, upGap)
            guard across >= 0 || down >= 0 else { return }
            if across >= down {
                let half: Double = across / 2
                if rightGap >= leftGap { right = min(right, half) } else { left = min(left, half) }
            } else {
                let half: Double = down / 2
                if downGap >= upGap { bottom = min(bottom, half) } else { top = min(top, half) }
            }
        }
    }

    static func union(_ boxes: [OcclusionBox]) -> OcclusionBox {
        guard let first = boxes.first else { return OcclusionBox(x: 0, y: 0, w: 0, h: 0) }
        var minX: Double = first.x
        var minY: Double = first.y
        var maxX: Double = first.x + first.w
        var maxY: Double = first.y + first.h
        for box in boxes.dropFirst() {
            minX = min(minX, box.x)
            minY = min(minY, box.y)
            maxX = max(maxX, box.x + box.w)
            maxY = max(maxY, box.y + box.h)
        }
        return OcclusionBox(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }

    // MARK: union-find

    static func find(_ parent: inout [Int], _ i: Int) -> Int {
        var root: Int = i
        while parent[root] != root { root = parent[root] }
        var node: Int = i
        while parent[node] != root {
            let next: Int = parent[node]
            parent[node] = root
            node = next
        }
        return root
    }

    static func union(_ parent: inout [Int], _ a: Int, _ b: Int) {
        let rootA: Int = find(&parent, a)
        let rootB: Int = find(&parent, b)
        if rootA != rootB { parent[max(rootA, rootB)] = min(rootA, rootB) }
    }

    /// The groups among `items`, each in its original order.
    static func components(_ items: [Int], parent: inout [Int]) -> [[Int]] {
        var groups: [Int: [Int]] = [:]
        var roots: [Int] = []
        for item in items {
            let root: Int = find(&parent, item)
            if groups[root] == nil { roots.append(root) }
            groups[root, default: []].append(item)
        }
        return roots.map { groups[$0] ?? [] }
    }

    /// Left to right; where two start together, the wider first, so a line
    /// read whole comes before its own words read again.
    static func sortedAcross(_ line: [Int], rects: [Rect]) -> [Int] {
        line.sorted { a, b in
            if abs(rects[a].minX - rects[b].minX) > 1e-9 { return rects[a].minX < rects[b].minX }
            return rects[a].width > rects[b].width
        }
    }
}
