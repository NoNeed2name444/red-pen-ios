import SwiftUI

// MARK: - The collapsible floating switcher
//
// One floating glass strip at the bottom of a screen for choosing between a
// few views of the same thing - Ideas' List / Board / Space, the reader's
// Document / Page - under the thumb, instead of a segmented control up in
// the navigation bar. It folds away into one small glass circle (showing
// what is chosen) and opens again with a tap; a long press on the circle
// chooses without opening it.
//
// The caller decides where each state sits: the expanded strip usually on
// its own row above a bar, the circle at the leading end of that bar.
//
// At the accessibility text sizes the strip's names would shrink past
// reading, so it stays the circle, and a tap opens every choice as a list in
// a sheet, one to a row, with room for the whole name.

struct SwitcherItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let symbol: String
    /// The segment's accessibility identifier.
    let identifier: String
    var id: String { identifier }

    init(value: Value, title: String, symbol: String, identifier: String) {
        self.value = value
        self.title = title
        self.symbol = symbol
        self.identifier = identifier
    }
}

struct FloatingSwitcher<Value: Hashable>: View {
    let items: [SwitcherItem<Value>]
    @Binding var selection: Value
    @Binding var collapsed: Bool
    /// The identifier of the collapse button AND of the collapsed circle.
    let toggleIdentifier: String
    var tint: Color = .accentColor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var liftSpace
    /// The list of choices, open at the accessibility text sizes.
    @State private var listing = false

    init(items: [SwitcherItem<Value>], selection: Binding<Value>, collapsed: Binding<Bool>,
         toggleIdentifier: String, tint: Color = .accentColor) {
        self.items = items
        self._selection = selection
        self._collapsed = collapsed
        self.toggleIdentifier = toggleIdentifier
        self.tint = tint
    }

    private var change: Animation? { reduceMotion ? nil : .snappy(duration: 0.3) }

    private var chosen: SwitcherItem<Value>? {
        items.first { $0.value == selection }
    }

    private func choose(_ value: Value) {
        withAnimation(change) { selection = value }
    }

    private func setCollapsed(_ now: Bool) {
        withAnimation(change) { collapsed = now }
    }

    var body: some View {
        let large: Bool = typeSize.isAccessibilitySize
        Group {
            if collapsed || large {
                SwitcherBubble(items: items, chosen: chosen, tint: tint,
                               identifier: toggleIdentifier,
                               expand: { if large { listing = true } else { setCollapsed(false) } },
                               choose: choose)
                    .transition(.growFade(0.6))
            } else {
                SwitcherStrip(items: items, selection: selection, tint: tint,
                              identifier: toggleIdentifier, liftSpace: liftSpace,
                              collapse: { setCollapsed(true) },
                              choose: choose)
                    .transition(.growFade(0.9))
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .sheet(isPresented: $listing) {
            SwitcherListSheet(items: items, selection: selection, tint: tint, choose: choose)
        }
    }
}

/// Every choice as a list, one to a row - the switcher at the accessibility
/// text sizes.
private struct SwitcherListSheet<Value: Hashable>: View {
    let items: [SwitcherItem<Value>]
    let selection: Value
    let tint: Color
    let choose: (Value) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(items) { item in
                row(item)
            }
            .navigationTitle("Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ item: SwitcherItem<Value>) -> some View {
        let chosen: Bool = item.value == selection
        return Button {
            choose(item.value)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: item.symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if chosen {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
        .accessibilityIdentifier(item.identifier)
    }
}

/// The expanded strip: every choice, and a chevron to fold it away.
private struct SwitcherStrip<Value: Hashable>: View {
    let items: [SwitcherItem<Value>]
    let selection: Value
    let tint: Color
    let identifier: String
    let liftSpace: Namespace.ID
    let collapse: () -> Void
    let choose: (Value) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        GlassEffectContainer {
            HStack(spacing: 2) {
                ForEach(items) { item in
                    SwitcherSegment(item: item, chosen: item.value == selection, tint: tint,
                                    liftSpace: liftSpace) {
                        choose(item.value)
                    }
                }
                SwitcherCollapseButton(identifier: identifier, action: collapse)
            }
            .padding(5)
        }
        .liquidGlassPanel(cornerRadius: 26)
        .popOut(.floating, in: shape)
    }
}

private struct SwitcherSegment<Value: Hashable>: View {
    let item: SwitcherItem<Value>
    let chosen: Bool
    let tint: Color
    let liftSpace: Namespace.ID
    let action: () -> Void

    var body: some View {
        let ink: Color = chosen ? tint : Color.secondary
        let shape = RoundedRectangle(cornerRadius: 21, style: .continuous)
        let traits: AccessibilityTraits = chosen ? .isSelected : []
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .scaledFont(17, relativeTo: .body, weight: .semibold, maxSize: 28)
                Text(item.title)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .frame(minWidth: 64, minHeight: 48)
            .background {
                if chosen {
                    SwitcherLift(shape: shape, tint: tint, liftSpace: liftSpace)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier(item.identifier)
    }
}

/// The soft capsule behind the chosen segment, which travels between them.
private struct SwitcherLift: View {
    let shape: RoundedRectangle
    let tint: Color
    let liftSpace: Namespace.ID

    // With Reduce Motion the choice changes without an animation, so the
    // lift jumps rather than travels.
    var body: some View {
        shape
            .fill(tint.opacity(0.14))
            .matchedGeometryEffect(id: "switcherLift", in: liftSpace)
    }
}

private struct SwitcherCollapseButton: View {
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .scaledFont(14, relativeTo: .body, weight: .bold, maxSize: 24)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Hide the switcher")
        .accessibilityIdentifier(identifier)
    }
}

/// The folded state: one glass circle showing what is chosen.
private struct SwitcherBubble<Value: Hashable>: View {
    let items: [SwitcherItem<Value>]
    let chosen: SwitcherItem<Value>?
    let tint: Color
    let identifier: String
    let expand: () -> Void
    let choose: (Value) -> Void

    var body: some View {
        let symbol: String = chosen?.symbol ?? "square.grid.2x2"
        let title: String = chosen?.title ?? ""
        let label: String = "Show the switcher, now \(title)"
        Button(action: expand) {
            Image(systemName: symbol)
                .scaledFont(18, relativeTo: .body, weight: .semibold, maxSize: 28)
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .overlay(alignment: .topTrailing) { SwitcherBadge() }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibleGlass(.regular.interactive(), in: Circle())
        .contextMenu {
            ForEach(items) { item in
                Button {
                    choose(item.value)
                } label: {
                    Label(item.title, systemImage: item.symbol)
                }
            }
        }
        .accessibilityLabel(label)
        .accessibilityHint("Tap to show every view. Hold to switch straight away.")
        .accessibilityIdentifier(identifier)
        .popOut(.floating, in: Circle())
    }
}

private struct SwitcherBadge: View {
    var body: some View {
        Image(systemName: "chevron.up")
            .scaledFont(7, relativeTo: .caption2, weight: .heavy, maxSize: 11)
            .foregroundStyle(.secondary)
            .padding(3)
            .background(.thinMaterial, in: Circle())
            .offset(x: -2, y: 2)
            .accessibilityHidden(true)
    }
}
