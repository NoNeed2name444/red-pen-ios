// Home on a short phone (HomeFit): which windows count as short, how many
// beds the round shows there, how much of the page shows above the bar (the
// page's cut), and the check the preview runs on a laid-out home: at the
// standard text sizes the round card and its Start ward round button end
// above the cut; at large sizes the page scrolls but the cut slices no
// button and leaves no sliver; New set sits on no part of the card that
// shows; no word breaks. The faults are what the r7 picture at the iPhone
// SE's size and the r11 pictures at XXL and AX1 showed.
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
// large text: a bed comes off while the cut slices Start, one always stays
check("a trim takes a bed off a tall window", HomeFit.shownBeds(3, short: false, trimmed: 1) == 2)
check("a trim goes on from a short window's two", HomeFit.shownBeds(4, short: true, trimmed: 1) == 1)
check("a trim leaves one bed", HomeFit.shownBeds(3, short: false, trimmed: 9) == 1)
check("a trim leaves none as none", HomeFit.shownBeds(0, short: false, trimmed: 2) == 0)

// the cut through a button (the iPad at AX1: Start 967-1025, cut 1020)
check("a cut through the middle slices", HomeFit.slices(minY: 967, maxY: 1025, cut: 1020))
check("a button wholly above the cut is not sliced", !HomeFit.slices(minY: 600, maxY: 656, cut: 1020))
check("a button wholly past the cut is not sliced", !HomeFit.slices(minY: 1049, maxY: 1107, cut: 768))
check("a button ending on the cut is not sliced", !HomeFit.slices(minY: 964, maxY: 1020, cut: 1020))

// MARK: - The preview's check

func box(_ y0: Double, _ y1: Double, x0: Double = 16, x1: Double = 359) -> HomeFit.Box {
    HomeFit.Box(minX: x0, minY: y0, maxX: x1, maxY: y1)
}

let fitting = HomeFit.faults(card: box(204, 527), start: box(460, 510), bar: box(557, 647),
                             newSet: box(8, 52, x0: 300, x1: 344))
check("a home that fits has no faults", fitting.isEmpty, fitting.joined(separator: "; "))

// the r7 SE picture: the card to 603, the bar from 570. New set sat on the
// card then; under the page's cut the card stops 12 points above the bar,
// so only the button and the card are caught
let cut = HomeFit.faults(card: box(204, 603), start: box(538, 590), bar: box(570, 720),
                         newSet: box(580, 632, x0: 232, x1: 359))
check("the button and the card past the cut are both caught",
      cut.count == 2 && cut[0].hasPrefix("Start ward round") && cut[1].hasPrefix("the round card"),
      cut.joined(separator: "; "))

// on a short window New set is up in the top row: on the card there, it is
// caught
let up = HomeFit.faults(card: box(120, 500), start: box(440, 490), bar: box(557, 647),
                        newSet: box(131, 175, x0: 300, x1: 344))
check("New set on the card's top is caught", up.count == 1 && up[0].hasPrefix("New set"), up.joined(separator: "; "))

// MARK: - Large text: the page scrolls

// r11's iPhone at XXL: the card 283-797 with Start at 725-781, the bar
// (New set over the dock) from 708. The page runs on under the cut at 696
// and scrolls; Start is wholly below it; nothing sits on what shows
let xxl = HomeFit.faults(card: box(283, 797), start: box(725, 781), bar: box(708, 860),
                         newSet: box(708, 764, x0: 232, x1: 386), large: true)
check("at XXL a home that runs on and scrolls fits", xxl.isEmpty, xxl.joined(separator: "; "))
let xxlDefault = HomeFit.faults(card: box(283, 797), start: box(725, 781), bar: box(708, 860),
                                newSet: box(708, 764, x0: 232, x1: 386))
check("the same page at the standard sizes does not", xxlDefault.count == 2, xxlDefault.joined(separator: "; "))
let sliced = HomeFit.faults(card: box(283, 760), start: box(680, 736), bar: box(708, 860), newSet: nil, large: true)
check("a Start button sliced by the cut is caught",
      sliced.count == 1 && sliced[0].contains("sliced"), sliced.joined(separator: "; "))
let whole = HomeFit.faults(card: box(283, 700), start: box(620, 676), bar: box(708, 860), newSet: nil, large: true)
check("a Start button wholly above the cut is fine", whole.isEmpty, whole.joined(separator: "; "))

// MARK: - Slivers and words

let sliver = HomeFit.faults(card: box(204, 527), start: box(460, 510), bar: box(557, 647), newSet: nil,
                            tiles: box(539, 700))
check("6 points of the tiles over the cut is a sliver", sliver.count == 1 && sliver[0].contains("sliver"),
      sliver.joined(separator: "; "))
