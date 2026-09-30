import SwiftUI

/// One line under anything the app wrote with AI: it is for studying, not for
/// deciding anything about a patient, and it can be wrong. Taps through to
/// the worker's /medical page, which says the same at length.
///
/// Not placed on any screen yet (P0.2 only adds it); P2.9 and the paywall
/// work place it, so no screenshot changes before then.
struct EducationFootnote: View {
    var body: some View {
        Link(destination: LegalLinks.url(.medical)) {
            Label("For study only, not for clinical decisions. AI can be wrong.",
                  systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the medical notice")
    }
}

/// A small banner over a practice case: the patient is simulated, and the
/// case is study material, not a real consultation.
struct SimulatedPatientBanner: ViewModifier {
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            Label("Simulated patient \u{2014} for study, not for clinical decisions.",
                  systemImage: "theatermasks")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
                .accessibilityIdentifier("simulatedPatientBanner")
        }
    }
}

extension View {
    /// Marks a case screen as a simulated patient.
    func simulatedPatientBanner() -> some View {
        modifier(SimulatedPatientBanner())
    }
}
