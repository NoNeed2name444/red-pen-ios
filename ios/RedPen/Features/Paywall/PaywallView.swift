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
    @State private var chosen: SubscriptionPlan = .yearly

    var body: some View {
        NavigationStack {
            ZStack {
                LibraryBackdrop()
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        plans
                        buyButton
                        footnotes
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Red Pen Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") { Task { await subscriptions.restore() } }
                        .disabled(subscriptions.busy)
                }
            }
            .task { await subscriptions.loadProducts() }
            .onChange(of: subscriptions.isPro) { _, pro in if pro { dismiss() } }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 42))
                .foregroundStyle(StudySetKind.mcq.tint)
            Text("Everything, from any lecture")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                perk("doc.text.viewfinder", "Read PDFs, Word and PowerPoint handouts")
                perk("stethoscope", "Doctor-R1 and MedVAL, the medical models, on this device")
                perk("cloud", "CramDown Cloud: Baichuan-M2, a medical model, writes and checks questions, stations and patient cases on any device")
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
                .foregroundStyle(StudySetKind.anki.tint)
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var plans: some View {
        if subscriptions.products.isEmpty {
            ProgressView().padding(.vertical, 24)
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

    private func planRow(_ plan: SubscriptionPlan, _ product: Product) -> some View {
        let picked = chosen == plan
        return Button {
            chosen = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: picked ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(picked ? StudySetKind.mcq.tint : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.label).font(.body.weight(.semibold))
                    if plan == .yearly, let saving = subscriptions.yearlySaving, saving > 0 {
                        Text("Save \(saving)% against monthly")
                            .font(.caption).foregroundStyle(StudySetKind.anki.tint)
                    }
                }
                Spacer()
                Text(product.displayPrice).font(.body.weight(.semibold))
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(picked ? StudySetKind.mcq.tint : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var buyButton: some View {
        VStack(spacing: 8) {
            Button {
                Task { await subscriptions.buy(chosen) }
            } label: {
                HStack {
                    if subscriptions.busy { ProgressView().controlSize(.small) }
                    Text("Subscribe")
                }
                .frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(.glassProminent)
            .disabled(subscriptions.busy || subscriptions.product(for: chosen) == nil)

            if let trouble = subscriptions.trouble {
                Text(trouble).font(.footnote).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var footnotes: some View {
        VStack(spacing: 6) {
            Text("Billed through your Apple Account and renews until cancelled. Cancel any time in Settings.")
            // required in the app itself, not only on a website
            HStack(spacing: 14) {
                Link("Terms", destination: URL(string: "https://redpen.app/terms")!)
                Link("Privacy", destination: URL(string: "https://redpen.app/privacy")!)
            }
            .font(.caption)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
        .padding(.top, 4)
    }
}
