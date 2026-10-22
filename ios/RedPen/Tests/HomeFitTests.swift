// Home on a short phone (HomeFit): which windows count as short, how many
// beds the round shows there, the page that is not cut above the bar (the
// owner, 22 Oct) and the row that lets its last tile scroll clear of the bar,
// and the check the preview runs on a laid-out home: at the standard text
// sizes the round card and its Start ward round button end above the bar's
// line; at large sizes the page scrolls but that line slices no button; New
// set sits on no part of the card above it; no word breaks. The faults are
// what the r7 picture at the iPhone SE's size and the r11 pictures at XXL
// and AX1 showed.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: - Short windows

// iPhone SE, mini and 16e, inside the status bar and home indicator
for height in [647.0, 728, 763] {
    check("\(Int(height)) points tall is short", HomeFit.isShort(height: height, broad: false))
}
// a Pro, a Pro Max
for height in [778.0, 840] {
    check("\(Int(height)) points tall is not short", !HomeFit.isShort(height: height, broad: false))
}
check("a wide iPad keeps New set at the bottom", !HomeFit.isShort(height: 700, broad: true))
check("nothing measured yet is not short", !HomeFit.isShort(height: 0, broad: false))

// MARK: - Beds shown

check("a short window shows two of four beds", HomeFit.shownBeds(4, short: true) == 2)
check("a short window shows a lone bed", HomeFit.shownBeds(1, short: true) == 1)
check("a tall window shows every bed", HomeFit.shownBeds(4, short: false) == 4)
check("no beds stay none", HomeFit.shownBeds(0, short: true) == 0)
// large text: a bed comes off while the bar's line slices Start, one always stays
check("a trim takes a bed off a tall window", HomeFit.shownBeds(3, short: false, trimmed: 1) == 2)
check("a trim goes on from a short window's two", HomeFit.shownBeds(4, short: true, trimmed: 1) == 1)
check("a trim leaves one bed", HomeFit.shownBeds(3, short: false, trimmed: 9) == 1)
check("a trim leaves none as none", HomeFit.shownBeds(0, short: false, trimmed: 2) == 0)

// the line through a button (the iPad at AX1: Start 967-1025, line 1020)
check("a line through the middle slices", HomeFit.slices(minY: 967, maxY: 1025, cut: 1020))
check("a button wholly above the line is not sliced", !HomeFit.slices(minY: 600, maxY: 656, cut: 1020))
check("a button wholly past the line is not sliced", !HomeFit.slices(minY: 1049, maxY: 1107, cut: 768))
check("a button ending on the line is not sliced", !HomeFit.slices(minY: 964, maxY: 1020, cut: 1020))

// MARK: - The preview's check

func box(_ y0: Double, _ y1: Double, x0: Double = 16, x1: Double = 359) -> HomeFit.Box {
    HomeFit.Box(minX: x0, minY: y0, maxX: x1, maxY: y1)
}

let fitting = HomeFit.faults(card: box(204, 527), start: box(460, 510), bar: box(557, 647),
                             newSet: box(8, 52, x0: 300, x1: 344))
check("a home that fits has no faults", fitting.isEmpty, fitting.joined(separator: "; "))

// the r7 SE picture: the card to 603, the bar from 570. New set sat on the
// card then; the card has to stop 12 points above the bar, so only the
// button and the card are caught
let cut = HomeFit.faults(card: box(204, 603), start: box(538, 590), bar: box(570, 720),
                         newSet: box(580, 632, x0: 232, x1: 359))
check("the button and the card past the bar's line are both caught",
      cut.count == 2 && cut[0].hasPrefix("Start ward round") && cut[1].hasPrefix("the round card"),
      cut.joined(separator: "; "))

// on a short window New set is up in the top row: on the card there, it is
// caught
let up = HomeFit.faults(card: box(120, 500), start: box(440, 490), bar: box(557, 647),
                        newSet: box(131, 175, x0: 300, x1: 344))
check("New set on the card's top is caught", up.count == 1 && up[0].hasPrefix("New set"), up.joined(separator: "; "))

// MARK: - Large text: the page scrolls

