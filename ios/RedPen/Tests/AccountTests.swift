// Getting in, and staying in.
//
// Both halves fail quietly when they are wrong: a malformed redirect looks like
// a sign-in that just does not work, and a mishandled expiry date looks like an
// app that has decided you did not pay.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let now = Date(timeIntervalSince1970: 1_700_000_000)

// MARK: PKCE

let verifier = AuthRules.verifier()
let challenge = AuthRules.challenge(for: verifier)
check("a verifier is not its own challenge", verifier != challenge)
check("the same verifier always gives the same challenge",
      AuthRules.challenge(for: verifier) == challenge)
check("two verifiers differ", AuthRules.verifier() != AuthRules.verifier())
// a + or / or = in a query string is a sign-in that fails for one user in ten
// and works on the developer's machine
check("a challenge is safe to put in a URL",
      !challenge.contains("+") && !challenge.contains("/") && !challenge.contains("="),
      challenge)
check("a hashed nonce is hex",
      AuthRules.sha256Hex("abc").count == 64
        && AuthRules.sha256Hex("abc").allSatisfy { $0.isHexDigit })
check("the same input hashes the same way twice",
      AuthRules.sha256Hex("abc") == AuthRules.sha256Hex("abc"))

// MARK: the redirect

let good = URL(string: "redpen://auth?code=xyz123&state=abc")!
check("the code comes back out of the redirect",
      AuthRules.code(fromRedirect: good, expectedState: "abc") == "xyz123")
// without this, anything that can open a URL in this app can hand it someone
// else's authorisation code
check("a redirect with the wrong state is refused",
      AuthRules.code(fromRedirect: good, expectedState: "different") == nil)
check("a redirect with no code is refused",
      AuthRules.code(fromRedirect: URL(string: "redpen://auth?state=abc")!,
                     expectedState: "abc") == nil)
check("an error redirect is refused",
      AuthRules.code(fromRedirect: URL(string: "redpen://auth?error=access_denied&state=abc")!,
                     expectedState: "abc") == nil)
check("an empty code is refused",
      AuthRules.code(fromRedirect: URL(string: "redpen://auth?code=&state=abc")!,
                     expectedState: "abc") == nil)

// MARK: sessions

let account = Account(id: "u1", provider: .apple)
let live = Session(account: account, token: "t", refreshToken: "r",
                   expiresAt: now.addingTimeInterval(3600))
check("a live session is valid", live.isValid(now: now))
check("an expired one is not",
      !Session(account: account, token: "t", refreshToken: nil,
               expiresAt: now.addingTimeInterval(-1)).isValid(now: now))
// refreshed before it dies, so a session never expires mid-sentence
check("a session is refreshed before it expires",
      Session(account: account, token: "t", refreshToken: "r",
              expiresAt: now.addingTimeInterval(60)).needsRefresh(now: now))
check("and not while it has hours left", !live.needsRefresh(now: now))

// MARK: what counts as subscribed

check("never subscribed is free",
      Entitlement.access(EntitlementRecord(), now: now) == .free)

let renewing = EntitlementRecord(plan: .yearly, expiresAt: now.addingTimeInterval(86_400),
                                 verifiedAt: now)
check("a live subscription is pro", Entitlement.access(renewing, now: now).isPro)

// a bounced card is not a cancellation, and the month is already paid for
let retrying = EntitlementRecord(plan: .monthly, expiresAt: now.addingTimeInterval(-86_400),
                                 verifiedAt: now, inBillingRetry: true)
check("a failed renewal keeps working while the App Store retries",
      Entitlement.access(retrying, now: now).isPro)
if case .grace(_, let why) = Entitlement.access(retrying, now: now) {
    check("and says why", why == .billingRetry)
} else {
    check("and says why", false)
}
let abandoned = EntitlementRecord(plan: .monthly, expiresAt: now.addingTimeInterval(-40 * 86_400),
                                  verifiedAt: now, inBillingRetry: true)
check("a retry that never succeeded does end",
      !Entitlement.access(abandoned, now: now).isPro)

// somebody revising on a plane must not be told to buy the app again
let unreachable = EntitlementRecord(plan: .yearly, expiresAt: now.addingTimeInterval(-3600),
                                    verifiedAt: now.addingTimeInterval(-7200))
check("a subscription we could not re-check keeps working for a few days",
      Entitlement.access(unreachable, now: now).isPro)
check("but not for ever",
      !Entitlement.access(unreachable, now: now.addingTimeInterval(5 * 86_400)).isPro)

// the asymmetry that matters: if we DID manage to ask after it expired, and it
// is still expired, it is genuinely over
let confirmed = EntitlementRecord(plan: .yearly, expiresAt: now.addingTimeInterval(-3600),
                                  verifiedAt: now)
check("a lapse confirmed by the App Store is a lapse",
      Entitlement.access(confirmed, now: now) == .lapsed)

// MARK: when to ask again

check("a phone that has never asked, asks",
      Entitlement.shouldRefresh(EntitlementRecord(), now: now))
check("a live subscription is not re-checked every minute",
      !Entitlement.shouldRefresh(renewing, now: now.addingTimeInterval(600)))
check("but is re-checked every hour",
      Entitlement.shouldRefresh(renewing, now: now.addingTimeInterval(4000)))
// the moment a renewal goes through, the paywall should stop appearing
check("anything lapsed is re-checked at once",
      Entitlement.shouldRefresh(confirmed, now: now))

print(failures.isEmpty ? "\nALL ACCOUNT TESTS PASS"
                       : "\n\(failures.count) ACCOUNT TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
