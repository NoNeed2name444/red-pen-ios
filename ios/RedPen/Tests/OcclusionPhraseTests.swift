// One cover per label, and the answer is exactly what is under it.
//
// The covers on a diagram used to be one per OCR piece: "Superior vena" and
// "cava" were two covers, neighbouring covers overlapped once the screen grew
// them, and the answer was one OCR line rather than the words the cover hid.
// These cases are built from synthetic word boxes, the shape Vision reports.
import Foundation
import CoreGraphics

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

typealias Word = OcclusionPhrases.Word

func word(_ text: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double = 0.03,
          sure: Double = 1) -> Word {
    Word(text: text, box: OcclusionBox(x: x, y: y, w: w, h: h), confidence: sure)
}

/// Every phrase covered, no filter: the grouping and the covers on their own.
func coversOf(_ words: [Word], aspect: Double = 1) -> [OcclusionPhrases.Cover] {
    let phrases = OcclusionPhrases.group(words, aspect: aspect)
    return OcclusionPhrases.covers(for: phrases, words: words, aspect: aspect)
}

func overlap(_ a: OcclusionBox, _ b: OcclusionBox) -> Bool {
    let across = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
    let down = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
    return across > 1e-9 && down > 1e-9
}

func inside(_ inner: OcclusionBox, _ outer: OcclusionBox) -> Bool {
    inner.x >= outer.x - 1e-9 && inner.y >= outer.y - 1e-9
        && inner.x + inner.w <= outer.x + outer.w + 1e-9
        && inner.y + inner.h <= outer.y + outer.h + 1e-9
}

/// The words lying under a cover, read top to bottom and left to right,
/// worked out independently of the code under test.
func wordsUnder(_ cover: OcclusionBox, in words: [Word]) -> String {
    let under = words.filter { overlap($0.box, cover) }
    let sorted = under.sorted { a, b in
        if abs(a.box.y - b.box.y) > 0.01 { return a.box.y < b.box.y }
        return a.box.x < b.box.x
    }
    return sorted.map(\.text).joined(separator: " ")
}

func noOverlaps(_ covers: [OcclusionPhrases.Cover]) -> Bool {
    for i in covers.indices {
        for j in covers.indices where j > i && overlap(covers[i].box, covers[j].box) { return false }
    }
    return true
}

// MARK: several words on one line are one cover

let line = [word("Superior", 0.10, 0.10, 0.08), word("vena", 0.19, 0.10, 0.04),
            word("cava", 0.24, 0.10, 0.04)]
let lineCovers = coversOf(line)
check("three words on one line make one cover", lineCovers.count == 1, "\(lineCovers.map(\.answer))")
check("its answer is the whole label", lineCovers.first?.answer == "Superior vena cava",
      "\(lineCovers.map(\.answer))")
check("every word of it is inside the cover",
      line.allSatisfy { w in lineCovers.first.map { inside(w.box, $0.box) } ?? false })
check("the line checks out", OcclusionPhrases.problems(lineCovers, words: line).isEmpty,
      "\(OcclusionPhrases.problems(lineCovers, words: line))")

// MARK: a label wrapped onto two lines is one cover

let wrapped = [word("Pulmonary", 0.60, 0.20, 0.10), word("trunk", 0.60, 0.236, 0.05)]
let wrappedCovers = coversOf(wrapped)
check("a two-line label makes one cover", wrappedCovers.count == 1, "\(wrappedCovers.map(\.answer))")
check("its answer reads across both lines", wrappedCovers.first?.answer == "Pulmonary trunk",
      "\(wrappedCovers.map(\.answer))")
check("both lines are under the one cover",
      wrapped.allSatisfy { w in wrappedCovers.first.map { inside(w.box, $0.box) } ?? false })

// centred lines, the second shorter, as a label is usually set
let centred = [word("Superior", 0.10, 0.50, 0.08), word("vena", 0.19, 0.50, 0.04),
               word("cava", 0.15, 0.535, 0.04)]
let centredCovers = coversOf(centred)
check("a centred wrapped label is one cover", centredCovers.count == 1
      && centredCovers[0].answer == "Superior vena cava", "\(centredCovers.map(\.answer))")

// right-aligned, as labels on the left of a diagram are
let rightAligned = [word("Inferior", 0.05, 0.70, 0.08), word("vena", 0.14, 0.70, 0.04),
                    word("cava", 0.14, 0.735, 0.04)]
check("a right-aligned wrapped label is one cover",
      coversOf(rightAligned).map(\.answer) == ["Inferior vena cava"], "\(coversOf(rightAligned).map(\.answer))")

