// Home on a short phone (HomeFit): which windows count as short, how many
// beds the round shows there, and the check the preview runs on a laid-out
// home - the round card and its Start ward round button end above the bar,
// and New set does not sit on the card. The faults are what the r7 picture
// at the iPhone SE's size showed.
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

// the r7 SE picture: the card to 603, the bar from 570, New set on the card
let cut = HomeFit.faults(card: box(204, 603), start: box(538, 590), bar: box(570, 720),
                         newSet: box(580, 632, x0: 232, x1: 359))
check("the cut button, the card under the bar and New set on it are all caught",
      cut.count == 3 && cut[0].hasPrefix("Start ward round") && cut[1].hasPrefix("the round card")
        && cut[2].hasPrefix("New set"), cut.joined(separator: "; "))

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
