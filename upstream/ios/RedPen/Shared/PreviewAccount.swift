import Foundation

/// The account a screenshot run pretends to be signed in as.
///
/// Without it every preview screen would be a picture of the sign-in page, and
/// the week-to-week comparison that catches layout regressions would compare
/// eighteen copies of the same screen. It is a made-up session that never
/// reaches the keychain or the server: the store is handed it directly, and a
/// screenshot run writes to throwaway files anyway.
extension PreviewLaunch {

    static func pretendSession() -> Session {
        Session(
            account: Account(id: "preview", provider: .apple,
                             email: "student@example.edu", displayName: "Preview"),
            token: "preview", refreshToken: nil,
            expiresAt: Date().addingTimeInterval(3600))
    }

    /// A subscribed record, for the same reason: the paywall is one screen to
    /// photograph, not a wall in front of the other seventeen.
    static func pretendEntitlement() -> EntitlementRecord {
        EntitlementRecord(plan: .yearly,
                          expiresAt: Date().addingTimeInterval(365 * 24 * 3600),
                          verifiedAt: Date())
    }
}
