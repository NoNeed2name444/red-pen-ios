import Foundation

/// The limits a push has to live within, and how a document written by a
/// different version of the app is read.
///
/// Pure - documents in, decisions out - because each rule here is a way for a
/// deck to stop syncing without anybody noticing: a push too big for the
/// server that fails on every run, a document the server quietly leaves out,
/// or an older phone saving over fields it cannot see.
enum SyncRules {

    /// The longest payload the server keeps, in base64 characters
    /// (server/sync.js, MAX_PAYLOAD_CHARS). A document over it is left out of
    /// the push by the server without a word, so it is caught here instead.
    static let maxPayloadChars = 1_900_000
    /// Documents per push. The server takes at most 500 and writes them twenty
    /// to a database call; far fewer keeps one request well inside a Worker's
    /// time and call limits, and lets a first sync land a batch at a time.
    static let maxDocsPerPush = 50
    /// Bytes per push. The server refuses a body over 24 MB outright; a few
    /// megabytes parse comfortably and survive a weak connection.
    static let maxBytesPerPush = 4 * 1024 * 1024

    /// A payload's length as the server counts it: base64 characters.
    static func payloadChars(_ doc: SyncDoc) -> Int {
        guard let payload = doc.payload else { return 0 }
        return (payload.count + 2) / 3 * 4
    }

    /// Whether the server would keep this document at all.
    static func fitsServer(_ doc: SyncDoc) -> Bool {
        payloadChars(doc) <= maxPayloadChars
    }

    /// Roughly what a document adds to a push's JSON body.
    static func wireSize(_ doc: SyncDoc) -> Int {
        payloadChars(doc) + doc.id.utf8.count + 160
    }

