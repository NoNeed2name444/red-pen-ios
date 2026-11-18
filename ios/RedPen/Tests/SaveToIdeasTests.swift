// The backlink a note keeps to where it was saved from (NoteSource): the key
// that stops the same item being saved twice, the chip's label, the link as
// stored on the note and as a url, and a note whose source this version
// cannot read still loading; and the board's links, each pair once
// (IdeaEdges, in NoteStore.swift).
//
// Compiled with NoteSource.swift and NoteStore.swift (its Combine half is
// fenced out on Linux).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let setA = UUID()
let setB = UUID()
let item = UUID()

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

// the way Note reads it (NoteStore.swift): `try?` around the field, so a
// source this version cannot read is dropped and the note still loads
struct NoteLike: Decodable {
    var title: String
    var source: NoteSource?
    private enum Keys: String, CodingKey { case title, source }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        title = try c.decode(String.self, forKey: .title)
        source = try? c.decodeIfPresent(NoteSource.self, forKey: .source)
    }
}
let newerNote = "{\"title\":\"Kept\",\"source\":{\"kind\":\"poem\",\"setID\":\"\(setA.uuidString)\"}}".data(using: .utf8)!
let readNote: NoteLike? = try? JSONDecoder().decode(NoteLike.self, from: newerNote)
check("a note with a newer source still loads", readNote?.title == "Kept" && readNote?.source == nil)
let brokenSet = "{\"title\":\"Kept\",\"source\":{\"kind\":\"card\",\"setID\":\"nope\"}}".data(using: .utf8)!
check("a note with a damaged source still loads", (try? JSONDecoder().decode(NoteLike.self, from: brokenSet))?.title == "Kept")
let sourceJSON: String = String(data: try! JSONEncoder().encode(q1), encoding: .utf8)!
let savedNote = ("{\"title\":\"Kept\",\"source\":" + sourceJSON + "}").data(using: .utf8)!
check("a note's own source reads back", (try? JSONDecoder().decode(NoteLike.self, from: savedNote))?.source == q1,
      String(data: savedNote, encoding: .utf8) ?? "")

// the board's links, each pair once (audit #106); IdeaEdges is in NoteStore.swift
let ideaA = UUID(), ideaB = UUID(), ideaC = UUID(), gone = UUID()
let boardEdges = IdeaEdges.pairs([(id: ideaA, to: [ideaB, ideaB, ideaA, gone]),
                                  (id: ideaB, to: [ideaA, ideaC]),
                                  (id: ideaC, to: [])])
let edgeKeys: Set<String> = Set(boardEdges.map { $0.0.uuidString + $0.1.uuidString })
check("each pair once, both ways counted once", boardEdges.count == 2 && edgeKeys.count == 2)
check("no line to itself or to a note that is gone",
      boardEdges.allSatisfy { $0.0 != $0.1 && $0.0 != gone && $0.1 != gone })
check("each pair in id order", boardEdges.allSatisfy { $0.0.uuidString < $0.1.uuidString })

if failures.isEmpty {
    print("all note-source checks passed")
} else {
    print("\(failures.count) FAILED")
    exit(1)
}
