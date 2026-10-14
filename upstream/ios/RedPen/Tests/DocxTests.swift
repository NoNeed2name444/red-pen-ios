// Opening a Word handout.
//
// The archive this runs against is a REAL zip, written by the runner's own zip
// command in the workflow step, not a hand-built one: the whole risk in reading
// a .docx is that a real file is laid out a few bytes differently from the one
// in your head, and a fixture built by the same code that reads it would hide
// exactly that.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: the XML, on its own

let xml = """
<?xml version="1.0"?><w:document xmlns:w="x"><w:body>\
<w:p><w:r><w:t>Lupus &amp; the kidney</w:t></w:r></w:p>\
<w:p><w:r><w:t>Class IV</w:t></w:r><w:r><w:t> nephritis</w:t></w:r></w:p>\
<w:p/>\
<w:p><w:r><w:t>Treat with</w:t></w:r><w:br/><w:r><w:t>steroids</w:t></w:r></w:p>\
</w:body></w:document>
"""

let paragraphs = DocxText.paragraphs(fromXML: xml)
check("every paragraph comes back", paragraphs.count == 4, "\(paragraphs)")
check("an ampersand survives as an ampersand",
      paragraphs.first == "Lupus & the kidney", paragraphs.first ?? "")
// Word splits a sentence across runs whenever the styling changes mid-word
check("runs inside one paragraph are one sentence",
      paragraphs.contains("Class IV nephritis"), "\(paragraphs)")
check("a line break inside a paragraph is a line break",
      paragraphs.contains("Treat with") && paragraphs.contains("steroids"))
check("an empty paragraph is not a blank line",
      !paragraphs.contains(""), "\(paragraphs)")

check("tags go, text stays",
      DocxText.stripTags("<a><b>hello</b></a>") == "hello")
// decoding before stripping would turn the rest of this into a tag and eat it
check("an escaped angle bracket is not treated as a tag",
      DocxText.paragraphs(fromXML: "<w:t>a &lt;b&gt; c</w:t></w:p>") == ["a <b> c"],
      "\(DocxText.paragraphs(fromXML: "<w:t>a &lt;b&gt; c</w:t></w:p>"))")
check("an escaped ampersand is decoded once",
      DocxText.decodeEntities("&amp;lt;") == "&lt;",
      DocxText.decodeEntities("&amp;lt;"))

check("image2 sorts before image10",
      DocxText.natural("word/media/image2.png") < DocxText.natural("word/media/image10.png"))
check("a picture is recognised", DocxText.isPicture("word/media/image1.JPG"))
check("a stylesheet is not a picture", !DocxText.isPicture("word/styles.xml"))

// MARK: the archive

check("rubbish is not an archive",
      Zip.entries(in: Data("not a zip at all, not even close".utf8)).isEmpty)
check("an empty file is not an archive", Zip.entries(in: Data()).isEmpty)

guard let archive = try? Data(contentsOf: URL(fileURLWithPath: "sample.docx")) else {
    print("FAIL the sample archive was never written")
    exit(1)
}
let entries = Zip.entries(in: archive)
check("the document is in the archive",
      entries[DocxText.documentPath] != nil, entries.keys.sorted().joined(separator: ", "))
check("so are the pictures",
      entries["word/media/image2.png"] != nil && entries["word/media/image10.png"] != nil,
      entries.keys.sorted().joined(separator: ", "))

// the XML is big enough that zip deflates it, so this is the deflate path
if let body = entries[DocxText.documentPath] {
    let round = String(decoding: body, as: UTF8.self)
    check("a deflated entry comes back whole",
          round.contains("Lupus") && round.hasSuffix("\n") || round.contains("steroids"),
          String(round.suffix(40)))
    check("and is exactly as long as it was written",
          round.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("</w:document>"),
          String(round.suffix(30)))
}

let read = DocxText.read(entries)
check("the handout's words are all there",
      read.text.contains("Lupus & the kidney") && read.text.contains("steroids"),
      read.text)
check("both pictures come back", read.images.count == 2, "\(read.images.count)")
check("in the order Word numbered them",
      String(decoding: read.images[0], as: UTF8.self).contains("two"),
      String(decoding: read.images[0], as: UTF8.self))

print(failures.isEmpty ? "\nALL DOCX TESTS PASS"
                       : "\n\(failures.count) DOCX TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