// a word broken over the line with a hyphen is mended
let hyphen = [word("Pulmo-", 0.3, 0.3, 0.07), word("nary", 0.3, 0.335, 0.05),
              word("artery", 0.36, 0.335, 0.06)]
check("a hyphenated break is mended", coversOf(hyphen).map(\.answer) == ["Pulmonary artery"],
      "\(coversOf(hyphen).map(\.answer))")

// three lines at most
let four = [word("one", 0.1, 0.1, 0.05), word("two", 0.1, 0.135, 0.05),
            word("three", 0.1, 0.17, 0.05), word("four", 0.1, 0.205, 0.05)]
check("a label is at most three lines", coversOf(four).count >= 2, "\(coversOf(four).map(\.answer))")

// MARK: separate labels stay separate

// a column of labels, one under another, each its own
let column = [word("Right", 0.10, 0.40, 0.06), word("atrium", 0.17, 0.40, 0.07),
              word("Right", 0.10, 0.445, 0.06), word("ventricle", 0.17, 0.445, 0.09)]
let columnCovers = coversOf(column)
check("two labels one under the other are two covers", columnCovers.count == 2,
      "\(columnCovers.map(\.answer))")
check("each with its own answer",
      columnCovers.map(\.answer) == ["Right atrium", "Right ventricle"], "\(columnCovers.map(\.answer))")

// two labels on one baseline, a clear gap apart
let baseline = [word("Aorta", 0.10, 0.80, 0.06), word("Left", 0.20, 0.80, 0.04),
                word("atrium", 0.25, 0.80, 0.06)]
let baselineCovers = coversOf(baseline)
check("two labels along one line are two covers", baselineCovers.count == 2,
      "\(baselineCovers.map(\.answer))")
check("and neither answer takes the other's words",
      baselineCovers.map(\.answer) == ["Aorta", "Left atrium"], "\(baselineCovers.map(\.answer))")

// two labels close together that a leader line runs between
let leader = [word("Mitral", 0.5, 0.5, 0.06), word("valve", 0.5, 0.536, 0.05)]
let apart = OcclusionPhrases.group(leader, separated: { _ in true })
check("lines with a leader line between them are not joined", apart.count == 2, "\(apart.map(\.text))")
check("without one they are", OcclusionPhrases.group(leader).count == 1)

// a number beside a label is not part of it
let numbered = [word("3", 0.10, 0.60, 0.015), word("Aorta", 0.12, 0.60, 0.06)]
let numberedPhrases = OcclusionPhrases.group(numbered)
check("a number beside a label is its own piece",
      numberedPhrases.map(\.text).contains("Aorta") && numberedPhrases.count == 2,
      "\(numberedPhrases.map(\.text))")
let numberedCovers = OcclusionPhrases.covers(for: numberedPhrases.filter { $0.text == "Aorta" },
                                             words: numbered)
check("and the label's cover does not hide it",
      numberedCovers.count == 1 && !overlap(numberedCovers[0].box, numbered[0].box),
      "\(numberedCovers.map(\.box))")

// a heading beside a label is not part of it
let heading = [word("Kidney", 0.1, 0.1, 0.2, 0.1), word("cortex", 0.31, 0.12, 0.1, 0.04)]
check("a heading is not joined to a small label", OcclusionPhrases.group(heading).count == 2)

// MARK: overlapping boxes are one label

let twice = [word("Aorta", 0.40, 0.40, 0.08), word("Aorta", 0.405, 0.401, 0.08)]
let twiceCovers = coversOf(twice)
check("two overlapping readings of a word are one cover", twiceCovers.count == 1,
      "\(twiceCovers.map(\.answer))")
check("said once", twiceCovers.first?.answer == "Aorta", "\(twiceCovers.map(\.answer))")
check("both readings are under it",
      twice.allSatisfy { w in twiceCovers.first.map { inside(w.box, $0.box) } ?? false })
check("and it checks out", OcclusionPhrases.problems(twiceCovers, words: twice).isEmpty,
      "\(OcclusionPhrases.problems(twiceCovers, words: twice))")

// a line read whole and again word by word, overlapping
let doubled = [word("Left ventricle", 0.3, 0.3, 0.16), word("Left", 0.3, 0.301, 0.05),
               word("ventricle", 0.36, 0.301, 0.10)]
let doubledCovers = coversOf(doubled)
check("a line read twice over is one cover", doubledCovers.count == 1, "\(doubledCovers.map(\.answer))")
check("said once", doubledCovers.first?.answer == "Left ventricle", "\(doubledCovers.map(\.answer))")

