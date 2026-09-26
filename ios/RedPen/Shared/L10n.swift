import SwiftUI

// MARK: - The app's strings, wherever this build keeps them
//
// The catalog is Resources/Localizable.xcstrings, English first (every key is
// its English), Arabic beside it. The two builds keep it in different places:
//
//   - Xcode (ios/project.yml) compiles the catalog into the app itself, so
//     Bundle.main has en.lproj and ar.lproj, and iOS knows the app speaks
//     Arabic (CFBundleLocalizations).
//   - Swift Playgrounds (tools/make_swiftpm.py) cannot be trusted to compile a
//     .xcstrings, so the package is given plain <lang>.lproj/Localizable.strings
//     (and .stringsdict for plurals) made from the catalog, declared with
//     .process("Localization"). An App Playgrounds executable target's
//     resources land in the package's resource bundle (Bundle.module, a
//     "<Package>_AppModule.bundle" inside the app), where the Samples folder
//     already goes (AppResources) - not in Bundle.main, which is where
//     Text("...") and String(localized:) look unless told otherwise. And the
//     Playgrounds app cannot declare its languages (no Info.plist), while a
//     package bundle's languages can be ignored when the app declares none.
//
// So the choice is made here, once, the same way in both builds:
//   1. the first of AppResources.bundles (the app, then the package's
//      bundles) that holds the Localizable table in any language;
//   2. the reader's language, from the ones it holds (L10nRules.language);
//   3. that language's own .lproj folder, opened as a bundle of its own, so
//      nothing can steer the lookup back to another language.
// Every step falls back instead of failing: no bundle, no folder or no key
// reads as the English key. Nothing is force-unwrapped, and Bundle.module is
// only reached through AppResources, exactly as the app already does at
// launch to find its Samples.
//
// Use: Text(l10n: "Sign in"), L10n.string("\(n) sets") for a String, and
// L10n.lookup(title) for a key only known at run time (a dock label from an
// enum). A Text(l10n:) keeps Markdown in a translation, as Text("...") does.

enum L10n {
    private struct Choice {
        let bundle: Bundle
        let language: String
    }

    private static let choice: Choice = resolve()

    /// Where catalog strings are read from in this build.
    static var bundle: Bundle { choice.bundle }

    /// The app's language: "en", "ar"...
    static var language: String { choice.language }

    /// The locale numbers and dates are written in (L10nRules.formattingLocale).
    static let locale: Locale = L10nRules.formattingLocale(language: choice.language,
                                                           current: Locale.current)

    /// Whether the app reads right to left.
    static let isRightToLeft: Bool = L10nRules.isRightToLeft(choice.language)

    /// A catalog string, with its interpolations formatted and its plural
    /// chosen for the app's locale: L10n.string("\(n) sets").
    static func string(_ value: String.LocalizationValue) -> String {
        String(localized: value, table: L10nRules.table, bundle: bundle, locale: locale)
    }

    /// A catalog string for a key known only at run time.
    static func lookup(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: L10nRules.table)
    }

    /// A whole number in the app's digits.
    static func count(_ value: Int) -> String {
        L10nFormat.count(value, locale: locale)
    }

    // MARK: Finding the catalog

    private static func resolve() -> Choice {
        let candidates: [Bundle] = AppResources.bundles
        let held: [[String]] = candidates.map(languagesHoldingTable)
        let preferred: [String] = Locale.preferredLanguages
        guard let index = L10nRules.firstWithTable(held) else {
            // no table anywhere: Bundle.main, in whatever language it speaks
            let spoken: String = L10nRules.language(available: Bundle.main.localizations,
                                                    preferred: preferred)
            return Choice(bundle: Bundle.main, language: spoken)
        }
        let home: Bundle = candidates[index]
        let language: String = L10nRules.language(available: held[index], preferred: preferred)
        // the folder only when the table is really in it (not when the
        // catalog is one .loctable beside it and the folder holds only
        // InfoPlist.strings)
        let inFolder: Bool = holdsTable(home, in: language)
        let folder: URL? = inFolder ? home.url(forResource: language, withExtension: "lproj") : nil
        let own: Bundle? = folder.flatMap { Bundle(url: $0) }
        return Choice(bundle: own ?? home, language: language)
    }

    /// The languages `bundle` has the Localizable table in. A newer Xcode
    /// may compile the catalog into one Localizable.loctable for every
    /// language rather than a table per .lproj folder; then it is all of them.
    private static func languagesHoldingTable(_ bundle: Bundle) -> [String] {
        let whole: URL? = bundle.url(forResource: L10nRules.table, withExtension: "loctable")
        if whole != nil { return bundle.localizations }
        return bundle.localizations.filter { holdsTable(bundle, in: $0) }
    }

    private static func holdsTable(_ bundle: Bundle, in language: String) -> Bool {
        let table: String = L10nRules.table
        let strings: String? = bundle.path(forResource: table, ofType: "strings",
                                           inDirectory: nil, forLocalization: language)
        if strings != nil { return true }
        let plurals: String? = bundle.path(forResource: table, ofType: "stringsdict",
                                           inDirectory: nil, forLocalization: language)
        return plurals != nil
    }
}

extension Text {
    /// A catalog string (see L10n): Text(l10n: "Read this before you start").
    init(l10n value: String.LocalizationValue) {
        let text: AttributedString = AttributedString(localized: value, table: L10nRules.table,
                                                      bundle: L10n.bundle, locale: L10n.locale)
        self.init(text)
    }
}

// MARK: - Right to left, whichever build

/// The app's language on the whole window: right to left, and the app's
/// locale for numbers and dates, when the app is in Arabic.
///
/// The Xcode build would get this from iOS anyway, because the app declares
/// Arabic. The Playgrounds app cannot declare it, so iOS lays it out left to
/// right even while its strings are Arabic; this says it for both. In a left
/// to right language nothing is changed at all.
private struct AppLanguage: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if L10n.isRightToLeft {
            content
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, L10n.locale)
        } else {
            content
        }
    }
}

extension View {
    /// The app's language and direction (see AppLanguage). Once, at the root
    /// of each window.
    func appLanguage() -> some View {
        modifier(AppLanguage())
    }

    /// A decorative picture that must look the same in both directions - the
    /// fan of mode tiles - kept left to right, so its tilts still fan out.
    func keepsLeftToRight() -> some View {
        environment(\.layoutDirection, .leftToRight)
    }

    /// A ring or arc drawn clockwise from the top, drawn anticlockwise in a
    /// right-to-left language, so it fills from the leading side as a bar
    /// does. Put it on the arc only, never on text.
    func fillsFromLeading() -> some View {
        flipsForRightToLeftLayoutDirection(true)
    }
}
