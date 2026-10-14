// Who the server says you are, and what its refusals mean (launch plan P0.2).
//
// The ways these fail are quiet and wide: a session field that will not
// decode signs every student out at once, a business refusal read as "signed
// out" throws a student to the sign-in screen, a header sent to a provider
// the student added tells a third party about the app, and a legal link to a
// page the worker does not serve is a dead link on the paywall.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // URLRequest, on Linux (the test suite)
#endif

// The suite builds without AuthAPI.swift (URLSession) and PersonalBuild.swift
// (bundles); these stand in for the two names the files under test use.
enum AuthAPI { static let baseURL = URL(string: "https://worker.example.dev")! }
enum PersonalBuild { static let isOn = false }

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: a saved session from before the owner flag

let saved = """
{"account":{"id":"u1","provider":"apple","email":"a@b.c","displayName":"Ali","createdAt":700000000},
 "token":"t1","refreshToken":"r1","expiresAt":800000000}
"""
let old = try? JSONDecoder().decode(Session.self, from: Data(saved.utf8))
check("a session saved before the owner flag still decodes", old != nil)
check("and is nobody's owner", old?.account.owner == nil && old?.account.isOwner == false)

var owned = old!
owned.account.owner = true
let again = try? JSONDecoder().decode(Session.self, from: JSONEncoder().encode(owned))
check("an owner session survives the keychain round trip", again == owned && again?.account.isOwner == true)
owned.account.owner = false
check("owner false is not the owner", !owned.account.isOwner)

// MARK: /account/me

let full = """
{"userId":"u1","owner":true,"termsVersion":1,"aiConsent":2,"rulesVersion":1,
 "legal":{"privacy":3,"terms":2,"aiConsent":2,"rules":1,"effective":"2026-10-01"},"extra":"ignored"}
"""
let me = try? JSONDecoder().decode(AccountMe.self, from: Data(full.utf8))
check("/account/me decodes, unknown fields and all", me != nil)
check("the owner flag", me?.isOwner == true)
check("terms agreed to an older version are outdated", me?.termsOutdated == true)
check("an AI consent at the version in force is not", me?.aiConsentOutdated == false)

