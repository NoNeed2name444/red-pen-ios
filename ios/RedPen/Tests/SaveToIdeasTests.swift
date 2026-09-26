// Save to Ideas: the title a note gets from a question or a card, the key
// that stops the same item being saved twice, the folder a subject's notes
// go in, what a save writes and adds, and the backlink - as stored on the
// note and as a link.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let setA = UUID()
let setB = UUID()
let item = UUID()

// MARK: titles

let stem = "A 54-year-old man has crushing chest pain for 2 hours. His ECG shows ST elevation in II, III and aVF. Which artery is blocked?"
check("title is the first sentence",
      SaveToIdeas.title(from: stem) == "A 54-year-old man has crushing chest pain for 2 hours.",
      SaveToIdeas.title(from: stem))
check("a decimal does not end the sentence",
      SaveToIdeas.title(from: "pH 7.1 and a bicarbonate of 12. What next?") == "pH 7.1 and a bicarbonate of 12.",
      SaveToIdeas.title(from: "pH 7.1 and a bicarbonate of 12. What next?"))
check("e.g. does not end the sentence",
      SaveToIdeas.title(from: "Drugs e.g. digoxin cause it. More.") == "Drugs e.g. digoxin cause it.",
      SaveToIdeas.title(from: "Drugs e.g. digoxin cause it. More."))
check("a question alone is kept whole",
      SaveToIdeas.title(from: "What is the first-line drug for absence seizures?") == "What is the first-line drug for absence seizures?")
check("bold markers come out", SaveToIdeas.title(from: "The **SA node** paces the heart") == "The SA node paces the heart")
check("cloze shows its term",
      SaveToIdeas.title(from: "The {{c1::phrenic::nerve}} nerve supplies the diaphragm") == "The phrenic nerve supplies the diaphragm",
      SaveToIdeas.title(from: "The {{c1::phrenic::nerve}} nerve supplies the diaphragm"))
check("lines are folded", SaveToIdeas.title(from: "Line one\n  and  two") == "Line one and two")
check("empty text takes the fallback", SaveToIdeas.title(from: "  \n ", fallback: "Saved card") == "Saved card")
check("wiki brackets are defused", !SaveToIdeas.title(from: "See [[Heart]] now").contains("[["))
let long = String(repeating: "word ", count: 40)
let cut = SaveToIdeas.title(from: long)
check("a long title is cut at a word", cut.count <= SaveToIdeas.titleLimit + 1 && cut.hasSuffix("\u{2026}")
      && !cut.contains("wor\u{2026}"), cut)

// MARK: the dedupe key

let q1 = NoteSource(kind: .question, setID: setA, itemID: item, setName: "Cardiology")
let q2 = NoteSource(kind: .question, setID: setB, itemID: item, setName: "Mistakes - Cardiology")
check("same question, any set, same key", q1.dedupeKey == q2.dedupeKey)
let c1 = NoteSource(kind: .card, setID: setA, itemID: item)
check("a card is not the question with the same id", c1.dedupeKey != q1.dedupeKey)
let lectureP2 = NoteSource(kind: .lecture, setID: setA, itemID: item, page: 2)
let lectureP9 = NoteSource(kind: .lecture, setID: setA, itemID: item, page: 9)
check("a lecture is one note whatever the page", lectureP2.dedupeKey == lectureP9.dedupeKey)
let whole = NoteSource(kind: .osce, setID: setA)
check("no item: the set is the key", whole.dedupeKey.hasSuffix(setA.uuidString.lowercased()))

// MARK: folders

check("subject names the folder", SaveToIdeas.folderName(subject: "  Renal  medicine ") == "Renal medicine")
check("no subject: General", SaveToIdeas.folderName(subject: " ") == "General")
let top = SaveToIdeas.FolderRef(id: UUID(), name: "Cardiology", parentId: nil)
let inner = SaveToIdeas.FolderRef(id: UUID(), name: "cardiology", parentId: UUID())
let other = SaveToIdeas.FolderRef(id: UUID(), name: "Neurology", parentId: nil)
check("top-level match wins", SaveToIdeas.folder(named: "CARDIOLOGY", in: [inner, other, top]) == top.id)
check("a nested one is used when that is all there is",
      SaveToIdeas.folder(named: "Cardiology", in: [inner, other]) == inner.id)
check("accents and spacing are ignored",
      SaveToIdeas.folder(named: "Neurología", in: [SaveToIdeas.FolderRef(id: other.id, name: " neurologia ", parentId: nil)]) == other.id)
check("no match: make one", SaveToIdeas.folder(named: "Renal", in: [top, other]) == nil)

// MARK: bodies

let clip = SaveToIdeas.question(stem: stem, answer: "Right coronary artery",
                                explanation: "Inferior leads mean the RCA.", source: q1, subject: "Cardiology")
check("question clip title from stem", clip.title.hasPrefix("A 54-year-old man"))
check("question clip has the answer", clip.text.contains("**Answer:** Right coronary artery"))
let body = SaveToIdeas.body(for: clip)
check("body says where it came from", body.hasPrefix("_From [a question in Cardiology]("), body)
check("the from line links back to the question",
      body.contains("(stethoscore://item/question/\(setA.uuidString)/\(item.uuidString))_"), body)
let linkText: String = String(body.split(separator: "(")[1].split(separator: ")")[0])
check("the from link routes to the same item",
      NoteSource(url: URL(string: linkText)!)?.dedupeKey == q1.dedupeKey, linkText)
check("body holds the explanation", body.hasSuffix("Inferior leads mean the RCA."))
check("saving the same again adds nothing", SaveToIdeas.appending(clip, to: body) == nil)

