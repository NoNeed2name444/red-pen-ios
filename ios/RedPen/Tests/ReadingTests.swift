// What a Cases card's emphasis means, and how a textbook page is broken up.

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

func run(_ text: String, _ bold: Bool) -> Highlight.Run { Highlight.Run(text: text, bold: bold) }

// MARK: emphasis

ok(Highlight.runs("plain text") == [run("plain text", false)], "text with no markers is one plain run")
ok(Highlight.runs("the **key** term")
   == [run("the ", false), run("key", true), run(" term", false)],
   "a marked term is emboldened and the rest is left alone")
ok(Highlight.runs("**first** and **second**")
   == [run("first", true), run(" and ", false), run("second", true)],
   "two marked terms both work")
ok(Highlight.runs("**leading**") == [run("leading", true)],
   "a card that is nothing but a marked term")

// MARK: the characters medical writing is actually full of
//
// This is the whole reason this file exists. Read as Markdown, every one of
// these loses characters or swallows the rest of the line.

let underscores = "T_max_ and P_min_ rise"
ok(Highlight.plain(underscores) == underscores, "underscores are characters, not italics")

let numbered = "1. Give oxygen"
ok(Highlight.plain(numbered) == numbered, "a line starting with a number is not a list")

let bracketed = "Give adrenaline [1:1000] IM"
ok(Highlight.plain(bracketed) == bracketed, "square brackets are not a link")

let backtick = "the `sniff` position"
ok(Highlight.plain(backtick) == backtick, "backticks are not code")

let hash = "# of beats per minute"
ok(Highlight.plain(hash) == hash, "a hash is not a heading")

// MARK: markers that are not emphasis

ok(Highlight.runs("2 ** 3 is not emphasis") == [run("2 ** 3 is not emphasis", false)],
   "an unclosed pair stays as the asterisks somebody typed")
ok(Highlight.plain("**") == "**", "and so does a lone pair")
ok(Highlight.plain("****") == "****", "four asterisks emphasise nothing, so they stay")
ok(Highlight.runs("a ** b ** c")
   == [run("a ", false), run(" b ", true), run(" c", false)],
   "spaces inside the markers are kept, since they are part of what was typed")

// MARK: splitting a textbook

let book = """
Some words before any heading.

# The kidney
The nephron is the unit.

## Filtration
Blood arrives at the glomerulus.
"""
let pages = BookPages.split(book)
ok(pages.count == 3, "text before the first heading is a page of its own")
ok(pages[0].title == "Introduction", "and it is called Introduction")
ok(pages[1].title == "The kidney", "a heading names its page")
ok(pages[2].title == "Filtration", "at either level")
ok(pages[1].markdown.contains("The nephron is the unit."), "and carries the text under it")

ok(BookPages.split("").isEmpty, "an empty textbook has no pages")
ok(BookPages.split("   \n\n  ").isEmpty, "and neither does one with only whitespace")

// MARK: blocks
//
// A numbered list in a textbook is a sequence - the steps of a protocol, the
// stages of a disease. Redrawing it as anonymous bullets throws that away.

let blocks = BookPages.blocks("""
## Managing it
1. Give oxygen
2) Gain access
- Then reassess
* And again

| Stage | Finding |
| --- | --- |
| I | Normal |
""")

var bullets: [(String, String?)] = []
var headings = 0
var rows = 0
for block in blocks {
    switch block {
    case .bullet(let text, let marker): bullets.append((text, marker))
    case .heading: headings += 1
    case .row: rows += 1
    default: break
    }
}
ok(headings == 1, "the heading is a heading")
ok(bullets.count == 4, "every list line is a bullet")
ok(bullets[0].1 == "1." && bullets[1].1 == "2)",
   "a numbered line keeps its number, however it was punctuated")
ok(bullets[2].1 == nil && bullets[3].1 == nil, "an unnumbered one has no marker to keep")
ok(bullets.map(\.0) == ["Give oxygen", "Gain access", "Then reassess", "And again"],
   "and the marker is not repeated in the text")
ok(rows == 2, "a table's rows are rows, and its separator line is not one of them")

// The textbook's visual aids
let rich = BookPages.blocks("""
| Type | Feature |
| --- | --- |
| A | one |
> **Exam tip:** Remember this
```flow
Suspect it
If positive → confirm
```
![The brachial plexus](image:2)
""")
var header = 0, callouts: [String] = [], flows: [[String]] = [], pictures: [Int] = []
for block in rich {
    switch block {
    case .row(_, let isHeader): if isHeader { header += 1 }
    case .callout(let kind, _): callouts.append(kind)
    case .flow(let steps): flows.append(steps)
    case .image(let index, _): pictures.append(index)
    default: break
    }
}
ok(header == 1, "a table's first row, above the |---| line, is its header")
ok(callouts == ["Exam tip"], "a > **Exam tip:** line is an exam-tip callout")
ok(flows == [["Suspect it", "If positive \u{2192} confirm"]], "a flow block is a flowchart of its steps")
ok(pictures == [2], "a picture line points at the set's picture")

// one topic stays one page, and a page shows only the pictures it was given
let tidy = BookPages.tidyPage("## Lupus\n## Clinical features\n- rash\n![made up](image:9)", fallbackTitle: "Part 1", figures: [4])
ok(BookPages.split(tidy).count == 1, "a second ## inside a page becomes a section, not a new page")
ok(!tidy.contains("image:9") && tidy.contains("image:4"), "a picture the page was not given is dropped; one it was given is added")

// which figure goes on which page
let figs = [BookFigure(imageBase64: "x", page: 3, labels: ["brachial", "plexus", "radial", "nerve"]),
            BookFigure(imageBase64: "y", page: 9, labels: ["kidney", "nephron", "glomerulus"])]
let placed = BookFigures.assign(figs, to: ["The kidney: nephron and glomerulus filtration", "Brachial plexus: radial nerve injury"])
ok(placed == [[1], [0]], "each diagram goes on the page about its topic")
let squeezed = BookFigures.compact("![a](image:5)\ntext\n![b](image:2)", images: ["0","1","2","3","4","5"])
ok(squeezed.images == ["5", "2"] && squeezed.markdown.contains("image:0") && squeezed.markdown.contains("image:1"),
   "a set keeps only the pictures its pages show, renumbered")

print(failures == 0 ? "\nALL READING TESTS PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
