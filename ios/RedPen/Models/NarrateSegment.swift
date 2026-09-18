import Foundation

/// One phrase of a narrated transcript.
///
/// `lang` picks the reading pace used when no recording is attached (see
/// `NarrateScheduler`), matching the web app's English/Arabic split.
///
/// The timing fields are filled only when the transcript came from a real
/// recording (see LectureTranscriber). They are optional rather than defaulted
/// to zero because "this line starts at 0.0" and "nobody knows when this line
/// starts" are different facts, and the player has to behave differently for
/// each: follow the audio, or fall back to a reading pace. Being optional also
/// means every transcript saved before this existed still decodes.
struct NarrateSegment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var lang: String = "en" // "en" or "ar"

    /// When this line begins and ends in the recording, in seconds.
    var start: Double?
    var end: Double?
    /// Where each word sits, when the recogniser reported it. A line with no
    /// word times still plays; the highlight just moves a line at a time.
    var words: [SpokenTiming]?

    var isTimed: Bool { start != nil && end != nil }
}

/// One word's place in the recording, as the recogniser reported it.
struct SpokenTiming: Codable, Hashable {
    var text: String
    var start: Double
    var end: Double
}

/// Reading-pace timing, ported from the web app's no-recording fallback.
///
/// This is now the fallback in the true sense: it is what runs when there is no
/// recording to follow. With audio attached the player takes its clock from the
/// audio instead, because an estimate that drifts is worse than useless once
/// there is a real answer available.
enum NarrateScheduler {
    /// Milliseconds to hold on one segment before advancing, at 1x speed -
    /// matches `narrateSegmentMs()`'s words-per-minute estimate.
    static func segmentMs(_ segment: NarrateSegment, speed: Double) -> Double {
        // A timed line knows exactly how long it lasted, so use that rather
        // than guessing from the word count.
        if let start = segment.start, let end = segment.end, end > start {
            return max(300, (end - start) * 1000) / max(0.1, speed)
        }
        let words = max(1, segment.text.split { $0.isWhitespace }.count)
        let wpm: Double = segment.lang == "ar" ? 110 : 150
        let ms = (Double(words) / wpm) * 60000
        return max(900, ms) / max(0.1, speed)
    }

    /// The transcript a recording produced, as segments the player can hold.
    static func segments(from lines: [LectureTranscriber.Line], lang: String) -> [NarrateSegment] {
        lines.map { line in
            NarrateSegment(text: line.text, lang: lang,
                           start: line.start, end: line.end,
                           words: line.words.map { SpokenTiming(text: $0.text, start: $0.start, end: $0.end) })
        }
    }

    /// The word timings in the shape WordTiming.layout wants.
    static func measured(_ segments: [NarrateSegment]) -> [[(text: String, start: Double, end: Double)]]? {
        guard segments.contains(where: { ($0.words?.isEmpty == false) }) else { return nil }
        return segments.map { ($0.words ?? []).map { ($0.text, $0.start, $0.end) } }
    }
}
