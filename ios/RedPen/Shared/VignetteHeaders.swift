import Foundation

/// The two headers every request to the worker carries: which build of the
/// app is asking, and whether it is the App Store app or the Swift
/// Playgrounds package.
///
/// The worker uses them for remote-config messages (a minimum or maximum
/// build) and in its logs, never for access: anyone can send any header.
/// They go to the worker only - a provider the student added themselves is
/// told nothing about the app.
enum VignetteHeaders {
    static let buildField = "X-Vignette-Build"
    static let surfaceField = "X-Vignette-Surface"

    /// CFBundleVersion, or "0" when there is none (Swift Playgrounds may run
    /// the package without one).
    static var build: String {
        let raw: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return sanitisedBuild(raw)
    }

    /// "playgrounds" for the Swift package, "app" for the Xcode build.
    static var surface: String {
        #if SWIFT_PACKAGE
        return "playgrounds"
        #else
        return "app"
        #endif
    }

    /// Digits and dots only, at most 20 characters; anything else is "0".
    static func sanitisedBuild(_ raw: String) -> String {
        let trimmed: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "0123456789.")
        let clean: Bool = !trimmed.isEmpty && trimmed.count <= 20
            && trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
        return clean ? trimmed : "0"
    }

    /// The header values, by field name.
    static func values(build: String = VignetteHeaders.build,
                       surface: String = VignetteHeaders.surface) -> [String: String] {
        [buildField: build, surfaceField: surface]
    }

    /// Whether a URL points at the worker (same scheme, host and port).
    static func isWorker(_ url: URL?, base: URL = AuthAPI.baseURL) -> Bool {
        guard let url, let host = url.host?.lowercased(), let baseHost = base.host?.lowercased() else {
            return false
        }
        let sameScheme: Bool = url.scheme?.lowercased() == base.scheme?.lowercased()
        return sameScheme && host == baseHost && url.port == base.port
    }

    /// Adds both headers to a request for the worker. A request for any
    /// other host is left exactly as it was.
    static func apply(to request: inout URLRequest, base: URL = AuthAPI.baseURL) {
        guard isWorker(request.url, base: base) else { return }
        for (field, value) in values() {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }
}
