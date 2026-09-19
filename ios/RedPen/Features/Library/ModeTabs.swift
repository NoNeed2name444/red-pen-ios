import SwiftUI

/// Moving between modes by swiping, the way WhatsApp moves between its chats
/// and its updates.
///
/// The library used to be one undifferentiated list of every set in every
/// mode, and the only way to see just the OSCE stations was to scroll past
/// everything else. A pager fixes that without adding a screen to get lost in:
/// the tabs are always visible, a sideways swipe moves one tab, and the bar
/// underneath the labels slides with the swipe rather than jumping when it
/// ends - which is what makes the gesture feel attached to the content instead
/// of merely triggering it.
///
/// Only the modes the student actually has sets in get a tab. A row of six
/// tabs where four are empty is a menu of disappointments.
struct LibraryTab: Hashable, Identifiable {
    /// nil is the "All" tab - every set, in one list.
    let kind: StudySetKind?

    var id: String { kind?.rawValue ?? "all" }
    var title: String { kind?.label ?? "All" }
    var tint: Color { kind?.tint ?? StudySetKind.mcq.tint }

    static let all = LibraryTab(kind: nil)

    /// The tabs worth showing, in the order the modes are declared.
    static func present(in sets: [StudySet]) -> [LibraryTab] {
        let kinds = Set(sets.map(\.kind))
        guard kinds.count > 1 else { return [] }
        return [.all] + StudySetKind.allCases.filter { kinds.contains($0) }.map { LibraryTab(kind: $0) }
    }
}

/// The tab strip: pills for each mode, with a sliding underline.
struct ModeTabBar: View {
    let tabs: [LibraryTab]
    @Binding var selection: LibraryTab
    /// How many sets sit behind each tab, so a tab says what it holds.
    var count: (LibraryTab) -> Int

    @Namespace private var underline

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs) { tab in
                        button(tab)
                            .id(tab.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
            }
            .onChange(of: selection) { _, tab in
                withAnimation(.snappy) { proxy.scrollTo(tab.id, anchor: .center) }
            }
        }
    }

    private func button(_ tab: LibraryTab) -> some View {
        let chosen = tab == selection
        return Button {
            withAnimation(.snappy(duration: 0.28)) { selection = tab }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(tab.title)
                        .font(.subheadline.weight(chosen ? .semibold : .medium))
                    Text("\(count(tab))")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .opacity(chosen ? 0.9 : 0.55)
                }
                .foregroundStyle(chosen ? AnyShapeStyle(tab.tint) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10)

                // The underline is one shape moved between tabs rather than
                // one per tab shown and hidden, so it travels instead of
                // blinking out here and in again there.
                Group {
                    if chosen {
                        Capsule()
                            .fill(tab.tint)
                            .matchedGeometryEffect(id: "underline", in: underline)
                            .frame(height: 2.5)
                    } else {
                        Capsule().fill(.clear).frame(height: 2.5)
                    }
                }
                .padding(.horizontal, 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.title), \(count(tab)) sets")
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}
