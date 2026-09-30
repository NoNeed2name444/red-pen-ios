import Foundation

/// The owner's personal build: a one-time claim, put in the build itself
/// (Samples/owner-claim.txt) and never in the repository, that makes the
/// first account this device creates the owner's - Pro, with no App Store
/// subscription, for the person the app belongs to. Nil in every other build.
enum OwnerClaim {
    static var bundled: String? {
        guard let url = AppResources.sample("owner-claim", "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let claim = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return claim.count >= 32 ? claim : nil
    }
}
