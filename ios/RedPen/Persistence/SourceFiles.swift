import Foundation
import CryptoKit

/// Original lecture files, kept on the device that imported them.
///
/// Filed under the hash of their own bytes, like the pictures in BlobCache and
/// for the same reasons: the same lecture imported into three sets is stored
/// once, and re-importing a file cannot produce a second copy.
///
/// Deliberately NOT synced. A term of slide decks is gigabytes, and pushing
/// that between devices to make the preview prettier would cost the student
/// their data allowance to save them a tap. The text travels; the file stays.
/// Everything here is therefore optional by design - `url(for:)` returning nil
/// is the normal state on a second device, not a failure.
enum SourceFiles {

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("RedPenSources", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Not in the phone's backup: a term of slide decks is gigabytes, the
        // text the sets need is inside the library, and the files themselves
        // can be imported again. Backed up, they filled a free iCloud until
        // the phone's backups stopped working.
        var excluded = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        return folder
    }()

    /// Where this source's file is, if this device has it.
    static func url(for source: SourceDoc) -> URL? {
        guard let blob = source.fileBlob else { return nil }
        let candidate = directory.appendingPathComponent(blob).appendingPathExtension(ext(source.kind))
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Takes a copy of an imported file and returns its hash, or nil if it
    /// could not be read.
    ///
    /// A copy, because the URL a document picker hands over is borrowed: it is
    /// security scoped, it may live in another app's container, and it can stop
    /// resolving as soon as the import finishes.
    ///
    /// Read a piece at a time and copied, never held whole: a lecture deck with
    /// video in it is hundreds of megabytes, and reading all of it into memory
    /// - beside the copy the importer had just read - is how an app gets
    /// ended for using too much. Off the main thread from a screen: `keeping`.
    @discardableResult
    static func keep(_ url: URL, kind: SourceDoc.Kind) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let name = hash(of: url) else { return nil }
        let destination = directory.appendingPathComponent(name).appendingPathExtension(ext(kind))
        let files = FileManager.default
        if !files.fileExists(atPath: destination.path) {
            // a copy (a clone, on the phone's file system) put in place whole,
            // so a half-copied file is never taken for the lecture
            let partial = directory.appendingPathComponent(UUID().uuidString + ".partial")
            do {
                try files.copyItem(at: url, to: partial)
                try files.moveItem(at: partial, to: destination)
            } catch {
                try? files.removeItem(at: partial)
            }
        }
        // Dated now, whatever the original's date: a file just picked belongs
        // to a set still being made, and the sweep leaves recent files alone.
        try? files.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
        return name
    }

    /// `keep`, off the main thread - for a screen, which would otherwise
    /// freeze for the seconds a big file takes to hash and copy.
    static func keeping(_ url: URL, kind: SourceDoc.Kind) async -> String? {
        await Task.detached(priority: .userInitiated) { keep(url, kind: kind) }.value
    }

    /// The SHA-256 of a file's bytes in hex - the same name BlobRefs gives the
    /// same bytes - read a megabyte at a time.
    private static func hash(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try? handle.read(upToCount: 1 << 20) else { return nil }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Drops files no source in the library refers to any more.
    ///
    /// Only ever called with the whole library in hand. A sweep run on part of
    /// it deletes lectures that are still in use - and unlike a stale file, a
    /// missing one is visible the moment somebody opens a card and asks where
    /// it came from.
    ///
    /// A file from the last day is never swept, referred to or not: it may
    /// belong to a set still being made - a New set sheet that has read the
    /// lecture and not been saved yet.
    static func sweep(keeping live: Set<String>, sparingNewerThan age: TimeInterval = 86_400) {
        let files = FileManager.default
        let found = (try? files.contentsOfDirectory(atPath: directory.path)) ?? []
        let cutoff = Date().addingTimeInterval(-age)
        for file in found {
            let name = (file as NSString).deletingPathExtension
            guard !live.contains(name) else { continue }
            let url = directory.appendingPathComponent(file)
            let modified = (try? files.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            guard let modified, modified < cutoff else { continue }
            try? files.removeItem(at: url)
        }
    }

    /// The sweep, with everything that may still need a file: the library,
    /// sets this version could not read, and cloud jobs not yet collected
    /// (their recipes carry the lecture they were made from). Off the main
    /// thread; called once the library has loaded.
    @MainActor
    static func sweepUnused(in store: Store) {
        // a library that could not be read is not a library that refers to
        // nothing: nothing is swept on its word
        guard store.readWhole else { return }
        var live = referenced(in: store.library)
        for text in store.unreadSets { live.formUnion(BlobRefs.hashes(in: text)) }
        for job in CloudJobs.pending() {
            if let recipe = job.recipe, let text = String(data: recipe, encoding: .utf8) {
                live.formUnion(BlobRefs.hashes(in: text))
            }
        }
        let keep = live
        Task.detached(priority: .background) { sweep(keeping: keep) }
    }

    /// Every file hash the library still refers to.
    static func referenced(in sets: [StudySet]) -> Set<String> {
        Set(sets.flatMap { $0.sources.compactMap(\.fileBlob) })
    }

    private static func ext(_ kind: SourceDoc.Kind) -> String {
        switch kind {
        case .pdf: return "pdf"
        case .word: return "docx"
        case .powerpoint: return "pptx"
        case .text: return "txt"
        }
    }
}
