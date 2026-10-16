import Foundation

// The book of parts that can meet home's cut (WardPartBook, HomeFit), without
// the views, so it is checked on Linux (HomeFitTests). Foundation only, and
// not in HomeFit's file: WardControls is kept where HomeFit is dropped.

/// The top a part is booked at: floored onto the pixel grid, never
/// rounded to the nearest half point, so a booked top is never below the
/// real one (682.78 at 3x books 682.667, not 683: the part drawn at
/// 682.67 would otherwise show a pixel over a cut at 683).
func wardBookedTop(_ value: Double, scale: Double) -> Double {
    guard value.isFinite else { return value }
    guard scale > 0, scale.isFinite else { return value.rounded(.down) }
    return (value * scale + 1e-6).rounded(.down) / scale
}

/// The parts of a page that reported themselves at rest, by key (the
/// view's id): the logic of WardPartBook without the views (HomeFit's
/// settledCut reads its tops). A part that
/// goes away is dropped; a new page clears the lot.
struct WardPartLedger<Key: Hashable> {
    struct Entry: Equatable {
        var name: String
        var rect: CGRect
        var top: Double
    }

    private(set) var entries: [Key: Entry] = [:]

    /// The sorted, distinct booked tops.
    var tops: [Double] { Array(Set(entries.values.map(\.top))).sorted() }

    /// One part's frame; `reach` is how far its face stands out above
    /// its frame (a row's tile). Empty frames are not kept.
    mutating func set(_ key: Key, name: String, rect: CGRect, reach: Double, scale: Double) {
        guard !rect.isEmpty else { return }
        var face: CGRect = rect
        face.origin.y -= CGFloat(reach)
        face.size.height += CGFloat(reach)
        entries[key] = Entry(name: name, rect: face,
                             top: wardBookedTop(Double(face.minY), scale: scale))
    }

    mutating func drop(_ key: Key) { entries[key] = nil }

    mutating func clear() { entries = [:] }
}
