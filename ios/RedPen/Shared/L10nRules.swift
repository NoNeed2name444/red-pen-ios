import Foundation

// MARK: - Which language, which direction, which digits
//
// The decisions behind the app's localisation, kept apart from SwiftUI and
// from any real bundle so they run on Linux (Tests/L10nTests.swift).
// L10n.swift applies them to the bundles the app actually has.
//
// The catalog (Resources/Localizable.xcstrings) is written in English: every
// key IS the English text, so a key the catalog lacks, or a language it lacks,
// reads as the English it always did. Nothing here can make a string vanish.

enum L10nRules {
    /// The language the catalog is written in.
    static let development: String = "en"

    /// The table every catalog string lives in (Localizable.xcstrings, or the
    /// Localizable.strings the Playgrounds package is given in its place).
    static let table: String = "Localizable"

    /// The app's language: the first of the reader's own languages, in their
    /// order, that the catalog has - "ar-EG" finds "ar", "zh-Hant-TW" finds
    /// "zh-Hant" - or English when none of them is there.
    static func language(available: [String], preferred: [String]) -> String {
        let offered: [String] = available.filter { $0 != "Base" }
        for wanted in preferred {
            if let found = match(wanted, in: offered) { return found }
        }
        return development
    }

    /// `wanted`, or the shortest form of it that is on offer.
    private static func match(_ wanted: String, in offered: [String]) -> String? {
        var parts: [String] = normalised(wanted).split(separator: "-").map(String.init)
        while !parts.isEmpty {
            let tag: String = parts.joined(separator: "-")
            if let found = offered.first(where: { normalised($0) == tag }) { return found }
            parts.removeLast()
        }
        return nil
    }

    /// "ar_EG" and "AR-eg" alike as "ar-eg".
    static func normalised(_ tag: String) -> String {
        tag.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    /// "ar" of "ar-EG".
    static func base(_ tag: String) -> String {
        let first: Substring = normalised(tag).split(separator: "-").first ?? ""
        return String(first)
    }

    /// Whether `language` is written right to left (Arabic, Hebrew, Persian,
    /// Urdu...), from the locale data rather than a list kept here.
    static func isRightToLeft(_ language: String) -> Bool {
        Locale.Language(identifier: language).characterDirection == .rightToLeft
    }

    /// The first bundle that holds the catalog in any language, given for
    /// each candidate the languages that hold it - or nil when none does
    /// (keys then read as their English).
    static func firstWithTable(_ languagesPerBundle: [[String]]) -> Int? {
        languagesPerBundle.firstIndex { !$0.isEmpty }
    }

    /// The locale numbers and dates are written in. The reader's own when it
    /// is already in the app's language (their region, their calendar, their
    /// choice of digits); otherwise the app's language in their region, so
    /// an Arabic screen never counts in the other language's digits.
    static func formattingLocale(language: String, current: Locale) -> Locale {
        let currentBase: String = current.language.languageCode?.identifier ?? ""
        if currentBase == base(language) { return current }
        guard let region = current.region?.identifier else { return Locale(identifier: language) }
        return Locale(identifier: language + "_" + region)
    }
}

// MARK: - Numbers, times and dates in the reader's digits
//
// String(format: "%d:%02d") and "\(n)" always write Western digits. These go
// through FormatStyle with the app's locale: "2:05" in English, "٢:٠٥" in
// Egyptian Arabic.

enum L10nFormat {
    /// A whole number: "1,204" / "١٬٢٠٤".
    static func count(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.locale(locale))
    }

    /// Minutes and seconds, or hours, minutes and seconds past the hour:
    /// "2:05", "1:02:05". Negative or not-a-number reads as zero.
    static func clock(seconds: Double, locale: Locale) -> String {
        let total: Int = seconds.isFinite && seconds > 0 ? Int(seconds.rounded()) : 0
        let hours: Int = total / 3600
        let minutes: Int = (total % 3600) / 60
        let secs: Int = total % 60
        let two: IntegerFormatStyle<Int> = IntegerFormatStyle<Int>(locale: locale)
            .precision(.integerLength(2...)).grouping(.never)
        let one: IntegerFormatStyle<Int> = IntegerFormatStyle<Int>(locale: locale).grouping(.never)
        let tail: String = two.format(secs)
        if hours > 0 {
            let lead: String = one.format(hours)
            let middle: String = two.format(minutes)
            return "\(lead):\(middle):\(tail)"
        }
        let lead: String = one.format(minutes)
        return "\(lead):\(tail)"
    }

    /// A fraction as a whole percentage: "71%" / "٧١٪".
    static func percent(_ fraction: Double, locale: Locale) -> String {
        let safe: Double = fraction.isFinite ? fraction : 0
        let style: FloatingPointFormatStyle<Double>.Percent = .percent.precision(.fractionLength(0))
        return safe.formatted(style.locale(locale))
    }

    /// A day and a short month: "21 Sept" / "٢١ سبتمبر".
    static func day(_ date: Date, locale: Locale) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }
}