    /// The documents, in order, cut into pushes the server can take. A
    /// document bigger than a whole batch still goes, on its own - leaving it
    /// out would be the silent failure this exists to prevent.
    static func batches(_ docs: [SyncDoc], maxDocs: Int = maxDocsPerPush,
                        maxBytes: Int = maxBytesPerPush) -> [[SyncDoc]] {
        var out: [[SyncDoc]] = []
        var current: [SyncDoc] = []
        var bytes = 0
        for doc in docs {
            let size = wireSize(doc)
            if !current.isEmpty && (current.count >= maxDocs || bytes + size > maxBytes) {
                out.append(current)
                current = []
                bytes = 0
            }
            current.append(doc)
            bytes += size
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    // MARK: documents the server would not take

    /// Whether a document the server refused last time should be left out of
    /// this push without even being built again.
    ///
    /// Too large: until it changes, since sending the same bytes again gets the
    /// same answer (and costs the student a couple of megabytes of data a
    /// minute). Anything else - the account was full, the server had a reason
    /// of its own - is tried again after a day, or as soon as it changes.
    static func stillRefused(_ refused: RefusedDoc?, updatedAt: Date?, now: Date = Date()) -> Bool {
        guard let refused, let updatedAt, refused.updatedAt == updatedAt else { return false }
        return refused.tooLarge || now.timeIntervalSince(refused.at) < retryRefusedAfter
    }

    static let retryRefusedAfter: TimeInterval = 86_400

    // MARK: pictures the server does not have

    /// Whether a failed fetch means the server does not have that picture
    /// (404) or will not look it up (400) - an answer that asking again in a
    /// minute will not change - rather than a moment's trouble.
    static func pictureIsMissing(status: Int) -> Bool {
        status == 404 || status == 400
    }

    /// Whether to ask for a picture the server said it did not have. Not on
    /// every run: a picture nobody ever uploaded is otherwise a request a
    /// minute for ever, from every device. Once a week, in case the device
    /// that has it finally sent it - and sooner whenever a set naming it
    /// arrives again, since a device uploads a set's pictures before the set.
    static func asksForPicture(missingSince: Date?, now: Date = Date()) -> Bool {
        guard let missingSince else { return true }
        return now.timeIntervalSince(missingSince) >= askAgainForMissingPictureAfter
    }

    static let askAgainForMissingPictureAfter: TimeInterval = 7 * 86_400

    // MARK: a newer version's document

    /// Where to pull from after the app is updated, so the documents the last
    /// version could not read - or read only in part - come again. The cursor
    /// moved past them long ago; without this they would only ever return if
    /// the other device happened to change them.
    static func rereadCursor(_ cursor: Int, revisiting revisions: [Int]) -> Int {
        guard let earliest = revisions.min() else { return cursor }
        return min(cursor, max(0, earliest - 1))
    }

    /// Whether this device holds its edits to a document back until the app
    /// is updated: saving would lose fields (`dropsFields`).
    ///
    /// Not for ever. `heldSince` is when this same revision was first held,
    /// when it was held before - read again after an update that still could
    /// not keep those fields, with nothing written on the other device since.
    /// Held that way for a month, the fields are not a newer version's at all
    /// but ones no version keeps any more (a field since taken out of the
    /// app), and waiting would keep the set's edits off every other device
    /// for good.
    static func holdsForNewer(dropsFields: Bool, heldSince: Date?, now: Date = Date()) -> Bool {
        guard dropsFields else { return false }
        guard let heldSince else { return true }
        return now.timeIntervalSince(heldSince) < holdForNewerAtMost
    }

    static let holdForNewerAtMost: TimeInterval = 30 * 86_400

    /// Whether reading a document and writing it back loses something.
    ///
    /// A newer version of the app adds a field; an older one reads the
    /// document tolerantly - which means without that field - and every save
    /// it then makes would push the document back without it, erasing it on
    /// every device. Comparing what arrived with what this version would send
    /// back finds that before it happens.
    ///
    /// Only what is LOST counts. A field this version adds (an older device
    /// never wrote it) is not a loss, and neither is a key that held nothing -
    /// null, or an empty list.
    static func dropsFields(original: Data, reencoded: Data) -> Bool {
        if original == reencoded { return false }
        guard let before = try? JSONSerialization.jsonObject(with: original, options: [.fragmentsAllowed]),
              let after = try? JSONSerialization.jsonObject(with: reencoded, options: [.fragmentsAllowed])
        else { return false }
        return loses(before, after)
    }

    private static func loses(_ before: Any, _ after: Any) -> Bool {
        if let old = before as? [String: Any] {
            guard let new = after as? [String: Any] else { return !holdsNothing(before) }
            for (key, value) in old {
                guard let kept = new[key] else {
                    if holdsNothing(value) { continue }
                    return true
                }
                if loses(value, kept) { return true }
            }
            return false
        }
        if let old = before as? [Any] {
            guard let new = after as? [Any] else { return !old.isEmpty }
            // a list this version shortened dropped whatever it could not read
            if new.count < old.count { return true }
            for (index, value) in old.enumerated() where loses(value, new[index]) { return true }
            return false
        }
        return !sameValue(before, after)
    }

    private static func holdsNothing(_ value: Any) -> Bool {
        if value is NSNull { return true }
        if let list = value as? [Any] { return list.isEmpty }
        if let object = value as? [String: Any] { return object.isEmpty }
        return false
    }

    /// Two plain JSON values alike: an enum case this version does not know,
    /// read as a default, is a value it would write back differently.
    private static func sameValue(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? String, let y = b as? String { return x == y }
        if let x = a as? NSNumber, let y = b as? NSNumber { return x == y }
        if a is NSNull && b is NSNull { return true }
        return false
    }
}

/// A document the server would not keep, and what it held then - so the same
/// bytes are not sent again every minute to be refused again.
struct RefusedDoc: Codable, Equatable {
    /// The set's `updatedAt` when it was refused; a change moves it, and the
    /// changed set is tried again.
    var updatedAt: Date?
    var at: Date
    /// Over the server's size limit, rather than refused for some other reason.
    var tooLarge: Bool
}
