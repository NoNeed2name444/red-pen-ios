// The notes' part of the 3D map's signature (GraphShapeKey): it changes
// whenever something the picture shows changes - a name, a kind, a folder, a
// link, a folder's name or place, a note added or gone, and (in the looks
// that size by length) a note crossing a size step - and stays put otherwise,
// so typing inside one step does not plan the map again. And it is cheap: a
// note's words are counted again only when its text changes (Chat-me audit
// row 107: every redraw used to count every note's words).
//
// Compiled with Features/Notes/GraphShapeKey.swift and
// Features/Notes/GraphUniverse.swift, which import only Foundation.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func id(_ k: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", k))! }

func words(_ count: Int) -> String { Array(repeating: "word", count: count).joined(separator: " ") }

let cardiology: UUID = id(900)
let examples: UUID = id(901)
let base: [GraphShapeKey.Note] = [
    .init(id: id(1), title: "Heart failure", kind: "page", folder: cardiology, body: words(40)),
    .init(id: id(2), title: "Murmurs", kind: "idea", folder: cardiology, body: words(10)),
    .init(id: id(3), title: "Loose thought", kind: "idea", folder: nil, body: ""),
]
let baseEdges: [(UUID, UUID)] = [(id(1), id(2))]
let baseFolders: [GraphShapeKey.Folder] = [
    .init(id: cardiology, name: "Cardiology", parent: nil),
    .init(id: examples, name: "Examples", parent: nil),
]

func key(_ notes: [GraphShapeKey.Note] = base, edges: [(UUID, UUID)] = baseEdges,
         folders: [GraphShapeKey.Folder] = baseFolders, levels: Bool = true) -> Int {
    GraphShapeKey().key(notes: notes, edges: edges, folders: folders, levels: levels)
}

func with(_ k: Int, _ change: (inout GraphShapeKey.Note) -> Void) -> [GraphShapeKey.Note] {
    var notes = base
    change(&notes[k])
    return notes
}

// MARK: K1 - what changes it

let start: Int = key()
check("K1a the same notes give the same key", key() == start)
check("K1b a renamed note", key(with(1) { $0.title = "Heart sounds" }) != start)
check("K1c a note made a page", key(with(1) { $0.kind = "page" }) != start)
check("K1d a note moved to another folder", key(with(1) { $0.folder = examples }) != start)
check("K1e a note taken out of its folder", key(with(1) { $0.folder = nil }) != start)
check("K1f a new link", key(edges: baseEdges + [(id(2), id(3))]) != start)
check("K1g a link gone", key(edges: []) != start)
check("K1h a link moved to another note", key(edges: [(id(1), id(3))]) != start)
check("K1i a renamed folder", key(folders: [.init(id: cardiology, name: "Heart", parent: nil), baseFolders[1]]) != start)
check("K1j a folder put inside another",
      key(folders: [baseFolders[0], .init(id: examples, name: "Examples", parent: cardiology)]) != start)
check("K1k a new folder", key(folders: baseFolders + [.init(id: id(902), name: "Renal", parent: nil)]) != start)
check("K1l a new note", key(base + [.init(id: id(4), title: "New", kind: "idea", folder: nil, body: "")]) != start)
check("K1m a note gone", key(Array(base.prefix(2))) != start)
// a name moving between two fields must not hash the same
check("K1n a name's last letter moved into the kind",
      key(with(1) { $0.title = "Murmur"; $0.kind = "sidea" }) != start)

// MARK: K2 - the text: only a size step counts

// "Murmurs" has 10 words, under the first step (15)
check("K2a typing inside a size step leaves it", key(with(1) { $0.body = words(12) }) == start)
check("K2b crossing a size step changes it", key(with(1) { $0.body = words(15) }) != start)
check("K2c rewording a note keeps it", key(with(0) { $0.body = String(repeating: "other ", count: 40) }) == start)
let plain: Int = key(levels: false)
check("K2d the single looks ignore the text, even a long one",
      key(with(1) { $0.body = words(3000) }, levels: false) == plain)
check("K2e but not the names", key(with(1) { $0.title = "Heart sounds" }, levels: false) != plain)
check("K2f sizing by length is its own key", plain != start)

// MARK: K3 - cheap: a note's words are counted only when its text changes

let memo = GraphShapeKey()
let first: Int = memo.key(notes: base, edges: baseEdges, folders: baseFolders, levels: true)
check("K3a the first look counts every note", memo.counted == 3, "\(memo.counted)")
let second: Int = memo.key(notes: base, edges: baseEdges, folders: baseFolders, levels: true)
check("K3b a redraw with nothing changed counts none", memo.counted == 3 && second == first, "\(memo.counted)")
for _ in 0..<50 { _ = memo.key(notes: base, edges: baseEdges, folders: baseFolders, levels: true) }
check("K3c nor do fifty more", memo.counted == 3, "\(memo.counted)")
let typed: [GraphShapeKey.Note] = with(1) { $0.body = words(12) }
let afterTyping: Int = memo.key(notes: typed, edges: baseEdges, folders: baseFolders, levels: true)
check("K3d typing in one note counts that note only", memo.counted == 4, "\(memo.counted)")
check("K3e and keeps the key, as the step is the same", afterTyping == first)
let renamed: [GraphShapeKey.Note] = typed.map { var n = $0; n.title += "!"; return n }
_ = memo.key(notes: renamed, edges: baseEdges, folders: baseFolders, levels: true)
check("K3f renaming every note counts none", memo.counted == 4, "\(memo.counted)")
let crossed: [GraphShapeKey.Note] = with(1) { $0.body = words(16) }
let afterCrossing: Int = memo.key(notes: crossed, edges: baseEdges, folders: baseFolders, levels: true)
check("K3g a kept key follows a step crossed", afterCrossing == key(crossed) && afterCrossing != first)
_ = memo.key(notes: Array(crossed.prefix(1)), edges: [], folders: baseFolders, levels: true)
check("K3h notes that are gone are forgotten", memo.remembered == 1, "\(memo.remembered)")
_ = memo.key(notes: crossed, edges: baseEdges, folders: baseFolders, levels: false)
check("K3i the single looks count nothing", memo.counted == 5, "\(memo.counted)")
let shared = GraphShapeKey()
check("K3j a kept key is the same number as a fresh one",
      shared.key(notes: base, edges: baseEdges, folders: baseFolders, levels: true) == start
          && shared.key(notes: typed, edges: baseEdges, folders: baseFolders, levels: true) == start)

// MARK: K4 - a big library: redraws stay cheap

// 2,000 notes of 300 words each; fifty redraws with one note being typed in
var library: [GraphShapeKey.Note] = (0..<2_000).map { k in
    GraphShapeKey.Note(id: id(10_000 + k), title: "Note \(k)", kind: k % 3 == 0 ? "page" : "idea",
                       folder: k % 2 == 0 ? cardiology : nil, body: words(300))
}
let big = GraphShapeKey()
_ = big.key(notes: library, edges: [], folders: baseFolders, levels: true)
let before: Int = big.counted
for round in 0..<50 {
    library[7].body = words(301 + round)
    _ = big.key(notes: library, edges: [], folders: baseFolders, levels: true)
}
check("K4a fifty saves while typing count fifty notes, not 100,000", big.counted - before == 50,
      "\(big.counted - before)")

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED: \(failures.joined(separator: ", "))")
exit(failures.isEmpty ? 0 : 1)
