// Red Pen · what the transcription learning must do.
//
// The sound keys are checked against the values pipeline/consensus.py produces
// for the same tokens. The two implementations have to agree exactly: a table
// learned on the phone is read by the committee and one learned by the
// committee is read by the phone, so a single disagreement makes both wrong in
// a way nobody would notice until a transcript came back strange.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: the sound key

check("an Arabic and an English spelling of one sound match",
      SoundKey.of("\u{631}\u{64a}\u{641}\u{631}\u{633}\u{628}\u{644}") == SoundKey.of("reversible"),
      SoundKey.of("\u{631}\u{64a}\u{641}\u{631}\u{633}\u{628}\u{644}") + " vs " + SoundKey.of("reversible"))
check("the definite article does not change the sound",
      SoundKey.of("\u{627}\u{644}\u{640}\u{645}\u{627}\u{644}\u{627}\u{631}") == SoundKey.of("\u{645}\u{627}\u{644}\u{627}\u{631}"),
      SoundKey.of("\u{627}\u{644}\u{640}\u{645}\u{627}\u{644}\u{627}\u{631}"))
check("a ta-marbuta and a ha are the same word",
      SoundKey.of("\u{645}\u{645}\u{64a}\u{632}\u{647}") == SoundKey.of("\u{645}\u{645}\u{64a}\u{632}\u{629}"))
check("different words stay different",
      SoundKey.of("\u{641}\u{647}\u{645}") != SoundKey.of("\u{639}\u{644}\u{645}"))

// A known, deliberate collision, asserted so nobody "fixes" it by accident.
// ق and ك are both k in this scheme, so قلب (heart) and كلب (dog) are one
// sound. Python says "klb" for both; if Swift ever disagrees, the tables the
// two produce stop being interchangeable.
check("qaf and kaf collide, exactly as they do in Python",
      SoundKey.of("\u{642}\u{644}\u{628}") == "klb" && SoundKey.of("\u{643}\u{644}\u{628}") == "klb",
      SoundKey.of("\u{642}\u{644}\u{628}") + " / " + SoundKey.of("\u{643}\u{644}\u{628}"))
check("a split word and a joined one meet once the seam is closed",
      SoundKey.collapsed(SoundKey.of(span: ["\u{645}\u{64a}\u{643}\u{648}", "\u{643}\u{648}\u{62a}\u{64a}\u{646}\u{64a}\u{648}\u{633}"]))
      == SoundKey.collapsed(SoundKey.of("mucocutaneous")),
      SoundKey.collapsed(SoundKey.of(span: ["\u{645}\u{64a}\u{643}\u{648}", "\u{643}\u{648}\u{62a}\u{64a}\u{646}\u{64a}\u{648}\u{633}"]))
      + " vs " + SoundKey.collapsed(SoundKey.of("mucocutaneous")))

// MARK: the store

var store = PronunciationStore()
check("a correction is trusted at once",
      store.add(sound: SoundKey.of("\u{627}\u{643}\u{64a}\u{648}\u{62a}"), spelling: "acute",
                heardAs: "\u{627}\u{643}\u{64a}\u{648}\u{62a}", evidence: .correction))
check("and is then applied",
      store.apply(to: "\u{62f}\u{647} \u{627}\u{643}\u{64a}\u{648}\u{62a} \u{62c}\u{62f}\u{627}").text.contains("acute"),
      store.apply(to: "\u{62f}\u{647} \u{627}\u{643}\u{64a}\u{648}\u{62a} \u{62c}\u{62f}\u{627}").text)

// one sighting of repetition is not enough to rewrite anything
var weak = PronunciationStore()
weak.add(sound: "tst", spelling: "test", heardAs: "\u{62a}\u{633}\u{62a}", evidence: .repetition)
check("one repetition is not yet trusted",
      weak.entries["tst"]?.isTrusted == false, "\(weak.entries["tst"]?.counts ?? [:])")
for _ in 0..<2 {
    weak.add(sound: "tst", spelling: "test", heardAs: "\u{62a}\u{633}\u{62a}", evidence: .repetition)
}
check("three repetitions are", weak.entries["tst"]?.isTrusted == true)

