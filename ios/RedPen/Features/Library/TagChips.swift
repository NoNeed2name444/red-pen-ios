import SwiftUI

/// Tags as glass chips: each with its × to take it off, a field to add more
/// (Return, or the plus), and the library's own tags offered underneath as
/// the typing narrows them. For a card, a question or a whole set.
///
/// The rules - no spaces inside a tag, `::` nests, case ignored - are
/// CardTags', so what is typed here matches what came in from Anki.
struct TagChipsField: View {
    @Binding var tags: [String]?
    /// Every tag in the library, most used first, for suggestions.
    var known: [(tag: String, count: Int)] = []
    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let tags, !tags.isEmpty {
                ChipFlow(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        chip(tag)
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Add a tag", text: $typed)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(add)
                    .accessibilityIdentifier("tagField")
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(CardTags.parse(typed).isEmpty)
                .accessibilityLabel("Add tag")
            }
            .popField()
            let offered: [String] = CardTags.suggestions(for: typed, from: known, excluding: tags, limit: 8)
            if !offered.isEmpty && (focused || !typed.isEmpty) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(offered, id: \.self) { tag in
                            Button { take(tag) } label: {
                                Label(CardTags.label(tag), systemImage: "plus")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .liquidGlassChip()
                            .accessibilityLabel("Add tag \(tag)")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func chip(_ tag: String) -> some View {
        HStack(spacing: 6) {
            Text(CardTags.label(tag))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Button { remove(tag) } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .liquidGlassChip()
        .help(tag)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tag \(tag)")
    }

    private func add() {
        tags = CardTags.adding(typed, to: tags)
        typed = ""
    }

    private func take(_ tag: String) {
        tags = CardTags.adding(tag, to: tags)
        typed = ""
    }

    private func remove(_ tag: String) {
        tags = CardTags.removing(tag, from: tags)
    }
}

/// A row of small read-only tag labels, for a card's row in a list.
struct TagLine: View {
    let tags: [String]?
    var limit = 3

    var body: some View {
        if let tags, !tags.isEmpty {
            let shown: [String] = Array(tags.prefix(limit))
            let more: Int = tags.count - shown.count
            HStack(spacing: 4) {
                ForEach(shown, id: \.self) { tag in
                    Text("#" + CardTags.label(tag))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if more > 0 {
                    Text("+\(more)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tags: " + tags.joined(separator: ", "))
        }
    }
}

/// Chips laid out left to right, wrapping onto new lines.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width: CGFloat = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size: CGSize = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var line: CGFloat = 0
        for view in subviews {
            let size: CGSize = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
