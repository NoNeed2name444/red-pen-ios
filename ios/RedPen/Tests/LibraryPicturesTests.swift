// The library's pictures on disk (audit row 17): packed into references as
// the file is written, filled back in as it is read, swept when nothing
// refers to them, and named by the same SHA-256 on Linux as on the phone.

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("pictures-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let files = FileManager.default

// MARK: names (FIPS 180-4 vectors)

ok(BlobRefs.name(for: Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "SHA-256 of nothing")
ok(BlobRefs.name(for: Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 of abc")
ok(BlobRefs.name(for: Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
   == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", "SHA-256 of two blocks")
ok(BlobRefs.name(for: Data(repeating: 0x61, count: 1_000_000))
   == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0", "SHA-256 of a million a's")

// MARK: packing

let red = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
let blue = Data([0x89, 0x50, 0x4E, 0x47, 4, 5, 6])
let redName = BlobRefs.name(for: red)
let blueName = BlobRefs.name(for: blue)
let folder = root.appendingPathComponent("lib-pictures")
let pictures = LibraryPictures(folder: folder)
let setA = UUID()
let setB = UUID()

let images = [red.base64EncodedString(), "!!not base64!!", BlobRefs.prefix + String(repeating: "a", count: 64),
              "data:image/png;base64," + blue.base64EncodedString()]
let packed = pictures.pack(images, of: setA)
ok(packed == [BlobRefs.prefix + redName, "!!not base64!!", BlobRefs.prefix + String(repeating: "a", count: 64),
              BlobRefs.prefix + blueName], "pictures become references; garbled base64 and references stay")
ok(files.fileExists(atPath: folder.appendingPathComponent(redName).path)
   && files.fileExists(atPath: folder.appendingPathComponent(blueName).path), "and their blobs are written")
ok((try? Data(contentsOf: folder.appendingPathComponent(blueName))) == blue, "a data: picture is stored as its bytes")

// a picture in two sets is one file
_ = pictures.pack([red.base64EncodedString()], of: setB)
let onDisk = (try? files.contentsOfDirectory(atPath: folder.path))?.filter(BlobRefs.isName) ?? []
ok(onDisk.count == 2, "a picture in two sets is stored once")

// packed again unchanged: the memo, not the disk (a removed blob is not noticed)
try! files.removeItem(at: folder.appendingPathComponent(redName))
ok(pictures.pack(images, of: setA)[0] == BlobRefs.prefix + redName, "a verified picture is not looked for again")

// a blob that cannot be written: the picture stays inline
let blocked = root.appendingPathComponent("blocked")
try! Data("a file, not a folder".utf8).write(to: blocked)
let stuck = LibraryPictures(folder: blocked)
let green = Data([7, 7, 7])
ok(stuck.pack([green.base64EncodedString()], of: setA) == [green.base64EncodedString()],
   "a picture whose blob cannot be written stays inline")

// a picture moved within its set is found again by its string
let moved = pictures.pack([images[3], images[0]], of: setA)
ok(moved == [BlobRefs.prefix + blueName, BlobRefs.prefix + redName], "a picture moved within its set keeps its name")

// MARK: filling

let fresh = LibraryPictures(folder: folder)
let missing = BlobRefs.prefix + String(repeating: "b", count: 64)
let filled = fresh.fill([BlobRefs.prefix + blueName, missing, "!!not base64!!"], of: setA)
ok(filled[0] == blue.base64EncodedString(), "a reference is filled from its blob")
ok(filled[1] == missing, "a reference whose blob is missing stays a reference")
ok(filled[2] == "!!not base64!!", "anything else is left as it is")
ok(fresh.pack(filled, of: setA) == [BlobRefs.prefix + blueName, missing, "!!not base64!!"],
   "filled pictures pack back to the same references")

ok(LibraryPictures.needsPacking([red.base64EncodedString()]), "an inline picture needs packing")
ok(!LibraryPictures.needsPacking([BlobRefs.prefix + redName, "!!not base64!!"]),
   "references and garbled base64 do not (no rewrite every launch)")

// MARK: where the pictures go

let support = URL(fileURLWithPath: "/support")
ok(LibraryPictures.folder(forLibrary: nil, support: support).path == "/support/RedPenBlobs",
   "the app's library uses the picture cache")
ok(LibraryPictures.folder(forLibrary: URL(fileURLWithPath: "/tmp/x/lib.json"), support: support).path == "/tmp/x/lib-pictures",
   "any other library a folder beside it")

// MARK: sweeping

let sweepFolder = root.appendingPathComponent("sweep")
let sweeper = LibraryPictures(folder: sweepFolder)
_ = sweeper.pack([red.base64EncodedString(), blue.base64EncodedString()], of: setA)
let old = Date().addingTimeInterval(-3 * 86_400)
try! files.setAttributes([.modificationDate: old], ofItemAtPath: sweepFolder.appendingPathComponent(redName).path)
try! files.setAttributes([.modificationDate: old], ofItemAtPath: sweepFolder.appendingPathComponent(blueName).path)
let stranger = sweepFolder.appendingPathComponent("notes.txt")
try! Data("x".utf8).write(to: stranger)
try! files.setAttributes([.modificationDate: old], ofItemAtPath: stranger.path)
let recent = Data([9, 9, 9])
_ = sweeper.pack([recent.base64EncodedString()], of: setB)

ok(sweeper.sweepDue(), "a folder never swept is due")
let removed = sweeper.sweep(keeping: [redName])
ok(removed == [blueName], "only an old blob nothing refers to is swept")
ok(files.fileExists(atPath: stranger.path), "a file not named as a blob is never touched")
ok(files.fileExists(atPath: sweepFolder.appendingPathComponent(BlobRefs.name(for: recent)).path), "a blob from the last day is spared")
ok(!sweeper.sweepDue(), "and the next sweep is a day away")
ok(sweeper.sweepDue(now: Date().addingTimeInterval(86_401)), "due again after a day")
ok(sweeper.pack([blue.base64EncodedString()], of: setA) == [BlobRefs.prefix + blueName]
   && files.fileExists(atPath: sweepFolder.appendingPathComponent(blueName).path),
   "a picture added back after a sweep is written again")

// MARK: what recovery copies mention

let text = "{\"images\":[\"blob:\(redName)\",\"blob:\(String(repeating: "z", count: 64))\",\"x blob:\(blueName)\"]}"
ok(LibraryPictures.mentions(in: Data(text.utf8)) == BlobRefs.names(mentionedIn: text),
   "the byte scan finds what the text scan finds")
ok(LibraryPictures.mentions(in: Data(text.utf8)) == [redName, blueName], "only real names")
let copyFolder = root.appendingPathComponent("docs")
try! files.createDirectory(at: copyFolder, withIntermediateDirectories: true)
try! Data(text.utf8).write(to: copyFolder.appendingPathComponent("library-unreadable-100.json"))
try! Data("blob:\(BlobRefs.name(for: recent))".utf8).write(to: copyFolder.appendingPathComponent("reviews-unreadable-100.json"))
ok(sweeper.mentions(inCopiesIn: copyFolder) == [redName, blueName], "the library's recovery copies are read, no other store's")
try! Data("blob:\(BlobRefs.name(for: recent))".utf8).write(to: copyFolder.appendingPathComponent("library-partly-unreadable-200.json"))
ok(sweeper.mentions(inCopiesIn: copyFolder) == [redName, blueName, BlobRefs.name(for: recent)], "a new copy is read too")

try? files.removeItem(at: root)
print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
