// Red Pen · how a lecture is cut up to be read aloud, and where each word falls
//
// Narrate reads a typed lecture aloud with the natural cloud voice, and falls
// back to the phone's own voice. Everything here is pure arithmetic, kept
// apart from the audio so it can be tested on Linux:
//
//   chunks     lines grouped into clips the server will take: a short first
//              clip so speech starts quickly, then longer ones, so a lecture
//              is a few dozen requests rather than one per line (the server
//              allows each account a few hundred lines a day)
//   wordTimes  a clip's words spread over the clip's REAL duration by how
//              long each takes to say, with room for the pauses at commas,
//              full stops and line ends - an even split makes the highlight
//              race ahead in lists and lag after every full stop
//   spot       which word is being said at a moment, by binary search
//   prefetch   which clips to fetch next, so the next few are always ready
//   phoneRate  a playback speed as AVSpeechUtterance's rate
//   wordIndex  the word a speech-synthesis range starts in
import Foundation

/// Consecutive lines read as one clip.
struct NarrateChunk: Equatable, Sendable {
    let lines: Range<Int>
    let text: String
}

/// One word inside a clip, and when it is said, in seconds from the clip start.
struct ClipWord: Equatable, Sendable {
    let line: Int
    let word: Int
    let start: Double
    let end: Double
}

enum NarratePlan {

    /// The server takes up to 1,500 characters; a little under leaves room.
    static let hardCap = 1400
    /// The first clip is short so the voice starts within a second or two.
    static let firstLimit = 240
    /// Later clips are longer: fewer requests, and each is fetched well
    /// before it is needed.
    static let limit = 900

    // MARK: cutting the lecture into clips

    /// Lines grouped into clips. A line is never split, and a clip always has
    /// at least one line, so a single very long line becomes its own clip
    /// (the phone's voice reads it if the server will not take it).
    static func chunks(_ lines: [String], first: Int = firstLimit, rest: Int = limit) -> [NarrateChunk] {
        var out: [NarrateChunk] = []
        var start = 0
        var length = 0
        for i in lines.indices {
            let n: Int = lines[i].count + 1
            let cap: Int = out.isEmpty ? first : rest
            if i > start && length + n > cap {
                out.append(chunk(lines, start..<i))
                start = i
                length = 0
            }
            length += n
        }
        if start < lines.count {
            out.append(chunk(lines, start..<lines.count))
        }
        return out
    }

    private static func chunk(_ lines: [String], _ range: Range<Int>) -> NarrateChunk {
        let parts: [String] = range.map { lines[$0].trimmingCharacters(in: .whitespaces) }
        let text: String = parts.filter { !$0.isEmpty }.joined(separator: " ")
        return NarrateChunk(lines: range, text: text)
    }

    /// The clip a line is read in.
    static func chunkIndex(containing line: Int, in chunks: [NarrateChunk]) -> Int? {
        var lo = 0
        var hi = chunks.count - 1
        while lo <= hi {
            let mid: Int = (lo + hi) / 2
            let range: Range<Int> = chunks[mid].lines
            if range.contains(line) { return mid }
            if line < range.lowerBound { hi = mid - 1 } else { lo = mid + 1 }
        }
        return nil
    }

    // MARK: where each word falls inside a clip

    /// The words as the screen shows them: split on spaces, empties dropped.
    static func tokens(_ line: String) -> [String] {
        line.split(separator: " ").map(String.init)
    }

    /// How long a word takes to say, in "characters". Letters and digits
    /// count; a floor keeps "a" and "of" from flashing past; Arabic writes no
    /// short vowels, so its letters are worth more.
    static func weight(_ word: String) -> Double {
        var letters = 0
        var arabic = false
        for scalar in word.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) { letters += 1 }
            if (0x0600...0x06FF).contains(scalar.value) { arabic = true }
        }
        let base: Double = Double(max(2, letters)) * (arabic ? 1.4 : 1.0)
        // the move from one word to the next takes a moment too
        return base + 1.0
    }

    /// The silence a speaker leaves after a word, in the same units.
    static func pause(after word: String, endsLine: Bool) -> Double {
        guard let last = word.last else { return 0 }
        if ".!?".contains(last) { return 6 }
        if ",;:".contains(last) { return 3 }
        if last == "\u{2014}" || last == "-" { return 2 }
        return endsLine ? 2 : 0
    }

    /// The clip's words laid over its real duration.
    static func wordTimes(lines: [String], range: Range<Int>, duration: Double) -> [ClipWord] {
        var spots: [(line: Int, word: Int, weight: Double, pause: Double)] = []
        for li in range where li >= 0 && li < lines.count {
            let words: [String] = tokens(lines[li])
            for (wi, word) in words.enumerated() {
                let endsLine: Bool = wi == words.count - 1
                spots.append((li, wi, weight(word), pause(after: word, endsLine: endsLine)))
            }
        }
        guard !spots.isEmpty, duration > 0 else { return [] }
        var total = 0.0
        for (i, spot) in spots.enumerated() {
            // the last word's pause is the clip's own end, not a gap
            total += spot.weight + (i == spots.count - 1 ? 0 : spot.pause)
        }
        let scale: Double = duration / max(total, 0.001)
        var out: [ClipWord] = []
        out.reserveCapacity(spots.count)
        var at = 0.0
        for (i, spot) in spots.enumerated() {
            let last: Bool = i == spots.count - 1
            let end: Double = last ? duration : at + spot.weight * scale
            out.append(ClipWord(line: spot.line, word: spot.word, start: at, end: end))
            at = end + spot.pause * scale
        }
        return out
    }

    /// The word being said at `t`: the last one that has started, so the
    /// highlight holds through a pause instead of blinking off.
    static func spot(at t: Double, in words: [ClipWord]) -> Int? {
        guard !words.isEmpty else { return nil }
        if t < words[0].start { return 0 }
        var lo = 0
        var hi = words.count - 1
        while lo < hi {
            let mid: Int = (lo + hi + 1) / 2
            if words[mid].start <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Where in its clip a line begins, for jumping to it.
    static func start(ofLine line: Int, in words: [ClipWord]) -> Double {
        words.first { $0.line >= line }?.start ?? 0
    }

    // MARK: fetching ahead

    /// The clips to fetch now: the one playing and the next `ahead`, less any
    /// already fetched or on their way.
    static func prefetch(current: Int, count: Int, ahead: Int, have: Set<Int>) -> [Int] {
        guard count > 0, current < count else { return [] }
        let from: Int = max(0, current)
        let to: Int = min(count - 1, from + ahead)
        return (from...to).filter { !have.contains($0) }
    }

    // MARK: the phone's own voice

    /// A playback speed (0.75x, 1x, 1.5x...) as AVSpeechUtterance's rate,
    /// where 0.5 is the phone's normal pace and the scale is far from linear:
    /// doubling the number is much more than twice as fast.
    static func phoneRate(_ speed: Double) -> Float {
        let rate: Double = 0.5 + (speed - 1) * 0.18
        return Float(min(0.68, max(0.32, rate)))
    }

    /// The word a synthesiser range starts in. `offset` counts UTF-16 units,
    /// as NSRange does; words are split exactly as `tokens` splits them.
    static func wordIndex(atUTF16 offset: Int, in text: String) -> Int {
        var index = -1
        var position = 0
        var previousWasSpace = true
        for unit in text.utf16 {
            if position > offset { break }
            let space: Bool = unit == 0x20
            if !space && previousWasSpace { index += 1 }
            previousWasSpace = space
            position += 1
        }
        return max(0, index)
    }
}
