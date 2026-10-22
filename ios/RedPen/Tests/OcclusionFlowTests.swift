// Picture cards, step by step (T0133): every label on a card's picture is
// masked; Reveal takes off only the one asked; a rating moves to the next
// card; the photo path (labels read, covered, a cover moved and one added,
// saved) ends in cards that review the same way; and all of it reads back
// after a relaunch. The steps' names match
// android/.../data/OcclusionFlowTest.kt.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func inside(_ inner: OcclusionBox, _ outer: OcclusionBox) -> Bool {
    inner.x >= outer.x - 1e-9 && inner.y >= outer.y - 1e-9
        && inner.x + inner.w <= outer.x + outer.w + 1e-9 && inner.y + inner.h <= outer.y + outer.h + 1e-9
}

extension OcclusionBox {
    /// A box as a finger drags it over a word: a little past it all round.
    func grownForTest() -> OcclusionBox { OcclusionBox(x: x - 0.004, y: y - 0.004, w: w + 0.008, h: h + 0.008) }
}

/// A drawn label: its lines, where it stands (its right edge when `right`),
/// and the words it gives with the label each belongs to.
struct Drawn {
    var words: [OcclusionPhrases.Word] = []
    /// For each label, its answer and the indices of its words.
    var labels: [(answer: String, words: [Int])] = []
}

/// Lays labels out on a `width` x `height` picture at `size` pt, lines
/// `pitch` pt apart, each word boxed by `box(text, baseline)` -> (top, bottom).
func draw(_ labels: [([String], Double, Double, Bool)], width: Double, height: Double, size: Double,
          pitch: Double, box: (String, Double) -> (Double, Double)) -> Drawn {
    var out = Drawn()
    let advance: Double = size * 12 / 22
    for (lines, x, y, right) in labels {
        var mine: [Int] = []
        for (i, line) in lines.enumerated() {
            let parts = line.split(separator: " ").map(String.init)
            let lineWidth = Double(parts.map(\.count).reduce(0, +)) * advance + Double(parts.count - 1) * advance / 2
            var left = right ? x - lineWidth : x
            let baseline = y + size * 21 / 22 + pitch * Double(i)
            for part in parts {
                let (top, bottom) = box(part, baseline)
                mine.append(out.words.count)
                out.words.append(OcclusionPhrases.Word(text: part, box: OcclusionBox(
                    x: left / width, y: top / height, w: Double(part.count) * advance / width, h: (bottom - top) / height)))
                left += Double(part.count) * advance + advance / 2
            }
        }
        out.labels.append((lines.joined(separator: " "), mine))
    }
    return out
}

/// Vision's glyph-tight word boxes: from the x-height or cap height to the
/// baseline or the descenders.
func glyphTight(size: Double) -> (String, Double) -> (Double, Double) {
    { part, baseline in
        let ascends = part.contains { $0.isUppercase || "bdfhklt".contains($0) }
        let descends = part.contains { "gjpqy".contains($0) }
        return (baseline - (ascends ? 0.72 : 0.53) * size, baseline + (descends ? 0.21 : 0) * size)
    }
}

/// The heart example's labels as Vision reads them: word boxes tight round
/// the glyphs, on OcclusionExample's 900 x 640 drawing (22 pt, 25 pt pitch).
func heart() -> Drawn {
    let labels: [([String], Double, Double, Bool)] = [
        (["Superior vena", "cava"], 190, 70, true), (["Right atrium"], 190, 245, true),
        (["Tricuspid valve"], 190, 345, true), (["Right ventricle"], 190, 440, true),
        (["Inferior vena", "cava"], 190, 548, true), (["Aorta"], 700, 58, false),
        (["Pulmonary", "trunk"], 700, 150, false), (["Left atrium"], 700, 255, false),
        (["Mitral valve"], 700, 335, false), (["Left ventricle"], 700, 430, false),
        (["Interventricular", "septum"], 700, 540, false),
    ]
    return draw(labels, width: 900, height: 640, size: 22, pitch: 25, box: glyphTight(size: 22))
}

