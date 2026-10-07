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

// chunks: the planned edges, before each is moved to a quiet moment
check("a short clip is one chunk", CloudTranscript.chunkStarts(duration: 95) == [0])
check("an hour is planned as six ten-minute chunks", CloudTranscript.chunkStarts(duration: 3600) == [0, 600, 1200, 1800, 2400, 3000])
check("a few seconds past a boundary join the last chunk",
      CloudTranscript.chunkStarts(duration: 1210) == [0, 600], "\(CloudTranscript.chunkStarts(duration: 1210))")
check("no audio, no chunks", CloudTranscript.chunkStarts(duration: 0).isEmpty)

// the quiet moment a cut moves back to
let rate = 16000.0
func speech(seconds: Double, quietFrom: Double? = nil, quietTo: Double = 0) -> [Int16] {
    (0..<Int(seconds * rate)).map { i in
        let t = Double(i) / rate
        if let from = quietFrom, t >= from, t < quietTo { return Int16(i % 2 == 0 ? 40 : -40) }
        return Int16(i % 2 == 0 ? 8000 : -8000)
    }
}
let pause = CloudTranscript.frameLevels(speech(seconds: 3, quietFrom: 1.2, quietTo: 1.6), sampleRate: rate)
check("three seconds are measured in overlapping tenths", pause.count == 59, "\(pause.count)")
let cut = CloudTranscript.quietestCut(levels: pause, windowStart: 597, edge: 600)
check("the cut moves back into the pause between words", cut >= 598.2 && cut <= 598.6, "\(cut)")
let steady = CloudTranscript.frameLevels(speech(seconds: 3), sampleRate: rate)
let late = CloudTranscript.quietestCut(levels: steady, windowStart: 597, edge: 600)
check("with no pause the cut stays as late as it can", late > 599.8 && late <= 600, "\(late)")
check("audio that could not be read keeps the exact mark",
      CloudTranscript.quietestCut(levels: [], windowStart: 597, edge: 600) == 600)
check("a sliver too short to measure has no levels", CloudTranscript.frameLevels([1, 2, 3], sampleRate: rate).isEmpty)
let edgeCut = CloudTranscript.quietestCut(levels: [5, 5, 0], windowStart: 597, edge: 597.1)
check("a cut never passes the planned edge", edgeCut <= 597.1, "\(edgeCut)")

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

// a reply cut off at the token limit keeps what came before
let cutOff = """
[{"start": 0.4, "end": 3.1, "text": "الـ malar rash بتاعة الـ SLE"},
 {"start": 3.3, "end": 6.0, "text": "spares the nasolabial folds"},
 {"start": 6.2, "end": 9.8, "text": "skin skin skin sk
"""
check("a cut-off reply is not read as a whole one", CloudTranscript.phrases(fromReply: cutOff) == nil)
check("but its complete phrases are kept", CloudTranscript.salvage(fromReply: cutOff)?.map(\.text)
      == ["الـ malar rash بتاعة الـ SLE", "spares the nasolabial folds"],
      "\(String(describing: CloudTranscript.salvage(fromReply: cutOff)))")
check("a fenced cut-off reply too", CloudTranscript.salvage(fromReply: "```json\n" + cutOff)?.count == 2)
check("prose has nothing to keep", CloudTranscript.salvage(fromReply: "Here is the transcript: {hello}") == nil)
check("nor does a reply cut off in its first phrase", CloudTranscript.salvage(fromReply: "[{\"start\": 0, \"end\": 2, \"te") == nil)

// the runaway-loop guard
check("a word said over and over is cut back to once",
      CloudTranscript.cutRepeats(in: "the rash " + Array(repeating: "skin", count: 400).joined(separator: " ")) == "the rash skin")
check("so is a looping line of several words",
      CloudTranscript.cutRepeats(in: String(repeating: "the malar rash spares the folds ", count: 30))
          == "the malar rash spares the folds")
