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
    private static let row = RoundedRectangle(cornerRadius: 14, style: .continuous)

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
            .background(LibraryBackdrop())
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
                .scaledFont(42, relativeTo: .largeTitle, maxSize: 64)
                .foregroundStyle(StudySetKind.mcq.tint)
                .accessibilityHidden(true)
            Text("Everything, from any lecture")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                perk("doc.text.viewfinder", "Read PDFs, Word and PowerPoint handouts")
                perk("stethoscope", "Doctor-R1 and MedVAL, the medical models, on this device")
                perk("cloud", "\(Brand.name) Cloud: Google's Gemini writes and checks questions, stations and patient cases on any device")
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
                .accessibilityHidden(true)
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

    /// The chosen plan stands a little out of the glass; the other lies flat.
    private func planRow(_ plan: SubscriptionPlan, _ product: Product) -> some View {
        let picked: Bool = chosen == plan
        let symbol: String = picked ? "largecircle.fill.circle" : "circle"
        let mark: Color = picked ? StudySetKind.mcq.tint : Color.secondary
        let edge: Color = picked ? StudySetKind.mcq.tint : Color.clear
        let plane: PopOutPlane = picked ? .raised : .screen
        let traits: AccessibilityTraits = picked ? .isSelected : []
        return Button {
            chosen = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(mark)
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
            .background(.thinMaterial, in: PaywallView.row)
            .overlay(PaywallView.row.stroke(edge, lineWidth: 2))
            .contentShape(PaywallView.row)
        }
        .buttonStyle(.plain)
        .popOut(plane, in: PaywallView.row)
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
            Text(trouble).font(.footnote).foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
        Button {
            Task { await subscriptions.buy(chosen) }
        } label: {
            HStack(spacing: 8) {
                if subscriptions.busy { ProgressView().controlSize(.small) }
                Text(buyTitle)
            }
        }
        .buttonStyle(.bigPrimary)
        .keyboardShortcut(.defaultAction)
        .disabled(cannotBuy)
        // required in the app itself, not only on a website
        HStack(spacing: 16) {
            Button("Restore") { Task { await subscriptions.restore() } }
                .disabled(subscriptions.busy)
            Link("Terms", destination: URL(string: "https://redpen.app/terms")!)
            Link("Privacy", destination: URL(string: "https://redpen.app/privacy")!)
        }
        .font(.footnote)
        .buttonStyle(.borderless)
    }

    private var billing: some View {
        Text("Billed through your Apple Account and renews until cancelled. Cancel any time in Settings.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}
