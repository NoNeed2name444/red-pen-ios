// Opening a Word or PowerPoint file that somebody else made.
//
// A handout arrives from a group chat and is opened the moment it is picked, so
// the zip reader is the app's front door for hostile files. These archives are
// built here, byte by byte, precisely BECAUSE they are not what any zip tool
// would write: a size field that lies, ten thousand directory entries sharing
// one stream, a stream that never ends. DocxTests covers a real archive written
// by the runner's own zip command.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: building archives by hand

/// Bits into bytes the way deflate packs them: least significant first.
struct Bits {
    var bytes: [UInt8] = []
    var used = 8

    mutating func put(_ value: UInt32, _ count: Int) {
        for shift in 0..<count {
            if used == 8 { bytes.append(0); used = 0 }
            if (value >> UInt32(shift)) & 1 == 1 { bytes[bytes.count - 1] |= UInt8(1 << used) }
            used += 1
        }
    }

    /// A Huffman code, which deflate writes most significant bit first.
    mutating func code(_ value: UInt32, _ count: Int) {
        for shift in stride(from: count - 1, through: 0, by: -1) { put((value >> UInt32(shift)) & 1, 1) }
    }
}

/// A deflate stream of `1 + 258 * repeats` zero bytes, in one fixed-Huffman
/// block: a literal zero, then "copy 258 bytes from one back" over and over.
/// About 160 to 1, which is plenty to test a ceiling with.
func zeros(repeats: Int, finished: Bool = true) -> Data {
    var bits = Bits()
    bits.put(1, 1)                     // the last block
    bits.put(1, 2)                     // fixed Huffman codes
    bits.code(0x30, 8)                 // literal 0
    for _ in 0..<repeats {
        bits.code(0b1100_0101, 8)      // length 258
        bits.code(0, 5)                // distance 1
    }
    if finished { bits.code(0, 7) }    // end of block
    return Data(bits.bytes)
}

/// Byte runs joined - one call rather than a long chain of `+`, which is slow
/// for the compiler to type-check.
func bytes(_ runs: [UInt8]...) -> [UInt8] { runs.flatMap { $0 } }

func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)] }
func le32(_ value: Int) -> [UInt8] {
    [UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)]
}

struct Part {
    var name: String
    var method: Int
    var body: Data
    /// The uncompressed size the archive CLAIMS.
    var claimed: Int
}

/// A zip of `parts`, plus `aliases` extra directory entries that all point at
/// the first part's local header under names of their own - the overlapping
/// bomb, which inflates one stream once per name.
func archive(_ parts: [Part], aliases: Int = 0) -> Data {
    var out: [UInt8] = []
    var central: [UInt8] = []
    var offsets: [Int] = []
    for part in parts {
        let name = Array(part.name.utf8)
        offsets.append(out.count)
        out += bytes(le32(0x0403_4b50), le16(20), le16(0), le16(part.method), le16(0), le16(0))
        out += bytes(le32(0), le32(part.body.count), le32(part.claimed))
        out += bytes(le16(name.count), le16(0), name, Array(part.body))
    }
    func entry(_ part: Part, named name: [UInt8], at offset: Int) {
        central += bytes(le32(0x0201_4b50), le16(20), le16(20), le16(0), le16(part.method))
        central += bytes(le16(0), le16(0), le32(0), le32(part.body.count), le32(part.claimed))
        central += bytes(le16(name.count), le16(0), le16(0), le16(0), le16(0), le32(0), le32(offset))
        central += name
    }
    for (part, offset) in zip(parts, offsets) { entry(part, named: Array(part.name.utf8), at: offset) }
    if let first = parts.first {
        for alias in 0..<aliases { entry(first, named: Array("word/media/copy\(alias).png".utf8), at: offsets[0]) }
    }
    let count = parts.count + (parts.isEmpty ? 0 : aliases)
    let start = out.count
    out += central
    out += bytes(le32(0x0605_4b50), le16(0), le16(0), le16(count), le16(count))
    out += bytes(le32(central.count), le32(start), le16(0))
    return Data(out)
}

