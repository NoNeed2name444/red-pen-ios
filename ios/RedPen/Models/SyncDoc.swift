import Foundation

/// The kinds of thing that travel between a student's devices.
///
/// Everything is a document with an id, not a table with columns, because the
/// shapes here change with the app and a sync protocol that has to be migrated
/// every time a card gains a field is a sync protocol nobody dares change.
enum SyncKind: String, Codable, CaseIterable {
    case set        // a StudySet
    case folder     // a StudyFolder
    case review     // one card's place in the schedule
    case saying     // one learned pronunciation
}

/// One thing, as the server sees it.
///
/// `rev` is the server's revision counter and only the server ever sets it. It
/// is what makes "has anything changed since I last looked" answerable in one
/// request, and what tells a push whether it is about to overwrite something it
/// never saw.
///
/// `updatedAt` is the DEVICE's clock, and is used only to decide who wins when
/// two devices genuinely edited the same thing. Device clocks disagree, which
/// is exactly why it is not used for anything else.
struct SyncDoc: Codable, Equatable, Identifiable {
    var id: String
    var kind: SyncKind
    var rev: Int
    var updatedAt: Date
    /// A tombstone. Deletions have to travel as documents: a row that simply
    /// vanishes from one device is a row the other device happily uploads
    /// again, for ever.
    var deleted: Bool = false
    /// The thing itself, as JSON. Absent on a tombstone - there is nothing left
    /// to carry, and keeping the body of something somebody deleted is the
    /// opposite of deleting it.
    var payload: Data?

    /// Two documents carry the same thing when their bodies match. Used to tell
    /// a real conflict from two devices that happen to agree, which is the
    /// common case after a device has been offline.
    func sameContent(as other: SyncDoc) -> Bool {
        deleted == other.deleted && payload == other.payload
    }
}

/// What this device knows about a document's last successful sync.
///
/// Kept per document rather than as one timestamp for the whole library,
/// because "which of these did I change since we last agreed" cannot be
/// answered by a clock.
struct SyncMark: Codable, Equatable {
    /// The revision this device last pulled or pushed for that document.
    var rev: Int
    /// What the body looked like at that moment, as a hash. Comparing against
    /// it is how the device knows whether IT changed something, without having
    /// to keep a second copy of everything.
    var contentHash: String
}
