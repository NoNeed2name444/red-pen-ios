import SwiftUI

/// The idea dump: one place to throw every thought as it comes, then sort it
/// into folders and join it up later.
///
/// The capture bar is always at the top, whichever way the notes are being
/// looked at, because the moment an idea arrives is not the moment to go
/// looking for where it belongs. Return saves it and leaves the bar ready for
/// the next one.
///
/// Three ways to look at the same notes:
/// - List: folders and notes, the way you tidy.
/// - Board: a flat canvas of idea cards, dragged about and joined by hand.
/// - Space: every note and link as a 3D graph, folders as clusters.
struct IdeasView: View {
    @EnvironmentObject private var notes: NoteStore
    @AppStorage("vignette.ideas.mode") private var modeRaw = IdeasMode.list.rawValue
    @State private var query = ""
    @State private var draft = ""
    /// The folder being browsed in the list, or nil for the top level.
    @State private var folderId: UUID?
    @State private var opening: NoteRef?
    @State private var naming: FolderPrompt?
    @FocusState private var capturing: Bool

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

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LibraryBackdrop())
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .navigationTitle("Ideas")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search ideas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New idea", systemImage: "lightbulb") { capturing = true }
                        Button("New page", systemImage: "doc.badge.plus") { newPage() }
                        Button("New folder", systemImage: "folder.badge.plus") {
                            naming = .new(parent: folderId)
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
            }
            .sheet(item: $opening) { ref in
                NoteEditorView(noteID: ref.id)
            }
            .sheet(item: $naming) { prompt in
                nameSheet(prompt)
            }
            // the folder being browsed was deleted: back to the top
            .onChange(of: notes.folders) { _, _ in
                if folderId != nil, notes.folder(folderId) == nil { folderId = nil }
            }
    }

    // MARK: the capture bar and the view switch

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(.secondary)
                TextField("Dump an idea\u{2026}", text: $draft)
                    .focused($capturing)
                    .submitLabel(.done)
                    .onSubmit(capture)
                    .accessibilityIdentifier("idea-capture")
                if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: capture) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Save idea")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)

            Picker("View", selection: $modeRaw) {
                ForEach(IdeasMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Saves what is in the bar as an idea, straight away, and leaves the bar
    /// ready for the next one. In the list it goes into the folder on screen.
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

    // MARK: what is under the bar

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
        return List {
            if found.isEmpty {
                Text("Nothing matches \u{201C}\(query)\u{201D}.")
                    .foregroundStyle(.secondary)
            } else {
                Section("\(found.count) found") {
                    ForEach(found) { note in noteRow(note) }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var listView: some View {
        let subfolders = notes.subfolders(of: folderId)
        let here = notes.contents(of: folderId)
        let current = notes.folder(folderId)
        return List {
            if let current {
                Section {
                    Button {
                        folderId = current.parentId
                    } label: {
                        Label(notes.folder(current.parentId)?.name ?? "All ideas",
                              systemImage: "chevron.backward")
                    }
                } header: {
                    Text(notes.path(to: current.id).map(\.name).joined(separator: " / "))
                        .textCase(nil)
                }
            }
            if !subfolders.isEmpty {
                Section("Folders") {
                    ForEach(subfolders) { folder in folderRow(folder) }
                }
            }
            Section(current?.name ?? (subfolders.isEmpty ? "Ideas" : "Loose ideas")) {
                if here.isEmpty {
                    Text(current == nil
                         ? "Type anything above and press return. Sort it later."
                         : "Nothing in this folder yet. Ideas dumped while it is open land here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(here) { note in noteRow(note) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if notes.notes.isEmpty && notes.folders.isEmpty {
                ContentUnavailableView {
                    Label("Dump your first idea", systemImage: "lightbulb")
                } description: {
                    Text("Anything worth remembering: a mnemonic, a question to look up, a link between two topics. Join them up later on the board or in the space.")
                } actions: {
                    Button("Start typing") { capturing = true }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private func folderRow(_ folder: NoteFolder) -> some View {
        Button {
            folderId = folder.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .foregroundStyle(NoteTone.color(for: folder.id, in: notes))
                    .frame(width: 24)
                Text(folder.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text("\(notes.count(in: folder.id))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        let links = notes.connections(of: note.id).count
        let preview = note.body.split(separator: "\n").first.map(String.init) ?? ""
        return Button {
            openNote(note.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: note.kind.symbol)
                    .foregroundStyle(NoteTone.color(for: note.folderId, in: notes))
                    .frame(width: 24)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if links > 0 {
                        Label("\(links) linked", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("Move to", systemImage: "folder") {
                Button("No folder") { notes.move(note.id, to: nil) }
                ForEach(Array(notes.folderOutline().enumerated()), id: \.offset) { _, entry in
                    Button(String(repeating: "\u{2003}", count: entry.depth) + entry.folder.name) {
                        notes.move(note.id, to: entry.folder.id)
                    }
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                notes.delete(note.id)
            }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                notes.delete(note.id)
            }
        }
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