func stored(_ name: String, _ text: String) -> Part {
    let body = Data(text.utf8)
    return Part(name: name, method: 0, body: body, claimed: body.count)
}

let small = Zip.Limits(entryBytes: 1 << 20, totalBytes: 3 << 20, ratio: 1_100)

// MARK: honest archives still open

let honest = zeros(repeats: 4_000)       // 1,032,001 bytes, many output chunks
let plain = archive([stored("word/document.xml", "<w:t>hello</w:t>"),
                     Part(name: "word/media/image1.png", method: 8, body: honest, claimed: 1 + 258 * 4_000)])
let opened = Zip.entries(in: plain)
check("a stored entry comes back as it was",
      opened["word/document.xml"].map { String(decoding: $0, as: UTF8.self) } == "<w:t>hello</w:t>",
      "\(opened.keys.sorted())")
check("a deflated entry comes back whole, across many chunks",
      opened["word/media/image1.png"]?.count == 1 + 258 * 4_000,
      "\(opened["word/media/image1.png"]?.count ?? -1)")
check("and is what was deflated",
      opened["word/media/image1.png"]?.allSatisfy { $0 == 0 } == true)

let listed = Zip.directory(of: plain)
check("the directory lists without reading",
      listed.map(\.name) == ["word/document.xml", "word/media/image1.png"], "\(listed.map(\.name))")

let onlyText = Zip.entries(in: plain) { $0 == "word/document.xml" }
check("only the entries asked for are read",
      Array(onlyText.keys) == ["word/document.xml"], "\(onlyText.keys.sorted())")

// the file as a slice of a bigger buffer: offsets are the archive's, not the buffer's
let padded = (Data(repeating: 7, count: 13) + plain).dropFirst(13)
check("an archive that is a slice of a larger buffer still opens",
      Zip.entries(in: padded)["word/document.xml"] != nil)

// MARK: size fields that lie

// Case 1: an entry CLAIMING four gigabytes is refused before anything is
// allocated; the old reader sized its buffer from this field.
let claimsHuge = archive([Part(name: "word/document.xml", method: 8, body: zeros(repeats: 10),
                               claimed: 0xFFFF_FFFF),
                          stored("word/media/image1.png", "picture")])
let hugeRead = Zip.entries(in: claimsHuge)
check("an entry claiming four gigabytes is refused",
      hugeRead["word/document.xml"] == nil, "\(hugeRead.keys.sorted())")
check("without losing the rest of the archive",
      hugeRead["word/media/image1.png"] != nil, "\(hugeRead.keys.sorted())")

// Case 2: an entry claiming to be small that inflates far past its ceiling.
let bomb = zeros(repeats: 40_000)          // about 10 MB of zeros from about 65 KB
let lying = archive([Part(name: "word/document.xml", method: 8, body: bomb, claimed: 1_000),
                     stored("ppt/slides/slide1.xml", "<a:t>still here</a:t>")])
let started = Date()
let lyingRead = Zip.entries(in: lying, limits: small)
check("an entry that inflates past its ceiling is dropped, not cut short",
      lyingRead["word/document.xml"] == nil, "\(lyingRead["word/document.xml"]?.count ?? -1)")
check("and the entries beside it are still read",
      lyingRead["ppt/slides/slide1.xml"] != nil)
check("and it gives up at the ceiling rather than inflating everything",
      Date().timeIntervalSince(started) < 2, "\(Date().timeIntervalSince(started))s")

// a claimed size that deflate could never reach from so few bytes
let impossible = archive([Part(name: "a.xml", method: 8, body: zeros(repeats: 2), claimed: 900_000)])
check("a claimed ratio deflate cannot reach is refused",
      Zip.entries(in: impossible)["a.xml"] == nil)
let strict = Zip.Limits(entryBytes: 64 << 20, totalBytes: 256 << 20, ratio: 50)
let ratioRead = Zip.entries(in: archive([Part(name: "a.xml", method: 8, body: zeros(repeats: 4_000), claimed: 10)]),
                            limits: strict)