// a guess must never displace a person's own spelling
var fought = PronunciationStore()
fought.add(sound: "rsk", spelling: "risk", heardAs: "\u{631}\u{633}\u{643}", evidence: .correction)
fought.add(sound: "rsk", spelling: "rosacea", heardAs: "\u{631}\u{633}\u{643}", evidence: .repetition)
check("a weaker guess cannot overwrite a correction",
      fought.spelling(for: ["\u{631}\u{633}\u{643}"]) == "risk",
      fought.spelling(for: ["\u{631}\u{633}\u{643}"]) ?? "nil")

// the table is the same one the pipeline reads and writes
let round = PronunciationStore.fromTSV(store.tsv())
check("the table survives a round trip through TSV",
      round.spelling(for: ["\u{627}\u{643}\u{64a}\u{648}\u{62a}"]) == "acute",
      round.tsv())

// MARK: fixing a word

var segments = ["\u{62f}\u{647} \u{627}\u{643}\u{64a}\u{648}\u{62a} \u{62c}\u{62f}\u{627}",
                "\u{648}\u{627}\u{644}\u{640}\u{627}\u{643}\u{64a}\u{648}\u{62a} \u{62a}\u{627}\u{646}\u{64a}"]
let snapshot = segments
var learning = PronunciationStore()
let outcome = TranscriptCorrections.fix(segment: 0, words: 1...1, to: "acute",
                                        in: &segments, store: &learning)
check("the word the student tapped is fixed",
      segments[0].contains("acute"), segments[0])
check("the same mistake elsewhere is fixed too",
      segments[1].contains("acute"), segments[1])
check("the lecturer's article is kept",
      segments[1].contains("\u{627}\u{644}\u{640} acute"), segments[1])
check("the spread is reported rather than silent",
      outcome.elsewhere.count == 1 && outcome.summary().contains("1 more like it"),
      outcome.summary())
check("and it was remembered", outcome.learned)

TranscriptCorrections.undo(snapshot, into: &segments, touching: outcome)
check("one undo puts all of it back", segments == snapshot, segments.joined(separator: " | "))

// the same mistake twice in ONE line must not shift the splice off the word
// that was actually tapped
var twice = ["\u{627}\u{643}\u{64a}\u{648}\u{62a} \u{62f}\u{647} \u{627}\u{643}\u{64a}\u{648}\u{62a}"]
var store2 = PronunciationStore()
let twiceOut = TranscriptCorrections.fix(segment: 0, words: 2...2, to: "acute",
                                         in: &twice, store: &store2)
check("both occurrences end up fixed, none skipped",
      twice[0].split(separator: " ").filter { $0 == "acute" }.count == 2, twice[0])
check("the tapped word is the one reported as here",
      twiceOut.here != nil, "\(String(describing: twiceOut.here))")

// MARK: the word clock

let words = WordTiming.layout(texts: ["one two three", "four five"], ends: [3.0, 5.0])
check("every word gets a slot", words.count == 5, "\(words.count)")
check("the words run in order",
      zip(words, words.dropFirst()).allSatisfy { $0.end <= $1.start + 0.0001 })
check("an estimate says it is an estimate",
      words.allSatisfy { $0.source == .estimated })
check("the phrase ends where it was told to",
      abs((words.last?.end ?? 0) - 5.0) < 0.0001, "\(words.last?.end ?? 0)")
check("the word at a moment is found",
      WordTiming.word(at: 0.1, in: words)?.text == "one",
      WordTiming.word(at: 0.1, in: words)?.text ?? "nil")

let measured = WordTiming.words(in: "one two", segment: 0, from: 0, to: 2,
                                measured: [("one", 0.0, 0.8), ("two", 0.8, 1.9)])
check("a measured time is used as given",
      measured.allSatisfy { $0.source == .measured } && measured[1].end == 1.9)

let partial = WordTiming.words(in: "one two three", segment: 0, from: 0, to: 3,
                               measured: [("one", 0.0, 0.8)])
check("a partly timed phrase keeps what was measured and estimates the rest",
      partial.count == 3 && partial[0].source == .measured
      && partial[1].source == .estimated, "\(partial.map(\.source))")

check("an Arabic word is not rushed",
      WordTiming.weight("\u{645}\u{643}\u{62a}\u{628}") > WordTiming.weight("desk"),
      "\(WordTiming.weight("\u{645}\u{643}\u{62a}\u{628}")) vs \(WordTiming.weight("desk"))")

print(failures.isEmpty ? "\nALL LEARNING TESTS PASS"
                       : "\n\(failures.count) LEARNING TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
