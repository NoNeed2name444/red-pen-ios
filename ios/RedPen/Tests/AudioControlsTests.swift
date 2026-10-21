// Red Pen · the lecture player's controls: the speeds on offer and the one
// remembered, the sleep timer's countdown and fade, and a lecture's sections.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: speed

check("quarter steps from 0.75x to 2.5x",
      AudioRate.steps == [0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5], "\(AudioRate.steps)")
check("a speed off the menu snaps to the nearest step", AudioRate.snapped(1.3) == 1.25)
check("too fast is the fastest", AudioRate.snapped(9) == 2.5)
check("too slow is the slowest", AudioRate.snapped(0.1) == 0.75)
check("not a number is Normal", AudioRate.snapped(.nan) == 1 && AudioRate.snapped(-2) == 1)
check("faster goes up a step", AudioRate.faster(than: 1.5) == 1.75)
check("faster at the top stays there", AudioRate.faster(than: 2.5) == 2.5)
check("slower goes down a step", AudioRate.slower(than: 1) == 0.75)
check("slower at the bottom stays there", AudioRate.slower(than: 0.75) == 0.75)
check("the chip reads 1.25\u{00d7}", AudioRate.label(1.25) == "1.25\u{00d7}", AudioRate.label(1.25))
check("1x is called Normal", AudioRate.name(1) == "Normal")
check("2x is called 2\u{00d7}", AudioRate.name(2) == "2\u{00d7}", AudioRate.name(2))

let suite = "audio-controls-tests-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
let first = UUID()
let second = UUID()
let third = UUID()
check("a lecture never played opens at Normal",
      AudioRate.remembered(for: first, in: defaults) == 1)
AudioRate.remember(1.75, for: first, in: defaults)
check("a lecture opens at the speed it was last heard at",
      AudioRate.remembered(for: first, in: defaults) == 1.75)
check("a new lecture opens at the last speed chosen anywhere",
      AudioRate.remembered(for: second, in: defaults) == 1.75)
AudioRate.remember(1.25, for: third, in: defaults)
check("each lecture keeps its own",
      AudioRate.remembered(for: first, in: defaults) == 1.75
        && AudioRate.remembered(for: third, in: defaults) == 1.25)
check("and the default follows the latest choice",
      AudioRate.remembered(for: second, in: defaults) == 1.25)
AudioRate.remember(7, for: first, in: defaults)
check("a speed off the menu is kept as a step on it",
      AudioRate.remembered(for: first, in: defaults) == 2.5)
defaults.removePersistentDomain(forName: suite)

// MARK: the sleep timer

check("the menu has the six times and the end of the section",
      SleepChoice.all.count == 7 && SleepChoice.all.last == .endOfSection)

var timer = SleepCountdown(choice: .minutes(15))!
check("fifteen minutes is 900 seconds", timer.remaining == 900)
check("full volume to begin with", timer.volume == 1)
check("the chip counts down in minutes and seconds", timer.label == "15:00", timer.label)
timer.advance(listened: 1)
check("a second heard is a second off", timer.remaining == 899 && timer.label == "14:59", timer.label)
timer.advance(listened: 600)
check("a long gap - the app was not running - takes off no more than a few seconds",
      timer.remaining == 899 - SleepCountdown.maxStep, "\(timer.remaining)")
timer.advance(listened: -3)
timer.advance(listened: .nan)
check("time never runs backwards", timer.remaining == 899 - SleepCountdown.maxStep)
check("checks once a second while far from the end", timer.nextCheck == 1)

var ending = SleepCountdown(choice: .minutes(1))!
for _ in 0..<50 { ending.advance(listened: 1) }
check("the last ten seconds are when it checks often", ending.nextCheck == 0.1 && !ending.isDone,
      "\(ending.nextCheck)")
check("it never sleeps past the start of the fade",
      SleepCountdown(choice: .minutes(1))!.nextCheck <= 1)
check("still loud until the fade", ending.volume == 1, "\(ending.volume)")
ending.advance(listened: 5)
check("half way through the fade is a quarter of the volume", ending.volume == 0.25, "\(ending.volume)")
for _ in 0..<10 { ending.advance(listened: 1) }
check("then it is done, and silent", ending.isDone && ending.volume == 0)

let curve: [Float] = stride(from: 10.0, through: 0.0, by: -0.5).map { SleepCountdown.volume(remaining: $0) }
check("the fade only ever gets quieter",
      zip(curve, curve.dropFirst()).allSatisfy { $0 >= $1 }, "\(curve)")
