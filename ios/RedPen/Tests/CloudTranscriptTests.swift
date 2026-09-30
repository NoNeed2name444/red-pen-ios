// What Gemini is asked and how its answer becomes lines the Narrate player can
// follow. The network call is Google's; what is tested is everything CramDown
// decides about its answer.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

typealias Phrase = CloudTranscript.Phrase

// chunks
check("a short clip is one chunk", CloudTranscript.chunkStarts(duration: 95) == [0])
check("an hour is six ten-minute chunks", CloudTranscript.chunkStarts(duration: 3600) == [0, 600, 1200, 1800, 2400, 3000])
check("a few seconds past a boundary join the last chunk",
      CloudTranscript.chunkStarts(duration: 1210) == [0, 600], "\(CloudTranscript.chunkStarts(duration: 1210))")
check("no audio, no chunks", CloudTranscript.chunkStarts(duration: 0).isEmpty)

// the answer
let reply = """
[{"start": 0.4, "end": 3.1, "text": "الـ malar rash بتاعة الـ SLE"},
 {"start": 3.3, "end": 6.0, "text": "spares the nasolabial folds"},
 {"start": 6.2, "end": 9.8, "text": "  "}]
"""
let phrases = CloudTranscript.phrases(fromReply: reply)
check("JSON phrases are read", phrases?.count == 2, "\(String(describing: phrases))")
check("a fenced answer is read too",
      CloudTranscript.phrases(fromReply: "```json\n" + reply + "\n```")?.count == 2)
check("prose is not a transcript", CloudTranscript.phrases(fromReply: "Here is the transcript: hello") == nil)

// timing, from times that can be trusted
let lines = CloudTranscript.lines(from: phrases ?? [], offset: 600, length: 600)
check("lines sit on the recording's clock, not the chunk's", lines.first?.start == 600.4, "\(lines.first?.start ?? -1)")
check("and keep their end", lines.last.map { abs($0.end - 606.0) < 0.001 } == true)
check("each word gets a time inside its line",
      lines.allSatisfy { line in line.words.allSatisfy { $0.start >= line.start - 0.001 && $0.end <= line.end + 0.001 } })
check("word times follow each other",
      lines[1].words.map(\.start) == lines[1].words.map(\.start).sorted())
check("a longer word takes longer to say",
      (lines[1].words.first { $0.text == "nasolabial" }?.duration ?? 0) > (lines[1].words.first { $0.text == "the" }?.duration ?? 1))

// timing, from times that cannot
let zeros = [Phrase(start: 0, end: 0, text: "one two three four"), Phrase(start: 0, end: 0, text: "five six"),
             Phrase(start: 0, end: 0, text: "seven eight nine ten eleven twelve")]
check("all-zero times are not trusted", !CloudTranscript.trustworthy(zeros, length: 60))
let spread = CloudTranscript.lines(from: zeros, offset: 0, length: 60)
check("so the chunk is shared out by text length",
      spread.first?.start == 0 && abs((spread.last?.end ?? 0) - 60) < 0.001 && spread[1].start == spread[0].end,
      spread.map { "\($0.start)-\($0.end)" }.joined(separator: " "))
let backwards = [Phrase(start: 30, end: 33, text: "a"), Phrase(start: 10, end: 12, text: "b"),
                 Phrase(start: 5, end: 7, text: "c"), Phrase(start: 1, end: 2, text: "d")]
check("times running backwards are not trusted", !CloudTranscript.trustworthy(backwards, length: 60))
let wobbly = [Phrase(start: 0, end: 4, text: "a b"), Phrase(start: 3.5, end: 8, text: "c d"),
              Phrase(start: 8, end: 700, text: "e f")]
let clamped = CloudTranscript.lines(from: wobbly, offset: 0, length: 600)
check("a small overlap is kept in order", clamped[1].start >= clamped[0].start)
check("nothing ends past the chunk", clamped.allSatisfy { $0.end <= 600 })

// language
check("an Arabic line is Arabic", CloudTranscript.language(of: "الـ malar rash بتاعة الـ SLE الواضحة") == "ar")
check("an English line is English", CloudTranscript.language(of: "spares the nasolabial folds") == "en")
check("numbers alone read as English", CloudTranscript.language(of: "12 3") == "en")

// vocabulary
let slides = ["Systemic Lupus Erythematosus: malar rash, discoid lesions, photosensitivity",
              "Anti-phospholipid syndrome. Hydroxychloroquine for every patient with lupus. Photosensitivity again."]
let vocab = CloudTranscript.vocabulary(from: slides, extra: ["nephritis", "photosensitivity"], limit: 30)
check("repeated slide terms come first", vocab.first?.lowercased() == "photosensitivity", "\(vocab)")
check("short and common words are left out", !vocab.contains { ["rash", "for", "patient"].contains($0.lowercased()) })
check("the common list fills the room left, without repeats",
      vocab.contains("nephritis") && vocab.filter { $0.lowercased() == "photosensitivity" }.count == 1)
check("Arabic on a slide is not a spelling hint",
      CloudTranscript.vocabulary(from: ["الذئبة الحمراء lupus"]).allSatisfy { $0.unicodeScalars.allSatisfy(\.isASCII) })
let prompt = CloudTranscript.prompt(vocabulary: ["hydroxychloroquine"])
check("the prompt carries the slide terms", prompt.contains("hydroxychloroquine"))
check("and asks for Egyptian Arabic in Arabic script, English in English",
      prompt.contains("Egyptian") && prompt.contains("English letters"))

if failures.isEmpty { print("all passed") } else { print("\(failures.count) failed"); exit(1) }
