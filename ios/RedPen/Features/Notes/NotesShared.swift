import SwiftUI
import UIKit

/// The quiet colour each top-level folder is known by, on the board and in the
/// space alike. Muted on purpose: it is there to tell clusters apart at a
/// glance, not to decorate.
enum NoteTone {
    private static let palette: [Color] = [
        Color(red: 0.36, green: 0.62, blue: 0.60),  // sea green
        Color(red: 0.45, green: 0.47, blue: 0.75),  // slate blue
        Color(red: 0.78, green: 0.58, blue: 0.40),  // sand
        Color(red: 0.62, green: 0.46, blue: 0.66),  // heather
        Color(red: 0.47, green: 0.63, blue: 0.42),  // sage
        Color(red: 0.76, green: 0.47, blue: 0.47),  // clay
        Color(red: 0.40, green: 0.58, blue: 0.76),  // sky
    ]

    /// Loose notes are plain grey; a note in a folder takes the colour of
    /// the top-level folder it sits in.
    @MainActor
    static func color(for folderId: UUID?, in store: NoteStore) -> Color {
        guard let root = store.rootFolder(of: folderId),
              let index = store.subfolders(of: nil).firstIndex(where: { $0.id == root })
        else { return Color.gray }
        return palette[index % palette.count]
    }

    @MainActor
    static func uiColor(for folderId: UUID?, in store: NoteStore) -> UIColor {
        UIColor(color(for: folderId, in: store))
    }
}

/// Which way the notes are being looked at.
enum IdeasMode: String, CaseIterable, Identifiable {
    case list, board, space
    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: return "List"
        case .board: return "Board"
        case .space: return "Space"
        }
    }
    /// The symbol on the switcher's segment and on its folded circle.
    var symbol: String {
        switch self {
        case .list: return "list.bullet"
        case .board: return "rectangle.3.group"
        case .space: return "cube.transparent"
        }
    }
    /// The switcher segment's accessibility identifier.
    var identifier: String {
        switch self {
        case .list: return "ideasMode-list"
        case .board: return "ideasMode-board"
        case .space: return "ideasMode-space"
        }
    }
}

/// A note to open, by id, so the editor always reads the stored note rather
/// than a copy taken when it was tapped.
struct NoteRef: Identifiable, Hashable {
    let id: UUID
}

/// Turning a note into flashcards: its "Question | Answer" lines become cards
/// the same way a pasted Cards set does, and when there are none, its bullet
/// points become the answers to one card asked by the note's title.
enum NoteCards {
    static func cards(from note: Note) -> [AnkiCard] {
        let lines = note.body.components(separatedBy: .newlines)
        let paired = lines.filter { $0.contains("|") }.joined(separator: "\n")
        let cards = PlainTextImport.parseAnkiQA(paired)
        if !cards.isEmpty { return cards }

        let bullets = lines.compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            for marker in ["- ", "* ", "\u{2022} "] where line.hasPrefix(marker) {
                let text = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                return text.isEmpty ? nil : text
            }
            return nil
        }
        let question = note.title.trimmingCharacters(in: .whitespaces)
        guard !bullets.isEmpty, !question.isEmpty else { return [] }
        // a card holds up to four answer bullets, so a long list becomes a
        // run of cards on the same question
        return stride(from: 0, to: bullets.count, by: 4).map { start in
            let chunk = Array(bullets[start..<min(start + 4, bullets.count)])
            let front = bullets.count > 4 ? "\(question) (\(start / 4 + 1))" : question
            return AnkiCard(type: .qa, front: front, bullets: chunk)
        }
    }
}
