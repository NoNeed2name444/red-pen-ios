// Picture cards from your own photo or scan: the size a picture is kept at,
// covers dragged, stretched, drawn and hit, and the cards the covers make.
import Foundation
import CoreGraphics

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

func inPicture(_ box: OcclusionBox) -> Bool {
    let right: Double = box.x + box.w
    let bottom: Double = box.y + box.h
    let low: Bool = box.x >= -1e-9 && box.y >= -1e-9
    let high: Bool = right <= 1 + 1e-9 && bottom <= 1 + 1e-9
    return low && high
}

typealias PO = PhotoOcclusion

// MARK: downscale

let phone = PO.fitted(width: 4032, height: 3024)
check("a phone photo is shrunk to 2048 on its long side", phone.width == 2048 && phone.height == 1536,
      "\(phone)")
let tall = PO.fitted(width: 1170, height: 2532)
check("a screenshot is shrunk by its height", tall.height == 2048 && tall.width == 946, "\(tall)")
let small = PO.fitted(width: 800, height: 600)
check("a small picture is never enlarged", small.width == 800 && small.height == 600)
let exact = PO.fitted(width: 2048, height: 10)
check("exactly 2048 is kept", exact.width == 2048 && exact.height == 10)
let sliver = PO.fitted(width: 20000, height: 3)
check("a sliver keeps at least a pixel", sliver.width == 2048 && sliver.height == 1, "\(sliver)")
let none = PO.fitted(width: 0, height: 100)
check("an empty picture is nothing", none.width == 0 && none.height == 0)

// MARK: clamping and moving

let outside = PO.clamped(OcclusionBox(x: 0.95, y: -0.2, w: 0.2, h: 0.1))
check("a box is pulled back inside the picture", inPicture(outside) && near(outside.x, 0.8) && near(outside.y, 0),
      "\(outside)")
let tiny = PO.clamped(OcclusionBox(x: 0.5, y: 0.5, w: 0.001, h: 0))
check("a box is never smaller than the least", tiny.w >= PO.minSide && tiny.h >= PO.minSide)
let huge = PO.clamped(OcclusionBox(x: -1, y: -1, w: 3, h: 3))
check("a box bigger than the picture is the picture", near(huge.w, 1) && near(huge.h, 1) && near(huge.x, 0))

let start = OcclusionBox(x: 0.4, y: 0.4, w: 0.2, h: 0.1)
let dragged = PO.moved(start, dx: 0.1, dy: -0.05)
check("a drag moves a box", near(dragged.x, 0.5) && near(dragged.y, 0.35) && near(dragged.w, 0.2))
let pushed = PO.moved(start, dx: 5, dy: 5)
check("a box dragged off the edge stops at it", near(pushed.x, 0.8) && near(pushed.y, 0.9) && near(pushed.w, 0.2),
      "\(pushed)")

// MARK: stretching

let wider = PO.resized(start, handle: .bottomRight, dx: 0.1, dy: 0.05)
check("the bottom-right corner stretches", near(wider.x, 0.4) && near(wider.w, 0.3) && near(wider.h, 0.15))
let fromTopLeft = PO.resized(start, handle: .topLeft, dx: -0.1, dy: -0.1)
check("the top-left corner stretches and the far corner stays",
      near(fromTopLeft.x, 0.3) && near(fromTopLeft.y, 0.3)
        && near(fromTopLeft.x + fromTopLeft.w, 0.6) && near(fromTopLeft.y + fromTopLeft.h, 0.5))
let crossed = PO.resized(start, handle: .topLeft, dx: 0.5, dy: 0.5)
check("a corner cannot cross its opposite", near(crossed.x + crossed.w, 0.6) && crossed.w >= PO.minSide - 1e-9
        && near(crossed.y + crossed.h, 0.5), "\(crossed)")
let beyond = PO.resized(start, handle: .topRight, dx: 3, dy: -3)
check("a corner stops at the picture's edge", inPicture(beyond) && near(beyond.y, 0) && near(beyond.x + beyond.w, 1),
      "\(beyond)")
let bottomLeft = PO.resized(start, handle: .bottomLeft, dx: -0.05, dy: 0.02)
check("the bottom-left corner stretches", near(bottomLeft.x, 0.35) && near(bottomLeft.h, 0.12)
        && near(bottomLeft.x + bottomLeft.w, 0.6))

// MARK: drawing a new cover

let backwards = PO.drawn(fromX: 0.6, y: 0.5, toX: 0.2, y: 0.3)
check("a box drawn backwards is the same box", backwards.map { near($0.x, 0.2) && near($0.y, 0.3)
        && near($0.w, 0.4) && near($0.h, 0.2) } ?? false, "\(String(describing: backwards))")
check("a tap draws nothing", PO.drawn(fromX: 0.5, y: 0.5, toX: 0.501, y: 0.502) == nil)
let offEdge = PO.drawn(fromX: 0.9, y: 0.9, toX: 1.4, y: 1.3)
check("a box drawn off the picture stays on it", offEdge.map(inPicture) ?? false)
let line = PO.drawn(fromX: 0.1, y: 0.5, toX: 0.5, y: 0.5)
check("a flat stroke still makes a findable box", (line?.h ?? 0) >= PO.minSide - 1e-9)

let middle = PO.added(aspect: 1)
check("a new cover sits in the middle", near(middle.x + middle.w / 2, 0.5) && near(middle.y + middle.h / 2, 0.5))
let wide = PO.added(aspect: 2)
check("a new cover on a wide picture is taller as a fraction", wide.h > middle.h)
let corner = PO.added(centreX: 0.99, centreY: 0.99)
check("a new cover near the edge stays inside", inPicture(corner))

