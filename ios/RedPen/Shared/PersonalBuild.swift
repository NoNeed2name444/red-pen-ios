import Foundation

/// Where the app's bundled files can be: the app itself, the Swift package's
/// own resource bundle, and any resource bundle inside the app (where Swift
/// Playgrounds may put the Samples folder).
enum AppResources {
    static let bundles: [Bundle] = {
        var found = [Bundle.main]
        #if SWIFT_PACKAGE
        found.append(Bundle.module)
        #endif
        let inside = (try? FileManager.default.contentsOfDirectory(
            at: Bundle.main.bundleURL, includingPropertiesForKeys: nil)) ?? []
        found += inside.filter { $0.pathExtension == "bundle" }.compactMap(Bundle.init(url:))
        return found
    }()

    /// A file in a Samples folder, wherever it ended up.
    static func sample(_ name: String, _ ext: String) -> URL? {
        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Samples") { return url }
        }
        return nil
    }

    /// Every file of one kind in the Samples folders.
    static func samples(withExtension ext: String) -> [URL] {
        var seen = Set<String>()
        return bundles.flatMap { $0.urls(forResourcesWithExtension: ext, subdirectory: "Samples") ?? [] }
            .filter { seen.insert($0.lastPathComponent).inserted }
    }
}

/// Whether this is the owner's personal build (examples in every mode, the
/// bundled lecture). Swift Playgrounds runs an app under a bundle id of its
/// own, so the id alone cannot say: the personal package carries a marker
/// file in its Samples folder, and an Xcode personal build ends in ".personal".
enum PersonalBuild {
    static let isOn: Bool =
        Bundle.main.bundleIdentifier?.hasSuffix(".personal") == true
        // the simulator tests ask for it, to check the examples appear
        || ProcessInfo.processInfo.arguments.contains("-personalBuild")
        || AppResources.sample("personal-build", "txt") != nil
}
