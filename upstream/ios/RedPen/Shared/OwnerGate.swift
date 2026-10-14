import Foundation
import Observation

/// Whether the person using the app is its owner: the one question behind
/// every owner-only row (the Owner hub, the review queues, the config).
///
/// Three things can say yes:
/// - the owner's personal build (`PersonalBuild.isOn`), always, with no
///   server - a runtime check, so one codebase builds both apps;
/// - the signed-in session, whose account the worker marked `owner`;
/// - `/account/me`, which refreshes that flag for sessions saved before the
///   worker sent it.
///
/// It only decides what is shown. The worker checks the owner itself on
/// every owner route and answers everyone else 404, so a wrong yes here opens
/// a screen whose every request is refused.
@MainActor
@Observable
final class OwnerGate {
    static let shared = OwnerGate()

    /// What the current session (or the last /account/me) said.
    private(set) var accountIsOwner = false
    /// The account that flag belongs to, so an answer for one account never
    /// sticks to the next.
    private(set) var accountId: String?

    init() {}

    var isOwner: Bool { OwnerGate.decide(personalBuild: PersonalBuild.isOn, account: accountIsOwner) }

    /// The rule, apart from where its inputs come from.
    nonisolated static func decide(personalBuild: Bool, account: Bool) -> Bool {
        personalBuild || account
    }

    /// A session was adopted, restored or dropped (nil when signed out).
    func update(account: Account?) {
        accountId = account?.id
        accountIsOwner = account?.isOwner ?? false
    }

    /// /account/me answered for `accountId`. Ignored when the answer is for
    /// an account that is no longer the signed-in one.
    func update(me: AccountMe, accountId id: String) {
        guard id == accountId else { return }
        accountIsOwner = me.isOwner
    }
}
