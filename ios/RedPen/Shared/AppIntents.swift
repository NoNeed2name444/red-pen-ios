import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers
import Foundation

// MARK: - Siri, Shortcuts and Spotlight
//
// "Review my due cards", "Quiz me on cardiology", "Open Renal week 3": the
// phrases are listed in RedPenShortcuts (DeckExportIntents.swift, the app's
// one AppShortcutsProvider), and iOS 26 shows the same App Shortcuts as
// Spotlight actions. Every set is in Spotlight as a StudySetEntity
// (IndexedEntity), and tapping one runs OpenSetIntent.
//
// The intents only say where to go; AppRouter (AppIntentsRouting.swift) does
// the going, once the library is on screen. None of them changes data.
//
// Compiles in both builds. The Playgrounds package has no App Intents
// metadata step, so there the phrases do not reach Siri, but Spotlight
// indexing and the in-app routes still work.

// MARK: the set, in Spotlight

extension StudySetEntity: IndexedEntity {
    /// What Spotlight shows and matches: the name, the mode and the size.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = name
        attributes.displayName = name
        attributes.contentDescription = kind + " \u{00B7} \(cards) items"
        attributes.keywords = [kind, "Stethoscore"]
        return attributes
    }

    init(_ set: StudySet) {
        self.init(id: set.id, name: set.name, kind: set.kind.label, cards: set.itemCount)
    }
}

extension StudySetQuery: EntityStringQuery {
    /// "Open cardio" - by name, subject or tag, the best matches first.
    @MainActor
    func entities(matching string: String) async throws -> [StudySetEntity] {
        let library: [StudySet] = await IntentLibrary.sets()
        var scored: [(score: Int, set: StudySet)] = []
        for set in library {
            let names: [String] = [set.name, set.subject] + (set.tags ?? [])
            let score: Int = SubjectMatch.score(query: string, names: names)
            if score > 0 { scored.append((score, set)) }
        }
        scored.sort { a, b in a.score != b.score ? a.score > b.score : a.set.name < b.set.name }
        return scored.prefix(30).map { StudySetEntity($0.set) }
    }
}

/// The library for an intent: the running app's when it is on screen, or as
/// last saved when Siri woke the app in the background.
@MainActor
enum IntentLibrary {
    /// The saved library, read once for a run with no library on screen -
    /// a parameter picker asks on every keystroke. Kept briefly (so a
    /// later run does not show a library from whenever the process was
    /// last alive) and forgotten as soon as the app attaches its live Store.
    private static var saved: [StudySet]?
    private static var savedAt: Date = .distantPast
    private static let keepSeconds: TimeInterval = 30

    static func sets() async -> [StudySet] {
        if let live = AppRouter.shared.library {
            saved = nil
            return live
        }
        if let saved, Date().timeIntervalSince(savedAt) < keepSeconds { return saved }
        // decoded off the main thread, and never by building a second Store
        let read: [StudySet] = await Task.detached(priority: .userInitiated) { () -> [StudySet] in
            Store.savedLibrary()
        }.value
        saved = read
        savedAt = Date()
        return read
    }

    /// The live library is here: the saved copy is out of date.
    static func forget() {
        saved = nil
    }
}

// MARK: open a set

/// Spotlight's tap on a set, "Open Renal week 3 in Stethoscore", and a
/// Shortcuts action.
struct OpenSetIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open set"
    static var description = IntentDescription("Opens one of your sets in Stethoscore.")

    @Parameter(title: "Set")
    var target: StudySetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.openSet(target.id))
        return .result()
    }
}

// MARK: quiz me on a subject

/// A subject in the library, for "Quiz me on cardiology".
struct SubjectEntity: AppEntity {
    let id: String

    var name: String { id }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Subject" }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }

    static var defaultQuery = SubjectQuery()
}

