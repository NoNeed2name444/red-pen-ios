import SwiftUI

/// "Add to…": keep a captured question in a study mode - a question set, a
/// deck, the cases, an OSCE station, the idea dump or a narration - in a set
/// or folder the student picks, or in "Lens captures".
///
/// Whatever is made carries the Lens tag and "Study Lens" as its source, and
/// joins the library like any new content, so the accuracy engine checks it
/// as it checks everything else.
struct LensAddSheet: View {
    let question: DetectedQuestion
    let answer: LensAnswer
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var notes: NoteStore
    @Environment(\.dismiss) private var dismiss

    /// Where in the chosen mode.
    enum Target: Hashable {
        case lensCaptures
        case existing(UUID)
        case new
    }

    @State private var destination: LensDestination
    @State private var target: Target = .lensCaptures
    @State private var newName: String = ""
    @State private var added: String?
    @State private var problem: String?

    init(question: DetectedQuestion, answer: LensAnswer) {
        self.question = question
        self.answer = answer
        let suggested: LensDestination = LensDestination.suggested(for: question.type)
        let usable: Bool = LensConversion.can(question, answer, goTo: suggested)
        _destination = State(initialValue: usable ? suggested : .ideas)
    }

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                placeSection
                if let added {
                    Section {
                        Label(added, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryBackdrop())
            .navigationTitle("Add to\u{2026}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(added == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: destination) { _, _ in
                target = .lensCaptures
                added = nil
                problem = nil
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: choosing

    private var modeSection: some View {
        Section("Add as") {
            ForEach(LensDestination.allCases) { d in
                let usable: Bool = LensConversion.can(question, answer, goTo: d)
                Button {
                    destination = d
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: d.symbol)
                            .foregroundStyle(LensStyle.tint(d))
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.title).foregroundStyle(.primary)
                            Text(usable ? d.detail : "Not enough in this answer to make one")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if d == destination {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .disabled(!usable)
                .accessibilityAddTraits(d == destination ? .isSelected : [])
            }
        }
    }

    private var placeSection: some View {
        Section(destination == .ideas ? "Folder" : "Set") {
            Picker(destination == .ideas ? "Folder" : "Set", selection: $target) {
                Text(LensConversion.defaultName).tag(Target.lensCaptures)
                ForEach(places) { place in
                    Text(place.name).tag(Target.existing(place.id))
                }
                Text(destination == .ideas ? "New folder\u{2026}" : "New set\u{2026}").tag(Target.new)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if target == .new {
                TextField(destination == .ideas ? "Folder name" : "Set name", text: $newName)
                    .textInputAutocapitalization(.words)
            }
        }
    }

    /// The sets of the chosen mode (newest first), or the note folders, less
    /// the one called "Lens captures", which has its own row.
    private var places: [LensPlace] {
        if destination == .ideas {
            let outline: [(folder: NoteFolder, depth: Int)] = notes.folderOutline()
            let kept = outline.filter { $0.folder.name != LensConversion.defaultName }
            return kept.map { LensPlace(id: $0.folder.id, name: String(repeating: "  ", count: $0.depth) + $0.folder.name) }
        }
        guard let kind = destination.kind else { return [] }
        let sets: [StudySet] = store.library.filter { $0.kind == kind && $0.name != LensConversion.defaultName }
        let newest: [StudySet] = sets.sorted { $0.updatedAt > $1.updatedAt }
        return newest.map { LensPlace(id: $0.id, name: $0.name) }
    }

    private var canSave: Bool {
        guard added == nil else { return false }
        if target == .new { return !newName.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    // MARK: saving

    private func save() {
        problem = nil
        if destination == .ideas {
            saveNote()
            return
        }
        guard let kind = destination.kind else { return }
        let name: String = newName.trimmingCharacters(in: .whitespaces)
        var base: StudySet? = nil
        switch target {
        case .existing(let id):
            base = store.library.first { $0.id == id }
        case .lensCaptures:
            base = store.library.first { $0.kind == kind && $0.name == LensConversion.defaultName }
        case .new:
            base = nil
        }
        let isNew: Bool = base == nil
        let fresh: StudySet? = LensConversion.newSet(for: destination, name: name.isEmpty ? LensConversion.defaultName : name)
        guard let start = base ?? fresh,
              let updated = LensConversion.adding(question, answer, to: start) else {
            problem = "This answer can\u{2019}t be made into that mode."
            return
        }
        if isNew { store.addSet(updated) } else { store.update(updated) }
        added = "Added to \u{201C}" + updated.name + "\u{201D} in " + destination.title + "."
    }

    /// An idea note in the chosen folder, linked to the "Lens captures" hub
    /// note (made the first time) so every capture sits together on the board.
    private func saveNote() {
        let folderID: UUID? = noteFolder()
        let hubExists: Bool = notes.notes.contains { $0.title == LensConversion.defaultName }
        if !hubExists {
            notes.create(title: LensConversion.defaultName,
                         body: "Questions captured with Study Lens link here.",
                         kind: .page, folderId: folderID)
        }
        let made = LensConversion.note(question, answer)
        var note: Note = notes.create(title: made.title, body: made.body, kind: .idea, folderId: folderID)
        note.tags = [LensConversion.tag]
        notes.update(note)
        added = "Added to Ideas."
    }

    private func noteFolder() -> UUID? {
        switch target {
        case .existing(let id):
            return id
        case .new:
            let name: String = newName.trimmingCharacters(in: .whitespaces)
            return notes.createFolder(name: name).id
        case .lensCaptures:
            if let found = notes.folders.first(where: { $0.name == LensConversion.defaultName && $0.parentId == nil }) {
                return found.id
            }
            return notes.createFolder(name: LensConversion.defaultName).id
        }
    }
}

/// A set or note folder to add to.
struct LensPlace: Identifiable, Hashable {
    let id: UUID
    let name: String
}
