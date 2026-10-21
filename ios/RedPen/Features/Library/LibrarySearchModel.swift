import Combine
import Foundation

/// The library search's moving parts: the index, rebuilt off the main thread
/// when the library or the notes change, and the search itself, run 250 ms
/// after the last keystroke, also off the main thread.
///
/// The index is only built once something is typed, and only rebuilt while a
/// search is showing, so a student who never searches never pays for it.
@MainActor
final class LibrarySearchModel: ObservableObject {
    /// All, Questions, Cards, Notes or Lectures. Changing it searches again
    /// at once.
    @Published var scope: LibrarySearch.Scope = .all {
        didSet { if oldValue != scope { schedule(after: .zero) } }
    }
    @Published private(set) var results = LibrarySearch.Results()
    /// True from a keystroke until its results arrive.
    @Published private(set) var busy = false

    static let debounce: Duration = .milliseconds(250)

    private var query: String = ""
    private var sets: [StudySet] = []
    private var notes: [LibrarySearch.NoteText] = []
    private var index: LibrarySearch.Index?
    /// Moves on every change to what is indexed, so a build that finishes
    /// after the library changed again is not kept as current.
    private var generation: Int = 0
    private var builtGeneration: Int = -1
    private var pending: Task<Void, Never>?

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The search field changed.
    func update(query text: String) {
        guard text != query else { return }
        query = text
        schedule(after: Self.debounce)
    }

    /// The library changed. Cheap: it only notes the change, unless a search
    /// is on screen, when the results are brought up to date.
    func libraryChanged(_ library: [StudySet]) {
        sets = library
        generation &+= 1
        if isSearching { schedule(after: Self.debounce) }
    }

    func notesChanged(_ all: [Note]) {
        notes = all.map { note in
            LibrarySearch.NoteText(id: note.id, title: note.title, body: note.body, tags: note.tags)
        }
        generation &+= 1
        if isSearching { schedule(after: Self.debounce) }
    }

    private func schedule(after delay: Duration) {
        pending?.cancel()
        let phrase: String = query
        let chosen: LibrarySearch.Scope = scope
        guard !phrase.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = LibrarySearch.Results()
            busy = false
            return
        }
        busy = true
        pending = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            let index: LibrarySearch.Index = await self.currentIndex()
            guard !Task.isCancelled else { return }
            let found: LibrarySearch.Results = await Task.detached(priority: .userInitiated) {
                LibrarySearch.search(phrase, in: index, scope: chosen)
            }.value
            guard !Task.isCancelled else { return }
            self.results = found
            self.busy = false
        }
    }

    /// The index for the library as it is now, built if it is out of date.
    private func currentIndex() async -> LibrarySearch.Index {
        if let index, builtGeneration == generation { return index }
        let at: Int = generation
        let library: [StudySet] = sets
        let written: [LibrarySearch.NoteText] = notes
        let built: LibrarySearch.Index = await Task.detached(priority: .userInitiated) {
            LibrarySearch.build(sets: library, notes: written)
        }.value
        // a change while it was building: still the best there is for this
        // search, but the next one builds again
        index = built
        builtGeneration = at
        return built
    }
}
