import Foundation

// The paper frame against the system bars and the display's corner (the
// owner, 22 Oct: the frame never crosses or hides a system bar or a
// control, and every radius near a corner matches the device's). The same
// cases as android/.../ui/ward/WardFrameClearTest.kt.

var failures = 0
func check(_ name: String, _ result: Bool) {
    print("\(result ? "PASS" : "FAIL") \(name)")
    if !result { failures += 1 }
}

struct Phone {
    let label: String
    let width: Double
    let height: Double
    let safe: WardSystemInsets
    let device: Double?
}

let phones = [
    Phone(label: "iPhone 16 Pro", width: 402, height: 874, safe: WardSystemInsets(top: 62, bottom: 34), device: nil),
    Phone(label: "iPhone SE", width: 375, height: 667, safe: WardSystemInsets(top: 20, bottom: 0), device: 0),
    Phone(label: "Pro Max landscape", width: 956, height: 440, safe: WardSystemInsets(top: 0, bottom: 21, left: 62, right: 62), device: nil),
    Phone(label: "iPad", width: 834, height: 1194, safe: WardSystemInsets(top: 24, bottom: 20), device: nil),
    Phone(label: "no bars", width: 402, height: 874, safe: .none, device: nil),
]

// the rule: device less inset, floored at the element's own minimum
check("radius is the device's less the inset", WardCorner.concentric(device: 55, inset: 12, floor: WardEdge.minRadius) == 43)
check("floored at the element's own minimum", WardCorner.concentric(device: 55, inset: 50, floor: 24) == 24)
for floor in [WardEdge.minRadius, 16, 24] {
    for inset in [0, WardPaper.frame, WardPaper.sideInset, 62] {
        check("corner 0: floor \(floor) at \(inset)", WardCorner.concentric(device: 0, inset: inset, floor: floor) == floor)
    }
}

let half = WardPaper.edgeWidth / 2
for p in phones {
    let pad = p.label == "iPad"
    guard let panel = WardPaper.panel(width: p.width, height: p.height, safe: p.safe, device: p.device, pad: pad) else {
        check("\(p.label): a panel", false)
        continue
    }
    check("\(p.label): clear of the status bar", panel.y - half >= p.safe.top - 1e-9)
    check("\(p.label): clear of the home indicator", panel.y + panel.height + half <= p.height - p.safe.bottom + 1e-9)
    check("\(p.label): clear of the side insets",
          panel.x - half >= p.safe.left - 1e-9 && panel.x + panel.width + half <= p.width - p.safe.right + 1e-9)
    check("\(p.label): never nearer the edge than the frame", panel.x >= WardPaper.frame && panel.y >= WardPaper.frame)
    let device = p.device ?? WardPaper.deviceRadius(width: p.width, height: p.height, pad: pad)
    let side = max(panel.x, p.width - panel.x - panel.width)
    let cap = min(panel.width, panel.height) / (2 * 1.52866483)
    check("\(p.label): top corners concentric", panel.radius ==
          min(cap, WardCorner.concentric(device: device, inset: max(side, panel.y), floor: WardEdge.minRadius)))
    check("\(p.label): bottom corners concentric", panel.bottomRadius ==
          min(cap, WardCorner.concentric(device: device, inset: max(side, p.height - panel.y - panel.height), floor: WardEdge.minRadius)))
    let moved = WardPaper.panel(width: p.width, height: p.height, top: 4, safe: p.safe, device: p.device, pad: pad)!
    check("\(p.label): a top above the bar is held below it", moved.y == panel.y)
    check("\(p.label): outline inside the panel", WardEdge.outline(panel).allSatisfy {
        $0.y >= panel.y - 1e-9 && $0.y <= panel.y + panel.height + 1e-9 })
    // a page's content (SkyRoot's sideInset inside the safe area) starts inside the ring's inner edge
    check("\(p.label): content inside the ring",
          WardPaper.contentEdge(p.safe.left) > panel.x + half &&
          p.width - WardPaper.contentEdge(p.safe.right) < panel.x + panel.width - half)
}
check("no bars, no device: the frame as before",
      WardPaper.panel(width: 402, height: 874, safe: .none, device: nil) == WardPaper.panel(width: 402, height: 874))
check("no bars, iPad: its 18-point corner as before",
      WardPaper.panel(width: 834, height: 1194, safe: .none, device: nil, pad: true) == WardPaper.panel(width: 834, height: 1194, pad: true))
check("a reported 0: the frame's corners at their floor",
      WardPaper.panel(width: 375, height: 667, safe: WardSystemInsets(top: 20), device: 0).map {
          $0.radius == WardEdge.minRadius && $0.bottomRadius == WardEdge.minRadius } == true)

print("\(failures) WARD FRAME CLEAR FAILURES")
exit(failures == 0 ? 0 : 1)
