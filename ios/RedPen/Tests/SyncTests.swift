// Two devices, one library.
//
// Every check here is a way somebody loses work. Sync bugs do not announce
// themselves - a deck that quietly stops existing is found weeks later, and by
// then there is nothing to recover it from.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let t0 = Date(timeIntervalSince1970: 1_700_000_000)
func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

func doc(_ body: String, rev: Int, at when: Date, deleted: Bool = false) -> SyncDoc {
    SyncDoc(id: "deck-1", kind: .set, rev: rev, updatedAt: when,
            deleted: deleted, payload: deleted ? nil : Data(body.utf8))
}

// MARK: one side only

check("nothing anywhere is nothing to do",
      SyncMerge.resolve(local: nil, mark: nil, remote: nil) == .nothingToDo)
check("something the server has never seen is pushed",
      SyncMerge.resolve(local: doc("a", rev: 0, at: t0), mark: nil, remote: nil) == .push)
check("something from another device is taken",
      SyncMerge.resolve(local: nil, mark: nil,
                        remote: doc("a", rev: 4, at: t0)) == .applyRemote)
// a tombstone for something already gone still has to be applied, or this
// device will upload it again from its own copy for ever
check("a tombstone for something we no longer have is still taken",
      SyncMerge.resolve(local: nil, mark: nil,
                        remote: doc("", rev: 5, at: t0, deleted: true)) == .applyRemote)

// MARK: the quiet cases

let agreed = doc("a", rev: 3, at: t0)
let mark = SyncMerge.mark(for: agreed)
check("two sides that already agree do nothing",
      SyncMerge.resolve(local: agreed, mark: mark, remote: agreed) == .nothingToDo)
check("a change only on the server is taken",
      SyncMerge.resolve(local: agreed, mark: mark,
                        remote: doc("b", rev: 4, at: at(60))) == .applyRemote)
check("a change only here is pushed",
      SyncMerge.resolve(local: doc("c", rev: 3, at: at(60)), mark: mark,
                        remote: agreed) == .push)

// MARK: both moved

// two devices that each applied the same correction are not in conflict
check("both sides arriving at the same text is not a conflict",
      SyncMerge.resolve(local: doc("same", rev: 3, at: at(10)), mark: mark,
                        remote: doc("same", rev: 9, at: at(20))) == .applyRemote)

// the rule that matters: the loser is KEPT
check("the later edit wins and the earlier is kept beside it",
      SyncMerge.resolve(local: doc("mine", rev: 3, at: at(10)), mark: mark,
                        remote: doc("theirs", rev: 9, at: at(20)))
        == .applyRemoteKeepingLocalCopy)
check("and the same the other way round, so the other device loses nothing either",
      SyncMerge.resolve(local: doc("mine", rev: 3, at: at(30)), mark: mark,
                        remote: doc("theirs", rev: 9, at: at(20)))
        == .pushKeepingRemoteCopy)
// every device has to reach the same answer independently, or they disagree for
// ever; the server's copy is the only thing they all see
check("identical timestamps resolve the same way on every device",
      SyncMerge.resolve(local: doc("mine", rev: 3, at: at(20)), mark: mark,
                        remote: doc("theirs", rev: 9, at: at(20)))
        == .applyRemoteKeepingLocalCopy)

// MARK: deletion

// resurrecting deleted decks as "copies" is the most hated behaviour any
// syncing app has, so a deletion wins outright and leaves nothing behind
check("a deletion beats an older edit, and leaves no copy",
      SyncMerge.resolve(local: doc("edited", rev: 3, at: at(10)), mark: mark,
                        remote: doc("", rev: 9, at: at(20), deleted: true)) == .applyRemote)
// but an edit made after the deletion is a real edit to something that existed
check("an edit made after the deletion brings it back",
      SyncMerge.resolve(local: doc("edited", rev: 3, at: at(30)), mark: mark,
                        remote: doc("", rev: 9, at: at(20), deleted: true)) == .push)
check("deleting here beats an older edit there",
      SyncMerge.resolve(local: doc("", rev: 3, at: at(30), deleted: true), mark: mark,
                        remote: doc("theirs", rev: 9, at: at(20))) == .push)
