// Where a recording becomes readable lines, and whether the highlight lands on
// the word actually being spoken.
//
// The recogniser itself is not tested here - it is Apple's, it needs a device,
// and a test that needs a microphone is a test nobody runs. What is tested is
// everything Red Pen decides: where a line ends, what happens to the word times
// on the way through, and what the player asks for on every frame.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

typealias Spoken = LectureTranscriber.SpokenWord

func say(_ text: String, _ start: Double, _ dur: Double = 0.3) -> Spoken {
    Spoken(text: text, start: start, duration: dur)
}

// A lecturer speaking, pausing, then speaking again.
let spoken = [
    say("the", 0.0), say("malar", 0.35), say("rash", 0.7),
    say("spares", 1.05), say("the", 1.4), say("nasolabial", 1.75), say("folds", 2.2),
    // a breath
    say("that", 3.2), say("is", 3.55), say("how", 3.9),
    say("you", 4.25), say("tell", 4.6), say("it", 4.95), say("from", 5.3),
    say("rosacea", 5.65),
]
let lines = LectureTranscriber.lines(from: spoken)

check("a pause ends a line", lines.count == 2, "\(lines.count) lines")
check("the first line is what was said before the pause",
      lines.first?.text == "the malar rash spares the nasolabial folds",
      lines.first?.text ?? "nil")
check("a line starts when its first word does",
      lines.first?.start == 0.0 && lines.last?.start == 3.2,
      "\(lines.first?.start ?? -1) / \(lines.last?.start ?? -1)")
check("a line ends when its last word does",
      abs((lines.first?.end ?? 0) - 2.5) < 0.0001, "\(lines.first?.end ?? 0)")
check("no word is lost at a break",
      lines.reduce(0) { $0 + $1.words.count } == spoken.count,
      "\(lines.reduce(0) { $0 + $1.words.count }) of \(spoken.count)")

// An unbroken stretch still has to end somewhere, or it becomes a paragraph.
let gabble = (0..<40).map { say("word", Double($0) * 0.3) }
let chopped = LectureTranscriber.lines(from: gabble)
check("speech with no pause is still broken into lines", chopped.count >= 3, "\(chopped.count)")
check("and no line runs past the limit",
      chopped.allSatisfy { $0.words.count <= LectureTranscriber.maxWordsPerLine },
      "\(chopped.map(\.words.count))")

check("silence transcribes to nothing rather than an empty line",
      LectureTranscriber.lines(from: []).isEmpty)

// MARK: the word clock the player runs on

let timings = LectureTranscriber.timings(for: lines)
let words = WordTiming.layout(texts: lines.map(\.text),
                              ends: lines.map(\.end),
                              measured: timings)

check("every spoken word reaches the player", words.count == spoken.count, "\(words.count)")
check("the recogniser's own times are used, not estimates",
      words.allSatisfy { $0.source == .measured }, "\(Set(words.map(\.source)))")

// the point of the whole exercise: the right word at the right moment
check("the highlight is on the word being said",
      WordTiming.word(at: 1.9, in: words)?.text == "nasolabial",
      WordTiming.word(at: 1.9, in: words)?.text ?? "nil")
check("and on the last word of the lecture at the end",
      WordTiming.word(at: 5.8, in: words)?.text == "rosacea",
      WordTiming.word(at: 5.8, in: words)?.text ?? "nil")
// during the breath there is no word being spoken; the player should hold the
// last one rather than blink the highlight off
check("a pause holds the last word rather than going blank",
      WordTiming.word(at: 2.9, in: words)?.text == "folds",
      WordTiming.word(at: 2.9, in: words)?.text ?? "nil")
check("before the lecture starts nothing is highlighted",
      WordTiming.word(at: -1, in: words) == nil)

// A partly-timed phrase must not throw the rest of the line away.
let partly = WordTiming.words(in: "one two three", segment: 0, from: 0, to: 3,
                              measured: [("one", 0.0, 0.8)])
check("an untimed remainder is estimated, not dropped",
      partly.count == 3 && partly[0].source == .measured && partly[2].source == .estimated,
      "\(partly.map(\.source))")

// MARK: what a lecture transcript then goes through

// The learned table is applied to a fresh transcript, which is what makes a
// correction made last week show up already fixed this week.
var table = PronunciationStore()
table.add(sound: SoundKey.of("\u{645}\u{64a}\u{643}\u{648}\u{643}\u{648}\u{62a}\u{64a}\u{646}\u{64a}\u{648}\u{633}"), spelling: "mucocutaneous",
          heardAs: "\u{645}\u{64a}\u{643}\u{648}\u{643}\u{648}\u{62a}\u{64a}\u{646}\u{64a}\u{648}\u{633}", evidence: .correction)
var fresh = ["\u{62f}\u{647} \u{645}\u{64a}\u{643}\u{648}\u{643}\u{648}\u{62a}\u{64a}\u{646}\u{64a}\u{648}\u{633} \u{62a}\u{627}\u{646}\u{64a}"]
let fixed = TranscriptCorrections.applyLearned(table, to: &fresh)
check("last week's correction is already applied to this week's lecture",
      fixed == 1 && fresh[0].contains("mucocutaneous"), fresh[0])

print(failures.isEmpty ? "\nALL TRANSCRIBER TESTS PASS"
                       : "\n\(failures.count) TRANSCRIBER TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
