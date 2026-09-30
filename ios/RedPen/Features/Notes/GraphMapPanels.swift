import SwiftUI

// The Ideas map's own panels over the SceneKit view (Graph3DView): the peek
// card a tap brings up, a body's options (held still on it), the pickers
// its options open, and the Link length bar from the Look menu. The
// decisions behind them are GraphTouchModel.swift's.

/// Something the map is asked to do from SwiftUI (a link chip, Show links,
/// Fly in, a selection kept across a rebuild). `serial` tells a new request
/// from the one already done.
struct GraphMapCommand: Equatable {
    enum Kind: Equatable {
        case none
        case select(UUID, glide: Bool)
        case clear
        case links(UUID?)
        case flyIn(UUID)
        /// The design preview: a body held still, as a finger would.
        case previewHold(UUID)
    }

    var kind: Kind = .none
    var serial: Int = 0

    mutating func send(_ next: Kind) {
        kind = next
        serial += 1
    }
}

/// A note opened from the map (the sheet's item).
struct GraphReading: Identifiable, Equatable {
    let id: UUID
}

/// A body whose options are up, and where on screen it was held (nil:
/// from the card's More).
struct GraphOptionsTarget: Identifiable, Equatable {
    let id: UUID
    let folder: Bool
    let home: Bool
    var point: CGPoint? = nil
}

// MARK: - The peek card

/// A small glass card at the bottom: what the chosen body is, its first
/// lines and its links (a note), or its counts and latest notes (a
/// folder). Tap it, swipe it up or press Open to read it.
struct GraphPeekCardView: View {
    static let zoomID: String = "graphPeek"

