import Foundation

// Recovery copies and lossy reading (RecoveryFiles): one record this version
// cannot read costs only itself, and the copy put aside can be found again.

var failures: [String] = []
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

struct Rec: Codable, Equatable { var due: Int; var kind: String }
enum Kind: String, Codable { case review, learn }
struct Strict: Codable { var due: Int; var kind: Kind }

let a = UUID(), b = UUID(), c = UUID()
let written = try! JSONEncoder().encode([a: Rec(due: 1, kind: "review"), b: Rec(due: 2, kind: "hologram"),
                                         c: Rec(due: 3, kind: "learn")])
let read = RecoveryFiles.records(Strict.self, from: written, decoder: JSONDecoder())
check("records: the readable ones are kept", read?.values.count == 2 && read?.values[a]?.due == 1 && read?.values[c]?.due == 3,
      "\(String(describing: read?.values.keys))")
check("records: and the one this version cannot read is counted, not fatal", read?.skipped == 1)
check("records: a file that is not a schedule at all is nil", RecoveryFiles.records(Strict.self, from: Data("[1,2".utf8), decoder: JSONDecoder()) == nil)
let empty = RecoveryFiles.records(Strict.self, from: try! JSONEncoder().encode([UUID: Rec]()), decoder: JSONDecoder())
check("records: an empty schedule is empty, nothing skipped", empty?.values.isEmpty == true && empty?.skipped == 0)

struct Box: Decodable { var items: [RecoveryFiles.Kept<Strict>]? }
let box = try! JSONDecoder().decode(Box.self, from: Data(#"{"items":[{"due":1,"kind":"review"},{"due":2,"kind":"x"},{"due":3,"kind":"learn"}]}"#.utf8))
let listed = RecoveryFiles.list(box.items)
check("list: read one at a time", listed.values.map(\.due) == [1, 3] && listed.skipped == 1)
check("list: none is none", RecoveryFiles.list([RecoveryFiles.Kept<Strict>]?.none).values.isEmpty)

// copies put aside, and found again newest first
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("recovery-\(UUID().uuidString)", isDirectory: true)
try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let file = folder.appendingPathComponent("redpen-reviews.json")
try! written.write(to: file)
let first = RecoveryFiles.putAside(file, as: "reviews-partly-unreadable", now: Date(timeIntervalSince1970: 1_000))
check("put aside: a copy beside the file", first?.lastPathComponent == "reviews-partly-unreadable-1000.json"
      && FileManager.default.contentsEqual(atPath: first?.path ?? "", andPath: file.path))
check("put aside: not again while the file is unchanged",
      RecoveryFiles.putAside(file, as: "reviews-partly-unreadable", now: Date(timeIntervalSince1970: 2_000)) == nil)
try! Data("{}".utf8).write(to: folder.appendingPathComponent("notes-unreadable-3000.json"))
try! Data("{}".utf8).write(to: folder.appendingPathComponent("unrelated-4000.json"))
let found = RecoveryFiles.copies(in: [folder]).map(\.lastPathComponent)
check("copies: every recovery copy, newest first, nothing else",
      found == ["notes-unreadable-3000.json", "reviews-partly-unreadable-1000.json"], "\(found)")
check("copies: an empty or missing folder has none",
      RecoveryFiles.copies(in: [folder.appendingPathComponent("nope")]).isEmpty)
try? FileManager.default.removeItem(at: folder)

print(failures.isEmpty ? "\nALL RECOVERY TESTS PASS" : "\n\(failures.count) RECOVERY TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
