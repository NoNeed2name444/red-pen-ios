// Red Pen · Fix this word
//
// The student taps a word that came out wrong, types what it should say, and
// three things happen at once:
//
//   1. that word is fixed;
//   2. every OTHER word in the transcript that sounds the same is fixed too,
//      reported and undoable - the recogniser makes the same mistake in the
//      same lecture, so fixing one occurrence and leaving eleven is busywork;
//   3. the pronunciation is remembered, so the next lecture never shows it.
//
// Step 2 is the one that needs care. The match is on SOUND, not on letters, so
// a correction to ميكو كوتينيوس also catches ميكو كوتينياس - and that reach is
// exactly why nothing here happens silently. Every change is listed, the count
// is shown, and one undo puts all of it back.
//
// What is never done: guessing. A correction only ever replaces spans that
// sound like the one the student actually pointed at.
import Foundation

public struct CorrectionChange: Equatable, Sendable {
    public var segment: Int
    public var firstWord: Int
    public var lastWord: Int
    public var was: String
    public var now: String
}

public struct CorrectionOutcome: Sendable {
    /// the span the student pointed at
    public var here: CorrectionChange?
    /// every other span that sounded the same
    public var elsewhere: [CorrectionChange] = []
    /// whether the pronunciation was added to the store
    public var learned = false
    /// a span that sounded the same but was ALREADY spelled the new way, so it
    /// needed no change - counted so the report does not overstate itself
    public var alreadyRight = 0

    public var changed: Int { (here == nil ? 0 : 1) + elsewhere.count }

    /// What to put on screen. Deliberately plain: the student is mid-lecture.
    public func summary() -> String {
        guard here != nil else { return "Nothing to fix" }
        if elsewhere.isEmpty { return learned ? "Fixed, and remembered" : "Fixed" }
        let others = elsewhere.count == 1 ? "1 more like it" : "\(elsewhere.count) more like it"
        return learned ? "Fixed \(others), and remembered" : "Fixed \(others)"
    }
}

public enum TranscriptCorrections {

    /// Tokens of one phrase, so a replacement can be spliced without disturbing
    /// the punctuation and spacing around it.
    static func tokens(_ text: String) -> [String] {
        text.split(separator: " ").map(String.init)
    }

    /// The lecturer's definite article stays where he put it.
    static func withArticle(of head: String, _ spelling: String) -> String {
        let bare = SoundKey.stripArticle(head)
        return (bare != head && head.count > 3) ? "الـ " + spelling : spelling
    }

    /// The student fixed one word (or a short run of words).
    ///
    /// `segments` is edited in place. The store learns the pronunciation with
    /// `.correction` evidence, which outranks anything the recogniser or the
    /// repair could have contributed - a person's own spelling is the last word.
    @discardableResult
    public static func fix(segment: Int, words range: ClosedRange<Int>, to spelling: String,
                           in segments: inout [String],
                           store: inout PronunciationStore,
                           spreadToRest: Bool = true) -> CorrectionOutcome {
        var outcome = CorrectionOutcome()
        let wanted = spelling.trimmingCharacters(in: .whitespacesAndNewlines)
        guard segments.indices.contains(segment), !wanted.isEmpty else { return outcome }

        let parts = tokens(segments[segment])
        guard range.lowerBound >= 0, range.upperBound < parts.count else { return outcome }
        let span = Array(parts[range])
        let key = SoundKey.of(span: span)
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return outcome }

        let was = span.joined(separator: " ")
        let width = span.count
        // Where the student's own span sits. Replacing an EARLIER span in the
        // same phrase shortens it, so this has to move with it - otherwise the
        // splice at the end lands a word or two to the right of the word that
        // was tapped, which is the kind of bug nobody reports because it only
        // happens when the same mistake appears twice in one line.
        var targetStart = range.lowerBound

        // Everywhere else first, so the word just fixed is never mistaken for
        // one of the others it taught.
        if spreadToRest {
            for i in segments.indices {
                var parts = tokens(segments[i])
                var j = 0
                var touched = false
                while j + width <= parts.count {
                    if i == segment && j == targetStart { j += width; continue }
                    let here = Array(parts[j..<(j + width)])
                    guard SoundKey.of(span: here) == key else { j += 1; continue }
                    if here.joined(separator: " ").caseInsensitiveCompare(wanted) == .orderedSame {
                        outcome.alreadyRight += 1
                        j += width
                        continue
                    }
                    parts.replaceSubrange(j..<(j + width), with: [withArticle(of: parts[j], wanted)])
                    outcome.elsewhere.append(CorrectionChange(segment: i, firstWord: j,
                                                              lastWord: j + width - 1,
                                                              was: here.joined(separator: " "),
                                                              now: wanted))
                    if i == segment && j < targetStart { targetStart -= (width - 1) }
                    touched = true
                    j += 1
                }
                if touched { segments[i] = parts.joined(separator: " ") }
            }
        }

        var finalParts = tokens(segments[segment])
        let last = targetStart + width - 1
        if targetStart >= 0, last < finalParts.count {
            finalParts.replaceSubrange(targetStart...last,
                                       with: [withArticle(of: finalParts[targetStart], wanted)])
            segments[segment] = finalParts.joined(separator: " ")
            outcome.here = CorrectionChange(segment: segment, firstWord: targetStart,
                                            lastWord: last, was: was, now: wanted)
        }

        outcome.learned = OnDeviceLearning.fromCorrection(heard: span, wrote: wanted, into: &store)
        return outcome
    }

    /// Put back everything one correction changed. The snapshot is taken by the
    /// caller before `fix`, because restoring token positions after the spans
    /// have already shifted is the kind of arithmetic that goes wrong quietly.
    public static func undo(_ snapshot: [String], into segments: inout [String],
                            touching outcome: CorrectionOutcome) {
        var indexes = Set(outcome.elsewhere.map { $0.segment })
        if let here = outcome.here { indexes.insert(here.segment) }
        for i in indexes where snapshot.indices.contains(i) && segments.indices.contains(i) {
            segments[i] = snapshot[i]
        }
    }

    /// Apply everything already learned to a transcript that has just arrived.
    /// This is the "fix it later" half: a lecture recorded next week never
    /// shows a mistake the student has already corrected once.
    @discardableResult
    public static func applyLearned(_ store: PronunciationStore,
                                    to segments: inout [String]) -> Int {
        var fixed = 0
        for i in segments.indices {
            let (text, hits) = store.apply(to: segments[i])
            if !hits.isEmpty {
                segments[i] = text
                fixed += hits.count
            }
        }
        return fixed
    }
}
