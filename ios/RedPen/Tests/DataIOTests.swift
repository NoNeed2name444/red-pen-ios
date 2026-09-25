// Data in and out: Anki packages of every generation (and the zstd inside
// the newer ones), spreadsheets from Quizlet, Sheets and Anki's text export,
// tags, and the whole-library backup's format and merge.
//
// The .apkg/.colpkg fixtures in Tests/Fixtures were written by Anki itself
// (the `anki` Python package, 26.09) - Basic, Basic-and-reversed, Cloze,
// Anki's own image occlusion, an Image Occlusion Enhanced note with its SVG
// mask, a subdeck, tags and one reviewed card - and the .zst files by the
// reference zstd library. The whole risk in reading a file format is that a
// real file is laid out differently from the one in your head.
import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

/// The fixtures folder, from the repository root (CI) or beside it.
func fixture(_ name: String) -> URL? {
    let roots = ["ios/RedPen/Tests/Fixtures", "rp-prev/ios/RedPen/Tests/Fixtures",
                 ProcessInfo.processInfo.environment["FIXTURES"] ?? ""]
    for root in roots where !root.isEmpty {
        let url = URL(fileURLWithPath: root).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }
    }
    return nil
}

// MARK: - zstd

let vectors: [(String, Int, UInt32)] = [
    ("zstd-text-19.zst", 190_172, 937_892_548),     // Huffman literals, FSE tables, checksum
    ("zstd-mixed-3.zst", 24_150, 3_021_568_868),    // many blocks, treeless literals, repeat tables
    ("zstd-binary-1.zst", 90_000, 1_033_784_869),   // level 1: raw and RLE literals
]
for (name, size, crc) in vectors {
    guard let url = fixture(name), let packed = try? Data(contentsOf: url) else {
        check("fixture \(name) is there", false)
        continue
    }
    do {
        let plain = try Zstd.decompress(packed)
        check("zstd: \(name) decodes to the reference bytes", plain.count == size && MiniZip.crc32(plain) == crc,
              "\(plain.count) bytes, crc \(MiniZip.crc32(plain))")
    } catch {
        check("zstd: \(name) decodes", false, "\(error)")
    }
}
// a small frame, typed out: "hello hello hello zstd" at level 3
let tiny = Data(base64Encoded: "KLUv/SAWhQAAUGhlbGxvIHpzdGQBAOFKEQ==")!
check("zstd: a small frame with one match", (try? Zstd.decompress(tiny)).map { String(decoding: $0, as: UTF8.self) } == "hello hello hello zstd",
      "\((try? Zstd.decompress(tiny)).map { String(decoding: $0, as: UTF8.self) } ?? "error")")
check("zstd: two frames back to back are both read",
      (try? Zstd.decompress(tiny + tiny))?.count == 44)
if let url = fixture("zstd-text-19.zst"), let packed = try? Data(contentsOf: url) {
    // hostile variants: none may crash, all must end
    var survived = true
    for cut in stride(from: 5, to: packed.count, by: 997) {
        _ = try? Zstd.decompress(packed.prefix(cut))
    }
    var flipped = [UInt8](packed)
    for i in stride(from: 13, to: flipped.count, by: 211) { flipped[i] ^= 0x5A }
    _ = try? Zstd.decompress(Data(flipped))
    check("zstd: cut-short and corrupted frames fail cleanly", survived)
    survived = false
    do { _ = try Zstd.decompress(packed, limit: 1_000) } catch Zstd.Failure.tooLarge { survived = true } catch {}
    check("zstd: output past the limit is refused, not allocated", survived)
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("zstd-\(UUID().uuidString).bin")
    try? Zstd.decompress(packed, to: out)
    let written = (try? Data(contentsOf: out)) ?? Data()
    check("zstd: streaming to a file gives the same bytes", MiniZip.crc32(written) == 937_892_548)
    try? FileManager.default.removeItem(at: out)
}
check("zstd: not zstd at all is said so", (try? Zstd.decompress(Data("PK\u{3}\u{4}".utf8))) == nil)

// MARK: - Anki field text

