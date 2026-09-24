// Red Pen · on-device OCR
//
// Vision's text recogniser handles Red Pen's material natively - measured on a
// macOS 26 runner: English exact, Arabic exact ("الطفح الجلدي المزمن"), and
// ar-SA / ars-SA both in supportedRecognitionLanguages. No model to ship, no
// network, no account.
//
// The one case it gets wrong is the one Red Pen actually has: a slide line that
// mixes both scripts comes back in VISUAL order.
//     slide:  الـ malar rash بيـ spare الـ nasolabial fold
//     Vision: nasolabial fold ال spare بي malar rash ال
// Every token is correct; only the order is wrong, and the structure of the
// error is exact rather than approximate - it is the token list reversed, with
// each embedded Latin run left in its own reading order. So the inverse is
// exact: reverse the tokens, then reverse each contiguous Latin run back.
//
// This is also what feeds the .slide evidence in OnDeviceLearning: the slide is
// the lecturer's own spelling of the word he is about to say, which is why it
// outranks anything the recogniser guesses.
import Foundation
import Vision
import CoreGraphics

public struct OCRLine {
    public let text: String
    public let box: CGRect          // normalised, origin bottom-left
    public let confidence: Float
    /// Each word of the line with its own box, when Vision can say where each
    /// one is. Empty for a line that mixes scripts (its words are reordered)
    /// or when Vision gave no word boxes; the line is then one piece.
    public var words: [OCRWord] = []
}

public struct OCRWord {
    public let text: String
    public let box: CGRect          // normalised, origin bottom-left
}

public enum RedPenOCR {

    /// Languages worth asking for on Red Pen's material. ars-SA is Najdi; asking
    /// for both widens dialectal coverage at no cost, and unsupported tags are
    /// simply ignored by Vision rather than throwing.
    public static let languages = ["ar-SA", "ars-SA", "en-US"]

    public static func read(_ image: CGImage,
                            languages: [String] = languages) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        return (request.results ?? []).compactMap { observation -> OCRLine? in
            guard let best = observation.topCandidates(1).first else { return nil }
            var line = OCRLine(text: logicalOrder(best.string),
                               box: observation.boundingBox,
                               confidence: best.confidence)
            line.words = words(of: best)
            return line
        }
        // Top-to-bottom, then left-to-right for anything sharing a baseline.
        .sorted { a, b in
            if abs(a.box.midY - b.box.midY) > 0.01 { return a.box.midY > b.box.midY }
            return a.box.minX < b.box.minX
        }
    }

    /// Every word of a recognised line with its own box. One line from Vision
    /// can hold two labels that happen to share a baseline, and only the word
    /// boxes show the gap between them. All or nothing: if any word has no
    /// box, the caller falls back to the whole line.
    static func words(of text: VNRecognizedText) -> [OCRWord] {
        let string: String = text.string
        // a line with Arabic in it has its words reordered; keep it whole
        guard !hasArabic(string) else { return [] }
        var out: [OCRWord] = []
        var index: String.Index = string.startIndex
        while index < string.endIndex {
            while index < string.endIndex && string[index].isWhitespace {
                index = string.index(after: index)
            }
            guard index < string.endIndex else { break }
            var end: String.Index = index
            while end < string.endIndex && !string[end].isWhitespace {
                end = string.index(after: end)
            }
            let range: Range<String.Index> = index..<end
            guard let observed = try? text.boundingBox(for: range) else { return [] }
            let box: CGRect = observed.boundingBox
            guard box.width > 0, box.height > 0 else { return [] }
            out.append(OCRWord(text: String(string[range]), box: box))
            index = end
        }
        return out
    }

    /// Undo the visual ordering of a mixed-script line. A line in one script is
    /// already logical - Vision handles pure Arabic correctly - so only a line
    /// carrying both is touched, and a line carrying neither is left alone.
    public static func logicalOrder(_ text: String) -> String {
        let tokens = text.split(separator: " ").map(String.init)
        guard tokens.count > 1 else { return text }
        let arabic = tokens.filter(hasArabic)
        guard !arabic.isEmpty, arabic.count < tokens.count else { return text }

        var out: [String] = []
        var i = tokens.count - 1
        while i >= 0 {
            if hasArabic(tokens[i]) {
                out.append(tokens[i])
                i -= 1
            } else {
                // a Latin run reads left-to-right even inside a right-to-left
                // line, so put it back the way round it was written
                var j = i
                while j >= 0 && !hasArabic(tokens[j]) { j -= 1 }
                out.append(contentsOf: tokens[(j + 1)...i])
                i = j
            }
        }
        return out.joined(separator: " ")
    }

    static func hasArabic(_ s: String) -> Bool {
        s.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x0600...0x06FF).contains(v) || (0x0750...0x077F).contains(v)
                || (0xFB50...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
        }
    }

    /// The whole page as text, one line per recognised line.
    public static func readText(_ image: CGImage,
                                languages: [String] = languages) throws -> String {
        try read(image, languages: languages).map(\.text).joined(separator: "\n")
    }
}
