import Foundation

/// The outgoing half of a sync: what this device has to say, and the pictures
/// that have to exist before it says it.
///
/// Apart from SyncEngine's own file because the two halves fail differently. A
/// pull that goes wrong leaves the library untouched; a push that goes wrong
/// can leave the server holding a document that points at a picture nobody has.
/// That is why the pictures go first here, and why a refused document is an
/// answer to merge rather than an error to report.
extension SyncEngine {

    /// What this device has to send.
    struct Outgoing {
        var docs: [SyncDoc] = []
        /// The pictures each set names, by document id - so a picture that
        /// will not go up holds back only the sets that show it.
        var pictures: [String: Set<String>] = [:]
        /// Each set's `updatedAt` as it was packed. It becomes the stamp when
        /// the server takes the set (see record).
        var stamps: [String: Date] = [:]
    }

    // MARK: pushing

    func push(_ run: Run) async throws {
        var outgoing = outgoingDocuments()
        var attempts = 0
        while !outgoing.docs.isEmpty && attempts < 3 {
            attempts += 1
            // Too big for the server to keep: not sent at all. The server
            // would leave it out without a word, this device would send the
            // same megabytes again every minute, and the badge would say
            // synced. Refused here, and said so at the end of the run.
            var sendable: [SyncDoc] = []
            for doc in outgoing.docs {
                if SyncRules.fitsServer(doc) {
                    sendable.append(doc)
                } else {
                    refuse(doc, tooLarge: true)
                }
            }
            // The pictures go first, on every attempt. A document that mentions
            // a blob the server has never seen would arrive on the other device
            // as a card with a hole in it, and the student would have no way of
            // knowing it was coming. Round two matters as much as round one: a
            // conflict merge can mint a whole new set - the kept copy - whose
            // pictures have never been offered to the server.
            let ready = try await uploadPictures(for: sendable, pictures: outgoing.pictures, run: run)

            // A batch at a time, each landing (and its bookmarks saved) before
            // the next goes: a first sync of a big library is many requests the
            // server can take, not one it refuses on every run.
            var conflicts: [SyncDoc] = []
            for batch in SyncRules.batches(ready) {
                try stillCurrent(run)
                let result = try await SyncAPI.push(batch, token: run.token)
                try stillCurrent(run)
                record(result, sent: batch, stamps: outgoing.stamps)
                conflicts += result.conflicts
                await store.flushed()
                await bookmarks.commit()
            }
            guard !conflicts.isEmpty else { break }

            // Somebody else pushed between our pull and our push. Merge against
            // what they sent and try those documents again - the rest have
            // already landed.
            for conflict in conflicts { apply(conflict) }
            outgoing = outgoingDocuments()
        }
    }

    /// What the server said about one batch, remembered.
    private func record(_ result: SyncAPI.PushResult, sent: [SyncDoc], stamps: [String: Date]) {
        for accepted in result.accepted {
            bookmarks.update { state in
                state.remember(accepted)
                state.refused[accepted.id] = nil
                // The stamp of the version that was SENT. An edit made while
                // this push was out has a later one, so the next run still sees
                // it as unsent and packs it; the set's stamp as it is now would
                // mark that edit synced, and it would never go.
                if accepted.kind == .set, let stamp = stamps[accepted.id] {
                    state.stamps[accepted.id] = stamp
                }
            }
        }
        store.forgetTombstones(result.accepted.filter(\.deleted)
                                .compactMap { UUID(uuidString: $0.id) })
        // Neither taken nor refused as stale: the server would not keep it -
        // the account's share is used up, or it had a reason of its own. Noted,
        // so it is not sent again every minute; tried again tomorrow, or as
        // soon as it changes.
        let answered = Set(result.accepted.map(\.id) + result.conflicts.map(\.id))
        for doc in sent where !answered.contains(doc.id) {
            refuse(doc, tooLarge: !SyncRules.fitsServer(doc))
        }
    }

    private func refuse(_ doc: SyncDoc, tooLarge: Bool) {
        bookmarks.update { state in
            state.refused[doc.id] = RefusedDoc(updatedAt: doc.updatedAt, at: Date(), tooLarge: tooLarge)
        }
    }

