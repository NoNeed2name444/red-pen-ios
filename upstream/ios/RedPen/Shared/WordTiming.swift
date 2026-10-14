// Red Pen · where each WORD sits in the recording
//
// The transcript arrives as phrases: a line of text and the second it ended.
// Highlighting a whole phrase at a time is what the web build does, and it is
// the wrong grain for following a lecture - by the time a line lights up the
// lecturer is already inside it, and a student reading along has no idea which
// word is being said.
//
// Two ways to get word times, and the difference matters enough to keep:
//
//   .measured   the recogniser gave real per-word times (Gemini 3.5 Transcribe
//               returns them). Used exactly as given.
//   .estimated  only the phrase's end time is known, so the phrase's span is
//               shared out across its words by how long each one takes to say.
//
// An estimate is never presented as a measurement. The player dims the
// highlight when timing is estimated, for the same reason the transcript marks
// a repaired line: the reader should be able to tell what is known from what is
// inferred.
import Foundation

public enum TimingSource: String, Codable, Sendable {
    case measured
    case estimated
}

public struct TranscriptWord: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(segment).\(index)" }
    public var segment: Int
    public var index: Int
    public var text: String
    public var start: Double
    public var end: Double
    public var source: TimingSource

    public func contains(_ t: Double) -> Bool { t >= start && t < end }
    public var duration: Double { max(0, end - start) }
}

public enum WordTiming {

    /// A word's share of a phrase. Not every word takes the same time to say,
    /// and splitting the phrase equally makes long words lag and short ones
    /// race. Length is the cheap proxy everyone uses; the floor stops "a" and
    /// "في" from flashing past unreadably.
    static let minimumWordSeconds = 0.12

    static func weight(_ word: String) -> Double {
        // Arabic script writes short vowels as nothing, so a four-letter Arabic
        // word is spoken about as long as a six-letter English one. Counting
        // letters alone would make every Arabic word look hurried.
        let letters = word.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let arabic = word.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
        return max(1.0, Double(letters) * (arabic ? 1.4 : 1.0))
    }

    /// Split one phrase into words carrying a start and an end.
    ///
    /// `measured` is the recogniser's own word times when it had them; any word
    /// it did not time falls back to its estimated share, so a partial answer
    /// is still worth having.
    public static func words(in text: String, segment: Int,
                             from start: Double, to end: Double,
                             measured: [(text: String, start: Double, end: Double)]? = nil)
    -> [TranscriptWord] {
        let tokens = text.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }

        if let measured, !measured.isEmpty {
            var out: [TranscriptWord] = []
            for (i, token) in tokens.enumerated() where i < measured.count {
                let m = measured[i]
                out.append(TranscriptWord(segment: segment, index: i, text: token,
                                          start: m.start, end: max(m.start, m.end),
                                          source: .measured))
            }
            if out.count == tokens.count { return out }
            // the recogniser timed only part of the phrase: estimate the rest
            // from where its last measurement stopped
            let restStart = out.last?.end ?? start
            let rest = Array(tokens[out.count...])
            return out + share(rest, segment: segment, firstIndex: out.count,
                               from: restStart, to: max(restStart, end))
        }
        return share(tokens, segment: segment, firstIndex: 0, from: start, to: end)
    }

    private static func share(_ tokens: [String], segment: Int, firstIndex: Int,
                              from start: Double, to end: Double) -> [TranscriptWord] {
        guard !tokens.isEmpty else { return [] }
        let span = max(end - start, Double(tokens.count) * minimumWordSeconds)
        let weights = tokens.map(weight)
        let total = weights.reduce(0, +)
        var out: [TranscriptWord] = []
        var at = start
        for (i, token) in tokens.enumerated() {
            let slice = max(minimumWordSeconds, span * (weights[i] / total))
            let stop = (i == tokens.count - 1) ? max(end, at + minimumWordSeconds) : at + slice
            out.append(TranscriptWord(segment: segment, index: firstIndex + i, text: token,
                                      start: at, end: stop, source: .estimated))
            at = stop
        }
        return out
    }

    /// Lay out a whole transcript. `ends[i]` is the second phrase i finished;
    /// a phrase starts where the previous one ended.
    public static func layout(texts: [String], ends: [Double],
                              measured: [[(text: String, start: Double, end: Double)]]? = nil)
    -> [TranscriptWord] {
        var out: [TranscriptWord] = []
        var previousEnd = 0.0
        for (i, text) in texts.enumerated() {
            let end = i < ends.count ? ends[i] : previousEnd
            let start = min(previousEnd, end)
            out += words(in: text, segment: i, from: start, to: max(start, end),
                         measured: measured.flatMap { i < $0.count ? $0[i] : nil })
            previousEnd = max(previousEnd, end)
        }
        return out
    }

    /// The word being spoken at `t`. Binary search, because the player asks
    /// this on every frame of the audio clock.
    public static func word(at t: Double, in words: [TranscriptWord]) -> TranscriptWord? {
        guard !words.isEmpty else { return nil }
        var lo = 0, hi = words.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if words[mid].contains(t) { return words[mid] }
            if t < words[mid].start { hi = mid - 1 } else { lo = mid + 1 }
        }
        // between two words - the player should stay on the one just spoken
        // rather than blink off, so the last word that started is returned.
        // The search has already found it: every word at or below `hi` began
        // at or before `t`. (A linear scan here cost a pass over the whole
        // lecture on every tick that fell in a pause, which is most of them.)
        return hi >= 0 ? words[hi] : nil
    }
}