let field = AnkiNoteText.plain("<div>Aortic <b>stenosis</b>&nbsp;&amp; <i>MR</i></div><div><br></div><div>Age &gt; 65 [sound:x.mp3]<img src=\"heart.png\"></div>")
check("html: tags gone, bold kept as **, entities decoded, blank lines dropped",
      field.text == "Aortic **stenosis** & MR\nAge > 65", field.text.debugDescription)
check("html: pictures handed back by name", field.images == ["heart.png"], "\(field.images)")
check("html: an unquoted src and odd case", AnkiNoteText.plain("<IMG SRC=a_b.jpg>").images == ["a_b.jpg"])
check("html: numeric entities", AnkiNoteText.plain("&#945;&#x3B2; &le; 5").text == "\u{3b1}\u{3b2} \u{2264} 5")
check("html: a lone < is text", AnkiNoteText.plain("Na < 135").text == "Na < 135")
check("html: scripts are not text", AnkiNoteText.plain("a<script>alert(1)</script>b").text == "ab")
check("html: cloze markers survive", AnkiNoteText.plain("<b>{{c1::Digoxin}}</b> blocks").text == "**{{c1::Digoxin}}** blocks")
check("templates: fields shown, FrontSide and conditionals skipped",
      AnkiNoteText.fieldsShown(in: "{{FrontSide}}<hr id=answer>{{#Extra}}{{Back}} {{text:Extra}}{{/Extra}}") == ["Back", "Extra"])
check("templates: a type-in box is not a question",
      AnkiNoteText.fieldsShown(in: "{{Front}}\n{{type:Back}}", front: true) == ["Front"])
check("templates: the cloze field", AnkiNoteText.clozeField(in: "{{cloze:Text}}<br>{{Back Extra}}") == "Text")
check("tags: Anki's space-separated list", AnkiNoteText.tags(" #AK_Step1::Cardio  pharm ") == ["#AK_Step1::Cardio", "pharm"])
check("decks: both separators", AnkiNoteText.deckPath("A::B") == ["A", "B"] && AnkiNoteText.deckPath("A\u{1f}B") == ["A", "B"])

// image occlusion shapes
let shapes = AnkiNoteText.occlusions("{{c1::image-occlusion:rect:left=.1:top=.2:width=.3:height=.1:oi=1}}{{c2::image-occlusion:ellipse:left=.5:top=.5:rx=.1:ry=.05}}{{c2::image-occlusion:polygon:points=0.1,0.8 0.3,0.9 0.2,0.95}}")
check("occlusion: every cloze number read", shapes.keys.sorted() == [1, 2], "\(shapes.keys.sorted())")
let two = AnkiNoteText.union(shapes[2] ?? [])
func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
let unionOK: Bool = two.map { near($0.x, 0.1) && near($0.w, 0.6) && near($0.y, 0.5) } ?? false
check("occlusion: shapes under one number are one box", unionOK, "\(String(describing: two))")
let pixels = AnkiNoteText.occlusions("{{c1::image-occlusion:rect:left=20:top=10:width=50:height=20}}", pixelSize: (200, 100))
check("occlusion: pixel shapes become fractions", pixels[1]?.first == OcclusionBox(x: 0.1, y: 0.1, w: 0.25, h: 0.2))
check("occlusion: pixel shapes with no size are skipped, not stretched",
      AnkiNoteText.occlusions("{{c1::image-occlusion:rect:left=20:top=10:width=50:height=20}}").isEmpty)
let svg = "<svg width=\"200\" height=\"100\"><rect x=\"20\" y=\"10\" width=\"50\" height=\"20\" class=\"qshape\"/><rect x=\"100\" y=\"60\" width=\"40\" height=\"10\"/></svg>"
let mask = AnkiNoteText.svgMask(svg)
check("enhanced occlusion: the qshape is the target", mask?.target == OcclusionBox(x: 0.1, y: 0.1, w: 0.25, h: 0.2))
check("enhanced occlusion: the other masks are its covers", mask?.others.count == 1)

