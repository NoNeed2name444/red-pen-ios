// What has to be true of text pulled out of a lecture file.
//
// PDFKit and Vision are not tested here - they are Apple's and they need a
// device. What IS tested is every decision Red Pen makes about the text
// afterwards, because those decisions are what end up on a card. They live in
// SourceText for exactly that reason.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: words broken across a line

check("a hyphenated break becomes one word",
      SourceText.joinHyphenated("give hydroxy-\nchloroquine daily")
        == "give hydroxychloroquine daily",
      SourceText.joinHyphenated("give hydroxy-\nchloroquine daily"))
check("a dash on its own is left alone",
      SourceText.joinHyphenated("first line\n-\nsecond").contains("-"))
check("ordinary text is unchanged",
      SourceText.joinHyphenated("one\ntwo") == "one\ntwo")

// MARK: the furniture

let deck = [
    "Systemic lupus erythematosus\nDr Ahmed Fathy\nInternal Medicine 2026\n1",
    "Diagnostic criteria\nDr Ahmed Fathy\nInternal Medicine 2026\n2",
    "Treatment\nDr Ahmed Fathy\nInternal Medicine 2026\n3",
    "Prognosis\nDr Ahmed Fathy\nInternal Medicine 2026\n4",
    "Summary\nDr Ahmed Fathy\nInternal Medicine 2026\n5",
]
let furniture = SourceText.runningLines(deck)
check("the lecturer's name on every page is furniture",
      furniture.contains("Dr Ahmed Fathy"), "\(furniture)")
check("the course line is furniture too",
      furniture.contains("Internal Medicine 2026"))
check("the actual content of a page is not furniture",
      !furniture.contains("Treatment") && !furniture.contains("Prognosis"),
      "\(furniture)")

let cleaned = SourceText.clean(deck[1], dropping: furniture)
check("a cleaned page keeps its content", cleaned == "Diagnostic criteria", cleaned)
check("and loses the page number", !cleaned.contains("2"), cleaned)

check("a bare number is furniture", SourceText.isPageFurniture(" 12 "))
check("so is 'Page 4'", SourceText.isPageFurniture("Page 4"))
check("but a real line is not",
      !SourceText.isPageFurniture("10 points classify SLE"))
// a number that is the whole point of a slide must survive
check("a line that merely contains numbers is kept",
      SourceText.clean("Classified at 10 points or more") == "Classified at 10 points or more")

// A short document has no majority to measure, and guessing on three pages
// would throw away a heading that happens to repeat twice.
check("a two-page document has no furniture",
      SourceText.runningLines(["Title\nDr Ahmed Fathy", "More\nDr Ahmed Fathy"]).isEmpty)

// MARK: tidying

check("runs of blank lines collapse",
      SourceText.clean("one\n\n\n\ntwo") == "one\n\ntwo",
      SourceText.clean("one\n\n\n\ntwo").replacingOccurrences(of: "\n", with: "|"))
check("leading and trailing space goes",
      SourceText.clean("\n\n  Treatment  \n\n") == "Treatment")
check("an empty page cleans to nothing rather than crashing",
      SourceText.clean("") == "")

// MARK: the finished document

let built = SourceText.document(from: [
    (1, deck[0], false), (2, deck[1], false), (3, deck[2], false),
    (4, deck[3], true), (5, deck[4], true),
])
check("the furniture is gone from the assembled document",
      !built.text.contains("Dr Ahmed Fathy"), built.text)
check("every page's content survives",
      built.text.contains("Treatment") && built.text.contains("Summary"), built.text)
// OCR text is good enough to study from and not good enough to trust silently,
// so how much of it there was is carried rather than discarded
check("how much came from OCR is known", built.recognisedPages == 2, "\(built.recognisedPages)")
check("a document with nothing in it says so",
      SourceText.document(from: [(1, "", true)]).isEmpty)

print(failures.isEmpty ? "\nALL INGEST TESTS PASS"
                       : "\n\(failures.count) INGEST TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
