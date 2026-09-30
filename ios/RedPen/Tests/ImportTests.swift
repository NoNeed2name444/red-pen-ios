// What comes in from outside - text pasted from somebody's notes, a set shared
// from another phone - and what goes out to Anki.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: pasted text with Windows line endings

// In Swift "\r\n" is one Character, so splitting on "\n" found no lines at all
let windows = "Q1 | A;B;C;D | B | why\r\nQ2 | E;F;G;H | C | because\r\nQ3 | I;J | A | so"
let mcq = PlainTextImport.parseMCQ(windows)
check("a CRLF list is every question, not one", mcq.count == 3, "\(mcq.count)")
check("and nothing of the next line leaks into an explanation",
      mcq.first?.explanation == "why", mcq.first?.explanation ?? "")
check("old Mac line endings split too",
      PlainTextImport.parseMCQ("Q1 | A;B | A | x\rQ2 | A;B | B | y").count == 2)
let osce = PlainTextImport.parseOsce("## Knee exam\r\nInspect\r\nPalpate\r\n## Hip exam\r\nGait\r\n")
check("OSCE stations split on CRLF", osce.count == 2 && osce.first?.steps == ["Inspect", "Palpate"],
      "\(osce.map(\.title)) \(osce.first?.steps ?? [])")
check("Narrate lines split on CRLF",
      PlainTextImport.parseNarrate("en|One\r\nar|اثنان\r\nThree").count == 3)
check("Cards split on CRLF",
      PlainTextImport.parseAnkiQA("Front | a; b\r\n{{c1::Aorta}} carries blood | why").count == 2)
check("Cases split on CRLF",
      PlainTextImport.parseQA("Topic | case | Stem one? | ans\r\nTopic | recall | Stem two? | ans").count == 2)

// MARK: the answer letter

check("a blank answer letter is not quietly A",
      PlainTextImport.parseMCQ("Stem | a; b; c; d |  | why").isEmpty,
      "\(PlainTextImport.parseMCQ("Stem | a; b; c; d |  | why").map(\.correctIndex))")
check("a full-width letter is not quietly A",
      PlainTextImport.parseMCQ("Stem | a; b; c; d | \u{FF22} | why").isEmpty)
check("a digit is not a letter",
      PlainTextImport.parseMCQ("Stem | a; b; c; d | 2 | why").isEmpty)
check("a lower-case letter still counts",
      PlainTextImport.parseMCQ("Stem | a; b; c; d | c | why").first?.correctIndex == 2)
check("a letter past the options is refused",
      PlainTextImport.parseMCQ("Stem | a; b | D | why").isEmpty)
check("B is 1", PlainTextImport.optionIndex(" B ") == 1)

// MARK: a set shared from another phone

let folder = UUID()
var shared = StudySet(name: "Heart", subject: "Cardiology", kind: .anki)
shared.folderId = folder
shared.createdAt = Date(timeIntervalSince1970: 0)
shared.updatedAt = Date(timeIntervalSince1970: 0)
let picture = Data("jpeg bytes".utf8).base64EncodedString()
shared.images = [picture, "blob:" + String(repeating: "a", count: 64), picture]
shared.cards = [
    AnkiCard(type: .occlusion, front: "What is labelled here?", bullets: ["Aorta"], imageIndex: 0,
             occlusion: OcclusionBox(x: 0.1, y: 0.1, w: 0.1, h: 0.1)),
    AnkiCard(type: .occlusion, front: "What is labelled here?", bullets: ["Vena cava"], imageIndex: 1,
             occlusion: OcclusionBox(x: 0.2, y: 0.2, w: 0.1, h: 0.1)),
    AnkiCard(type: .occlusion, front: "What is labelled here?", bullets: ["Septum"], imageIndex: 2,
             occlusion: OcclusionBox(x: 0.3, y: 0.3, w: 0.1, h: 0.1)),
    AnkiCard(type: .qa, front: "Which valve?", bullets: ["Mitral"], imageIndex: 1),
]
shared.bookMarkdown = "# Heart\n![Front view](image:0)\n![Missing](image:1)\n![Side view](image:2)"

let now = Date(timeIntervalSince1970: 1_000_000)
let arrived = SetImport.received(shared, folders: [], now: now, isMissing: { $0.hasPrefix("blob:") })
check("a shared set gets an id of its own", arrived.set.id != shared.id)
check("a folder this library does not have is dropped, so the set can be seen",
      arrived.set.folderId == nil)
