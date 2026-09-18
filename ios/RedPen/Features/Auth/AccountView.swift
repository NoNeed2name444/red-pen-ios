import SwiftUI
import StoreKit

/// The account, the subscription, and the two ways to leave.
struct AccountView: View {
    @EnvironmentObject var account: AccountStore
    @EnvironmentObject var subscriptions: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Signed in") {
                    if let person = account.account {
                        LabeledContent("Account", value: person.shownName)
                        LabeledContent("Signed in with", value: person.provider.label)
                    }
                }

                Section {
                    LabeledContent("Subscription",
                                   value: Entitlement.summary(subscriptions.access))
                    if subscriptions.isPro {
                        // Apple's own sheet, so cancelling and changing plan
                        // happen where the student expects rather than in a
                        // screen of ours that can only be wrong
                        Button("Manage or cancel") { showManage() }
                    } else {
                        Button("See plans") { showPaywall = true }
                    }
                    Button("Restore purchases") { Task { await subscriptions.restore() } }
                        .disabled(subscriptions.busy)
                } footer: {
                    Text("Your decks, recordings and transcripts are on this phone only. Signing out does not remove them.")
                }

                Section {
                    Button("Sign out") {
                        account.signOut()
                        dismiss()
                    }
                    Button("Delete account", role: .destructive) { confirmingDelete = true }
                } footer: {
                    Text("Deleting removes your account and its subscription record from our server. It does not cancel an active subscription \u{2014} do that in Manage first, or Apple will keep billing.")
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .alert("Delete your account?", isPresented: $confirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        if await account.deleteAccount() { dismiss() }
                    }
                }
            } message: {
                Text("This cannot be undone. Your study material stays on this phone.")
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { account.trouble != nil }, set: { if !$0 { account.trouble = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(account.trouble ?? "")
            }
        }
    }

    private func showManage() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        Task { try? await AppStore.showManageSubscriptions(in: scene) }
    }
}
