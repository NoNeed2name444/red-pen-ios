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

/// The heart example's labels as Vision reads them: word boxes tight round
/// the glyphs, on OcclusionExample's 900 x 640 drawing (22 pt, 25 pt pitch).
func heartWords() -> [OcclusionPhrases.Word] {
    let labels: [([String], Double, Double, Bool)] = [
        (["Superior vena", "cava"], 190, 70, true), (["Right atrium"], 190, 245, true),
        (["Tricuspid valve"], 190, 345, true), (["Right ventricle"], 190, 440, true),
        (["Inferior vena", "cava"], 190, 548, true), (["Aorta"], 700, 58, false),
        (["Pulmonary", "trunk"], 700, 150, false), (["Left atrium"], 700, 255, false),
        (["Mitral valve"], 700, 335, false), (["Left ventricle"], 700, 430, false),
        (["Interventricular", "septum"], 700, 540, false),
    ]
    var out: [OcclusionPhrases.Word] = []
    for (lines, x, y, right) in labels {
        for (i, line) in lines.enumerated() {
            let parts = line.split(separator: " ").map(String.init)
            let width = Double(parts.map(\.count).reduce(0, +)) * 12 + Double(parts.count - 1) * 6
            var left = right ? x - width : x
            let baseline = y + 21 + 25 * Double(i)
            for part in parts {
                let ascends = part.contains { $0.isUppercase || "bdfhklt".contains($0) }
                let descends = part.contains { "gjpqy".contains($0) }
                let top = baseline - (ascends ? 0.72 : 0.53) * 22
                let bottom = baseline + (descends ? 0.21 : 0) * 22
                out.append(OcclusionPhrases.Word(text: part, box: OcclusionBox(
                    x: left / 900, y: top / 640, w: Double(part.count) * 12 / 900, h: (bottom - top) / 640)))
                left += Double(part.count) * 12 + 6
            }
        }
    }
    return out
}

let words = heartWords()
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

// MARK: O2 Reveal takes off the one asked, and only it

for card in deck.prefix(1) {
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