// decks into sets
func deck(_ path: [String], _ count: Int, picture: String? = nil) -> AnkiNoteText.Deck {
    var d = AnkiNoteText.Deck(path: path)
    if let picture { d.pictures = [picture] }
    for i in 0..<count {
        var c = AnkiCard(type: .qa, front: "\(path.joined()) \(i)", bullets: ["a"])
        if picture != nil { c.imageIndex = 0 }
        d.cards.append(c)
    }
    return d
}
let planned = AnkiNoteText.plan([deck(["Cardio"], 3), deck(["Cardio", "Valves"], 2), deck(["Renal"], 1)])
check("plan: a set per deck, top-level decks as folders",
      planned.map(\.name) == ["Cardio", "Valves", "Renal"] && planned.map { $0.folder ?? "-" } == ["Cardio", "Cardio", "Renal"],
      "\(planned.map(\.name)) \(planned.map { $0.folder ?? "-" })")
let single = AnkiNoteText.plan([deck(["Pharm"], 4)])
check("plan: one deck is one set, not in a folder", single.count == 1 && single.first?.folder == nil)
var many: [AnkiNoteText.Deck] = []
for i in 0..<30 { many.append(deck(["Top", "Block\(i / 10)", "Sub\(i)"], 1)) }
let cut = AnkiNoteText.plan(many, maxSets: 5)
check("plan: a deep tree is cut where the set count fits", cut.count == 3, "\(cut.map(\.name))")
let merged = AnkiNoteText.plan([deck(["A", "x"], 2, picture: "p.png"), deck(["A", "y"], 2, picture: "p.png")], maxSets: 1)
check("plan: merged decks share a picture once", merged.first?.deck.pictures == ["p.png"]
      && merged.first?.deck.cards.allSatisfy { $0.imageIndex == 0 } == true)
let parts = AnkiNoteText.plan([deck(["Huge"], 7_001)], maxCards: 3_000)
check("plan: a huge deck is split into parts", parts.map { $0.deck.cards.count } == [3_000, 3_000, 1_001]
      && parts.first?.name == "Huge (1 of 3)", "\(parts.map(\.name))")
let built = AnkiNoteText.studySet(planned[0], subject: "Cardio", folderId: nil) { _ in nil }
check("set: the deck's place becomes the set's tag", built.tags == ["Cardio"] && built.kind == .anki)
var occ = AnkiNoteText.Deck(path: ["P"])
occ.pictures = ["gone.png"]
var occCard = AnkiCard(type: .occlusion)
occCard.imageIndex = 0
occCard.occlusion = OcclusionBox(x: 0, y: 0, w: 0.1, h: 0.1)
occ.cards = [occCard, AnkiCard(type: .qa, front: "q", bullets: ["a"], imageIndex: 0)]
let noPicture = AnkiNoteText.studySet(AnkiNoteText.PlannedSet(name: "P", folder: nil, deck: occ), subject: "", folderId: nil) { _ in nil }
check("set: an occlusion card without its picture is left out; a basic card keeps its words",
      noPicture.cards.count == 1 && noPicture.cards.first?.type == .qa && noPicture.cards.first?.imageIndex == nil)

// schedule
let created = Date(timeIntervalSince1970: 1_790_308_800)
let review = AnkiProgress.from(type: 2, queue: 2, due: 5, interval: 12, reps: 4, lapses: 1, created: created,
                               now: created)
check("progress: a review card keeps its interval, reviews and lapses",
      review?.intervalDays == 12 && review?.reviews == 4 && review?.lapses == 1)
check("progress: its due day counts from the collection's creation",
      review.map { Int($0.due.timeIntervalSince(created) / 86_400) } == 5)
check("progress: a new card brings nothing", AnkiProgress.from(type: 0, queue: 0, due: 3, interval: 0, reps: 0, lapses: 0, created: created) == nil)
let learning = AnkiProgress.from(type: 1, queue: 1, due: 1_790_400_000, interval: -600, reps: 1, lapses: 0, created: created)
check("progress: a learning card's due is a moment", learning?.due == Date(timeIntervalSince1970: 1_790_400_000))
check("progress: suspended is kept", AnkiProgress.from(type: 2, queue: -1, due: 1, interval: 3, reps: 2, lapses: 0, created: created)?.suspended == true)

// MARK: - real packages

