import SwiftUI

/// Moving between modes from a dock that floats over the library.
///
/// It sits at the bottom, where a thumb is, rather than at the top where a
/// strip of tabs is a stretch away on a big phone. Each mode gets its icon and
/// its name, the chosen one sits in a lifted capsule and takes its own colour,
/// and a sideways swipe on the list moves one along - so the dock says where
/// you are while the gesture does the moving.
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
        GlassEffectContainer(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(tabs) { tab in
                            item(tab).id(tab.id)
                        }
                    }
                    .padding(5)
                }
                // Room for four before it scrolls: past that the labels are too
                // narrow to read, and a dock you cannot read is a row of dots.
                .frame(maxWidth: 4 * 92 + 10)
                .fixedSize(horizontal: tabs.count <= 4, vertical: false)
                .onChange(of: selection) { _, tab in
                    withAnimation(.snappy) { proxy.scrollTo(tab.id, anchor: .center) }
                }
            }
        }
        .liquidGlassPanel(cornerRadius: 30)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func item(_ tab: LibraryTab) -> some View {
        let chosen = tab == selection
        return Button {
            withAnimation(.snappy(duration: 0.3)) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 21, weight: .semibold))
                        .frame(height: 24)
                    if count(tab) > 0 {
                        Text("\(count(tab))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(tab.tint, in: Capsule())
                            .offset(x: 13, y: -5)
                    }
                }
                Text(tab.title)
                    .font(.footnote.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(chosen ? AnyShapeStyle(tab.tint) : AnyShapeStyle(.secondary))
            .frame(width: 84)
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