check("an entry that turns out denser than the ratio allows is refused",
      ratioRead["a.xml"] == nil, "\(ratioRead["a.xml"]?.count ?? -1)")

// MARK: many entries, one stream

// Case 3: ten thousand names pointing at one local header. The old reader
// inflated the same stream once per name and kept every copy.
let overlapping = archive([Part(name: "word/media/image1.png", method: 8, body: zeros(repeats: 4_000),
                                claimed: 1 + 258 * 4_000)], aliases: 10_000)
let overlapRead = Zip.entries(in: overlapping)
check("entries sharing one stream are read once",
      overlapRead.count == 1, "\(overlapRead.count) entries")
check("the directory lists it once too",
      Zip.directory(of: overlapping).count == 1, "\(Zip.directory(of: overlapping).count)")

// Case 4: many honest-looking entries that add up past the archive's budget.
let many = archive((0..<8).map { Part(name: "ppt/media/image\($0).png", method: 8, body: zeros(repeats: 4_000),
                                      claimed: 1 + 258 * 4_000) })
let manyRead = Zip.entries(in: many, limits: small)
let total = manyRead.values.reduce(0) { $0 + $1.count }
check("the archive as a whole stops at its budget",
      total <= small.totalBytes && manyRead.count < 8, "\(manyRead.count) entries, \(total) bytes")
check("having read what fitted", manyRead.count >= 2, "\(manyRead.count)")

// MARK: broken files

let truncated = archive([Part(name: "a.xml", method: 8, body: zeros(repeats: 300, finished: false),
                              claimed: 1 + 258 * 300)])
let truncatedRead = Zip.entries(in: truncated)["a.xml"]
check("a stream that stops short neither hangs nor crashes",
      truncatedRead == nil || truncatedRead!.count <= 1 + 258 * 300, "\(truncatedRead?.count ?? -1)")
let reserved = Data([0xff, 0xff, 0xff, 0xff])   // a block type deflate does not have
check("a stream that is not deflate at all is refused",
      reserved.withUnsafeBytes { Zip.inflate($0, limit: 1 << 20).data } == nil)
var junk = Data("PK not really".utf8)
junk += Data(bytes(le32(0x0605_4b50), le16(0), le16(0), le16(9), le16(9), le32(500), le32(0x7fff_ffff), le16(0)))
check("a directory pointing past the end of the file reads as empty",
      Zip.entries(in: junk).isEmpty)
var outside = Array(plain)
// point the first entry's local header far outside the file
let cdStart = Int(outside[outside.count - 6]) | Int(outside[outside.count - 5]) << 8
outside[cdStart + 42] = 0xff; outside[cdStart + 43] = 0xff; outside[cdStart + 44] = 0xff
check("an entry whose header is outside the file is skipped, not a crash",
      Zip.entries(in: Data(outside))["word/document.xml"] == nil)
check("rubbish is not an archive",
      Zip.entries(in: Data("not a zip at all, not even close".utf8)).isEmpty)
check("an empty file is not an archive", Zip.entries(in: Data()).isEmpty)

// MARK: which parts of an Office file are worth opening

check("a slide is read", PptxText.isNeeded("ppt/slides/slide3.xml", pictures: false))
check("a Word document is read", PptxText.isNeeded("word/document.xml", pictures: false))
check("a slide's relationships are not",
      !PptxText.isNeeded("ppt/slides/_rels/slide3.xml.rels", pictures: false))
check("an embedded lecture video never is",
      !PptxText.isNeeded("ppt/media/media1.mp4", pictures: true))
check("pictures only when diagrams are wanted",
      PptxText.isNeeded("ppt/media/image4.png", pictures: true)
        && !PptxText.isNeeded("ppt/media/image4.png", pictures: false))

// MARK: what Word shows, not what its XML holds

