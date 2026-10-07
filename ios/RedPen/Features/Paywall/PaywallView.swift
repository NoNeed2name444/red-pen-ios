import SwiftUI
import StoreKit

/// Choosing a plan.
///
/// Prices come from the App Store rather than from this file, because a price
/// written into a button is a price that is wrong in half the world - StoreKit
/// already knows what this costs in the student's own currency, with their own
/// tax in it. The yearly saving is worked out from those two real prices for
/// the same reason: it cannot drift from what is actually charged.
struct PaywallView: View {
    @EnvironmentObject var subscriptions: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.windowSpan) private var span
    @State private var chosen: SubscriptionPlan = .yearly

    private static let title: String = Brand.name + " Pro"
    private static let row = RoundedRectangle(cornerRadius: WardRadius.card, style: .continuous)

    /// A centred sheet, whatever the window behind it: on a wide iPad the
    /// buy bar centres under the plans instead of hugging the trailing edge,
    /// and Subscribe is not capped as it is on a full-width screen.
    private var sheetSpan: WindowSpan { min(span, WindowSpan.middling) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    plans
                    billing
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .wardScreen()
            // buying, restoring and the small print, under the thumb
            .studyBar { buyBar }
            .navigationTitle(PaywallView.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .task { await subscriptions.loadProducts() }
            .onChange(of: subscriptions.isPro) { _, pro in if pro { dismiss() } }
        }
        .environment(\.windowSpan, sheetSpan)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 42))
                .foregroundStyle(Color.wardPrimaryInk)
                .accessibilityHidden(true)
            Text("Everything, from any lecture")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.wardInk)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                perk("doc.text.viewfinder", "Read PDFs, Word and PowerPoint handouts")
                perk("stethoscope", "Doctor-R1, the medical writer, on this device")
                perk("cloud", "\(Brand.name) Cloud: Google's Gemini writes and checks questions and stations on any device")
                perk("checkmark.shield", "Every cloud answer checked for medical accuracy")
                perk("rectangle.dashed", "Turn labelled diagrams into occlusion cards")
                perk("waveform", "Transcribe a recorded lecture, in Arabic or English")
            }
            .padding(.top, 4)
        }
    }

    private func perk(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(Color.wardPrimaryInk)
                .accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(Color.wardInk)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var plans: some View {
        if subscriptions.products.isEmpty {
            // the spinner only while an answer is still to come: trouble
            // (nothing for sale, the App Store unreachable) is shown below
            if subscriptions.trouble == nil {
                EcgLoader().padding(.vertical, 24)
            }
        } else {
            VStack(spacing: 10) {
                ForEach(SubscriptionPlan.allCases) { plan in
                    if let product = subscriptions.product(for: plan) {
                        planRow(plan, product)
                    }
                }
            }
        }
    }

    /// Each plan a soft tile: the chosen one pressed into the base, its mark
    /// in Theatre Blue; the other raised.
    private func planRow(_ plan: SubscriptionPlan, _ product: Product) -> some View {
        let picked: Bool = chosen == plan
        let symbol: String = picked ? "largecircle.fill.circle" : "circle"
        let mark: Color = picked ? Color.wardPrimaryInk : Color.wardInkSecondary
        let traits: AccessibilityTraits = picked ? .isSelected : []
        return Button {
            chosen = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(mark)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.label).font(.body.weight(.semibold)).foregroundStyle(Color.wardInk)
                    if plan == .yearly, let saving = subscriptions.yearlySaving, saving > 0 {
                        Text("Save \(saving)% against monthly")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.wardSuccess)
                    }
                }
                Spacer()
                Text(product.displayPrice)
                    .font(WardType.obs.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.wardInk)
            }
            .padding(14)
            .wardRelief(in: PaywallView.row, lift: .mid, pressed: picked)
            .contentShape(PaywallView.row)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: picked)
        .hoverEffect(.highlight)
        .accessibilityAddTraits(traits)
    }

    /// What the button says: the plan's price when the App Store has sent it.
    private var buyTitle: String {
        guard let product = subscriptions.product(for: chosen) else { return "Subscribe" }
        return "Subscribe \u{00B7} " + product.displayPrice
    }

    private var cannotBuy: Bool {
        subscriptions.busy || subscriptions.product(for: chosen) == nil
    }

    @ViewBuilder
    private var buyBar: some View {
        if let trouble = subscriptions.trouble {
            WardBanner(tone: .danger, symbol: "exclamationmark.triangle.fill", text: trouble)
        }
        Button {
            Task { await subscriptions.buy(chosen) }
        } label: {
            HStack(spacing: 8) {
                if subscriptions.busy { EcgLoader() }
                Text(buyTitle)
            }
        }
        .buttonStyle(.wardPrimary)
        .keyboardShortcut(.defaultAction)
        .disabled(cannotBuy)
        // required in the app itself, not only on a website
        HStack(spacing: 16) {
            Button("Restore") { Task { await subscriptions.restore() } }
                .disabled(subscriptions.busy)
            // served by our own server (server/legal.js), not the retired redpen.app
            Link("Terms", destination: LegalLinks.url(.terms))
            Link("Privacy", destination: LegalLinks.url(.privacy))
        }
        .font(.footnote)
        .buttonStyle(.borderless)
    }

    private var billing: some View {
        Text("Billed through your Apple Account and renews until cancelled. Cancel any time in Settings.")
            .font(.caption2)
            .foregroundStyle(Color.wardInkSecondary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}
