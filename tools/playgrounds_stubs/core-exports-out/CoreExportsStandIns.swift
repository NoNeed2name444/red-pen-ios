import SwiftUI

// Only in the Swift Playgrounds core builds that leave imports and exports out
// (core, core1): stand-ins for step 2 of the add-back order
// (tools/playgrounds_stubs/README.md) - Anki packages, picture cards from
// photos, occlusion covers and the figure finder - and the core shell's empty
// ways in. core2 has the real ones and core-exports-in/ instead of this file.

/// What this build leaves out of step 2, for the note under the library.
enum CoreExportsPart {
    static let missing: [String] = ["Anki import and export", "PDF export", "backups", "picture cards from photos"]
}

/// The library's picture-card row: none here.
struct CoreLibraryExports: View {
    var body: some View { EmptyView() }
}

/// Settings' library and data section (backups): none here.
struct CoreDataSection: View {
    var body: some View { EmptyView() }
}

extension View {
    /// A set row's export menu: none here.
    func coreRowActions(_ set: StudySet) -> some View { self }
}

struct PictureFromPhotoView: View {
    let initialFiles: [URL]

    init(initialFiles: [URL] = []) {
        self.initialFiles = initialFiles
    }

    var body: some View { NotInThisBuild(feature: "Picture cards from photos") }
}

/// Where the covers of a picture card go (Shared/OcclusionFilter.swift).
enum OcclusionCovers {
    static let targetRGB: (red: Double, green: Double, blue: Double) = (0.93, 0.45, 0.09)
    static let otherRGB: (red: Double, green: Double, blue: Double) = (0.56, 0.58, 0.62)
    static let drawPadding: CGFloat = 0
    static let drawMinimum: CGFloat = 6

    static func others(for card: AnkiCard, in deck: [AnkiCard]) -> [OcclusionBox] {
        var found: [OcclusionBox] = card.siblings
        if found.isEmpty, let index = card.imageIndex {
            for other in deck where other.id != card.id && other.type == .occlusion
                && other.imageIndex == index {
                if let box = other.occlusion { found.append(box) }
            }
        }
        var kept: [OcclusionBox] = []
        for box in found {
            if let target = card.occlusion, overlapShare(box, target) > 0.5 { continue }
            if kept.contains(box) { continue }
            kept.append(box)
        }
        return kept
    }

    static func overlapShare(_ a: OcclusionBox, _ b: OcclusionBox) -> Double {
        let w = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
        let h = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
        guard w > 0, h > 0 else { return 0 }
        let smaller = min(a.w * a.h, b.w * b.h)
        return smaller > 0 ? (w * h) / smaller : 0
    }

    static func rect(for box: OcclusionBox, in frame: CGRect, padding: CGFloat,
                     minimum: CGFloat, pixelScale: CGFloat = 1) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return .zero }
        var r = CGRect(x: frame.minX + CGFloat(box.x) * frame.width,
                       y: frame.minY + CGFloat(box.y) * frame.height,
                       width: CGFloat(box.w) * frame.width,
                       height: CGFloat(box.h) * frame.height)
        r = r.insetBy(dx: -padding, dy: -padding)
        if r.width < minimum { r = r.insetBy(dx: -(minimum - r.width) / 2, dy: 0) }
        if r.height < minimum { r = r.insetBy(dx: 0, dy: -(minimum - r.height) / 2) }
        r = r.intersection(frame)
        guard !r.isNull, r.width > 0, r.height > 0 else { return .zero }
        let s = max(pixelScale, 1)
        let minX = (r.minX * s).rounded(.down) / s
        let minY = (r.minY * s).rounded(.down) / s
        let maxX = (r.maxX * s).rounded(.up) / s
        let maxY = (r.maxY * s).rounded(.up) / s
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Figures in a lecture's pages (Shared/FigureFinder.swift): none are found
/// in this build, so imports carry their text and pictures only.
enum FigureFinder {
    struct Found {
        var figure: OcclusionBox
        var cards: [AnkiCard]
    }

    static func read(_ image: CGImage, imageIndex: Int,
                     question: String = "What is labelled here?",
                     pageBands: Bool = true) -> Found? {
        nil
    }
}

// MARK: - Anki packages (Shared/ApkgImport.swift): not read in this build

struct AnkiProgress: Equatable {
    var due: Date
    var intervalDays: Double
    var reviews: Int
    var lapses: Int
    var suspended: Bool

    func lastReviewed(now: Date = Date()) -> Date {
        min(due.addingTimeInterval(-intervalDays * 86_400), now)
    }
}

enum AnkiNoteText {
    struct Deck {
        var progress: [UUID: AnkiProgress] = [:]
    }

    struct PlannedSet {
        var name: String
        var folder: String?
        var deck: Deck = Deck()
    }

    static func studySet(_ planned: PlannedSet, subject: String, folderId: UUID?, now: Date = Date(),
                         picture: (String) -> String?) -> StudySet {
        var set = StudySet(name: planned.name, subject: subject, kind: .anki)
        set.folderId = folderId
        set.createdAt = now
        return set
    }
}

enum ApkgImport {
    struct Package {
        var sets: [AnkiNoteText.PlannedSet] = []
        var media: [String: URL] = [:]
        var format = "Anki package"
        var noteCount = 0
        var ankiCardCount = 0
        var madeCards = 0
        var skippedNotes = 0
        var pictureCount = 0
        var picturesLeftOut = 0
        var occlusionCardsLeftOut = 0
        var tagCount = 0
        var deckCount = 0

        func discard() {}
    }

    enum Failure: LocalizedError {
        case empty
        case notInThisBuild

        var errorDescription: String? {
            switch self {
            case .empty: return "There were no cards in that deck."
            case .notInThisBuild: return "Anki decks open in the full app; this build leaves the Anki reader out."
            }
        }
    }

    static func read(_ url: URL) throws -> Package {
        throw Failure.notInThisBuild
    }
}