    /// Everything this device has changed since it last agreed with the server.
    func outgoingDocuments() -> Outgoing {
        var out = Outgoing()
        let state = bookmarks.state
        let now = Date()
        // a document the server refused last time, unchanged since, is not
        // offered again yet (SyncRules.stillRefused)
        func offer(_ doc: inout SyncDoc) -> Bool {
            if SyncRules.stillRefused(state.refused[doc.id], updatedAt: doc.updatedAt, now: now) { return false }
            return send(&doc)
        }

        for set in store.library {
            let id = set.id.uuidString
            // kept on this device only (chooseLibrary): neither the set nor
            // its schedule goes up
            if state.heldBack.contains(id) { continue }
            // Packing a set hashes every picture in it. Doing that for the whole
            // library on every foreground would be hundreds of megabytes of
            // hashing to discover that nothing changed - so a set whose stamp
            // still matches the one we pushed is skipped without being built.
            // Store only moves that stamp when something really differs.
            let unchanged = state.stamps[id] == set.updatedAt && state.mark(id) != nil
            // refused last time and unchanged since: not built again either
            let refused = SyncRules.stillRefused(state.refused[id], updatedAt: set.updatedAt, now: now)
            // Last written by a newer version of the app, and edited here.
            // Sending it would save it back without the fields this version
            // cannot see - on every device. It waits for this one's update.
            let newer = !unchanged && state.newer[id] != nil
            if newer { heldForNewer += 1 }
            if !(unchanged || refused || newer), let built = try? SyncDocuments.document(for: set) {
                var setDoc = built.doc
                if send(&setDoc) {
                    out.docs.append(setDoc)
                    // Filed in the cache as they are packed. A set made on this
                    // device has its pictures only inside itself until now, and
                    // the upload step looks for them by name.
                    for (_, data) in built.blobs { blobs.store(data) }
                    var names = Set(built.blobs.keys)
                    names.formUnion(set.images.compactMap { BlobRefs.hash(fromRef: $0) })
                    out.pictures[setDoc.id] = names
                    out.stamps[setDoc.id] = set.updatedAt
                } else {
                    // moved and back again: it holds what we last agreed, so
                    // that is its stamp, and it is not packed again next time
                    bookmarks.update { $0.stamps[id] = set.updatedAt }
                }
            }
            if var review = (try? SyncDocuments.reviewDocument(forSet: set,
                                                               records: reviews.records)) ?? nil,
               offer(&review) {
                out.docs.append(review)
            }
        }
        for folder in store.folders where !state.heldBack.contains(folder.id.uuidString) {
            guard var doc = try? SyncDocuments.document(for: folder) else { continue }
            if offer(&doc) { out.docs.append(doc) }
        }
        for (id, when) in store.tombstones where !state.heldBack.contains(id.uuidString) {
            // Sent as a set; the server matches on id and keeps whichever kind
            // it already knew this document by.
            var doc = SyncDocuments.tombstone(id, kind: .set, at: when)
            if offer(&doc) { out.docs.append(doc) }
        }
        return out
    }

    /// Whether a document differs from what we last agreed - and if it does,
    /// stamps it with the revision that agreement was at.
    ///
    /// That revision is the whole compare-and-set. Sending zero would tell the
    /// server "I have never seen this", and it would have no way to notice that
    /// another device pushed in the gap between our pull and our push.
    func send(_ doc: inout SyncDoc) -> Bool {
        let mark = bookmarks.state.mark(doc.id)
        guard SyncMerge.needsPush(local: doc, mark: mark) else { return false }
        doc.rev = mark?.rev ?? 0
        return true
    }

    func localDoc(id: String, kind: SyncKind) -> SyncDoc? {
        switch kind {
        case .set:
            guard let uuid = UUID(uuidString: id) else { return nil }
            if let set = store.library.first(where: { $0.id == uuid }) {
                return try? SyncDocuments.document(for: set).doc
            }
            if let when = store.tombstones[uuid] {
                return SyncDocuments.tombstone(uuid, kind: .set, at: when)
            }
            return nil
        case .folder:
            guard let uuid = UUID(uuidString: id) else { return nil }
            if let folder = store.folders.first(where: { $0.id == uuid }) {
                return try? SyncDocuments.document(for: folder)
            }
            if let when = store.tombstones[uuid] {
                return SyncDocuments.tombstone(uuid, kind: .folder, at: when)
            }
            return nil
        case .review:
            guard let setID = SyncDocuments.setID(fromReviewDocID: id),
                  let set = store.library.first(where: { $0.id == setID }) else { return nil }
            return (try? SyncDocuments.reviewDocument(forSet: set, records: reviews.records)) ?? nil
        case .saying:
            return nil
        }
    }

    // MARK: pictures

