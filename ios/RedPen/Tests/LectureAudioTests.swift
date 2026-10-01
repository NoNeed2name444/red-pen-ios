// Replacing a lecture recording: the old one goes only once the new one is in.

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lectures-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
func text(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }
func put(_ text: String, _ name: String) -> URL {
    let url = dir.appendingPathComponent(name)
    try! Data(text.utf8).write(to: url)
    return url
}
func leftovers() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(".incoming-") }
}

let set = UUID()
let old = put("the old lecture", "\(set.uuidString).m4a")

// MARK: a copy that fails keeps the old recording

let gone = dir.appendingPathComponent("picked-then-deleted.m4a")
var threw = false
do { try LectureAudio.store(imported: gone, for: set, in: dir) } catch { threw = true }
ok(threw, "a recording that cannot be copied in says so")
ok(text(old) == "the old lecture", "and the old recording is still there, whole")
ok(leftovers().isEmpty, "with nothing half-copied left beside it")

// MARK: a copy that lands replaces it

let picked = put("the new lecture", "picked.m4a")
let placed = try! LectureAudio.store(imported: picked, for: set, in: dir)
ok(text(placed) == "the new lecture", "a new recording takes the old one's place")
ok(LectureAudio.recordings(for: set, in: dir).count == 1, "and is the only one for the set")
ok(leftovers().isEmpty, "with nothing left beside it")

// MARK: another container replaces the old one too

let wav = put("the same lecture as wav", "picked.WAV")
let placedWav = try! LectureAudio.store(imported: wav, for: set, in: dir)
let now = LectureAudio.recordings(for: set, in: dir)
ok(now == [placedWav] && placedWav.pathExtension == "wav",
   "a recording in another container replaces the earlier one, under its own lower-case extension")
ok(text(placedWav) == "the same lecture as wav", "with what was picked")

// MARK: another set's recording is never touched

let other = UUID()
let theirs = put("someone else's lecture", "\(other.uuidString).m4a")
_ = try! LectureAudio.store(imported: picked, for: set, in: dir)
ok(text(theirs) == "someone else's lecture", "another set's recording is left alone")

try? FileManager.default.removeItem(at: dir)
print(failures == 0 ? "\nALL LECTURE AUDIO TESTS PASS" : "\n\(failures) LECTURE AUDIO TEST FAILURE(S)")
exit(failures == 0 ? 0 : 1)
