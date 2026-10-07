import Foundation

/// Where a set's recording lives.
///
/// Deliberately a convention rather than a field on StudySet. A recording is a
/// forty-minute file: putting its path in the library JSON would be harmless,
/// but putting anything else there is a slope, and every file path saved inside
/// a document eventually breaks - iOS moves the container between installs and
/// restores, so an absolute path recorded last month points nowhere today.
/// Deriving the location from the set's id instead means it is right by
/// construction, and a set exported as JSON stays a text file rather than
/// silently referring to audio the other phone does not have.
enum LectureAudio {

    static var folder: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lectures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for setID: UUID, ext: String = "m4a") -> URL {
        folder.appendingPathComponent("\(setID.uuidString).\(ext)")
    }

    /// The recording for this set, whatever container it arrived in.
    ///
    /// Found by listing the folder for `<id>.*` rather than by trying a list
    /// of extensions: the picker accepts any audio, so .flac, .aiff, .m4b,
    /// .ogg and .3gp all arrive, and a recording stored under an extension
    /// the list did not have was never found again - no playback, no sync to
    /// the transcript, and a file nothing could remove.
    static func existing(for setID: UUID) -> URL? {
        recordings(for: setID).first
    }

    /// Every file stored for this set, most likely container first.
    static func recordings(for setID: UUID, in dir: URL = LectureAudio.folder) -> [URL] {
        let stem = setID.uuidString
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let known = ["m4a", "mp3", "wav", "aac", "caf", "mp4"]
        return names
            .filter { ($0 as NSString).deletingPathExtension == stem }
            .sorted { first, second in
                let a = known.firstIndex(of: (first as NSString).pathExtension.lowercased()) ?? known.count
                let b = known.firstIndex(of: (second as NSString).pathExtension.lowercased()) ?? known.count
                return a == b ? first < second : a < b
            }
            .map { dir.appendingPathComponent($0) }
    }

    /// Copy an imported file in, keeping its extension so AVAudioPlayer can
    /// work out the format.
    ///
    /// A file picked from the Files app or another app arrives security-scoped,
    /// which is why the access is opened and closed around the copy rather than
    /// the URL being kept - hold onto the original and it stops working the
    /// moment the picker goes away.
    ///
    /// The new file is copied in beside the old recording first, and only
    /// once it is all there does it take the old one's place: removing the
    /// old one first lost the student's only copy whenever the copy failed
    /// (the disk full, a file that stopped being readable half way). Earlier
    /// recordings under other extensions go after: one left behind under the
    /// same name made the copy fail with "an item with the same name already
    /// exists".
    @discardableResult
    static func store(imported source: URL, for setID: UUID) throws -> URL {
        try store(imported: source, for: setID, in: folder)
    }

    /// `store(imported:for:)` into a given folder (a test's own).
    static func store(imported source: URL, for setID: UUID, in dir: URL) throws -> URL {
        #if !os(Linux)  // security scopes are Apple's; the Linux test suites have plain files
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        #endif

        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let destination = dir.appendingPathComponent("\(setID.uuidString).\(ext)")
        // hidden, and named so it is never taken for one of the set's recordings
        let incoming = dir.appendingPathComponent(".incoming-\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: source, to: incoming)
        let older = recordings(for: setID, in: dir)
        let same = older.first { $0.lastPathComponent.lowercased() == destination.lastPathComponent.lowercased() }
        var placed = destination
        do {
            if let same {
                placed = try FileManager.default.replaceItemAt(same, withItemAt: incoming) ?? same
            } else {
                try FileManager.default.moveItem(at: incoming, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: incoming)
            throw error
        }
        for there in older where there != same {
            try? FileManager.default.removeItem(at: there)
        }
        return placed
    }

    /// The set's recording, gone from the phone. Called when the set is
    /// deleted: a lecture recording is tens of megabytes, often of other
    /// people's voices, and the student who deleted the set has no other way
    /// to reach it.
    static func remove(for setID: UUID) {
        for there in recordings(for: setID) {
            try? FileManager.default.removeItem(at: there)
        }
    }

    /// Minutes and seconds, for a transport bar, in the reader's digits
    /// (hours too, past the hour). The views pass L10n.locale; the locale is
    /// a parameter so this file stays Foundation-only for its Linux suite.
    static func clock(_ seconds: Double, locale: Locale) -> String {
        L10nFormat.clock(seconds: seconds, locale: locale)
    }
}