for (tiles, what) in [(box(500, 700), "a good part of the tiles"), (box(560, 700), "tiles wholly under the cut")] {
    let f = HomeFit.faults(card: box(204, 480), start: box(420, 470), bar: box(557, 647), newSet: nil, tiles: tiles)
    check("\(what) is fine", f.isEmpty, f.joined(separator: "; "))
}
let broken = HomeFit.faults(card: box(204, 527), start: box(460, 510), bar: box(557, 647), newSet: nil,
                            words: [HomeFit.Words(name: "the Vitals tile's streak", width: 46, widest: 52),
                                    HomeFit.Words(name: "the brain map's line", width: 120, widest: 48)])
check("a text narrower than its widest word is caught, and only that one",
      broken.count == 1 && broken[0].hasPrefix("the Vitals tile's streak breaks inside a word"),
      broken.joined(separator: "; "))

// MARK: - Slivers of any row or part (the review's B1)

// the iPad at the default size: the PRACTISE tiles' tops at 1098, the bar
// from 1118, so the cut at 1106 shows 8 points of them
let ipadTiles = HomeFit.Part(name: "a Practise tile", box: box(1098, 1190))
let ipadBar = box(1118, 1194)
let ipadSliver = HomeFit.faults(card: box(300, 980), start: box(920, 976), bar: ipadBar, newSet: nil,
                                parts: [ipadTiles])
check("iPad at the default size: 8 points of the Practise tiles are caught",
      ipadSliver.count == 1 && ipadSliver[0].contains("a Practise tile (1098-1190)")
        && ipadSliver[0].contains("cut at 1106"), ipadSliver.joined(separator: "; "))
check("the cut moves up to the tiles' top", HomeFit.settledCut(1106, tops: [1098]) == 1098)
check("the page, cut there, shows none of them",
      HomeFit.cut(barTop: 1118, pageTop: 0, tops: [1098]) == 1098)
let ipadHonoured = HomeFit.faults(card: box(300, 980), start: box(920, 976), bar: ipadBar, newSet: nil,
                                  pageEnd: 1098, parts: [ipadTiles])
check("with the cut moved up, the tiles are no sliver", ipadHonoured.isEmpty, ipadHonoured.joined(separator: "; "))

// AX1: the top of bed 1's Due chip, 682.3-700, over the cut at 686 (bar 698)
let dueChip = HomeFit.Part(name: "bed 1's Due chip", box: box(682.3, 700, x0: 300, x1: 359))
let ax1Bar = box(698, 860)
let ax1Sliver = HomeFit.faults(card: box(283, 900), start: box(820, 876), bar: ax1Bar, newSet: nil,
                               large: true, parts: [dueChip])
check("AX1: 4 points of the Due chip over the cut are caught",
      ax1Sliver.count == 1 && ax1Sliver[0].contains("bed 1's Due chip"), ax1Sliver.joined(separator: "; "))
check("AX1: the cut moves up to the chip's top", HomeFit.settledCut(686, tops: [682.3]) == 682.3)
let ax1Honoured = HomeFit.faults(card: box(283, 900), start: box(820, 876), bar: ax1Bar, newSet: nil,
                                 large: true, pageEnd: 682.3, parts: [dueChip])
check("AX1: with the cut moved up, the chip is no sliver", ax1Honoured.isEmpty, ax1Honoured.joined(separator: "; "))

// AX1 phone, preview run 38820624486: the chip's top 682.3, the bar 698, the page
// 0 to 874 from a top at 0. The cut moved up to 682.3, yet the frame was snapped
// to the 3x grid and ended at 682.67: 0.37 of the chip showed. On the grid at or
// above the cut, the end is 682.0 (and likewise from an off-grid page top).
let ax1Height = HomeFit.shown(barTop: 698, pageTop: 0, pageHeight: 874, tops: [682.3], scale: 3)
check("AX1: the page ends on the 3x grid at or above the chip's top", ax1Height <= 682.3 && ax1Height > 682.3 - 1.0 / 3
      && (ax1Height * 3).rounded() == ax1Height * 3, "\(ax1Height)")
for top in [0.0, 0.17, 59.4, 62.5] {
    let h = HomeFit.shown(barTop: 698, pageTop: top, pageHeight: 874, tops: [682.3], scale: 3)
    let grid = (top + h) * 3
    check("AX1: from a page top at \(top), an end snapped to the grid either way is not below the chip",
          top + h <= 682.3 + 1e-9 && (grid.rounded() / 3) <= 682.3 + 1e-9, "\(top + h)")
}
let ax1Snapped = HomeFit.faults(card: box(413, 1173), start: box(1098, 1156), bar: box(698, 840), newSet: box(698, 755),
                                large: true, pageEnd: 682 + 0.0, parts: [dueChip])
