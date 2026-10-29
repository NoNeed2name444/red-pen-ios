import Foundation

// Home's first screen on a short phone. The round card, its Start ward
// round button and the bar at the bottom (New set over the dock) have to
// share the height: at the iPhone SE's 647 points under the status bar the
// button was cut by the bar and New set sat on the card's edge (the owner's
// before/after sheet, 15 Oct). On a short window New set moves up beside
// the account button, and the round shows its first two beds, so the card
// ends above the dock.
//
// The page is not cut above the bar (the owner, 22 Oct: the band under
// New set and the tabs was wrong). The list runs on to the window's bottom
// edge behind New set and the dock, which float on the page with nothing
// behind them but the page itself; a row as tall as the bar, and `endRoom`
// more, ends the list (`endSpace`), so the last tile scrolls wholly clear
// above them (`lastRowBottom`). The preview checks the first screen with
// `faults`: at the standard sizes the card and its button end `barRoom`
// above the bar, at the large sizes the bar's line slices no button, New
// set sits on no part of the card above that line, and no word of home's
// text is broken across two lines.

enum HomeFit {
    /// Window heights (points, inside the safe area) under this are short:
    /// an iPhone SE (647), a mini (728), a 16e (763). A Pro (778) is not.
    static let shortHeight: Double = 770
    /// How many beds the round shows on a short window.
    static let shortBeds: Int = 2
    /// The least room between the card's end and the bar.
    static let gap: Double = 8
    /// At the standard text sizes, the least room between the round card's
    /// end (and its Start ward round button's) and the bar's top. Not a line
    /// on screen: where the first screen's round has to end.
    static let barRoom: Double = 12
    /// The room under the last row once the list has scrolled to its end.
    static let endRoom: Double = 24

    /// The bar's line: `barRoom` above its top (global points).
    static func barLine(barTop: Double) -> Double { barTop - barRoom }

    /// How tall the row that ends the list is: as tall as the bar (New set
    /// over the dock, or the selection bar), and `endRoom` more. Nothing
    /// cuts the page, so this row is all that keeps the last tile clear of
    /// the bar: the list's own inset for the bar is not relied on.
    static func endSpace(barHeight: Double) -> Double {
        max(0, barHeight.isFinite ? barHeight : 0) + endRoom
    }

    /// Where the last row's bottom rests once the list has scrolled to its
    /// end, the list running on to the bar's bottom (it is not cut above the
    /// bar). `insetHonoured`: the list also keeps its own inset for the bar,
    /// which only lifts the row further. Global points.
    static func lastRowBottom(barTop: Double, barHeight: Double, insetHonoured: Bool = false) -> Double {
        let listEnd: Double = barTop + max(0, barHeight)
        return listEnd - endSpace(barHeight: barHeight) - (insetHonoured ? max(0, barHeight) : 0)
    }

    /// Whether a push and back showed home covered by the pushed page: a
    /// part of home left the book during the push, or, when every face
    /// booked before it lay wholly at or below home's cut, at least one
    /// went away and was kept by that cut, all the book can show then
    /// (WardPartLedger.drop). `faces`: the tops of the faces booked before
    /// the push; `cut`: home's cut then (nil, not cut); `removed`, `kept`:
    /// the book's drops during the push.
    static func pushCovered(faces: [Double], cut: Double?, removed: Int, kept: Int) -> Bool {
        if removed > 0 { return true }
        guard let cut, !faces.isEmpty, kept > 0 else { return false }
        return faces.allSatisfy { $0 + 1e-6 >= cut }
    }

    /// Whether a window this tall is short. A wide iPad keeps New set at
    /// the bottom beside the rail, where it has the room.
    static func isShort(height: Double, broad: Bool) -> Bool {
        !broad && height > 0 && height < shortHeight
    }

    /// How many of the round's beds are shown.
    /// `trimmed` is how many more were taken off, one at a time, while the
    /// bar's line sliced Start ward round at large text (`slices`); one
    /// bed always stays.
    static func shownBeds(_ count: Int, short: Bool, trimmed: Int = 0) -> Int {
        let base: Int = short ? min(count, shortBeds) : count
        return max(min(base, 1), base - max(0, trimmed))
    }