// r11's iPhone at XXL: the card 283-797 with Start at 725-781, the bar
// (New set over the dock) from 708. The page runs on behind the bar, its
// line at 696, and scrolls; Start is wholly below it; nothing sits on the
// card above the line
let xxl = HomeFit.faults(card: box(283, 797), start: box(725, 781), bar: box(708, 860),
                         newSet: box(708, 764, x0: 232, x1: 386), large: true)
check("at XXL a home that runs on and scrolls fits", xxl.isEmpty, xxl.joined(separator: "; "))
let xxlDefault = HomeFit.faults(card: box(283, 797), start: box(725, 781), bar: box(708, 860),
                                newSet: box(708, 764, x0: 232, x1: 386))
check("the same page at the standard sizes does not", xxlDefault.count == 2, xxlDefault.joined(separator: "; "))
let sliced = HomeFit.faults(card: box(283, 760), start: box(680, 736), bar: box(708, 860), newSet: nil, large: true)
check("a Start button sliced by the bar's line is caught",
      sliced.count == 1 && sliced[0].contains("sliced"), sliced.joined(separator: "; "))
let whole = HomeFit.faults(card: box(283, 700), start: box(620, 676), bar: box(708, 860), newSet: nil, large: true)
check("a Start button wholly above the bar's line is fine", whole.isEmpty, whole.joined(separator: "; "))

// MARK: - Tiles behind the bar, and words

// Tiles and rows past the bar's line are no fault: they pass behind New set
// and the dock, which hide nothing a scroll cannot bring clear
for (card, what) in [(box(204, 527), "the card fitting, the tiles under it"),
                     (box(204, 480), "the card well clear")] {
    let f = HomeFit.faults(card: card, start: box(420, 470), bar: box(557, 647), newSet: nil)
    check("\(what): no fault", f.isEmpty, f.joined(separator: "; "))
}
let broken = HomeFit.faults(card: box(204, 527), start: box(460, 510), bar: box(557, 647), newSet: nil,
                            words: [HomeFit.Words(name: "the Vitals tile's streak", width: 46, widest: 52),
                                    HomeFit.Words(name: "the brain map's line", width: 120, widest: 48)])
check("a text narrower than its widest word is caught, and only that one",
      broken.count == 1 && broken[0].hasPrefix("the Vitals tile's streak breaks inside a word"),
      broken.joined(separator: "; "))

// MARK: - Not cut above the bar (the owner, 22 Oct)

// The bar's line is only where the first screen's round has to end
check("the bar's line is barRoom (12) above the bar", HomeFit.barRoom == 12 && HomeFit.barLine(barTop: 700) == 688)
// the row that ends the list: as tall as the bar, and 24 more
check("the end row is the bar's height and 24", HomeFit.endSpace(barHeight: 140) == 164 && HomeFit.endRoom == 24)
check("no bar measured: the end row is 24", HomeFit.endSpace(barHeight: 0) == 24)
check("an unmeasurable bar is not counted", HomeFit.endSpace(barHeight: .nan) == 24 && HomeFit.endSpace(barHeight: -5) == 24)
// the last tile, scrolled to the end, rests above the bar's top: the list
// runs on to the bar's bottom, and the end row lifts the last tile clear,
// whether or not the list keeps its own inset for the bar too, for bars
// from none to AX5's height (New set over the dock, the dock alone, the
// selection bar) and tops from a short phone's to an iPad's.
var clear: Bool = true
var worst: Double = -.infinity
for barTop in [520.0, 700, 742, 790, 1118] {
    for barHeight in [0.0, 56, 76, 132, 152, 220, 400] {
        for honoured in [false, true] {
            let bottom: Double = HomeFit.lastRowBottom(barTop: barTop, barHeight: barHeight, insetHonoured: honoured)
            worst = max(worst, bottom - barTop)
            if !(bottom <= barTop - HomeFit.endRoom + 1e-9) { clear = false }
        }
    }
}
check("the last tile can sit wholly above the bar, endRoom clear of it", clear, "worst \(worst)")
check("a bar from 700, 132 tall: the last tile ends at 676",
      HomeFit.lastRowBottom(barTop: 700, barHeight: 132) == 676)

