import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// What this device last agreed with the server about.
///
/// Two things, and the difference between them matters.
///
/// `cursor` is the server's revision counter as of the last successful pull. It
/// makes "what has changed since I last looked" one cheap request instead of a
/// comparison of the whole library.
///
/// `marks` is per document: the revision this device last saw for it, and a
/// hash of what it contained then. The hash is the only way to answer "did *I*
/// change this?" without keeping a second copy of everything to compare
/// against.
///
/// Deliberately stored beside the library rather than inside it. It describes
/// this device's relationship with the server, not the student's material - and
/// a library exported, shared or restored onto another phone must not arrive
/// claiming to be already in sync.
struct SyncState: Codable, Equatable {
    var cursor: Int = 0
    var marks: [String: SyncMark] = [:]
    /// The `updatedAt` of each set as we last agreed it.
    ///
    /// Purely to avoid work: packing a set hashes every picture in it, and
    /// doing that for the whole library on every foreground to discover that
    /// nothing changed would be hundreds of megabytes of hashing. Store moves a
    /// set's `updatedAt` only when something really differs, so an unchanged
    /// stamp is a reliable "skip this one".
    var stamps: [String: Date] = [:]
    /// The last id this device announced itself under. Used to name conflict
    /// copies after the device they came from, which is the only thing that
    /// makes two copies of a deck tellable apart.
    var deviceName: String = ""
    var lastSyncedAt: Date?

    /// The account these bookmarks describe. They are about that account's
    /// copy on the server and nothing else: another account starts from
    /// nothing, however it came to be signed in. Nil when nothing has synced
    /// since this was first recorded.
    var accountId: String?
    /// The account this device's library has been sent up to. Somebody else
    /// signing in on the same phone is asked before any of it goes into their
    /// account (SyncEngine.chooseLibrary). Survives a reset: it is about the
    /// library on this device, not about any account's bookmarks.
    var libraryOwner: String?
    /// Sets and folders kept on this device only - a library that was here
    /// before a different account signed in, when the student chose not to
    /// add it. Never pushed. Survives a reset, like `libraryOwner`.
    var heldBack: Set<String> = []
    /// Documents the server would not keep, so they are not sent again every
    /// minute to be refused again (SyncRules.stillRefused).
    var refused: [String: RefusedDoc] = [:]
    /// Documents from another device this version could not read, and their
    /// revision. The cursor has moved past them, so after an update they are
    /// fetched again rather than missed for good.
    var unreadable: [String: Int] = [:]
    /// Documents from another device carrying fields this version would drop
    /// on its next save (SyncRules.dropsFields), and their revision. Edits to
    /// them wait here until the app is updated; after that they are fetched
    /// again whole.
    var newer: [String: Int] = [:]
    /// What `newer` held under the build before this one, while those
    /// documents are read again after an update.
    var newerBefore: [String: Int] = [:]
    /// When each document in `newer` was first held at that revision. One
    /// still held a month on, unchanged, is let go (SyncRules.holdsForNewer):
    /// no update is coming that keeps its fields.
    var newerSince: [String: Date] = [:]
    /// The build that last synced: a different one reads `unreadable` and
    /// `newer` again.
    var build: String?
    /// Pictures the server said it does not have (or would not look up), and
    /// when. Asked for again only after a while, or when a set naming them
    /// arrives again (SyncRules.asksForPicture) - not on every run for ever.
    var missingPictures: [String: Date] = [:]

    func mark(_ id: String) -> SyncMark? { marks[id] }

    /// Records agreement about ONE document. Deliberately does not touch the
    /// cursor.
    ///
    /// The cursor is a promise about the whole account - "I have seen
    /// everything up to here" - and only a pull is ever in a position to make
    /// it. Documents are also remembered while resolving a push conflict, and
    /// the conflicting document's revision can be far ahead of what this device
    /// has actually pulled. Moving the cursor to it would quietly skip every
    /// document in between, on every device, for ever.
    mutating func remember(_ doc: SyncDoc) {
        marks[doc.id] = SyncMerge.mark(for: doc)
    }

    mutating func forget(_ id: String) {
        marks[id] = nil
        stamps[id] = nil
    }
}

