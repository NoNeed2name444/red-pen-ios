import Foundation
import CoreGraphics

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
        CGRect(x: x * size.width, y: y * size.height,
               width: w * size.width, height: h * size.height)
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
    /// "occlusion" only: index into the owning StudySet's images.
    var imageIndex: Int?
    /// "occlusion" only: the region to hide until revealed.
    var occlusion: OcclusionBox?
    /// Where this came from, when it was made from a file - "Lupus, p.14".
    ///
    /// A generated card is only as trustworthy as the page behind it, and
    /// without this a card that looks wrong can only be distrusted, not
    /// checked. Optional because a hand-typed card has no source, and because
    /// libraries saved before this existed decode without it.
    var source: String?

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
        case id, type, front, bullets, clozeText, why, imageIndex, occlusion, source
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
        occlusion = try c.decodeIfPresent(OcclusionBox.self, forKey: .occlusion)
        source = try c.decodeIfPresent(String.self, forKey: .source)
    }
}