// The app's page is not cut: no frame shortens it above the bar, the bar
// floats over it with nothing drawn behind it, its last row is the end row,
// and nothing fades under the bar (the source, read from the repository root)
let library = (try? String(contentsOfFile: "ios/RedPen/Features/Library/LibraryView.swift", encoding: .utf8)) ?? ""
let fit = (try? String(contentsOfFile: "ios/RedPen/Shared/Learn/HomeFit.swift", encoding: .utf8)) ?? ""
check("found home's source", !library.isEmpty && !fit.isEmpty)
check("no page cut in HomeFit", !fit.contains("cutRoom") && !fit.contains("static func cut(")
      && !fit.contains("static func shown(") && !fit.contains("settledCut"))
check("no page cut in the library", !library.contains("pageCutHeight") && !library.contains("HomeFit.cut(")
      && !library.contains("HomeFit.shown(") && !library.contains("cutRoom"))
check("the bar floats over the page", library.contains(".safeAreaInset(edge: .bottom) { bottomBar }"))
let barStart = library.range(of: "private var bottomBar: some View {")
let barEnd = library.range(of: "private var newSetShown: Bool")
let barSource = barStart.flatMap { a in barEnd.map { String(library[a.lowerBound..<$0.lowerBound]) } } ?? ""
check("nothing is drawn behind New set and the dock: no fill, strip, line or glow",
      !barSource.isEmpty && !barSource.contains(".background") && !barSource.contains("Divider")
      && !barSource.contains("WardEtch") && !barSource.contains("Rectangle(") && !barSource.contains("wardBarBase")
      && barSource.components(separatedBy: ".wardUnlit()").count == 3)
check("the list ends with the end row",
      library.contains(".frame(height: CGFloat(HomeFit.endSpace(barHeight: Double(dockHeight))))"))
check("no soft edge fades the rows under the bar (no fading, the owner, 9 Oct)",
      library.contains(".scrollEdgeEffectHidden(true, for: .bottom)"))
check("Start ward round keeps clear of the bar's line", library.contains("HomeFit.barLine(barTop: Double(barTop))"))

let close = HomeFit.faults(card: box(204, 553), start: box(500, 545), bar: box(557, 647), newSet: nil)
check("ending 4 points above the bar is too close", close.count == 1, close.joined(separator: "; "))

check("nothing laid out is a fault", HomeFit.faults(card: nil, start: nil, bar: nil, newSet: nil).count == 1)
check("a card with no button is a fault",
      HomeFit.faults(card: box(0, 1), start: nil, bar: nil, newSet: nil).count == 1)

// MARK: - The parts book (WardPartBook's ledger)

// The ledger still guards a cut a page may set (WardPartBook.cut, nil on
// home now): the cut once no part shows under 12 points over it, as the
// ledger's loop guard expects it to settle.
func settled(_ cut: Double, tops: [Double]) -> Double {
    var at: Double = cut
    var moved: Bool = true
    while moved {
        moved = false
        for top in tops where top.isFinite && top < at && at - top < 12 {
            at = top
            moved = true
        }
    }
    return at
}

// N3: a top is booked floored onto the pixel grid, never rounded to a half
// point: 682.78 at 3x is 682.667 (a half-point round gave 683, below the
// real top, so a pixel of the part showed over a cut at 683)
let booked682: Double = wardBookedTop(682.78, scale: 3)
check("682.78 at 3x books at the pixel line above, 682.667", abs(booked682 - 2048.0 / 3) < 1e-9, "\(booked682)")
check("a booked top is never below the real one",
      booked682 <= 682.78 && (682.78 - booked682) < 1.0 / 3)
check("a top already on the grid keeps its place", wardBookedTop(683, scale: 3) == 683)
check("a top on a 2x pixel line keeps its place", wardBookedTop(100.5, scale: 2) == 100.5)
var neverBelow: Bool = true
for scale in [1.0, 2, 3] {
    for step in 0..<3000 {
        let y: Double = 600 + Double(step) * 0.0137
        let top: Double = wardBookedTop(y, scale: scale)
        if top > y + 1e-9 || y - top >= 1 / scale + 1e-9 { neverBelow = false }
    }
}
check("every booked top is at or above the real one, within a pixel", neverBelow)
check("an unknown scale floors to a whole point", wardBookedTop(682.78, scale: 0) == 682)