// two phrases handed over separately whose boxes overlap share one cover
let a = OcclusionPhrases.Phrase(lines: [[0]], text: "Aortic", box: twice[0].box,
                                confidence: 1, lineHeight: 0.03)
let pieces = [word("Aortic", 0.40, 0.40, 0.08), word("arch", 0.46, 0.40, 0.05)]
let b = OcclusionPhrases.Phrase(lines: [[1]], text: "arch", box: pieces[1].box,
                                confidence: 1, lineHeight: 0.03)
let mergedCovers = OcclusionPhrases.covers(for: [a, b], words: pieces)
check("overlapping covers are merged into one", mergedCovers.count == 1
      && mergedCovers[0].answer == "Aortic arch", "\(mergedCovers.map(\.answer))")

// MARK: a crowded diagram: covers never overlap, answers are what is under them

let diagram: [Word] = [
    word("Superior", 0.02, 0.08, 0.10), word("vena", 0.13, 0.08, 0.05), word("cava", 0.13, 0.115, 0.05),
    word("Right", 0.02, 0.30, 0.06), word("atrium", 0.09, 0.30, 0.08),
    word("Right", 0.02, 0.345, 0.06), word("ventricle", 0.09, 0.345, 0.10),   // close under it
    word("Aorta", 0.70, 0.06, 0.07),
    word("Pulmonary", 0.70, 0.16, 0.11), word("trunk", 0.70, 0.196, 0.06),
    word("Left", 0.70, 0.30, 0.05), word("atrium", 0.76, 0.30, 0.07),
    word("Mitral", 0.70, 0.40, 0.07), word("valve", 0.78, 0.40, 0.06),
    word("Tricuspid", 0.30, 0.40, 0.11), word("valve", 0.42, 0.40, 0.06),
    word("Left", 0.70, 0.52, 0.05), word("ventricle", 0.76, 0.52, 0.10),
    word("Interventricular", 0.62, 0.62, 0.18), word("septum", 0.62, 0.656, 0.08),
    word("12", 0.50, 0.62, 0.02),                                                  // a stray number
]
let all = coversOf(diagram, aspect: 1.4)
check("one cover per label on a crowded diagram", all.count == 11, "\(all.map(\.answer))")
let expected: Set<String> = ["Superior vena cava", "Right atrium", "Right ventricle", "Aorta",
                             "Pulmonary trunk", "Left atrium", "Mitral valve", "Tricuspid valve",
                             "Left ventricle", "Interventricular septum", "12"]
check("the answers are the labels", Set(all.map(\.answer)) == expected, "\(all.map(\.answer))")
check("no cover overlaps another", noOverlaps(all), "\(all.map(\.box))")
let mismatched = all.filter { wordsUnder($0.box, in: diagram).replacingOccurrences(of: "- ", with: "") != $0.answer }
check("each answer is exactly the words under its cover", mismatched.isEmpty,
      mismatched.map { "\($0.answer) vs \(wordsUnder($0.box, in: diagram))" }.joined(separator: "; "))
check("the whole diagram checks out", OcclusionPhrases.problems(all, words: diagram, aspect: 1.4).isEmpty,
      "\(OcclusionPhrases.problems(all, words: diagram, aspect: 1.4))")
check("every cover is padded past its words when there is room",
      all.contains { c in c.answer == "Aorta" && c.box.h > 0.03 + 0.01 }, "\(all.map(\.box))")

// two labels almost touching still get covers that do not overlap
// (0.3 of a letter-height apart, the next one starting with a capital)
let tight = [word("Left", 0.10, 0.10, 0.05), word("atrium", 0.16, 0.10, 0.07),
             word("Aorta", 0.10, 0.139, 0.06)]
let tightCovers = coversOf(tight)
check("labels a hair apart: two covers", tightCovers.count == 2, "\(tightCovers.map(\.answer))")
check("that do not overlap", noOverlaps(tightCovers), "\(tightCovers.map(\.box))")
check("and each still covers its words",
      OcclusionPhrases.problems(tightCovers, words: tight).isEmpty,
      "\(OcclusionPhrases.problems(tightCovers, words: tight))")

// MARK: the checker catches a bad cover

var bad = lineCovers[0]
bad.box = OcclusionBox(x: 0.0, y: 0.0, w: 0.5, h: 0.5)
let stray = line + [word("Hilum", 0.3, 0.3, 0.06)]
check("a cover over a word not in its answer is caught",
      !OcclusionPhrases.problems([bad], words: stray).isEmpty)
