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
/// **Nothing is half-applied.** Each document is merged into the library, the
/// library reaches the disk, and only then does the bookmark that says it was
/// seen. A run that dies in the middle leaves the library consistent and the
/// next run picks up where it stopped - at worst fetching a document twice,
/// never skipping one.
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
        /// Sync is part of Pro, and this account has none.
        case needsPro
        /// The library on this device was synced with a different account.
        /// Nothing moves until the student says whether it joins this one
        /// (chooseLibrary).
        case needsLibraryChoice
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
    /// Whether this run already renewed a refused session once, so a server
    /// that keeps refusing does not have the app renewing in a loop.
    private var renewedForRun = false
    private var lastSweep: Date?
    /// Pictures the server could not give us lately, and when: asked for again
    /// after a while rather than on every run (a picture nobody uploaded is
    /// otherwise a request a minute for ever).
    var unavailablePictures: [String: Date] = [:]
    /// Said at the end of a run: why some pictures, and the sets they are in,
    /// did not go up.
    var pictureTrouble: String?
    /// Edited sets that were last written by a newer version of the app, and
    /// wait for this one to be updated before they go up.
    var heldForNewer = 0

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

    /// Who a run is for. Captured when it starts and checked after every wait
    /// (stillCurrent): a run that began for one account must never write that
    /// account's bookmarks back after somebody signed in as another.
    struct Run {
        let token: String
        let accountId: String
        let generation: Int
    }

    /// Thrown when the account changed under a run; the next run starts
    /// afresh for whoever is signed in now.
    struct Superseded: Error {}

    func syncNow() async {
        guard let first = account.token, first != Session.localToken else { return }
        // a session near its end is renewed first, so a sync never fails
        // halfway through for want of one
        await account.refreshIfNeeded()
        // part of Pro; the library stays on this device (and on the server,
        // from when it was synced) until Pro comes back
        guard LocalLLMService.shared.isPro else { status = .needsPro; return }
        // a change made while a run is out is sent by a second run straight
        // after, not left until the app is next opened
        if running { again = true; return }
        running = true
        defer {
            running = false
            if again {
                again = false
                Task { await syncNow() }
            }
        }
        await runOnce()
    }

    private func runOnce() async {
        guard let token = account.token, token != Session.localToken,
              let who = account.account?.id else { return }
        prepareBookmarks(for: who)
        guard ownsLibrary(who) else {
            status = .needsLibraryChoice
            return
        }
        let run = Run(token: token, accountId: who, generation: bookmarks.generation)
        status = .syncing
        copiesKept = 0
        pictureTrouble = nil
        heldForNewer = 0

        do {
            try await pull(run)
            try await push(run)
            try await fetchMissingPictures(run)
            try stillCurrent(run)
            bookmarks.update { $0.lastSyncedAt = Date() }
            lastSyncedAt = bookmarks.state.lastSyncedAt
            await sweepPicturesIfDue()
            status = problems() ?? .idle
            renewedForRun = false
        } catch is Superseded {
            // Signed out, or in as somebody else, while this run was out. It
            // stops without writing anything more; the next run is for the
            // account signed in now.
            again = true
            status = .idle
        } catch AuthAPI.Failure.offline {
            // Not a failure worth shouting about. The library is intact and the
            // next run continues from the same bookmark.
            status = .offline
        } catch AuthAPI.Failure.needsPro {
            status = .needsPro
        } catch AuthAPI.Failure.signedOut {
            // Usually only a session that ran out while the app was open:
            // renewed, the run goes again - once. Only if that does not help
            // is the student asked to sign in.
            if !renewedForRun {
                renewedForRun = true
                await account.refreshIfNeeded(force: true)
                if let fresh = account.token, fresh != token {
                    again = true
                    status = .idle
                    await saveProgress()
                    return
                }
            }
            status = .failed("Please sign in again.")
        } catch {
            Diagnostics.record(.error, area: .sync, message: "sync.failed", error: error)
            status = .failed((error as? LocalizedError)?.errorDescription
                             ?? error.localizedDescription)
        }
        await saveProgress()
    }

    /// Whatever the run learned, kept - the library first, then the bookmarks
    /// that describe it.
    private func saveProgress() async {
        await store.flushed()
        await bookmarks.commit()
    }

    func stillCurrent(_ run: Run) throws {
        guard bookmarks.generation == run.generation,
              account.account?.id == run.accountId else { throw Superseded() }
    }

    /// The bookmarks are about one account's copy on the server. A different
    /// account - however it came to be signed in: signed out and back in as
    /// somebody else, a lapsed session replaced by a new sign-in - starts from
    /// nothing, rather than skipping its own documents because another
    /// account's cursor was further along.
    private func prepareBookmarks(for who: String) {
        if let known = bookmarks.state.accountId, known != who {
            bookmarks.reset()
        }
        if bookmarks.state.accountId == nil {
            bookmarks.update { $0.accountId = who }
        }
        // A new build of the app reads again what the last one could not:
        // documents it skipped as unreadable, and ones it would have saved
        // without their newer fields.
        let build = Self.buildStamp
        guard bookmarks.state.build != build else { return }
        bookmarks.update { state in
            let revisit = Array(state.unreadable.values) + Array(state.newer.values)
            state.cursor = SyncRules.rereadCursor(state.cursor, revisiting: revisit)
            // the whole of each newer document is taken again, not treated as
            // already seen because its revision has not moved
            for id in state.newer.keys { state.marks[id]?.rev = 0 }
            // remembered while they are read again: one still losing fields
            // at the same revision stays held from when it first was, and is
            // let go after a month (SyncRules.holdsForNewer)
            state.newerBefore = state.newer
            state.unreadable = [:]
            state.newer = [:]
            state.build = build
        }
    }

    /// Whether the library on this device may sync with this account. The
    /// first account it meets claims it; a different one has to be told yes
    /// (chooseLibrary) before a single set goes up.
    private func ownsLibrary(_ who: String) -> Bool {
        guard let owner = bookmarks.state.libraryOwner else {
            bookmarks.update { $0.libraryOwner = who }
            return true
        }
        return owner == who
    }

    /// The answer to "this library was synced with another account".
    ///
    /// Added: everything on this device joins the account signed in now.
    /// Kept here: the sets, folders and deletions already on this device stay
    /// on it and never go up; anything made from now on syncs as usual.
    /// Either way the account's own library comes down.
    func chooseLibrary(addToAccount: Bool) async {
        guard let who = account.account?.id else { return }
        var here = Set(store.library.map(\.id.uuidString))
        here.formUnion(store.folders.map(\.id.uuidString))
        here.formUnion(store.tombstones.keys.map(\.uuidString))
        bookmarks.update { state in
            state.libraryOwner = who
            if addToAccount {
                state.heldBack = []
            } else {
                state.heldBack.formUnion(here)
            }
        }
        // answered: the question goes away now, not after the write
        status = .idle
        await bookmarks.commit()
        await syncNow()
    }

    /// Sets kept on this device only by that choice.
    var setsKeptHere: Int {
        let held = bookmarks.state.heldBack
        guard !held.isEmpty else { return 0 }
        return store.library.filter { held.contains($0.id.uuidString) }.count
    }

    /// Changing one's mind: the sets kept here join this account after all.
    func addKeptSets() async {
        bookmarks.update { $0.heldBack = [] }
        await bookmarks.commit()
        await syncNow()
    }

    /// Everything this device knows, forgotten - used when a different person
    /// signs in on the same phone. Their library must not arrive already
    /// believing it has seen documents it has never met.
    ///
    /// `libraryNowBelongsTo`: an account this device was just linked to on
    /// purpose (Link another device). Its library goes with it without asking,
    /// since linking is how the student said so.
    func forgetEverythingSynced(libraryNowBelongsTo owner: String? = nil) {
        bookmarks.reset()
        if let owner {
            bookmarks.update { state in
                state.libraryOwner = owner
                state.heldBack = []
            }
            Task { await bookmarks.commit() }
        }
        lastSyncedAt = nil
        status = .idle
    }

    /// Anything still not syncing after an otherwise good run, said plainly,
    /// or nil when nothing is.
    private func problems() -> Status? {
        let state = bookmarks.state
        let tooLarge = store.library.filter { state.refused[$0.id.uuidString]?.tooLarge == true }
        if let first = tooLarge.first {
            let more: String = tooLarge.count > 1 ? " and \(tooLarge.count - 1) more are" : " is"
            return .failed("\u{201C}\(first.name)\u{201D}\(more) too large to sync \u{2014} everything else is up to date.")
        }
        if let pictureTrouble { return .failed(pictureTrouble) }
        let notTaken = store.library.filter { state.refused[$0.id.uuidString]?.tooLarge == false }.count
        if notTaken > 0 {
            let sets: String = notTaken == 1 ? "1 set was" : "\(notTaken) sets were"
            return .failed("\(sets) not saved on the server \u{2014} the account may be full. Tried again tomorrow.")
        }
        if heldForNewer > 0 {
            return .failed("Some sets were last changed by a newer version of \(Brand.name). Update this one to sync your changes to them.")
        }
        if !state.unreadable.isEmpty {
            return .failed("Some sets from your other device need the latest version of \(Brand.name).")
        }
        return nil
    }

    /// This build of the app: its version, and when its binary was made (a
    /// Swift Playgrounds build has no version to go on).
    static let buildStamp: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        var stamp = (info["CFBundleShortVersionString"] as? String ?? "")
            + "-" + (info["CFBundleVersion"] as? String ?? "")
        if let binary = Bundle.main.executableURL,
           let made = (try? binary.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
            stamp += "-\(Int(made.timeIntervalSince1970))"
        }
        return stamp
    }()

    /// Pictures nothing refers to any more, dropped - at most once a day, and
    /// only at the end of a run, with the whole library in hand.
    private func sweepPicturesIfDue() async {
        // not on the word of a library file that could not be read whole
        guard store.readWhole else { return }
        if let lastSweep, Date().timeIntervalSince(lastSweep) < 86_400 { return }
        lastSweep = Date()
        let images: [String] = store.library.flatMap(\.images)
        // sets this version could not read still name their pictures
        let alsoKept: Set<String> = store.heldPictureNames
        // naming a picture means hashing it; a library holds hundreds of
        // megabytes of them, so that is done off the main thread
        let live: Set<String> = await Task.detached(priority: .utility) {
            BlobRefs.names(in: images).union(alsoKept)
        }.value
        blobs.sweep(keeping: live)
    }

    // MARK: pulling

    private func pull(_ run: Run) async throws {
        var more = true
        while more {
            let changes = try await SyncAPI.changes(since: bookmarks.state.cursor, token: run.token)
            try stillCurrent(run)
            for doc in changes.docs {
                apply(doc)
            }
            // The library reaches the disk before the bookmark that says these
            // were seen. The other way round, an app killed in between wakes
            // with a cursor past documents its library never got - and a kept
            // conflict copy lost while its bookmark says we agreed.
            await store.flushed()
            try stillCurrent(run)
            bookmarks.update { $0.cursor = max($0.cursor, changes.cursor) }
            await bookmarks.commit()
            more = changes.more
        }
    }

    /// One document from the server, merged against what is here.
    func apply(_ remote: SyncDoc) {
        let mark = bookmarks.state.mark(remote.id)
        let local = localDoc(id: remote.id, kind: remote.kind)
        let edited = editedHere(remote.id, kind: remote.kind)

        switch SyncMerge.resolve(local: local, mark: mark, remote: remote, editedHere: edited) {
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
            if remote.kind == .set { keepLocalCopy(of: remote.id, packed: local, beside: remote) }
            adopt(remote)
        case .applyRemote:
            adopt(remote)
        }
    }

    /// For a set: whether it was edited here since we last agreed, read from
    /// its stamp - which only a real change moves - rather than from a hash of
    /// how this version of the app happens to encode it. Nil where there is no
    /// stamp to go on; the hash decides then.
    func editedHere(_ id: String, kind: SyncKind) -> Bool? {
        guard kind == .set, bookmarks.state.mark(id) != nil,
              let stamp = bookmarks.state.stamps[id], let uuid = UUID(uuidString: id),
              let set = store.library.first(where: { $0.id == uuid }) else { return nil }
        return set.updatedAt != stamp
    }

    /// Ours, kept beside the version that wins.
    ///
    /// Taken from the library itself, which still holds every picture - not
    /// from the packed document, whose pictures are only names. A picture
    /// added here since the last push exists nowhere else: the cache has never
    /// seen it, and adopting theirs is about to replace the only copy.
    ///
    /// Its cards take new ids where the winning version (`remote`) holds the
    /// same ones, so the two decks do not share one schedule.
    private func keepLocalCopy(of id: String, packed local: SyncDoc?, beside remote: SyncDoc) {
        let winner: StudySet? = SyncDocuments.set(from: remote)
        if let uuid = UUID(uuidString: id), let live = store.library.first(where: { $0.id == uuid }) {
            store.keepConflictCopy(of: live, from: "this device", beside: winner)
            copiesKept += 1
        } else if let local, let mine = SyncDocuments.set(from: local) {
            store.keepConflictCopy(of: blobs.restore(mine), from: "this device", beside: winner)
            copiesKept += 1
        }
    }

    /// Writes the server's version into the library and records that we agree.
    private func adopt(_ remote: SyncDoc) {
        guard let id = UUID(uuidString: remote.id) ?? SyncDocuments.setID(fromReviewDocID: remote.id)
        else { return }

        if remote.deleted {
            switch remote.kind {
            case .set, .folder:
                // a deleted deck's cards lose their places in the schedule -
                // only its own, never those of decks this device has not got
                // yet (a blanket prune did that during a first sync)
                let cards: [UUID] = store.library.first(where: { $0.id == id })?.cards.map(\.id) ?? []
                store.removeFromSync(id)
                reviews.forget(cards)
            case .review, .saying:
                break
            }
            bookmarks.update { state in
                state.remember(remote)
                state.unreadable[remote.id] = nil
                state.newer[remote.id] = nil
                state.newerBefore[remote.id] = nil
                state.newerSince[remote.id] = nil
                state.heldBack.remove(remote.id)
            }
            return
        }

        switch remote.kind {
        case .set:
            guard let incoming = SyncDocuments.set(from: remote) else {
                // This version cannot read it - a kind of set from a newer
                // version, say. Not remembered, so it is still the server's to
                // give; and noted, because the cursor moves past it: after an
                // update it is fetched again instead of being missed for good.
                bookmarks.update { $0.unreadable[remote.id] = remote.rev }
                return
            }
            // Pictures that have not arrived yet stay as references; the card
            // still knows which one it wants and a later run fills it in.
            let restored = blobs.restore(incoming)
            store.applyFromSync(restored)
            let drops = Self.dropsFields(remote, read: incoming)
            // pictures this version names that the server said it lacked are
            // worth asking for again: the device that sent it put its
            // pictures up first
            let named: [String] = incoming.images.compactMap { BlobRefs.hash(fromRef: $0) }
            bookmarks.update { state in
                state.stamps[remote.id] = restored.updatedAt
                state.unreadable[remote.id] = nil
                // written by a newer version: shown, but not saved back over
                // it (SyncPush holds its edits) until this one is updated
                let sameRevision: Bool = state.newer[remote.id] == remote.rev
                    || state.newerBefore[remote.id] == remote.rev
                let since: Date? = sameRevision ? state.newerSince[remote.id] : nil
                let hold: Bool = SyncRules.holdsForNewer(dropsFields: drops, heldSince: since)
                state.newer[remote.id] = hold ? remote.rev : nil
                state.newerSince[remote.id] = hold ? (since ?? Date()) : nil
                state.newerBefore[remote.id] = nil
                state.heldBack.remove(remote.id)
                for name in named where state.missingPictures[name] != nil {
                    state.missingPictures[name] = nil
                }
            }
        case .folder:
            guard let folder = SyncDocuments.folder(from: remote) else {
                bookmarks.update { $0.unreadable[remote.id] = remote.rev }
                return
            }
            store.applyFromSync(folder)
            bookmarks.update { state in
                state.unreadable[remote.id] = nil
                state.heldBack.remove(remote.id)
            }
        case .review:
            // Never replaced: merged card by card, so a deck reviewed on two
            // devices in one day keeps both afternoons' work.
            reviews.merge(SyncDocuments.records(from: remote))
        case .saying:
            break
        }
        bookmarks.update { $0.remember(remote) }
    }

    /// Whether this version, saving the set it just read, would lose fields a
    /// newer version wrote into it.
    private static func dropsFields(_ remote: SyncDoc, read incoming: StudySet) -> Bool {
        guard let payload = remote.payload,
              let again = try? JSONEncoder.sync.encode(incoming) else { return false }
        return SyncRules.dropsFields(original: payload, reencoded: again)
    }

    /// Theirs, kept beside ours - which stays under the original id, so the
    /// copy's cards take new ids where ours holds the same ones.
    private func keepCopy(of remote: SyncDoc) {
        guard remote.kind == .set, let theirs = SyncDocuments.set(from: remote) else { return }
        let ours: StudySet? = UUID(uuidString: remote.id).flatMap { id in store.library.first { $0.id == id } }
        store.keepConflictCopy(of: blobs.restore(theirs), from: "another device", beside: ours)
        copiesKept += 1
    }
}
