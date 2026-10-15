import Foundation

// Home's first screen on a short phone. The round card, its Start ward
// round button and the bar at the bottom (New set over the dock) have to
// share the height: at the iPhone SE's 647 points under the status bar the
// button was cut by the bar and New set sat on the card's edge (the owner's
// before/after sheet, 15 Oct). On a short window New set moves up beside
// the account button, and the round shows its first two beds, so the card
// ends above the dock.
//
// The page ends at a clean cut `cutRoom` above the bar (`shown` is how
// tall it is): nothing scrolled under New set or the dock shows, a row
// past the cut is off screen to taps and VoiceOver, and there is no strip
// or line under them, so the page reads unbroken to the bottom (the owner,
// 9 and 14 Oct). The preview checks the result with `faults`: the card
// above the cut, no sliver of the tiles peeking over it, New set off the
// card, and no word of home's text broken across two lines.

enum HomeFit {
    /// Window heights (points, inside the safe area) under this are short:
    /// an iPhone SE (647), a mini (728), a 16e (763). A Pro (778) is not.
    static let shortHeight: Double = 770
    /// How many beds the round shows on a short window.
    static let shortBeds: Int = 2
    /// The least room between the card's end and the bar.
    static let gap: Double = 8
    /// The room between the page's cut and the bar's top.
    static let cutRoom: Double = 12
    /// The least of a row that may show over the cut at rest: less reads as
    /// a stray line, not as more to scroll to.
    static let leastShown: Double = 12

    /// Where the page's cut falls, from the page's top: `cutRoom` above the
    /// bar, however tall the page's own frame is (a list runs on past it,
    /// under the bar). Nil, no cut: there is no bar (the keyboard is up,
    /// the sky is behind) or it has not been measured. Global points in.
    /// `tops` are the global tops, at rest, of the rows and parts that can
    /// meet the cut (`settledCut`).
    static func cut(barTop: Double?, pageTop: Double, tops: [Double] = []) -> Double? {
        guard let barTop, barTop.isFinite, barTop > pageTop else { return nil }
        return max(0, settledCut(barTop - cutRoom, tops: tops) - pageTop)
    }

    /// How tall a page with this much room is, from its top: down to the
    /// cut, or all of it.
    static func shown(barTop: Double?, pageTop: Double, pageHeight: Double, tops: [Double] = []) -> Double {
        cut(barTop: barTop, pageTop: pageTop, tops: tops).map { min(pageHeight, $0) } ?? pageHeight
    }

    /// The cut (global points) once no part shows less than `leastShown`
    /// over it: where a part's top falls within `leastShown` above the cut,
    /// the cut moves up to that top, so the part is wholly past it and no
    /// stray sliver shows. A part's top at the cut, or `leastShown` or more
    /// above it, leaves the cut where it is. Moving the cut up can bring
    /// another top into that band, so it goes on until none is.
    static func settledCut(_ cut: Double, tops: [Double]) -> Double {
        var at: Double = cut
        var moved: Bool = true
        while moved {
            moved = false
            for top in tops where top.isFinite && top < at && at - top < leastShown {
                at = top
                moved = true
            }
        }
        return at
    }

    /// Whether a window this tall is short. A wide iPad keeps New set at
    /// the bottom beside the rail, where it has the room.
    static func isShort(height: Double, broad: Bool) -> Bool {
        !broad && height > 0 && height < shortHeight
    }

    /// How many of the round's beds are shown.
    /// `trimmed` is how many more were taken off, one at a time, while the
    /// page's cut sliced Start ward round at large text (`slices`); one
    /// bed always stays.
    static func shownBeds(_ count: Int, short: Bool, trimmed: Int = 0) -> Int {
        let base: Int = short ? min(count, shortBeds) : count
        return max(min(base, 1), base - max(0, trimmed))
    }

    /// Whether a cut at `cut` falls inside something spanning `minY` to
    /// `maxY`: neither wholly above it nor wholly below.
    static func slices(minY: Double, maxY: Double, cut: Double) -> Bool {
        minY < cut && maxY > cut
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

    /// A row or part of the page that can meet the cut, as laid out at rest:
    /// a Practise tile, a set's row, the Due chip inside the round card.
    struct Part: Equatable {
        var name: String
        var box: Box
    }

    /// A text as laid out, and the width of its widest word on its own:
    /// narrower than that word, the text has to break inside it ("No
    /// strea / k yet" on the Vitals tile).
    struct Words: Equatable {
        var name: String
        var width: Double
        var widest: Double
    }

    /// What is wrong with home as laid out at rest; empty when it fits.
    ///
    /// At the standard text sizes the round card and its Start ward round
    /// button end above the page's cut, so the first screen holds the whole
    /// round. At the larger sizes (`large`: XL and up) the page may run on
    /// past the cut and scroll, as Apple's large-text guidance expects, but
    /// the cut must not slice the Start button (whole above it or wholly
    /// out of sight) and no sliver of the card or the tiles may peek over
    /// it. At any size New set sits on no part of the card that shows, and
    /// no word of home's text is broken across two lines.
    ///
    /// `pageEnd` is where the page was actually cut, when it was measured
    /// (the layout may have moved the cut up, `settledCut`): the cut is the
    /// higher of it and the one the bar gives. `parts` are the other rows
    /// and parts that can meet the cut: none may show under `leastShown`
    /// over it.
    static func faults(card: Box?, start: Box?, bar: Box?, newSet: Box?, tiles: Box? = nil,
                       large: Bool = false, words: [Words] = [],
                       pageEnd: Double? = nil, parts: [Part] = []) -> [String] {
        guard let card else { return ["no round card was laid out"] }
        guard let start else { return ["no Start ward round button was laid out"] }
        guard let bar else { return ["no bottom bar was laid out"] }
        var out: [String] = []
        let cut: Double = min(bar.minY - cutRoom, pageEnd ?? .infinity)
        let at: String = "\(Int(cut.rounded()))"
        if large {
            if slices(minY: start.minY, maxY: start.maxY, cut: cut) {
                out.append("Start ward round (\(start.text)) is sliced by the page's cut at \(at)")
            }
        } else {
            if start.maxY > cut {
                out.append("Start ward round (\(start.text)) runs past the page's cut at \(at), above the bar")
            }
            if card.maxY > cut {
                out.append("the round card (\(card.text)) runs past the page's cut at \(at)")
            }
        }
        var named: [(String, Box?)] = [("the round card", card), ("the tiles", tiles)]
        named += parts.map { ($0.name, Optional($0.box)) }
        for (name, box) in named {
            guard let box, box.minY < cut, cut - box.minY < leastShown else { continue }
            let line: String = "a sliver of \(name) (\(box.text)) peeks over the page's cut at \(at)"
            if !out.contains(line) { out.append(line) }
        }
        // the part of the card that shows: down to the cut
        if let newSet, card.minY < cut {
            var shown: Box = card
            shown.maxY = min(card.maxY, cut)
            if newSet.overlaps(shown) {
                out.append("New set (\(newSet.text)) sits on the round card (\(shown.text))")
            }
        }
        for w in words where w.widest > w.width + 0.5 {
            out.append("\(w.name) breaks inside a word: its widest word needs \(Int(w.widest.rounded())) pt, "
                       + "it has \(Int(w.width.rounded()))")
        }
        return out
    }
}
