import Foundation

// What the map's picture takes from the notes, folders and links, as one
// number: the larger part of the 3D map's signature (Graph3DView), which
// decides when the map is planned again.
//
// The signature is worked out every time SwiftUI redraws the screen around
// the map - each save while a note is being typed (half a second after the
// typing pauses, even with the editor over the map), every tap, every step
// of the link-length slider. It used to build a line of text per note and
// count every note's words each time (Chat-me audit row 107). This hashes
// the same fields without building any text, and counts a note's words again
// only when its text has changed, so a redraw costs a pass over the notes'
// names and ids, not over everything written in them.
//
// Foundation only, so it is tested on Linux.

/// The notes' part of the map's signature, keeping each note's size step
/// (GraphUniverse.level) until its text changes. One per map; main thread
/// only.
nonisolated final class GraphShapeKey {
    /// One note, as the signature needs it.
    struct Note {
        var id: UUID
        var title: String
        var kind: String
        var folder: UUID?
        var body: String
    }

    /// One folder, as the signature needs it.
    struct Folder {
        var id: UUID
        var name: String
        var parent: UUID?
    }

    /// Each note's text when its words were last counted, and its size step.
    private var steps: [UUID: (body: String, step: Int)] = [:]
    /// How many notes' words have been counted in all; the tests read it.
    private(set) var counted: Int = 0

    /// How many notes' size steps are kept.
    var remembered: Int { steps.count }

    /// The same notes, links and folders give the same number while the app
    /// runs (not from one launch to the next: Swift seeds its hashing anew).
    /// - Parameter levels: whether each note's size step counts (the
    ///   Universe and the themes, which size by length); the single looks
    ///   ignore a note's text.
    func key(notes: [Note], edges: [(UUID, UUID)], folders: [Folder], levels: Bool) -> Int {
        var hasher = Hasher()
        hasher.combine(notes.count)
        for note in notes {
            hasher.combine(note.id)
            hasher.combine(note.title)
            hasher.combine(note.kind)
            hasher.combine(note.folder)
            if levels { hasher.combine(step(note)) }
        }
        hasher.combine(edges.count)
        for edge in edges {
            hasher.combine(edge.0)
            hasher.combine(edge.1)
        }
        hasher.combine(folders.count)
        for folder in folders {
            hasher.combine(folder.id)
            hasher.combine(folder.name)
            hasher.combine(folder.parent)
        }
        // a note that is gone is forgotten
        if levels && steps.count > notes.count {
            let here: Set<UUID> = Set(notes.map(\.id))
            steps = steps.filter { here.contains($0.key) }
        }
        return hasher.finalize()
    }

    /// The note's size step, counted again only when its text has changed.
    /// Text that has not changed is the very same string as last time, so
    /// the comparison does not read it.
    private func step(_ note: Note) -> Int {
        if let kept = steps[note.id], kept.body == note.body { return kept.step }
        let step: Int = GraphUniverse.level(words: GraphUniverse.wordCount(note.body))
        steps[note.id] = (note.body, step)
        counted += 1
        return step
    }
}