    let content: GraphPeekContent
    let folder: Bool
    let linksShown: Bool
    var zoom: Namespace.ID?
    let open: () -> Void
    let showLinks: () -> Void
    let flyIn: () -> Void
    let chip: (UUID) -> Void
    /// The body's options (More).
    let more: [String]
    let option: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(Array(content.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !content.chips.isEmpty { chipRow }
            buttons
        }
        .padding(16)
        .frame(maxWidth: 520, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture(perform: open)
        .simultaneousGesture(swipeUp)
        .modifier(GraphZoomSource(zoom: zoom))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(content.spoken)
        .accessibilityAction(named: Text(content.primary), open)
        .accessibilityIdentifier("graphPeekCard")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityIdentifier("graphPeekTitle")
                Text(content.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(content.chips, id: \.id) { item in
                    Button {
                        chip(item.id)
                    } label: {
                        Text(item.title)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .accessibilityHint("Selects it on the map")
                }
                if content.moreLinks > 0 {
                    Text("+\(content.moreLinks) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 8) {
            Button(content.primary, systemImage: folder ? "folder" : "doc.text", action: open)
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("graphPeekOpen")
            if folder {
                Button("Fly in", systemImage: "scope", action: flyIn)
                    .buttonStyle(.glass)
            } else {
                Button(linksShown ? "All links" : "Show links", systemImage: "point.3.connected.trianglepath.dotted",
                       action: showLinks)
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("graphPeekLinks")
                Menu {
                    ForEach(more.filter { $0 != "Open" }, id: \.self) { item in
                        let role: ButtonRole? = item == "Delete" ? ButtonRole.destructive : nil
                        Button(item, role: role) { option(item) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 36, height: 34)
                        .contentShape(Capsule())
                }
                .glassEffect(.regular.interactive(), in: Capsule())
                .accessibilityLabel("More")
            }
        }
        .lineLimit(1)
    }

    private var swipeUp: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                if value.translation.height < -40 { open() }
            }
    }
}

/// The card is where the opened note grows from (a zoom transition).
private struct GraphZoomSource: ViewModifier {
    let zoom: Namespace.ID?

    func body(content: Content) -> some View {
        if let zoom {
            content.matchedTransitionSource(id: GraphPeekCardView.zoomID, in: zoom)
        } else {
            content
        }
    }
}

// MARK: - A body's options

/// The options held on a body, as a glass list next to where it was held.
struct GraphNodeMenuView: View {
    let title: String
    let items: [String]
    let pick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            ForEach(items, id: \.self) { item in
                let role: ButtonRole? = item == "Delete" ? ButtonRole.destructive : nil
                Divider()
                Button(role: role) {
                    pick(item)
                } label: {
                    Label(item, systemImage: Self.symbol(item))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(item == "Delete" ? Color.red : Color.primary)
            }
        }
        .frame(width: 230)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("graphNodeMenu")
    }

    static func symbol(_ item: String) -> String {
        switch item {
        case "Open", "Open folder": return "doc.text"
        case "Rename": return "pencil"
        case "Link to\u{2026}": return "link"
        case "Move to folder\u{2026}": return "folder"
        case "Add note here": return "plus"
        case "Delete": return "trash"
        default: return "circle"
        }
    }
}

// MARK: - Pickers

/// Link to…: every other note, searchable; picking one links them.
struct GraphNotePicker: View {
    @EnvironmentObject private var notes: NoteStore
    @Environment(\.dismiss) private var dismiss
    let from: UUID
    @State private var query: String = ""

    var body: some View {
        NavigationStack {
            List(found) { note in
                Button {
                    notes.link(from, note.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                        Spacer()
                        if notes.isLinked(from, note.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Linked")
                        }
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle("Link to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var found: [Note] {
        let others: [Note] = notes.notes.filter { $0.id != from }
        let q: String = query.trimmingCharacters(in: .whitespaces).lowercased()
        let kept: [Note] = q.isEmpty ? others : others.filter { $0.title.lowercased().contains(q) }
        return kept.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

/// Move to folder…: no folder, or any folder (indented as in the List).
struct GraphFolderPicker: View {
    @EnvironmentObject private var notes: NoteStore
    @Environment(\.dismiss) private var dismiss
    let note: UUID

    var body: some View {
        NavigationStack {
            List {
                Button("No folder") { move(to: nil) }
                ForEach(Array(notes.folderOutline().enumerated()), id: \.offset) { _, entry in
                    Button(IdeasView.indented(entry.folder.name, depth: entry.depth)) { move(to: entry.folder.id) }
                }
            }
            .navigationTitle("Move to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func move(to folder: UUID?) {
        notes.move(note, to: folder)
        dismiss()
    }
}

// MARK: - Link length

/// The Look menu's Link length: a slider from Shorter to Longer over the
/// map, the same stored value as Settings > Look and feel. The map is
/// rebuilt when the finger lifts (or a step button is pressed), each body
/// gliding to its new place.
struct GraphLinkLengthBar: View {
    @Binding var value: Double
    let done: () -> Void
    @State private var dragging: Double?

    var body: some View {
        let shown: Double = dragging ?? value
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Link length")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(GraphLinkLength.spoken(shown))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Done", action: done)
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("linkLengthDone")
            }
            HStack(spacing: 10) {
                Button {
                    commit(shown - GraphLinkLength.step)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shorter")
                Slider(value: slider, in: GraphLinkLength.shortest...GraphLinkLength.longest,
                       step: GraphLinkLength.step) {
                    Text("Link length")
                } minimumValueLabel: {
                    Text("Shorter").font(.caption2)
                } maximumValueLabel: {
                    Text("Longer").font(.caption2)
                } onEditingChanged: { editing in
                    if !editing, let held = dragging {
                        dragging = nil
                        commit(held)
                    }
                }
                .accessibilityValue(GraphLinkLength.spoken(shown))
                .accessibilityIdentifier("linkLengthSlider")
                Button {
                    commit(shown + GraphLinkLength.step)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Longer")
            }
        }
        .padding(14)
        .frame(maxWidth: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("linkLengthBar")
    }

    /// While dragging only the label follows; the map is rebuilt on lift.
    private var slider: Binding<Double> {
        Binding<Double>(
            get: { dragging ?? value },
            set: { dragging = $0 }
        )
    }

    private func commit(_ next: Double) {
        let clamped: Double = GraphLinkLength.clamped(next)
        if clamped != value { value = clamped }
    }
}

/// Which themes' first-run card has shown the touch lines.
enum GraphMapTouch {
    static let seenKey: String = "vignette.space.touchHintSeen"

    static func seen(_ raw: String, _ theme: GraphTheme) -> Bool {
        raw.split(separator: ",").contains { String($0) == theme.rawValue }
    }

    static func marking(_ raw: String, _ theme: GraphTheme) -> String {
        if seen(raw, theme) { return raw }
        return raw.isEmpty ? theme.rawValue : raw + "," + theme.rawValue
    }
}
