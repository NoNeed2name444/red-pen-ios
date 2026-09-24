import Foundation
import Combine

/// Keeping one student's library the same on every device they study on.
///
/// The shape of a run is: pull everything new, merge each document against what
/// is here, push whatever this device changed, then move the pictures. Pulling
/// first is deliberate - a push that goes first is a push made in ignorance,
/// and it is how one device's stale copy flattens another's work.
///
/// Three promises hold the whole thing up.
///
/// **The library works without any of this.** Every screen reads the Store, not
/// the server. A student with no signal, no account, or a server that is down
/// loses nothing and notices nothing except that the badge says it has not
/// synced.
///
/// **Nothing is half-applied.** Each document is merged and saved on its own,
/// and the bookmark for it moves only once that has succeeded. A run that dies
/// in the middle leaves the library consistent and the next run picks up
/// exactly where it stopped.
///
/// **A conflict keeps both copies.** See SyncMerge for the rules; here is where
/// the losing version is written back as a visible copy rather than dropped.
@MainActor
final class SyncEngine: ObservableObject {

    enum Status: Equatable {
        case idle
        case syncing
        case offline
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastSyncedAt: Date?
    /// How many conflict copies the last run had to keep. Worth surfacing: it
    /// is the one outcome the student has to act on.
    @Published var copiesKept = 0

    // Internal rather than private: the pushing half lives in SyncPush, and
    // Swift's `private` is per file.
    let store: Store
    let reviews: ReviewStore
    let account: AccountStore
    let blobs: BlobCache
    let bookmarks: SyncStateStore
    private var running = false
    private var again = false

    init(store: Store, reviews: ReviewStore, account: AccountStore,
         blobs: BlobCache? = nil, bookmarks: SyncStateStore? = nil) {
        self.store = store
        self.reviews = reviews
        self.account = account
        self.blobs = blobs ?? BlobCache()
        self.bookmarks = bookmarks ?? SyncStateStore()
        self.lastSyncedAt = self.bookmarks.state.lastSyncedAt
    }

    // MARK: a run

    func syncNow() async {
        guard let token = account.token, token != Session.localToken else { return }
        // a change made while a run is out is sent by a second run straight
        // after, not left until the app is next opened
        if running { again = true; return }
        running = true
        status = .syncing
        copiesKept = 0
        defer {
            running = false
            if again {
                again = false
                Task { await syncNow() }
            }
        }

        do {
            try await pull(token: token)
            try await push(token: token)
            try await fetchMissingPictures(token: token)
            bookmarks.update { $0.lastSyncedAt = Date() }
            lastSyncedAt = bookmarks.state.lastSyncedAt
            status = .idle
        } catch AuthAPI.Failure.offline {
            // Not a failure worth shouting about. The library is intact and the
            // next run continues from the same bookmark.
            status = .offline
        } catch AuthAPI.Failure.signedOut {
            status = .failed("Please sign in again.")
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription
                             ?? error.localizedDescription)
        }
    }

    /// Everything this device knows, forgotten - used when a different person
    /// signs in on the same phone. Their library must not arrive already
    /// believing it has seen documents it has never met.
    func forgetEverythingSynced() {
        bookmarks.reset()
        lastSyncedAt = nil
        status = .idle
    }

    // MARK: pulling

    private func pull(token: String) async throws {
        var more = true
        while more {
            let changes = try await SyncAPI.changes(since: bookmarks.state.cursor, token: token)
            for doc in changes.docs {
                apply(doc)
            }
            bookmarks.update { $0.cursor = max($0.cursor, changes.cursor) }
            more = changes.more
        }
    }

    /// One document from the server, merged against what is here.
    func apply(_ remote: SyncDoc) {
        let mark = bookmarks.state.mark(remote.id)
        let local = localDoc(id: remote.id, kind: remote.kind)

        switch SyncMerge.resolve(local: local, mark: mark, remote: remote) {
        case .nothingToDo, .push:
            // Handled in the push pass, where the server's answer decides the
            // revision. Recording a bookmark here would claim an agreement that
            // has not happened yet.
            break
        case .pushKeepingRemoteCopy:
            // Ours is the later edit and will go up, but theirs was real work
            // on another device. Keeping it here is the only way that device
            // ever learns it lost.
            keepCopy(of: remote)
            // And we now agree about where the server is, even though we are
            // about to disagree about the contents. Without this the push that
            // follows would still quote the revision from before their edit,
            // the server would rightly refuse it, and this same branch would
            // run again - keeping a second copy, and a third, while our own
            // edit never landed at all.
            bookmarks.update { $0.remember(remote) }
        case .applyRemoteKeepingLocalCopy:
            if let local, let mine = SyncDocuments.set(from: local) {
                // restored, not left as references: a kept copy whose pictures
                // are missing is not much of a rescue
                store.keepConflictCopy(of: blobs.restore(mine), from: "this device")
                copiesKept += 1
            }
            adopt(remote)
        case .applyRemote:
            adopt(remote)
        }
    }

    /// Writes the server's version into the library and records that we agree.
    private func adopt(_ remote: SyncDoc) {
        guard let id = UUID(uuidString: remote.id) ?? SyncDocuments.setID(fromReviewDocID: remote.id)
        else { return }

        if remote.deleted {
            switch remote.kind {
            case .set, .folder: store.removeFromSync(id)
            case .review: reviews.prune(keeping: store.library)
            case .saying: break
            }
            bookmarks.update { $0.remember(remote) }
            return
        }

        switch remote.kind {
        case .set:
            guard let incoming = SyncDocuments.set(from: remote) else { return }
            // Pictures that have not arrived yet stay as references; the card
            // still knows which one it wants and a later run fills it in.
            let restored = blobs.restore(incoming)
            store.applyFromSync(restored)
            bookmarks.update { $0.stamps[remote.id] = restored.updatedAt }
        case .folder:
            guard let folder = SyncDocuments.folder(from: remote) else { return }
            store.applyFromSync(folder)
        case .review:
            // Never replaced: merged card by card, so a deck reviewed on two
            // devices in one day keeps both afternoons' work.
            reviews.merge(SyncDocuments.records(from: remote))
        case .saying:
            break
        }
        bookmarks.update { $0.remember(remote) }
    }

    private func keepCopy(of remote: SyncDoc) {
        guard remote.kind == .set, let theirs = SyncDocuments.set(from: remote) else { return }
        store.keepConflictCopy(of: blobs.restore(theirs), from: "another device")
        copiesKept += 1
    }
}
