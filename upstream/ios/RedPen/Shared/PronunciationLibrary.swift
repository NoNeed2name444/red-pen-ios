import Foundation
import Combine

/// What the phone has learned about this lecturer, kept between lectures.
///
/// Held apart from Store on purpose. The library is the student's content -
/// sets, folders, progress - and this is a model of one person's speech: a
/// different lifetime, a different file, and one that must survive a set being
/// deleted. A pronunciation learned from last week's lecture is still true
/// after that lecture is thrown away.
///
/// The file is the same tab-separated table the pipeline reads and writes, not
/// a private encoding, so a table learned on the phone can be handed to a
/// committee run and a table learned by the committee can be dropped straight
/// in here.
@MainActor
final class PronunciationLibrary: ObservableObject {
    @Published private(set) var table = PronunciationStore()

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = dir.appendingPathComponent("redpen-pronunciations.tsv")
        }
        load()
    }

    var count: Int { table.entries.count }

    func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        table = PronunciationStore.fromTSV(text)
    }

    func save() {
        try? table.tsv().write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// The student fixed a word. Everything that sounds the same is fixed with
    /// it, and the pronunciation is remembered - see TranscriptCorrections.
    @discardableResult
    func fix(segment: Int, words range: ClosedRange<Int>, to spelling: String,
             in texts: inout [String]) -> CorrectionOutcome {
        var working = table
        let outcome = TranscriptCorrections.fix(segment: segment, words: range, to: spelling,
                                               in: &texts, store: &working)
        table = working
        save()
        return outcome
    }

    /// Undo restores the text, and must also forget what that correction
    /// taught - otherwise the next transcript quietly reapplies the very
    /// spelling the student just rejected.
    func undo(_ snapshot: [String], into texts: inout [String],
              touching outcome: CorrectionOutcome) {
        TranscriptCorrections.undo(snapshot, into: &texts, touching: outcome)
        if let here = outcome.here, outcome.learned {
            var working = table
            working.forget(sound: SoundKey.of(span: here.was.split(separator: " ").map(String.init)))
            table = working
            save()
        }
    }

    /// Apply everything already learned to a transcript that has just arrived:
    /// a lecture recorded next week never shows a mistake corrected once.
    @discardableResult
    func applyLearned(to texts: inout [String]) -> Int {
        TranscriptCorrections.applyLearned(table, to: &texts)
    }

    /// Terms read off the lecturer's own slides, which is the strongest
    /// evidence there is: his spelling of the word he is about to say.
    @discardableResult
    func learnFromSlides(transcript: String, slideText: [String]) -> Int {
        var working = table
        let learned = OnDeviceLearning.fromSlides(transcript: transcript, slideText: slideText,
                                                  into: &working)
        table = working
        if learned > 0 { save() }
        return learned
    }
}
