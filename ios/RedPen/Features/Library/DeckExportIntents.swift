import AppIntents
import Foundation

/// Building decks without opening the app.
///
/// The PDF builder has two implementations: tools/deck_pdf.py, for a Mac or a
/// server, and DeckPDF.swift, for the phone. iOS cannot run Python at all -
/// there is no interpreter an app may ship and no shell to run it in - so
/// "automate it on the device" cannot mean running the script there. What it
/// can mean is exposing the Swift builder to Shortcuts, which is the phone's
/// own automation: once these intents exist, a shortcut can build a deck, save
/// it to Files or iCloud Drive, mail it, or print it, and an automation can run
/// that shortcut on a schedule - every Sunday evening, say - with nobody
/// touching the app.
///
/// The intents return the file itself rather than writing it somewhere of their
/// own choosing. Where a deck should end up is a decision for the shortcut that
/// asked for it, and an intent that quietly saved into its own folder would be
/// one more place to go looking.

// MARK: the set to export

struct StudySetEntity: AppEntity {
    let id: UUID
    let name: String
    let kind: String
    let cards: Int

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Study set" }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(kind) \u{00B7} \(cards) cards")
    }

    static var defaultQuery = StudySetQuery()
}

struct StudySetQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [StudySetEntity] {
        StudySetQuery.all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [StudySetEntity] {
        StudySetQuery.all()
    }

    /// The library as the app last saved it.
    ///
    /// A Store of its own, read fresh each time: an intent may run while the
    /// app is not, and it must not show a library from whenever the process
    /// last happened to be alive.
    @MainActor
    static func all() -> [StudySetEntity] {
        Store().library.map {
            StudySetEntity(id: $0.id, name: $0.name, kind: $0.kind.label, cards: $0.itemCount)
        }
    }
}

// MARK: one deck

struct ExportDeckIntent: AppIntent {
    static var title: LocalizedStringResource = "Export deck"
    static var description = IntentDescription(
        "Builds a set as a printable flashcard deck - one question to a page, its answer overleaf - and hands back the file. Cards sets come back as .apkg instead, which keeps their schedule and their occlusion masks.")
    static var openAppWhenRun = false

    @Parameter(title: "Set")
    var set: StudySetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Export \(\.$set) as a deck")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let studySet = Store().library.first(where: { $0.id == set.id }) else {
            throw DeckExportError.gone(set.name)
        }
        return .result(value: try DeckExport.file(for: studySet))
    }
}

// MARK: the whole library, which is the one worth automating

struct ExportEveryDeckIntent: AppIntent {
    static var title: LocalizedStringResource = "Export every deck"
    static var description = IntentDescription(
        "Builds every set in the library and hands back the files, so a shortcut or a weekly automation can keep a folder of decks up to date.")
    static var openAppWhenRun = false

    @Parameter(title: "Only this subject", default: "")
    var subject: String

    static var parameterSummary: some ParameterSummary {
        Summary("Export every deck in \(\.$subject)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let wanted = subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sets = Store().library.filter {
            wanted.isEmpty || $0.subject.lowercased().contains(wanted)
        }
        guard !sets.isEmpty else { throw DeckExportError.nothingToBuild }

        // One failure does not lose the rest: a single set that cannot be built
        // - an empty one, say - should not cost a weekly automation every other
        // deck it was asked for.
        let files = sets.compactMap { try? DeckExport.file(for: $0) }
        guard !files.isEmpty else { throw DeckExportError.nothingToBuild }
        return .result(value: files)
    }
}

// MARK: shared

enum DeckExport {
    /// Whichever form keeps the most of the set, as the library screen decides it.
    @MainActor
    static func file(for set: StudySet) throws -> IntentFile {
        let url: URL?
        if set.kind == .anki {
            url = try? ApkgExporter.export(set)
        } else {
            url = DeckPDF.export(set)
        }
        guard let url else { throw DeckExportError.couldNotBuild(set.name) }
        return IntentFile(fileURL: url, filename: url.lastPathComponent)
    }
}

enum DeckExportError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case gone(String)
    case couldNotBuild(String)
    case nothingToBuild

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .gone(let name):
            return "\(name) is no longer in the library."
        case .couldNotBuild(let name):
            return "\(name) has nothing in it to print."
        case .nothingToBuild:
            return "No sets matched, so there was nothing to build."
        }
    }
}

struct RedPenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ExportDeckIntent(), phrases: [
            "Export a deck from \(.applicationName)",
            "Make a \(.applicationName) deck",
        ], shortTitle: "Export deck", systemImageName: "doc.richtext")

        AppShortcut(intent: ExportEveryDeckIntent(), phrases: [
            "Export every \(.applicationName) deck",
        ], shortTitle: "Export every deck", systemImageName: "square.stack.3d.up")
    }
}