/// A second diagram, a kidney, as an older reader boxes it: every word the
/// whole line's height (1.25 x the type, whatever its letters), 18 pt on a
/// 1000 x 760 picture, lines 24 pt apart; its two lower-case labels "vein"
/// and "artery" stand one over the other, as separate labels do.
func kidney() -> Drawn {
    let labels: [([String], Double, Double, Bool)] = [
        (["Cortex"], 240, 90, true), (["Medulla"], 240, 220, true),
        (["Renal", "pelvis"], 240, 360, true), (["Minor calyx"], 240, 520, true),
        (["vein"], 760, 180, false), (["artery"], 760, 224, false),
        (["Renal capsule"], 760, 400, false), (["Ureter"], 760, 600, false),
    ]
    return draw(labels, width: 1000, height: 760, size: 18, pitch: 24) { _, baseline in
        (baseline - 18, baseline + 0.25 * 18 * 0.9)
    }
}

/// The one-rectangle rule: each label is under exactly one cover, every one
/// of its word boxes wholly inside it, with a margin all round, and no word
/// of another label under it.
func oneEach(_ name: String, _ drawn: Drawn, _ made: [OcclusionPhrases.Cover]) {
    for label in drawn.labels {
        let mine = label.words.map { drawn.words[$0].box }
        let touching = made.filter { cover in mine.contains { OcclusionCovers.overlapShare($0, cover.box) > 0 } }
        check("\(name): \"\(label.answer)\" has exactly one cover", touching.count == 1, "\(touching.count)")
        guard let cover = touching.first else { continue }
        check("\(name): every word of \"\(label.answer)\" is wholly under it", mine.allSatisfy { inside($0, cover.box) })
        let all = OcclusionPhrases.union(mine)
        let margins = [all.x - cover.box.x, all.y - cover.box.y,
                       cover.box.x + cover.box.w - all.x - all.w, cover.box.y + cover.box.h - all.y - all.h]
        check("\(name): \"\(label.answer)\" has a margin all round", margins.allSatisfy { $0 > 0 }, "\(margins)")
        let others = drawn.labels.filter { $0.answer != label.answer }.flatMap { $0.words.map { drawn.words[$0] } }
        let swallowed = others.filter { OcclusionCovers.overlapShare($0.box, cover.box) > 0.05 }.map(\.text)
        check("\(name): \"\(label.answer)\"'s cover reaches no other label", swallowed.isEmpty, "\(swallowed)")
    }
}

let drawnHeart = heart()
let words = drawnHeart.words
let covers = OcclusionPhrases.layout(words, figure: OcclusionBox(x: 0, y: 0, w: 1, h: 1),
                                     pageBands: false, aspect: 900.0 / 640.0)
let deck: [AnkiCard] = OcclusionPhrases.cards(from: covers, imageIndex: 0)

/// Every box drawn over a card's picture before Reveal: the grey others and
/// the card's own "?" (AnkiCardFace.covers draws exactly these).
func masked(_ card: AnkiCard) -> [OcclusionBox] {
    OcclusionCovers.others(for: card, in: deck) + [card.occlusion].compactMap { $0 }
}

/// After Reveal: the others stay grey; the asked one is only outlined.
func maskedAfterReveal(_ card: AnkiCard) -> [OcclusionBox] {
    OcclusionCovers.others(for: card, in: deck)
}

// MARK: O1 every hidden label is masked

check("O1 masked: a card for each of the 11 labels", deck.count == 11, "\(deck.map(\.bullets))")
let showing = deck.flatMap { card in
    words.filter { w in !masked(card).contains { inside(w.box, $0) } }.map { w in "\(card.bullets[0]): \(w.text)" }
}
check("O1 masked: on every card, no word of any label shows", showing.isEmpty, "\(showing.prefix(6))")
check("O1 masked: each card asks one, under its own \"?\"", deck.allSatisfy { $0.occlusion != nil && $0.bullets.count == 1 })

// MARK: O1 one rectangle per label (the owner's rule)

