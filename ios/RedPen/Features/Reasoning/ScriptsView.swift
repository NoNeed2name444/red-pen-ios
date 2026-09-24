import SwiftUI

/// A set's disease scripts: one card per disease with who gets it, how it
/// runs, what to look for, what settles it and what to do - and a way to keep
/// them in Ideas, where their lookalikes join them up in the graph.
struct ScriptsView: View {
    let set: StudySet
    @ObservedObject private var reasoning = ReasoningStore.shared
    @EnvironmentObject private var notes: NoteStore
    @State private var confirmClear = false
    @State private var savedMessage: String?

    /// The folder in Ideas that saved scripts go into.
    static let folderName = "Disease scripts"

    var body: some View {
        let scripts = reasoning.pack(for: set.id).scripts
        let titles = notes.titleIndex()
        let here = Set(scripts.map { $0.disease.lowercased() })
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if set.id != ReasoningExamples.setId {
                        ReasoningWriteBar(tool: .scripts, set: set)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemBackground)))
                    }
                    if scripts.isEmpty {
                        Text("No scripts yet. Write them from this set's lecture above.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    }
                    ForEach(scripts) { script in
                        ScriptCard(
                            script: script,
                            saved: titles[script.disease.trimmingCharacters(in: .whitespaces).lowercased()] != nil,
                            jumpable: here,
                            onSave: { save([script]) },
                            onJump: { name in
                                guard let target = scripts.first(where: { $0.disease.lowercased() == name.lowercased() })
                                else { return }
                                withAnimation(.snappy) { reader.scrollTo(target.id, anchor: .top) }
                            })
                        .id(script.id)
                    }
                }
                .padding()
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Disease scripts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !scripts.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Save all to Ideas", systemImage: "lightbulb") { save(scripts) }
                        if set.id != ReasoningExamples.setId {
                            Button("Delete scripts", systemImage: "trash", role: .destructive) { confirmClear = true }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("Delete these scripts?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete scripts", role: .destructive) { reasoning.clear(.scripts, for: set.id) }
        } message: {
            Text("Scripts already saved to Ideas stay there.")
        }
        .alert("Saved to Ideas", isPresented: Binding(get: { savedMessage != nil },
                                                    set: { if !$0 { savedMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(savedMessage ?? "")
        }
        .generationHUD()
    }

    /// Saves scripts to Ideas as pages in the "Disease scripts" folder, each
    /// lookalike written as a `[[link]]`. A script already there under the
    /// same title is brought up to date rather than saved twice.
    private func save(_ scripts: [IllnessScript]) {
        let folder = notes.subfolders(of: nil).first { $0.name == Self.folderName }
            ?? notes.createFolder(name: Self.folderName)
        var added = 0, updated = 0
        for script in scripts {
            let index = notes.titleIndex()
            let key = script.disease.trimmingCharacters(in: .whitespaces).lowercased()
            if let id = index[key], var existing = notes.note(id) {
                existing.body = script.notePage
                existing.kind = .page
                if !existing.tags.contains("disease script") { existing.tags.append("disease script") }
                notes.update(existing)
                updated += 1
            } else {
                var made = notes.create(title: script.disease, body: script.notePage, kind: .page, folderId: folder.id)
                made.tags = ["disease script"]
                notes.update(made)
                added += 1
            }
        }
        var parts: [String] = []
        if added > 0 { parts.append("\(added) new page\(added == 1 ? "" : "s")") }
        if updated > 0 { parts.append("\(updated) updated") }
        savedMessage = parts.joined(separator: ", ")
            + " in \u{201C}\(Self.folderName)\u{201D}. Lookalikes are linked, so scripts that name each other join up in the graph."
    }
}

/// One disease on one card.
struct ScriptCard: View {
    let script: IllnessScript
    /// Already a page in Ideas.
    let saved: Bool
    /// Diseases with a card of their own on this screen, lowercased: their
    /// lookalike chips jump to that card.
    let jumpable: Set<String>
    let onSave: () -> Void
    let onJump: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(script.disease).font(.title3.weight(.bold))
                Spacer(minLength: 8)
                Button(action: onSave) {
                    Label(saved ? "In Ideas" : "Save to Ideas",
                          systemImage: saved ? "checkmark.circle.fill" : "lightbulb")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            line("person.2", "Who gets it", script.who)
            line("clock", "Time course", script.timeCourse)
            list("list.bullet", "Key features", script.keyFeatures)
            list("stethoscope", "Examination", script.examSigns)
            line("testtube.2", "Decisive investigation", script.decisiveTest, strong: true)
            line("cross.case", "First-line management", script.firstLine)
            if !script.lookalikes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    heading("arrow.triangle.branch", "Lookalikes")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(script.lookalikes, id: \.self) { name in
                                let here = jumpable.contains(name.lowercased())
                                Button {
                                    onJump(name)
                                } label: {
                                    Text(name)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Capsule().fill(here ? Color.accentColor.opacity(0.18)
                                                                        : Color.secondary.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                                .disabled(!here)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func heading(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func line(_ symbol: String, _ title: String, _ text: String, strong: Bool = false) -> some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                heading(symbol, title)
                Text(text)
                    .font(strong ? .subheadline.weight(.semibold) : .subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func list(_ symbol: String, _ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                heading(symbol, title)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\u{2022}").foregroundStyle(.secondary)
                        Text(item).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
