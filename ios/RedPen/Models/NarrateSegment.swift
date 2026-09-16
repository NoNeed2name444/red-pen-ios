import Foundation

/// One phrase of a narrated transcript. `lang` picks the reading-pace used
/// when no recording is attached (see `NarrateScheduler`), matching the web
/// app's English/Arabic split in `narrateSegmentMs()`.
struct NarrateSegment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var lang: String = "en" // "en" or "ar"
}

/// Reading-pace timing and playback state, ported from the web app's
/// no-recording fallback (`narrateSegmentMs()` / `playNarrate()` /
/// `pauseNarrate()` / `jumpToNarrateSegment()` / `restartNarrate()`).
/// Recording playback synced to a real audio file is a larger feature
/// (on-device transcription, Whisper, alignment) left for later — this
/// ports the always-available typed-transcript path, which is what most
/// Narrate sets are read with anyway.
enum NarrateScheduler {
    /// Milliseconds to hold on one segment before advancing, at 1x speed —
    /// matches `narrateSegmentMs()`'s words-per-minute estimate.
    static func segmentMs(_ segment: NarrateSegment, speed: Double) -> Double {
        let words = max(1, segment.text.split { $0.isWhitespace }.count)
        let wpm: Double = segment.lang == "ar" ? 110 : 150
        let ms = (Double(words) / wpm) * 60000
        return max(900, ms) / max(0.1, speed)
    }
}
