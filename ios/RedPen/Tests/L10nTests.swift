// The localisation lane's decisions: which of the reader's languages the app
// speaks, which way it reads, where the catalog is found, and numbers, times,
// percentages and dates in the app's own digits (L10nRules.swift).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let catalog: [String] = ["en", "ar"]
let egypt: Locale = Locale(identifier: "ar_EG")
let britain: Locale = Locale(identifier: "en_GB")

// MARK: the app's language

check("Arabic phone gets Arabic", L10nRules.language(available: catalog, preferred: ["ar-EG", "en-GB"]) == "ar")
check("plain ar too", L10nRules.language(available: catalog, preferred: ["ar"]) == "ar")
check("underscore spelling", L10nRules.language(available: catalog, preferred: ["ar_SA"]) == "ar")
check("English phone gets English", L10nRules.language(available: catalog, preferred: ["en-GB"]) == "en")
check("the reader's order wins", L10nRules.language(available: catalog, preferred: ["en-US", "ar"]) == "en")
check("first language the catalog has", L10nRules.language(available: catalog, preferred: ["fr-FR", "ar-EG"]) == "ar")
check("nothing in common reads English", L10nRules.language(available: catalog, preferred: ["fr", "de"]) == "en")
check("no preferences reads English", L10nRules.language(available: catalog, preferred: []) == "en")
check("an empty catalog reads English", L10nRules.language(available: [], preferred: ["ar"]) == "en")
check("Base is never a language", L10nRules.language(available: ["Base"], preferred: ["Base"]) == "en")
let chinese: String = L10nRules.language(available: ["en", "zh-Hant"], preferred: ["zh-Hant-TW"])
check("script kept, region dropped", chinese == "zh-Hant", chinese)
let spelled: String = L10nRules.language(available: ["en", "pt-BR"], preferred: ["PT_br"])
check("the catalog's own spelling comes back", spelled == "pt-BR", spelled)
check("base of ar-EG", L10nRules.base("ar-EG") == "ar")
check("base of ar_EG", L10nRules.base("ar_EG") == "ar")

// MARK: which way it reads

check("Arabic reads right to left", L10nRules.isRightToLeft("ar"))
check("Egyptian Arabic too", L10nRules.isRightToLeft("ar-EG"))
check("Hebrew too", L10nRules.isRightToLeft("he"))
check("Persian too", L10nRules.isRightToLeft("fa"))
check("Urdu too", L10nRules.isRightToLeft("ur"))
check("English reads left to right", !L10nRules.isRightToLeft("en"))
check("French reads left to right", !L10nRules.isRightToLeft("fr"))

// MARK: where the catalog is

check("the app first when it has the table", L10nRules.firstWithTable([["en", "ar"], ["en", "ar"]]) == 0)
check("the package bundle when the app has none", L10nRules.firstWithTable([[], ["en", "ar"]]) == 1)
check("no table anywhere", L10nRules.firstWithTable([[], []]) == nil)
check("no bundles at all", L10nRules.firstWithTable([]) == nil)

// MARK: the locale numbers are written in

let keptEgypt: Locale = L10nRules.formattingLocale(language: "ar", current: egypt)
check("an Arabic phone keeps its own locale", keptEgypt.identifier == egypt.identifier, keptEgypt.identifier)
let keptBritain: Locale = L10nRules.formattingLocale(language: "en", current: britain)
check("an English phone keeps its own locale", keptBritain.identifier == britain.identifier, keptBritain.identifier)
let arabicInBritain: Locale = L10nRules.formattingLocale(language: "ar", current: britain)
let arabicBase: String = arabicInBritain.language.languageCode?.identifier ?? ""
let arabicRegion: String = arabicInBritain.region?.identifier ?? ""
check("Arabic app on an English phone counts in Arabic", arabicBase == "ar", arabicInBritain.identifier)
check("...in the phone's region", arabicRegion == "GB", arabicInBritain.identifier)

// MARK: numbers, times, percentages, dates

let arabicDigits: CharacterSet = CharacterSet(charactersIn: "٠١٢٣٤٥٦٧٨٩")
let westernDigits: CharacterSet = CharacterSet(charactersIn: "0123456789")
func onlyArabicDigits(_ text: String) -> Bool {
    text.unicodeScalars.contains { arabicDigits.contains($0) }
        && !text.unicodeScalars.contains { westernDigits.contains($0) }
}

check("count in English", L10nFormat.count(7, locale: britain) == "7")
check("count groups thousands", L10nFormat.count(1204, locale: britain) == "1,204", L10nFormat.count(1204, locale: britain))
let arCount: String = L10nFormat.count(125, locale: egypt)
check("count in Egyptian Arabic", arCount == "١٢٥", arCount)

check("clock m:ss", L10nFormat.clock(seconds: 125, locale: britain) == "2:05")
check("clock under a minute", L10nFormat.clock(seconds: 9, locale: britain) == "0:09")
check("clock rounds", L10nFormat.clock(seconds: 59.6, locale: britain) == "1:00")
check("clock past the hour", L10nFormat.clock(seconds: 3725, locale: britain) == "1:02:05",
      L10nFormat.clock(seconds: 3725, locale: britain))
check("clock never negative", L10nFormat.clock(seconds: -4, locale: britain) == "0:00")
check("clock of not-a-number", L10nFormat.clock(seconds: .nan, locale: britain) == "0:00")
check("clock of infinity", L10nFormat.clock(seconds: .infinity, locale: britain) == "0:00")
check("clock does not group", L10nFormat.clock(seconds: 3600 * 1200, locale: britain) == "1200:00:00",
      L10nFormat.clock(seconds: 3600 * 1200, locale: britain))
let arClock: String = L10nFormat.clock(seconds: 125, locale: egypt)
check("clock in Arabic digits", arClock == "٢:٠٥", arClock)

check("percent", L10nFormat.percent(0.71, locale: britain) == "71%", L10nFormat.percent(0.71, locale: britain))
check("percent rounds", L10nFormat.percent(0.999, locale: britain) == "100%")
check("percent of not-a-number", L10nFormat.percent(.nan, locale: britain) == "0%")
let arPercent: String = L10nFormat.percent(0.71, locale: egypt)
check("percent in Arabic digits", onlyArabicDigits(arPercent), arPercent)

var parts: DateComponents = DateComponents()
parts.year = 2026
parts.month = 9
parts.day = 21
parts.hour = 12
var gregorian: Calendar = Calendar(identifier: .gregorian)
gregorian.timeZone = TimeZone(identifier: "UTC") ?? gregorian.timeZone
let day: Date = gregorian.date(from: parts) ?? Date()
let enDay: String = L10nFormat.day(day, locale: britain)
check("day and month in English", enDay.contains("21") && enDay.contains("Sep"), enDay)
let arDay: String = L10nFormat.day(day, locale: egypt)
check("day and month in Arabic", onlyArabicDigits(arDay) && arDay.contains("سبتمبر"), arDay)

if failures.isEmpty {
    print("all l10n checks passed")
} else {
    print("\(failures.count) FAILED")
    exit(1)
}
