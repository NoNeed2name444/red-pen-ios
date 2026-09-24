import SwiftUI

/// One note, to write in and to join up with the rest.
///
/// Writing `[[Title]]` in the body links to the note of that title, as in
/// Obsidian, and the links appear underneath as they are typed. "Link to…"
/// joins two notes by hand without writing anything. Tapping a linked note
/// opens it in place, with Back to return, so a chain of ideas can be followed
/// without closing anything.
///
/// Changes save themselves a moment after typing stops, and again on close.
struct NoteEditorView: View {
    @EnvironmentObject private var notes: NoteStore
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    /// The note on screen. Following a link swaps it for another, and the
    /// notes left behind are kept in `trail` for Back.
    @State private var current: UUID
    @State private var trail: [UUID] = []
    @State private var title = ""
    @State private var text = ""
    @State private var kind: NoteKind = .idea
    @State private var folderId: UUID?
    @State private var loaded = false
    /// Read the note as Markdown instead of editing it; remembered.
    @AppStorage("notesReadAsMarkdown") private var reading = false
    @State private var linking = false
    @State private var confirmingDelete = false
    /// What "Turn into cards" did, to say so.
    @State private var cardsMessage: String?

    init(noteID: UUID) {
        _current = State(initialValue: noteID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, axis: .vertical)
                        .font(.title3.weight(.semibold))
                    Picker("Kind", selection: $kind) {
                        ForEach(NoteKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    Picker("Folder", selection: $folderId) {
                        Text("No folder").tag(UUID?.none)
                        ForEach(Array(notes.folderOutline().enumerated()), id: \.offset) { _, entry in
                            Text(String(repeating: "\u{2003}", count: entry.depth) + entry.folder.name)
                                .tag(Optional(entry.folder.id))
                        }
                    }
                }

                Section {
                    Picker("View", selection: $reading) {
                        Label("Write", systemImage: "pencil").tag(false)
                        Label("Read", systemImage: "doc.richtext").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("noteMarkdownToggle")
                    if reading {
                        NoteMarkdownView(text: text) { name in openNote(named: name) }
                            .frame(minHeight: kind == .page ? 260 : 140, alignment: .topLeading)
                    } else {
                        TextEditor(text: $text)
                            .frame(minHeight: kind == .page ? 260 : 140)
                            .accessibilityLabel("Note")
                    }
                    if !reading && !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions) { note in
                                    Button(note.title) { complete(with: note.title) }
                                        .buttonStyle(.bordered)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Type [[ and a note\u{2019}s title to link it, like [[Heart failure]]. Markdown works too: # headings, - bullets, **bold**, *italic*; switch to Read to see it laid out. Lines written \u{201C}Question | Answer\u{201D}, or bullet points, can be turned into cards.")
                }

                Section("Linked notes") {
                    ForEach(outgoing, id: \.self) { id in
                        linkRow(id, how: isHandLinked(id) ? "Linked by hand" : "Named in the text")
                    }
                    ForEach(unresolved, id: \.self) { name in
                        Button {
                            makePage(named: name)
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(name).foregroundStyle(.primary)
                                    Text("No note by this name yet \u{2014} tap to make it")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        commit()
                        linking = true
                    } label: {
                        Label("Link to\u{2026}", systemImage: "link")
                    }
                }

                if !backlinks.isEmpty {
                    Section("Linked here from") {
                        ForEach(backlinks, id: \.self) { id in
                            linkRow(id, how: isHandLinked(id) ? "Linked by hand" : "Names this note")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryBackdrop())
            .navigationTitle(kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !trail.isEmpty {
                        Button {
                            goBack()
                        } label: {
                            Label("Back", systemImage: "chevron.backward")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commit()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Turn into cards", systemImage: "rectangle.on.rectangle") { turnIntoCards() }
                        Button("Delete note", systemImage: "trash", role: .destructive) {
                            confirmingDelete = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
            .confirmationDialog("Delete this note?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    notes.delete(current)
                    dismiss()
                }
            } message: {
                Text("Links to it from other notes are removed too.")
            }
            .alert("Turn into cards", isPresented: Binding(
                get: { cardsMessage != nil },
                set: { if !$0 { cardsMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cardsMessage ?? "")
            }
            .sheet(isPresented: $linking) {
                LinkPickerView(noteID: current)
            }
        }
        .onAppear {
            if !loaded { load() }
        }
        .onDisappear { commit() }
        // saved a moment after typing stops, not on every key
        .task(id: draftKey) {
            guard loaded else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    // MARK: loading and saving

    private var draftKey: String {
        [title, text, kind.rawValue, folderId?.uuidString ?? ""].joined(separator: "\u{0}")
    }

    private func load() {
        guard let note = notes.note(current) else { return }
        title = note.title
        text = note.body
        kind = note.kind
        folderId = note.folderId
        loaded = true
    }

    private func commit() {
        guard loaded, var note = notes.note(current) else { return }
        note.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        note.body = text
        note.kind = kind
        note.folderId = folderId
        notes.update(note)
    }

    // MARK: following links

    private func follow(_ id: UUID) {
        guard id != current else { return }
        commit()
        trail.append(current)
        current = id
        load()
    }

    private func goBack() {
        guard let previous = trail.popLast() else { return }
        commit()
        current = previous
        load()
    }

    /// A `[[Title]]` tapped while reading: that note, or a new page by that name.
    private func openNote(named name: String) {
        if let id = notes.titleIndex()[name.trimmingCharacters(in: .whitespaces).lowercased()] {
            follow(id)
        } else {
            makePage(named: name)
        }
    }

    private func makePage(named name: String) {
        let page = notes.create(title: name, kind: .page, folderId: folderId)
        follow(page.id)
    }

    // MARK: what this note is linked to, as typed

    /// Hand-made links, then the `[[Title]]`s in the text as it is now.
    private var outgoing: [UUID] {
        let explicit = notes.note(current)?.links ?? []
        let wiki = notes.resolve(wikiLinksIn: text)
        var seen = Set<UUID>([current])
        return (explicit + wiki).filter { notes.note($0) != nil && seen.insert($0).inserted }
    }

    private var backlinks: [UUID] {
        let shown = Set(outgoing)
        return notes.backlinks(of: current).filter { !shown.contains($0) }
    }

    /// `[[Title]]`s that name no note yet.
    private var unresolved: [String] {
        let index = notes.titleIndex()
        var seen = Set<String>()
        return NoteStore.wikiTitles(in: text).filter { title in
            index[title.lowercased()] == nil && seen.insert(title.lowercased()).inserted
        }
    }

    private func isHandLinked(_ id: UUID) -> Bool {
        notes.isLinked(current, id)
    }

    private func linkRow(_ id: UUID, how: String) -> some View {
        let note = notes.note(id)
        return Button {
            follow(id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: note?.kind.symbol ?? "doc")
                    .foregroundStyle(NoteTone.color(for: note?.folderId, in: notes))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.map { $0.title.isEmpty ? "Untitled" : $0.title } ?? "Missing note")
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(how)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            if isHandLinked(id) {
                Button("Unlink", systemImage: "xmark") {
                    notes.unlink(current, id)
                }
                .tint(.gray)
            }
        }
    }

    // MARK: [[ completion

    /// Whatever has been typed after an unclosed `[[` at the end of the text.
    private var openFragment: String? {
        guard let start = text.range(of: "[[", options: .backwards) else { return nil }
        let after = text[start.upperBound...]
        if after.contains("]") || after.contains("\n") { return nil }
        return String(after)
    }

    private var suggestions: [Note] {
        guard let fragment = openFragment?.lowercased() else { return [] }
        let matches = notes.notes.filter { note in
            note.id != current && !note.title.isEmpty
                && (fragment.isEmpty || note.title.lowercased().contains(fragment))
        }
        return Array(matches.sorted { $0.updatedAt > $1.updatedAt }.prefix(8))
    }

    private func complete(with name: String) {
        guard let start = text.range(of: "[[", options: .backwards) else { return }
        text = String(text[..<start.upperBound]) + name + "]]"
    }

    // MARK: studying it

    private func turnIntoCards() {
        commit()
        guard let note = notes.note(current) else { return }
        let cards = NoteCards.cards(from: note)
        guard !cards.isEmpty else {
            cardsMessage = "Nothing to make cards from yet. Write lines like \u{201C}Question | Answer\u{201D}, or bullet points under a title."
            return
        }
        let name = note.title.isEmpty ? "Ideas" : note.title
        store.addSet(StudySet(name: name, subject: "Ideas", kind: .anki, cards: cards))
        cardsMessage = "\u{201C}\(name)\u{201D} is in your Cards now, \(cards.count) card\(cards.count == 1 ? "" : "s") ready to review."
    }
}

/// Every other note, to join to this one by hand or to part from it.
struct LinkPickerView: View {
    let noteID: UUID
    @EnvironmentObject private var notes: NoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let others = notes.search(query).filter { $0.id != noteID }
                if others.isEmpty {
                    Text(query.isEmpty ? "There are no other notes yet." : "Nothing matches.")
                        .foregroundStyle(.secondary)
                }
                ForEach(others) { note in
                    let linked = notes.isLinked(noteID, note.id)
                    Button {
                        if linked { notes.unlink(noteID, note.id) } else { notes.link(noteID, note.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: note.kind.symbol)
                                .foregroundStyle(NoteTone.color(for: note.folderId, in: notes))
                                .frame(width: 24)
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            if linked {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(linked ? [.isSelected] : [])
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryBackdrop())
            .searchable(text: $query, prompt: "Find a note")
            .navigationTitle("Link to\u{2026}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