// the ledger books that top, and the cut moves up to it
var ledger = WardPartLedger<Int>()
ledger.set(1, name: "chip", rect: CGRect(x: 0, y: 682.78, width: 80, height: 24), reach: 0, scale: 3)
check("the ledger lists the floored top", ledger.tops.count == 1 && abs(ledger.tops[0] - 2048.0 / 3) < 1e-9,
      "\(ledger.tops)")
check("a cut at 683 settles on the chip's pixel line",
      abs(settled(683, tops: ledger.tops) - 2048.0 / 3) < 1e-9)
// a row's tile stands out above its frame
ledger.set(2, name: "row", rect: CGRect(x: 0, y: 700, width: 300, height: 60), reach: 8, scale: 2)
check("reach lifts a row's top", ledger.entries[2]?.top == 692 && ledger.entries[2]?.rect.height == 68)

// N2: a part whose view went away leaves the book; a new page clears it
ledger.drop(1)
check("a dropped part leaves the book", ledger.entries[1] == nil && ledger.tops == [692])
ledger.drop(99)
check("dropping a part that is not there changes nothing", ledger.tops == [692])
ledger.set(3, name: "gone", rect: .zero, reach: 4, scale: 2)
check("an empty frame is not kept", ledger.entries[3] == nil)
ledger.clear()
check("a new page empties the ledger", ledger.entries.isEmpty && ledger.tops.isEmpty)
// the same top from two parts counts once, and survives one of them going
ledger.set(4, name: "a", rect: CGRect(x: 0, y: 500, width: 10, height: 10), reach: 0, scale: 2)
ledger.set(5, name: "b", rect: CGRect(x: 0, y: 500, width: 10, height: 10), reach: 0, scale: 2)
check("two parts at one top book it once", ledger.tops == [500])
ledger.drop(4)
check("the top stays while another part holds it", ledger.tops == [500])

// MARK: - N4 & N5: push and pop, scroll settlement, and the cut loop guard

// 1. Push and pop with no movement (onAppear re-booking from the remembered spot)
do {
    var book = WardPartLedger<Int>()
    var changes: [[Double]] = []
    let rect = CGRect(x: 16, y: 1098, width: 300, height: 92)
    if book.set(1, name: "a Practise tile", rect: rect, reach: 3, scale: 2, atRest: true) {
        changes.append(book.told)
    }
    check("initial rest sighting books the tile and publishes once",
          book.entries[1] != nil && book.sightings[1] != nil && book.tops == [1095] && changes == [[1095]])
    if book.drop(1, atRest: true) {
        changes.append(book.told)
    }
    check("push disappear drops both entry and sighting",
          book.entries[1] == nil && book.sightings[1] == nil && book.tops.isEmpty && changes == [[1095], []])
    // On pop, onGeometryChange is silent because the rect is unchanged; onAppear hands the spot back.
    if book.set(1, name: "a Practise tile", rect: rect, reach: 3, scale: 2, atRest: true) {
        changes.append(book.told)
    }
    check("onAppear re-books the identical rect and publishes once",
          book.entries[1]?.top == 1095 && book.tops == [1095] && changes == [[1095], [], [1095]])
}

// 2. Push and pop during a transition (atRest: false then rebook())
do {
    var book = WardPartLedger<Int>()
    var changes: [[Double]] = []
    let rect = CGRect(x: 16, y: 682.3, width: 60, height: 18)
    if book.set(1, name: "bed 1's Due chip", rect: rect, reach: 0, scale: 3, atRest: true) {
        changes.append(book.told)
    }
    let chipTop = wardBookedTop(682.3, scale: 3)
    check("chip booked at rest before transition", book.tops == [chipTop] && changes.count == 1)
    let droppedWhileMoving = book.drop(1, atRest: false)
    check("mid-push drop clears entry without publishing mid-transition",
          !droppedWhileMoving && book.entries[1] == nil && book.sightings[1] == nil && book.told == [chipTop])
    let sightedWhileMoving = book.set(1, name: "bed 1's Due chip", rect: rect, reach: 0, scale: 3, atRest: false)
    check("mid-pop sighting is kept in sightings without booking or publishing",
          !sightedWhileMoving && book.sightings[1] != nil && book.entries[1] == nil && book.told == [chipTop])
    // Because told is still [chipTop] from before the mid-transition drop, verify rebook restores entries
    // and when tops differ from told, rebook publishes once.
    let secondRect = CGRect(x: 16, y: 740, width: 300, height: 56)
    _ = book.set(2, name: "a set row", rect: secondRect, reach: 4, scale: 3, atRest: false)
    if book.rebook() {
        changes.append(book.told)
    }
    check("rebook on rest restores the popped part and publishes once",
          book.entries[1]?.top == chipTop && book.entries[2]?.top == 736
            && book.tops == [chipTop, 736] && changes.count == 2)
}

