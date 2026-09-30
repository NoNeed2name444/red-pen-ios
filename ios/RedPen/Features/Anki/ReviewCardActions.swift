import SwiftUI

/// "Undo" for a few seconds after each rating: a small glass capsule, the same
/// material as the floating switcher, at the top corner of the card. It is
/// shown by a timestamp rather than an animation, so nothing runs while it
/// waits; it simply goes when the time is up or the next card is rated.
struct ReviewUndoChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Undo", systemImage: "arrow.uturn.backward")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .popOut(.floating, in: Capsule())
        // Cmd-Z, as anywhere else
        .keyboardShortcut("z", modifiers: .command)
        .accessibilityLabel("Undo last rating")
        .accessibilityHint("Brings the last card back as it was")
        .accessibilityIdentifier("reviewUndo")
    }
}

extension View {
    /// The undo chip over this view's top trailing corner while `until` is
    /// in the future; it clears `until` itself when the time is up.
    func reviewUndoChip(until: Binding<Date?>, action: @escaping () -> Void) -> some View {
        modifier(ReviewUndoOverlay(until: until, action: action))
    }

    /// Hold a card (or swipe it sideways) for Bury until tomorrow and Suspend.
    func reviewCardActions(onBury: @escaping () -> Void,
                           onSuspend: @escaping () -> Void) -> some View {
        modifier(ReviewCardActionsModifier(onBury: onBury, onSuspend: onSuspend))
    }
}

private struct ReviewUndoOverlay: ViewModifier {
    @Binding var until: Date?
    let action: () -> Void

    /// How long Undo stays in reach.
    static let seconds: Double = 5

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if until != nil {
                    ReviewUndoChip(action: action)
                        .padding(.top, 8)
                        .padding(.trailing, 16)
                        .transition(.opacity)
                }
            }
            .animation(.snappy(duration: 0.2), value: until)
            .task(id: until) {
                guard let shown = until else { return }
                let wait: Double = shown.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, until == shown else { return }
                until = nil
            }
    }
}

private struct ReviewCardActionsModifier: ViewModifier {
    let onBury: () -> Void
    let onSuspend: () -> Void
    @State private var asking = false

    /// A sideways swipe at least this long, and clearly more sideways than
    /// down, asks; anything shorter is a scroll or a tap.
    static let swipe: CGFloat = 90

    func body(content: Content) -> some View {
        content
            .contextMenu {
                buryButton
                suspendButton
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    let dx: CGFloat = abs(value.translation.width)
                    let dy: CGFloat = abs(value.translation.height)
                    if dx > Self.swipe && dx > dy * 2 { asking = true }
                }
            )
            .confirmationDialog("This card", isPresented: $asking, titleVisibility: .hidden) {
                buryButton
                suspendButton
                Button("Cancel", role: .cancel) {}
            }
            .accessibilityAction(named: "Bury until tomorrow", onBury)
            .accessibilityAction(named: "Suspend card", onSuspend)
    }

    private var buryButton: some View {
        Button(action: onBury) {
            Label("Bury until tomorrow", systemImage: "moon.zzz")
        }
    }

    private var suspendButton: some View {
        Button(role: .destructive, action: onSuspend) {
            Label("Suspend card", systemImage: "pause.circle")
        }
    }
}