    /// Whether a line at `cut` falls inside something spanning `minY` to
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

    /// A row or part of the page, as laid out at rest: a Practise tile, a
    /// set's row, the Due chip inside the round card.
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
    /// button end `barRoom` above the bar, so the first screen holds the
    /// whole round. At the larger sizes (`large`: XL and up) the page may
    /// run on behind the bar and scroll, as Apple's large-text guidance
    /// expects, but the bar's line must not slice the Start button (whole
    /// above it or wholly past it). At any size New set sits on no part of
    /// the card above the bar's line, and no word of home's text is broken
    /// across two lines. Rows and tiles past the line are not faults: they
    /// pass behind New set and the dock, and scroll clear (`endSpace`).
    static func faults(card: Box?, start: Box?, bar: Box?, newSet: Box?,
                       large: Bool = false, words: [Words] = []) -> [String] {
        guard let card else { return ["no round card was laid out"] }
        guard let start else { return ["no Start ward round button was laid out"] }
        guard let bar else { return ["no bottom bar was laid out"] }
        var out: [String] = []
        let line: Double = barLine(barTop: bar.minY)
        let at: String = "\(Int(line.rounded()))"
        if large {
            if slices(minY: start.minY, maxY: start.maxY, cut: line) {
                out.append("Start ward round (\(start.text)) is sliced by the bar's line at \(at)")
            }
        } else {
            if start.maxY > line {
                out.append("Start ward round (\(start.text)) runs past the bar's line at \(at), above the bar")
            }
            if card.maxY > line {
                out.append("the round card (\(card.text)) runs past the bar's line at \(at)")
            }
        }
        // the part of the card on the first screen: down to the bar's line
        if let newSet, card.minY < line {
            var shown: Box = card
            shown.maxY = min(card.maxY, line)
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

// MARK: - The row a turn keeps

/// Turning the phone, or the window's width changing, keeps the student's
/// place on home: the set row that stood first in view before stands in view
/// after (T0151). The window's width changes every row's height (a name wraps
/// less on its side), so the scroll's offset alone lands somewhere else; the
/// list is scrolled back to that row instead, by its id.
enum HomeRowKeep {
    /// A row as it stood in the list's own frame: its top and bottom in
    /// points from the scroll view's top edge.
    struct Row<ID: Hashable>: Equatable {
        var id: ID
        var minY: Double
        var maxY: Double
    }

    /// The row a turn keeps, and how far down the list's visible part its top
    /// stood (0 at the top, 1 at the bottom).
    struct Place<ID: Hashable>: Equatable {
        var id: ID
        var fraction: Double
    }

    /// Where the list may put the kept row, as a fraction of its height: off
    /// the top row and the masthead above, and off New set and the dock below,
    /// on a phone either way up (UnitPoint's y for ScrollViewProxy.scrollTo).
    static let anchorRange: ClosedRange<Double> = 0.2...0.7

    /// The first row whose middle stands in the visible band from `top` to
    /// `bottom` (the list's insets: the top row above, the dock below), the
    /// row a finger would land on first; else the first row that shows at
    /// all (one taller than the band). Nil when no row shows, or the band is
    /// empty: there is no place to keep.
    static func place<ID: Hashable>(_ rows: [Row<ID>], top: Double, bottom: Double) -> Place<ID>? {
        guard bottom > top else { return nil }
        let height: Double = bottom - top
        let showing: [Row<ID>] = rows.filter { $0.maxY > top + 0.5 && $0.minY < bottom - 0.5 && $0.maxY > $0.minY }
        let held: [Row<ID>] = showing.filter { row in
            let middle: Double = (row.minY + row.maxY) / 2
            return middle >= top && middle <= bottom
        }
        guard let row = (held.isEmpty ? showing : held).min(by: { $0.minY < $1.minY }) else { return nil }
        return Place(id: row.id, fraction: (row.minY - top) / height)
    }

    /// Where the kept row goes after the turn: about where it stood, but
    /// never under the top row or the bar.
    static func anchor(_ fraction: Double) -> Double {
        min(anchorRange.upperBound, max(anchorRange.lowerBound, fraction.isFinite ? fraction : anchorRange.lowerBound))
    }

    /// The row a turn holds while the turn's layout settles.
    ///
    /// Scrolling it back at fixed times after the turn (0, 150 and 300 ms)
    /// was not enough: on a busy Mac the app did not settle for seconds
    /// after the turn (App build 40671914663: "Wait for app to idle" ran
    /// from 25.8 s to 29.6 s), all three scrolls were spent before the list
    /// laid out on its side, and it kept the upright offset, with the row
    /// at the window's bottom edge. So while held, each new size or content
    /// height scrolls it back again.
    ///
    /// A hold left running would pull the list back after things the
    /// student did (a search, a set added, a scroll to the top), and keep
    /// the place from being noted afresh. So it ends at the first rest
    /// after the turn, on any edit or scroll that is not the turn's, on
    /// leaving the page, and on its time limit: `limit` seconds of a free
    /// app with no new layout. The caller ticks it (`expired`) every
    /// `tick` seconds; a stalled main thread runs no tick, and a late one
    /// counts as one `tick`, so a stall like that run's (about 4 s) does not
    /// spend the window, and the heights that arrive after it still scroll
    /// the row back. Each new size or layout opens the window afresh, and
    /// `cap` seconds after the turn the hold ends whatever comes.
    ///
    /// Times are seconds on one clock (the system's uptime unless given).
    struct Hold<ID: Hashable>: Equatable {
        /// Seconds of a free app, with no new layout, that end a hold.
        static var limit: Double { 1.0 }
        /// The longest a hold may last after its turn, in seconds.
        static var cap: Double { 8.0 }
        /// How often the caller ticks the hold, in seconds.
        static var tick: Double { 0.25 }
        /// Ticks enough to pass the cap.
        static var ticks: Int { Int((cap / tick).rounded(.up)) + 1 }

        static func now() -> Double { ProcessInfo.processInfo.systemUptime }

        private(set) var place: Place<ID>?
        /// Which turn holds now, so a tick from an earlier one ends nothing.
        private(set) var turnNumber = 0
        private var started: Double = 0
        private var lastTick: Double = 0
        /// Free time since the last layout, counted a tick at a time.
        private var free: Double = 0

        init() {}

        var isHolding: Bool { place != nil }

        /// The list took a new size. A hold already running keeps its
        /// row, the one noted at rest, and its window opens afresh; else
        /// the row noted at rest, if any, for a new turn. What to scroll
        /// back to now, and the turn it belongs to (for `expired`).
        mutating func turn(kept: Place<ID>?, at now: Double = Hold.now()) -> (place: Place<ID>, turn: Int)? {
            if place != nil, now - started >= Self.cap { place = nil }
            if place == nil {
                guard let kept else { return nil }
                place = kept
                turnNumber += 1
                started = now
            }
            free = 0
            lastTick = now
            return place.map { ($0, turnNumber) }
        }

        /// The list laid out again (its size or its content): where to
        /// scroll back to, while held. The window opens afresh.
        mutating func relaid(at now: Double = Hold.now()) -> Place<ID>? {
            guard place != nil else { return nil }
            if now - started >= Self.cap || free >= Self.limit {
                place = nil
                return nil
            }
            free = 0
            lastTick = now
            return place
        }

        /// The list came to rest: the turn's layout is done.
        mutating func settled() { place = nil }

        /// A tick of turn `number`'s timer: a later turn holds on. It ends
        /// the hold after `limit` free seconds with no layout, or at `cap`.
        mutating func expired(turn number: Int, at now: Double = Hold.now()) {
            guard number == turnNumber, place != nil else { return }
            free += min(max(now - lastTick, 0), Self.tick)
            lastTick = now
            if now - started >= Self.cap || free >= Self.limit - 1e-9 { place = nil }
        }

        /// A finger on the list, a scroll to the top, a search, an edit,
        /// or the page left: the place is the student's again.
        mutating func touched() { place = nil }
    }
}
