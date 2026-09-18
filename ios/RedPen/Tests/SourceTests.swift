// Searching a lecture, and reading a card's citation back apart.

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

func page(_ number: Int, _ text: String, ocr: Bool = false) -> SourceDoc.Page {
    SourceDoc.Page(number: number, text: text, recognised: ocr)
}

// MARK: a page knows how to describe itself

let blank = page(1, "   \n\n  ")
ok(blank.isBlank, "a page with nothing but whitespace is blank")
ok(blank.heading == "", "and offers no heading")

let titled = page(2, "\n\n  Glomerular disease  \nThe nephritic syndrome")
ok(titled.heading == "Glomerular disease",
   "a heading is the first line with anything on it, trimmed")

// MARK: searching

let pages = [
    page(1, "The nephrotic syndrome\nOedema, proteinuria, low albumin"),
    page(2, "Oedema is pitting oedema in most cases"),
    page(3, "Nothing relevant here at all"),
]

var found = SourceSearch.hits(for: "oedema", in: pages)
ok(found.count == 3, "every appearance is found, on every page")
ok(SourceSearch.pagesMatched(found) == 2, "across two pages")
ok(found.map(\.page) == [1, 2, 2], "in reading order")

ok(SourceSearch.hits(for: "OEDEMA", in: pages).count == 3, "case does not matter")
ok(SourceSearch.hits(for: "oedema", in: [page(1, "Œdema and oedema")]).count >= 1,
   "and neither do accents")

ok(SourceSearch.hits(for: "z", in: pages).isEmpty,
   "a single character is not a search, so it finds nothing rather than everything")
ok(SourceSearch.hits(for: "  ", in: pages).isEmpty, "nor is whitespace")

// MARK: the snippet marks the right occurrence
//
// The second "oedema" on page 2 must be marked at ITS position, not at the
// first one's - searching the snippet again is exactly how that goes wrong.

let onPageTwo = found.filter { $0.page == 2 }
ok(onPageTwo.count == 2, "both appearances on one page are separate hits")
for hit in onPageTwo {
    let chars = Array(hit.snippet)
    ok(hit.range.lowerBound >= 0 && hit.range.upperBound <= chars.count,
       "the marked range lies inside its own snippet")
    let marked = String(chars[hit.range]).lowercased()
    ok(marked == "oedema", "and marks the word itself, not something near it")
}

// MARK: a match at the very start, and at the very end

let edge = [page(1, "Oedema")]
let only = SourceSearch.hits(for: "Oedema", in: edge)
ok(only.count == 1 && only[0].range.lowerBound == 0,
   "a match at the start of a page is marked from the start")
ok(!only[0].snippet.hasPrefix("…"), "and has nothing elided before it")

// MARK: overlapping matches cannot loop
//
// Advancing by one character instead of past the match makes "aa" in "aaaa"
// match for ever. The limit would hide it; the count is what catches it.

let repeated = SourceSearch.hits(for: "aa", in: [page(1, "aaaa")])
ok(repeated.count == 2, "overlapping matches advance past the match, not into it")

// MARK: citations

ok(Citation.read("Immunology, p. 12") == Citation.Reference(name: "Immunology", page: 12),
   "the app's own citation format is read back")
ok(Citation.read("p. 7") == Citation.Reference(name: "", page: 7),
   "a citation with no document name still names a page")
ok(Citation.read("Renal block, page 3")?.page == 3, "so does one that spells out 'page'")
ok(Citation.read("Notes, pp. 14-16")?.page == 14, "a range opens at its first page")
ok(Citation.read("Lecture 2, p. 5")?.name == "Lecture 2",
   "a number in the document's own name is not mistaken for the page")
ok(Citation.read("Lecture 2, p. 5")?.page == 5, "and the page is still the page")

ok(Citation.read(nil) == nil, "no citation is not a citation")
ok(Citation.read("") == nil, "nor is an empty one")
ok(Citation.read("Immunology") == nil, "nor a document name with no page")
ok(Citation.read("p. 0") == nil, "and page zero is not a page")

print(failures == 0 ? "\nALL SOURCE TESTS PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
