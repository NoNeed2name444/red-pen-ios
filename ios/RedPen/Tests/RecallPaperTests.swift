// Draw from memory's paper (the owner, 22 Oct; review R7): its foot stands
// just above a docked pen tray; Compare never resizes it, so the comparison
// stands on the space that was drawn on; and the original takes the mode, so
// there is no white block on the dark paper.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

// MARK: the foot above the tray

let room = CGRect(x: 16, y: 120, width: 361, height: 640)          // foot at 760
let docked = CGRect(x: 0, y: 700, width: 393, height: 152)          // the tray's top at 700
ok(RecallPaper.trayGap(room: room, picker: docked, space: 8) == 68, "the foot rises past the docked tray, with the gap: \(RecallPaper.trayGap(room: room, picker: docked, space: 8))")
ok(RecallPaper.trayGap(room: room, picker: .null, space: 8) == 0, "no tray (floating or hidden): no gap")
ok(RecallPaper.trayGap(room: room, picker: CGRect(x: 0, y: 800, width: 393, height: 52), space: 8) == 0, "a tray clear of the room: no gap")
ok(RecallPaper.trayGap(room: .zero, picker: docked, space: 8) == 0, "before the room is measured: no gap")

// MARK: Compare never resizes the paper

let drawnAt = CGSize(width: 361, height: 572)
ok(RecallPaper.size(comparing: true, drawnOn: drawnAt) == drawnAt, "comparing: the paper keeps the size it was drawn at")
ok(RecallPaper.size(comparing: false, drawnOn: drawnAt) == nil, "drawing: the paper fills its room again")
ok(RecallPaper.size(comparing: true, drawnOn: nil) == nil, "nothing drawn on yet: the room decides")
ok(RecallPaper.size(comparing: true, drawnOn: .zero) == nil, "an unmeasured size is never held")
// the tray goes away while comparing; the held paper does not follow it
let held = RecallPaper.size(comparing: true, drawnOn: drawnAt)
let roomWithoutTray = CGRect(x: 16, y: 120, width: 361, height: 700)
ok(held == drawnAt && RecallPaper.trayGap(room: roomWithoutTray, picker: .null, space: 8) == 0,
   "with the tray gone the room grows, and the paper stays the size it was drawn at")

// MARK: the original takes the mode

ok(RecallPaper.original(dark: true) == .invertedScreen, "dark: the figure's white is inverted and screened away, no white block")
ok(RecallPaper.original(dark: false) == .multiply, "light: the figure's white is multiplied into the page")

print(failures == 0 ? "ALL RECALL PAPER TESTS PASS" : "\(failures) RECALL PAPER TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
