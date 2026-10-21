// A mock paper left part way comes back as it was left.

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mock-\(UUID().uuidString)")
let url = dir.appendingPathComponent("nested").appendingPathComponent("mock-sitting.json")
let q1 = UUID(), q2 = UUID(), q3 = UUID()
let started = Date(timeIntervalSince1970: 1_790_000_000)
let sitting = MockSittingSave(
    title: "PLAB 1", specs: [MockSectionSpec(title: "Paper", questions: 3, minutes: 180)],
    questionIds: [[q1, q2, q3]], wanted: 180, track: "plab", passMark: 0.63,
    section: 0, current: 2, selected: [q1: 3, q2: 0], orders: [q1: [2, 0, 1, 3, 4], q2: [0, 1, 2, 3, 4]],
    flagged: [q2], struck: [q1: [1, 4]], highlights: [q3: [0, 2]],
    secondsLeft: 4_321.5, onBreak: false, spent: [q1: 61.2, q2: 30], startedAt: started)

ok(MockSittingStore.load(from: url) == nil, "nothing to resume before anything is saved")
MockSittingStore.save(sitting, to: url)
let back = MockSittingStore.load(from: url)
ok(back == sitting, "a sitting comes back exactly as it was saved, in a folder made for it")
ok(back?.selected[q1] == 3 && back?.struck[q1] == [1, 4] && back?.flagged == [q2],
   "answers, crossed-out options and flags come back by question")
ok(back?.secondsLeft == 4_321.5 && back?.startedAt == started, "and the clock as it was left")
ok(back?.answered == 2 && back?.total == 3, "answered and total, for the resume card")

var later = sitting
later.selected[q3] = 1
later.current = 0
MockSittingStore.save(later, to: url)
ok(MockSittingStore.load(from: url)?.selected[q3] == 1, "a later save replaces the earlier one")

try! Data("not a sitting".utf8).write(to: url)
ok(MockSittingStore.load(from: url) == nil, "a file that cannot be read is no sitting, not a crash")

MockSittingStore.save(sitting, to: url)
MockSittingStore.clear(at: url)
ok(MockSittingStore.load(from: url) == nil, "a finished or abandoned sitting leaves nothing to resume")

try? FileManager.default.removeItem(at: dir)
print(failures == 0 ? "\nALL MOCK SITTING TESTS PASS" : "\n\(failures) MOCK SITTING TEST FAILURE(S)")
exit(failures == 0 ? 0 : 1)
