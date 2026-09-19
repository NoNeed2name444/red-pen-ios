import SwiftUI
import StoreKit

/// The account, the subscription, and the two ways to leave.
struct AccountView: View {
    /// True when this is already inside someone else's navigation - the iPad
    /// sidebar pushes it rather than presenting it, and a stack inside a stack
    /// gives you two title bars and a Done button that dismisses nothing.
    var embedded: Bool = false

    @EnvironmentObject var account: AccountStore
    @EnvironmentObject var subscriptions: SubscriptionStore
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if embedded { form } else { NavigationStack { form } }
        }
    }

    private var form: some View {
        Form {
            Section("Signed in") {
                if let person = account.account {
                    LabeledContent("Account", value: person.shownName)
                    LabeledContent("Signed in with", value: person.provider.label)
                }
            }

            Section {
                LabeledContent("Sync", value: syncSummary)
                Button("Sync now") { Task { await sync.syncNow() } }
                    .disabled(sync.status == .syncing)
                if sync.copiesKept > 0 {
                    Text("\(sync.copiesKept) deck\(sync.copiesKept == 1 ? " was" : "s were") edited in two places. Both versions are in your library \u{2014} check them and delete the one you don't want.")
                        .font(.caption).foregroundStyle(.orange)
                }
            } footer: {
                Text("Your decks, folders and review schedule follow you between your devices. Recordings and learned pronunciations stay on the phone that made them.")
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
            }

            Section {
                Button("Sign out") {
                    account.signOut()
                    // Whatever this device believed it had agreed with the
                    // server is about that account, not this phone. Left in
                    // place, the next person to sign in here would start
                    // with bookmarks for documents they have never seen.
                    sync.forgetEverythingSynced()
                    dismiss()
                }
                Button("Delete account", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Deleting removes your account, your synced library and its subscription record from our server. The copy on this phone stays. It does not cancel an active subscription \u{2014} do that in Manage first, or Apple will keep billing.")
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert("Delete your account?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    if await account.deleteAccount() {
                        sync.forgetEverythingSynced()
                        dismiss()
                    }
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

    /// Said in words rather than as a date, because "synced" is a state and a
    /// timestamp on its own does not say whether anything is wrong.
    private var syncSummary: String {
        switch sync.status {
        case .syncing: return "Syncing\u{2026}"
        case .offline: return "Waiting for a connection"
        case .failed(let why): return why
        case .idle:
            guard let when = sync.lastSyncedAt else { return "Not synced yet" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Synced " + formatter.localizedString(for: when, relativeTo: Date())
        }
    }

    private func showManage() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        Task { try? await AppStore.showManageSubscriptions(in: scene) }
    }
}
