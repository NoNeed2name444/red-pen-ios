import Foundation

/// A set that arrived as a file from somebody else's phone, made into one of
/// ours.
///
/// "Share as JSON" writes the set exactly as the sender's library holds it, and
/// two things in it only mean something on the sender's phone:
///   * its folder. The receiver has no folder with that id, and the library
///     shows a set either loose or inside a folder it has, so a set filed in
///     a folder that does not exist is saved, synced and nowhere to be seen;
///   * pictures that had not finished downloading there. A synced set holds
///     a `blob:` reference in place of each picture until the picture
///     arrives, and a reference names a picture in the SENDER's account. On
///     the receiver's phone it can never be fetched, and every sync that
///     tried failed whole.
///
/// Foundation only, so it is tested.
enum SetImport {

    struct Received {
        var set: StudySet
        /// Pictures the file referred to but did not carry. The cards that
        /// were nothing without them were left out.
        var missingPictures: Int
    }

    /// The set as it should join this library: a new id, its folder only if
    /// this library has that folder, dated today, and no picture it cannot
    /// have. `isMissing` says whether an image string is a reference rather
    /// than a picture (BlobRefs.isRef).
    static func received(_ incoming: StudySet, folders: Set<UUID>, now: Date = Date(),
                         isMissing: (String) -> Bool) -> Received {
        var set = incoming
        // never collide with a set already here - the sender's own copy of
        // it, if this is the sender's phone
        set.id = UUID()
        if let folder = set.folderId, !folders.contains(folder) { set.folderId = nil }
        // new to this library, so it sorts as new and syncs as a change
        set.createdAt = now
        set.updatedAt = now

        let missing = set.images.filter(isMissing).count
        guard missing > 0 else { return Received(set: set, missingPictures: 0) }

        // Pictures are referred to by position, so dropping one renumbers
        // every picture after it, everywhere the set points at one.
        var moved: [Int: Int] = [:]
        var kept: [String] = []
        for (index, image) in set.images.enumerated() where !isMissing(image) {
            moved[index] = kept.count
            kept.append(image)
        }
        set.images = kept
        set.cards = set.cards.compactMap { card -> AnkiCard? in
            guard let old = card.imageIndex else { return card }
            var renumbered = card
            renumbered.imageIndex = moved[old]
            // an occlusion card IS its picture; any other card still reads
            if renumbered.imageIndex == nil && card.type == .occlusion { return nil }
            return renumbered
        }
        set.questions = set.questions.map { question -> MCQQuestion in
            var renumbered = question
            if let old = question.imageIndex { renumbered.imageIndex = moved[old] }
            return renumbered
        }
        if !set.bookMarkdown.isEmpty {
            set.bookMarkdown = renumbered(set.bookMarkdown, moved: moved)
        }
        return Received(set: set, missingPictures: missing)
    }

    /// A textbook's picture lines pointed at their new positions, and the
    /// lines whose picture is gone taken out.
    static func renumbered(_ markdown: String, moved: [Int: Int]) -> String {
        markdown.components(separatedBy: "\n").compactMap { line -> String? in
            guard let (index, caption) = BookFigures.parse(line.trimmingCharacters(in: .whitespaces))
            else { return line }
            guard let now = moved[index] else { return nil }
            return "![\(caption)](\(BookFigures.reference(now)))"
        }.joined(separator: "\n")
    }
}