let bare = try? JSONDecoder().decode(AccountMe.self, from: Data(#"{"userId":"u2"}"#.utf8))
check("an answer with only the id decodes", bare != nil)
check("and says nothing is outdated, and no owner",
      bare?.termsOutdated == false && bare?.aiConsentOutdated == false && bare?.isOwner == false)
let never = try? JSONDecoder().decode(AccountMe.self, from: Data(#"{"userId":"u3","legal":{"aiConsent":1}}"#.utf8))
check("never having agreed to AI is outdated once a version is in force", never?.aiConsentOutdated == true)
check("an answer without the id does not decode",
      (try? JSONDecoder().decode(AccountMe.self, from: Data(#"{"owner":true}"#.utf8))) == nil)

// MARK: what a refusal means

check("2xx is fine", ServerVerdict.of(status: 200, code: nil) == .ok && ServerVerdict.of(status: 204, code: "x") == .ok)
check("401 is signed out, code or not",
      ServerVerdict.of(status: 401, code: nil) == .signedOut && ServerVerdict.of(status: 401, code: "group_full") == .signedOut)
check("402 needs Pro", ServerVerdict.of(status: 402, code: "pro") == .needsPro)
check("428 needs a consent, and says which", ServerVerdict.of(status: 428, code: " ai_consent_required ") == .needsConsent("ai_consent_required"))
check("429 is too many tries", ServerVerdict.of(status: 429, code: nil) == .tooManyTries)
// the live worker sends no code: these must read exactly as before
check("403 without a code is still signed out", ServerVerdict.of(status: 403, code: nil) == .signedOut)
check("404 without a code is still not found", ServerVerdict.of(status: 404, code: nil) == .notFound)
check("a blank code counts as none", ServerVerdict.of(status: 403, code: "  ") == .signedOut)
check("500 is the server", ServerVerdict.of(status: 500, code: nil) == .server)
check("410 is gone", ServerVerdict.of(status: 410, code: nil) == .gone)
// a business answer is never a signed-out session
check("403 with a code is a refusal, not a sign-out", ServerVerdict.of(status: 403, code: "group_full") == .refused("group_full"))
check("404 with a code is a refusal", ServerVerdict.of(status: 404, code: "no_such_code") == .refused("no_such_code"))

let coded = ServerVerdict.problem(in: Data(#"{"error":"Full.","message":"That group is full.","code":"group_full"}"#.utf8))
check("a coded body's parts", coded.code == "group_full" && coded.message == "That group is full." && coded.error == "Full.")
// ai.js and tts.js nest the message: error is an object there
let nested = ServerVerdict.problem(in: Data(#"{"error":{"message":"Busy."},"message":"Busy."}"#.utf8))
check("an object error is no string, and no code", nested.error == nil && nested.code == nil && nested.message == "Busy.")
let numeric = ServerVerdict.problem(in: Data(#"{"code":429}"#.utf8))
check("a numeric code is no code", numeric.code == nil)
let junk = ServerVerdict.problem(in: Data("<html>".utf8))
check("a body that is not JSON has nothing", junk.code == nil && junk.message == nil && junk.error == nil)

// MARK: the owner

check("the personal build is the owner", OwnerGate.decide(personalBuild: true, account: false))
check("an owner account is the owner", OwnerGate.decide(personalBuild: false, account: true))
check("anyone else is not", !OwnerGate.decide(personalBuild: false, account: false))

await MainActor.run {
    let gate = OwnerGate()
    var account = Account(id: "u1", provider: .apple)
    account.owner = true
    gate.update(account: account)
    check("a session marked owner opens the gate", gate.isOwner && gate.accountId == "u1")
    let notOwner = try! JSONDecoder().decode(AccountMe.self, from: Data(#"{"userId":"u1","owner":false}"#.utf8))
    gate.update(me: notOwner, accountId: "u2")
    check("an answer for another account is ignored", gate.isOwner)
    gate.update(me: notOwner, accountId: "u1")
    check("/account/me can close it", !gate.isOwner)
    gate.update(account: account)
    gate.update(account: nil)
    check("signing out closes it", !gate.isOwner && gate.accountId == nil)
}

// MARK: the headers the worker is sent

check("a build number passes", VignetteHeaders.sanitisedBuild(" 1.2.345 ") == "1.2.345")
check("anything else is 0",
      VignetteHeaders.sanitisedBuild("") == "0" && VignetteHeaders.sanitisedBuild("12; drop") == "0"
      && VignetteHeaders.sanitisedBuild(String(repeating: "1", count: 21)) == "0")
let values = VignetteHeaders.values(build: "7", surface: "app")
check("two headers", values == ["X-Vignette-Build": "7", "X-Vignette-Surface": "app"])
check("the worker is the worker", VignetteHeaders.isWorker(URL(string: "https://WORKER.example.dev/v1/chat")))
check("another host is not",
      !VignetteHeaders.isWorker(URL(string: "https://api.openai.com/v1"))
      && !VignetteHeaders.isWorker(URL(string: "https://worker.example.dev.evil.com/"))
      && !VignetteHeaders.isWorker(URL(string: "http://worker.example.dev/"))
      && !VignetteHeaders.isWorker(URL(string: "https://worker.example.dev:8443/"))
      && !VignetteHeaders.isWorker(nil))

var toWorker = URLRequest(url: URL(string: "https://worker.example.dev/sync/push")!)
VignetteHeaders.apply(to: &toWorker)
check("a request to the worker carries both",
      toWorker.value(forHTTPHeaderField: "X-Vignette-Build") != nil
      && toWorker.value(forHTTPHeaderField: "X-Vignette-Surface") != nil)
var toProvider = URLRequest(url: URL(string: "https://api.example.com/v1/chat/completions")!)
VignetteHeaders.apply(to: &toProvider)
check("a request to a provider the student added carries neither",
      toProvider.allHTTPHeaderFields?.keys.contains { $0.lowercased().hasPrefix("x-vignette") } != true)

// MARK: leaving

// the server never holds an Apple token it could revoke, so deleting an Apple
// account leaves one step in Settings, and only an Apple account does
check("deleting an Apple account leaves the Settings step",
      AuthProvider.apple.listedInSettingsAfterDeletion)
check("no other way in leaves one",
      AuthProvider.allCases.filter(\.listedInSettingsAfterDeletion) == [.apple])

// MARK: legal links

check("only the pages the worker serves (server/legal.js)", LegalLinks.Page.allCases.map(\.rawValue) == ["privacy", "terms"])
check("the terms, in Arabic",
      LegalLinks.url(.terms, language: "ar").absoluteString == "https://worker.example.dev/terms?lang=ar")
check("an unknown language falls back to English",
      LegalLinks.url(.privacy, language: "fr").absoluteString == "https://worker.example.dev/privacy?lang=en")
check("the first language the pages come in",
      LegalLinks.languageCode(preferred: ["fr-FR", "ar-EG", "en-GB"]) == "ar"
      && LegalLinks.languageCode(preferred: ["en-US", "ar"]) == "en"
      && LegalLinks.languageCode(preferred: ["de"]) == "en" && LegalLinks.languageCode(preferred: []) == "en")
check("a placeholder resolves", LegalLinks.resolve(URL(string: "legal://terms")!)?.path == "/terms")
check("an unknown placeholder does not",
      LegalLinks.resolve(URL(string: "legal://medical")!) == nil
      && LegalLinks.resolve(URL(string: "https://worker.example.dev/terms")!) == nil)

print(failures.isEmpty ? "\nALL GATES TESTS PASS"
                       : "\n\(failures.count) GATES TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
