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

// MARK: pictures as blob references (audit row 17)

let files = FileManager.default
func blobsIn(_ folder: URL) -> Set<String> {
    Set(((try? files.contentsOfDirectory(atPath: folder.path)) ?? []).filter(BlobRefs.isName))
}
func age(_ url: URL) {
    try? files.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 86_400)], ofItemAtPath: url.path)
}
// a picture big enough that a file still carrying it inline is plainly not small
var bytes = [UInt8](repeating: 0, count: 200_000)
for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: i &* 2_654_435_761 >> 7) }
let photo = Data(bytes)
let photoName = BlobRefs.name(for: photo)

// a library written before row 17: its picture inline
let picsDir = root.appendingPathComponent("pics")
try! files.createDirectory(at: picsDir, withIntermediateDirectories: true)
let picsURL = picsDir.appendingPathComponent("redpen-library.json")
let picsFolder = picsDir.appendingPathComponent("redpen-library-pictures")
var oldSet = StudySet(name: "Slides", kind: .anki)
oldSet.images = [photo.base64EncodedString()]
try! JSONEncoder.redPen.encode(LibraryFile(library: [oldSet], folders: [], tombstones: nil, unread: nil)).write(to: picsURL)

let migrated = Store(fileURL: picsURL)
ok(migrated.library.first?.images == [photo.base64EncodedString()], "in memory a set keeps its pictures as base64")
ok(await migrated.flushed(), "the old file is written again")
ok(Store.savedLibrary(fileURL: picsURL).first?.images == [BlobRefs.prefix + photoName], "migrated: the file holds a reference")
ok(blobsIn(picsFolder) == [photoName], "and the picture is a file beside it")
let reread = Store(fileURL: picsURL)
ok(reread.library.first?.images == [photo.base64EncodedString()], "read back, the reference is filled in")

migrated.rename(oldSet.id, to: "Slides, renamed")
ok(await migrated.flushed(), "a rename is written")
let renamedSize = (try? files.attributesOfItem(atPath: picsURL.path))?[.size] as? Int ?? .max
ok(renamedSize < 20_000, "and the file is small (\(renamedSize) bytes), not carrying the picture")

// two sets, one picture; and a data: prefix
var twin = StudySet(name: "Twin", kind: .anki)
twin.images = ["data:image/png;base64," + photo.base64EncodedString()]
migrated.addSet(twin)
ok(await migrated.flushed(), "a set with a data: picture is written")
ok(Store.savedLibrary(fileURL: picsURL).first { $0.id == twin.id }?.images == [BlobRefs.prefix + photoName],
   "a data: picture is a reference too")
ok(blobsIn(picsFolder) == [photoName], "a picture in two sets is stored once")

// a missing blob stays a reference
try! files.removeItem(at: picsFolder.appendingPathComponent(photoName))
let without = Store(fileURL: picsURL)
ok(without.library.allSatisfy { $0.images == [BlobRefs.prefix + photoName] }, "a reference whose blob is missing stays a reference")

// a blob that cannot be written: the picture stays inline in the file
let stuckDir = root.appendingPathComponent("stuck")
try! files.createDirectory(at: stuckDir, withIntermediateDirectories: true)
let stuckURL = stuckDir.appendingPathComponent("redpen-library.json")
let notAFolder = stuckDir.appendingPathComponent("not-a-folder")
try! Data("a file".utf8).write(to: notAFolder)
let stuck = Store(fileURL: stuckURL, pictures: notAFolder)
var inline = StudySet(name: "Inline", kind: .anki)
inline.images = [photo.base64EncodedString()]
stuck.addSet(inline)
ok(await stuck.flushed(), "the library is written even when a blob cannot be")
ok(Store.savedLibrary(fileURL: stuckURL).first?.images == [photo.base64EncodedString()],
   "and the picture whose blob failed stays inline")

