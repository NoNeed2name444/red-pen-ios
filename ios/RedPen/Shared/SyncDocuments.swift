import Foundation

/// Turning the library into documents, and documents back into the library.
///
/// This is where the app's own shapes meet the wire, and it is kept pure -
/// values in, values out, no store and no network - because the interesting
/// decisions live here and every one of them is a way to lose somebody's work.
enum SyncDocuments {

    /// The schedule travels one document per deck, not one per card.
    ///
    /// A card apiece would be thousands of documents for a term's work. The
    /// whole schedule in one document would be worse: two phones reviewing two
    /// different decks on the same afternoon would each overwrite the other,
    /// and a day of reviews would disappear. Per deck matches how people
    /// actually study - one deck at a time - and makes a clash rare. When one
    /// does happen it is merged card by card rather than decided by last write,
    /// so nothing is lost even then.
    static func reviewDocID(forSet id: UUID) -> String { "review-" + id.uuidString }

    static func setID(fromReviewDocID id: String) -> UUID? {
        UUID(uuidString: String(id.dropFirst("review-".count)))
    }

    // MARK: the library, as documents

    /// One set, with its pictures replaced by references, and the bytes that
    /// now have to exist on the server.
    static func document(for set: StudySet) throws -> (doc: SyncDoc, blobs: [String: Data]) {
        var packed = set
        let (refs, blobs) = BlobRefs.pack(set.images)
        packed.images = refs
        let payload = try JSONEncoder.sync.encode(packed)
        return (SyncDoc(id: set.id.uuidString, kind: .set, rev: 0,
                        updatedAt: set.updatedAt, deleted: false, payload: payload), blobs)
    }

    static func document(for folder: StudyFolder) throws -> SyncDoc {
        SyncDoc(id: folder.id.uuidString, kind: .folder, rev: 0,
                updatedAt: folder.updatedAt, deleted: false,
                payload: try JSONEncoder.sync.encode(folder))
    }

    /// The schedule for one deck: only the cards that deck actually holds, so a
    /// card deleted from it stops being synced with it.
    static func reviewDocument(forSet set: StudySet,
                               records: [UUID: ReviewRecord]) throws -> SyncDoc? {
        var mine: [String: ReviewRecord] = [:]
        for card in set.cards {
            if let record = records[card.id] { mine[card.id.uuidString] = record }
        }
        guard !mine.isEmpty else { return nil }
        // The document's own timestamp is the most recent rating in it, so a
        // deck nobody has touched does not keep looking newer every time the
        // app opens.
        let newest = mine.values.map(\.ratedAt).max() ?? Date()
        return SyncDoc(id: reviewDocID(forSet: set.id), kind: .review, rev: 0,
                       updatedAt: newest, deleted: false,
                       payload: try JSONEncoder.sync.encode(mine))
    }

    static func tombstone(_ id: UUID, kind: SyncKind, at when: Date) -> SyncDoc {
        SyncDoc(id: id.uuidString, kind: kind, rev: 0, updatedAt: when,
                deleted: true, payload: nil)
    }

    // MARK: documents, as the library

    static func set(from doc: SyncDoc) -> StudySet? {
        guard let payload = doc.payload else { return nil }
        return try? JSONDecoder.sync.decode(StudySet.self, from: payload)
    }

    static func folder(from doc: SyncDoc) -> StudyFolder? {
        guard let payload = doc.payload else { return nil }
        return try? JSONDecoder.sync.decode(StudyFolder.self, from: payload)
    }

    static func records(from doc: SyncDoc) -> [UUID: ReviewRecord] {
        guard let payload = doc.payload,
              let raw = try? JSONDecoder.sync.decode([String: ReviewRecord].self, from: payload)
        else { return [:] }
        var out: [UUID: ReviewRecord] = [:]
        for (key, record) in raw {
            if let id = UUID(uuidString: key) { out[id] = record }
        }
        return out
    }

    /// Every blob any of these sets refers to. What a sweep must keep.
    static func referencedBlobs(in sets: [StudySet]) -> Set<String> {
        BlobRefs.names(in: sets.flatMap(\.images))
    }

    /// Merging two versions of a deck's schedule - see ReviewPlan, where the
    /// rule lives with the rest of the scheduling.
    static func mergeRecords(_ mine: [UUID: ReviewRecord],
                             _ theirs: [UUID: ReviewRecord]) -> [UUID: ReviewRecord] {
        ReviewPlan.merging(mine, theirs)
    }
}

extension JSONEncoder {
    /// The encoder every payload goes through.
    ///
    /// Sorted keys are load-bearing, not tidiness: a document's hash is what
    /// tells a device whether it changed something, and a dictionary that
    /// encodes its keys in a different order each time would make every
    /// document look edited on every launch. Compact rather than pretty because
    /// these go over a phone connection.
    static let sync: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let sync: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
