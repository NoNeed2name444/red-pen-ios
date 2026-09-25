import Foundation
import CryptoKit

/// Deciding what happens to one document when two devices disagree.
///
/// The rule underneath all of this: **nothing a student made may disappear
/// without them having asked for it.** A sync that silently drops a deck is
/// worse than no sync at all, because they will not find out until the exam.
/// So when two devices genuinely changed the same thing, one version wins and
/// the other is KEPT, as a copy, where it can be seen and thrown away on
/// purpose.
///
/// The one exception is a deletion, and it is deliberate. A tombstone wins
/// outright and leaves no copy: the student asked for that deck to be gone, and
/// an app that keeps resurrecting deleted decks as "copies" is the single most
/// hated behaviour in any syncing app. An edit made AFTER the deletion still
/// wins, because that is a real edit to something that existed at the time.
///
/// Entirely pure - two documents and a bookmark go in, a decision comes out -
/// so every rule below is tested rather than hoped for.
enum SyncMerge {

    enum Resolution: Equatable {
        /// Both sides already agree.
        case nothingToDo
        /// Take the server's copy.
        case applyRemote
        /// Send ours; the server has not seen it.
        case push
        /// The server's copy wins, but ours was different and is kept beside it.
        case applyRemoteKeepingLocalCopy
        /// Ours wins, but the server's was different and is kept beside it, so
        /// the device that made it does not lose work it never learns about.
        case pushKeepingRemoteCopy
    }

    /// What to do about one document.
    ///
    /// `mark` is what this device last agreed with the server about it. Absent
    /// means this device has never synced that document, which is the same
    /// situation as a first run.
    ///
    /// `editedHere`, when the caller knows it, says whether this device edited
    /// the document since that agreement - for a set, read from its stamp. It
    /// is preferred to comparing hashes because a hash also moves when nothing
    /// was edited at all: an app update that adds a field to a card changes
    /// how every set encodes, and every unedited set would then look "changed
    /// here", turning the other device's next edit into a conflict copy.
    static func resolve(local: SyncDoc?, mark: SyncMark?, remote: SyncDoc?,
                        editedHere: Bool? = nil) -> Resolution {
        switch (local, remote) {
        case (nil, nil):
            return .nothingToDo
        case (.some, nil):
            // the server has never heard of it
            return .push
        case (nil, .some):
            // a document from another device, or a tombstone telling us to let
            // go of something we have already forgotten
            return .applyRemote
        case (.some(let local), .some(let remote)):
            return resolveBoth(local: local, mark: mark, remote: remote, editedHere: editedHere)
        }
    }

    private static func resolveBoth(local: SyncDoc, mark: SyncMark?,
                                    remote: SyncDoc, editedHere: Bool?) -> Resolution {
        // with no bookmark there is nothing to have edited since, so the hash
        // rule (everything counts as changed) stands whatever the stamp says
        let byHash: Bool = mark.map { $0.contentHash != hash(local) } ?? true
        let changedHere: Bool = mark == nil ? true : (editedHere ?? byHash)
        let changedThere = mark.map { remote.rev > $0.rev } ?? true

        switch (changedHere, changedThere) {
        case (false, false):
            return .nothingToDo
        case (false, true):
            return .applyRemote
        case (true, false):
            return .push
        case (true, true):
            // Both moved. Very often they moved to the same place - two devices
            // that each applied the same correction, say - and that is not a
            // conflict at all.
            if local.sameContent(as: remote) { return .applyRemote }

            // A deletion is an instruction, not an edit, and it does not leave
            // a copy behind. It still only wins if it is the later of the two.
            if remote.deleted && remote.updatedAt >= local.updatedAt { return .applyRemote }
            if local.deleted && local.updatedAt > remote.updatedAt { return .push }

            // Two real, different versions. Later wins; the earlier survives as
            // a copy so nothing is lost on either device.
            if remote.updatedAt > local.updatedAt {
                return local.deleted ? .applyRemote : .applyRemoteKeepingLocalCopy
            }
            if local.updatedAt > remote.updatedAt {
                return remote.deleted ? .push : .pushKeepingRemoteCopy
            }
            // Identical timestamps, different contents: two devices with clocks
            // that agree to the second. The server's copy wins, because that is
            // the one answer every device will reach independently - a rule
            // that depends on which device is asking is a rule that leaves them
            // permanently disagreeing.
            return .applyRemoteKeepingLocalCopy
        }
    }

    /// A document's body, as a hash.
    ///
    /// The bookmark keeps this rather than the body itself: it is how a device
    /// knows whether IT changed something since the last sync, without keeping
    /// a second copy of the whole library to compare against.
    static func hash(_ doc: SyncDoc) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(doc.deleted ? [1] : [0]))
        if let payload = doc.payload { hasher.update(data: payload) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func mark(for doc: SyncDoc, rev: Int? = nil) -> SyncMark {
        SyncMark(rev: rev ?? doc.rev, contentHash: hash(doc))
    }

    /// Whether this device has anything to say about a document.
    static func needsPush(local: SyncDoc, mark: SyncMark?) -> Bool {
        guard let mark else { return true }
        return mark.contentHash != hash(local)
    }
}
