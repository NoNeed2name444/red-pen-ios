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
    static func recordings(for setID: UUID) -> [URL] {
        let stem = setID.uuidString
        let dir = folder
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
    /// Every earlier recording for the set goes first, whatever its
    /// extension: one left behind under the same name made the copy fail with
    /// "an item with the same name already exists".
    @discardableResult
    static func store(imported source: URL, for setID: UUID) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let destination = url(for: setID, ext: ext)
        remove(for: setID)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
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
    /// (hours too, past the hour).
    static func clock(_ seconds: Double) -> String {
        L10nFormat.clock(seconds: seconds, locale: L10n.locale)
    }
}
