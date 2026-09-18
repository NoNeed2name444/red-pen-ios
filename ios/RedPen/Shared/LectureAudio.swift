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
    static func existing(for setID: UUID) -> URL? {
        for ext in ["m4a", "mp3", "wav", "aac", "caf", "mp4"] {
            let candidate = url(for: setID, ext: ext)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Copy an imported file in, keeping its extension so AVAudioPlayer can
    /// work out the format.
    ///
    /// A file picked from the Files app or another app arrives security-scoped,
    /// which is why the access is opened and closed around the copy rather than
    /// the URL being kept - hold onto the original and it stops working the
    /// moment the picker goes away.
    @discardableResult
    static func store(imported source: URL, for setID: UUID) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let destination = url(for: setID, ext: ext)
        if let already = existing(for: setID) {
            try? FileManager.default.removeItem(at: already)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    static func remove(for setID: UUID) {
        if let there = existing(for: setID) {
            try? FileManager.default.removeItem(at: there)
        }
    }

    /// Minutes and seconds, for a transport bar.
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
