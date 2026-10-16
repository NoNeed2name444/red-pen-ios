import Foundation

var failures = 0
func check(_ name: String, _ result: Bool) {
    print("\(result ? "PASS" : "FAIL") \(name)")
    if !result { failures += 1 }
}
func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) <= tolerance }
let phone = WardPaper.panel(width: 402, height: 874)!
let deck = WardEdge.join(outline: WardEdge.outline(phone), y: 733, radius: phone.radius)!
let page = CGRect(x: 16, y: 0, width: 370, height: 874)

#if !A1_BASE || A1_SIDES
for (label, host, covered, left, right) in [
    ("page", CGRect(x: 16, y: 732.25, width: 370, height: 130), false, true, true),
    ("sheet", CGRect(x: 0, y: 732.25, width: 402, height: 130), false, false, false),
    ("trailing host", CGRect(x: 200, y: 732.25, width: 186, height: 130), false, false, true),
    ("sky", CGRect(x: 16, y: 732.25, width: 370, height: 130), true, false, false),
    ("one point", CGRect(x: 17, y: 732.25, width: 368, height: 130), false, true, true),
    ("outside tolerance", CGRect(x: 17.01, y: 732.25, width: 367.98, height: 130), false, false, false)
] {
    let sides = WardIsland.sides(host: host, page: page, covered: covered)
    check("A1 sides: \(label)", sides.left == left && sides.right == right)
}
#endif

#if !A1_BASE || A1_LOCAL
let local = WardIsland.local(deck, origin: SIMD2(16, 732.25))
check("A1 local line stays half the stroke below strip top", near(local.y, 0.75))
check("A1 local left center", near(local.left!.center.x, 43.10) && near(local.left!.center.y, 47.85))
check("A1 local right center", near(local.right!.center.x, 326.90) && near(local.right!.center.y, 47.85))
check("A1 local left join", near(local.left!.join.x, -4) && near(local.left!.join.y, 47.85))
check("A1 local right join", near(local.right!.join.x, 374) && near(local.right!.join.y, 47.85))
check("A1 local straight ends", near(local.fromX!, 43.10) && near(local.toX!, 326.90))
let half = WardEdge.join(outline: WardEdge.outline(phone), y: 733, radius: phone.radius, left: false)!
check("translation keeps an unjoined side", WardIsland.local(half, origin: SIMD2(200, 732.25)).left == nil &&
      WardIsland.local(half, origin: SIMD2(200, 732.25)).fromX == nil)
#endif

#if !A1_BASE || A1_CLEARANCE
let bands = WardIsland.clearance(panel: phone, page: page, sides: .init(left: true, right: true))
check("A1 two clearance pieces", bands.count == 2)
check("A1 left piece only 12...16", bands[0] == CGRect(x: 12, y: 12, width: 4, height: 850))
check("A1 right piece only 386...390", bands[1] == CGRect(x: 386, y: 12, width: 4, height: 850))
check("A1 pieces never enter the page", bands.allSatisfy { $0.maxX <= page.minX || $0.minX >= page.maxX })
check("one-sided clearance", WardIsland.clearance(panel: phone, page: page,
      sides: .init(left: false, right: true)) == [bands[1]])
check("sheet and sky have no pieces", WardIsland.clearance(panel: phone, page: page,
      sides: .init(left: false, right: false)).isEmpty)
#endif

#if !A1_BASE || A1_PAD
for (w, h) in [(834.0, 1194.0), (1194, 834), (1032, 1376), (744, 1133), (375, 812)] {
    let pad = WardPaper.panel(width: w, height: h, pad: true)!
    check("A1 iPad \(w)x\(h), including narrow window: 18", pad.radius == 18)
    check("A1 moved iPad opening: 18", WardPaper.panel(width: w, height: h, top: 120, pad: true)!.radius == 18)
    let old = WardPaper.panel(width: w, height: h)!
    check("A1 non-iPad unchanged", near(old.radius, (min(w, h) - 24) * 53.33 / 428, 1e-10))
}
check("A1 phone still 47.10", near(phone.radius, 47.10))
let pad = WardPaper.panel(width: 834, height: 1194, pad: true)!
let padY = pad.y + pad.height - 128
let joinedPad = WardEdge.join(outline: WardEdge.outline(pad), y: padY, radius: pad.radius)!
for (name, corner, x) in [("left", joinedPad.left!, 12.0), ("right", joinedPad.right!, 822.0)] {
    check("A1 iPad \(name) radius", near(corner.radius, 18))
    check("A1 iPad \(name) join", near(corner.join.x, x) && near(corner.join.y, padY + 18))
    let vector = corner.join - corner.center
    let angle = asin(min(1, abs(vector.y) / hypot(vector.x, vector.y))) * 180 / .pi
    check("A1 iPad \(name) tangent to vertical outline within 0.5 degrees", angle <= 0.5)
    check("A1 iPad \(name) tangent to horizontal line", near(corner.center.y - corner.radius, padY))
}
let small = WardEdge.join(outline: WardEdge.outline(pad), y: pad.y + pad.height - 30, radius: pad.radius)!
check("iPad radius halves the remaining room", near(small.left!.radius, 15))
#endif

#if !A1_BASE
// The pill has a fixed point size, including at AX5. Taller decks change
// their y, so check both heights and the reduced-room case independently.
for (name, w, h, isPad) in [("phone", 402.0, 874.0, false), ("SE", 375, 667, false),
                           ("Pro Max", 440, 956, false), ("iPad", 834, 1194, true)] {
    let panel = WardPaper.panel(width: w, height: h, pad: isPad)!
    for (text, room) in [("default", 129.0), ("AX5", 310.0), ("short", 70.0)] {
        let y = panel.y + panel.height - room
        let join = WardEdge.join(outline: WardEdge.outline(panel), y: y, radius: panel.radius)!
        let slab = CGRect(x: 28, y: y - WardPaper.edgeWidth / 2, width: w - 56, height: room - 8)
        let inset = WardIsland.foldInset(slab: slab, join: join)
        let gap = WardIsland.foldClearance(slab: slab, join: join, inset: inset)
        print(String(format: "FOLD %@ %@ inset=%.2f slab=%.3f island=%.3f pt (rim included)", name, text, inset, gap.slab, gap.island))
        check("fold \(name) \(text) clears both curves by 2pt", gap.slab >= 2 && gap.island >= 2)
        // This also bounds narrower, trailing iPad slabs: the near corner is
        // in the same position; the distant corner only gets farther away.
    }
}
#endif

print("\(failures) WARD ISLAND FAILURES")
exit(failures == 0 ? 0 : 1)