check("a lecturer repeating a term is left alone",
      CloudTranscript.cutRepeats(in: "malar rash, malar rash, the malar rash") == "malar rash, malar rash, the malar rash")
check("three times in a row is still speech", CloudTranscript.cutRepeats(in: "no no no") == "no no no")
check("Arabic loops are cut the same way",
      CloudTranscript.cutRepeats(in: Array(repeating: "يعني كده", count: 10).joined(separator: " ")) == "يعني كده")
let normal = (0..<150).map { Phrase(start: Double($0) * 4, end: Double($0) * 4 + 3.5, text: "phrase number \($0) about lupus") }
let unchanged = CloudTranscript.cutLoops(normal)
check("a normal chunk passes untouched", unchanged.removed == 0 && unchanged.phrases == normal)
let block = [Phrase(start: 600, end: 601, text: "and the kidney"), Phrase(start: 601, end: 602, text: "is involved.")]
let looped = Array(normal.prefix(20)) + Array(Array(repeating: block, count: 40).joined())
let guarded = CloudTranscript.cutLoops(looped)
check("the same two phrases forty times keep one round",
      guarded.phrases.count == 22 && guarded.phrases.suffix(2).map(\.text) == ["and the kidney", "is involved."],
      "\(guarded.phrases.count)")
check("and count what was cut", guarded.removed == 39 * 5, "\(guarded.removed)")
check("enough to tell the student", guarded.removed >= CloudTranscript.loopWorthMentioning)
let echo = [Phrase(start: 0, end: 1, text: "Malar rash."), Phrase(start: 1, end: 2, text: "malar rash"),
            Phrase(start: 2, end: 3, text: "Malar rash!"), Phrase(start: 3, end: 4, text: "the cheeks")]
check("a phrase said three times running is speech", CloudTranscript.cutLoops(echo).removed == 0)
let fourEchoes = [echo[0], echo[1], echo[2], echo[1], echo[3]]
check("four times, whatever the punctuation, is a loop", CloudTranscript.cutLoops(fourEchoes).phrases.count == 2)

// what the student is told
check("whole parts need no note",
      CloudTranscript.notice(for: [.init(number: 1), .init(number: 2)], of: 2) == nil)
let told = CloudTranscript.notice(for: [.init(number: 1), .init(number: 2, trimmed: true), .init(number: 3, trimmed: true)], of: 3) ?? ""
check("trimmed parts are named", told.contains("parts 2 and 3") && told.contains("those parts"), told)
let one = CloudTranscript.notice(for: [.init(number: 1, trimmed: true)], of: 1) ?? ""
check("a one-part lecture is the lecture", one.contains("the lecture") && !one.contains("part 1"), one)
check("parts are listed as a person would", CloudTranscript.partNames([1, 2, 6]) == "parts 1, 2 and 6"
      && CloudTranscript.partNames([4]) == "part 4")

// which model heard each part
let flash = CloudTranscript.PartNote(number: 1, model: "gemini-3.5-flash")
let lite = CloudTranscript.PartNote(number: 2, model: "gemini-3.5-flash-lite")
check("every part from 3.5 Flash needs no note", CloudTranscript.notice(for: [flash, flash], of: 2) == nil)
check("a part whose model is not known is not called a downgrade",
      !CloudTranscript.fellBack(.init(number: 1)) && CloudTranscript.fellBack(lite) && !CloudTranscript.fellBack(flash))
let downgraded = CloudTranscript.notice(for: [flash, lite], of: 2) ?? ""
check("a part Flash-Lite heard is named, never a silent downgrade",
      downgraded.contains("Part 2 went to gemini-3.5-flash-lite"), downgraded)