check("and an edit there after our deletion brings it back",
      SyncMerge.resolve(local: doc("", rev: 3, at: at(10), deleted: true), mark: mark,
                        remote: doc("theirs", rev: 9, at: at(20))) == .applyRemote)
check("two deletions are not a conflict",
      SyncMerge.resolve(local: doc("", rev: 3, at: at(10), deleted: true), mark: mark,
                        remote: doc("", rev: 9, at: at(20), deleted: true)) == .applyRemote)

// MARK: a device that has never synced

// no bookmark means everything looks changed on both sides, which is the safe
// way round: it conflicts rather than assuming
let fresh = SyncMerge.resolve(local: doc("mine", rev: 0, at: at(10)), mark: nil,
                              remote: doc("theirs", rev: 7, at: at(20)))
check("a first sync with different copies keeps both",
      fresh == .applyRemoteKeepingLocalCopy, "\(fresh)")
check("a first sync with matching copies just adopts the server's",
      SyncMerge.resolve(local: doc("same", rev: 0, at: at(10)), mark: nil,
                        remote: doc("same", rev: 7, at: at(20))) == .applyRemote)

// MARK: the bookmark itself

check("the same body hashes the same",
      SyncMerge.hash(doc("a", rev: 1, at: t0)) == SyncMerge.hash(doc("a", rev: 8, at: at(99))))
check("a different body hashes differently",
      SyncMerge.hash(doc("a", rev: 1, at: t0)) != SyncMerge.hash(doc("b", rev: 1, at: t0)))
// a tombstone and an empty document are not the same thing
check("a deletion hashes differently from an empty body",
      SyncMerge.hash(doc("", rev: 1, at: t0, deleted: true))
        != SyncMerge.hash(doc("", rev: 1, at: t0)))
check("an unchanged document needs no push",
      !SyncMerge.needsPush(local: agreed, mark: mark))
check("an edited one does",
      SyncMerge.needsPush(local: doc("edited", rev: 3, at: at(5)), mark: mark))
check("and one never synced does",
      SyncMerge.needsPush(local: agreed, mark: nil))

// MARK: images

let red = Data([0xFF, 0x00, 0x00, 0x01])
let blue = Data([0x00, 0x00, 0xFF, 0x01])
let packed = BlobRefs.pack([red.base64EncodedString(), blue.base64EncodedString()])
check("every image becomes a reference",
      packed.refs.allSatisfy(BlobRefs.isRef), "\(packed.refs)")
check("and its bytes come back to be uploaded", packed.blobs.count == 2)

// the same diagram in three decks is one blob, uploaded once
let twice = BlobRefs.pack([red.base64EncodedString(), red.base64EncodedString()])
check("the same picture twice is one blob", twice.blobs.count == 1, "\(twice.blobs.count)")
check("and both cards point at it", twice.refs[0] == twice.refs[1])

check("packing something already packed changes nothing",
      BlobRefs.pack(packed.refs).refs == packed.refs
        && BlobRefs.pack(packed.refs).blobs.isEmpty)
// a garbled picture is a bad card; a missing one is a card about nothing
check("an image that cannot be decoded is left alone",
      BlobRefs.pack(["!!not base64!!"]).refs == ["!!not base64!!"])
check("a data: URI is understood",
      BlobRefs.data(fromStored: "data:image/png;base64," + red.base64EncodedString()) == red)

let restored = BlobRefs.unpack(packed.refs, blobs: packed.blobs)
check("unpacking gives the pictures back",
      restored == [red.base64EncodedString(), blue.base64EncodedString()], "\(restored)")
// the card still knows which picture it wants, so a later sync can fill it in
check("a reference with no blob yet stays a reference",
      BlobRefs.unpack(packed.refs, blobs: [:]) == packed.refs)

let have = Set([BlobRefs.name(for: red)])
let wanted = BlobRefs.missing(packed.refs + packed.refs, have: have)
check("only what is missing is asked for", wanted == [BlobRefs.name(for: blue)], "\(wanted)")
check("the same name is a stable address",
      BlobRefs.name(for: red) == BlobRefs.name(for: Data([0xFF, 0x00, 0x00, 0x01])))