func imported(_ name: String) -> ApkgImport.Package? {
    guard let url = fixture(name) else { check("fixture \(name) is there", false); return nil }
    do { return try ApkgImport.read(url) } catch { check("\(name) opens", false, "\(error)"); return nil }
}
for name in ["anki-legacy.apkg", "anki-latest.apkg", "anki-latest.colpkg"] {
    guard let package = imported(name) else { continue }
    let cards = package.sets.flatMap { $0.deck.cards }
    check("\(name): every note read (\(package.format))", package.noteCount == 6 && package.ankiCardCount == 9,
          "\(package.noteCount) notes, \(package.ankiCardCount) cards")
    check("\(name): never the 'please update Anki' stub",
          !cards.contains { $0.front.contains("Please update") || $0.clozeText.contains("Please update") })
    check("\(name): subdecks became sets in folders",
          package.sets.map(\.name).contains("Valves") && package.sets.first { $0.name == "Valves" }?.folder == "Cardio",
          "\(package.sets.map { "\($0.name)/\($0.folder ?? "-")" })")
    let basic = cards.first { $0.front.hasPrefix("Most common valve lesion") }
    check("\(name): a basic note's answer lines are bullets",
          basic?.bullets == ["Aortic stenosis", "Calcific degeneration", "Age > 65"], "\(basic?.bullets ?? [])")
    check("\(name): tags kept, nested ones whole", basic?.tags == ["#AK_Step1::Cardio", "valves"], "\(basic?.tags ?? [])")
    check("\(name): a reversed note is two cards",
          cards.contains { $0.front == "Furosemide" && $0.bullets == ["Loop diuretic"] }
          && cards.contains { $0.front == "Loop diuretic" && $0.bullets == ["Furosemide"] })
    let cloze = cards.first { $0.type == .cloze }
    check("\(name): a cloze note keeps every cN and its hint",
          cloze?.clozeText == "{{c1::Digoxin}} inhibits the {{c2::Na/K ATPase::pump}}" && cloze?.why == "Narrow window",
          cloze?.clozeText ?? "none")
    let io = cards.filter { $0.type == .occlusion && $0.front == "Kidney" }
    check("\(name): Anki's image occlusion is a card per mask, each covering the others",
          io.count == 2 && io.allSatisfy { $0.siblings.count == 1 && $0.imageIndex != nil },
          "\(io.count) \(io.map { $0.siblings.count })")
    let ioe = cards.first { $0.front == "Brachial plexus" }
    check("\(name): the Enhanced add-on's SVG mask is read", ioe?.occlusion == OcclusionBox(x: 0.1, y: 0.1, w: 0.25, h: 0.2)
          && ioe?.siblings.count == 1 && ioe?.why == "Upper trunk", "\(String(describing: ioe?.occlusion))")
    let picture = cards.first { $0.front.hasPrefix("**Heart**") }
    check("\(name): a picture on a basic card comes with it", picture?.imageIndex != nil && package.pictureCount == 3,
          "\(package.pictureCount)")
    let valves = package.sets.first { $0.name == "Valves" }
    check("\(name): Anki's schedule comes with the reviewed card",
          valves?.deck.progress.values.first.map { $0.intervalDays == 12 && $0.reviews == 4 } == true
          && package.reviewedCards == 1)
    let files = package.media.values.filter { FileManager.default.fileExists(atPath: $0.path) }
    check("\(name): the pictures are taken out, under safe names",
          files.count == package.media.count && files.allSatisfy { $0.lastPathComponent.hasPrefix("m") })
    if let heart = package.media["heart.png"], let bytes = try? Data(contentsOf: heart) {
        check("\(name): a picture's bytes are the picture (zstd undone)", bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
    package.discard()
    check("\(name): its working folder is removed", !FileManager.default.fileExists(atPath: package.folder.path))
}
if let url = fixture("anki-latest.apkg"), let data = try? Data(contentsOf: url) {
    var options = ApkgImport.Options()
    options.includePictures = false
    if let lean = try? ApkgImport.read(data: data, options: options) {
        let cards = lean.sets.flatMap { $0.deck.cards }
        check("pictures off: basic cards lose theirs, occlusion cards keep theirs",
              cards.first { $0.front.hasPrefix("**Heart**") }?.imageIndex == nil
              && cards.filter { $0.type == .occlusion }.allSatisfy { $0.imageIndex != nil }
              && lean.picturesLeftOut == 1, "\(lean.picturesLeftOut)")
        lean.discard()
    }
    options = ApkgImport.Options()
    options.pictureBudget = 0
    if let none = try? ApkgImport.read(data: data, options: options) {
        check("no picture budget: occlusion cards are left out and counted",
              none.occlusionCardsLeftOut == 3 && none.sets.flatMap { $0.deck.cards }.allSatisfy { $0.type != .occlusion },
              "\(none.occlusionCardsLeftOut)")
        none.discard()
    }
}
check("not a package: a plain zip is refused",
      (try? ApkgImport.read(data: Data("PK\u{5}\u{6}".utf8) + Data(count: 18))) == nil)
var threw: ApkgImport.Failure?
do { _ = try ApkgImport.read(data: Data("hello".utf8)) } catch let f as ApkgImport.Failure { threw = f } catch {}
check("not a package: said plainly", threw == .notAPackage, "\(String(describing: threw))")

// MARK: - spreadsheets

let quizlet = "Furosemide\tLoop diuretic\nDigoxin\tNa/K ATPase inhibitor\nAtenolol\tBeta-1 blocker"
check("TSV: Quizlet's export is a table", PlainTextImport.looksDelimited(quizlet))
let q = PlainTextImport.parseAnyCards(quizlet)
check("TSV: a card per line, term on the front", q.count == 3 && q.first?.front == "Furosemide" && q.first?.bullets == ["Loop diuretic"])
let csv = "Front,Back,Tags\n\"Na, K\",\"Line one\nline two\",renal pharm\n\"Say \"\"hi\"\"\",Hello,\n"
let c = PlainTextImport.parseAnyCards(csv)
check("CSV: header found, quoted commas and line breaks kept", c.count == 2 && c.first?.front == "Na, K"
      && c.first?.bullets == ["Line one", "line two"], "\(c.map(\.front)) \(c.first?.bullets ?? [])")
check("CSV: doubled quotes are one quote", c.last?.front == "Say \"hi\"", c.last?.front ?? "")
check("CSV: the tags column becomes tags", c.first?.tags == ["renal", "pharm"], "\(c.first?.tags ?? [])")
check("CSV: separator found", PlainTextImport.detectSeparator("a;b\nc;d\ne;f") == ";")
let anki = "#separator:tab\n#html:true\n#tags column:3\nFront<br>side\t<b>Back</b> &amp; more\tcardio\n{{c1::Aorta}} is big\tExtra\t\n"
let a = PlainTextImport.parseAnyCards(anki)
check("Anki text export: headers read, HTML undone, cloze kept",
      a.count == 2 && a.first?.front == "Front\nside" && a.first?.bullets == ["**Back** & more"] && a.first?.tags == ["cardio"]
      && a.last?.type == .cloze, "\(a.map { $0.front + "|" + $0.clozeText })")
check("pipe lines still read the old way", PlainTextImport.parseAnyCards("Front | a; b | why").first?.bullets == ["a", "b"])
check("pipe lines are not a table", !PlainTextImport.looksDelimited("Front | a; b | why\nQ | x | y"))
let sheet = "Question,A,B,C,D,Answer,Explanation\nMost common cause?,Calcific,Rheumatic,Congenital,IE,A,Age\nWhich?,x,y,z,w,4,\n"
let mq = PlainTextImport.parseAnyMCQ(sheet)
check("CSV questions: option columns, a letter or a number as the key",
      mq.count == 2 && mq.first?.correctIndex == 0 && mq.first?.explanation == "Age" && mq.last?.correctIndex == 3,
      "\(mq.map(\.correctIndex))")
let joinedOptions = PlainTextImport.parseAnyMCQ("Stem\tOptions\tCorrect\nWhich?\tAlpha; Beta; Gamma\tBeta")
check("TSV questions: one options cell, the key as the option's words", joinedOptions.first?.correctIndex == 1)
check("an opened question sheet is read as questions", PlainTextImport.holdsQuestions(sheet)
      && PlainTextImport.holdsQuestions("Stem\tOptions\tCorrect\nWhich?\tAlpha; Beta; Gamma\tBeta"))
check("an opened Quizlet or front/back table is read as cards", !PlainTextImport.holdsQuestions(quizlet)
      && !PlainTextImport.holdsQuestions(csv) && !PlainTextImport.holdsQuestions("Question,Answer\nWhat?,That\n"))
check("a BOM does not become part of the first card",
      PlainTextImport.parseAnyCards("\u{feff}Term\tDef\nA\tB").first?.front == "A")

// MARK: - tags

check("tags: typed words become tags", CardTags.parse("cardio pharm cardio") == ["cardio", "pharm"])
check("tags: a comma list keeps spaces as _", CardTags.parse("heart failure, renal") == ["heart_failure", "renal"])
check("tags: adding twice adds once", CardTags.adding("Cardio", to: ["cardio"]) == ["cardio"])
check("tags: removing the last leaves nothing stored", CardTags.removing("x", from: ["x"]) == nil)
check("tags: a chip shows the last level", CardTags.label("#AK_Step1::Cardio") == "Cardio")
let search = CardTags.query("aortic tag:pharm #AK_Step1 valve")
check("search: tag words pulled out of the text", search.text == "aortic valve" && search.tags == ["pharm", "AK_Step1"])
check("search: a parent tag finds its children", CardTags.tag("#AK_Step1::Cardio", isUnder: "ak_step1"))
check("search: a prefix of a name is not a parent", !CardTags.tag("pharmacology", isUnder: "pharm"))
check("search: a deeper level is found by its own name", CardTags.tag("#AK_Step1_v12::#B&B::Cardio", isUnder: "cardio")
      && CardTags.tag("#AK_Step1::Cardio::HF", isUnder: "#cardio") && CardTags.tag("a::b::c", isUnder: "b::c"))
check("search: whole levels only", !CardTags.tag("#AK_Step1::Cardiology", isUnder: "cardio")
      && !CardTags.tag("a::b::c", isUnder: "a::c"))
var tagged = StudySet(name: "T", kind: .anki)
tagged.cards = [AnkiCard(type: .qa, front: "a", bullets: ["b"]), AnkiCard(type: .qa, front: "c", bullets: ["d"])]
tagged.cards[1].tags = ["renal::loop"]
check("search: only the tagged cards of a set", CardTags.tagged(tagged, with: ["renal"])?.cards.count == 1)
tagged.tags = ["renal"]
check("search: a set's tag covers every card", CardTags.tagged(tagged, with: ["renal"])?.cards.count == 2)
check("search: nothing tagged is nil", CardTags.tagged(tagged, with: ["neuro"]) == nil)
let counted = CardTags.counts(in: [tagged])
check("counts: most used first", counted.first?.tag == "renal" && counted.first?.count == 1 && counted.count == 2)
check("suggestions: what starts with the typing, not what is chosen",
      CardTags.suggestions(for: "ren", from: counted, excluding: ["renal"]) == ["renal::loop"])

// MARK: - old files still read

let oldCard = #"{"id":"6B1C3E1A-9C34-4E2C-8A5E-1F9E4D2B7A10","type":"qa","front":"Q","bullets":["A"]}"#
let decodedCard = try? JSONDecoder().decode(AnkiCard.self, from: Data(oldCard.utf8))
check("an old card without tags decodes", decodedCard?.tags == nil && decodedCard?.front == "Q")
var withTags = AnkiCard(type: .qa, front: "Q", bullets: ["A"])
withTags.tags = ["x"]
let round = (try? JSONEncoder().encode(withTags)).flatMap { try? JSONDecoder().decode(AnkiCard.self, from: $0) }
check("tags survive a save", round?.tags == ["x"])
let untagged = String(decoding: (try? JSONEncoder().encode(AnkiCard(type: .qa, front: "Q", bullets: ["A"]))) ?? Data(), as: UTF8.self)
check("an untagged card writes no tags at all", !untagged.contains("tags"))
let oldQuestion = #"{"id":"6B1C3E1A-9C34-4E2C-8A5E-1F9E4D2B7A11","stem":"S","options":["a","b"],"correctIndex":1,"explanation":"e"}"#
check("an old question without tags decodes",
      (try? JSONDecoder().decode(MCQQuestion.self, from: Data(oldQuestion.utf8)))?.tags == nil)
let oldSet = #"{"id":"6B1C3E1A-9C34-4E2C-8A5E-1F9E4D2B7A12","name":"S","kind":"anki"}"#
check("an old set without tags decodes", (try? JSONDecoder().decode(StudySet.self, from: Data(oldSet.utf8)))?.tags == nil)

// MARK: - backup

let cardA = AnkiCard(type: .qa, front: "A", bullets: ["a"])
let cardB = AnkiCard(type: .qa, front: "B", bullets: ["b"])
var here = StudySet(name: "Here", kind: .anki)
here.cards = [cardA]
var gone = StudySet(name: "Gone", kind: .anki)
gone.cards = [cardB]
var changed = here
changed.cards.append(AnkiCard(type: .qa, front: "A2", bullets: ["a2"]))
var fresh = StudySet(name: "New", kind: .mcq)
fresh.questions = [MCQQuestion(stem: "s", options: ["x", "y"], correctIndex: 0, explanation: "")]
let folder = StudyFolder(name: "Block 1")
fresh.folderId = folder.id
let backup = LibraryBackup.Library(library: [here, gone, fresh], folders: [folder])
let same = LibraryBackup.plan(backup: backup, library: [here], folders: [], deleted: [gone.id])
check("restore: an unchanged set is left alone", same.unchanged == 1)
check("restore: a deleted set comes back under a new id", same.returned == 1
      && same.sets.contains { $0.name == "Gone" && $0.id != gone.id } && same.setIDs[gone.id] != nil)
check("restore: a new set joins, its folder with it", same.added == 1 && same.folders.map(\.name) == ["Block 1"]
      && same.sets.first { $0.name == "New" }?.folderId == folder.id)
check("restore: the returned set's cards keep their ids, so their schedule follows",
      same.sets.first { $0.name == "Gone" }?.cards.first?.id == cardB.id)
let differs = LibraryBackup.plan(backup: LibraryBackup.Library(library: [changed], folders: []),
                                 library: [here], folders: [], deleted: [])
let copy = differs.sets.first
check("restore: a set that differs comes in beside this one", differs.copies == 1 && copy?.name == "Here (from backup)"
      && copy?.id != here.id)
check("restore: the copy's shared cards get new ids; the schedule stays with this phone's",
      copy?.cards.first?.id != cardA.id && differs.sharedItems.contains(cardA.id)
      && copy?.cards.last?.id == changed.cards.last?.id)
let records: [UUID: Int] = [cardA.id: 1, changed.cards[1].id: 2]
check("restore: only schedules of cards not already here", LibraryBackup.schedule(records, plan: differs) == [changed.cards[1].id: 2])
let sameName = LibraryBackup.plan(backup: backup, library: [], folders: [StudyFolder(name: "block 1")], deleted: [])
check("restore: a folder of the same name is used, not doubled", sameName.folders.isEmpty
      && sameName.sets.first { $0.name == "New" }?.folderId != folder.id)
let folderGone = LibraryBackup.plan(backup: backup, library: [], folders: [], deleted: [folder.id])
let returnedFolder = folderGone.folders.first
check("restore: a folder deleted here comes back under a new id", folderGone.folders.count == 1
      && returnedFolder?.name == "Block 1" && returnedFolder?.id != folder.id)
check("restore: its sets follow the returned folder",
      returnedFolder != nil && folderGone.sets.first { $0.name == "New" }?.folderId == returnedFolder?.id)
check("restore: study logs keep the bigger day", LibraryBackup.mergeDays(["d1": 3, "d2": 1], ["d1": 1, "d3": 4]) == ["d1": 3, "d2": 1, "d3": 4])
check("settings: this app's kept, sign-in and keys never",
      LibraryBackup.keepsSetting("exam.date") && LibraryBackup.keepsSetting("reminder.bedtime")
      && !LibraryBackup.keepsSetting("session") && !LibraryBackup.keepsSetting("llm.providers")
      && !LibraryBackup.keepsSetting("AppleLanguages") && !LibraryBackup.keepsSetting("backup.lastDate"))
check("settings: only what this phone has not set", LibraryBackup.settingsToApply(["exam.date": 1.0, "exam.track": "x"],
                                                                                 existing: ["exam.date"]).keys.sorted() == ["exam.track"])
check("files: no path climbs out", LibraryBackup.isSafeFileName("abc.pdf") && !LibraryBackup.isSafeFileName("../x")
      && !LibraryBackup.isSafeFileName("a/b") && !LibraryBackup.isSafeFileName(".hidden"))
check("file name: dated", LibraryBackup.fileName(app: "Stethoscore", date: Date(timeIntervalSince1970: 1_790_308_800))
      .hasPrefix("Stethoscore Backup 2026-09-"))
check("file name: the app's own backup type, so other apps offer Open in Stethoscore",
      LibraryBackup.fileName(app: "Stethoscore", date: Date()).hasSuffix(".stethoscorebackup"))

// the archive itself, written with MiniZip and read back
let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
let manifest = LibraryBackup.Manifest(createdAt: Date(timeIntervalSince1970: 1_790_308_800), app: "Test",
                                      counts: LibraryBackup.counts(of: [here], notes: 2, scheduled: 1, studyDays: 3, files: 1))
let backupParts: [(String, Data)] = [
    (LibraryBackup.Name.manifest, (try? LibraryBackup.encoder.encode(manifest)) ?? Data()),
    (LibraryBackup.Name.library, (try? LibraryBackup.encoder.encode(LibraryBackup.Library(library: [here], folders: []))) ?? Data()),
    (LibraryBackup.Name.sources + "lecture.pdf", Data(repeating: 7, count: 3_000_000)),
    (LibraryBackup.Name.sources + "../escape.pdf", Data("x".utf8)),
]
var entries: [(name: String, file: URL)] = []
for (index, part) in backupParts.enumerated() {
    let url = folderURL.appendingPathComponent("part\(index)")
    try? part.1.write(to: url)
    entries.append((part.0, url))
}
let zipURL = folderURL.appendingPathComponent("backup.zip")
try? MiniZip.write(files: entries, to: zipURL)
do {
    let archive = try LibraryBackup.Archive(url: zipURL)
    let written = (try? Data(contentsOf: zipURL)) ?? Data()
    let nameLength = written.count > 30 ? Int(written[26]) | (Int(written[27]) << 8) : 0
    let firstName = written.count >= 30 + nameLength ? String(decoding: written[30..<(30 + nameLength)], as: UTF8.self) : ""
    check("archive: the manifest is the first entry, so the first bytes say it is a backup",
          firstName == LibraryBackup.Name.manifest, firstName)
    check("archive: the manifest is read", archive.manifest.counts.sets == 1 && archive.manifest.app == "Test")
    let library = archive.decode(LibraryBackup.Library.self, LibraryBackup.Name.library)
    check("archive: the library is read", library?.library.first?.cards.first?.id == cardA.id)
    let listed = archive.files(under: LibraryBackup.Name.sources)
    check("archive: files listed, a climbing name refused", listed.map(\.name) == ["lecture.pdf"], "\(listed.map(\.name))")
    if let entry = listed.first?.entry {
        let out = folderURL.appendingPathComponent("restored.pdf")
        try archive.extract(entry, to: out)
        check("archive: a big file comes out whole", (try? Data(contentsOf: out))?.count == 3_000_000)
    }
} catch {
    check("archive opens", false, "\(error)")
}
var refused: LibraryBackup.Failure?
do { _ = try LibraryBackup.Archive(data: (try? Data(contentsOf: fixture("anki-latest.apkg")!)) ?? Data()) }
catch let f as LibraryBackup.Failure { refused = f } catch {}
check("archive: an Anki file is not a backup", refused == .notABackup)
var newer = manifest
newer.version = 99
var tooNew = false
do { try LibraryBackup.check(newer) } catch LibraryBackup.Failure.newerVersion { tooNew = true } catch {}
check("archive: a newer version's backup is refused with a reason", tooNew)
try? FileManager.default.removeItem(at: folderURL)

print(failures.isEmpty ? "\nALL DATA IN/OUT TESTS PASS"
                       : "\n\(failures.count) DATA IN/OUT TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
