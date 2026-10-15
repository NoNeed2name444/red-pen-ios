#if canImport(SwiftUI)
import SwiftUI

/// Every Ward control in each of its states, for one section, drawn with the
/// real styles (WardControls, PopTileStyle): the states gallery, a preview
/// screen (`-uiPreviewScreen states -uiPreviewSection <section>`), shot in
/// light and dark for each section by the Ward preview.
///
/// Three columns: at rest, held (drawn held through `wardShowsPressed`, with
/// no finger on it) and disabled. A control that can be chosen has two rows,
/// not chosen and chosen, so its six states (WardControlStates) are all on
/// one screen. WardStatesTests checks the same states' colours for every
/// section and mode on Linux.
struct WardStatesGallery: View {
    let section: WardSection

    /// A column of the gallery: the state its controls are drawn in.
    enum Column: CaseIterable {
        case rest, held, disabled

        var title: String {
            switch self {
            case .rest: return "Rest"
            case .held: return "Held"
            case .disabled: return "Disabled"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("States · \(section.galleryTitle)")
                    .wardSmallCaps()
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, WardSpace.s)
                HStack(spacing: WardSpace.s) {
                    ForEach(Column.allCases, id: \.self) { column in
                        Text(column.title)
                            .wardSmallCaps()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, WardSpace.m)

                VStack(spacing: WardSpace.s) {
                    states { Button("Start") {}.buttonStyle(.wardPrimary) }
                    states { Button("Skip") {}.buttonStyle(.wardSecondary) }
                    states { Button("Delete") {}.buttonStyle(.wardDestructive) }
                    states { Button("Done") {}.buttonStyle(.wardCompact) }
                    states { Button("Cancel") {}.buttonStyle(.wardQuiet) }
                }
                .padding(.bottom, WardSpace.l)

                VStack(spacing: WardSpace.s) {
                    states { chipAndCircle(chosen: false) }
                    states { chipAndCircle(chosen: true) }
                }
                .padding(.bottom, WardSpace.l)

                VStack(spacing: WardSpace.s) {
                    states { toggle(on: false) }
                    states { toggle(on: true) }
                    states {
                        WardSegmented(selection: .constant(0), options: [0, 1]) { option in
                            Image(systemName: option == 0 ? "list.bullet" : "square.grid.2x2")
                                .accessibilityLabel(option == 0 ? "List" : "Grid")
                        }
                    }
                }
                .padding(.bottom, WardSpace.l)

                VStack(spacing: WardSpace.s) {
                    states { tile(chosen: false) }
                    states { tile(chosen: true) }
                }
            }
            .padding(.horizontal, WardSpace.gutter)
            .padding(.vertical, WardSpace.s)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// One row: the control at rest, held and disabled, a column each.
    private func states<Control: View>(@ViewBuilder _ control: @escaping () -> Control) -> some View {
        HStack(spacing: WardSpace.s) {
            ForEach(Column.allCases, id: \.self) { column in
                control()
                    .environment(\.wardShowsPressed, column == .held)
                    .disabled(column == .disabled)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// A chip that is a button and a round button, chosen or not.
    private func chipAndCircle(chosen: Bool) -> some View {
        HStack(spacing: WardSpace.s) {
            Button("Hint") {}
                .buttonStyle(WardChipButtonStyle(on: chosen))
            Button {} label: {
                Image(systemName: "plus")
            }
            .buttonStyle(WardCircleButtonStyle(on: chosen))
            .accessibilityLabel("Add")
        }
    }

    /// The switch alone, its label hidden: the track sits where it would at
    /// the end of a row.
    private func toggle(on: Bool) -> some View {
        Toggle(isOn: .constant(on)) { Text("Timed") }
            .labelsHidden()
            .fixedSize()
            .frame(width: 52, alignment: .trailing)
    }

    /// A tile on the raised plane, chosen or not, with a label that colours
    /// itself as the app's tiles do: Chart Ink words and a glyph in the
    /// accent, Biro Grey when disabled.
    private func tile(chosen: Bool) -> some View {
        Button {} label: {
            WardStatesTileLabel(title: section.galleryTitle, symbol: section.gallerySymbol)
        }
        .buttonStyle(PopTileStyle(cornerRadius: WardRadius.card, selected: chosen))
    }
}

private struct WardStatesTileLabel: View {
    let title: String
    let symbol: String
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        VStack(spacing: WardSpace.xs) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(enabled ? Color.wardPrimaryInk : Color.wardDisabledInk)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(enabled ? Color.wardInk : Color.wardDisabledInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, WardSpace.s)
        .frame(maxWidth: .infinity, minHeight: 64)
    }
}

private extension WardSection {
    /// The section's name, for the gallery's heading and its tile.
    var galleryTitle: String {
        switch self {
        case .questions: return "Questions"
        case .cards: return "Cards"
        case .textbook: return "Textbook"
        case .cases: return "Cases"
        case .osce: return "OSCE"
        case .audio: return "Audio"
        case .ideas: return "Ideas"
        }
    }

    /// The section's glyph, as its mode shows it (StudySetKind.symbol).
    var gallerySymbol: String {
        switch self {
        case .questions: return "checklist.checked"
        case .cards: return "rectangle.on.rectangle.angled"
        case .textbook: return "book.pages"
        case .cases: return "stethoscope"
        case .osce: return "list.clipboard"
        case .audio: return "waveform"
        case .ideas: return "lightbulb"
        }
    }
}
#endif
