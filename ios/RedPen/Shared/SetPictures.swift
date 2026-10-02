import Foundation

/// Pictures that travel with the items that show them. A question or card
/// points into its own set's `images` by position, so moving it into another
/// set without its picture shows nothing, or someone else's picture.
extension StudySet {

    /// Picture `index` of `source`, copied into this set, and its position
    /// here. One already here is pointed at rather than copied again, so a
    /// set topped up many times does not grow a copy per top-up.
    mutating func carryPicture(_ index: Int?, from source: StudySet) -> Int? {
        guard let index, source.images.indices.contains(index) else { return nil }
        let picture: String = source.images[index]
        if let at = images.firstIndex(of: picture) { return at }
        images.append(picture)
        return images.count - 1
    }

    /// The "Mistakes" set's top-up: questions not already here, by stem,
    /// each with its picture (audit #20 - they used to arrive without).
    mutating func addMistakes(_ questions: [MCQQuestion], from source: StudySet) {
        var known: Set<String> = Set(self.questions.map(\.stem))
        for q in questions where !known.contains(q.stem) {
            var q = q
            q.imageIndex = carryPicture(q.imageIndex, from: source)
            self.questions.append(q)
            known.insert(q.stem)
        }
        for doc in source.sources where !sources.contains(where: { $0.id == doc.id }) {
            sources.append(doc)
        }
    }

    /// Two or more sets of one kind as a new set named `name`: every picture
    /// re-based into the joined pool - a book's `image:N` lines too (audit
    /// #19) - and every set's sources kept, so citations still open.
    static func combined(_ members: [StudySet], name: String) -> StudySet? {
        guard let first = members.first, members.count >= 2,
              members.allSatisfy({ $0.kind == first.kind }) else { return nil }
        var out = StudySet(name: name, subject: first.subject, kind: first.kind)
        for m in members {
            let base: Int = out.images.count
            out.images.append(contentsOf: m.images)
            for doc in m.sources where !out.sources.contains(where: { $0.id == doc.id }) {
                out.sources.append(doc)
            }
            switch m.kind {
            case .mcq:
                out.questions.append(contentsOf: m.questions.map { q in
                    var q = q; q.id = UUID(); if let i = q.imageIndex { q.imageIndex = i + base }; return q
                })
            case .anki:
                out.cards.append(contentsOf: m.cards.map { c in
                    var c = c; c.id = UUID(); if let i = c.imageIndex { c.imageIndex = i + base }; return c
                })
            case .book:
                let rebased: String = BookFigures.rebased(m.bookMarkdown, by: base)
                out.bookMarkdown += (out.bookMarkdown.isEmpty ? "" : "\n\n") + rebased
            case .osce:
                out.osceChecklists.append(contentsOf: m.osceChecklists.map { var c = $0; c.id = UUID(); return c })
            case .narrate:
                out.narrateSegments.append(contentsOf: m.narrateSegments.map { var s = $0; s.id = UUID(); return s })
            }
        }
        return out
    }
}
