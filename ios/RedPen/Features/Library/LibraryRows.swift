import SwiftUI

/// Everything the library draws for one row or one strip.
///
/// Split out of LibraryView because that file had grown to the point where
/// changing one thing meant re-reading four hundred lines to find it, and
/// because SwiftUI type-checks a whole view expression at once.
extension LibraryView {

    /// What is due right now, across every deck at once.
    ///
    /// The count is the point. Twenty lectures means twenty decks, and without
    /// a number on the first screen nobody knows which of them is waiting - so
    /// the schedule goes unused however well it works underneath.
    @ViewBuilder
    var dueBanner: some View {
        let due = reviews.dueAcross(store.library).count
        if store.library.contains(where: { $0.kind == .anki }) {
            NavigationLink { DueTodayView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: due > 0 ? "tray.full.fill" : "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(due > 0 ? StudySetKind.anki.tint : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(due > 0 ? "\(due) card\(due == 1 ? "" : "s") due" : "Nothing due")
                            .font(.body.weight(.semibold))
                        Text(due > 0 ? "Across all your decks" : "You're up to date")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if due > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
            .disabled(due == 0)
        }
    }

    /// A row of small mode counters - how many of each kind of set the library
    /// holds.
    var summaryStrip: some View {
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

    func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    /// One library row - a navigation link normally, a tickable row in
    /// selection mode, with the per-set actions in a long-press menu and as
    /// swipe actions.
    @ViewBuilder
    func row(_ set: StudySet) -> some View {
        Group {
            if selecting {
                Button {
                    withAnimation(.snappy(duration: 0.15)) {
                        if selected.contains(set.id) { selected.remove(set.id) }
                        else { selected.insert(set.id) }
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
            } else if span.splits {
                // Two columns: the row chooses what the other column shows,
                // rather than pushing a screen over the list it came from.
                Button { chosen = set.id } label: { setRow(set) }
                    .buttonStyle(.pressableRow)
                    .listRowBackground(chosen == set.id
                                       ? set.kind.tint.opacity(0.10) : Color.clear)
            } else {
                NavigationLink(value: set) { setRow(set) }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
        .contextMenu { rowMenu(set) }
        .swipeActions(edge: .leading) {
            Button { export(set) } label: { Label(set.kind == .anki ? "Export deck" : "Export PDF", systemImage: "arrow.down.doc") }
                .tint(set.kind.tint)
        }
    }

    @ViewBuilder
    func rowMenu(_ set: StudySet) -> some View {
        Button("Rename", systemImage: "pencil") { renaming = set }
        // The lecture this set came from, readable on its own - not only by
        // way of a card that happens to cite it.
        if set.sources.count == 1, let only = set.sources.first {
            Button("Open \(only.name)", systemImage: only.kind.symbol) {
                reading = SourceOpening(source: only, page: 1)
            }
        } else if set.sources.count > 1 {
            Menu("Open source", systemImage: "doc.richtext") {
                ForEach(set.sources) { source in
                    Button(source.name, systemImage: source.kind.symbol) {
                        reading = SourceOpening(source: source, page: 1)
                    }
                }
            }
        }
        if set.kind == .anki || set.kind == .mcq {
            Button("Edit cards", systemImage: "square.and.pencil") { editing = set }
        }
        Menu("Move to folder", systemImage: "folder") {
            ForEach(store.folders) { folder in
                Button(folder.name) { store.move(set.id, to: folder.id) }
            }
            Button("New folder\u{2026}", systemImage: "folder.badge.plus") {
                selected = [set.id]; naming = .folder
            }
            if set.folderId != nil {
                Divider()
                Button("Remove from folder", systemImage: "folder.badge.minus") {
                    store.move(set.id, to: nil)
                }
            }
        }
        if set.kind != .anki {
            Button("Export PDF", systemImage: "arrow.down.doc") { export(set) }
        }
        if set.kind == .anki {
            Button("Export Anki deck (.apkg)", systemImage: "square.and.arrow.up") {
                if let url = try? ApkgExporter.export(set) { exportURL = url }
                else { exportFailedSetName = set.name }
            }
        }
        Button("Share as JSON", systemImage: "doc.text") {
            if let url = JSONExporter.export(set) { exportURL = url }
            else { exportFailedSetName = set.name }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { store.deleteSet(set.id) }
    }

    /// The floating action bar shown in selection mode.
    var selectionBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                Text(selected.isEmpty ? "Select sets" : "\(selected.count) selected")
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button { naming = .folder } label: {
                    Label("Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.glass)
                .disabled(selected.isEmpty)
                Button { naming = .combine } label: {
                    Label("Combine", systemImage: "square.stack.3d.down.forward")
                }
                .buttonStyle(.glassProminent)
                .disabled(!canCombine)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(.horizontal, 10).padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    func setRow(_ set: StudySet) -> some View {
        let due = set.kind == .anki ? reviews.dueCount(for: set.cards) : 0
        return HStack(spacing: 14) {
            ModeTile(kind: set.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(set.name).font(.body.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(set.kind.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(set.kind.tint)
                    Text("\u{00b7}").foregroundStyle(.tertiary)
                    Text("\(set.itemCount) \(set.itemNoun)\(set.itemCount == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                    if !set.subject.isEmpty && set.subject != "General" {
                        Text("\u{00b7}").foregroundStyle(.tertiary)
                        Text(set.subject).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if due > 0 {
                Text("\(due)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(StudySetKind.anki.tint, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            HStack(spacing: -10) {
                ForEach([StudySetKind.mcq, .anki, .qa], id: \.self) { kind in
                    ModeTile(kind: kind, size: 56)
                        .rotationEffect(.degrees(kind == .anki ? 0 : (kind == .mcq ? -10 : 10)))
                }
            }
            Text("Nothing here yet").font(.title2.weight(.bold))
            Text("Make an MCQ quiz, an Anki deck, a textbook, a case set, an OSCE checklist, or a narrated transcript \u{2014} all of it stays on this phone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { showNewSet = true } label: {
                Label("New set", systemImage: "plus").padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
