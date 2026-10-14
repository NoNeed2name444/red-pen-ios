// Red Pen · learning a lecturer's pronunciations from one lecture, on the phone
//
// Three sources of evidence, all of them already on the device:
//
//   .slide       the lecturer reads terms off his slides, and Red Pen already
//                runs Vision OCR over them. The slide gives the spelling, the
//                audio gives the sound. Nothing is inferred - the two are
//                simply matched, and this is the strongest signal there is;
//   .correction  the student edits a word in the transcript. Gold, and free;
//   .repetition  the same sound recurs in one lecture and the deterministic
//                repair maps every occurrence to the same term. Corroboration
//                by repetition rather than by a second model.
//
// No audio leaves the phone and no model is retrained. What is produced is a
// table of sound-to-spelling, which is the only thing that was missing.
import Foundation

public enum OnDeviceLearning {

    /// Terms the slides spell out. Vision OCR already gives Red Pen this text;
    /// what matters is that it is the LECTURER'S OWN spelling of the words he
    /// is about to say, which makes it supervision rather than a guess.
    @discardableResult
    public static func fromSlides(transcript: String, slideText: [String],
                                  into store: inout PronunciationStore) -> Int {
        var phrases: [(key: String, spelling: String)] = []
        for slide in slideText {
            let words = slide.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map(String.init)
            for width in 1...2 {
                guard words.count >= width else { continue }
                for start in 0...(words.count - width) {
                    let phrase = Array(words[start..<(start + width)])
                    let usable = phrase.allSatisfy { word in
                        word.count >= 3 && word.unicodeScalars.allSatisfy { $0.isASCII }
                    }
                    guard usable else { continue }
                    let key = SoundKey.of(span: phrase)
                    if key.replacingOccurrences(of: " ", with: "").count >= 4 {
                        phrases.append((key, phrase.joined(separator: " ")))
                    }
                }
            }
        }
        guard !phrases.isEmpty else { return 0 }
        var bySound: [String: String] = [:]
        for phrase in phrases {
            bySound[phrase.key] = bySound[phrase.key] ?? phrase.spelling
            let flat = SoundKey.collapsed(phrase.key)
            bySound[flat] = bySound[flat] ?? phrase.spelling
        }

        let tokens = transcript.split(separator: " ").map(String.init)
        var learned = 0
        var i = 0
        while i < tokens.count {
            var n = min(2, tokens.count - i)
            var matched = false
            while n >= 1 {
                let span = Array(tokens[i..<(i + n)])
                let key = SoundKey.of(span: span)
                if span.contains(where: SoundKey.hasArabic),
                   let spelling = bySound[key] ?? bySound[SoundKey.collapsed(key)] {
                    if store.add(sound: key, spelling: spelling,
                                 heardAs: span.joined(separator: " "), evidence: .slide) {
                        learned += 1
                    }
                    i += n
                    matched = true
                    break
                }
                n -= 1
            }
            if !matched { i += 1 }
        }
        return learned
    }

    /// The student edited a word. Whatever they wrote is how it is spelled.
    @discardableResult
    public static func fromCorrection(heard: [String], wrote: String,
                                      into store: inout PronunciationStore) -> Bool {
        store.add(sound: SoundKey.of(span: heard), spelling: wrote,
                  heardAs: heard.joined(separator: " "), evidence: .correction)
    }

    /// The deterministic repair mapped the same sound to the same term more
    /// than once in a lecture. Weaker than a slide, so it needs repetition -
    /// and a sound that produced two DIFFERENT terms teaches nothing at all.
    @discardableResult
    public static func fromRepetition(_ repairs: [(heard: String, term: String)],
                                      into store: inout PronunciationStore) -> Int {
        var seen: [String: [String: Int]] = [:]
        var heardAs: [String: String] = [:]
        for hit in repairs {
            let key = SoundKey.of(span: hit.heard.split(separator: " ").map(String.init))
            guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            seen[key, default: [:]][hit.term, default: 0] += 1
            heardAs[key] = hit.heard
        }
        var learned = 0
        for (key, terms) in seen where terms.count == 1 {
            guard let (term, times) = terms.first, times >= Evidence.repetition.needed else { continue }
            for _ in 0..<times {
                store.add(sound: key, spelling: term, heardAs: heardAs[key] ?? "",
                          evidence: .repetition)
            }
            learned += 1
        }
        return learned
    }
}
