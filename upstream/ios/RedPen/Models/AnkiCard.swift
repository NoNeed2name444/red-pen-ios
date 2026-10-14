import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The three card shapes: a question with bullet answers, a cloze-deletion
/// sentence, or an image with a hidden region to identify.
enum AnkiCardType: String, Codable, CaseIterable {
    case qa, cloze, occlusion
}

/// A normalized bounding box (0...1 fractions of image width and height).
struct OcclusionBox: Codable, Hashable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    /// Convenience for drawing: the box's rect within a given image size.
    func rect(in size: CGSize) -> CGRect {
        let left: CGFloat = CGFloat(x) * size.width
        let top: CGFloat = CGFloat(y) * size.height
        let width: CGFloat = CGFloat(w) * size.width
        let height: CGFloat = CGFloat(h) * size.height
        return CGRect(x: left, y: top, width: width, height: height)
    }
}

/// One flashcard. Fields are blank or nil depending on `type`.
struct AnkiCard: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var type: AnkiCardType

    /// "qa": the question. "occlusion": the question about the hidden region,
    /// falling back to "What's hidden here?" when blank.
    var front: String = ""
    /// "qa" only: 1-4 short answer bullets. `**term**` markers highlight the
    /// tested word or number.
    var bullets: [String] = []
    /// "cloze" only: the sentence with `{{c1::term}}`-style blanks.
    var clozeText: String = ""
    /// All types: optional 1-2 sentence "why / how" shown after reveal.
    var why: String = ""
    /// Index into the owning StudySet's images: an occlusion card's picture,
    /// or one an imported basic or cloze card carried (audit #14).
    var imageIndex: Int?
    /// A basic or cloze card's picture belongs to the answer, as it was on
    /// the back of the Anki card it came from: shown only once revealed, so
    /// it never gives the answer away. Nil on the front, and on cards saved
    /// before this existed.
    var pictureOnBack: Bool? = nil
    /// "occlusion" only: the region to hide until revealed.
    var occlusion: OcclusionBox?
    /// Where this came from, when it was made from a file - "Lupus, p.14".
    ///
    /// A generated card is only as trustworthy as the page behind it, and
    /// without this a card that looks wrong can only be distrusted, not
    /// checked. Optional because a hand-typed card has no source, and because
    /// libraries saved before this existed decode without it.
    var source: String?
    /// "occlusion" only: the masks over every OTHER tested label on the same
    /// picture. They stay covered after the card is revealed, so a neighbouring
    /// label can never give this card's answer away. Empty on cards saved
    /// before this existed; those take the masks from the set's other cards on
    /// the same picture (OcclusionCovers.others).
    var siblings: [OcclusionBox] = []
    /// Labels for finding and filtering - "#AK_Step1::Cardio", "pharm".
    /// Kept from an Anki deck's notes on import and written back on export.
    /// Optional, so cards saved before tags existed decode, and an untagged
    /// card adds nothing to the library file.
    var tags: [String]? = nil

    var displayFront: String {
        if type == .occlusion, front.trimmingCharacters(in: .whitespaces).isEmpty {
            return "What's hidden here?"
        }
        return front
    }
}

/// A card's live position in a review session. Kept separate from the card so
/// the same deck can be reviewed again with a fresh sitting; what carries over
/// between sittings is the ReviewRecord, not this.
struct AnkiQueueItem: Identifiable {
    let id: UUID
    var card: AnkiCard
    var due: Date
    var intervalMin: Double

    init(card: AnkiCard, due: Date = Date(), intervalMin: Double = 0) {
        self.id = card.id
        self.card = card
        self.due = due
        self.intervalMin = intervalMin
    }
}

/// Read tolerantly, like StudySet: a card from another version of the app
/// may lack a field this one has.
extension AnkiCard {
    private enum Keys: String, CodingKey {
        case id, type, front, bullets, clozeText, why, imageIndex, pictureOnBack, occlusion, source, siblings, tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(type: try c.decode(AnkiCardType.self, forKey: .type))
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        front = try c.decodeIfPresent(String.self, forKey: .front) ?? ""
        bullets = try c.decodeIfPresent([String].self, forKey: .bullets) ?? []
        clozeText = try c.decodeIfPresent(String.self, forKey: .clozeText) ?? ""
        why = try c.decodeIfPresent(String.self, forKey: .why) ?? ""
        imageIndex = try c.decodeIfPresent(Int.self, forKey: .imageIndex)
        pictureOnBack = try? c.decodeIfPresent(Bool.self, forKey: .pictureOnBack)
        occlusion = try c.decodeIfPresent(OcclusionBox.self, forKey: .occlusion)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        siblings = (try? c.decodeIfPresent([OcclusionBox].self, forKey: .siblings)) ?? []
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? nil
    }
}

// MARK: - where a card's picture goes

extension AnkiCard {
    /// Whether the picture is drawn above the question: an occlusion card's
    /// always is (its covers are the question), any other card's unless it
    /// came from the answer side.
    var pictureOnFront: Bool { type == .occlusion || pictureOnBack != true }

    /// The picture an imported note's card shows and whether it is the
    /// answer's: the first one on the question side that the package
    /// carries, else the first on the answer side.
    static func picture(front: [String], back: [String],
                        available: (String) -> Bool) -> (name: String?, onBack: Bool) {
        if let shown = front.first(where: available) { return (shown, false) }
        if let shown = back.first(where: available) { return (shown, true) }
        return (nil, false)
    }
}

// MARK: - a cloze sentence, in pieces

extension AnkiCard {
    /// One run of a cloze sentence: plain text, or a gap with its answer and
    /// the hint Anki writes after a second `::` ({{c1::answer::hint}}).
    struct ClozePiece: Equatable {
        var text: String
        var isGap: Bool
        var hint: String? = nil
    }

    /// The sentence split at its gaps, so a card can show it as Anki does: the
    /// same words in the same place, the gap hidden and then filled in where
    /// it stood, rather than the whole sentence written out again below.
    static func clozePieces(_ text: String) -> [ClozePiece] {
        guard let re = try? NSRegularExpression(pattern: #"\{\{c\d+::([\s\S]+?)(?:::([\s\S]*?))?\}\}"#) else {
            return [ClozePiece(text: text, isGap: false)]
        }
        let ns = text as NSString
        var out: [ClozePiece] = []
        var at = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > at {
                out.append(ClozePiece(text: ns.substring(with: NSRange(location: at, length: m.range.location - at)),
                                      isGap: false))
            }
            let hintRange = m.range(at: 2)
            let hint: String? = hintRange.location == NSNotFound ? nil
                : ns.substring(with: hintRange).trimmingCharacters(in: .whitespaces)
            out.append(ClozePiece(text: ns.substring(with: m.range(at: 1)), isGap: true,
                                  hint: (hint?.isEmpty ?? true) ? nil : hint))
            at = m.range.location + m.range.length
        }
        if at < ns.length { out.append(ClozePiece(text: ns.substring(from: at), isGap: false)) }
        return out
    }

    /// How a gap reads before it is revealed: Anki's "[...]", or its hint.
    static func clozeGap(_ piece: ClozePiece) -> String {
        "[" + (piece.hint ?? "...") + "]"
    }
}
