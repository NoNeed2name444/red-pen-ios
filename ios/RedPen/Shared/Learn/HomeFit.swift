import Foundation

// Home's first screen on a short phone. The round card, its Start ward
// round button and the bar at the bottom (New set over the dock) have to
// share the height: at the iPhone SE's 647 points under the status bar the
// button was cut by the bar and New set sat on the card's edge (the owner's
// before/after sheet, 15 Oct). On a short window New set moves up beside
// the account button, and the round shows its first two beds, so the card
// ends above the dock. The preview checks the result with `faults`.

enum HomeFit {
    /// Window heights (points, inside the safe area) under this are short:
    /// an iPhone SE (647), a mini (728), a 16e (763). A Pro (778) is not.
    static let shortHeight: Double = 770
    /// How many beds the round shows on a short window.
    static let shortBeds: Int = 2
    /// The least room between the card's end and the bar.
    static let gap: Double = 8

    /// Whether a window this tall is short. A wide iPad keeps New set at
    /// the bottom beside the rail, where it has the room.
    static func isShort(height: Double, broad: Bool) -> Bool {
        !broad && height > 0 && height < shortHeight
    }

    /// How many of the round's beds are shown.
    static func shownBeds(_ count: Int, short: Bool) -> Int {
        short ? min(count, shortBeds) : count
    }

    /// A laid-out thing's edges, in one coordinate space.
    struct Box: Equatable {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double

        func overlaps(_ other: Box) -> Bool {
            minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
        }

        var text: String { "\(Int(minY.rounded()))-\(Int(maxY.rounded()))" }
    }

    /// What is wrong with home as laid out at rest; empty when the round
    /// card and its button end above the bar and nothing at the bottom
    /// sits on the card.
    static func faults(card: Box?, start: Box?, bar: Box?, newSet: Box?) -> [String] {
        guard let card else { return ["no round card was laid out"] }
        guard let start else { return ["no Start ward round button was laid out"] }
        guard let bar else { return ["no bottom bar was laid out"] }
        var out: [String] = []
        if start.maxY + gap > bar.minY {
            out.append("Start ward round (\(start.text)) is cut by the bar from \(Int(bar.minY.rounded()))")
        }
        if card.maxY + gap > bar.minY {
            out.append("the round card (\(card.text)) runs under the bar from \(Int(bar.minY.rounded()))")
        }
        if let newSet, newSet.overlaps(card) {
            out.append("New set (\(newSet.text)) sits on the round card (\(card.text))")
        }
        return out
    }
}
