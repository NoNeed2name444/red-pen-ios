import Foundation

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

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("RedPenSources", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

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
    @discardableResult
    static func keep(_ url: URL, kind: SourceDoc.Kind) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let name = BlobRefs.name(for: data)
        let destination = directory.appendingPathComponent(name).appendingPathExtension(ext(kind))
        if !FileManager.default.fileExists(atPath: destination.path) {
            try? data.write(to: destination, options: .atomic)
        }
        return name
    }

    /// Drops files no source in the library refers to any more.
    ///
    /// Only ever called with the whole library in hand. A sweep run on part of
    /// it deletes lectures that are still in use - and unlike a stale file, a
    /// missing one is visible the moment somebody opens a card and asks where
    /// it came from.
    static func sweep(keeping live: Set<String>) {
        let found = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in found {
            let name = (file as NSString).deletingPathExtension
            guard !live.contains(name) else { continue }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
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
