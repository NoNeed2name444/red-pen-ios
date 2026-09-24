import SwiftUI

/// The idea dump: one place to throw every thought as it comes, then sort it
/// into folders and join it up later.
///
/// Everything you tap sits at the bottom, under the thumb, in one container
/// (IdeasBottomBar): the floating List / Board / Space switcher, which folds
/// away into a small circle, and under it the capture field - always there,
/// whichever way the notes are being looked at, because the moment an idea
/// arrives is not the moment to go looking for where it belongs. Return saves
/// it and leaves the field ready for the next one.
///
/// Three ways to look at the same notes:
/// - List: folders and notes, the way you tidy.
/// - Board: a flat canvas of idea cards, dragged about and joined by hand.
/// - Space: every note and link as a 3D graph, folders as clusters.
///
/// It lives in two places:
/// - embedded, as the Library's Ideas place (`query` given): the Library owns
///   the title, the search field and the backdrop, and its dock sits under
///   this screen, so the lists end with room to scroll clear of it;
/// - standalone, pushed from the Examples hub or the help pages: its own
///   inline title, its own search field in the top drawer, its own backdrop.
///   Never its own NavigationStack and never a leading toolbar item - Back
///   stays the first button in the navigation bar.
struct IdeasView: View {
    @EnvironmentObject private var notes: NoteStore
    @AppStorage("vignette.ideas.mode") private var modeRaw = IdeasMode.list.rawValue
    private let externalQuery: Binding<String>?
    /// How tall the Library's dock is, so the lists can scroll clear of it.
    private let dockClearance: CGFloat
    @State private var ownQuery = ""
    @State private var draft = ""
    /// The folder being browsed in the list, or nil for the top level.
    @State private var folderId: UUID?
    @State private var opening: NoteRef?
    @State private var naming: FolderPrompt?
    /// The note whose Move… was asked for, from its leading swipe.
    @State private var moving: Note?
    @FocusState private var capturing: Bool
    /// `capturing`, held a moment after the caret leaves: Return drops the
    /// focus for an instant before a saved idea puts it back, and the
    /// switcher should not flash open in between.
    @State private var typing = false

    init(query: Binding<String>? = nil, dockClearance: CGFloat = 0) {
        self.externalQuery = query
        self.dockClearance = dockClearance
    }

    /// The naming sheet, for a new folder or a renamed one.
    enum FolderPrompt: Identifiable {
        case new(parent: UUID?)
        case rename(NoteFolder)

        var id: String {
            switch self {
            case .new(let parent): return "new-\(parent?.uuidString ?? "top")"
            case .rename(let folder): return "rename-\(folder.id.uuidString)"
            }
        }
    }

    private var mode: IdeasMode { IdeasMode(rawValue: modeRaw) ?? .list }

    private var embedded: Bool { externalQuery != nil }

    private var queryText: Binding<String> { externalQuery ?? $ownQuery }

    private var query: String { queryText.wrappedValue }

    private var movingShown: Binding<Bool> {
        Binding(get: { moving != nil }, set: { if !$0 { moving = nil } })
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .modifier(IdeasChrome(embedded: embedded, query: $ownQuery))
            .sheet(item: $opening) { ref in
                NoteEditorView(noteID: ref.id)
            }
            .sheet(item: $naming) { prompt in
                nameSheet(prompt)
            }
            .confirmationDialog("Move to", isPresented: movingShown, titleVisibility: .visible,
                                presenting: moving) { note in
                moveChoices(note)
            }
            // the folder being browsed was deleted: back to the top
            .onChange(of: notes.folders) { _, _ in
                if folderId != nil, notes.folder(folderId) == nil { folderId = nil }
            }
            .task(id: capturing) {
                if capturing {
                    typing = true
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                typing = false
            }
    }

    // MARK: the bottom container

    private var bottomBar: some View {
        IdeasBottomBar(modeRaw: $modeRaw, draft: $draft, capturing: $capturing, typing: typing,
                       capture: capture, newPage: newPage,
                       newFolder: { naming = .new(parent: folderId) })
    }

    /// Saves what is in the field as an idea, straight away, and leaves the
    /// field ready for the next one. In the list it goes into the folder on
    /// screen.
    private func capture() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        notes.create(title: text, kind: .idea, folderId: mode == .list ? folderId : nil)
        draft = ""
        capturing = true
    }

    private func newPage() {
        let note = notes.create(title: "Untitled page", kind: .page,
                                folderId: mode == .list ? folderId : nil)
        opening = NoteRef(id: note.id)
    }

    private func openNote(_ id: UUID) {
        opening = NoteRef(id: id)
    }

    // MARK: what is above the bar