var short = lineCovers[0]
short.box = OcclusionBox(x: 0.10, y: 0.10, w: 0.10, h: 0.03)
check("a cover a word sticks out of is caught", !OcclusionPhrases.problems([short], words: line).isEmpty)
var wrong = lineCovers[0]
wrong.answer = "Superior vena"
check("an answer that is not the words under it is caught",
      !OcclusionPhrases.problems([wrong], words: line).isEmpty)
let twoOver = [lineCovers[0], OcclusionPhrases.Cover(box: lineCovers[0].box, answer: "x", lines: [])]
check("overlapping covers are caught", !OcclusionPhrases.problems(twoOver, words: line).isEmpty)

// MARK: the filter judges whole phrases

let slide: [Word] = [
    word("Deep", 0.30, 0.40, 0.05, 0.04), word("inguinal", 0.36, 0.40, 0.09, 0.04),
    word("ring", 0.46, 0.40, 0.04, 0.04),
    word("Figure", 0.30, 0.60, 0.07, 0.04), word("2", 0.38, 0.60, 0.015, 0.04),
    word("Left", 0.60, 0.70, 0.05, 0.04),                                        // means nothing alone
    word("Pubic", 0.60, 0.40, 0.07, 0.04), word("tubercle", 0.68, 0.40, 0.10, 0.04),
    word("Femoral", 0.30, 0.80, 0.09, 0.04, sure: 0.2), word("vein", 0.40, 0.80, 0.05, 0.04, sure: 0.2),
]
let whole = OcclusionBox(x: 0, y: 0, w: 1, h: 1)
let laidOut = OcclusionPhrases.layout(slide, figure: whole, pageBands: false)
let answers = laidOut.map(\.answer)
check("a phrase is kept whole", answers.contains("Deep inguinal ring"), "\(answers)")
check("no piece of it is covered alone", !answers.contains("Deep") && !answers.contains("ring"), "\(answers)")
check("a figure number is not covered", !answers.contains { $0.hasPrefix("Figure") }, "\(answers)")
check("a direction alone is not covered", !answers.contains("Left"), "\(answers)")
check("an unsure reading is not covered", !answers.contains { $0.contains("Femoral") }, "\(answers)")
check("the labels that pass are covered", Set(answers) == ["Deep inguinal ring", "Pubic tubercle"], "\(answers)")
check("the laid-out covers check out", OcclusionPhrases.problems(laidOut, words: slide).isEmpty,
      "\(OcclusionPhrases.problems(laidOut, words: slide))")
let inked = OcclusionPhrases.layout(slide, figure: whole, pageBands: false, hasInk: { $0.x < 0.5 })
check("a phrase with no ink under it is not covered", inked.map(\.answer) == ["Deep inguinal ring"],
      "\(inked.map(\.answer))")

// MARK: cards

let cardCovers = coversOf([word("Aorta", 0.1, 0.1, 0.06), word("Aorta", 0.6, 0.6, 0.06),
                           word("Left", 0.1, 0.5, 0.05), word("atrium", 0.16, 0.5, 0.07)])
let cards = OcclusionPhrases.cards(from: cardCovers, imageIndex: 4)
check("one card per different label", cards.count == 2, "\(cards.map(\.bullets))")
check("each card's answer is its cover's words", cards.map(\.bullets) == [["Aorta"], ["Left atrium"]],
      "\(cards.map(\.bullets))")
check("its box is the cover", cards.first?.occlusion == cardCovers.first?.box)
check("every other cover rides along, the repeat too",
      cards.allSatisfy { $0.siblings.count == 2 }, "\(cards.map(\.siblings.count))")
check("the card points at its picture", cards.allSatisfy { $0.imageIndex == 4 })
check("one label is not a labelled diagram",
      OcclusionPhrases.cards(from: Array(cardCovers.prefix(1)), imageIndex: 0).isEmpty)

// MARK: the old entry point groups the same way

let joined = OcclusionFilter.joinedOnLines([
    OcclusionFilter.Line(text: "Superior vena", box: OcclusionBox(x: 0.1, y: 0.1, w: 0.13, h: 0.03)),
    OcclusionFilter.Line(text: "cava", box: OcclusionBox(x: 0.1, y: 0.136, w: 0.05, h: 0.03)),
])
check("the filter joins a wrapped label too", joined.map(\.text) == ["Superior vena cava"], "\(joined.map(\.text))")
check("and knows its line height", abs((joined.first?.textHeight ?? 0) - 0.03) < 1e-9)

print(failures.isEmpty ? "\nALL OCCLUSION PHRASE TESTS PASS"
                       : "\n\(failures.count) OCCLUSION PHRASE TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