check("AX1: the snapped page end clears the chip in the gate", ax1Snapped.isEmpty, ax1Snapped.joined(separator: "; "))
check("no scale known: the cut as it was", HomeFit.shown(barTop: 698, pageTop: 0, pageHeight: 874, tops: [682.3]) == 682.3)

// the cut is left alone by tops at it, 12 or more over it, or past it
check("a top at the cut leaves it", HomeFit.settledCut(686, tops: [686]) == 686)
check("a top 12 points over the cut leaves it", HomeFit.settledCut(686, tops: [674]) == 686)
check("a top past the cut leaves it", HomeFit.settledCut(686, tops: [690, 900]) == 686)
check("no tops, no move", HomeFit.settledCut(686, tops: []) == 686)
// moving up can bring another top into the band: it goes on until none is
check("a chain of tops moves the cut to the last", HomeFit.settledCut(686, tops: [680, 670, 640]) == 670)
check("tops in any order settle the same", HomeFit.settledCut(686, tops: [670, 640, 680]) == 670)
// a part twice reported is one sliver
let twice = HomeFit.faults(card: box(204, 480), start: box(420, 470), bar: box(557, 647), newSet: nil,
                           tiles: box(539, 700), parts: [HomeFit.Part(name: "the tiles", box: box(539, 700))])
check("the same sliver reported twice is one fault", twice.count == 1, twice.joined(separator: "; "))
// a part wholly past the cut, or well over it, is fine
let partsFine = HomeFit.faults(card: box(204, 480), start: box(420, 470), bar: box(557, 647), newSet: nil,
                               parts: [HomeFit.Part(name: "a row", box: box(545, 600)),
                                       HomeFit.Part(name: "a tile", box: box(400, 500))])
check("parts wholly past the cut or well over it are fine", partsFine.isEmpty, partsFine.joined(separator: "; "))

// MARK: - How much of the page shows

check("no bar measured: all of the page", HomeFit.shown(barTop: nil, pageTop: 0, pageHeight: 874) == 874)
check("a bar at 700: down to 688", HomeFit.shown(barTop: 700, pageTop: 0, pageHeight: 874) == 688)
check("measured from the page's own top", HomeFit.shown(barTop: 700, pageTop: 100, pageHeight: 774) == 588)
check("a bar not below the page's top: all of it", HomeFit.shown(barTop: 50, pageTop: 100, pageHeight: 774) == 774)
check("an endless bar top: all of it", HomeFit.shown(barTop: .infinity, pageTop: 0, pageHeight: 874) == 874)
check("the cut, from the page's top", HomeFit.cut(barTop: 700, pageTop: 100) == 588)
check("the cut below a short page's frame is kept", HomeFit.cut(barTop: 700, pageTop: 100) == 588
      && HomeFit.shown(barTop: 700, pageTop: 100, pageHeight: 500) == 500)
check("no bar, no cut", HomeFit.cut(barTop: nil, pageTop: 0) == nil)
check("a bar over the page's top, no cut", HomeFit.cut(barTop: 50, pageTop: 100) == nil)
check("a bar just under the page's top cuts at its top", HomeFit.cut(barTop: 105, pageTop: 100) == 0)

let close = HomeFit.faults(card: box(204, 553), start: box(500, 545), bar: box(557, 647), newSet: nil)
check("ending 4 points above the bar is too close", close.count == 1, close.joined(separator: "; "))

check("nothing laid out is a fault", HomeFit.faults(card: nil, start: nil, bar: nil, newSet: nil).count == 1)
check("a card with no button is a fault",
      HomeFit.faults(card: box(0, 1), start: nil, bar: nil, newSet: nil).count == 1)

// MARK: - The parts book (WardPartBook's ledger)

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
      abs(HomeFit.settledCut(683, tops: ledger.tops) - 2048.0 / 3) < 1e-9)
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
    let movedCut = HomeFit.settledCut(686, tops: book.tops)
    check("the chip at 682 moves the cut from 686 to 682", movedCut == 682)
    book.cut = movedCut
    let loopDrop = book.drop(1, atRest: true, cut: 682)
    check("dropping a part at or below the settled cut keeps its entry so settledCut stays at 682",
          !loopDrop && book.entries[1]?.top == 682 && book.sightings[1] != nil
            && HomeFit.settledCut(686, tops: book.tops) == 682)
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

if failures.isEmpty {
    print("all HomeFit checks passed")
} else {
    print("\(failures.count) HomeFit checks failed")
    exit(1)
}