check("the fade starts at full volume and ends at none", curve.first == 1 && curve.last == 0)

check("the end of a section with no end known cannot be set",
      SleepCountdown(choice: .endOfSection) == nil)
var section = SleepCountdown(choice: .endOfSection, sectionLeft: 120)!
check("the end of this section starts from the player's own count", section.remaining == 120)
section.advance(listened: 1)
section.follow(sectionLeft: 200)
check("a scrub back gives the time back", section.remaining == 200)
section.follow(sectionLeft: -4)
check("past the end is done", section.isDone)

// MARK: chapters - from headings

let typed: [String] = [
    "Today: acid-base in three systems.",
    "# Buffers",
    "Buffers act in seconds.",
    "The bicarbonate buffer is the one you'll use most.",
    "# The lungs",
    "The lungs act in minutes.",
    "A rise in CO2 lowers pH.",
    "Slide 7: The kidneys",
    "The kidneys act over days.",
    "They reabsorb bicarbonate."
]
let fromHeadings = AudioChapters.derive(lines: typed)
check("a section at every heading, and one for the opening",
      fromHeadings.map(\.lines) == [0..<1, 1..<4, 4..<7, 7..<10], "\(fromHeadings.map(\.lines))")
check("headings are the sections' names",
      fromHeadings.map(\.title) == ["Today: acid-base in three systems", "Buffers", "The lungs", "Slide 7: The kidneys"],
      "\(fromHeadings.map(\.title))")
check("a typed lecture has no times", fromHeadings.allSatisfy { $0.start == nil })

check("a Markdown heading is a heading", AudioChapters.heading("## Renal tubular acidosis") == "Renal tubular acidosis")
check("a short line ending in a colon is a heading", AudioChapters.heading("Management:") == "Management")
check("Part two is a heading", AudioChapters.heading("Part two") == "Part two")
check("Section B and Chapter IV are headings",
      AudioChapters.heading("Section B") == "Section B" && AudioChapters.heading("Chapter IV") == "Chapter IV")
check("Slide 12 is a heading in a recording too",
      AudioChapters.heading("slide 12 the nephron", timed: true) == "slide 12 the nephron")
check("a sentence that starts with Part is not a heading",
      AudioChapters.heading("part of the reason is the kidneys", timed: true) == nil)
check("Topic: with its colon is a heading",
      AudioChapters.heading("topic: the kidneys", timed: true) == "topic: the kidneys")
check("nor one that starts with Lecture",
      AudioChapters.heading("lecture notes are online after this", timed: true) == nil)
check("a short capitalised line with no full stop is a heading in typed notes",
      AudioChapters.heading("Clinical features") == "Clinical features")
check("but not in a recording's transcript, which may have no punctuation at all",
      AudioChapters.heading("Clinical features", timed: true) == nil)
check("a sentence is not a heading", AudioChapters.heading("Buffers act in seconds.") == nil)
check("a long line is not a heading",
      AudioChapters.heading("The kidneys compensate slowly by reabsorbing more bicarbonate over days") == nil)
check("Arabic has no capitals, so only a marker makes it a heading",
      AudioChapters.heading("\u{0627}\u{0644}\u{0639}\u{0644}\u{0627}\u{062C}") == nil)

let doubled = ["# Renal", "## Acid-base", "Line one.", "Line two.", "Line three.", "# Next", "More.", "And more."]
let merged = AudioChapters.derive(lines: doubled)
check("a heading and its subheading start one section, under the first",
      merged.map(\.lines) == [0..<5, 5..<8] && merged.first?.title == "Renal", "\(merged.map(\.lines))")

let listy = ["Causes:", "Drugs:", "Sepsis.", "Trauma:", "Burns:", "Other."]
check("headings on most lines are a list, not sections", AudioChapters.derive(lines: listy).isEmpty)

// MARK: chapters - a recording with no headings

// forty minutes, a line every 20 s, a long pause before line 45 and a
// "So now" at line 61
var said: [String] = []
var starts: [Double?] = []
var ends: [Double?] = []
for i in 0..<120 {
    let turn: Bool = i == 61
    said.append(turn ? "So now the kidneys, which take days" : "and this is line \(i) of what was said")
    let t: Double = Double(i) * 20 + (i >= 45 ? 8 : 0)
    starts.append(t)
    ends.append(t + 17)
}
let recorded = AudioChapters.derive(lines: said, starts: starts, ends: ends)
check("a forty-minute recording is cut into sections of about five minutes",
      recorded.count == 8, "\(recorded.count)")