oneEach("O1 heart", drawnHeart, covers)
let drawnKidney = kidney()
let kidneyCovers = OcclusionPhrases.layout(drawnKidney.words, figure: OcclusionBox(x: 0, y: 0, w: 1, h: 1),
                                           pageBands: false, aspect: 1000.0 / 760.0)
oneEach("O1 kidney", drawnKidney, kidneyCovers)
check("O1 kidney: \"vein\" over \"artery\" stay two labels",
      kidneyCovers.contains { $0.answer == "vein" } && kidneyCovers.contains { $0.answer == "artery" },
      "\(kidneyCovers.map(\.answer))")
// the same two lower-case labels with glyph-tight boxes, a list's 40 pt apart
let stacked = draw([(["vein"], 600, 200, false), (["artery"], 600, 240, false), (["Aortic", "arch"], 200, 200, true)],
                   width: 900, height: 640, size: 22, pitch: 25, box: glyphTight(size: 22))
let stackedCovers = OcclusionPhrases.layout(stacked.words, figure: OcclusionBox(x: 0, y: 0, w: 1, h: 1),
                                            pageBands: false, aspect: 900.0 / 640.0)
oneEach("O1 stacked", stacked, stackedCovers)
check("O1 stacked: glyph-tight \"vein\" over \"artery\" stay two labels",
      Set(stackedCovers.map(\.answer)) == ["vein", "artery", "Aortic arch"], "\(stackedCovers.map(\.answer))")
// the photo path: two drags over one label's two lines are one cover; the
// same term in two far places keeps both; a neighbour is never swallowed
let svcLines = drawnHeart.labels[0].words.map { drawnHeart.words[$0].box }
let dragged: [PhotoOcclusion.Cover] = [
    PhotoOcclusion.Cover(box: OcclusionPhrases.union(Array(svcLines.prefix(2))).grownForTest(), answer: "Superior vena cava"),
    PhotoOcclusion.Cover(box: svcLines[2].grownForTest(), answer: "superior vena  cava"),
    PhotoOcclusion.Cover(box: OcclusionBox(x: 0.7, y: 0.1, w: 0.1, h: 0.04), answer: "Aorta"),
    PhotoOcclusion.Cover(box: OcclusionBox(x: 0.7, y: 0.8, w: 0.1, h: 0.04), answer: "Aorta"),
]
let joined = PhotoOcclusion.oneEach(dragged)
check("O1 photo: one label's two drags are one cover", joined.filter { PhotoOcclusion.tidied($0.answer).lowercased() == "superior vena cava" }.count == 1)
check("O1 photo: and that cover holds all its words", svcLines.allSatisfy { box in joined.contains { inside(box, $0.box) } })
check("O1 photo: one term in two far places keeps both", joined.filter { $0.answer == "Aorta" }.count == 2)
check("O1 photo: the saved cards have one cover for the label", PhotoOcclusion.cards(from: dragged, imageIndex: 0)
      .first { $0.bullets == ["Superior vena cava"] }.map { card in svcLines.allSatisfy { inside($0, card.occlusion!) } } ?? false)

// MARK: O2 Reveal takes off the one asked, and only it

for card in deck {
    let answerWords = words.filter { w in card.occlusion.map { inside(w.box, $0) } ?? false }
    let stillHidden = words.filter { w in maskedAfterReveal(card).contains { inside(w.box, $0) } }
    check("O2 reveal: the answer is the words under its cover",
          card.bullets[0] == answerWords.map(\.text).joined(separator: " "), "\(card.bullets) vs \(answerWords.map(\.text))")
    check("O2 reveal: its words come into view", answerWords.allSatisfy { w in !maskedAfterReveal(card).contains { inside(w.box, $0) } })
    check("O2 reveal: every other label stays covered", stillHidden.count == words.count - answerWords.count,
          "\(stillHidden.count) of \(words.count - answerWords.count)")
}
check("O2 reveal: across the deck, each label is revealed by its own card",
      Set(deck.map { $0.bullets[0] }).count == 11)

// MARK: O3 a rating moves to the next card

