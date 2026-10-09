import SwiftUI
import StoreKit

/// The account, the subscription, and the two ways to leave.
///
/// Who you are sits at the top on a raised card, with the one thing most
/// people come here to do; syncing, the subscription and the rest are under
/// it, and Sign out and Delete account are always last.
struct AccountView: View {
    /// True when this is already inside someone else's navigation - the
    /// library pushes it rather than presenting it, and a stack inside a stack
    /// gives you two title bars and a Done button that dismisses nothing.
    var embedded: Bool = false

    @EnvironmentObject var account: AccountStore
    @EnvironmentObject var subscriptions: SubscriptionStore
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false
    @State private var confirmingDelete = false
    @State private var linking = false

    /// The header card's one action.
    private enum HeaderAction { case plans, sync, link }

    var body: some View {
        Group {
            if embedded { form } else { NavigationStack { form } }
        }
    }

    private var form: some View {
        Form {
            headerSection
            syncSection
            subscriptionSection
            leaveSection
        }
        .wardForm()
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $linking) { LinkDeviceView() }
        .alert("Delete your account?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteAccount() }
        } message: {
            Text("This cannot be undone. Your study material stays on this phone.")
        }
        .alert("Something went wrong", isPresented: troubleShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(account.trouble ?? "")
        }
    }

    // MARK: Who you are

    private var isLocalOnly: Bool { account.state.session?.isLocalOnly == true }

    /// Not Pro: the plans. Pro, on this device only: linking a second device,
    /// the one way such a library starts syncing. Otherwise: sync now.
    private var headerAction: HeaderAction {
        if !subscriptions.isPro { return .plans }
        if isLocalOnly { return .link }
        return .sync
    }

    private var headerSection: some View {
        Section {
            // The chip shows a real subscription; the personal build opens Pro without one.
            AccountHeaderCard(person: account.account, localOnly: isLocalOnly,
                              isPro: subscriptions.access.isPro) {
                headerButton
            }
            .wardCardRow()
        }
    }

    /// The screen's one primary button, on the card under who you are.
    @ViewBuilder
    private var headerButton: some View {
        switch headerAction {
        case .plans:
            Button("See plans") { showPaywall = true }
                .buttonStyle(.wardPrimary)
        case .link:
            Button { linking = true } label: {
                Label("Link another device", systemImage: "ipad.and.iphone")
            }
            .buttonStyle(.wardPrimary)
        case .sync:
            Button { Task { await sync.syncNow() } } label: {
                Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.wardPrimary)
            .disabled(sync.status == .syncing)
        }
    }

    // MARK: Sync

    private var syncSection: some View {
        Section {
            LabeledContent {
                WardChip(text: syncSummary, tone: syncTone)
            } label: {
                Text("Sync")
            }
            if !subscriptions.isPro {
                Text("Keeping your iPhone and iPad the same is part of Pro.")
                    .font(.footnote).foregroundStyle(Color.wardInkSecondary)
            } else if isLocalOnly {
                Text("This library is only on this device. Link another device to keep them the same.")
                    .font(.footnote).foregroundStyle(Color.wardInkSecondary)
            }
            if headerAction != .link {
                Button { if subscriptions.isPro { linking = true } else { showPaywall = true } } label: {
                    Label("Link another device", systemImage: "ipad.and.iphone")
                }
            }
            if sync.copiesKept > 0 {
                WardBanner(tone: .warning, symbol: "exclamationmark.triangle.fill", text: copiesNote)
            }
            if sync.status == .needsLibraryChoice {
                // somebody else's library is on this device: nothing of it
                // goes into this account until the student says so
                Text("The library on this device was synced with another account. Nothing syncs until you choose.")
                    .font(.footnote).foregroundStyle(Color.wardInkSecondary)
                Button("Add it to this account") {
                    Task { await sync.chooseLibrary(addToAccount: true) }
                }
                Button("Keep it on this device only") {
                    Task { await sync.chooseLibrary(addToAccount: false) }
                }
            } else if sync.setsKeptHere > 0 {
                Text(keptNote)
                    .font(.footnote).foregroundStyle(Color.wardInkSecondary)
                Button("Add them to this account") {
                    Task { await sync.addKeptSets() }
                }
            }
        } footer: {
            Text("Your decks, folders and review schedule follow you between your devices. Recordings and learned pronunciations stay on the phone that made them.")
        }
        .wardRowBackground()
    }

    /// Sets kept off this account when it signed in, said as a sentence.
    private var keptNote: String {
        let count: Int = sync.setsKeptHere
        let sets: String = count == 1 ? "1 set stays" : "\(count) sets stay"
        return sets + " on this device only, from before this account signed in."
    }

    /// How many decks were edited in two places, said as a sentence.
    private var copiesNote: String {
        let count: Int = sync.copiesKept
        let decks: String = count == 1 ? "1 deck was" : "\(count) decks were"
        let rest: String = "edited in two places. Both versions are in your library \u{2014} check them and delete the one you don't want."
        return decks + " " + rest
    }

    // MARK: Subscription

    private var subscriptionSection: some View {
        Section {
            LabeledContent("Subscription",
                           value: Entitlement.accountLine(subscriptions.access, personal: PersonalBuild.isOn))
            if subscriptions.access.isPro {
                // Apple's own sheet, so cancelling and changing plan
                // happen where the student expects rather than in a
                // screen of ours that can only be wrong
                Button("Manage or cancel") { showManage() }
            }
            // The owner's build has nothing to restore.
            if !PersonalBuild.isOn {
                Button("Restore purchases") { Task { await subscriptions.restore() } }
                    .disabled(subscriptions.busy)
            }
        }
        .wardRowBackground()
    }

    // MARK: Leaving - always last

    private var leaveSection: some View {
        Section {
            Button("Sign out") { signOut() }
            Button("Delete account", role: .destructive) { confirmingDelete = true }
        } footer: {
            Text("Deleting removes your account, your synced library and its subscription record from our server. The copy on this phone stays. It does not cancel an active subscription \u{2014} do that in Manage first, or Apple will keep billing.")
        }
        .wardRowBackground()
    }

    private func signOut() {
        account.signOut()
        // Whatever this device believed it had agreed with the server is
        // about that account, not this phone. Left in place, the next person
        // to sign in here would start with bookmarks for documents they have
        // never seen.
        sync.forgetEverythingSynced()
        dismiss()
    }

    private func deleteAccount() {
        Task {
            if await account.deleteAccount() {
                sync.forgetEverythingSynced()
                dismiss()
            }
        }
    }

    private var troubleShown: Binding<Bool> {
        Binding(get: { account.trouble != nil },
                set: { shown in if !shown { account.trouble = nil } })
    }

    /// Said in words rather than as a date, because "synced" is a state and a
    /// timestamp on its own does not say whether anything is wrong.
    private var syncSummary: String {
        switch sync.status {
        case .syncing: return "Syncing\u{2026}"
        case .offline: return "Waiting for a connection"
        case .failed(let why): return why
        case .needsPro: return "Part of Pro"
        case .needsLibraryChoice: return "Waiting for your choice"
        case .idle:
            guard let when = sync.lastSyncedAt else { return "Not synced yet" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let ago: String = formatter.localizedString(for: when, relativeTo: Date())
            return "Synced " + ago
        }
    }

    private var syncTone: WardTone {
        switch sync.status {
        case .syncing: return .blue
        case .offline, .needsLibraryChoice: return .warning
        case .failed: return .danger
        case .needsPro: return .grey
        case .idle: return sync.lastSyncedAt == nil ? .grey : .green
        }
    }

    private func showManage() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        Task { try? await AppStore.showManageSubscriptions(in: scene) }
    }
}

