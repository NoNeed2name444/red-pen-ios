import SwiftUI

/// Save to Ideas, the library's end of it: the idea store handed to the
/// study screens' buttons once the library is on screen, and a saved note's
/// way back - its chip, or the link at the end of its text - opening the
/// question, card, case, station or lecture page where it lives, the way a
/// search result is opened (openHit).
extension LibraryView {
    /// Once the library is up: the study screens can save from now on. A
    /// screenshot run never can, so its screens look as they always have.
    func attachIdeaSaver() {
        guard PreviewLaunch.screen == nil else { return }
        IdeaSaver.shared.attach(noteStore)
    }

    /// The item a saved note came from, opened in its set: out of Ideas and
    /// any note left open first, then as a search result would be.
    func openSaved(_ source: NoteSource) {
        guard let set = IdeaSaver.set(for: source, in: store.library) else {
            let noun: String = source.kind.noun
            AppRouter.shared.notice = "That \(noun) is no longer in your library."
            return
        }
        if source.kind == .lecture, !set.sources.contains(where: { $0.id == source.itemID }) {
            AppRouter.shared.notice = "That lecture is no longer in your library."
            return
        }
        // back to the library itself: whatever was pushed or shown over it
        // (a link can arrive from anywhere) is put away first
        closeOpenPlaces()
        if inIdeas {
            withAnimation(.snappy(duration: 0.3)) { inIdeas = false }
            category = StudyCategory(kind: set.kind)
        }
        let hit: LibrarySearch.Hit = Self.hit(for: source, in: set)
        // after the note's sheet has gone and the pop has landed
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            openHit(hit)
        }
    }

    private func closeOpenPlaces() {
        foundNote = nil
        foundCard = nil
        reading = nil
        quickQuiz = nil
        featureQuiz = nil
        featurePage = nil
        sessionDeck = nil
        showingDue = false
        if !opened.isEmpty { opened = [] }
        support = nil
    }

    /// The search result that opens the same place.
    private static func hit(for source: NoteSource, in set: StudySet) -> LibrarySearch.Hit {
        let kind: LibrarySearch.Kind
        switch source.kind {
        case .question: kind = .question
        case .card: kind = .card
        case .lecture: kind = .lecture
        case .caseCard, .osce: kind = .set
        }
        let page: Int? = source.kind == .lecture ? (source.page ?? 1) : nil
        return LibrarySearch.Hit(kind: kind, setID: set.id, itemID: source.itemID, page: page,
                                 snippet: "", range: 0..<0, setName: set.name)
    }
}

extension View {
    /// Links to the app's own places tapped inside the library - the one at
    /// the end of a note saved to Ideas - go straight to the router rather
    /// than out through the system and back.
    func appLinksInPlace() -> some View {
        environment(\.openURL, OpenURLAction { url in
            let routed: Bool = MainActor.assumeIsolated { AppRouter.shared.open(url: url) }
            return routed ? .handled : .systemAction
        })
    }
}