// 3. Scroll settlement (atRest: false -> rebook())
do {
    var book = WardPartLedger<Int>()
    var changes: [[Double]] = []
    if book.set(1, name: "row 1", rect: CGRect(x: 0, y: 500, width: 300, height: 50), reach: 4, scale: 2, atRest: true) {
        changes.append(book.told)
    }
    for y in [480.0, 440.0, 410.0] {
        if book.set(1, name: "row 1", rect: CGRect(x: 0, y: y, width: 300, height: 50), reach: 4, scale: 2, atRest: false) {
            changes.append(book.told)
        }
    }
    check("scrolling updates sightings without changing entries or told",
          book.entries[1]?.top == 496 && book.told == [496] && changes.count == 1)
    if book.rebook() {
        changes.append(book.told)
    }
    check("rebook at scroll settlement updates entries to final sighting and fires once",
          book.entries[1]?.top == 406 && book.tops == [406] && changes == [[496], [406]])
    if book.rebook() {
        changes.append(book.told)
    }
    check("a second rebook with no change does not fire again", changes.count == 2)
}

// 4. Row recycled off-screen while scrolling (drop + rebook)
do {
    var book = WardPartLedger<Int>()
    var changes: [[Double]] = []
    _ = book.set(1, name: "row 1", rect: CGRect(x: 0, y: 300, width: 300, height: 50), reach: 0, scale: 2, atRest: true)
    if book.set(2, name: "row 2", rect: CGRect(x: 0, y: 600, width: 300, height: 50), reach: 0, scale: 2, atRest: true) {
        changes.append(book.told)
    }
    let midDrop = book.drop(1, atRest: false)
    check("row recycled mid-scroll does not publish until settlement",
          !midDrop && book.entries[1] == nil && book.sightings[1] == nil && book.told == [300, 600])
    if book.rebook() {
        changes.append(book.told)
    }
    check("settlement after mid-scroll recycle publishes remaining row once",
          book.entries[1] == nil && book.entries[2]?.top == 600 && book.tops == [600] && book.told == [600]
            && changes.last == [600])
}

// 5. Cut moves above a part at rest (loop guard) vs normal removal above the cut
do {
    var book = WardPartLedger<Int>()
    book.cut = 686
    _ = book.set(1, name: "chip", rect: CGRect(x: 0, y: 682, width: 60, height: 18), reach: 0, scale: 2, atRest: true)
    _ = book.set(2, name: "upper row", rect: CGRect(x: 0, y: 400, width: 300, height: 50), reach: 0, scale: 2, atRest: true)
    let movedCut = settled(686, tops: book.tops)
    check("the chip at 682 moves the cut from 686 to 682", movedCut == 682)
    book.cut = movedCut
    let loopDrop = book.drop(1, atRest: true, cut: 682)
    check("dropping a part at or below the settled cut keeps its entry so settledCut stays at 682",
          !loopDrop && book.entries[1]?.top == 682 && book.sightings[1] != nil
            && settled(686, tops: book.tops) == 682)
    // the next rest books the hidden part where it was: nothing published,
    // so the cut never falls back to show it and hide it again
    let restAfterHide = book.rebook()
    check("a part hidden by the cut stays booked through the next rest",
          !restAfterHide && book.entries[1]?.top == 682 && book.tops.contains(682))
    let normalDrop = book.drop(2, atRest: true, cut: 682)
    check("dropping a part above the cut removes it from entries and tops",
          normalDrop && book.entries[2] == nil && book.sightings[2] == nil && book.tops == [682])
}

