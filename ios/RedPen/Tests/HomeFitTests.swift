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

if failures.isEmpty {
    print("all HomeFit checks passed")
} else {
    print("\(failures.count) HomeFit checks failed")
    exit(1)
}
