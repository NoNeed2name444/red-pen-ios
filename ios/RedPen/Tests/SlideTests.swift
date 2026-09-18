// Reading a PowerPoint, and working out which page a card came off.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: slide order

let names = ["ppt/slides/slide10.xml", "ppt/slides/slide2.xml",
             "ppt/slides/slide1.xml", "ppt/media/image1.png",
             "ppt/slides/_rels/slide1.xml.rels", "docProps/app.xml"]
let slides = PptxText.slidePaths(in: names)
// plain sorting puts slide10 second, which silently reorders the lecture
check("slides come back in the order they are shown",
      slides == ["ppt/slides/slide1.xml", "ppt/slides/slide2.xml",
                 "ppt/slides/slide10.xml"], "\(slides)")
check("the relationship files are not slides",
      !slides.contains { $0.contains("_rels") }, "\(slides)")
check("a deck with no slides is not an error",
      PptxText.slidePaths(in: ["docProps/app.xml"]).isEmpty)

// MARK: slide text

let slide = """
<p:sld><p:cSld><p:spTree>\
<p:sp><p:txBody><a:p><a:r><a:t>Systemic lupus erythematosus</a:t></a:r></a:p></p:txBody></p:sp>\
<p:sp><p:txBody>\
<a:p><a:r><a:t>Malar rash spares the nasolabial fold</a:t></a:r></a:p>\
<a:p><a:r><a:t>Discoid rash is chronic &amp; scarring</a:t></a:r></a:p>\
</p:txBody></p:sp></p:spTree></p:cSld></p:sld>
"""
let text = PptxText.text(fromSlideXML: slide)
check("the title comes through", text.contains("Systemic lupus erythematosus"), text)
// one run per line, or a bulleted slide arrives as one long sentence and the
// generator makes a single card out of three facts
check("each bullet is its own line",
      text.components(separatedBy: "\n").count == 3,
      text.replacingOccurrences(of: "\n", with: " | "))
check("an ampersand survives", text.contains("chronic & scarring"), text)
check("an attribute on the run is not mistaken for text",
      PptxText.text(fromSlideXML: "<a:t dirty=\"0\">kidney</a:t>") == "kidney",
      PptxText.text(fromSlideXML: "<a:t dirty=\"0\">kidney</a:t>"))
check("an empty slide gives nothing rather than crashing",
      PptxText.text(fromSlideXML: "<p:sld/>").isEmpty)

// MARK: which page a card came off

let document = SourceText.Document(pages: [
    SourceText.Page(number: 1, text: "Introduction to connective tissue disease", recognised: false),
    SourceText.Page(number: 2, text: "Malar rash spares the nasolabial fold and is reversible", recognised: false),
    SourceText.Page(number: 3, text: "Lupus nephritis class IV is treated with cyclophosphamide", recognised: false),
])

check("a question lands on the page it came from",
      Provenance.page(for: "Which rash spares the nasolabial fold?", in: document.pages) == 2,
      "\(Provenance.page(for: "Which rash spares the nasolabial fold?", in: document.pages) ?? -1)")
check("a different fact lands on its own page",
      Provenance.page(for: "cyclophosphamide in class IV nephritis", in: document.pages) == 3)
// a question that matches nothing is a question that drifted from the source,
// and saying nothing is more honest than naming a page at random
check("a question matching nothing is left uncited",
      Provenance.page(for: "Which cranial nerve supplies the stapedius?",
                      in: document.pages) == nil)
check("an empty question is not attributed",
      Provenance.page(for: "", in: document.pages) == nil)
check("a document with no pages attributes nothing",
      Provenance.page(for: "malar rash", in: []) == nil)

let question = MCQQuestion(stem: "A woman has a facial rash. Which is it?",
                           options: ["Malar rash", "Discoid rash"], correctIndex: 0,
                           explanation: "It spares the nasolabial fold.")
let cited = Provenance.attribute([question], to: document, name: "Lupus")
check("the citation names the file and the page",
      cited.first?.source == "Lupus, p. 2", cited.first?.source ?? "none")

var known = AnkiCard(type: .qa, front: "malar rash", bullets: ["spares the nasolabial fold"])
known.source = "Lupus, p. 14"
let recited = Provenance.attribute([known], to: document, name: "Lupus")
// a figure card knows its page exactly; a guess must never overwrite that
check("a card that already knows its page keeps it",
      recited.first?.source == "Lupus, p. 14", recited.first?.source ?? "none")

let bare = AnkiCard(type: .qa, front: "Which rash is reversible?",
                    bullets: ["the malar rash"])
check("a card with no source gets one",
      Provenance.attribute([bare], to: document, name: "Lupus").first?.source == "Lupus, p. 2")
check("a nameless file still cites the page",
      Provenance.label("", page: 3) == "p. 3")

print(failures.isEmpty ? "\nALL SLIDE TESTS PASS"
                       : "\n\(failures.count) SLIDE TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