/// Who is signed in, on a card: the name, how they signed in, a Pro
/// badge, and one action under them. With no account it shows only the
/// action.
private struct AccountHeaderCard<Action: View>: View {
    let person: Account?
    let localOnly: Bool
    let isPro: Bool
    private let action: Action

    init(person: Account?, localOnly: Bool, isPro: Bool, @ViewBuilder action: () -> Action) {
        self.person = person
        self.localOnly = localOnly
        self.isPro = isPro
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let person {
                identity(person)
            } else if isPro {
                ProBadge()
            }
            action
        }
        // as low as the tiles round it, the button proud of it
        .wardCard(lift: .low)
    }

    private func identity(_ person: Account) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .scaledFont(44, relativeTo: .largeTitle, maxSize: 64)
                .foregroundStyle(Color.wardPrimaryInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.shownName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.wardInk)
                    .lineLimit(1)
                Text(Self.how(person, localOnly: localOnly))
                    .font(.subheadline)
                    .foregroundStyle(Color.wardInkSecondary)
            }
            Spacer(minLength: 8)
            if isPro { ProBadge() }
        }
        .accessibilityElement(children: .combine)
    }

    static func how(_ person: Account, localOnly: Bool) -> String {
        if localOnly { return "On this device only" }
        return "Signed in with " + person.provider.label
    }
}

/// A small capsule saying the account has Pro: a label pressed into the
/// card, its word in Theatre Blue.
private struct ProBadge: View {
    var body: some View {
        WardChip(text: "Pro", tone: .blue)
            .accessibilityLabel("Pro subscription")
    }
}