// 6. Dedup across set / drop / rebook
do {
    var book = WardPartLedger<Int>()
    let first = book.set(1, name: "a", rect: CGRect(x: 0, y: 500, width: 100, height: 40), reach: 0, scale: 2, atRest: true)
    let sameId = book.set(1, name: "a", rect: CGRect(x: 10, y: 500, width: 120, height: 40), reach: 0, scale: 2, atRest: true)
    let secondSameTop = book.set(2, name: "b", rect: CGRect(x: 140, y: 500, width: 100, height: 40), reach: 0, scale: 2, atRest: true)
    let dropOneOfTwo = book.drop(1, atRest: true)
    let rebookSame = book.rebook()
    let dropLast = book.drop(2, atRest: true)
    let dropEmpty = book.drop(99, atRest: true)
    check("told deduplicates identical sorted tops across set, drop and rebook",
          first && !sameId && !secondSameTop && !dropOneOfTwo && !rebookSame && dropLast && !dropEmpty)
}

// MARK: - T0060: the fourth review's ledger regressions

// Nit 1: multiplication and division can land on opposite sides of a 3x
// pixel line. A holder on that line must stay hidden through drop/rebook.
do {
    var keptEveryHolder = true
    var roundedApart = 0
    for pixel in 1800..<2100 {
        var book = WardPartLedger<Int>()
        let y = Double(pixel) * (1.0 / 3)
        let cut = Double(pixel) / 3
        if y < cut { roundedApart += 1 }
        book.cut = cut
        book.set(1, name: "holder", rect: CGRect(x: 0, y: y, width: 100, height: 44), reach: 0, scale: 3)
        let dropped = book.drop(1)
        let rebooked = book.rebook()
        keptEveryHolder = keptEveryHolder && !dropped && !rebooked && book.entries[1]?.top == cut
    }
    check("T0060 nit 1: every 3x holder survives roundoff at the cut", roundedApart > 0 && keptEveryHolder)
}

// Nit 2: only disappeared parts below the current cut may be retained.
// Live parts above it still count, and a sighting makes a retained part live.
do {
    var book = WardPartLedger<Int>()
    book.cut = 682
    book.set(1, name: "old holder", rect: CGRect(x: 0, y: 682, width: 100, height: 44), reach: 0, scale: 3)
    book.set(2, name: "live row", rect: CGRect(x: 0, y: 600, width: 100, height: 44), reach: 0, scale: 3)
    book.drop(1)
    book.cut = 686
    let pruned = book.rebook()
    let prunedGhost = pruned && book.entries[1] == nil && book.sightings[1] == nil && book.told == [600]
        && settled(686, tops: book.tops) == 686
    book.set(3, name: "reappeared", rect: CGRect(x: 0, y: 690, width: 100, height: 44), reach: 0, scale: 3)
    book.drop(3)
    book.set(3, name: "reappeared", rect: CGRect(x: 0, y: 680, width: 100, height: 44), reach: 0, scale: 3)
    book.rebook()
    let reappeared = book.entries[3]?.top == 680
    book.set(4, name: "hidden", rect: CGRect(x: 0, y: 700, width: 100, height: 44), reach: 0, scale: 3)
    book.drop(4)
    book.cut = nil
    book.rebook()
    check("T0060 nit 2: rebook prunes ghosts above or without a cut, keeping live and reappeared rows",
          prunedGhost && reappeared && book.entries[4] == nil && book.sightings[4] == nil)
}

