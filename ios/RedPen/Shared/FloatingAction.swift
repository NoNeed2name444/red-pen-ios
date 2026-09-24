import SwiftUI

/// A screen's main button that stays in reach: while the real button is
/// scrolled out of sight a copy floats at the bottom of the screen, and when
/// the student scrolls down to where it lives the copy goes and the real one
/// takes over in its place.
///
/// The section that owns the button registers what it does (`floatingAction`)
/// and marks the button itself (`floatingActionAnchor`); the screen shows the
/// floating copy (`floatingActionBar`) only for the section it expects, so a
/// section left behind by switching mode can never leave its button floating.
@MainActor
final class FloatingAction: ObservableObject {
    static let shared = FloatingAction()

    struct Item {
        let id: String
        var title: String
        var symbol: String
        var enabled: Bool
        var run: () -> Void
    }

    @Published private(set) var items: [String: Item] = [:]
    /// Which real buttons are on screen. A button counts as off screen until
    /// it reports in: in a long form its row may not even exist yet.
    @Published private(set) var visible: Set<String> = []

    func register(_ new: Item) { items[new.id] = new }

    func setVisible(_ id: String, _ isVisible: Bool) {
        if isVisible { visible.insert(id) } else { visible.remove(id) }
    }

    func clear() {
        items = [:]
        visible = []
    }
}

extension View {
    /// Registers the section's main action, kept current as its title and
    /// whether it can run change.
    func floatingAction(id: String, title: String, symbol: String = "sparkles",
                        enabled: Bool, run: @escaping () -> Void) -> some View {
        task(id: "\(id)|\(title)|\(enabled)") {
            FloatingAction.shared.register(.init(id: id, title: title, symbol: symbol, enabled: enabled, run: run))
        }
    }

    /// Marks the real button, so the floating copy knows when it is on screen.
    func floatingActionAnchor(_ id: String) -> some View {
        onScrollVisibilityChange(threshold: 0.6) { visible in
            FloatingAction.shared.setVisible(id, visible)
        }
    }

    /// Shows the floating copy of the action registered under `expecting`.
    func floatingActionBar(expecting id: String?) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { FloatingActionBar(expecting: id) }
    }
}

private struct FloatingActionBar: View {
    let expecting: String?
    @ObservedObject private var floating = FloatingAction.shared
    @ObservedObject private var generation = GenerationCenter.shared

    private var shown: FloatingAction.Item? {
        guard let expecting, let item = floating.items[expecting],
              !floating.visible.contains(expecting), generation.job == nil else { return nil }
        return item
    }

    var body: some View {
        ZStack {
            if let item = shown {
                Button(action: item.run) {
                    Label(item.title, systemImage: item.symbol)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .disabled(!item.enabled)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .frame(maxWidth: 560)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("floatingAction")
            }
        }
        .animation(.snappy(duration: 0.25), value: shown?.id)
        .animation(.snappy(duration: 0.25), value: floating.visible)
    }
}
