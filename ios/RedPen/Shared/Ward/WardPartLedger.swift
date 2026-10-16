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
    /// A live part's latest reported frame, kept whether or not the page is
    /// at rest so the next rest can book it.
    struct Sighting: Equatable {
        var name: String
        var rect: CGRect
        var reach: Double
        var scale: Double
    }

    struct Entry: Equatable {
        var name: String
        var rect: CGRect
        var top: Double

        init(name: String, rect: CGRect, top: Double) {
            self.name = name
            self.rect = rect
            self.top = top
        }

        init(sighting: Sighting) {
            var face: CGRect = sighting.rect
            face.origin.y -= CGFloat(sighting.reach)
            face.size.height += CGFloat(sighting.reach)
            self.name = sighting.name
            self.rect = face
            self.top = wardBookedTop(Double(face.minY), scale: sighting.scale)
        }
    }

    private(set) var entries: [Key: Entry] = [:]
    private(set) var sightings: [Key: Sighting] = [:]
    /// The tops last published at rest.
    private(set) var told: [Double] = []
    /// The page's settled cut (global points), for the at-rest drop loop guard.
    var cut: Double?

    /// The sorted, distinct booked tops.
    var tops: [Double] { Array(Set(entries.values.map(\.top))).sorted() }

    /// Records a sighting of one part and, at rest, books it from that
    /// sighting and reports whether the published tops changed. Empty frames
    /// are not kept.
    @discardableResult
    mutating func set(_ key: Key, _ sighting: Sighting, atRest: Bool = true) -> Bool {
        guard !sighting.rect.isEmpty else { return false }
        sightings[key] = sighting
        guard atRest else { return false }
        entries[key] = Entry(sighting: sighting)
        return publish()
    }

    /// Books one part again from a sighting it is handed.
    @discardableResult
    mutating func book(_ key: Key, _ sighting: Sighting, atRest: Bool = true) -> Bool {
        set(key, sighting, atRest: atRest)
    }

    /// One part's frame; `reach` is how far its face stands out above
    /// its frame (a row's tile). Empty frames are not kept.
    @discardableResult
    mutating func set(_ key: Key, name: String, rect: CGRect, reach: Double, scale: Double,
                      atRest: Bool = true) -> Bool {
        set(key, Sighting(name: name, rect: rect, reach: reach, scale: scale), atRest: atRest)
    }

    /// Books every live sighting again at once (used when the list comes to
    /// rest) and reports whether the published tops changed.
    @discardableResult
    mutating func rebook() -> Bool {
        entries = sightings.mapValues(Entry.init)
        return publish()
    }

    /// Drops a part that went away. At rest, a part whose booked face lies
    /// wholly at or below the page's current cut is hidden by the cut rather
    /// than gone, so it keeps its entry and its sighting: the next rest books
    /// it where it was, and the cut never falls back to show it again (a
    /// cut/drop loop at rest). While moving, the book changes without
    /// publishing; the next rest publishes.
    @discardableResult
    mutating func drop(_ key: Key, atRest: Bool = true, cut: Double? = nil) -> Bool {
        if atRest, let activeCut = cut ?? self.cut, let entry = entries[key],
           Double(entry.rect.minY) >= activeCut, Double(entry.rect.maxY) >= activeCut {
            return false
        }
        sightings[key] = nil
        entries[key] = nil
        guard atRest else { return false }
        return publish()
    }

    /// A new page: empties entries, sightings and the cut, and reports whether
    /// the published tops changed.
    @discardableResult
    mutating func clear() -> Bool {
        entries = [:]
        sightings = [:]
        cut = nil
        return publish()
    }

    private mutating func publish() -> Bool {
        let now: [Double] = tops
        guard now != told else { return false }
        told = now
        return true
    }
}