check("different bytes get different addresses",
      BlobRefs.name(for: red) != BlobRefs.name(for: blue))

// MARK: every image form answers the same question

// a set that is half-restored - one picture arrived, one has not - holds both
// forms at once, and a sweep that understood only one would delete the other
let halfRestored = BlobRefs.names(in: [red.base64EncodedString(), packed.refs[1]])
check("base64 and a reference name the same blobs",
      halfRestored == Set([BlobRefs.name(for: red), BlobRefs.name(for: blue)]),
      "\(halfRestored)")

// MARK: an update that only changes how a set encodes

// An app update that adds a field to a card changes every set's bytes without
// anybody editing anything. Deciding "changed here" by hash then made the
// other device's next edit a conflict copy of a deck nobody touched here.
let reencoded = doc("same deck, new field", rev: 3, at: t0)
check("an unedited set whose encoding moved takes the other device's edit",
      SyncMerge.resolve(local: reencoded, mark: mark,
                        remote: doc("their edit", rev: 9, at: at(20)), editedHere: false) == .applyRemote)
check("and with nothing new there, there is nothing to do",
      SyncMerge.resolve(local: reencoded, mark: mark, remote: agreed, editedHere: false) == .nothingToDo)
check("a set its stamp says was edited here still conflicts and keeps both",
      SyncMerge.resolve(local: doc("mine", rev: 3, at: at(10)), mark: mark,
                        remote: doc("theirs", rev: 9, at: at(20)), editedHere: true)
        == .applyRemoteKeepingLocalCopy)
check("an edit here goes up when the server has not moved",
      SyncMerge.resolve(local: doc("mine", rev: 3, at: at(10)), mark: mark,
                        remote: agreed, editedHere: true) == .push)
// with no bookmark there is nothing to have been edited since
check("no bookmark still counts as changed, whatever the stamp says",
      SyncMerge.resolve(local: doc("mine", rev: 0, at: at(10)), mark: nil,
                        remote: doc("theirs", rev: 7, at: at(20)), editedHere: false)
        == .applyRemoteKeepingLocalCopy)

// MARK: a picture reference is only ever a hash

let realName = BlobRefs.name(for: Data([1, 2, 3]))
check("a real reference names its blob", BlobRefs.hash(fromRef: "blob:" + realName) == realName)
// used as a file name, this read the app's own library into a "picture"
check("a reference that walks out of the folder is refused",
      BlobRefs.hash(fromRef: "blob:../../Documents/redpen-library.json") == nil)
check("a reference that is not a hash is refused", BlobRefs.hash(fromRef: "blob:cat") == nil)
check("an upper-case hash is not one this app writes",
      BlobRefs.hash(fromRef: "blob:" + realName.uppercased()) == nil)
check("a hash one character short is refused",
      BlobRefs.hash(fromRef: "blob:" + String(realName.dropLast())) == nil)
check("a bad reference is left as it is, not dropped",
      BlobRefs.unpack(["blob:../x"], blobs: [:]) == ["blob:../x"])
check("and asks for nothing", BlobRefs.missing(["blob:../x", "blob:cat"], have: []).isEmpty)

// a picture filled in by a sync is the same picture
let redBase64 = red.base64EncodedString()
check("a picture and its reference are the same picture",
      BlobRefs.samePictures([redBase64], ["blob:" + BlobRefs.name(for: red)]))
check("two different pictures are not",
      !BlobRefs.samePictures([redBase64], ["blob:" + BlobRefs.name(for: blue)]))
check("nor lists of different lengths", !BlobRefs.samePictures([redBase64], []))

// a set this version cannot read still names its pictures and its lecture file
let heldJSON = "{\"images\":[\"blob:\(realName)\",\"blob:../x\"],\"sources\":[{\"fileBlob\":\"\(realName)\"}]}"
check("a held set's pictures are found in its text",
      BlobRefs.names(mentionedIn: heldJSON) == [realName])
check("and so is a bare hash, like a lecture file's",
      BlobRefs.hashes(in: "{\"fileBlob\":\"\(realName)\"}") == [realName])
