// The lecture recorder's core (T0146): every move and the ones refused, the
// clock frozen while paused, a call pausing it, the file name and default
// title, the shared file, and the microphone asked only from a Record tap.
// Repair 1: saving makes no upload call, a cancelled save is saved again, and
// a recording cut off by a kill is found and the shared file reset.
// android/app/src/test/.../audio/RecorderStateTest.kt has the same cases.

import Foundation

var failures = 0
var checks = 0
func ok(_ condition: Bool, _ what: String) {
    checks += 1
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

let call = RecorderWords.callPaused

// MARK: every allowed move

ok(RecorderState.idle.ask() == .asking, "idle -> asking on the first Record tap")
ok(RecorderState.asking.cancel() == .idle, "asking -> idle when the microphone is refused")
ok(RecorderState.idle.start(at: 10) == .recording(startedAt: 10, banked: 0), "idle -> recording")
ok(RecorderState.asking.start(at: 10) == .recording(startedAt: 10, banked: 0), "asking -> recording once allowed")
ok(RecorderState.failed(reason: "x").start(at: 10) == .recording(startedAt: 10, banked: 0), "failed -> recording again")
ok(RecorderState.recording(startedAt: 10, banked: 0).pause(at: 15) == .paused(banked: 5, reason: nil), "recording -> paused, banking 5 s")
ok(RecorderState.paused(banked: 5, reason: nil).resume(at: 20) == .recording(startedAt: 20, banked: 5), "paused -> recording, keeping the banked 5 s")
ok(RecorderState.recording(startedAt: 10, banked: 0).stop(at: 30) == .saving, "recording -> saving on Stop")
ok(RecorderState.paused(banked: 5, reason: nil).stop(at: 30) == .saving, "paused -> saving on Stop")
ok(RecorderState.recording(startedAt: 10, banked: 2).interrupt(at: 20, reason: call) == .paused(banked: 12, reason: call),
   "recording -> paused by a call, saying why")
ok(RecorderState.paused(banked: 12, reason: call).resumeAfterInterruption(at: 40) == .recording(startedAt: 40, banked: 12),
   "a call's pause -> recording when asked to resume after it")
ok(RecorderState.paused(banked: 12, reason: call).resume(at: 40) == .recording(startedAt: 40, banked: 12), "a call's pause -> Resume works too")
ok(RecorderState.saving.finish() == .idle, "saving -> idle once handed on")
ok(RecorderState.failed(reason: "x").finish() == .idle, "failed -> idle once read")
ok(RecorderState.recording(startedAt: 1, banked: 0).fail("disk") == .failed(reason: "disk"), "recording -> failed")
ok(RecorderState.asking.fail("x") == .failed(reason: "x"), "asking -> failed")
ok(RecorderState.saving.fail("x") == .failed(reason: "x"), "saving -> failed")
ok(RecorderState.paused(banked: 1, reason: nil).fail("x") == .failed(reason: "x"), "paused -> failed")

// MARK: the moves refused

let rec = RecorderState.recording(startedAt: 10, banked: 0)
let paused = RecorderState.paused(banked: 5, reason: nil)
ok(RecorderState.idle.pause(at: 1) == nil, "idle cannot pause")
ok(RecorderState.idle.resume(at: 1) == nil, "idle cannot resume")
ok(RecorderState.idle.stop(at: 1) == nil, "idle cannot stop")
ok(RecorderState.idle.interrupt(at: 1, reason: call) == nil, "idle is not interrupted")
ok(RecorderState.idle.fail("x") == nil, "idle does not fail")
ok(RecorderState.idle.finish() == nil, "idle has nothing to finish")
ok(RecorderState.idle.cancel() == nil, "idle has nothing to cancel")
ok(rec.start(at: 20) == nil, "recording cannot start again")
ok(rec.ask() == nil, "recording does not ask")
ok(rec.resume(at: 20) == nil, "recording cannot resume")
ok(rec.resumeAfterInterruption(at: 20) == nil, "recording cannot resume after an interruption")
ok(rec.finish() == nil, "recording cannot finish without Stop")
ok(paused.pause(at: 20) == nil, "paused cannot pause")
ok(paused.start(at: 20) == nil, "paused cannot start")
ok(paused.interrupt(at: 20, reason: call) == nil, "paused is not interrupted again")
ok(paused.resumeAfterInterruption(at: 20) == nil, "a pause the student chose is not undone by a call ending")
ok(RecorderState.saving.start(at: 1) == nil, "saving cannot start")
ok(RecorderState.saving.pause(at: 1) == nil, "saving cannot pause")
ok(RecorderState.saving.stop(at: 1) == nil, "saving cannot stop again")
ok(RecorderState.asking.pause(at: 1) == nil, "asking cannot pause")
ok(RecorderState.asking.ask() == nil, "asking does not ask twice")
ok(RecorderState.failed(reason: "x").fail("y") == nil, "failed does not fail twice")

// MARK: the clock

let running = RecorderState.recording(startedAt: 100, banked: 0)
ok(running.elapsed(at: 160) == 60, "60 s in while recording")
let held = running.pause(at: 160)!
ok(held.elapsed(at: 160) == 60 && held.elapsed(at: 1000) == 60, "frozen at 60 s while paused")
let again = held.resume(at: 200)!
ok(again.elapsed(at: 200) == 60, "resumed with the banked 60 s")
ok(again.elapsed(at: 230) == 90, "and counting on from it: 90 s")
ok(again.elapsed(at: 150) == 60, "a clock that went back never takes time off")
ok(RecorderState.idle.elapsed(at: 5) == 0 && RecorderState.saving.elapsed(at: 5) == 0, "nothing elapsed when not recording")
let byCall = again.interrupt(at: 245, reason: call)!
ok(byCall == .paused(banked: 105, reason: call) && byCall.elapsed(at: 999) == 105, "a call pauses it at 105 s with the reason")
ok(RecorderNames.clock(723) == "12:03" && RecorderNames.clock(3723) == "1:02:03" && RecorderNames.clock(-4) == "0:00",
   "the clock reads 12:03, 1:02:03 and 0:00")

// MARK: names

let moment = RecorderNames.Moment(year: 2026, month: 10, day: 23, hour: 14, minute: 5)
ok(RecorderNames.Moment(Date(timeIntervalSince1970: 1792764300), timeZone: TimeZone(identifier: "UTC")!) == moment,
   "a fixed date read in its time zone")
ok(RecorderNames.fileName(moment) == "lecture-20261023-1405.m4a", "file name lecture-20261023-1405.m4a")
ok(RecorderNames.defaultTitle(moment, language: "en") == "Lecture, 23 Oct 14:05", "English title: Lecture, 23 Oct 14:05")
ok(RecorderNames.defaultTitle(moment, language: "ar") == "محاضرة، ٢٣ أكتوبر ١٤:٠٥", "Arabic title in Arabic digits")
ok(RecorderNames.defaultTitle(moment, language: "ar-EG") == "محاضرة، ٢٣ أكتوبر ١٤:٠٥", "ar-EG reads Arabic too")
let early = RecorderNames.Moment(year: 2027, month: 1, day: 3, hour: 9, minute: 7)
ok(RecorderNames.fileName(early) == "lecture-20270103-0907.m4a", "single digits padded in the file name")
ok(RecorderNames.defaultTitle(early, language: "en") == "Lecture, 3 Jan 09:07", "and the title: Lecture, 3 Jan 09:07")

// MARK: the meter and the disk

ok(RecorderMeter.level(decibels: -60) == 0 && RecorderMeter.level(decibels: -25) == 0.5 && RecorderMeter.level(decibels: 0) == 1,
   "meter: -60 dB silent, -25 dB half, 0 dB full")
ok(RecorderMeter.level(decibels: -.infinity) == 0, "meter: no signal reads silent")
ok(RecorderMeter.diskTooLow(freeBytes: 199 * 1024 * 1024) && !RecorderMeter.diskTooLow(freeBytes: 200 * 1024 * 1024),
   "under 200 MB free stops the recording")

// MARK: the shared file

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("recorder-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let file = dir.appendingPathComponent(RecorderShelf.fileName)
for state: RecorderState in [.idle, .asking, .recording(startedAt: 1792764300.5, banked: 12.25),
                             .paused(banked: 61, reason: nil), .paused(banked: 61, reason: call), .saving, .failed(reason: "disk")] {
    ok(RecorderShelf.write(state, to: file) && RecorderShelf.read(from: file) == state, "round trip: \(state.phase)")
}
let shape = (try? JSONSerialization.jsonObject(with: RecorderShelf.encode(.recording(startedAt: 5, banked: 2)))) as? [String: Any]
ok(shape?["phase"] as? String == "recording" && (shape?["v"] as? NSNumber)?.intValue == 1
   && (shape?["startedAt"] as? NSNumber)?.doubleValue == 5, "the file says v, phase, startedAt and banked")
ok(RecorderShelf.read(from: dir.appendingPathComponent("missing.json")) == .idle, "a missing file reads as idle")
try! Data("{not json".utf8).write(to: file)
ok(RecorderShelf.read(from: file) == .idle, "a garbled file reads as idle")
try! Data("{\"v\":9,\"phase\":\"recording\",\"startedAt\":1,\"banked\":0}".utf8).write(to: file)
ok(RecorderShelf.read(from: file) == .idle, "a newer app's file reads as idle")
try! Data("{\"v\":1,\"phase\":\"recording\"}".utf8).write(to: file)
ok(RecorderShelf.read(from: file) == .idle, "a recording with no clock reads as idle")
try! Data("[1,2]".utf8).write(to: file)
ok(RecorderShelf.read(from: file) == .idle, "the wrong shape reads as idle")
try? FileManager.default.removeItem(at: dir)

// MARK: the microphone, asked only from a Record tap

final class FakeGate: PermissionGate {
    var status: MicPermission
    let answer: Bool
    var requests = 0
    init(_ status: MicPermission, answer: Bool) { self.status = status; self.answer = answer }
    func request() async -> Bool {
        requests += 1
        status = answer ? .granted : .denied
        return answer
    }
}

await MainActor.run {}
let fresh = FakeGate(.undetermined, answer: true)
let flow = await RecordFlow(gate: fresh)
ok(fresh.requests == 0, "making the flow (the launch path) asks nothing")
let first = await flow.tapRecord()
ok(first == .sheet && fresh.requests == 0, "the first Record tap shows the sheet, not the system prompt")
let allowed = await flow.continueFromSheet()
ok(allowed == .record && fresh.requests == 1, "Continue asks the system once, and records when allowed")
let second = await flow.tapRecord()
ok(second == .record && fresh.requests == 1, "the next tap records without asking again")
let twice = await flow.continueFromSheet()
ok(twice == .record && fresh.requests == 1, "Continue after it was allowed does not ask again")

let refusing = FakeGate(.undetermined, answer: false)
let refused = await RecordFlow(gate: refusing)
_ = await refused.tapRecord()
let no = await refused.continueFromSheet()
ok(no == .settingsRow && refusing.requests == 1, "refused: the Open Settings row")
let after = await refused.tapRecord()
ok(after == .settingsRow && refusing.requests == 1, "and a later tap shows the row again, never the prompt")

let off = FakeGate(.denied, answer: true)
let offFlow = await RecordFlow(gate: off)
let offTap = await offFlow.tapRecord()
ok(offTap == .settingsRow && off.requests == 0, "already off in Settings: the row, no prompt")

ok(RecorderWords.sheetTitle == "Record your lecture"
   && RecorderWords.sheetBody == "Stethoscore uses the microphone to record the lecture. The recording stays on this phone until you choose to transcribe it."
   && RecorderWords.micOff == "Microphone is off for Stethoscore", "the sheet and row say what the owner wrote")

ok(RecorderWords.callPaused == "Paused for a call" && RecorderWords.lowDisk == "Stopped because this phone is almost full.",
   "the pause and low-disk lines are whole sentences, no bare hyphen")

// MARK: the moment from a file name (both platforms name a new set from it)

ok(RecorderNames.moment(fileName: "lecture-20261023-1405.caf") == moment, "read back from the file name")
ok(RecorderNames.moment(fileName: "lecture-20270103-0907.m4a") == early, "any extension")
ok(RecorderNames.moment(fileName: "notes.m4a") == nil, "not ours: nothing")
ok(RecorderNames.moment(fileName: "lecture-2026102-1405.m4a") == nil, "a name cut short: nothing")

// MARK: saving only saves; a cancelled save can be saved again (repair R1, R2)

let stopped = URL(fileURLWithPath: "/tmp/lecture-20261023-1405.m4a")
let setID = UUID()
var save = RecordingSave()
save.offer(stopped)
ok(save.choosing && save.file == stopped, "Stop offers the choice")
save.choosing = false   // the dialog's Cancel
ok(save.waiting && save.file == stopped, "Cancel keeps the recording, waiting to be saved")
save.reopen()
ok(save.choosing && !save.waiting, "Save the recording opens the choice again")
var uploads = 0
var copies = 0
let keptURL = URL(fileURLWithPath: "/tmp/\(setID.uuidString).m4a")
save.save(into: setID) { _, _ in copies += 1; return keptURL }
ok(save.kept == keptURL && save.setID == setID && save.file == nil && !save.waiting, "saved: kept under the set, nothing waiting")
ok(copies == 1 && uploads == 0, "the save path made one copy and no upload call")
save.reopen()
ok(!save.choosing, "nothing to reopen once saved")
await save.transcribe { url, id in if url == keptURL && id == setID { uploads += 1 } }
ok(uploads == 1, "Transcribe, its own action, sends the saved copy once")

var failing = RecordingSave()
failing.offer(stopped)
failing.save(into: setID) { _, _ in nil }
ok(failing.waiting && failing.kept == nil, "a copy that failed leaves it waiting to be saved again")
await failing.transcribe { _, _ in uploads += 1 }
ok(uploads == 1, "an unsaved recording is never sent")

// MARK: a recording cut off by a kill (repair R3)

ok(RecorderRecovery.leftover(["lecture-20261022-0900.caf", "lecture-20261023-1405.caf", "x.m4a"]) == "lecture-20261023-1405.caf", "the newest stem")
ok(RecorderRecovery.leftover(["lecture-20261023-1405.m4a", "lecture-20261023-1405.caf"]) == "lecture-20261023-1405.caf",
   "its live .caf before a half-made export")
ok(RecorderRecovery.leftover(["lecture-20261023-1405.m4a"]) == "lecture-20261023-1405.m4a", "a finished export alone")
ok(RecorderRecovery.leftover(["notes.txt"]) == nil, "none of ours")

let launch = FileManager.default.temporaryDirectory.appendingPathComponent("recover-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: launch, withIntermediateDirectories: true)
let shelfFile = launch.appendingPathComponent(RecorderShelf.fileName)
let partial = launch.appendingPathComponent("lecture-20261023-1405.caf")
try! Data([0x63, 0x61, 0x66, 0x66, 0, 1, 0, 0]).write(to: partial)
RecorderShelf.write(.recording(startedAt: 1792764300, banked: 3), to: shelfFile)
ok(RecorderRecovery.recover(shelf: shelfFile, folder: launch)?.lastPathComponent == partial.lastPathComponent, "a recording cut off by a kill is found")
ok(RecorderShelf.read(from: shelfFile) == .idle, "the shared file is reset to idle")
ok(RecorderRecovery.recover(shelf: shelfFile, folder: launch) == nil, "and found once")
RecorderShelf.write(.paused(banked: 9, reason: call), to: shelfFile)
ok(RecorderRecovery.recover(shelf: shelfFile, folder: launch) != nil, "paused when killed: found too")
RecorderShelf.write(.saving, to: shelfFile)
ok(RecorderRecovery.recover(shelf: shelfFile, folder: launch) != nil, "stopped but not saved: found too")
RecorderShelf.write(.failed(reason: "x"), to: shelfFile)
ok(RecorderRecovery.recover(shelf: shelfFile, folder: launch) == nil && RecorderShelf.read(from: shelfFile) == .idle,
   "a failure: nothing offered, and reset")
try! Data().write(to: partial)
RecorderShelf.write(.recording(startedAt: 1, banked: 0), to: shelfFile)
ok(RecorderRecovery.recover(shelf: shelfFile, folder: launch) == nil && RecorderShelf.read(from: shelfFile) == .idle,
   "an empty file: nothing offered, and reset")
try? FileManager.default.removeItem(at: launch)

ok(RecorderWords.recoverBody == "Stethoscore closed while recording. You can keep what it recorded up to then."
   && RecorderWords.keepKey != RecorderWords.keep && RecorderWords.discardKey != RecorderWords.discard,
   "the recovery question says when, and its Keep and Delete have keys of their own")

// MARK: a copy running starts no second one (repair 2, N3)

var busy = RecordingSave()
busy.offer(stopped)
busy.save(into: setID) { _, _ in nil }
ok(busy.canSave && !busy.copying, "a failed copy leaves Save the recording ready again")
busy.reopen()
ok(busy.choosing, "and the choice opens again")

// MARK: the microphone lost mid-recording keeps the .caf (repair 2, B3)

let lostDir = FileManager.default.temporaryDirectory.appendingPathComponent("lost-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: lostDir, withIntermediateDirectories: true)
let written = lostDir.appendingPathComponent("lecture-20261023-1405.caf")
try! Data([0x63, 0x61, 0x66, 0x66, 0, 1, 0, 0]).write(to: written)
ok(RecorderLoss.handOn(written) == written && FileManager.default.fileExists(atPath: written.path),
   "the microphone lost: what was written is handed on to be saved")
var afterLoss = RecordingSave()
if let handed = RecorderLoss.handOn(written) { afterLoss.offer(handed) }
afterLoss.cancel()
ok(afterLoss.canSave && afterLoss.file == written, "and Save the recording offers it")
let empty = lostDir.appendingPathComponent("lecture-20261023-1500.caf")
try! Data().write(to: empty)
ok(RecorderLoss.handOn(empty) == nil && !FileManager.default.fileExists(atPath: empty.path), "an empty file is dropped")
ok(RecorderLoss.handOn(nil) == nil, "nothing recording: nothing handed on")
try? FileManager.default.removeItem(at: lostDir)

print(failures == 0 ? "\nALL RECORDER TESTS PASS (\(checks) checks)" : "\n\(failures) RECORDER TEST FAILURE(S) of \(checks)")
exit(failures == 0 ? 0 : 1)
