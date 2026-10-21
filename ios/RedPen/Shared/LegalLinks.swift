import Foundation

/// Where the legal pages live: on the worker (`GET /terms`, `/privacy`,
/// server/legal.js), asked for in English or Arabic by `?lang=` (the worker
/// answers in English until it has the Arabic). One place, so the paywall,
/// the sign-in screen and Settings can never point at different addresses -
/// or at a domain the app does not own. A page joins `Page` only once the
/// worker serves it.
enum LegalLinks {
    enum Page: String, CaseIterable {
        case privacy, terms
    }

    /// The languages the worker writes its pages in.
    static let languages: [String] = ["en", "ar"]

    /// The page in the student's language.
    static func url(_ page: Page, base: URL = AuthAPI.baseURL,
                    language: String = LegalLinks.language) -> URL {
        let lang: String = languages.contains(language) ? language : "en"
        let pageURL: URL = base.appendingPathComponent(page.rawValue)
        guard var parts = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else { return pageURL }
        parts.queryItems = [URLQueryItem(name: "lang", value: lang)]
        return parts.url ?? pageURL
    }

    /// "ar" when the student reads Arabic before English, otherwise "en".
    static var language: String {
        languageCode(preferred: Locale.preferredLanguages)
    }

    /// The first of the student's languages the pages come in; English when
    /// none does.
    static func languageCode(preferred: [String]) -> String {
        for tag in preferred {
            let base: String = tag.lowercased().split(separator: "-").first.map(String.init) ?? ""
            if languages.contains(base) { return base }
        }
        return "en"
    }

    /// Links written into a localised sentence as `legal://terms` (so the
    /// sentence stays one string for translators); the page each one means.
    static let placeholderScheme = "legal"

    static func page(forPlaceholder url: URL) -> Page? {
        guard url.scheme?.lowercased() == placeholderScheme else { return nil }
        let name: String = (url.host ?? "").lowercased()
        return Page(rawValue: name)
    }

    /// The real address for a placeholder link, or nil for any other URL.
    static func resolve(_ url: URL) -> URL? {
        guard let page = page(forPlaceholder: url) else { return nil }
        return self.url(page)
    }
}