check("every line is in exactly one section, in order",
      recorded.map { Array($0.lines) }.flatMap { $0 } == Array(0..<120))
check("each section starts when its first line does",
      recorded.allSatisfy { $0.start == starts[$0.lines.lowerBound] })
check("a cut falls at the long pause", recorded.contains { $0.lines.lowerBound == 45 },
      "\(recorded.map(\.lines.lowerBound))")
check("a cut falls at the line that turns to something new",
      recorded.contains { $0.lines.lowerBound == 61 }, "\(recorded.map(\.lines.lowerBound))")
check("no section is tiny", recorded.allSatisfy { $0.lines.count >= 5 }, "\(recorded.map(\.lines.count))")
check("a section is named by its first words",
      recorded[0].title == "and this is line 0 of\u{2026}", recorded[0].title)

let untimedStarts: [Double?] = Array(repeating: nil, count: said.count)
let untimed = AudioChapters.derive(lines: said, starts: untimedStarts, ends: untimedStarts)
check("a transcript with no times is cut by its length read aloud",
      untimed.count >= 2 && untimed.allSatisfy { $0.start == nil }, "\(untimed.count)")

let brief = ["One short line.", "Another short line.", "And a third."]
check("a short lecture with no headings is one section", AudioChapters.derive(lines: brief).isEmpty)
check("a single line is one section", AudioChapters.derive(lines: ["Just this."]).isEmpty)

// MARK: where am I

let marks: [AudioChapter] = [
    AudioChapter(title: "A", lines: 0..<4, start: 0),
    AudioChapter(title: "B", lines: 4..<9, start: 100),
    AudioChapter(title: "C", lines: 9..<12, start: 250)
]
check("the section at a moment", AudioChapters.index(atTime: 120, in: marks) == 1)
check("at the very start of a section, that section", AudioChapters.index(atTime: 100, in: marks) == 1)
check("before the first, the first", AudioChapters.index(atTime: -1, in: marks) == 0)
check("past the last start, the last", AudioChapters.index(atTime: 9_999, in: marks) == 2)
check("no sections, no section", AudioChapters.index(atTime: 5, in: []) == nil)
check("the section a line is in", AudioChapters.index(containingLine: 8, in: marks) == 1)
check("its last line too", AudioChapters.index(containingLine: 11, in: marks) == 2)
check("a section ends where the next starts", AudioChapters.end(after: 120, in: marks, duration: 400) == 250)
check("the last ends with the recording", AudioChapters.end(after: 300, in: marks, duration: 400) == 400)
check("Back well into a section goes to its start", AudioChapters.previous(fromTime: 150, in: marks) == 1)
check("Back just after a section starts goes to the one before",
      AudioChapters.previous(fromTime: 101, in: marks) == 0)
check("Back in the first section goes to its start", AudioChapters.previous(fromTime: 1, in: marks) == 0)
check("Back by line: mid-section to its start", AudioChapters.previous(fromLine: 6, in: marks) == 1)
check("Back by line: on the first line, the one before", AudioChapters.previous(fromLine: 4, in: marks) == 0)
check("Next goes to the section after", AudioChapters.next(after: 1, in: marks) == 2)
check("there is no next after the last", AudioChapters.next(after: 2, in: marks) == nil)
check("the lock screen's words", AudioChapters.position(1, of: marks) == "Section 2 of 3")

let reading = ["one two three four five", "six seven eight nine ten", "eleven twelve"]
let aloud: Double = AudioChapters.secondsToRead(reading, line: 0, word: 0, until: 2, speed: 1)
check("ten words at 150 a minute is four seconds", aloud == 4, "\(aloud)")
let quick: Double = AudioChapters.secondsToRead(reading, line: 0, word: 0, until: 2, speed: 2)
check("twice as fast, half the time", quick == 2, "\(quick)")
let partway: Double = AudioChapters.secondsToRead(reading, line: 1, word: 3, until: 2, speed: 1)
check("the words already said do not count, but it is never quite zero", partway == 1, "\(partway)")
check("once there, zero", AudioChapters.secondsToRead(reading, line: 2, word: 0, until: 2, speed: 1) == 0)

print(failures.isEmpty ? "\nALL AUDIO CONTROLS TESTS PASS"
                       : "\n\(failures.count) AUDIO CONTROLS TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
