import Foundation
import StoreKit
import Combine

/// Buying and keeping a subscription.
///
/// StoreKit 2 verifies transactions itself and keeps them on the device, so
/// there is no receipt to parse and no server round trip needed to know whether
/// somebody has paid. The server is told afterwards as a convenience - so a
/// second phone signing in already knows - but the App Store stays the
/// authority. An app that trusts its own server over the App Store is an app
/// that locks people out when the server has a bad day.
///
/// What counts as subscribed is not decided here: that is Entitlement, which is
/// pure and tested. This only finds out the facts.
@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var record = EntitlementRecord()
    @Published var busy = false
    @Published var trouble: String?

    var access: Access { Entitlement.access(record) }
    /// Personal build: everything is unlocked, no subscription needed.
    var isPro: Bool { true }

    private var updates: Task<Void, Never>?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? dir.appendingPathComponent("redpen-entitlement.json")
        load()
        // A screenshot run has no App Store to ask, so it starts subscribed -
        // otherwise the paywall is not one screen to photograph, it is a wall
        // in front of the other seventeen.
        if PreviewLaunch.screen != nil { record = PreviewLaunch.pretendEntitlement() }
        // A renewal, a refund or a purchase made on another device arrives here
        // rather than being noticed the next time somebody opens the paywall.
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self, case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self.refresh()
            }
        }
    }

    deinit { updates?.cancel() }

    // MARK: what is for sale

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let found = try await Product.products(for: SubscriptionPlan.allCases.map(\.rawValue))
            // cheapest first, so the yearly saving is visible rather than
            // merely stated
            products = found.sorted { $0.price < $1.price }
        } catch {
            trouble = "Couldn't reach the App Store."
        }
    }

    func product(for plan: SubscriptionPlan) -> Product? {
        products.first { $0.id == plan.rawValue }
    }

    /// What the yearly plan saves against paying monthly, as a percentage, or
    /// nil when both are not loaded. Worked out from the real prices rather
    /// than written into the button, so it cannot drift from what is charged.
    var yearlySaving: Int? {
        guard let monthly = product(for: .monthly)?.price,
              let yearly = product(for: .yearly)?.price, monthly > 0 else { return nil }
        let full = monthly * 12
        guard full > yearly else { return nil }
        return Int((((full - yearly) / full) as NSDecimalNumber).doubleValue * 100)
    }

    // MARK: buying

    func buy(_ plan: SubscriptionPlan) async {
        guard let product = product(for: plan) else {
            trouble = "That plan isn't available right now."
            return
        }
        busy = true
        trouble = nil
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refresh()
                } else {
                    trouble = "That purchase couldn't be verified."
                }
            case .userCancelled:
                break // not a problem to report
            case .pending:
                // Ask to Buy, or a bank step that finishes later
                trouble = "Waiting for that purchase to be approved."
            @unknown default:
                break
            }
        } catch {
            trouble = error.localizedDescription
        }
    }

    /// Restoring is for a new phone, or one that has been wiped.
    func restore() async {
        busy = true
        trouble = nil
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        if !isPro { trouble = "No subscription found on this Apple Account." }
    }

    // MARK: what the App Store says now

    func refreshIfNeeded() async {
        guard Entitlement.shouldRefresh(record) else { return }
        await refresh()
    }

    func refresh() async {
        var found = record
        found.plan = nil
        found.expiresAt = nil
        found.inBillingRetry = false

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  let plan = SubscriptionPlan(rawValue: transaction.productID) else { continue }
            // whichever runs longest wins, which is what an upgrade looks like
            // while the old plan is still live
            if let expiry = transaction.expirationDate,
               expiry > (found.expiresAt ?? .distantPast) {
                found.plan = plan
                found.expiresAt = expiry
            }
        }

        if found.plan != nil,
           let statuses = try? await Product.SubscriptionInfo.status(for: SubscriptionPlan.groupName) {
            // being told a renewal is being retried is the difference between
            // "they cancelled" and "their card expired"
            found.inBillingRetry = statuses.contains {
                $0.state == .inBillingRetryPeriod || $0.state == .inGracePeriod
            }
        }

        found.verifiedAt = Date()
        record = found
        save()
    }

    // MARK: keeping it between launches

    /// Kept on disk so the app knows what it last confirmed before it has
    /// managed to ask again - which is what lets a subscription keep working on
    /// a plane. Not a source of truth: the App Store overrides it the moment it
    /// answers.
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder.redPen.decode(EntitlementRecord.self, from: data)
        else { return }
        record = stored
    }

    private func save() {
        guard let data = try? JSONEncoder.redPen.encode(record) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
