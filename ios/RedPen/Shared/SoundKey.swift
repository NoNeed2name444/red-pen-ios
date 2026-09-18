// Red Pen · the sound of a word, whatever script it is written in
//
// The recogniser writes what it hears in Arabic letters. The lecturer's slides,
// the glossary and the exam write the same words in English. Compared as text
// these never match; compared as consonant skeletons they are one word, and
// that is the whole trick the transcript repair and the on-device learning rest
// on.
//
// The skeleton is lossy ON PURPOSE. Arabic omits short vowels, so keeping them
// would mean comparing letters the writer never wrote. The cost is real
// collisions - q and k fold together, so قلب and كلب are one sound - and every
// caller is built knowing that: a lookup only rewrites a transcript where the
// evidence is a person's own spelling, never on the skeleton alone.
//
// This must agree exactly with sound() in pipeline/consensus.py. A table the
// phone learns is read by the committee and vice versa, so two implementations
// that disagree on one word make both tables wrong in ways nobody would notice.
import Foundation

public enum SoundKey {

    private static let arabicToLatin: [Character: String] = [
        "ء": "'", "آ": "a", "أ": "a", "ؤ": "w", "إ": "i", "ئ": "y", "ا": "a",
        "ب": "b", "ة": "a", "ت": "t", "ث": "th", "ج": "g", "ح": "h", "خ": "kh",
        "د": "d", "ذ": "z", "ر": "r", "ز": "z", "س": "s", "ش": "sh", "ص": "s",
        "ض": "d", "ط": "t", "ظ": "z", "ع": "a", "غ": "gh", "ف": "f", "ق": "k",
        "ك": "k", "ل": "l", "م": "m", "ن": "n", "ه": "h", "و": "w", "ى": "a",
        "ي": "y",
    ]
    /// harakat, the hamza and madda marks NFKD frees from a carrier, the
    /// superscript alef, and the tatweel stretcher
    private static let marks: ClosedRange<UInt32> = 0x064B...0x0655
    private static let vowels = Set("aeiouwy")
    private static let digraphs = [("sh", "$"), ("th", "0"), ("ph", "f"),
                                   ("gh", "g"), ("kh", "X"), ("ck", "k"), ("qu", "k")]
    private static let single: [Character: String] = [
        "c": "k", "q": "k", "z": "s", "j": "g", "v": "f", "p": "b", "x": "ks",
    ]

    static func isArabicLetter(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else { return false }
        return (0x0621...0x064A).contains(v) || (0x066E...0x06D3).contains(v)
    }

    public static func hasArabic(_ s: String) -> Bool { s.contains(where: isArabicLetter) }

    /// Egyptian glues و/ف/ب/ل onto the definite article, so والـ is the article
    /// wearing a conjunction. Both come off before the sound is taken.
    public static func stripArticle(_ s: String) -> String {
        var t = Substring(s)
        if let first = t.first, "وفبل".contains(first), t.count > 3 {
            let rest = t.dropFirst()
            if rest.hasPrefix("ال") { t = rest }
        }
        if t.hasPrefix("الـ") { return String(t.dropFirst(3)) }
        if t.hasPrefix("ال") { return String(t.dropFirst(2)) }
        return String(t)
    }

    static func fold(_ s: String) -> String {
        var out = ""
        for ch in s.decomposedStringWithCanonicalMapping {
            guard let v = ch.unicodeScalars.first?.value else { continue }
            if marks.contains(v) || v == 0x0670 || v == 0x0640 { continue }
            switch ch {
            case "ى": out.append("ي")      // alef maqsura reads as ya
            case "ة": out.append("ه")      // ta marbuta reads as ha
            default: out.append(ch)
            }
        }
        return out
    }

    static func romanize(_ s: String) -> String {
        var out = ""
        for ch in s {
            if let latin = arabicToLatin[ch] { out += latin }
            else if !isArabicLetter(ch) { out.append(ch) }
        }
        return out
    }

    /// 'ch' is /k/ in Greek-derived medical words (chronic, chloride) and a
    /// different sound otherwise, so it splits on the letter that follows it.
    static func foldCh(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "c", s.index(after: i) < s.endIndex, s[s.index(after: i)] == "h" {
                let after = s.index(i, offsetBy: 2)
                let next = after < s.endIndex ? s[after] : " "
                out += (next == "r" || next == "l") ? "k" : "$"
                i = after
                continue
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }

    static func skeleton(_ raw: String) -> String {
        var s = raw.lowercased().map { ch -> Character in
            (ch.isLetter && ch.isASCII) || ch == "'" || ch == " " ? ch : " "
        }.reduce(into: "") { $0.append($1) }
        s = foldCh(s)
        for (from, to) in digraphs { s = s.replacingOccurrences(of: from, with: to) }
        s = s.reduce(into: "") { out, ch in out += single[ch] ?? String(ch) }
        s = s.filter { !vowels.contains($0) && $0 != "'" }
        // collapse runs: the recogniser's split keeps a doubled letter across a
        // space that the joined word has already lost
        var collapsed = ""
        for ch in s where collapsed.last != ch { collapsed.append(ch) }
        return collapsed.trimmingCharacters(in: .whitespaces)
    }

    /// The key a token is stored and looked up under.
    public static func of(_ token: String) -> String {
        let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?\"'()[]{}…،؛؟-"))
        guard hasArabic(bare) else { return skeleton(bare.lowercased()) }
        return skeleton(romanize(fold(stripArticle(bare))))
    }

    public static func of(span: [String]) -> String {
        span.map { of($0) }.joined(separator: " ")
    }

    /// The same sound with the word boundary removed. The recogniser splits
    /// words it heard as one - ميكو كوتينيوس is `mucocutaneous` - so a two-token
    /// span and a one-word spelling have to be comparable, and joining keeps a
    /// doubled letter across the seam that the joined word never had.
    public static func collapsed(_ key: String) -> String {
        var out = ""
        for ch in key where ch != " " && out.last != ch { out.append(ch) }
        return out
    }
}