let both = CloudTranscript.notice(for: [flash, .init(number: 2, trimmed: true, model: "gemini-3.5-flash-lite")], of: 2) ?? ""
check("a loop and a downgrade are both told", both.contains("repeating itself") && both.contains("flash-lite"), both)
let heard = CloudTranscript.lines(from: phrases ?? [], offset: 0, length: 600, model: "gemini-3.5-flash-lite")
check("each line keeps the model that heard it", !heard.isEmpty && heard.allSatisfy { $0.model == "gemini-3.5-flash-lite" })
let kept = NarrateScheduler.segments(from: heard, lang: "ar")
check("and so does the saved transcript", kept.allSatisfy { $0.model == "gemini-3.5-flash-lite" })
let saved = try? JSONDecoder().decode(NarrateSegment.self, from: Data(#"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"hi","lang":"en"}"#.utf8))
check("a line saved before models were kept still opens", saved?.text == "hi" && saved?.model == nil)
let again = try? JSONDecoder().decode(NarrateSegment.self, from: JSONEncoder().encode(kept[0]))
check("and the model is saved with the line", again?.model == "gemini-3.5-flash-lite")

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
let heart = CloudTranscript.lectureTerms(slides: ["Atrial fibrillation: anticoagulation and rhythm control"])
check("a cardiology lecture's terms are its own, not lupus's",
      heart.contains("fibrillation") && !heart.contains("lupus") && !heart.contains("hydroxychloroquine"), "\(heart)")
check("no slides, no slide terms", CloudTranscript.lectureTerms(slides: []).isEmpty
      && !CloudTranscript.prompt(vocabulary: CloudTranscript.lectureTerms(slides: [])).contains("Terms from"))
check("Arabic on a slide is not a spelling hint",
      CloudTranscript.vocabulary(from: ["الذئبة الحمراء lupus"]).allSatisfy { $0.unicodeScalars.allSatisfy(\.isASCII) })
let prompt = CloudTranscript.prompt(vocabulary: ["hydroxychloroquine"])
check("the prompt carries the slide terms", prompt.contains("hydroxychloroquine"))
check("and asks for Egyptian Arabic in Arabic script, English in English",
      prompt.contains("Egyptian") && prompt.contains("English letters"))
check("a mixed lecture is the default", prompt == CloudTranscript.prompt(vocabulary: ["hydroxychloroquine"], language: .mixed))
check("and shows the accent example only there", prompt.contains("cloud storage") && prompt.contains("كلاود"))

// the pipeline's rules, after the app's own
for (name, said) in [("mixed", prompt), ("English", CloudTranscript.prompt(vocabulary: [], language: .english))] {
    check("\(name): goes on to the end", said.contains("do not stop early") && said.contains("first second to the last"))
    check("\(name): the recording is the only source", said.contains("only source") && said.contains("from memory"))
    check("\(name): drugs and poisons are relayed, not advised on",
          said.contains("transcription only") && said.contains("poisons") && said.contains("do not give advice"))
    check("\(name): students' questions and repetitions are kept",
          said.contains("students' questions") && said.contains("repetitions"))
    let own = said.range(of: "Leave out only")?.lowerBound, added = said.range(of: "do not stop early")?.lowerBound
    check("\(name): the app's own rules come first", own != nil && added != nil && own! < added!)
    check("\(name): still asks for timed phrases", said.contains("start and end time"))
}

// an English lecture
let english = CloudTranscript.prompt(vocabulary: ["hydroxychloroquine"], language: .english)
check("an English lecture is not told to expect Egyptian Arabic",
      !english.contains("Egyptian") && !english.contains("Arabic script") && english.contains("speaks English"))
check("and gets no Arabic example", !english.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) })
check("and still asks for correct English spelling of every term", english.contains("correct English spelling"))
check("and still carries the slide terms", english.contains("hydroxychloroquine"))
check("one prompt per language", CloudTranscript.prompt(vocabulary: [], language: .mixed)
      != CloudTranscript.prompt(vocabulary: [], language: .english))
check("an English lecture is heard by the English recogniser",
      LectureLanguage.english.locale == "en-US" && LectureLanguage.mixed.locale == "ar-EG")

if failures.isEmpty { print("all passed") } else { print("\(failures.count) failed"); exit(1) }