check("a longer run of hex is not a hash",
      BlobRefs.hashes(in: realName + "0").isEmpty)

// MARK: what the server will take

func sized(_ id: String, bytes: Int) -> SyncDoc {
    SyncDoc(id: id, kind: .set, rev: 0, updatedAt: t0, payload: Data(count: bytes))
}
check("a payload is counted in base64 characters, as the server counts it",
      SyncRules.payloadChars(sized("a", bytes: 3)) == 4 && SyncRules.payloadChars(sized("a", bytes: 4)) == 8)
// 1,425,000 bytes is exactly 1,900,000 characters
check("a document at the server's limit fits", SyncRules.fitsServer(sized("a", bytes: 1_425_000)))
check("one byte more does not", !SyncRules.fitsServer(sized("a", bytes: 1_425_001)))
check("a tombstone always fits",
      SyncRules.fitsServer(SyncDoc(id: "t", kind: .set, rev: 0, updatedAt: t0, deleted: true)))

let many = (0..<120).map { sized("d\($0)", bytes: 10) }
let byCount = SyncRules.batches(many, maxDocs: 50, maxBytes: 1_000_000)
check("a big library goes up in batches", byCount.map(\.count) == [50, 50, 20], "\(byCount.map(\.count))")
check("in order, and nothing left out", byCount.flatMap { $0 }.map(\.id) == many.map(\.id))
let heavy = (0..<5).map { sized("h\($0)", bytes: 300_000) }
let bySize = SyncRules.batches(heavy, maxDocs: 50, maxBytes: 1_000_000)
check("and cut by size as well as by count", bySize.allSatisfy { $0.count <= 2 } && bySize.flatMap { $0 }.count == 5,
      "\(bySize.map(\.count))")
let lone = SyncRules.batches([sized("x", bytes: 900_000), sized("y", bytes: 10)], maxDocs: 50, maxBytes: 100_000)
check("a document bigger than a batch still goes, on its own", lone.map(\.count) == [1, 1], "\(lone.map(\.count))")
check("nothing to send is no batches", SyncRules.batches([]).isEmpty)

// refused once, not sent again every minute
let stamp = at(100)
let tooBig = RefusedDoc(updatedAt: stamp, at: at(200), tooLarge: true)
check("a set too large to sync is not offered again while unchanged",
      SyncRules.stillRefused(tooBig, updatedAt: stamp, now: at(10 * 86_400)))
check("but is as soon as it changes",
      !SyncRules.stillRefused(tooBig, updatedAt: at(300), now: at(400)))
let notTaken = RefusedDoc(updatedAt: stamp, at: at(200), tooLarge: false)
check("one refused for another reason waits a day",
      SyncRules.stillRefused(notTaken, updatedAt: stamp, now: at(200 + 3_600)))
check("and is tried again after it",
      !SyncRules.stillRefused(notTaken, updatedAt: stamp, now: at(200 + 86_401)))
check("nothing refused is nothing held", !SyncRules.stillRefused(nil, updatedAt: stamp))

// MARK: a document from a newer version

func json(_ text: String) -> Data { Data(text.utf8) }
check("the same bytes lose nothing",
      !SyncRules.dropsFields(original: json("{\"a\":1}"), reencoded: json("{\"a\":1}")))
// the newer device's field, read by the older one and written back without it
check("a field this version cannot read is a loss",
      SyncRules.dropsFields(original: json("{\"cards\":[{\"front\":\"q\",\"siblings\":[{\"x\":1}]}]}"),
                            reencoded: json("{\"cards\":[{\"front\":\"q\"}]}")))
// the other way round: the older device never wrote it
check("a field this version adds is not a loss",
      !SyncRules.dropsFields(original: json("{\"cards\":[{\"front\":\"q\"}]}"),
                             reencoded: json("{\"cards\":[{\"front\":\"q\",\"siblings\":[]}]}")))
check("a key that held nothing is not a loss",
      !SyncRules.dropsFields(original: json("{\"a\":1,\"b\":[],\"c\":null,\"d\":{}}"),
                             reencoded: json("{\"a\":1}")))