// the sweep: right after a write lands, at most once a day
let sweepDir = root.appendingPathComponent("sweep")
try! files.createDirectory(at: sweepDir, withIntermediateDirectories: true)
let sweepURL = sweepDir.appendingPathComponent("redpen-library.json")
let sweepFolder = sweepDir.appendingPathComponent("redpen-library-pictures")
let sweeping = Store(fileURL: sweepURL)
var kept = StudySet(name: "Kept", kind: .anki)
kept.images = [photo.base64EncodedString(), BlobRefs.prefix + String(repeating: "c", count: 64)]
sweeping.addSet(kept)
ok(await sweeping.flushed(), "a library with a picture is written")
let orphan = Data([1, 2, 3, 4])
let held = Data([5, 6, 7, 8])
let copied = Data([9, 10, 11, 12])
for blob in [orphan, held, copied] { try! blob.write(to: sweepFolder.appendingPathComponent(BlobRefs.name(for: blob))) }
for name in blobsIn(sweepFolder) { age(sweepFolder.appendingPathComponent(name)) }
try! Data("{\"images\":[\"blob:\(BlobRefs.name(for: copied))\"]}".utf8)
    .write(to: sweepDir.appendingPathComponent("library-unreadable-100.json"))
sweeping.keepUnread(["{\"kind\":\"future\",\"images\":[\"blob:\(BlobRefs.name(for: held))\"]}"])
ok(await sweeping.flushed(), "written again within the day")
ok(blobsIn(sweepFolder).contains(BlobRefs.name(for: orphan)), "not swept again within the day")
try? files.removeItem(at: sweepFolder.appendingPathComponent(".swept"))
sweeping.rename(kept.id, to: "Kept still")
ok(await sweeping.flushed(), "and once the day is up")
let left = blobsIn(sweepFolder)
ok(!left.contains(BlobRefs.name(for: orphan)), "an old picture nothing refers to is swept")
ok(left.contains(photoName), "one the library refers to is kept, however old")
ok(left.contains(BlobRefs.name(for: held)), "one a set this version cannot read mentions is kept")
ok(left.contains(BlobRefs.name(for: copied)), "one a recovery copy mentions is kept")
let fresher = Data([13, 14, 15])
try! fresher.write(to: sweepFolder.appendingPathComponent(BlobRefs.name(for: fresher)))
try? files.removeItem(at: sweepFolder.appendingPathComponent(".swept"))
sweeping.rename(kept.id, to: "Kept again")
ok(await sweeping.flushed(), "swept once more")
ok(blobsIn(sweepFolder).contains(BlobRefs.name(for: fresher)), "a picture from the last day is spared")
var back = StudySet(name: "Back", kind: .anki)
back.images = [orphan.base64EncodedString()]
sweeping.addSet(back)
ok(await sweeping.flushed(), "a set with the swept picture is added")
ok(blobsIn(sweepFolder).contains(BlobRefs.name(for: orphan))
   && Store.savedLibrary(fileURL: sweepURL).first { $0.id == back.id }?.images == [BlobRefs.prefix + BlobRefs.name(for: orphan)],
   "a picture added back after a sweep is written again")

// a library not read whole is never swept on
let unreadDir = root.appendingPathComponent("garbled")
try! files.createDirectory(at: unreadDir, withIntermediateDirectories: true)
let garbledURL = unreadDir.appendingPathComponent("redpen-library.json")
try! Data("not json".utf8).write(to: garbledURL)
let garbledFolder = unreadDir.appendingPathComponent("redpen-library-pictures")
try! files.createDirectory(at: garbledFolder, withIntermediateDirectories: true)
let lone = garbledFolder.appendingPathComponent(BlobRefs.name(for: orphan))
try! orphan.write(to: lone)
age(lone)
let garbled = Store(fileURL: garbledURL)
garbled.addSet(StudySet(name: "New", kind: .mcq))
ok(await garbled.flushed(), "a library that could not be read is written over only once put aside")
ok(files.fileExists(atPath: lone.path), "and no picture is swept on its word")

try? FileManager.default.removeItem(at: root)
print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
