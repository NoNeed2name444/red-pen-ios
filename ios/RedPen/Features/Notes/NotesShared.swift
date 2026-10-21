import SwiftUI
import UIKit

/// The colour each top-level folder is known by, on the board and in the
/// space alike: there to tell clusters apart at a glance, not to decorate.
///
/// Seven of the owner's 2026-10-21 palette (docs/design/palette-2026-10-21.md),
/// in the stored order the folders are matched by index: the 3D map's space
/// draws its clusters in the colours themselves; a folder's glyph on a
/// card or a row, which must read 3:1 on the page, takes a shade of the
/// same hue where the colour itself does not. Vital Coral is left out, so
/// a folder never reads as a wrong answer.
enum NoteTone {
    /// (the owner's colour, the glyph's by day, the glyph's at night), 0xRRGGBB
    private static let palette: [(fill: UInt32, light: UInt32, dark: UInt32)] = [
        (0x14B8A6, 0x3B8B80, 0x14B8A6),  // Pulse Teal (was sea green)
        (0x6366F1, 0x6366F1, 0x737CB3),  // Electric Indigo (was slate blue)
        (0xFF9F7A, 0xBF6642, 0xFF9F7A),  // Peach Glow (was sand)
        (0xA78BFA, 0x886BD4, 0xA78BFA),  // Soft Lilac (was heather)
        (0xA3E635, 0x708558, 0xA3E635),  // Lime Zest (was sage)
        (0xF472B6, 0xCE4F93, 0xF472B6),  // Bubblegum Pink (was clay)
        (0x3B82F6, 0x367AEC, 0x3B82F6),  // Care Blue (was sky)
    ]

    private static func ui(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static let glyphs: [Color] = palette.map { tone in
        Color(uiColor: UIColor { traits in ui(traits.userInterfaceStyle == .dark ? tone.dark : tone.light) })
    }

    @MainActor
    private static func index(for folderId: UUID?, in store: NoteStore) -> Int? {
        guard let root = store.rootFolder(of: folderId),
              let index = store.subfolders(of: nil).firstIndex(where: { $0.id == root })
        else { return nil }
        return index % palette.count
    }

    /// Loose notes are plain grey; a note in a folder takes the colour of
    /// the top-level folder it sits in (its glyph's shade, light or dark).
    @MainActor
    static func color(for folderId: UUID?, in store: NoteStore) -> Color {
        guard let k = index(for: folderId, in: store) else { return Color.gray }
        return glyphs[k]
    }

    /// The folder's colour itself, for the space's clusters.
    @MainActor
    static func uiColor(for folderId: UUID?, in store: NoteStore) -> UIColor {
        guard let k = index(for: folderId, in: store) else { return UIColor(Color.gray) }
        return ui(palette[k].fill)
    }

    /// The palette's colour at `index` (wrapping), for a folder the space
    /// treats as top level although the store does not (GraphUniverseScene).
    static func uiColor(at index: Int) -> UIColor {
        let count: Int = palette.count
        let k: Int = ((index % count) + count) % count
        return ui(palette[k].fill)
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