check("an item this version could not read is a loss",
      SyncRules.dropsFields(original: json("{\"cards\":[{\"f\":1},{\"f\":2}]}"),
                            reencoded: json("{\"cards\":[{\"f\":1}]}")))
check("a value read as something else is a loss",
      SyncRules.dropsFields(original: json("{\"type\":\"diagram\"}"), reencoded: json("{\"type\":\"basic\"}")))
check("the same values in another order are not",
      !SyncRules.dropsFields(original: json("{\"a\":1,\"b\":\"x\"}"), reencoded: json("{\"b\":\"x\",\"a\":1}")))

// after an update, what the last version could not read is fetched again
check("the cursor goes back to just before the earliest to read again",
      SyncRules.rereadCursor(500, revisiting: [120, 340]) == 119)
check("never forward", SyncRules.rereadCursor(50, revisiting: [120]) == 50)
check("and not at all when there is nothing to read again", SyncRules.rereadCursor(500, revisiting: []) == 500)
check("never below zero", SyncRules.rereadCursor(500, revisiting: [0]) == 0)

// held until the app is updated - but not for ever: the same revision still
// losing fields a month on, through updates, holds fields no version keeps
check("a document that would lose fields is held",
      SyncRules.holdsForNewer(dropsFields: true, heldSince: nil, now: at(0)))
check("one that loses nothing is not",
      !SyncRules.holdsForNewer(dropsFields: false, heldSince: nil, now: at(0)))
check("held a week, unchanged, it is still held",
      SyncRules.holdsForNewer(dropsFields: true, heldSince: at(0), now: at(7 * 86_400)))
check("held a month, unchanged, it is let go",
      !SyncRules.holdsForNewer(dropsFields: true, heldSince: at(0), now: at(31 * 86_400)))

// MARK: a picture the server does not have

check("no such picture is remembered", SyncRules.pictureIsMissing(status: 404))
check("nor one it will not look up", SyncRules.pictureIsMissing(status: 400))
check("a server having a bad moment is not",
      !SyncRules.pictureIsMissing(status: 503) && !SyncRules.pictureIsMissing(status: 500))
check("a picture never missing is asked for", SyncRules.asksForPicture(missingSince: nil, now: at(0)))
check("one the server just said it lacks is not asked for again every run",
      !SyncRules.asksForPicture(missingSince: at(0), now: at(3_600)))
check("nor the next day", !SyncRules.asksForPicture(missingSince: at(0), now: at(86_400)))
check("but is after a week, in case it was uploaded since",
      SyncRules.asksForPicture(missingSince: at(0), now: at(7 * 86_400)))

// MARK: what becomes of a cloud job

check("only a 404 means a job is gone", CloudJobRules.answer(forFailedStatus: 404) == .gone)
check("a server error does not", CloudJobRules.answer(forFailedStatus: 503) == .unreachable)
check("an expired session does not", CloudJobRules.answer(forFailedStatus: 401) == .unreachable)
check("no signal does not", CloudJobRules.answer(forFailedStatus: nil) == .unreachable)
let started = at(0)
// nine days offline: the finished job is still on the server, and still wanted
check("a job not heard from for nine days is kept",
      !CloudJobRules.letGo(started: started, answer: .unreachable, reachable: true, now: at(9 * 86_400)))
check("one the server says is gone after eight days is let go",
      CloudJobRules.letGo(started: started, answer: .gone, reachable: true, now: at(9 * 86_400)))
check("but not before: the server keeps a finished job a week",
      !CloudJobRules.letGo(started: started, answer: .gone, reachable: true, now: at(3 * 86_400)))
// made under another account: asking as this one finds nothing, which says
// nothing about the job
check("a job made under another account is kept a month",
      !CloudJobRules.letGo(started: started, answer: .gone, reachable: false, now: at(20 * 86_400)))
check("and let go after it",
      CloudJobRules.letGo(started: started, answer: .unreachable, reachable: false, now: at(31 * 86_400)))

print(failures.isEmpty ? "\nALL SYNC TESTS PASS"
                       : "\n\(failures.count) SYNC TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
