import SwiftUI

// The ways into the spoken modes from existing screens. Each is one modifier,
// so the screen it is added to changes by a single line.

extension View {
    /// A toolbar button that opens commute mode (Due today).
    func commuteModeButton() -> some View {
        modifier(CommuteModeButton())
    }

    /// A toolbar button that opens a spoken session for this station (the
    /// OSCE drill). Nothing is shown when there is no station.
    func spokenPatientButton(for station: OsceChecklist?) -> some View {
        modifier(SpokenPatientButton(station: station))
    }
}

private struct CommuteModeButton: ViewModifier {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore
    @EnvironmentObject private var llm: LocalLLMService
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
            .sheet(isPresented: $open) {
                NavigationStack {
                    CommuteModeView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { open = false }
                            }
                        }
                }
                .environmentObject(store)
                .environmentObject(reviews)
                .environmentObject(llm)
            }
    }
}

private struct SpokenPatientButton: ViewModifier {
    let station: OsceChecklist?
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var llm: LocalLLMService
    @State private var open: OsceChecklist?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if let station {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { open = station } label: {
                            Label("Practise with a spoken patient", systemImage: "person.wave.2")
                        }
                    }
                }
            }
            .sheet(item: $open) { station in
                NavigationStack {
                    SpokenStationView(station: station)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { open = nil }
                            }
                        }
                }
                .environmentObject(store)
                .environmentObject(llm)
            }
    }
}
