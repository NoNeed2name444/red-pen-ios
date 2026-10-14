import Foundation

/// The Idea Board's links as pairs, each pair once, in one pass over the
/// notes. Asking every note for its links looked each one up by scanning all
/// the notes, which grew with the square of the note count and ran on every
/// frame of a pan, pinch or card drag (audit #106); NoteStore now keeps the
/// result until a note changes.
enum IdeaEdges {
    /// `outgoing`: each note and what it links to, by hand or by
    /// `[[Title]]`. A link to itself or to a note that is gone is left out;
    /// each pair is ordered by id, so a line always bows the same way.
    static func pairs(_ outgoing: [(id: UUID, to: [UUID])]) -> [(UUID, UUID)] {
        let known = Set(outgoing.map(\.id))
        var seen = Set<String>()
        var edges: [(UUID, UUID)] = []
        for (id, targets) in outgoing {
            for other in targets where other != id && known.contains(other) {
                let pair: (UUID, UUID) = id.uuidString < other.uuidString ? (id, other) : (other, id)
                if seen.insert(pair.0.uuidString + pair.1.uuidString).inserted { edges.append(pair) }
            }
        }
        return edges
    }
}