let now = Date(timeIntervalSince1970: 1_792_000_000)
var records: [UUID: ReviewRecord] = [:]
var queue = ReviewPlan.queue(for: deck, records: records, now: now)
check("O3 rate: the whole deck is due the first time", queue.count == 11)
let first = queue[0].card
records[first.id] = ReviewPlan.after(rating: .good, record: ReviewPlan.record(for: first, in: records, now: now), now: now)
queue = ReviewPlan.queue(for: deck, records: records, now: now)
check("O3 rate: Good moves on to the next card", queue.count == 10 && queue[0].card.id != first.id)
let second = queue[0].card
records[second.id] = ReviewPlan.after(rating: .again, record: ReviewPlan.record(for: second, in: records, now: now), now: now)
check("O3 rate: Again brings it back within the sitting, not now",
      (records[second.id]?.due ?? now) > now && (records[second.id]?.intervalMin ?? 99) <= 10)
let soon = now.addingTimeInterval(11 * 60)
check("O3 rate: and it is back once its minutes are up",
      ReviewPlan.queue(for: deck, records: records, now: soon).contains { $0.card.id == second.id })

// MARK: O4 picture from a photo: labels read, covered, moved, added, saved

var editing: [PhotoOcclusion.Cover] = PhotoOcclusion.covers(from: covers)
check("O4 photo: each label read gets a cover", editing.count == 11)
let aorta = editing.firstIndex { $0.answer == "Aorta" }!
let before = editing[aorta].box
editing[aorta].box = PhotoOcclusion.moved(before, dx: 0.01, dy: 0.005)
check("O4 photo: a cover moves", abs(editing[aorta].box.x - before.x - 0.01) < 1e-9
      && abs(editing[aorta].box.y - before.y - 0.005) < 1e-9)
editing.append(PhotoOcclusion.Cover(box: PhotoOcclusion.added(centreX: 0.5, centreY: 0.95, aspect: 900.0 / 640.0),
                                    answer: "Apex"))
editing.append(PhotoOcclusion.Cover(box: PhotoOcclusion.added(centreX: 0.1, centreY: 0.95, aspect: 900.0 / 640.0),
                                    answer: "  "))
let saved: [AnkiCard] = PhotoOcclusion.cards(from: editing, imageIndex: 0, source: "My photo")
check("O4 photo: saving makes a card for each answered cover", saved.count == 12, "\(saved.count)")
check("O4 photo: the added label is asked", saved.contains { $0.bullets == ["Apex"] })
check("O4 photo: the moved cover is where it was put", saved.first { $0.bullets == ["Aorta"] }?.occlusion == editing[aorta].box)
check("O4 photo: an unanswered cover still masks on every card", saved.allSatisfy { $0.siblings.count == 12 })
check("O4 photo: the cards are reviewable picture cards", saved.allSatisfy { $0.type == .occlusion && $0.imageIndex == 0 }
      && ReviewPlan.queue(for: saved, records: [:], now: now).count == 12)

// MARK: O5 after a relaunch

let data = try! JSONEncoder().encode(saved)
let back = try! JSONDecoder().decode([AnkiCard].self, from: data)
check("O5 relaunch: the cards read back the same", back == saved)
check("O5 relaunch: every cover and sibling is where it was",
      zip(back, saved).allSatisfy { $0.occlusion == $1.occlusion && $0.siblings == $1.siblings })
// (the Aorta cover was moved on purpose, so each cover is checked where it
// was saved, not over the words read)
check("O5 relaunch: still every cover masked on every card", back.allSatisfy { card in
    let all = OcclusionCovers.others(for: card, in: back) + [card.occlusion].compactMap { $0 }
    return editing.allSatisfy { cover in all.contains(cover.box) }
})
let kept = try! JSONDecoder().decode([UUID: ReviewRecord].self, from: try! JSONEncoder().encode(records))
check("O5 relaunch: the ratings read back, so the next card is the same",
      ReviewPlan.queue(for: deck, records: kept, now: now).map(\.card.id)
      == ReviewPlan.queue(for: deck, records: records, now: now).map(\.card.id))

print(failures.isEmpty ? "\nALL OCCLUSION FLOW TESTS PASS" : "\n\(failures.count) OCCLUSION FLOW TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