check("and it is dated as new here",
      arrived.set.createdAt == now && arrived.set.updatedAt == now)
check("a picture that only exists in the sender's account is left out",
      arrived.set.images == [picture, picture] && arrived.missingPictures == 1,
      "\(arrived.set.images.count) images, \(arrived.missingPictures) missing")
check("the occlusion card that needed it goes with it",
      !arrived.set.cards.contains { $0.bullets == ["Vena cava"] })
check("the cards after it point at their own picture still",
      arrived.set.cards.first { $0.bullets == ["Septum"] }?.imageIndex == 1,
      "\(arrived.set.cards.map { "\($0.bullets.first ?? ""):\($0.imageIndex ?? -1)" })")
check("a written card keeps its words and loses only the picture",
      arrived.set.cards.first { $0.front == "Which valve?" }.map { $0.imageIndex == nil } == true)
check("a textbook page points at the renumbered pictures and drops the missing one",
      arrived.set.bookMarkdown == "# Heart\n![Front view](image:0)\n![Side view](image:1)",
      arrived.set.bookMarkdown)
let home = SetImport.received(shared, folders: [folder], now: now, isMissing: { $0.hasPrefix("blob:") })
check("a folder this library DOES have is kept", home.set.folderId == folder)
var whole = shared
whole.images = [picture]
whole.cards = [shared.cards[0]]
let untouched = SetImport.received(whole, folders: [], now: now, isMissing: { $0.hasPrefix("blob:") })
check("a set with every picture comes in whole",
      untouched.missingPictures == 0 && untouched.set.cards.count == 1 && untouched.set.images == [picture])

// MARK: what goes into Anki

check("a cloze is escaped like any other field",
      AnkiFields.cloze("<img src=x onerror=alert(1)>{{c1::aorta}}")
        == "&lt;img src=x onerror=alert(1)&gt;{{c1::aorta}}",
      AnkiFields.cloze("<img src=x onerror=alert(1)>{{c1::aorta}}"))
check("ordinary medical text survives escaping",
      AnkiFields.cloze("{{c1::Na}} < 135 & K > 5") == "{{c1::Na}} &lt; 135 &amp; K &gt; 5")
check("bold still works inside a cloze",
      AnkiFields.cloze("{{c1::**aorta**}}") == "{{c1::<b>aorta</b>}}")
check("each cN is one card", AnkiFields.clozeOrdinals("{{c1::a}} {{c2::b}} {{c1::c}}") == [0, 1])
check("a c0 is not a card at ordinal -1", AnkiFields.clozeOrdinals("{{c0::a}}") == [0])
check("Anki's checksum reads the text, not the escaping",
      AnkiFields.stripped("<b>Na</b> &lt; 135 &amp;") == "Na < 135 &")

// MARK: the .apkg's zip

let folderURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("minizip-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
let first = folderURL.appendingPathComponent("a")
let second = folderURL.appendingPathComponent("b")
let big = Data((0..<3_000_000).map { UInt8($0 % 251) })   // several read chunks
try? Data("collection".utf8).write(to: first)
try? big.write(to: second)
let zipURL = folderURL.appendingPathComponent("deck.apkg")
var wrote = true
do { try MiniZip.write(files: [("collection.anki2", first), ("0", second)], to: zipURL) } catch { wrote = false }
check("the archive is written from files", wrote)
let back = (try? Data(contentsOf: zipURL)).map { Zip.entries(in: $0) } ?? [:]
check("and reads back entry for entry",
      back["collection.anki2"] == Data("collection".utf8) && back["0"] == big,
      "\(back.keys.sorted()) \(back["0"]?.count ?? -1)")
check("its CRC is the standard one",
      MiniZip.crc32(Data("123456789".utf8)) == 0xCBF4_3926,
      String(MiniZip.crc32(Data("123456789".utf8)), radix: 16))
var refused = false
do {
    let many = Array(repeating: (name: "x", file: first), count: 70_000)
    try MiniZip.write(files: many, to: folderURL.appendingPathComponent("many.apkg"))
} catch { refused = true }
check("more entries than a zip can count is an error, not a crash", refused)
try? FileManager.default.removeItem(at: folderURL)

print(failures.isEmpty ? "\nALL IMPORT TESTS PASS"
                       : "\n\(failures.count) IMPORT TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
