// Which words on a slide become masks, and how the masks are drawn.
//
// A deck of anatomy slides used to come back with a mask on the college crest,
// the lecturer's name and "Slide 12". These cases are the page furniture every
// lecture template carries, and the labels a student is actually examined on.
import Foundation
import CoreGraphics

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

/// A line of text at a place on the page, top-left fractions.
func line(_ text: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> OcclusionFilter.Line {
    OcclusionFilter.Line(text: text, box: OcclusionBox(x: x, y: y, w: w, h: h))
}

func kept(_ lines: [OcclusionFilter.Line], figure: OcclusionBox?, pageBands: Bool = true) -> [String] {
    OcclusionFilter.testable(lines, figure: figure, pageBands: pageBands).map(\.text)
}

// MARK: a typical anatomy slide, figure in the middle

let figure = OcclusionBox(x: 0.1, y: 0.2, w: 0.8, h: 0.65)
let slide = [
    line("University of Leeds", 0.02, 0.02, 0.25, 0.04),
    line("The Inguinal Canal", 0.1, 0.12, 0.5, 0.08),          // the title
    line("Inferior epigastric artery", 0.3, 0.4, 0.25, 0.04),
    line("Spermatic cord", 0.5, 0.6, 0.2, 0.04),
    line("IVC", 0.2, 0.5, 0.05, 0.04),                          // on the figure, not in any list
    line("Hesselbach", 0.02, 0.5, 0.06, 0.04),                  // off the figure
    line("Dr Jane Smith MBBS", 0.3, 0.7, 0.2, 0.04),
    line("Slide 12", 0.4, 0.8, 0.1, 0.04),
    line("12/45", 0.9, 0.95, 0.05, 0.03),
    line("Figure 2", 0.3, 0.75, 0.1, 0.04),
    line("Source: Gray's Anatomy", 0.3, 0.78, 0.25, 0.03),
    line("www.anatomy.com", 0.5, 0.95, 0.2, 0.03),
    line("© 2020 Elsevier", 0.2, 0.95, 0.2, 0.03),
    line("03 March 2024", 0.7, 0.95, 0.2, 0.03),
]
let onSlide = kept(slide, figure: figure)
check("a medical label on the figure is kept", onSlide.contains("Inferior epigastric artery"), "\(onSlide)")
check("another is kept", onSlide.contains("Spermatic cord"), "\(onSlide)")
check("an abbreviation on the figure is kept", onSlide.contains("IVC"), "\(onSlide)")
check("the college name is dropped", !onSlide.contains("University of Leeds"))
check("the slide title is dropped", !onSlide.contains("The Inguinal Canal"))
check("text off the figure is dropped", !onSlide.contains("Hesselbach"))
check("the lecturer is dropped", !onSlide.contains("Dr Jane Smith MBBS"))
check("a slide number is dropped", !onSlide.contains("Slide 12"))
check("a page count is dropped", !onSlide.contains("12/45"))
check("a figure number is dropped", !onSlide.contains("Figure 2"))
check("a source line is dropped", !onSlide.contains("Source: Gray's Anatomy"))
check("a web address is dropped", !onSlide.contains("www.anatomy.com"))
check("a copyright line is dropped", !onSlide.contains("© 2020 Elsevier"))
check("a date is dropped", !onSlide.contains("03 March 2024"))
check("exactly the three labels", onSlide.count == 3, "\(onSlide)")

// MARK: a figure that swallowed the whole page, logos and all

let whole = OcclusionBox(x: 0, y: 0, w: 1, h: 1)
let crowded = [
    line("KCL", 0.9, 0.02, 0.06, 0.04),                         // a crest's letters, in the header
    line("Rectus sheath", 0.4, 0.03, 0.15, 0.04),               // a real label that reaches the top
    line("Anatomy of the Abdominal Wall", 0.1, 0.12, 0.6, 0.09),
    line("Linea alba", 0.5, 0.5, 0.1, 0.04),
    line("Faculty of Medicine", 0.02, 0.95, 0.2, 0.03),
    line("Page 3", 0.9, 0.95, 0.05, 0.03),
]
let onPage = kept(crowded, figure: whole)
check("a crest's letters in the header are dropped", !onPage.contains("KCL"), "\(onPage)")
check("a medical label in the header band survives", onPage.contains("Rectus sheath"), "\(onPage)")
check("the title is dropped even on the figure", !onPage.contains("Anatomy of the Abdominal Wall"))
check("a label mid-page is kept", onPage.contains("Linea alba"), "\(onPage)")
check("a faculty footer is dropped", !onPage.contains("Faculty of Medicine"))
check("a page number is dropped", !onPage.contains("Page 3"))

// a picture that IS the diagram has no header: its top labels are labels
let picture = kept([line("SVC", 0.4, 0.03, 0.08, 0.04), line("Right atrium", 0.3, 0.5, 0.2, 0.04)],
                   figure: whole, pageBands: false)
check("without page bands, a label at the top is kept", picture.contains("SVC"), "\(picture)")

// with no figure known, only the vocabulary lets a label through
let bare = kept([line("Femoral nerve", 0.3, 0.5, 0.2, 0.04), line("Key points", 0.3, 0.6, 0.2, 0.04)],
                figure: nil)
check("no figure: a medical term passes", bare.contains("Femoral nerve"), "\(bare)")
check("no figure: other words do not", !bare.contains("Key points"), "\(bare)")

// MARK: the word checks on their own

check("a sentence is not a label",
      !OcclusionFilter.looksLikeALabel("the arrow shows the direction of blood flow here"))
check("a lone number is not a label", !OcclusionFilter.looksLikeALabel("42"))
check("one letter is not a label", !OcclusionFilter.looksLikeALabel("A"))
check("a hospital is branding", OcclusionFilter.isBoilerplate("St Thomas' Hospital NHS Trust"))
check("an email is branding", OcclusionFilter.isBoilerplate("j.smith@leeds.ac.uk"))
check("a nerve is not branding", !OcclusionFilter.isBoilerplate("Ilioinguinal nerve"))
check("a Latin ending reads as medical", OcclusionFilter.isMedicalTerm("Pectineus"))
check("a plain word does not", !OcclusionFilter.isMedicalTerm("Key points"))

// MARK: every card covers every label

func label(_ text: String, _ x: Double, _ y: Double) -> FigureGrid.Label {
    FigureGrid.Label(text: text, box: OcclusionBox(x: x, y: y, w: 0.15, h: 0.04))
}
let cards = FigureGrid.cards(from: [label("Deep ring", 0.1, 0.2), label("Superficial ring", 0.5, 0.2),
                                    label("Spermatic cord", 0.3, 0.6)], imageIndex: 2)
check("three labels, three cards", cards.count == 3, "\(cards.count)")
check("each card carries the other two masks", cards.allSatisfy { $0.siblings.count == 2 },
      "\(cards.map(\.siblings.count))")
if let first = cards.first, let own = first.occlusion {
    check("a card's own mask is not among its siblings", !first.siblings.contains(own))
}

// an older card has no siblings: they come from the set's other cards on the picture
func old(_ x: Double, image: Int) -> AnkiCard {
    AnkiCard(type: .occlusion, bullets: ["x"], imageIndex: image,
             occlusion: OcclusionBox(x: x, y: 0.1, w: 0.1, h: 0.05))
}
let a = old(0.1, image: 0), b = old(0.4, image: 0), c = old(0.7, image: 1)
var overlapping = old(0.11, image: 0)
overlapping.bullets = ["same label twice"]
let derived = OcclusionCovers.others(for: a, in: [a, b, c, overlapping])
check("an older card covers the other labels on its picture",
      derived == [b.occlusion!], "\(derived)")
check("a stored sibling list wins", OcclusionCovers.others(for: cards[0], in: []).count == 2)

// MARK: the covers themselves

let frame = CGRect(x: 0, y: 0, width: 101, height: 51)
let raw = CGRect(x: 10.1, y: 5.1, width: 20.2, height: 5.1)
let cover = OcclusionCovers.rect(for: OcclusionBox(x: 0.1, y: 0.1, w: 0.2, h: 0.1),
                                 in: frame, padding: 3, minimum: 12)
check("a cover contains the label with room to spare",
      cover.contains(raw.insetBy(dx: -2.9, dy: -2.9)), "\(cover)")
check("a cover sits on whole pixels",
      [cover.minX, cover.minY, cover.maxX, cover.maxY].allSatisfy { $0 == $0.rounded() }, "\(cover)")
check("a cover is at least the minimum size", cover.height >= 12 && cover.width >= 12, "\(cover)")
let tiny = OcclusionCovers.rect(for: OcclusionBox(x: 0.5, y: 0.5, w: 0, h: 0),
                                in: frame, padding: 3, minimum: 12)
check("even a zero box gets a cover", tiny.width >= 12 && tiny.height >= 12, "\(tiny)")
let edge = OcclusionCovers.rect(for: OcclusionBox(x: 0.95, y: 0.95, w: 0.05, h: 0.05),
                                in: frame, padding: 3, minimum: 12)
check("a cover never runs off the picture", frame.contains(edge), "\(edge)")
let retina = OcclusionCovers.rect(for: OcclusionBox(x: 0.1, y: 0.1, w: 0.2, h: 0.1),
                                  in: frame, padding: 3, minimum: 12, pixelScale: 3)
check("at 3x a cover sits on third-points",
      [retina.minX, retina.maxX].allSatisfy { abs($0 * 3 - ($0 * 3).rounded()) < 0.0001 }, "\(retina)")

// MARK: stored and read back

let json = #"{"type":"occlusion","imageIndex":0,"occlusion":{"x":0.1,"y":0.1,"w":0.1,"h":0.1}}"#
let decoded = try? JSONDecoder().decode(AnkiCard.self, from: Data(json.utf8))
check("a card saved before siblings still opens", decoded != nil && decoded!.siblings.isEmpty)
if let data = try? JSONEncoder().encode(cards[0]),
   let back = try? JSONDecoder().decode(AnkiCard.self, from: data) {
    check("siblings survive a save", back.siblings == cards[0].siblings, "\(back.siblings)")
} else {
    check("a card with siblings round-trips", false)
}

print(failures.isEmpty ? "\nALL OCCLUSION TESTS PASS"
                       : "\n\(failures.count) OCCLUSION TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
