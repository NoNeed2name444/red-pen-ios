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

print(failures.isEmpty ? "\nALL SYNC TESTS PASS"
                       : "\n\(failures.count) SYNC TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
