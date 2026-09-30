import SwiftUI

/// What a picked deck or table will add, before anything is added: the
/// figures as glass tiles ("412 cards", "38 pictures", "3 subdecks → 3
/// sets"), the sets it becomes, anything left out and why, and one Import
/// tile. Cancel leaves the library exactly as it was.
struct ImportPreviewSheet: View {
    let preview: ImportPreview
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false

    /// The most set rows listed before "and N more".
    private let listed = 12

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    facts
                    setsList
                    if !preview.notes.isEmpty { notes }
                    importTile
                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(ModeBackdrop(kind: kind))
            .tint(kind.tint)
            .environment(\.modeTint, kind.tint)
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .accessibilityIdentifier("importPreview")
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(importing)
    }

    private var kind: StudySetKind { preview.sets.first?.kind ?? .anki }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: preview.source.symbol)
                .font(.title2)
                .foregroundStyle(kind.tint)
                .frame(width: 48, height: 48)
                .liquidGlassChip(tint: kind.tint, plane: .raised)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                Text("Nothing is added until you tap Import.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var facts: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
            ForEach(preview.facts, id: \.self) { fact in
                factTile(fact)
            }
        }
    }

    private func factTile(_ fact: ImportFact) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: fact.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(kind.tint)
            Text(fact.value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(fact.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassPanel(cornerRadius: 16, plane: .raised)
        .accessibilityElement(children: .combine)
    }

    private var setsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.sets.count == 1 ? "Your new set" : "Your new sets")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(preview.sets.prefix(listed).enumerated()), id: \.offset) { index, set in
                    if index > 0 { Divider().padding(.leading, 14) }
                    setRow(set, folder: folderName(at: index))
                }
                if preview.sets.count > listed {
                    Divider().padding(.leading, 14)
                    Text("and \(preview.sets.count - listed) more")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .liquidGlassPanel(cornerRadius: 16, plane: .raised)
        }
    }

    private func folderName(at index: Int) -> String? {
        preview.folderNames.indices.contains(index) ? preview.folderNames[index] : nil
    }

    private func setRow(_ set: StudySet, folder: String?) -> some View {
        let count: Int = set.itemCount
        let noun: String = count == 1 ? set.itemNoun : set.itemNoun + "s"
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let folder {
                    Label(folder, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text("\(count.formatted()) \(noun)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(preview.notes, id: \.self) { line in
                Label(line, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The one tile that adds everything.
    private var importTile: some View {
        let count: Int = preview.itemCount
        let noun: String = kind == .mcq ? (count == 1 ? "question" : "questions") : (count == 1 ? "card" : "cards")
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button {
            guard !importing else { return }
            importing = true
            onImport()
        } label: {
            HStack(spacing: 12) {
                if importing {
                    ProgressView()
                } else {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.title3)
                }
                Text(importing ? "Adding\u{2026}" : "Import \(count.formatted()) \(noun)")
                    .font(.headline)
            }
            .foregroundStyle(kind.tint)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(kind.tint.opacity(0.14), in: shape)
            .overlay(shape.strokeBorder(kind.tint.opacity(0.5), lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(PopTileStyle(cornerRadius: 18, plane: .floating, tint: kind.tint))
        .disabled(importing)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("importConfirm")
    }
}