// Nit 3: the holder hides on the last moving frame, before the rest event.
// No intermediate publication or later onAppear should be needed.
do {
    var book = WardPartLedger<Int>()
    book.cut = 680
    book.set(1, name: "More ways to practise", rect: CGRect(x: 0, y: 680, width: 300, height: 44), reach: 0, scale: 3)
    var publishedWhileMoving = false
    for y in [620.0, 650, 680] {
        publishedWhileMoving = book.set(1, name: "More ways to practise",
            rect: CGRect(x: 0, y: y, width: 300, height: 44), reach: 0, scale: 3, atRest: false)
            || publishedWhileMoving
    }
    let dropped = book.drop(1, atRest: false)
    let rested = book.rebook()
    let keptHolder = !publishedWhileMoving && !dropped && !rested && book.entries[1]?.top == 680
        && book.sightings[1] != nil && book.told == [680]
        && settled(686, tops: book.tops) == 680
    // The previous rest frame must not protect a row that is now above the
    // cut (including a real fraction of a pixel, beyond floating slack).
    book.set(1, name: "More ways to practise", rect: CGRect(x: 0, y: 679.9, width: 300, height: 44),
             reach: 0, scale: 3, atRest: false)
    book.drop(1, atRest: false)
    book.rebook()
    check("T0060 nit 3: keep a self-topped holder through moving drop/rest, but recycle above-cut rows",
          keptHolder && book.entries.isEmpty && book.sightings.isEmpty && book.told.isEmpty)
}

// Nit 4: switching sections may leave pageCut numerically unchanged, so
// clear must not depend on another onChange to restore the loop guard.
do {
    var book = WardPartLedger<Int>()
    book.cut = 682
    book.set(1, name: "old page", rect: CGRect(x: 0, y: 682, width: 100, height: 44), reach: 0, scale: 3)
    book.drop(1)
    book.clear()
    book.rebook()
    let cleared = book.entries.isEmpty && book.sightings.isEmpty && book.told.isEmpty
    book.set(2, name: "new page", rect: CGRect(x: 0, y: 682, width: 100, height: 44), reach: 0, scale: 3)
    let dropped = book.drop(2)
    check("T0060 nit 4: clear empties the book while preserving an unchanged cut",
          cleared && book.cut == 682 && !dropped && book.entries[2]?.top == 682)
}

// MARK: - Drop outcomes: removed, kept below cut, and no such part
do {
    var book = WardPartLedger<Int>()
    book.cut = 680
    book.set(1, name: "chip", rect: CGRect(x: 0, y: 690, width: 60, height: 18), reach: 0, scale: 3)
    book.set(2, name: "row", rect: CGRect(x: 0, y: 600, width: 300, height: 50), reach: 0, scale: 3)
    let keptDrop: WardPartLedger<Int>.Drop = book.drop(1)
    let removedDrop: WardPartLedger<Int>.Drop = book.drop(2)
    let missingDrop: WardPartLedger<Int>.Drop = book.drop(99)
    check("drop reports kept below cut", keptDrop == .kept && book.entries[1]?.top == 690)
    check("drop reports removed", removedDrop == .removed && book.entries[2] == nil)
    check("drop reports no such part", missingDrop == .none)
}

// MARK: - A push and back shows home covered (shots/ward-nits-3)
do {
    // AX5 on the SE's size: every face booked lies below home's cut at
    // 670, so the three parts that went away were kept and none removed
    let se: [Double] = [682, 971, 1142, 1219, 1765, 1812, 2071]
    check("push: kept drops show home covered when every face is below the cut",
          HomeFit.pushCovered(faces: se, cut: 670, removed: 0, kept: 3))
    check("push: no drop at all is no push",
          !HomeFit.pushCovered(faces: se, cut: 670, removed: 0, kept: 0))
    // AX5 on the phone: the round card stands above the cut at 640
    let phone: [Double] = [589, 878, 1177, 1247, 1775, 1844]
    check("push: a part above the cut must leave the book",
          !HomeFit.pushCovered(faces: phone, cut: 640, removed: 0, kept: 5))
    check("push: a part leaving the book shows home covered",
          HomeFit.pushCovered(faces: phone, cut: 640, removed: 1, kept: 5))
    check("push: an uncut page needs a part to leave",
          !HomeFit.pushCovered(faces: [100, 300], cut: nil, removed: 0, kept: 2))
    check("push: a face on the cut is below it",
          HomeFit.pushCovered(faces: [682.3333333333333], cut: 682.3333333333333, removed: 0, kept: 1))
}

if failures.isEmpty {
    print("all HomeFit checks passed")
} else {
    print("\(failures.count) HomeFit checks failed")
    exit(1)
}