/// Read field by field, each with its default when absent: a bookmark file
/// that failed to read would be thrown away, and a device with no bookmarks
/// treats every document it has as a conflict. Files written before a field
/// existed are the usual case, not the exception.
extension SyncState {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ type: T.Type) -> T? {
            let found: T?? = try? c.decodeIfPresent(type, forKey: key)
            return found ?? nil
        }
        cursor = read(.cursor, Int.self) ?? 0
        marks = read(.marks, [String: SyncMark].self) ?? [:]
        stamps = read(.stamps, [String: Date].self) ?? [:]
        deviceName = read(.deviceName, String.self) ?? ""
        lastSyncedAt = read(.lastSyncedAt, Date.self)
        accountId = read(.accountId, String.self)
        libraryOwner = read(.libraryOwner, String.self)
        heldBack = read(.heldBack, Set<String>.self) ?? []
        refused = read(.refused, [String: RefusedDoc].self) ?? [:]
        unreadable = read(.unreadable, [String: Int].self) ?? [:]
        newer = read(.newer, [String: Int].self) ?? [:]
        newerBefore = read(.newerBefore, [String: Int].self) ?? [:]
        newerSince = read(.newerSince, [String: Date].self) ?? [:]
        build = read(.build, String.self)
        missingPictures = read(.missingPictures, [String: Date].self) ?? [:]
    }
}

/// Where that bookmark lives between launches.
///
/// Changed in memory and written when asked (`commit`), off the main thread.
/// A sync changes a bookmark per document, and writing the whole file for each
/// one made a first sync of a big library freeze the screen. Writing later is
/// also what lets the order be right: a bookmark may only reach the disk after
/// the library it describes (SyncEngine commits after `Store.flushed`). A
/// bookmark lost to the app being killed costs a document fetched twice; one
/// written before its document would be a document missed for good.
@MainActor
final class SyncStateStore {
    private let fileURL: URL
    private(set) var state = SyncState()
    /// Moves on every reset. A sync run notes it when it starts and stops as
    /// soon as it has moved, so a run that began for one account can never
    /// write that account's bookmarks back over another's.
    private(set) var generation = 0
    private var dirty = false

    /// One write at a time, in order: a later bookmark never lands before an
    /// earlier one.
    private static let writeQueue = DispatchQueue(label: "redpen.sync-state.write", qos: .utility)

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = dir.appendingPathComponent("redpen-sync.json")
        }
        // self.fileURL, not the parameter: the parameter is the optional the
        // caller may not have passed, and the one just settled above is the
        // file we actually read.
        if let data = try? Data(contentsOf: self.fileURL),
           let stored = try? JSONDecoder.redPen.decode(SyncState.self, from: data) {
            state = stored
        }
        if state.deviceName.isEmpty { state.deviceName = Self.thisDevice() }
    }

    /// Changes the bookmarks in memory; `commit` writes them.
    func update(_ change: (inout SyncState) -> Void) {
        change(&state)
        dirty = true
    }

    /// Writes whatever changed, and returns once it is on disk. The main
    /// thread is not held while it is written.
    func commit() async {
        guard dirty else { return }
        dirty = false
        let snapshot = state
        let url = fileURL
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            Self.writeQueue.async {
                Self.write(snapshot, to: url)
                done.resume()
            }
        }
    }

    /// Everything this device thought it knew about an account, thrown away.
    ///
    /// Used when somebody signs in as a different person: keeping the old
    /// bookmarks would have the new account's first sync assume it had already
    /// seen documents it has never met. What is about the library on this
    /// device rather than an account - its name, whose library it is, what
    /// stays on it - is kept.
    func reset() {
        let kept = state
        state = SyncState()
        state.deviceName = kept.deviceName
        state.libraryOwner = kept.libraryOwner
        state.heldBack = kept.heldBack
        generation &+= 1
        dirty = true
        Task { await self.commit() }
    }

    private nonisolated static func write(_ state: SyncState, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// A name a person would recognise on a conflict copy - "Ahmed's iPhone"
    /// rather than a UUID.
    private static func thisDevice() -> String {
        #if canImport(UIKit)
        let name = UIDevice.current.name
        return name.isEmpty ? "another device" : name
        #else
        return "another device"
        #endif
    }
}
