import Foundation

/// The owner's personal build: a one-time claim, put in the build itself
/// (Samples/owner-claim.txt) and never in the repository, that makes the
/// first account this device creates the owner's - Pro, with no App Store
/// subscription, for the person the app belongs to. Nil in every other build.
enum OwnerClaim {
    static var bundled: String? {
        var bundles = [Bundle.main]
        #if SWIFT_PACKAGE
        bundles.append(Bundle.module)
        #endif
        for bundle in bundles {
            if let url = bundle.url(forResource: "owner-claim", withExtension: "txt", subdirectory: "Samples"),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                let claim = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if claim.count >= 32 { return claim }
            }
        }
        return nil
    }
}
