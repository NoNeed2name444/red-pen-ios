import SwiftUI

/// The lecture reader's one bottom container, under the thumb.
///
/// - the floating Document / Page switcher, which folds into a small circle
///   and opens again with a tap (held, it switches without opening);
/// - the page list, as a glass circle at the leading end (left thumb) - on a
///   wide iPad the list is already beside the reader, so it is not here;
/// - in Page view, the pager at the trailing end (right thumb): back, where
///   you are, forward. The arrow keys turn the pages too.
///
/// With the switcher open it has its own row above the other two, so the
/// bar is never wider than a phone; folded, all three share one row.
struct ReaderBar: View {
    @Binding var whole: Bool
    @Binding var page: Int
    let pageCount: Int
    /// "Page" or "Slide".
    let pageNoun: String
    /// Whether the page list button is here (not on a wide iPad, where the
    /// list is beside the reader, nor over Quick Look, which has no pages).
    let showsPages: Bool
    let openPages: () -> Void

    @AppStorage("vignette.reader.switcherCollapsed") private var collapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var modes: [SwitcherItem<Bool>] {
        [SwitcherItem(value: true, title: "Document", symbol: "doc.text", identifier: "readerMode-document"),
         SwitcherItem(value: false, title: "Page", symbol: "doc.richtext", identifier: "readerMode-page")]
    }

    private var switcher: some View {
        FloatingSwitcher(items: modes, selection: $whole, collapsed: $collapsed,
                         toggleIdentifier: "readerSwitcherToggle")
    }

    /// Whether the lower row has anything in it.
    private var hasRow: Bool {
        collapsed || showsPages || !whole
    }

    var body: some View {
        let change: Animation? = reduceMotion ? nil : .snappy(duration: 0.25)
        VStack(spacing: 10) {
            if !collapsed {
                switcher
                    .transition(.opacity)
            }
            if hasRow {
                row
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .animation(change, value: collapsed)
        .animation(change, value: whole)
    }

    private var row: some View {
        HStack(spacing: 10) {
            if showsPages {
                ReaderPagesButton(noun: pageNoun, action: openPages)
            }
            if collapsed {
                switcher
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if !whole {
                ReaderPager(page: $page, count: pageCount, noun: pageNoun)
                    .transition(.slideFade(.trailing))
            }
        }
    }
}

/// Every page, as a list: a 44-point glass circle.
private struct ReaderPagesButton: View {
    let noun: String
    let action: () -> Void

    var body: some View {
        let label: String = "All \(noun.lowercased())s"
        Button(action: action) {
            Image(systemName: "sidebar.squares.left")
                .scaledFont(17, relativeTo: .body, weight: .semibold, maxSize: 26)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibleGlass(.regular.interactive(), in: Circle())
        .popOut(.floating, in: Circle())
        .hoverEffect(.lift)
        .accessibilityLabel(label)
    }
}

/// "‹ Page 3 of 12 ›": a floating glass capsule. The left and right arrow
/// keys turn the pages as well.
private struct ReaderPager: View {
    @Binding var page: Int
    let count: Int
    let noun: String

    private var atStart: Bool { page <= 1 }
    private var atEnd: Bool { page >= count }

    var body: some View {
        let place: String = "\(noun) \(page) of \(count)"
        let before: String = "Previous \(noun.lowercased())"
        let after: String = "Next \(noun.lowercased())"
        HStack(spacing: 0) {
            ReaderPagerArrow(symbol: "chevron.left", label: before, key: .leftArrow,
                             enabled: !atStart) { turn(-1) }
            Text(place)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
                .frame(minWidth: 88)
            ReaderPagerArrow(symbol: "chevron.right", label: after, key: .rightArrow,
                             enabled: !atEnd) { turn(1) }
        }
        .padding(.horizontal, 2)
        .accessibleGlass(.regular, in: Capsule())
        .popOut(.floating, in: Capsule())
    }

    private func turn(_ by: Int) {
        let moved: Int = page + by
        let kept: Int = min(max(1, moved), max(1, count))
        page = kept
    }
}

private struct ReaderPagerArrow: View {
    let symbol: String
    let label: String
    let key: KeyEquivalent
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        let ink: Color = enabled ? Color.primary : Color.secondary.opacity(0.5)
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(16, relativeTo: .body, weight: .semibold, maxSize: 26)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ink)
        .hoverEffect(.highlight)
        .keyboardShortcut(key, modifiers: [])
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
