import SwiftUI

// The ways into the spoken modes from existing screens. Each is one modifier,
// so the screen it is added to changes by a single line.

extension View {
    /// A toolbar button that opens commute mode (Due today).
    func commuteModeButton() -> some View {
        modifier(CommuteModeButton())
    }

    /// Commute mode as a sheet, for a screen that puts its own button to it
    /// where the thumb is - Due today's "Listen" beside Reveal - rather than
    /// up in the toolbar.
    func commuteModeSheet(isPresented: Binding<Bool>) -> some View {
        modifier(CommuteModeSheet(isPresented: isPresented))
    }
}

private struct CommuteModeButton: ViewModifier {
    @State private var open = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { open = true } label: {
                        Label("Commute mode", systemImage: "car.fill")
                    }
                    .accessibilityHint("Reads your due cards and questions aloud and listens for the answers")
                }
            }
            .commuteModeSheet(isPresented: $open)
    }
}

/// The sheet half of commute mode: the spoken session in its own navigation
/// stack, with Close where a sheet keeps it, and the camera kept off while it
/// listens.
private struct CommuteModeSheet: ViewModifier {
    @Binding var isPresented: Bool
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore
    @EnvironmentObject private var llm: LocalLLMService

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    CommuteModeView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { isPresented = false }
                            }
                        }
                }
                .environmentObject(store)
                .environmentObject(reviews)
                .environmentObject(llm)
                .popOutFacePaused()
            }
    }
}
