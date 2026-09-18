// What has to be true of text pulled out of a lecture file.
//
// PDFKit and Vision are not tested here - they are Apple's and they need a
// device. What is tested is every decision Red Pen makes about the text
// afterwards, because those decisions are what end up on a card.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: words broken across a line

check("a hyphenated break becomes one word",
      SourceIngest.joinHyphenated("give hydroxy-\nchloroquine daily")
        == "give hydroxychloroquine daily",
      SourceIngest.joinHyphenated("give hydroxy-\nchloroquine daily"))
check("a real hyphen at the end of a line is not swallowed",
      SourceIngest.joinHyphenated("anti-\ninflammatory") == "antiinflammatory",
      SourceIngest.joinHyphenated("anti-\ninflammatory"))
check("a dash on its own is left alone",
      SourceIngest.joinHyphenated("first line\n-\nsecond").contains("-"))
check("ordinary text is unchanged",
      SourceIngest.joinHyphenated("one\ntwo") == "one\ntwo")

// MARK: the furniture

let deck = [
    "Systemic lupus erythematosus\nDr Ahmed Fathy\nInternal Medicine 2026\n1",
    "Diagnostic criteria\nDr Ahmed Fathy\nInternal Medicine 2026\n2",
    "Treatment\nDr Ahmed Fathy\nInternal Medicine 2026\n3",
    "Prognosis\nDr Ahmed Fathy\nInternal Medicine 2026\n4",
    "Summary\nDr Ahmed Fathy\nInternal Medicine 2026\n5",
]
let furniture = SourceIngest.runningLines(deck)
check("the lecturer's name on every page is furniture",
      furniture.contains("Dr Ahmed Fathy"), "\(furniture)")
check("the course line is furniture too",
      furniture.contains("Internal Medicine 2026"))
check("the actual content of a page is not furniture",
      !furniture.contains("Treatment") && !furniture.contains("Prognosis"),
      "\(furniture)")

let cleaned = SourceIngest.clean(deck[1], dropping: furniture)
check("a cleaned page keeps its content", cleaned == "Diagnostic criteria", cleaned)
check("and loses the page number", !cleaned.contains("2"), cleaned)

check("a bare number is furniture", SourceIngest.isPageFurniture(" 12 "))
check("so is 'Page 4'", SourceIngest.isPageFurniture("Page 4"))
check("but a real line is not",
      !SourceIngest.isPageFurniture("10 points classify SLE"))
// a number that is the whole point of a slide must survive
check("a line that merely contains numbers is kept",
      SourceIngest.clean("Classified at 10 points or more") == "Classified at 10 points or more")

// A short document has no majority to measure, and guessing on three pages
// would throw away a heading that happens to repeat twice.
check("a two-page document has no furniture",
      SourceIngest.runningLines(["Title\nDr Ahmed Fathy", "More\nDr Ahmed Fathy"]).isEmpty)

// MARK: tidying

check("runs of blank lines collapse",
      SourceIngest.clean("one\n\n\n\ntwo") == "one\n\ntwo",
      SourceIngest.clean("one\n\n\n\ntwo").replacingOccurrences(of: "\n", with: "|"))
check("leading and trailing space goes",
      SourceIngest.clean("\n\n  Treatment  \n\n") == "Treatment")
check("an empty page cleans to nothing rather than crashing",
      SourceIngest.clean("") == "")

// MARK: what the generator is handed

let document = SourceIngest.Document(
    pages: [SourceIngest.Page(number: 1, text: "Systemic lupus erythematosus", recognised: false),
            SourceIngest.Page(number: 2, text: "Malar rash spares the folds", recognised: true)],
    figures: [])
check("the pages join into one source text",
      document.text == "Systemic lupus erythematosus\n\nMalar rash spares the folds",
      document.text)
// OCR text is good enough to study from and not good enough to trust silently,
// so the count is carried rather than discarded
check("how much of it came from OCR is known", document.recognisedPages == 1)

print(failures.isEmpty ? "\nALL INGEST TESTS PASS"
                       : "\n\(failures.count) INGEST TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