let tracked = """
<w:body><w:p><w:r><w:t>Dose: </w:t></w:r>\
<w:del w:id="1" w:author="A"><w:r><w:delText>500 mg</w:delText></w:r></w:del>\
<w:ins w:id="2" w:author="A"><w:r><w:t>250 mg</w:t></w:r></w:ins></w:p></w:body>
"""
check("a tracked deletion is not read as text",
      DocxText.paragraphs(fromXML: tracked) == ["Dose: 250 mg"], "\(DocxText.paragraphs(fromXML: tracked))")

let field = """
<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r>\
<w:r><w:instrText xml:space="preserve"> HYPERLINK "https://example.org" </w:instrText></w:r>\
<w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>the guideline</w:t></w:r>\
<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>
"""
check("a field's code is not read, its result is",
      DocxText.paragraphs(fromXML: field) == ["the guideline"], "\(DocxText.paragraphs(fromXML: field))")

let textBox = """
<w:p><w:r><mc:AlternateContent><mc:Choice Requires="wps"><w:drawing><wps:txbx><w:txbxContent>\
<w:p><w:r><w:t>Red flags</w:t></w:r></w:p></w:txbxContent></wps:txbx></w:drawing></mc:Choice>\
<mc:Fallback><w:pict><v:textbox><w:txbxContent><w:p><w:r><w:t>Red flags</w:t></w:r></w:p>\
</w:txbxContent></v:textbox></w:pict></mc:Fallback></mc:AlternateContent></w:r></w:p>
"""
check("a text box is read once, not twice",
      DocxText.paragraphs(fromXML: textBox) == ["Red flags"], "\(DocxText.paragraphs(fromXML: textBox))")

let tabs = """
<w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr>\
<w:r><w:t>Na</w:t></w:r><w:r><w:tab/><w:t>135</w:t></w:r><w:r><w:br w:type="page"/><w:t>K</w:t></w:r></w:p>
"""
check("a tab stop is a setting, a tab is a tab, and a page break is a break",
      DocxText.paragraphs(fromXML: tabs) == ["Na\t135", "K"], "\(DocxText.paragraphs(fromXML: tabs))")
check("a greater-than sign in the text stays",
      DocxText.paragraphs(fromXML: "<w:p><w:r><w:t>BP > 140</w:t></w:r></w:p>") == ["BP > 140"])

// MARK: a malformed slide cannot hang the import

let unclosed = String(repeating: "<a:t>x", count: 60_000)
let slideStarted = Date()
_ = PptxText.text(fromSlideXML: unclosed)
check("runs with no closing tag end the slide rather than rescanning it",
      Date().timeIntervalSince(slideStarted) < 2, "\(Date().timeIntervalSince(slideStarted))s")
let noGreater = String(repeating: "<a:t ", count: 60_000)
let attrStarted = Date()
_ = PptxText.text(fromSlideXML: noGreater)
check("and so do runs whose tag never closes",
      Date().timeIntervalSince(attrStarted) < 2, "\(Date().timeIntervalSince(attrStarted))s")
check("a run after an empty one is still read",
      PptxText.text(fromSlideXML: "<a:t lang=\"en\"/><a:t>aorta</a:t>") == "aorta",
      PptxText.text(fromSlideXML: "<a:t lang=\"en\"/><a:t>aorta</a:t>"))
check("the runs before an unclosed one are kept",
      PptxText.text(fromSlideXML: "<a:t>renal</a:t><a:t>artery") == "renal")

// MARK: slides that could not be read keep their numbers

let partial: [String: Data] = ["ppt/slides/slide1.xml": Data("<a:t>one</a:t>".utf8),
                               "ppt/slides/slide3.xml": Data("<a:t>three</a:t>".utf8)]
let every = ["ppt/slides/slide1.xml", "ppt/slides/slide2.xml", "ppt/slides/slide3.xml"]
let numbered = PptxText.pages(partial, slides: every)
check("a slide left unread does not renumber the rest",
      numbered.count == 3 && numbered[2].number == 3 && numbered[2].text == "three",
      "\(numbered.map { "\($0.number):\($0.text)" })")

print(failures.isEmpty ? "\nALL ZIP TESTS PASS"
                       : "\n\(failures.count) ZIP TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
