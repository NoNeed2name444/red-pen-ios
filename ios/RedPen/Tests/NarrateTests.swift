// Red Pen · reading a lecture aloud: how it is cut into clips, where each
// word falls inside one, and what is fetched ahead.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: clips

let line = String(repeating: "word ", count: 20)   // 100 characters
let lecture: [String] = Array(repeating: line, count: 40)
let chunks = NarratePlan.chunks(lecture)

check("every line is in exactly one clip, in order",
      chunks.map { Array($0.lines) }.flatMap { $0 } == Array(0..<40), "\(chunks.map(\.lines))")
check("the first clip is short, so speech starts quickly",
      chunks[0].text.count <= NarratePlan.firstLimit, "\(chunks[0].text.count)")
check("later clips are longer, so a lecture is few requests",
      chunks.count < 12 && chunks[1].lines.count > chunks[0].lines.count, "\(chunks.count)")
check("no clip is more than the server takes",
      chunks.allSatisfy { $0.text.count <= NarratePlan.hardCap })

let long = String(repeating: "x", count: 2000)
let odd = NarratePlan.chunks(["short", long, "after"])
check("a line too long for a clip is still its own clip, never lost",
      odd.map(\.lines) == [0..<1, 1..<2, 2..<3], "\(odd.map(\.lines))")
check("a blank line leaves no double space",
      NarratePlan.chunks(["one", "  ", "two"])[0].text == "one two",
      NarratePlan.chunks(["one", "  ", "two"])[0].text)
check("an empty lecture has no clips", NarratePlan.chunks([]).isEmpty)

check("the clip holding a line is found",
      NarratePlan.chunkIndex(containing: 17, in: chunks).map { chunks[$0].lines.contains(17) } == true)
check("a line past the end is in no clip",
      NarratePlan.chunkIndex(containing: 99, in: chunks) == nil)

// MARK: word times

let words = NarratePlan.wordTimes(lines: ["Buffers act in seconds, the lungs in minutes.",
                                          "The kidneys take days."],
                                  range: 0..<2, duration: 6)
check("every word is timed", words.count == 12, "\(words.count)")
check("the words fill the clip exactly",
      words.first?.start == 0 && words.last?.end == 6, "\(words.first?.start ?? -1) \(words.last?.end ?? -1)")
check("times only move forward",
      zip(words, words.dropFirst()).allSatisfy { $0.end <= $1.start && $0.start < $0.end })
let seconds = words[3]                      // "seconds," before a comma
let the = words[4]
check("a comma leaves a pause before the next word",
      the.start - seconds.end > 0.05, "\(the.start - seconds.end)")
let minutes = words[7]                      // "minutes." ends the line
let next = words[8]
check("a full stop leaves a longer pause than a comma",
      next.start - minutes.end > the.start - seconds.end)
check("a long word is given longer than a short one",
      words[0].end - words[0].start > words[2].end - words[2].start)
check("the second line's words say which line they are in",
      words[8].line == 1 && words[8].word == 0)
check("nothing to time gives nothing",
      NarratePlan.wordTimes(lines: ["a"], range: 0..<1, duration: 0).isEmpty)

check("the word at a moment is found",
      NarratePlan.spot(at: seconds.start + 0.01, in: words) == 3)
check("in a pause the word just said stays lit",
      NarratePlan.spot(at: seconds.end + 0.01, in: words) == 3)
check("before the first word, the first word",
      NarratePlan.spot(at: -1, in: words) == 0)
check("after the end, the last word",
      NarratePlan.spot(at: 99, in: words) == words.count - 1)
check("no words, no spot", NarratePlan.spot(at: 1, in: []) == nil)
check("a line starts where its first word does",
      NarratePlan.start(ofLine: 1, in: words) == words[8].start)

// MARK: fetching ahead

check("the playing clip and the next three are fetched",
      NarratePlan.prefetch(current: 2, count: 10, ahead: 3, have: []) == [2, 3, 4, 5])
check("clips already here are not fetched again",
      NarratePlan.prefetch(current: 2, count: 10, ahead: 3, have: [2, 3]) == [4, 5])
check("nothing past the end is fetched",
      NarratePlan.prefetch(current: 8, count: 10, ahead: 3, have: []) == [8, 9])
check("past the end, nothing",
      NarratePlan.prefetch(current: 10, count: 10, ahead: 3, have: []).isEmpty)

// MARK: the phone's voice

check("normal speed is the phone's normal pace", NarratePlan.phoneRate(1) == 0.5)
check("faster is faster, slower is slower",
      NarratePlan.phoneRate(1.5) > 0.5 && NarratePlan.phoneRate(0.75) < 0.5)
check("double speed stays intelligible", NarratePlan.phoneRate(2) <= 0.7)

let spoken = "The  bicarbonate buffer"
check("a range at the start is the first word",
      NarratePlan.wordIndex(atUTF16: 0, in: spoken) == 0)
check("a double space does not count as a word",
      NarratePlan.wordIndex(atUTF16: 5, in: spoken) == 1, "\(NarratePlan.wordIndex(atUTF16: 5, in: spoken))")
check("the third word", NarratePlan.wordIndex(atUTF16: 17, in: spoken) == 2)
check("the words match the screen's split",
      NarratePlan.tokens(spoken) == ["The", "bicarbonate", "buffer"])
let arabic = "\u{627}\u{644}\u{62d}\u{645}\u{636} pH"
check("Arabic counts words the same way",
      NarratePlan.wordIndex(atUTF16: 6, in: arabic) == 1)

// MARK: the phone standing in for one clip

// a line too long for the server is read by the phone - that clip, and no
// more: the cloud takes the next one back
check("the phone hands the too-long line back at its own clip's end",
      NarratePlan.standInEnd(forLine: 1, in: odd) == 2, "\(String(describing: NarratePlan.standInEnd(forLine: 1, in: odd)))")
check("not at the end of the lecture",
      NarratePlan.standInEnd(forLine: 1, in: odd) != odd.last?.lines.upperBound)
check("a line in a longer clip hands back where that clip ends",
      NarratePlan.standInEnd(forLine: 17, in: chunks)
        == NarratePlan.chunkIndex(containing: 17, in: chunks).map { chunks[$0].lines.upperBound })
check("a line in no clip has nowhere to hand back", NarratePlan.standInEnd(forLine: 99, in: chunks) == nil)

// MARK: the clip cache

let day: TimeInterval = 86_400
let cached: [(name: String, used: Date)] = (0..<6).map {
    (name: "clip\($0).mp3", used: Date(timeIntervalSince1970: Double($0) * day))
}
check("nothing is pruned under the limit",
      NarratePlan.pruneList(cached, keep: 10, protected: []).isEmpty)
check("the least recently used go first",
      NarratePlan.pruneList(cached, keep: 4, protected: []) == ["clip0.mp3", "clip1.mp3"],
      "\(NarratePlan.pruneList(cached, keep: 4, protected: []))")
// replaying an old lecture: its clips are the oldest files, and deleting one
// that is about to play leaves the lecture silent
check("a clip the lecture holds is never pruned, however old",
      NarratePlan.pruneList(cached, keep: 4, protected: ["clip0.mp3"]) == ["clip1.mp3", "clip2.mp3"],
      "\(NarratePlan.pruneList(cached, keep: 4, protected: ["clip0.mp3"]))")
check("with everything protected, nothing is deleted",
      NarratePlan.pruneList(cached, keep: 2, protected: Set(cached.map(\.name))).isEmpty)

print(failures.isEmpty ? "\nALL NARRATE TESTS PASS"
                       : "\n\(failures.count) NARRATE TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
