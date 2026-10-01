import SwiftUI

/// One note, to write in and to join up with the rest.
///
/// Writing `[[Title]]` in the body links to the note of that title, as in
/// Obsidian; while typing one, the matching notes are offered in the bar over
/// the keyboard, and the links appear underneath as they are typed. "Link
/// to…" joins two notes by hand without writing anything. Tapping a linked
/// note opens it in place, with Back to return, so a chain of ideas can be
/// followed without closing anything.
///
/// Where things are:
/// - top: Back (after following a link), Done, and More with Delete note;
/// - under the title: two small chips, the note's kind and its folder;
/// - bottom, under the thumb, in one floating bar: Write / Read, Link to…
///   and the one main action, Turn into cards. The bar stays put while
///   typing and rides above the keyboard, so every action is in reach.
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
    /// Which field has the caret, if any.
    @FocusState private var editing: EditorField?

    enum EditorField: Hashable { case title, body }

    init(noteID: UUID) {
        _current = State(initialValue: noteID)
    }

    private var bodyHeight: CGFloat {
        kind == .page ? 260 : 140
    }

    private var cardsAlertShown: Binding<Bool> {
        Binding(get: { cardsMessage != nil }, set: { if !$0 { cardsMessage = nil } })
    }

    var body: some View {
        NavigationStack {
            form
                .scrollContentBackground(.hidden)
                .background(LibraryBackdrop())
                .studyBar { actionBar }
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
                            Button("Delete note", systemImage: "trash", role: .destructive) {
                                confirmingDelete = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("More")
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        if editing == .body && !reading && !suggestions.isEmpty {
                            suggestionBar
                        }
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
                .alert("Turn into cards", isPresented: cardsAlertShown) {
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

    /// The note itself: title and chips, the text, and its links.
    private var form: some View {
        Form {
            Section {
                // the title is a field you touch: its own raised slab
                TextField("Title", text: $title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .focused($editing, equals: .title)
                    .popFieldRow()
                HStack(spacing: 8) {
                    kindChip
                    folderChip
                    Spacer(minLength: 0)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(PopOutField.rowInsets)
            }

            Section {
                if reading {
                    NoteMarkdownView(text: text) { name in openNote(named: name) }
                        .frame(minHeight: bodyHeight, alignment: .topLeading)
                } else {
                    // The note's body is a reading surface - long text that is
                    // read, re-read and edited in place - so it stays ON the
                    // glass (screen plane) and never slides with the pop-out.
                    TextEditor(text: $text)
                        .frame(minHeight: bodyHeight)
                        .focused($editing, equals: .body)
                        .accessibilityLabel("Note")
                }
            } header: {
                Text("Notes")
            } footer: {
                Text("Type [[ and a note\u{2019}s title to link it, like [[Heart failure]]. Markdown works too: # headings, - bullets, **bold**, *italic*; switch to Read to see it laid out. Lines written \u{201C}Question | Answer\u{201D}, or bullet points, can be turned into cards.")
            }

            linkedSection

            if !backlinks.isEmpty {
                Section("Linked here from") {
                    ForEach(backlinks, id: \.self) { id in
                        linkRow(id, how: isHandLinked(id) ? "Linked by hand" : "Names this note")
                    }
                }
            }
        }
    }

    // MARK: the bottom bar and the chips

    /// Write / Read, Link to… and Turn into cards - with words when they
    /// fit, and the two smaller ones as symbols when they do not.
    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            NoteEditorActions(reading: $reading, labelled: true,
                              link: startLinking, cards: turnIntoCards)
            NoteEditorActions(reading: $reading, labelled: false,
                              link: startLinking, cards: turnIntoCards)
        }
    }

    private func startLinking() {
        commit()
        linking = true
    }

    private var kindChip: some View {
        let spoken: String = "Kind, \(kind.label)"
        return Menu {
            Picker("Kind", selection: $kind) {
                ForEach(NoteKind.allCases) { kind in
                    Label(kind.label, systemImage: kind.symbol).tag(kind)
                }
            }
        } label: {
            NoteChipLabel(title: kind.label, symbol: kind.symbol)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
    }

    private var folderChip: some View {
        let name: String = notes.folder(folderId)?.name ?? "No folder"
        let spoken: String = "Folder, \(name)"
        let tone: Color = NoteTone.color(for: folderId, in: notes)
        return Menu {
            Picker("Folder", selection: $folderId) {
                Text("No folder").tag(UUID?.none)
                ForEach(Array(notes.folderOutline().enumerated()), id: \.offset) { _, entry in
                    Text(IdeasView.indented(entry.folder.name, depth: entry.depth))
                        .tag(Optional(entry.folder.id))
                }
            }
        } label: {
            NoteChipLabel(title: name, symbol: "folder", tint: tone)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
    }

    /// The notes a half-typed `[[` could mean, over the keyboard.
    private var suggestionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions) { note in
                    Button(note.title) { complete(with: note.title) }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The notes this one links to. "Link to…" is only here when there are
    /// none yet; otherwise it is in the bottom bar alone.
    private var linkedSection: some View {
        let out: [UUID] = outgoing
        let missing: [String] = unresolved
        let none: Bool = out.isEmpty && missing.isEmpty
        return Section("Linked notes") {
            ForEach(out, id: \.self) { id in
                linkRow(id, how: isHandLinked(id) ? "Linked by hand" : "Named in the text")
            }
            ForEach(missing, id: \.self) { name in
                missingRow(name)
            }
            if none {
                Button {
                    startLinking()
                } label: {
                    Label("Link to\u{2026}", systemImage: "link")
                }
            }
        }
    }

    private func missingRow(_ name: String) -> some View {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
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
        let explicit: [UUID] = notes.note(current)?.links ?? []
        let wiki: [UUID] = notes.resolve(wikiLinksIn: text)
        let both: [UUID] = explicit + wiki
        var seen = Set<UUID>([current])
        return both.filter { notes.note($0) != nil && seen.insert($0).inserted }
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
        let named: String = note.map { $0.title.isEmpty ? "Untitled" : $0.title } ?? "Missing note"
        return Button {
            follow(id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: note?.kind.symbol ?? "doc")
                    .foregroundStyle(NoteTone.color(for: note?.folderId, in: notes))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(named)
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
        .hoverEffect(.highlight)
        .contextMenu {
            if isHandLinked(id) {
                Button("Unlink", systemImage: "xmark") {
                    notes.unlink(current, id)
                }
            }
        }
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
        let matches: [Note] = notes.notes.filter { note in
            let fits: Bool = fragment.isEmpty || note.title.lowercased().contains(fragment)
            return note.id != current && !note.title.isEmpty && fits
        }
        let recent: [Note] = matches.sorted { $0.updatedAt > $1.updatedAt }
        return Array(recent.prefix(8))
    }

    private func complete(with name: String) {
        guard let start = text.range(of: "[[", options: .backwards) else { return }
        let head: String = String(text[..<start.upperBound])
        text = head + name + "]]"
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
        let name: String = note.title.isEmpty ? "Ideas" : note.title
        store.addSet(StudySet(name: name, subject: "Ideas", kind: .anki, cards: cards))
        let count: Int = cards.count
        let plural: String = count == 1 ? "" : "s"
        let made: String = "\(count) card\(plural)"
        cardsMessage = "\u{201C}\(name)\u{201D} is in your Cards now, \(made) ready to review."
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

/// The editor's bottom bar: Write / Read, Link to… (the companion, leading)
/// and Turn into cards (the one main action, trailing, under the right
/// thumb).
private struct NoteEditorActions: View {
    @Binding var reading: Bool
    /// Words on the switch and on Link to…; symbols when there is no room.
    let labelled: Bool
    let link: () -> Void
    let cards: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            NoteModePicker(reading: $reading, labelled: labelled)
            Button(action: link) {
                if labelled {
                    Text("Link to\u{2026}")
                } else {
                    Image(systemName: "link")
                }
            }
            .buttonStyle(.bigCompanion)
            .accessibilityLabel("Link to\u{2026}")
            Button(action: cards) {
                Text("Turn into cards")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .buttonStyle(.bigPrimary)
        }
    }
}

/// Write or Read: the note as typed, or laid out as Markdown.
private struct NoteModePicker: View {
    @Binding var reading: Bool
    let labelled: Bool

    var body: some View {
        Picker("View", selection: $reading) {
            if labelled {
                Text("Write").tag(false)
                Text("Read").tag(true)
            } else {
                Image(systemName: "pencil")
                    .accessibilityLabel("Write")
                    .tag(false)
                Image(systemName: "doc.richtext")
                    .accessibilityLabel("Read")
                    .tag(true)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .fixedSize()
        .frame(minHeight: 44)
        .accessibilityIdentifier("noteMarkdownToggle")
    }
}

/// A small chip under the title - the note's kind, or its folder - that
/// opens a menu to change it.
private struct NoteChipLabel: View {
    let title: String
    let symbol: String
    /// The folder's own colour on the folder chip; grey on the kind chip.
    var tint: Color = Color.gray

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .liquidGlassChip(tint: tint, plane: .raised)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }
}