let bit = SaveToIdeas.excerpt("Inferior leads\nmean the RCA.", of: clip)
check("an excerpt is quoted line by line", SaveToIdeas.entry(for: bit) == "> Inferior leads\n> mean the RCA.",
      SaveToIdeas.entry(for: bit))
check("an excerpt keeps the note's title", bit.title == clip.title)
check("an excerpt already in the note adds nothing", SaveToIdeas.appending(bit, to: body) == nil)
let newBit = SaveToIdeas.excerpt("Posterior MI shows ST depression in V1-V3.", of: clip)
let grown = SaveToIdeas.appending(newBit, to: body)
check("a new passage goes on the end",
      grown == body + "\n\n> Posterior MI shows ST depression in V1-V3.", grown ?? "nil")

let page = SaveToIdeas.passage("Nephrotic: proteinuria > 3.5 g/day", lecture: "Glomerular disease",
                               source: lectureP9, subject: "Renal")
check("a passage names the lecture", page.title == "Glomerular disease")
check("a passage carries its page", SaveToIdeas.entry(for: page).hasSuffix("\u{2014} p. 9"))
check("a lecture is from a lecture", SaveToIdeas.body(for: page).hasPrefix("_From [a lecture]("))
let samePage = SaveToIdeas.appending(page, to: SaveToIdeas.body(for: page))
check("the same passage again adds nothing", samePage == nil)

let card = SaveToIdeas.card(front: "", cloze: "The {{c1::phrenic}} nerve supplies the diaphragm",
                            bullets: [], why: "C3, 4, 5 keeps the diaphragm alive.", source: c1, subject: "Anatomy")
check("cloze card titled from its sentence", card.title == "The phrenic nerve supplies the diaphragm", card.title)
check("cloze card body has the why", card.text.contains("C3, 4, 5"))
let qa = SaveToIdeas.card(front: "Causes of clubbing?", cloze: "", bullets: ["Lung cancer", " ", "IBD"],
                          why: "", source: c1, subject: "Resp")
check("card bullets become a list", qa.text == "- Lung cancer\n- IBD", qa.text)

let station = SaveToIdeas.osce(title: "Cardiovascular exam", steps: ["Wash hands", "Introduce yourself"],
                               weak: [1], source: whole, subject: "OSCE")
check("station steps are numbered", station.text.hasPrefix("1. Wash hands\n2. Introduce yourself"))
check("a weak step is marked", station.text.contains("started over here"))
check("an OSCE station takes an", SaveToIdeas.fromPhrase(whole) == "an OSCE station")

let theCase = SaveToIdeas.caseCard(topic: "Pneumothorax", stem: "A tall man, sudden breathlessness.",
                                   answer: ["Chest drain"], source: whole, subject: "Resp")
check("case titled from its topic", theCase.title == "Pneumothorax")
check("case body has the stem and answer", theCase.text.contains("sudden breathlessness") && theCase.text.contains("- Chest drain"))

let debrief = SaveToIdeas.caseDebrief(diagnosis: "Tension pneumothorax", missed: ["Ask about trauma", " "],
                                      covered: 7, total: 9, of: theCase)
check("a debrief goes in the case's note", debrief.title == theCase.title && debrief.source == theCase.source)
check("a debrief says the score", debrief.text.hasPrefix("**Pretend patient:** 7 of 9"), debrief.text)
check("a debrief lists what was missed", debrief.text.hasSuffix("Missed:\n- Ask about trauma"), debrief.text)
let caseNote = SaveToIdeas.body(for: theCase)
let withDebrief = SaveToIdeas.appending(debrief, to: caseNote)
check("a debrief adds to the case note", withDebrief?.hasPrefix(caseNote) == true)
check("the same debrief twice adds nothing", withDebrief.flatMap { SaveToIdeas.appending(debrief, to: $0) } == nil)

// MARK: the backlink

check("chip label", q1.chipLabel == "Question \u{00B7} Cardiology", q1.chipLabel)
check("chip label with page", lectureP9.chipLabel == "Lecture p. 9", lectureP9.chipLabel)
let named = NoteSource(kind: .lecture, setID: setA, itemID: item, page: 3, setName: "Renal & more")
for one in [q1, c1, whole, named] {
    check("link round trip \(one.kind.rawValue)", NoteSource(url: one.url) == one, one.url.absoluteString)
}
check("link uses the scheme people see", q1.url.scheme == "stethoscore")
check("another host is not a source", NoteSource(url: URL(string: "stethoscore://set/\(setA.uuidString)")!) == nil)
check("an unknown kind is not a source",
      NoteSource(url: URL(string: "stethoscore://item/poem/\(setA.uuidString)/-")!) == nil)
check("a bad page is dropped",
      NoteSource(url: URL(string: "stethoscore://item/lecture/\(setA.uuidString)/-?page=0")!)?.page == nil)

// stored on a note: optional, so an older note (no field) and a newer kind
// both read without losing the note
struct Holder: Codable { var source: NoteSource? }
let encoded = try! JSONEncoder().encode(Holder(source: q1))
check("stored source reads back", (try? JSONDecoder().decode(Holder.self, from: encoded))?.source == q1)
let old = "{}".data(using: .utf8)!
check("an old note has none", (try? JSONDecoder().decode(Holder.self, from: old)).map { $0.source == nil } == true)
let future = "{\"kind\":\"poem\",\"setID\":\"\(setA.uuidString)\"}".data(using: .utf8)!
check("a kind from a newer version does not read", (try? JSONDecoder().decode(NoteSource.self, from: future)) == nil)

if failures.isEmpty {
    print("all save-to-ideas checks passed")
} else {
    print("\(failures.count) FAILED")
    exit(1)
}