    /// Puts up the pictures the server is missing, and returns the documents
    /// that may go now: those whose pictures are all there, and those with
    /// none.
    ///
    /// A picture that will not go up - the account's picture storage is full,
    /// or the server had a bad moment - holds back only the sets that show it.
    /// A renamed deck, a moved folder and a day's review schedule still sync.
    func uploadPictures(for docs: [SyncDoc], pictures: [String: Set<String>],
                        run: Run) async throws -> [SyncDoc] {
        var wanted = Set<String>()
        for doc in docs { wanted.formUnion(pictures[doc.id] ?? []) }
        guard !wanted.isEmpty else { return docs }
        var failed = Set<String>()
        var full = false
        // Asking first turns a reinstall from a hundred-megabyte upload into a
        // few small questions, because the server already has every picture.
        let names = wanted.sorted()
        for start in stride(from: 0, to: names.count, by: 500) {
            let asked = Array(names[start..<min(start + 500, names.count)])
            let missing: [String]
            do {
                missing = try await SyncAPI.missingBlobs(asked, token: run.token)
            } catch let failure as AuthAPI.Failure where failure.endsRun {
                throw failure
            } catch {
                // not known to be there, so not assumed to be: those sets wait
                failed.formUnion(asked)
                continue
            }
            try stillCurrent(run)
            for name in missing {
                // Not here either: nothing can be sent, and the document goes
                // as it would have (its picture stays a reference).
                guard let data = blobs.data(name) else { continue }
                do {
                    try await SyncAPI.putBlob(data, name: name, token: run.token)
                } catch let failure as AuthAPI.Failure where failure.endsRun {
                    throw failure
                } catch {
                    failed.insert(name)
                    if (error as? SyncAPI.PictureRefused)?.storageFull == true { full = true }
                }
                try stillCurrent(run)
            }
        }
        guard !failed.isEmpty else { return docs }
        pictureTrouble = full
            ? "This account's picture storage is full, so sets with new pictures are waiting. Everything else is up to date."
            : "Some pictures could not be uploaded. The sets that show them will be tried again."
        return docs.filter { (pictures[$0.id] ?? []).isDisjoint(with: failed) }
    }

    /// Fetches any picture a set in the library is still only referring to.
    ///
    /// One the server cannot give - nobody ever uploaded it, or it arrived
    /// damaged - is skipped and asked for again later. It must not stop the
    /// pictures after it, or fail every sync for good.
    ///
    /// "Later" depends on the answer. The server saying it has no such
    /// picture (404, or 400 for a name it will not look up) is remembered
    /// with the bookmarks, and asked again only after a week or when a set
    /// naming it arrives again (SyncRules.asksForPicture) - otherwise a
    /// picture nobody ever uploaded is a request a minute for ever. Anything
    /// else - no signal, a bad moment, damaged bytes - is tried again within
    /// the hour.
    func fetchMissingPictures(_ run: Run) async throws {
        let have = blobs.names()
        let now = Date()
        let missing: [String: Date] = bookmarks.state.missingPictures
        var wanted: [String] = []
        var seen = Set<String>()
        for set in store.library {
            for image in set.images {
                guard let name = BlobRefs.hash(fromRef: image), !have.contains(name),
                      seen.insert(name).inserted else { continue }
                if !SyncRules.asksForPicture(missingSince: missing[name], now: now) { continue }
                if let when = unavailablePictures[name], now.timeIntervalSince(when) < 3_600 { continue }
                wanted.append(name)
            }
        }
        // what no set names any more is forgotten, so the list does not grow
        // for the life of the account
        let unnamed: [String] = missing.keys.filter { !seen.contains($0) }
        if !unnamed.isEmpty {
            bookmarks.update { state in
                for name in unnamed { state.missingPictures[name] = nil }
            }
        }
        for name in wanted {
            do {
                let data = try await SyncAPI.getBlob(name, token: run.token)
                try stillCurrent(run)
                blobs.store(data)
                unavailablePictures[name] = nil
                if bookmarks.state.missingPictures[name] != nil {
                    bookmarks.update { $0.missingPictures[name] = nil }
                }
            } catch let refused as SyncAPI.PictureRefused where SyncRules.pictureIsMissing(status: refused.status) {
                try stillCurrent(run)
                bookmarks.update { $0.missingPictures[name] = Date() }
            } catch let failure as AuthAPI.Failure where failure.endsRun {
                throw failure
            } catch is Superseded {
                throw Superseded()
            } catch {
                unavailablePictures[name] = Date()
            }
            try stillCurrent(run)
        }
        // Now that they are here, put them into the sets that were waiting -
        // only where one actually arrived, so a set still waiting is not
        // written again on every run.
        for set in store.library where set.images.contains(where: BlobRefs.isRef) {
            let restored = blobs.restore(set)
            if restored.images != set.images { store.applyFromSync(restored) }
        }
    }
}

extension AuthAPI.Failure {
    /// Failures that end the whole run rather than one picture's part in it:
    /// no connection, no session, no Pro. Anything else about one picture is
    /// that picture's problem.
    var endsRun: Bool {
        switch self {
        case .offline, .signedOut, .needsPro: return true
        default: return false
        }
    }
}
