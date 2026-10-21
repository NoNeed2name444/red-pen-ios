import Foundation

/// What kind of cards to make from a lecture.
enum CardStyle: String, CaseIterable, Identifiable {
    case mixed, qa, cloze, image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixed: return "Mixed (all types)"
        case .qa: return "Question & answer"
        case .cloze: return "Cloze deletion"
        case .image: return "Image occlusion"
        }
    }

    /// Whether the model writes any text cards for this style.
    var writesText: Bool { self != .image }
    /// Whether the lecture's labelled diagrams become cards.
    var usesDiagrams: Bool { self == .mixed || self == .image }
}

/// Cards made from the lecture's labelled diagrams, with the pictures they
/// point into (`imageIndex` is a position in `images`).
struct DiagramCards: Equatable {
    var cards: [AnkiCard] = []
    var images: [String] = []
    /// Whether they go into the set being made.
    var included = false
}
