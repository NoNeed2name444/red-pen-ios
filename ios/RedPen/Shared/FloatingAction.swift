import SwiftUI

/// A screen's main button that stays in reach: while the real button is
/// scrolled out of sight a copy floats at the bottom of the screen, and when
/// the student scrolls down to where it lives the copy goes and the real one
/// takes over in its place.
///
/// The section that owns the button registers what it does (`floatingAction`)
/// and marks the button itself (`floatingActionAnchor`); the screen shows the
/// floating copy only for the section it expects, so a section left behind by
/// switching mode can never leave its button floating. A screen with its own
/// bottom slab puts `FloatingActionButton` in it; any other screen uses
/// `floatingActionBar`, which brings a slab of its own.
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

    /// The copy to float for `expecting`: only while its real button is out
    /// of sight, and never while something is being generated (the progress
    /// card has the bottom then).
    func floating(expecting: String?, busy: Bool) -> Item? {
        guard let expecting, !busy, let item = items[expecting] else { return nil }
        if visible.contains(expecting) { return nil }
        return item
    }
}

extension View {
    /// Registers the section's main action, kept current as its title and
    /// whether it can run change.
    /// `inputs` names everything `run` reads (kind, subject, name...), so the
    /// floating copy never runs with settings the real button has moved past.
    func floatingAction(id: String, title: String, symbol: String = "sparkles",
                        enabled: Bool, inputs: [String] = [], run: @escaping () -> Void) -> some View {
        task(id: ([id, title, String(enabled)] + inputs).joined(separator: "|")) {
            FloatingAction.shared.register(.init(id: id, title: title, symbol: symbol, enabled: enabled, run: run))
        }
    }

    /// Marks the real button, so the floating copy knows when it is on screen.
    func floatingActionAnchor(_ id: String) -> some View {
        onScrollVisibilityChange(threshold: 0.6) { visible in
            FloatingAction.shared.setVisible(id, visible)
        }
    }

    /// Shows the floating copy of the action registered under `expecting`,
    /// in a floating slab of its own at the bottom of the screen.
    func floatingActionBar(expecting id: String?) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { FloatingActionBar(expecting: id) }
    }
}

/// Just the floating copy: the screen's hero button, for a screen that puts
/// it in its own bottom slab. Draws nothing while the real button is in
/// sight, or while something is being generated.
struct FloatingActionButton: View {
    let expecting: String?
    /// A shortcut for the copy - Command S when it is a Save.
    let shortcut: KeyboardShortcut?
    @ObservedObject private var floating = FloatingAction.shared
    @ObservedObject private var generation = GenerationCenter.shared

    init(expecting: String?, shortcut: KeyboardShortcut? = nil) {
        self.expecting = expecting
        self.shortcut = shortcut
    }

    private var shown: FloatingAction.Item? {
        floating.floating(expecting: expecting, busy: generation.job != nil)
    }

    var body: some View {
        let item: FloatingAction.Item? = shown
        let change: Animation = .snappy(duration: 0.25)
        ZStack {
            if let item {
                FloatingActionFace(item: item, shortcut: shortcut)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(change, value: item?.id)
        .animation(change, value: floating.visible)
    }
}

private struct FloatingActionFace: View {
    let item: FloatingAction.Item
    let shortcut: KeyboardShortcut?

    var body: some View {
        Button(action: item.run) {
            Label(item.title, systemImage: item.symbol)
        }
        .buttonStyle(.bigPrimary)
        .disabled(!item.enabled)
        .keyboardShortcut(shortcut)
        .accessibilityIdentifier("floatingAction")
    }
}

/// `floatingActionBar`'s slab: there only while there is a copy to float.
private struct FloatingActionBar: View {
    let expecting: String?
    @ObservedObject private var floating = FloatingAction.shared
    @ObservedObject private var generation = GenerationCenter.shared

    var body: some View {
        let showing: Bool = floating.floating(expecting: expecting, busy: generation.job != nil) != nil
        ZStack {
            if showing {
                StudyActionBar {
                    FloatingActionButton(expecting: expecting)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: showing)
    }
}