    @ViewBuilder
    private var content: some View {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            searchResults
        } else {
            switch mode {
            case .list: listView
            case .board: IdeaBoardView(open: openNote)
            case .space: Graph3DView(open: openNote)
            }
        }
    }

    private var searchResults: some View {
        let found = notes.search(query)
        let heading: String = "\(found.count) found"
        return List {
            if found.isEmpty {
                Text("Nothing matches \u{201C}\(query)\u{201D}.")
                    .foregroundStyle(.secondary)
            } else {
                Section(heading) {
                    ForEach(found) { note in noteRow(note) }
                }
            }
            dockSpacer
        }
        .scrollContentBackground(.hidden)
    }

    /// A clear row as tall as the Library's dock, so the last row can scroll
    /// out from under it. Nothing when standalone.
    @ViewBuilder
    private var dockSpacer: some View {
        if dockClearance > 0 {
            let room: CGFloat = dockClearance + 8
            Color.clear
                .frame(height: room)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityHidden(true)
        }
    }

    private var listView: some View {
        let subfolders = notes.subfolders(of: folderId)
        let here = notes.contents(of: folderId)
        let current = notes.folder(folderId)
        let loose: String = subfolders.isEmpty ? "Ideas" : "Loose ideas"
        let heading: String = current?.name ?? loose
        return List {
            if let current {
                Section {
                    upRow(current)
                } header: {
                    Text(trailText(current))
                        .textCase(nil)
                }
            }
            if !subfolders.isEmpty {
                Section("Folders") {
                    ForEach(subfolders) { folder in folderRow(folder) }
                }
            }
            Section(heading) {
                if here.isEmpty {
                    Text(emptyText(inFolder: current != nil))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(here) { note in noteRow(note) }
                }
            }
            dockSpacer
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if notes.notes.isEmpty && notes.folders.isEmpty {
                firstIdea
            }
        }
    }

    private func trailText(_ folder: NoteFolder) -> String {
        let names: [String] = notes.path(to: folder.id).map(\.name)
        return names.joined(separator: " / ")
    }

    private func emptyText(inFolder: Bool) -> String {
        if inFolder {
            return "Nothing in this folder yet. Ideas dumped while it is open land here."
        }
        return "Type anything below and press return. Sort it later."
    }

    private func upRow(_ current: NoteFolder) -> some View {
        let parentName: String = notes.folder(current.parentId)?.name ?? "All ideas"
        return Button {
            folderId = current.parentId
        } label: {
            Label(parentName, systemImage: "chevron.backward")
                .contentShape(Rectangle())
        }
        .hoverEffect(.highlight)
    }

    private var firstIdea: some View {
        ContentUnavailableView {
            Label("Dump your first idea", systemImage: "lightbulb")
        } description: {
            Text("Anything worth remembering: a mnemonic, a question to look up, a link between two topics. Join them up later on the board or in the space.")
        } actions: {
            // gone once typing, when Send is the one main button
            if !typing {
                Button("Start typing") { capturing = true }
                    .buttonStyle(.glassProminent)
                    .popOut(.hero, in: Capsule())
            }
        }
    }

    private func folderRow(_ folder: NoteFolder) -> some View {
        let count: String = "\(notes.count(in: folder.id))"
        return Button {
            folderId = folder.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .foregroundStyle(NoteTone.color(for: folder.id, in: notes))
                    .frame(width: 24)
                Text(folder.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(count)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .contextMenu {
            Button("Rename", systemImage: "pencil") { naming = .rename(folder) }
            Button("New folder inside", systemImage: "folder.badge.plus") {
                naming = .new(parent: folder.id)
            }
            Button("Delete folder", systemImage: "trash", role: .destructive) {
                notes.deleteFolder(folder.id)
            }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                notes.deleteFolder(folder.id)
            }
        }
    }

    private func noteRow(_ note: Note) -> some View {
        let links: Int = notes.connections(of: note.id).count
        let linked: String = "\(links) linked"
        let preview: String = note.body.split(separator: "\n").first.map(String.init) ?? ""
        let title: String = note.title.isEmpty ? "Untitled" : note.title
        return Button {
            openNote(note.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: note.kind.symbol)
                    .foregroundStyle(NoteTone.color(for: note.folderId, in: notes))
                    .frame(width: 24)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if links > 0 {
                        Label(linked, systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .contextMenu {
            Menu("Move to", systemImage: "folder") {
                moveChoices(note)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                notes.delete(note.id)
            }
        }
        .swipeActions(edge: .leading) {
            Button("Move\u{2026}", systemImage: "folder") { moving = note }
                .tint(.indigo)
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                notes.delete(note.id)
            }
        }
    }

    /// Every folder a note can go into, indented by depth, and "No folder".
    @ViewBuilder
    private func moveChoices(_ note: Note) -> some View {
        Button("No folder") { notes.move(note.id, to: nil) }
        ForEach(Array(notes.folderOutline().enumerated()), id: \.offset) { _, entry in
            Button(Self.indented(entry.folder.name, depth: entry.depth)) {
                notes.move(note.id, to: entry.folder.id)
            }
        }
    }

    static func indented(_ name: String, depth: Int) -> String {
        let indent: String = String(repeating: "\u{2003}", count: depth)
        return indent + name
    }

    @ViewBuilder
    private func nameSheet(_ prompt: FolderPrompt) -> some View {
        switch prompt {
        case .new(let parent):
            NameSheet(title: "New folder", prompt: "Folder name", initial: "", confirm: "Create") { name in
                _ = notes.createFolder(name: name, parentId: parent)
            }
        case .rename(let folder):
            NameSheet(title: "Rename folder", prompt: "Folder name", initial: folder.name, confirm: "Rename") { name in
                notes.renameFolder(folder.id, to: name)
            }
        }
    }
}

/// The standalone screen's own title, search field and backdrop. Embedded in
/// the Library, the Library provides all three, so none are added. Whether
/// it is embedded is fixed for the life of the view, so the branch below
/// never swaps the content out from under itself.
private struct IdeasChrome: ViewModifier {
    let embedded: Bool
    @Binding var query: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .background(LibraryBackdrop())
                .navigationTitle("Ideas")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                            prompt: "Search ideas")
        }
    }
}