struct SubjectQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [SubjectEntity] {
        identifiers.map { SubjectEntity(id: $0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SubjectEntity] {
        await SubjectQuery.subjects().prefix(40).map { SubjectEntity(id: $0) }
    }

    /// Whatever was said is a subject: a spoken "renal" is matched against
    /// the library when the quiz is built, not refused here.
    @MainActor
    func entities(matching string: String) async throws -> [SubjectEntity] {
        let said: String = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let subjects: [String] = await SubjectQuery.subjects()
        let known: [String] = subjects.filter { SubjectMatch.matches(said, $0) }
        if said.isEmpty { return known.map { SubjectEntity(id: $0) } }
        let exact: Bool = known.contains { SubjectMatch.canonical($0) == SubjectMatch.canonical(said) }
        let spoken: [String] = exact ? [] : [said]
        return (known + spoken).map { SubjectEntity(id: $0) }
    }

    /// The library's subjects, busiest first.
    @MainActor
    static func subjects() async -> [String] {
        let library: [StudySet] = await IntentLibrary.sets()
        let studied: [StudySet] = library.filter { $0.kind == .mcq || $0.kind == .anki }
        return SubjectMatch.distinctSubjects(studied.map(\.subject))
    }
}

/// "Quiz me on cardiology": up to twenty questions from the sets on that
/// subject, cards turned into questions where there are no questions.
struct QuizMeIntent: AppIntent {
    static var title: LocalizedStringResource = "Quiz me on a subject"
    static var description = IntentDescription("Builds a short quiz from your sets on one subject and opens it.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Subject")
    var subject: SubjectEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Quiz me on \(\.$subject)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.quiz(subject: subject.name))
        return .result()
    }
}

// MARK: - Keeping Spotlight up to date

/// Puts every set in Spotlight, and takes out the ones that went.
///
/// Called (debounced) when the library changes. Only sets whose name, mode
/// or size changed are sent again, in batches of 500, at background
/// priority, off the main thread.
@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    /// Bool, default true: Settings > "Show sets in Spotlight".
    static let key = "platform.spotlight"

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    /// What was last sent, per set: "name|kind|count".
    private var indexed: [UUID: String] = SpotlightIndexer.loadIndexed()
    private var running: Task<Void, Never>?
    private var subjects: [String] = []

    func update(_ library: [StudySet]) {
        guard Self.enabled else {
            if !indexed.isEmpty { clear() }
            return
        }
        var now: [UUID: String] = [:]
        var changed: [StudySetEntity] = []
        for set in library {
            let entity = StudySetEntity(set)
            let signature: String = entity.name + "|" + entity.kind + "|" + String(entity.cards)
            now[set.id] = signature
            if indexed[set.id] != signature { changed.append(entity) }
        }
        let gone: [UUID] = indexed.keys.filter { now[$0] == nil }
        refreshPhrases(library)
        guard !changed.isEmpty || !gone.isEmpty else { return }
        indexed = now
        let snapshot: [UUID: String] = now
        running?.cancel()
        running = Task.detached(priority: .background) {
            await SpotlightIndexer.send(changed, removing: gone)
            SpotlightIndexer.saveIndexed(snapshot)
        }
    }

    /// Everything out of Spotlight (the toggle turned off).
    func clear() {
        indexed = [:]
        running?.cancel()
        running = Task.detached(priority: .background) {
            try? await CSSearchableIndex.default().deleteAllSearchableItems()
            SpotlightIndexer.saveIndexed([:])
        }
    }

    /// The subjects Siri can hear in "Quiz me on ...", told to the system
    /// only when they change.
    private func refreshPhrases(_ library: [StudySet]) {
        let studied: [StudySet] = library.filter { $0.kind == .mcq || $0.kind == .anki }
        let now: [String] = SubjectMatch.distinctSubjects(studied.map(\.subject))
        guard now != subjects else { return }
        subjects = now
        RedPenShortcuts.updateAppShortcutParameters()
    }

    nonisolated static func send(_ entities: [StudySetEntity], removing gone: [UUID]) async {
        let index = CSSearchableIndex.default()
        var start: Int = 0
        while start < entities.count {
            if Task.isCancelled { return }
            let end: Int = min(start + 500, entities.count)
            let batch: [StudySetEntity] = Array(entities[start..<end])
            try? await index.indexAppEntities(batch)
            start = end
        }
        if !gone.isEmpty {
            try? await index.deleteAppEntities(identifiedBy: gone, ofType: StudySetEntity.self)
        }
    }

    // MARK: what was sent, across launches

    nonisolated private static var fileURL: URL? {
        let caches: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return caches?.appendingPathComponent("spotlight-indexed.json")
    }

    nonisolated private static func loadIndexed() -> [UUID: String] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [:] }
        let raw: [String: String] = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        var out: [UUID: String] = [:]
        for (key, value) in raw {
            if let id = UUID(uuidString: key) { out[id] = value }
        }
        return out
    }

    nonisolated private static func saveIndexed(_ indexed: [UUID: String]) {
        guard let url = fileURL else { return }
        var raw: [String: String] = [:]
        for (key, value) in indexed { raw[key.uuidString] = value }
        guard let data = try? JSONEncoder().encode(raw) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