// MARK: hitting

let big = PO.Cover(box: OcclusionBox(x: 0.1, y: 0.1, w: 0.6, h: 0.6), answer: "Heart")
let inner = PO.Cover(box: OcclusionBox(x: 0.3, y: 0.3, w: 0.1, h: 0.05), answer: "Aorta")
let far = PO.Cover(box: OcclusionBox(x: 0.8, y: 0.8, w: 0.1, h: 0.1), answer: "Apex")
let placed: [PO.Cover] = [big, inner, far]
check("the smaller of two covers is the one hit", PO.hit(x: 0.35, y: 0.32, in: placed) == 1)
check("the big cover around it is hit elsewhere", PO.hit(x: 0.15, y: 0.6, in: placed) == 0)
check("empty picture is no cover", PO.hit(x: 0.75, y: 0.05, in: placed) == nil)
check("slack lets a finger just outside count", PO.hit(x: 0.79, y: 0.85, in: placed, slack: 0.02) == 2)

let box = OcclusionBox(x: 0.2, y: 0.2, w: 0.4, h: 0.2)
check("a corner is found near it", PO.handle(atX: 0.61, y: 0.41, of: box, toleranceX: 0.03, toleranceY: 0.03) == .bottomRight)
check("the top-left too", PO.handle(atX: 0.19, y: 0.2, of: box, toleranceX: 0.03, toleranceY: 0.03) == .topLeft)
check("the middle of an edge is no corner", PO.handle(atX: 0.4, y: 0.2, of: box, toleranceX: 0.03, toleranceY: 0.03) == nil)
let thin = OcclusionBox(x: 0.2, y: 0.2, w: 0.02, h: 0.02)
check("on a tiny box the nearest corner wins",
      PO.handle(atX: 0.221, y: 0.221, of: thin, toleranceX: 0.05, toleranceY: 0.05) == .bottomRight)

// MARK: from OCR, and to cards

let found = [OcclusionPhrases.Cover(box: OcclusionBox(x: 0.9, y: 0.1, w: 0.3, h: 0.05),
                                    answer: "Left atrium", lines: [[0, 1]])]
let editable = PO.covers(from: found)
check("OCR covers become editable ones, inside the picture",
      editable.count == 1 && editable[0].answer == "Left atrium" && inPicture(editable[0].box))

check("answers are tidied to one line", PO.tidied("  Superior vena\ncava ") == "Superior vena cava")

var covers: [PO.Cover] = [
    PO.Cover(box: OcclusionBox(x: 0.1, y: 0.1, w: 0.2, h: 0.05), answer: "Right atrium"),
    PO.Cover(box: OcclusionBox(x: 0.6, y: 0.1, w: 0.2, h: 0.05), answer: " Aorta "),
    PO.Cover(box: OcclusionBox(x: 0.1, y: 0.8, w: 0.2, h: 0.05), answer: "   "),
    PO.Cover(box: OcclusionBox(x: 0.6, y: 0.8, w: 0.2, h: 0.05), answer: "aorta"),
]
let cards = PO.cards(from: covers, imageIndex: 3, source: "Scan, p. 2")
check("one card per answered label, a repeat asked once", cards.count == 2, "\(cards.count)")
check("cards are picture cards on the right picture",
      cards.allSatisfy { $0.type == .occlusion && $0.imageIndex == 3 })
check("the answer is the tidied label", cards.first?.bullets == ["Right atrium"] && cards.last?.bullets == ["Aorta"])
check("each card carries its source", cards.allSatisfy { $0.source == "Scan, p. 2" })
let blank = covers[2].box
check("an unanswered cover still hides its place on every card",
      cards.allSatisfy { $0.siblings.contains(blank) })
check("a card's own cover is not among its siblings",
      cards.allSatisfy { card in !card.siblings.contains(card.occlusion ?? blank) })
check("the repeated label's second place stays covered on the first",
      cards.last.map { $0.siblings.contains(covers[3].box) } ?? false)

covers = [PO.Cover(box: OcclusionBox(x: 0.1, y: 0.1, w: 0.2, h: 0.05), answer: "Aorta")]
check("one label is enough for a photo", PO.cards(from: covers, imageIndex: 0).count == 1)
check("no answers, no cards", PO.cards(from: [PO.Cover(box: blank, answer: "")], imageIndex: 0).isEmpty)
check("nothing, nothing", PO.cards(from: [], imageIndex: 0).isEmpty)

// MARK: names and text

var parts = DateComponents()
parts.year = 2026; parts.month = 9; parts.day = 5; parts.hour = 12
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "UTC")!
let day: Date = calendar.date(from: parts)!
check("a scan is named for its day", PO.defaultName(on: day, scanned: true).hasPrefix("Scanned pages, "))
check("a photo deck is named for its day", PO.defaultName(on: day, scanned: false).hasPrefix("Picture cards, "))
check("a one-page source is just the name", PO.source(name: "Heart", page: 1, of: 1) == "Heart")
check("a page of several says which", PO.source(name: "Heart", page: 2, of: 3) == "Heart, p. 2")
check("page text drops blank lines", PO.pageText(["  Aorta ", "", "Left atrium", " \n"]) == "Aorta\nLeft atrium")

print(failures.isEmpty ? "\nALL PHOTO OCCLUSION TESTS PASS"
                       : "\n\(failures.count) PHOTO OCCLUSION TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
