import SwiftUI

/// Moving between modes from a dock that floats over the library.
///
/// It sits at the bottom, where a thumb is, rather than at the top where a
/// strip of tabs is a stretch away on a big phone. Every mode is shown at once
/// as its symbol; the chosen one widens into a lifted capsule, takes its own
/// colour and says its name. A sideways swipe on the list moves one along - so
/// the dock says where you are while the gesture does the moving.
///
/// Only the modes the student actually has sets in get a place. A dock of six
/// where four are empty is a menu of disappointments.
struct LibraryTab: Hashable, Identifiable {
    /// nil is the "All" tab - every set, in one list.
    let kind: StudySetKind?

    var id: String { kind?.rawValue ?? "all" }
    var title: String { kind?.label ?? "All" }
    var tint: Color { kind?.tint ?? StudySetKind.mcq.tint }
    var symbol: String { kind?.symbol ?? "square.stack" }

    static let all = LibraryTab(kind: nil)

    /// The tabs worth showing, in the order the modes are declared.
    static func present(in sets: [StudySet]) -> [LibraryTab] {
        let kinds = Set(sets.map(\.kind))
        guard kinds.count > 1 else { return [] }
        return [.all] + StudySetKind.allCases.filter { kinds.contains($0) }.map { LibraryTab(kind: $0) }
    }
}

/// The dock: one glass capsule holding every mode.
struct ModeDock: View {
    let tabs: [LibraryTab]
    @Binding var selection: LibraryTab
    /// How many sets sit behind each tab, so a tab says what it holds.
    var count: (LibraryTab) -> Int

    @Namespace private var lift

    var body: some View {
        // Every mode is visible at once. The first version let the dock scroll
        // once there were more than four, which hid Cases, OSCE and Narrate off
        // the right-hand edge - a switcher whose options cannot be seen is not
        // a switcher. Only the chosen mode is named; the rest are their symbol,
        // which is what makes seven fit across a phone.
        //
        // Seven modes across a phone is one width; seven across an iPad's
        // 340-point sidebar is another, and the first version only knew the
        // first. In the sidebar the row ran past both edges and clipped the
        // last mode's badge. ViewThatFits tries the roomy row, then a tighter
        // one, and settles on whichever the column can actually hold.
        ViewThatFits(in: .horizontal) {
            row(scale: 1)
            row(scale: 0.86)
            row(scale: 0.74)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func row(scale: CGFloat) -> some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 2 * scale) {
                ForEach(tabs) { tab in
                    item(tab, scale: scale)
                }
            }
            .padding(5)
        }
        .liquidGlassPanel(cornerRadius: 30)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func item(_ tab: LibraryTab, scale: CGFloat) -> some View {
        let chosen = tab == selection
        return Button {
            withAnimation(.snappy(duration: 0.3)) { selection = tab }
        } label: {
            HStack(spacing: 6 * scale) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 19 * scale, weight: .semibold))
                        .frame(width: 26 * scale, height: 24)
                    if count(tab) > 0 {
                        Text("\(count(tab))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(chosen ? AnyShapeStyle(.white)
                                                    : AnyShapeStyle(.secondary))
                            .padding(.horizontal, 3.5).padding(.vertical, 0.5)
                            // Grey unless this is the mode you are in: a
                            // coloured pip on every icon reads as six unread
                            // notifications rather than as six counts.
                            .background(chosen ? AnyShapeStyle(tab.tint)
                                               : AnyShapeStyle(.quaternary), in: Capsule())
                            .offset(x: 11 * scale, y: -6)
                    }
                }
                if chosen {
                    Text(tab.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            // Grey on grey made a stethoscope and a clipboard indistinguishable
            // at 19 points. Each mode keeps its own hue when it is not chosen,
            // just quietly: identifiable without competing with the one you are
            // actually in.
            .foregroundStyle(chosen ? AnyShapeStyle(tab.tint)
                                    : AnyShapeStyle(tab.tint.opacity(0.55)))
            .padding(.horizontal, (chosen ? 13 : 9) * scale)
            .padding(.vertical, 9)
            .background {
                // One capsule that moves between the tabs rather than one per
                // tab shown and hidden: it travels with the choice instead of
                // blinking out here and in again there.
                if chosen {
                    Capsule()
                        .fill(tab.tint.opacity(0.14))
                        .matchedGeometryEffect(id: "chosen", in: lift)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.title), \(count(tab)) sets")
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}
