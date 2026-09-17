import SwiftUI

/// The set list — matches the web app's `renderLibrary()` / `#libraryView`:
/// every saved set, tap to open into its mode's session, swipe to delete,
/// swipe the other way to export a PDF.
struct LibraryView: View {
    @EnvironmentObject var store: Store
    @State private var showNewSet = false
    @State private var exportURL: URL?
    @State private var exportFailedSetName: String?

    // selection mode — the web app's "Combine" / folder toggles
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var naming: NamingSheet?
    @State private var renaming: StudySet?
    @State private var renamingFolder: StudyFolder?
    @State private var draftName = ""

    private var pen: Color { StudySetKind.mcq.tint }

    private enum NamingSheet: Identifiable {
        case folder, combine
        var id: Int { self == .folder ? 0 : 1 }
    }
    private var selectedSets: [StudySet] { store.library.filter { selected.contains($0.id) } }
    private var canCombine: Bool {
        selectedSets.count >= 2 && Set(selectedSets.map(\.kind)).count == 1
    }
    private var loose: [StudySet] { store.library.filter { $0.folderId == nil } }
    private func members(of f: StudyFolder) -> [StudySet] { store.library.filter { $0.folderId == f.id } }

    var body: some View {
        NavigationStack {
            Group {
                if store.library.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            summaryStrip
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        }
                        if !loose.isEmpty {
                            Section {
                                ForEach(Array(loose.enumerated()), id: \.element.id) { i, set in row(set).riseIn(index: i) }
                                    .onDelete { offsets in delete(offsets.map { loose[$0].id }) }
                            } header: { sectionHeader("Your sets") }
                        }
                        ForEach(store.folders) { folder in
                            let inside = members(of: folder)
                            Section {
                                ForEach(Array(inside.enumerated()), id: \.element.id) { i, set in row(set).riseIn(index: loose.count + i) }
                                    .onDelete { offsets in delete(offsets.map { inside[$0].id }) }
                            } header: {
                                HStack {
                                    Label(folder.name, systemImage: "folder.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Menu {
                                        Button("Rename folder", systemImage: "pencil") {
                                            draftName = folder.name; renamingFolder = folder
                                        }
                                        Button("Ungroup", systemImage: "folder.badge.minus") { store.ungroup(folder.id) }
                                    } label: {
                                        Image(systemName: "ellipsis.circle").font(.body)
                                    }
                                }
                                .textCase(nil)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(LibraryBackdrop())
            .navigationTitle("Red Pen")
            .navigationDestination(for: StudySet.self) { set in
                destination(for: set)
            }
            .toolbar {
                if !store.library.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(selecting ? "Done" : "Select") {
                            withAnimation(.snappy) { selecting.toggle(); selected = [] }
                        }
                        .buttonStyle(.glass)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewSet = true } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .clipShape(Circle())
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting { selectionBar }
            }
            .sheet(item: $naming) { which in
                NameSheet(title: which == .folder ? "New folder" : "Combined set",
                          prompt: which == .folder ? "Folder name" : "Name the combined set",
                          initial: which == .folder ? "" : (selectedSets.first.map { "\($0.name) — combined" } ?? ""),
                          confirm: which == .folder ? "Create folder" : "Create combined set") { name in
                    if which == .folder { store.group(selected, into: name) }
                    else { store.combine(selectedSets.map(\.id), name: name) }
                    withAnimation(.snappy) { selecting = false; selected = [] }
                }
            }
            .sheet(item: $renaming) { set in
                NameSheet(title: "Rename set", prompt: "Set name", initial: set.name, confirm: "Rename") { name in
                    store.rename(set.id, to: name)
                }
            }
            .sheet(item: $renamingFolder) { folder in
                NameSheet(title: "Rename folder", prompt: "Folder name", initial: folder.name, confirm: "Rename") { name in
                    store.renameFolder(folder.id, to: name)
                }
            }
            .sheet(isPresented: $showNewSet) { NewSetView() }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                if let exportURL { ShareSheet(items: [exportURL]) }
            }
            .alert("Couldn't export", isPresented: .init(
                get: { exportFailedSetName != nil },
                set: { if !$0 { exportFailedSetName = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Something went wrong building the PDF for \(exportFailedSetName ?? "this set").")
            }
        }
        .tint(pen)
    }

    // MARK: pieces

    /// A row of small mode counters across the top — how many of each kind
    /// of set the library holds.
    private var summaryStrip: some View {
        let counts = Dictionary(grouping: store.library, by: \.kind).mapValues(\.count)
        let kinds = StudySetKind.allCases.filter { counts[$0] != nil }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(kinds) { kind in
                    HStack(spacing: 6) {
                        Image(systemName: kind.symbol).font(.caption.weight(.semibold))
                        Text("\(counts[kind] ?? 0) \(kind.label)").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(kind.tint)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .glassEffect(.regular.tint(kind.tint.opacity(0.22)), in: .capsule)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    private func delete(_ ids: [UUID]) {
        ids.forEach { store.deleteSet($0) }
    }

    /// One library row — a navigation link normally, a tickable row in
    /// selection mode, with the web app's per-set actions in a long-press
    /// menu and as swipe actions.
    @ViewBuilder
    private func row(_ set: StudySet) -> some View {
        Group {
            if selecting {
                Button {
                    withAnimation(.snappy(duration: 0.15)) {
                        if selected.contains(set.id) { selected.remove(set.id) } else { selected.insert(set.id) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected.contains(set.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selected.contains(set.id) ? set.kind.tint : Color.secondary)
                        setRow(set)
                    }
                }
                .buttonStyle(.pressableRow)
            } else {
                NavigationLink(value: set) { setRow(set) }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
        .contextMenu {
            Button("Rename", systemImage: "pencil") { renaming = set }
            Menu("Move to folder", systemImage: "folder") {
                ForEach(store.folders) { f in
                    Button(f.name) { store.move(set.id, to: f.id) }
                }
                Button("New folder…", systemImage: "folder.badge.plus") {
                    selected = [set.id]; naming = .folder
                }
                if set.folderId != nil {
                    Divider()
                    Button("Remove from folder", systemImage: "folder.badge.minus") { store.move(set.id, to: nil) }
                }
            }
            Button("Export PDF", systemImage: "arrow.down.doc") { export(set) }
            if set.kind == .anki {
                // the web app's "Export .apkg" — opens straight into the Anki app
                Button("Export Anki deck (.apkg)", systemImage: "square.and.arrow.up") {
                    if let url = try? ApkgExporter.export(set) { exportURL = url } else { exportFailedSetName = set.name }
                }
            }
            Button("Share as JSON", systemImage: "doc.text") {
                if let url = JSONExporter.export(set) { exportURL = url } else { exportFailedSetName = set.name }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { store.deleteSet(set.id) }
        }
        .swipeActions(edge: .leading) {
            // matches the web app's per-mode "Export PDF" button
            Button { export(set) } label: { Label("Export PDF", systemImage: "arrow.down.doc") }
                .tint(.teal)
        }
    }

    private func export(_ set: StudySet) {
        if let url = PDFExporter.export(set) { exportURL = url }
        else { exportFailedSetName = set.name }
    }

    /// The floating action bar shown in selection mode — the web app's
    /// "Combine N selected" / "Group into folder" controls.
    private var selectionBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                Text(selected.isEmpty ? "Select sets" : "\(selected.count) selected")
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button { naming = .folder } label: { Label("Folder", systemImage: "folder.badge.plus") }
                    .buttonStyle(.glass)
                    .disabled(selected.isEmpty)
                Button { naming = .combine } label: { Label("Combine", systemImage: "square.stack.3d.down.forward") }
                    .buttonStyle(.glassProminent)
                    .disabled(!canCombine)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(.horizontal, 10).padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func setRow(_ set: StudySet) -> some View {
        HStack(spacing: 14) {
            ModeTile(kind: set.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(set.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(set.kind.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(set.kind.tint)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(set.itemCount) \(set.itemNoun)\(set.itemCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !set.subject.isEmpty && set.subject != "General" {
                        Text("·").foregroundStyle(.tertiary)
                        Text(set.subject).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            HStack(spacing: -10) {
                ForEach([StudySetKind.mcq, .anki, .qa], id: \.self) { kind in
                    ModeTile(kind: kind, size: 56)
                        .rotationEffect(.degrees(kind == .anki ? 0 : (kind == .mcq ? -10 : 10)))
                }
            }
            Text("Nothing here yet")
                .font(.title2.weight(.bold))
            Text("Make an MCQ quiz, an Anki deck, a textbook, a case set, an OSCE checklist, or a narrated transcript — all of it stays on this phone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { showNewSet = true } label: {
                Label("New set", systemImage: "plus")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func destination(for set: StudySet) -> some View {
        switch set.kind {
        case .mcq: MCQQuizView(set: set)
        case .anki: AnkiReviewView(set: set)
        case .book: BookReaderView(set: set)
        case .qa: QACardsView(set: set)
        case .osce: OsceReviewView(set: set)
        case .narrate: NarrateReviewView(set: set)
        }
    }
}

/// The library's own backdrop: a warm paper tone with a whisper of pen red,
/// matching the web app's cream-and-red identity.
private struct LibraryBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            RadialGradient(colors: [StudySetKind.mcq.tint.opacity(scheme == .dark ? 0.22 : 0.14), .clear],
                           center: .init(x: 1.0, y: 0.0), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [StudySetKind.anki.tint.opacity(scheme == .dark ? 0.16 : 0.10), .clear],
                           center: .init(x: 0.0, y: 1.0), startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}

/// A one-field naming sheet used for new folders, combined sets and
/// renames — the native stand-in for the web app's inline save forms.
private struct NameSheet: View {
    let title: String
    let prompt: String
    let initial: String
    let confirm: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(prompt, text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(submit)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm, action: submit)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { name = initial; focused = true }
        }
        .presentationDetents([.height(180)])
    }

    private func submit() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        onConfirm(n); dismiss()
    }
}
