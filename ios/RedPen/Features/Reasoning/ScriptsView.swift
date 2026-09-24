import SwiftUI
import UIKit

/// A set's disease scripts: one card per disease with who gets it, how it
/// runs, what to look for, what settles it and what to do - and a way to keep
/// them in Ideas, where their lookalikes join them up in the graph.
///
/// Writing more and Save all to Ideas sit in the slab at the bottom; Delete
/// is in the More menu at the top, away from them.
struct ScriptsView: View {
    let set: StudySet
    @ObservedObject private var reasoning = ReasoningStore.shared
    @EnvironmentObject private var notes: NoteStore
    @State private var confirmClear = false
    @State private var savedMessage: String?

    /// The folder in Ideas that saved scripts go into.
    static let folderName = "Disease scripts"

    private var isExample: Bool { self.set.id == ReasoningExamples.setId }

    var body: some View {
        let scripts = reasoning.pack(for: set.id).scripts
        let titles = notes.titleIndex()
        let here = Set(scripts.map { $0.disease.lowercased() })
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if scripts.isEmpty {
                        Text("No scripts yet. Write them from this set\u{2019}s lecture below.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    }
                    ForEach(scripts) { script in
                        let key: String = script.disease.trimmingCharacters(in: .whitespaces).lowercased()
                        ScriptCard(
                            script: script,
                            saved: titles[key] != nil,
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
        .background(LibraryBackdrop())
        .overlay(alignment: .top) {
            if let savedMessage {
                SavedToIdeasToast(message: savedMessage) { self.savedMessage = nil }
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: savedMessage)
        .task(id: savedMessage) {
            // non-modal: it says what happened and goes by itself
            guard savedMessage != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            savedMessage = nil
        }
        .navigationTitle("Disease scripts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !scripts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Save all to Ideas", systemImage: "lightbulb") { save(scripts) }
                        if !isExample {
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
        .studyBar { bar(scripts) }
    }

    /// Write more, and Save all to Ideas once there is something to save.
    private func bar(_ scripts: [IllnessScript]) -> some View {
        VStack(spacing: 12) {
            if !isExample {
                ReasoningWriteBar(tool: .scripts, set: set)
            }
            if !scripts.isEmpty {
                Button {
                    save(scripts)
                } label: {
                    Label("Save all to Ideas", systemImage: "lightbulb")
                }
                .buttonStyle(.bigSecondary)
                .accessibilityHint("Keeps every script here as a page in Ideas, with lookalikes linked")
            }
        }
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
        if added > 0 {
            let plural: String = added == 1 ? "" : "s"
            parts.append("\(added) new page\(plural)")
        }
        if updated > 0 { parts.append("\(updated) updated") }
        let counts: String = parts.joined(separator: ", ")
        let message: String = "\(counts) in \u{201C}\(Self.folderName)\u{201D}, lookalikes linked"
        savedMessage = message
        let spoken: String = "Saved to Ideas: " + message
        UIAccessibility.post(notification: .announcement, argument: spoken)
    }
}

/// "Saved to Ideas", for two seconds, at the top: a glass slip that stands a
/// little out of the screen and does not stop anything. A tap puts it away.
private struct SavedToIdeasToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.title3)
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved to Ideas")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .liquidGlassPanel(cornerRadius: 18)
        .popOut(.raised, in: shape)
        .contentShape(shape)
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
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
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(script.disease).font(.title3.weight(.bold))
                Spacer(minLength: 8)
                saveButton
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
                                lookalikeChip(name)
                            }
                        }
                        // room for a raised chip to lean without being cut
                        // off at the ends; the row still lines up with the
                        // heading above
                        .padding(.horizontal, 6)
                    }
                    .padding(.horizontal, -6)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: shape)
    }

    /// Save to Ideas as a 44-point icon on a frosted disc that stands out of
    /// the card and sinks under the finger: a lightbulb, or a tick once it is
    /// there.
    private var saveButton: some View {
        let symbol: String = saved ? "checkmark.circle.fill" : "lightbulb"
        let title: String = saved ? "In Ideas \u{2014} save again" : "Save to Ideas"
        let colour: Color = saved ? Color.green : Color.accentColor
        return Button(action: onSave) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(colour)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        // a 22-point corner on a 44-point face is a circle
        .buttonStyle(PopTileStyle(cornerRadius: 22))
        .help(title)
        .accessibilityLabel(title)
    }

    /// A lookalike with a card on this screen is a glass chip standing out of
    /// the card; one without sits flat, since it goes nowhere.
    private func lookalikeChip(_ name: String) -> some View {
        let here: Bool = jumpable.contains(name.lowercased())
        return Button {
            onJump(name)
        } label: {
            LookalikeChipFace(name: name, here: here)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .disabled(!here)
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

/// One lookalike's face: raised glass when it jumps to a card here, a flat
/// grey capsule when it does not.
private struct LookalikeChipFace: View {
    let name: String
    let here: Bool

    var body: some View {
        let words = Text(name)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        if here {
            words.liquidGlassChip(tint: nil, plane: .raised)
        } else {
            words.background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
    }
}
