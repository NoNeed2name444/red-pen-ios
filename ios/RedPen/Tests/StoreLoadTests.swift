// The library read off the main thread at launch: nothing is written before
// it is in, a set added meanwhile is kept on top of it, and a file that could
// not be read is read again later without losing what was added since.

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("storeload-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

@MainActor func names(_ store: Store) -> Set<String> { Set(store.library.map(\.name)) }

// MARK: a library on disk, read in the background

let url = root.appendingPathComponent("redpen-library.json")
let flaggedID = UUID()
let first = Store(fileURL: url)
ok(first.loaded, "a store read in init is loaded straight away")
first.addSet(StudySet(name: "Renal", kind: .mcq))
first.flagged.insert(flaggedID)
ok(await first.flushed(), "a set and a flag are written")

let store = Store(fileURL: url, inBackground: true)
ok(!store.loaded, "a store read in the background is not loaded straight away")
ok(!store.readWhole, "and is not read whole meanwhile, so nothing is swept")
await store.whenLoaded()
ok(store.loaded, "it is loaded once the read is in")
ok(names(store) == ["Renal"], "with the library on disk")
ok(store.flagged.contains(flaggedID), "and the progress")
ok(store.readWhole && store.unreadable.isEmpty, "read whole")

// MARK: nothing is written before the read is in

let early = Store(fileURL: url, inBackground: true)
early.addSet(StudySet(name: "Cardiology", kind: .anki))
// what is here is one set; what is on disk is not known yet. `wait` holds
// until anything queued is on disk, and the read cannot come in before the
// file is looked at, both being on this thread
early.flush(wait: true)
ok(Set(Store.savedLibrary(fileURL: url).map(\.name)) == ["Renal"], "a flush before the read is in writes nothing")
await early.whenLoaded()
ok(names(early) == ["Renal", "Cardiology"], "a set added before the read is in is kept on top of the file")
ok(await early.flushed(), "and written once it is")
ok(names(Store(fileURL: url)) == ["Renal", "Cardiology"], "nothing on disk was lost to the early flush")

// MARK: a library never written

let freshURL = root.appendingPathComponent("fresh/redpen-library.json")
try! FileManager.default.createDirectory(at: freshURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let fresh = Store(fileURL: freshURL, inBackground: true)
fresh.addSet(StudySet(name: "Day one", kind: .book))
await fresh.whenLoaded()
ok(names(fresh) == ["Day one"], "with no file yet, what was added stays")
ok(fresh.readWhole && fresh.unreadable.isEmpty, "a library never written is read whole")
ok(await fresh.flushed(), "the set added before the read came in is written")
ok(names(Store(fileURL: freshURL)) == ["Day one"], "and is on disk")

// MARK: a file that is there but cannot be read

// a folder where the file belongs: present, and unreadable, even to root
// (what a launch before the first unlock after a restart finds)
let lockedURL = root.appendingPathComponent("locked/redpen-library.json")
try! FileManager.default.createDirectory(at: lockedURL, withIntermediateDirectories: true)
let locked = Store(fileURL: lockedURL, inBackground: true)
await locked.whenLoaded()
ok(locked.unreadable.contains(lockedURL), "a library that is there but cannot be read is unreadable")
ok(!locked.readWhole, "and not read whole")
locked.addSet(StudySet(name: "Collected", kind: .mcq))
let lockedFlushed: Bool = await locked.flushed()
ok(!lockedFlushed, "nothing is written over it, and flushed says so")

// the first unlock: the file can be read now
try! FileManager.default.removeItem(at: lockedURL)
try! FileManager.default.copyItem(at: url, to: lockedURL)
locked.reloadIfUnread()
let reloadFlushed: Bool = await locked.flushed()
ok(names(locked) == ["Renal", "Cardiology", "Collected"],
   "read again, the file is taken in and the set added meanwhile kept")
ok(locked.unreadable.isEmpty && locked.readWhole, "and the library is read whole")
ok(reloadFlushed, "flushed waits for the read, then writes")
ok(names(Store(fileURL: lockedURL)) == ["Renal", "Cardiology", "Collected"], "all three are on disk")

try? FileManager.default.removeItem(at: root)
print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
