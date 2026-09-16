import Foundation
import CoreGraphics

/// Matches the three card shapes the web app generates in `buildAnkiPrompt`
/// / renders in `renderAnkiCard()`: a question with bullet-point answers
/// ("qa"), a cloze-deletion sentence ("cloze"), or an image with a hidden
/// region to identify ("occlusion").
enum AnkiCardType: String, Codable, CaseIterable {
    case qa, cloze, occlusion
}

/// A normalized bounding box (0…1 fractions of image width/height) — same
/// shape as the web app's `c.occlusion` (`{x, y, w, h}`).
struct OcclusionBox: Codable, Hashable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    /// Convenience for drawing: the box's rect within a given image size.
    func rect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height)
    }
}

/// One flashcard. Fields are optional/blank depending on `type`, exactly as
/// the web app's card objects only populate the fields relevant to their
/// type — see the three branches of `renderAnkiCard()`.
struct AnkiCard: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var type: AnkiCardType

    /// "qa": the question. "occlusion": the clinical question about the
    /// hidden region (falls back to "What's hidden here?" when blank, same
    /// as the web app).
    var front: String = ""
    /// "qa" only: 1-4 short answer bullets. `**term**` markers highlight the
    /// tested word/number, same convention as the web app's `inlineAnkiHl`.
    var bullets: [String] = []
    /// "cloze" only: the full sentence with `{{c1::term}}`-style blanks.
    var clozeText: String = ""
    /// All types: optional 1-2 sentence "why / how" shown after reveal.
    var why: String = ""
    /// "occlusion" only: index into the owning StudySet's images.
    var imageIndex: Int?
    /// "occlusion" only: the region to hide until revealed.
    var occlusion: OcclusionBox?

    var displayFront: String {
        if type == .occlusion, front.trimmingCharacters(in: .whitespaces).isEmpty {
            return "What's hidden here?"
        }
        return front
    }
}

/// A card's live position in a review session — the native equivalent of
/// the web app's `state.ankiQueue` entries (`{card, due, intervalMin}`).
/// Kept separate from `AnkiCard` itself so the same card deck can be
/// reviewed repeatedly with a fresh schedule each session, matching
/// `openAnkiReview()` re-seeding `state.ankiQueue` from `state.ankiCards`.
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
