// Finding the diagram on a slide, and turning its labels into cards.
//
// None of this asks a model anything, so all of it is checkable: a grid of
// marked cells goes in, boxes and cards come out. The cases below are the ones
// that decide whether a deck of anatomy slides is useful or is fifty cards
// masking the page number.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

/// A picture of a grid, so the test reads like the thing it is testing.
func grid(_ rows: [String]) -> [[Bool]] {
    rows.map { row in row.map { $0 == "#" } }
}

// MARK: blobs

// The whole reason for eight-way connectivity: strokes in a diagram meet at
// corners constantly, and four-way counting would call this two drawings.
check("a diagonal join is one blob",
      FigureGrid.blobs(in: grid(["#.", ".#"])).count == 1,
      "\(FigureGrid.blobs(in: grid(["#.", ".#"])).count)")

let two = FigureGrid.blobs(in: grid([
    "##....",
    ".#....",
    "......",
    "....##",
    "....##",
]))
check("two separate drawings stay separate", two.count == 2, "\(two.count)")
check("a blob's box covers all of it",
      two.contains(FigureGrid.Cells(minX: 0, minY: 0, maxX: 1, maxY: 1)),
      "\(two)")
check("an empty page has no blobs", FigureGrid.blobs(in: grid(["..", ".."])).isEmpty)
check("no page at all does not crash", FigureGrid.blobs(in: []).isEmpty)

// MARK: merging

// A legend beside a diagram, an arrow floating free of the structure it points
// at: near things are one figure.
let near = FigureGrid.merged(FigureGrid.blobs(in: grid(["#.#"])))
check("boxes one cell apart become one", near.count == 1, "\(near)")
check("and the merged box spans both",
      near.first == FigureGrid.Cells(minX: 0, minY: 0, maxX: 2, maxY: 0), "\(near)")

let far = FigureGrid.merged(FigureGrid.blobs(in: grid(["#...#"])))
check("boxes far apart stay apart", far.count == 2, "\(far)")

// MARK: what counts as a figure

var page = Array(repeating: Array(repeating: false, count: 10), count: 10)
for y in 0..<2 { for x in 0..<2 { page[y][x] = true } }   // 4 cells of 100
check("a mark covering the threshold is a figure",
      FigureGrid.figures(in: page, minimumShare: 0.04).count == 1)
check("a smudge below it is not",
      FigureGrid.figures(in: page, minimumShare: 0.10).isEmpty)

for y in 6..<10 { for x in 6..<10 { page[y][x] = true } } // 16 cells
let ranked = FigureGrid.figures(in: page, minimumShare: 0.03)
check("figures come back biggest first",
      ranked.count == 2 && ranked[0].area > ranked[1].area, "\(ranked)")

// MARK: fractions

let fraction = FigureGrid.normalised(
    FigureGrid.Cells(minX: 2, minY: 4, maxX: 3, maxY: 7), gridWidth: 10, gridHeight: 20)
check("a box becomes fractions of the whole image",
      abs(fraction.x - 0.2) < 1e-9 && abs(fraction.y - 0.2) < 1e-9
        && abs(fraction.w - 0.2) < 1e-9 && abs(fraction.h - 0.2) < 1e-9,
      "\(fraction)")
check("an empty grid gives an empty box",
      FigureGrid.normalised(FigureGrid.Cells(minX: 0, minY: 0, maxX: 1, maxY: 1),
                            gridWidth: 0, gridHeight: 0).w == 0)

// MARK: which labels are worth a card

func label(_ text: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double)
    -> FigureGrid.Label {
    FigureGrid.Label(text: text, box: OcclusionBox(x: x, y: y, w: w, h: h))
}

let mixed = [
    label("renal artery", 0.1, 0.2, 0.15, 0.04),
    label("12", 0.5, 0.9, 0.03, 0.03),                        // an axis number
    label("Renal Artery", 0.7, 0.2, 0.15, 0.04),              // the same term again
    label("the arrow shows the direction of flow", 0.1, 0.8, 0.4, 0.04),
    label("caption", 0.0, 0.0, 0.6, 0.5),                     // covers the picture
    label("invisible", 0.3, 0.3, 0.0, 0.0),
]
let kept = FigureGrid.usableLabels(mixed)
check("a real label is kept", kept.count == 1 && kept[0].text == "renal artery",
      kept.map(\.text).joined(separator: " / "))
check("a number with no letters is dropped", !kept.contains { $0.text == "12" })
check("the same term labelled twice is one card",
      !kept.contains { $0.text == "Renal Artery" })
check("a sentence is a caption, not a label",
      !kept.contains { $0.text.hasPrefix("the arrow") })
check("a label covering the diagram is dropped",
      !kept.contains { $0.text == "caption" })
check("a zero-sized box is dropped", !kept.contains { $0.text == "invisible" })

// MARK: the cards themselves

let cards = FigureGrid.cards(from: [label("left ventricle", 0.0, 0.5, 0.2, 0.05)],
                             imageIndex: 3)
check("one card per usable label", cards.count == 1, "\(cards.count)")
if let card = cards.first, let box = card.occlusion {
    check("the card is an occlusion card", card.type == .occlusion)
    check("the answer is the label", card.bullets == ["left ventricle"], "\(card.bullets)")
    check("it points at the right image", card.imageIndex == 3, "\(card.imageIndex ?? -1)")
    // a mask drawn exactly on the glyphs leaves ascenders and descenders
    // showing, and half a word is half an answer
    check("the mask is grown past the glyphs",
          box.h > 0.05 && box.y < 0.5, "\(box)")
    check("and never runs off the edge of the image",
          box.x >= 0 && box.y >= 0 && box.x + box.w <= 1.0001, "\(box)")
} else {
    check("a card with a mask was produced", false)
}

check("a figure with no labels makes no cards",
      FigureGrid.cards(from: [], imageIndex: 0).isEmpty)

print(failures.isEmpty ? "\nALL FIGURE TESTS PASS"
                       : "\n\(failures.count) FIGURE TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
