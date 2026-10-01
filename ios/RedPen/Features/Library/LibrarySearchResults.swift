import SwiftUI

/// The library search's results: the scopes, then the questions, cards,
/// notes and lecture pages that matched, each with the matched phrase marked
/// and a tap that opens it where it lives. The sets that matched are listed
/// by the library's own rows above these (LibraryView.setsSections).
extension LibraryView {

    /// All · Questions · Cards · Notes · Lectures.
    var searchScopeSection: some View {
        Section {
            Picker("Search in", selection: $search.scope) {
                ForEach(LibrarySearch.Scope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("searchScope")
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// The items that matched, capped at fifty, and a way to study them.
    @ViewBuilder
    var searchItemsSection: some View {
        let hits: [LibrarySearch.Hit] = search.results.items
        if !hits.isEmpty {
            Section {
                ForEach(hits) { hit in
                    searchRow(hit)
                }
            } header: {
                CategoryHeading(title: itemsHeading)
            } footer: {
                if search.results.more {
                    Text("The first \(LibrarySearch.itemLimit). Add a word to narrow it.")
                }
            }
        } else if search.scope != .all && !search.busy {
            Section {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
        }
        if !hits.isEmpty && search.scope != .notes && search.scope != .lectures {
            Section {
                buildSessionButton(from: query)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var itemsHeading: String {
        switch search.scope {
        case .all: return "Questions & cards"
        case .questions: return "Questions"
        case .cards: return "Cards"
        case .notes: return "Notes"
        case .lectures: return "Lectures"
        }
    }

    /// "Build a session": a filtered deck from this search, or from filters.
    func buildSessionButton(from text: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button { sessionText = text; buildingSession = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build a session")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Missed this week, a subject, a tag, what\u{2019}s due")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.popTile)
        .accessibilityIdentifier("buildSession")
    }

    private func searchRow(_ hit: LibrarySearch.Hit) -> some View {
        Button { openHit(hit) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: hit.kind.symbol)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.marked(hit))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Text(Self.whereFound(hit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frostedListRow()
        .accessibilityHint("Opens it where it is")
    }

    /// The snippet with the match in bold on a soft highlight.
    static func marked(_ hit: LibrarySearch.Hit) -> AttributedString {
        let chars: [Character] = Array(hit.snippet)
        let lo: Int = min(max(0, hit.range.lowerBound), chars.count)
        let hi: Int = min(max(lo, hit.range.upperBound), chars.count)
        var out = AttributedString(String(chars[0..<lo]))
        var match = AttributedString(String(chars[lo..<hi]))
        match.inlinePresentationIntent = .stronglyEmphasized
        match.backgroundColor = Color.yellow.opacity(0.35)
        out += match
        out += AttributedString(String(chars[hi...]))
        return out
    }

    /// "Card · Heart failure", "Lecture · Nephrotic lecture, p. 2".
    static func whereFound(_ hit: LibrarySearch.Hit) -> String {
        let dot: String = " \u{00B7} "
        switch hit.kind {
        case .lecture:
            let page: String = hit.page.map { ", p. \($0)" } ?? ""
            return hit.kind.label + dot + hit.sourceName + page
        case .note:
            return hit.kind.label + dot + "Ideas"
        default:
            return hit.kind.label + dot + hit.setName
        }
    }

    /// A result opened where it lives: a question at its place in its set,
    /// a card on its own with its deck a tap away, a note in its editor, a
    /// lecture at the page.
    func openHit(_ hit: LibrarySearch.Hit) {
        switch hit.kind {
        case .set:
            if let set = librarySet(hit.setID) { opened.append(set) }
        case .question:
            guard let set = librarySet(hit.setID), let id = hit.itemID else { return }
            quickQuiz = LibrarySearch.opening(set, atQuestion: id) ?? set
        case .card:
            guard let set = librarySet(hit.setID) else { return }
            if let card = set.cards.first(where: { $0.id == hit.itemID }) {
                foundCard = FoundCard(set: set, card: card)
            } else {
                opened.append(set)
            }
        case .note:
            if let id = hit.itemID { foundNote = FoundNote(id: id) }
        case .lecture:
            guard let set = librarySet(hit.setID) else { return }
            guard let source = set.sources.first(where: { $0.id == hit.itemID }) else { return }
            reading = SourceOpening(source: source, page: hit.page ?? 1)
        }
    }

    private func librarySet(_ id: UUID?) -> StudySet? {
        guard let id else { return nil }
        return store.library.first { $0.id == id }
    }

    /// A custom session ready: a quiz goes where the library's other quick
    /// quizzes go; a deck opens in the review screen.
    func startSession(_ set: StudySet, _ mode: CustomSession.Mode) {
        if mode == .review { sessionDeck = set } else { quickQuiz = set }
    }
}

/// A card a search found, to open on its own.
struct FoundCard: Identifiable {
    let set: StudySet
    let card: AnkiCard
    var id: UUID { card.id }
}

/// A note a search found, for its editor.
struct FoundNote: Identifiable {
    let id: UUID
}

/// One card, found by a search: its front, the answer on a tap, and its deck
/// a tap further.
struct FoundCardSheet: View {
    let found: FoundCard
    let openDeck: (StudySet) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    face
                    if !revealed {
                        Button { revealed = true } label: {
                            Text("Show answer").font(.headline).frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("foundCardReveal")
                    }
                    Button {
                        dismiss()
                        openDeck(found.set)
                    } label: {
                        Label("Open \u{201C}\(found.set.name)\u{201D}", systemImage: "rectangle.stack")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("foundCardOpenDeck")
                }
                .padding(20)
            }
            .background(LibraryBackdrop())
            .navigationTitle("Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            Text(front)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if revealed {
                Divider()
                ForEach(Array(answers.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.body)
                }
                if !found.card.why.isEmpty {
                    Text(found.card.why)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: shape)
        .popOut(.raised, in: shape)
    }

    private var front: String {
        let card: AnkiCard = found.card
        if card.type == .cloze { return QuizFromCards.stem(of: card) }
        return card.displayFront
    }

    private var answers: [String] {
        let card: AnkiCard = found.card
        if card.type == .cloze { return [LibrarySearch.clozeBare(card.clozeText)] }
        return card.bullets
    }
}
