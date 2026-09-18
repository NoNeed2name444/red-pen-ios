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

/// Where that bookmark lives between launches.
@MainActor
final class SyncStateStore {
    private let fileURL: URL
    private(set) var state = SyncState()

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

    func update(_ change: (inout SyncState) -> Void) {
        change(&state)
        save()
    }

    /// Everything this device thought it knew, thrown away.
    ///
    /// Used when somebody signs in as a different person: keeping the old
    /// bookmarks would have the new account's first sync assume it had already
    /// seen documents it has never met.
    func reset() {
        let name = state.deviceName
        state = SyncState()
        state.deviceName = name
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder.redPen.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
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
