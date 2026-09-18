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

    // MARK: pushing

    func push(token: String) async throws {
        var outgoing = outgoingDocuments()
        guard !outgoing.docs.isEmpty else { return }

        var attempts = 0
        while !outgoing.docs.isEmpty && attempts < 3 {
            attempts += 1
            // The pictures go first, on every attempt. A document that mentions
            // a blob the server has never seen would arrive on the other device
            // as a card with a hole in it, and the student would have no way of
            // knowing it was coming. Round two matters as much as round one: a
            // conflict merge can mint a whole new set - the kept copy - whose
            // pictures have never been offered to the server.
            try await uploadPictures(for: outgoing.docs, token: token)
            let result = try await SyncAPI.push(outgoing.docs, token: token)
            for accepted in result.accepted {
                bookmarks.update { state in
                    state.remember(accepted)
                    if accepted.kind == .set,
                       let id = UUID(uuidString: accepted.id),
                       let set = self.store.library.first(where: { $0.id == id }) {
                        state.stamps[accepted.id] = set.updatedAt
                    }
                }
            }
            store.forgetTombstones(result.accepted.filter(\.deleted)
                                    .compactMap { UUID(uuidString: $0.id) })
            guard !result.conflicts.isEmpty else { break }

            // Somebody else pushed between our pull and our push. Merge against
            // what they sent and try those documents again - the rest have
            // already landed.
            for conflict in result.conflicts { apply(conflict) }
            outgoing = outgoingDocuments()
        }
    }

    /// Everything this device has changed since it last agreed with the server.
    func outgoingDocuments() -> (docs: [SyncDoc], blobs: [String: Data]) {
        var docs: [SyncDoc] = []
        var pictures: [String: Data] = [:]

        for set in store.library {
            // Packing a set hashes every picture in it. Doing that for the whole
            // library on every foreground would be hundreds of megabytes of
            // hashing to discover that nothing changed - so a set whose stamp
            // still matches the one we pushed is skipped without being built.
            // Store only moves that stamp when something really differs.
            if let stamp = bookmarks.state.stamps[set.id.uuidString], stamp == set.updatedAt,
               bookmarks.state.mark(set.id.uuidString) != nil {
                if var review = (try? SyncDocuments.reviewDocument(forSet: set,
                                                                   records: reviews.records)) ?? nil,
                   send(&review) {
                    docs.append(review)
                }
                continue
            }
            guard let built = try? SyncDocuments.document(for: set) else { continue }
            var setDoc = built.doc
            if send(&setDoc) {
                docs.append(setDoc)
                // Filed in the cache as they are packed. A set made on this
                // device has its pictures only inside itself until now, and the
                // upload step looks for them by name.
                for (_, data) in built.blobs { blobs.store(data) }
                pictures.merge(built.blobs) { first, _ in first }
            }
            if var review = (try? SyncDocuments.reviewDocument(forSet: set,
                                                               records: reviews.records)) ?? nil,
               send(&review) {
                docs.append(review)
            }
        }
        for folder in store.folders {
            guard var doc = try? SyncDocuments.document(for: folder) else { continue }
            if send(&doc) { docs.append(doc) }
        }
        for (id, when) in store.tombstones {
            // Sent as a set; the server matches on id and keeps whichever kind
            // it already knew this document by.
            var doc = SyncDocuments.tombstone(id, kind: .set, at: when)
            if send(&doc) { docs.append(doc) }
        }
        return (docs, pictures)
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

    func uploadPictures(for docs: [SyncDoc], token: String) async throws {
        let wanted = docs.compactMap { SyncDocuments.set(from: $0) }
        let names = Array(SyncDocuments.referencedBlobs(in: wanted))
        guard !names.isEmpty else { return }
        // Asking first turns a reinstall from a hundred-megabyte upload into one
        // small question, because the server already has every picture.
        for name in try await SyncAPI.missingBlobs(names, token: token) {
            guard let data = blobs.data(name) else { continue }
            try await SyncAPI.putBlob(data, name: name, token: token)
        }
    }

    /// Fetches any picture a set in the library is still only referring to.
    func fetchMissingPictures(token: String) async throws {
        let outstanding = store.library.flatMap { set in
            set.images.compactMap { BlobRefs.hash(fromRef: $0) }
        }
        let have = blobs.names()
        for name in Set(outstanding) where !have.contains(name) {
            let data = try await SyncAPI.getBlob(name, token: token)
            blobs.store(data)
        }
        // Now that they are here, put them into the sets that were waiting.
        for set in store.library where set.images.contains(where: BlobRefs.isRef) {
            store.applyFromSync(blobs.restore(set))
        }
    }
}
