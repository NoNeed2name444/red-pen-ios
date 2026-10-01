> **Source design, feature group B** (architect output, 2026-09-24), copied verbatim.
> It is an input to [`../implementation-plan.md`](../implementation-plan.md). Where the two disagree, **the plan wins**:
> see the plan's section 2 (conflict resolutions) and the work package that implements this design.

# Vignette, feature group B (monetisation): implementation design

Design only. No code or docs were changed. It is based on reading these files in `/tmp/claude-0/-home-user/8857977a-f678-5988-9658-6061ad2dfd91/scratchpad/rp-prev`: `server/worker.js`, `server/ai.js` (isPro / askApple / linkSubscription / wallet / budget), `server/tokens.js`, `server/pair.js`, `server/schema.sql`, `server/wrangler.toml`, `server/tests/pair.test.mjs`, `ios/RedPen/Shared/SubscriptionStore.swift`, `ios/RedPen/Shared/Entitlement.swift`, `ios/RedPen/Shared/AuthAPI.swift`, `ios/RedPen/Shared/PersonalBuild.swift`, `ios/RedPen/Shared/OwnerClaim.swift`, `ios/RedPen/Features/Paywall/PaywallView.swift`, `ios/RedPen/Features/Auth/AccountView.swift`, `ios/RedPen/RedPen.storekit`, `ios/project.yml`, `.github/workflows/{worker-deploy,server-tests,swift-tests}.yml` and `../make_swiftpm.py`.

Apple and Cloudflare facts were checked against current sources:
- **Apple's Node `app-store-server-library`** (`jws_verification.ts` and its models):
  - the certificate chain is exactly 3; the intermediate must carry OID 1.2.840.113635.100.6.2.1 and the leaf OID 1.2.840.113635.100.6.11.1;
  - when online checks are off, the "effective date" is the payload's `signedDate`;
  - `NotificationTypeV2` now includes ONE_TIME_CHARGE, RESCIND_CONSENT, METADATA_UPDATE, MIGRATION and PRICE_CHANGE; `offerType` 3 means an offer code.
- **Apple Root CA G3**, downloaded: SHA-256 `63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179`, P-384, valid until 2039. WWDR G6 is the current intermediate (P-384, signed with ecdsa-with-SHA384).
- **StoreKit views**: `SubscriptionStoreView(productIDs:marketingContent:)` lists options in the order of the array. `inAppPurchaseOptions((Product) async -> Set<Product.PurchaseOption>)` exists.
- **AppTransaction**: `appTransactionID` is globally unique per Apple Account per app and stays the same across reinstalls and devices.
- **Offer codes**: `offerIdentifier` holds the offer's reference name, never the code a customer typed. Each Apple Account can redeem one code per offer. Limits are up to 10 active offers per SKU and 1M redemptions per app per quarter. Offer codes now also work for non-renewing in-app purchases.
- **App Review Guidelines**, current text of 3.1.1, 3.1.2, 3.1.3(b)/(c), 2.3.1 and 5.6.3.
- **Egypt storefront**: prices are in EGP, with 14% VAT.

---

## 0. Launch blockers found in the existing code (fix in wave 1)

1. **`SubscriptionStore.isPro` returns `true` for everyone** (`var isPro: Bool { true }`, "Personal build: everything is unlocked"). As shipped to the App Store, every user would get Pro. Change it to `PersonalBuild.isOn || access.isPro`, where `access` merges StoreKit, the exam pass and the server's answer (see §4.3).
2. **Without App Store Connect keys, `isPro` → `askApple` returns `{until: 0}`** (the `none` answer). Every 6 hours that overwrites `verified_until = 0`, so a subscriber the server believed in loses Pro on the server. Once notifications and signed transactions keep the state current, `askApple` has to return `null` ("no answer, the last answer stands") when the keys are missing.
3. **`AuthAPI.send` maps 401 and 403 to `.signedOut`, and 404 to `.notConfigured`.** New routes must never use 403 or 404 for business errors such as "group full", "wrong code" or "bought by another account". Use 400, 409, 410 or 422 with a machine-readable `code` (§3.0). The existing `linkSubscription` 403 is harmless only because `report()` ignores it with `try?`.
4. **The paywall's Terms and Privacy links point to `https://redpen.app/...`**, which may not be a domain the owner controls. Group F hosts `/terms` and `/privacy` on the Worker; the paywall must link there.
5. **Deleting an account strands its subscription.** The subscription's `appAccountToken` names the deleted account, so `linkSubscription` gives a new account a 403 for ever. The "orphaned token" rule in §2.4 fixes this.

---

## 1. Products and the App Store setup the code assumes

| Product | Type | ID | Period | Offer | Paywall |
|---|---|---|---|---|---|
| Pro Annual | auto-renewable, group "Vignette Pro", level 1 | `com.redpen.pro.yearly` (existing) | P1Y | Introductory: **free, 1 week**, new subscribers | listed first, so selected by default |
| Pro Monthly | auto-renewable, same group, level 1 | `com.redpen.pro.monthly` (existing) | P1M | none | second |
| Exam Pass | **non-renewing subscription** | `com.redpen.pass.exam3m` (new) | the app defines it as 92 days | offer codes allowed | compact `ProductView` row under the picker |

**Why the exam pass is non-renewing.** "Pay once for exam season, nothing renews" is the whole selling point. A 3-month auto-renewing plan called a "pass" would risk a misleading-offer complaint (3.1.2 / 2.3.1). The cost is that the app and the server must work out its expiry, stack repeat purchases and restore it on every device:
- StoreKit's `Transaction.all` includes non-renewing transactions on any device signed in to the same Apple Account.
- The server records passes against the Vignette account (§2.4).
- Apple sends ONE_TIME_CHARGE and REFUND notifications for it.

**Stacking rule** (identical on server and client, with shared test vectors):
- Sort non-revoked pass purchases by `purchaseDate`.
- `end = max(purchase, previousEnd) + 92 days`.
- Refunded purchases (with a `revocationDate`) are skipped.
- While an auto-renewable subscription is active, the exam pass row is hidden.

**Family Sharing** stays off (`familyShareable: false`). It keeps "one Apple Account, one `appTransactionID`" meaningful for referrals.

**`RedPen.storekit` changes**, used by Xcode runs and the UI tests:
- On the yearly product: `"introductoryOffer": {"internalID":"INTRO-Y1W","numberOfPeriods":1,"paymentMode":"free","subscriptionPeriod":"P1W"}`.
- On both subscriptions, a test offer code: `"codeOffers": [{"eligibility":["new","expired","existing"],"internalID":"AMB-TEST","isStackable":true,"numberOfPeriods":1,"paymentMode":"free","referenceName":"amb-test","subscriptionPeriod":"P1M"}]`.
- The pass: `"nonRenewingSubscriptions": [{"displayPrice":"12.99","familyShareable":false,"internalID":"6740003","localizations":[{"description":"Three months of Pro for exam season. One payment, never renews.","displayName":"Exam Pass (3 months)","locale":"en_US"}],"productID":"com.redpen.pass.exam3m","referenceName":"Exam Pass 3 months","type":"NonRenewingSubscription"}]`.
- An Arabic (`ar`) localisation next to each `en_US` one.
- Rename the group to "Vignette Pro". The group ID is not used in code, because the paywall is built from product IDs.

---

## 2. Server data model

### 2.1 New columns on `accounts`

Add these to the `CREATE TABLE` in `schema.sql` for fresh databases, and to the ALTER loop in `worker-deploy.yml` for existing ones:

```sql
account_token      TEXT,                       -- the appAccountToken UUID (lowercase) = accountToken(id); set on create and lazily on /account/status
paid_until         INTEGER NOT NULL DEFAULT 0, -- latest end of a PRODUCTION subscription or pass (revenue); budget() counts this
referral_code      TEXT,                       -- 7 chars from pair.js ALPHABET, made lazily
app_transaction_id TEXT,                       -- this account's Apple Account (verified AppTransaction), for self-referral checks
last_seen_day      TEXT                        -- 'YYYY-MM-DD' of the last /account/status (referral "came back" signal)
```

Indexes on these columns go in the deploy step **after** the ALTERs, never in `schema.sql`. Otherwise `schema.sql` fails on an old database that does not have the columns yet. This is the same pattern as the existing `accounts_original_transaction` index.

```sql
CREATE UNIQUE INDEX IF NOT EXISTS accounts_account_token ON accounts (account_token) WHERE account_token IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS accounts_referral_code ON accounts (referral_code) WHERE referral_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS accounts_app_transaction ON accounts (app_transaction_id);
```

`verified_until`, `checked_at`, `apple_env` and `original_transaction_id` keep their meaning. `verified_until` becomes a cache of "Apple subscription or pass entitled until", sandbox included.

### 2.2 New tables (append to `schema.sql`; all `IF NOT EXISTS`)

```sql
-- Every App Store subscription Apple has told us about, whoever it belongs to.
-- Apple's signed data is the only writer; an unmatched row waits here until
-- its account shows up (/account/subscription or a later notification).
CREATE TABLE IF NOT EXISTS apple_subscriptions (
  original_transaction_id TEXT PRIMARY KEY,
  account_id        TEXT,
  account_token     TEXT,               -- appAccountToken from Apple, lowercase; NULL for offer-code/App Store-app purchases
  app_transaction_id TEXT,
  product_id        TEXT NOT NULL,
  state             TEXT NOT NULL,      -- active | grace | retry | expired | revoked
  expires_at        INTEGER NOT NULL DEFAULT 0,   -- seconds
  entitled_until    INTEGER NOT NULL DEFAULT 0,   -- expires_at, or grace end while in grace; 0 when revoked
  auto_renew        INTEGER,
  environment       TEXT NOT NULL,      -- Production | Sandbox
  storefront        TEXT,               -- ISO alpha-3, for regional pricing insight
  first_offer_type  INTEGER, first_offer_id TEXT,   -- the offer on the first purchase (ambassador attribution)
  last_offer_type   INTEGER, last_offer_id  TEXT,
  converted_at      INTEGER,            -- first paid renewal after a trial/offer
  signed_at         INTEGER NOT NULL,   -- ms: newest Apple signedDate applied (ordering guard)
  updated_at        INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS apple_subscriptions_account ON apple_subscriptions (account_id);
CREATE INDEX IF NOT EXISTS apple_subscriptions_token   ON apple_subscriptions (account_token);
CREATE INDEX IF NOT EXISTS apple_subscriptions_offer   ON apple_subscriptions (first_offer_id);

-- Exam passes (non-renewing): one row per purchase, stacked by passUntil().
CREATE TABLE IF NOT EXISTS apple_passes (
  transaction_id    TEXT PRIMARY KEY,
  original_transaction_id TEXT NOT NULL,
  account_id        TEXT,
  account_token     TEXT,
  product_id        TEXT NOT NULL,
  purchased_at      INTEGER NOT NULL,   -- seconds
  days              INTEGER NOT NULL,   -- from PASS_PRODUCTS (92)
  revoked_at        INTEGER,
  environment       TEXT NOT NULL,
  offer_id          TEXT,
  signed_at         INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS apple_passes_account ON apple_passes (account_id);
CREATE INDEX IF NOT EXISTS apple_passes_token   ON apple_passes (account_token);

-- App Store Server Notifications V2 received: dedupe + an owner-visible log.
-- Extracted fields only (no raw payload); pruned after 180 days by the cron.
CREATE TABLE IF NOT EXISTS apple_notifications (
  uuid        TEXT PRIMARY KEY,         -- notificationUUID
  type        TEXT NOT NULL,
  subtype     TEXT,
  environment TEXT,
  signed_at   INTEGER NOT NULL,         -- ms
  original_transaction_id TEXT,
  account_id  TEXT,
  outcome     TEXT NOT NULL,            -- applied | stale | unmatched | logged
  received_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS apple_notifications_received ON apple_notifications (received_at);

-- Pro time the App Store did not sell: referral rewards and welcome days.
-- 'banked' credits start only when the account is not otherwise Pro.
CREATE TABLE IF NOT EXISTS pro_grants (
  id          TEXT PRIMARY KEY,         -- 'ref:<referralId>:r' | 'ref:<referralId>:e' | 'gift:<uuid>'
  account_id  TEXT NOT NULL,
  kind        TEXT NOT NULL,            -- referral | welcome | gift
  days        INTEGER NOT NULL,
  state       TEXT NOT NULL,            -- banked | active | used | void
  starts_at   INTEGER, ends_at INTEGER,
  bank_expires_at INTEGER NOT NULL,     -- a banked credit lapses after BANKED_CREDIT_DAYS
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS pro_grants_account ON pro_grants (account_id, state);

-- Referrals. One per Apple Account ever (app_transaction_id UNIQUE survives
-- account deletion, with the account ids nulled).
CREATE TABLE IF NOT EXISTS referrals (
  id          TEXT PRIMARY KEY,
  referrer_id TEXT,
  referee_id  TEXT,
  app_transaction_id TEXT NOT NULL UNIQUE,
  code        TEXT NOT NULL,
  state       TEXT NOT NULL,            -- pending | rewarded | capped | void
  claimed_at  INTEGER NOT NULL,
  claim_day   TEXT NOT NULL,
  decided_at  INTEGER,
  reason      TEXT
);
CREATE INDEX IF NOT EXISTS referrals_referrer ON referrals (referrer_id, state, decided_at);
CREATE UNIQUE INDEX IF NOT EXISTS referrals_referee ON referrals (referee_id) WHERE referee_id IS NOT NULL;

-- Class access ("group licences"), created only by the owner.
CREATE TABLE IF NOT EXISTS licence_groups (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,            -- "Ain Shams MBBCh Year 4, 2026"
  institution TEXT,
  join_code   TEXT NOT NULL UNIQUE,     -- 10 chars from ALPHABET (~49.5 bits)
  seats       INTEGER NOT NULL,
  ends_at     INTEGER NOT NULL,
  paid_models INTEGER NOT NULL DEFAULT 0,        -- 1 only when an institution pays: cloud spend from its own budget
  monthly_budget_usd REAL NOT NULL DEFAULT 0,
  class_id    TEXT,                     -- optional link to group A's class
  created_by  TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  disabled_at INTEGER
);
CREATE TABLE IF NOT EXISTS licence_members (
  group_id   TEXT NOT NULL,
  account_id TEXT NOT NULL,
  joined_at  INTEGER NOT NULL,
  removed_at INTEGER,
  PRIMARY KEY (group_id, account_id)
);
CREATE INDEX IF NOT EXISTS licence_members_account ON licence_members (account_id);

-- Ambassadors (one per medical school) and the Apple offer each one maps to.
CREATE TABLE IF NOT EXISTS ambassadors (
  id           TEXT PRIMARY KEY,        -- slug: 'ain-shams'
  name         TEXT NOT NULL,
  school       TEXT NOT NULL,
  offer_ref    TEXT UNIQUE,             -- ASC offer reference name == transaction.offerIdentifier ('amb-ain-shams')
  custom_code  TEXT,                    -- the ASC custom code shown on their page ('AINSHAMS26')
  account_id   TEXT,                    -- their Vignette account (their referral code attributes too)
  active       INTEGER NOT NULL DEFAULT 1,
  created_at   INTEGER NOT NULL
);

-- Facts the worker learns (not config): e.g. apple_app_id from a verified
-- Production notification or the iTunes lookup API.
CREATE TABLE IF NOT EXISTS app_facts (
  key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL
);
```

If group D creates a config table, `app_facts` can merge into it. Settings (§2.3) are read as "D's remote config first, then `env`".

### 2.3 New `[vars]` in `wrangler.toml` (no new secrets)

```
APPLE_APP_ID = ""                        # optional; learned automatically (app_facts) once known
APPLE_ENVIRONMENTS = "Production,Sandbox" # environments accepted (Xcode/LocalTesting never)
SUB_PRODUCTS = "com.redpen.pro.monthly,com.redpen.pro.yearly"
PASS_PRODUCTS = "com.redpen.pass.exam3m:92"
REFERRALS = "on"
REFERRAL_REWARD_DAYS = "30"
REFERRAL_REFEREE_DAYS = "7"
REFERRAL_MAX_PER_MONTH = "3"
REFERRAL_MAX_PER_YEAR = "12"
REFERRAL_HOLD_HOURS = "72"
REFERRAL_CLAIM_WINDOW_DAYS = "7"
BANKED_CREDIT_DAYS = "365"
GROUP_LICENCES = "on"
GROUP_DELIVERY = "grant"                 # grant | offer-codes (review fallback, §5)
```

- The existing optional secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY` become **optional extras**. They enable the test notification, catching up on missed notifications and `askApple`. Nothing in group B needs them.
- Add a daily cron: `[triggers] crons = ["17 3 * * *"]`, with `export default { fetch, scheduled }` in `worker.js`.

### 2.4 Rules the tables enforce

- **Who owns an Apple transaction.** A signed transaction can be linked to account X only if one of these holds:
  - (a) its `appAccountToken` equals `accountToken(X)`;
  - (b) its `appAccountToken` belongs to no existing account (orphaned by a deletion); the first to present it wins and the row is rebound;
  - (c) it has no `appAccountToken` (offer-code redemption through the App Store app, or a promoted purchase), no other account holds it, and the existing unique index decides.

  A token that belongs to a **live** other account is refused with 409 `bought_by_other_account`. This replaces the 403 in `linkSubscription`.
- **Ordering.** A notification or transaction whose `signedDate` is older than `apple_subscriptions.signed_at` updates nothing; its outcome is recorded as `stale`. Apple delivers notifications out of order and retries them at 1, 12, 24, 48 and 72 hours.
- **Revenue vs access.** `paid_until` includes Production subscriptions and passes only. Sandbox (TestFlight) purchases unlock Pro but never count as revenue and **never** reach paid models.
- **Account deletion** (extends `deleteAccount`), in one `env.DB.batch`:
  - `DELETE FROM licence_members WHERE account_id=?`
  - `DELETE FROM pro_grants WHERE account_id=?`
  - `UPDATE referrals SET referee_id=NULL WHERE referee_id=?`
  - `UPDATE referrals SET referrer_id=NULL, state=CASE state WHEN 'pending' THEN 'void' ELSE state END WHERE referrer_id=?`
  - `UPDATE apple_subscriptions SET account_id=NULL WHERE account_id=?`
  - `UPDATE apple_passes SET account_id=NULL WHERE account_id=?`
  - `UPDATE apple_notifications SET account_id=NULL WHERE account_id=?`

  Apple's transaction records stay without personal data, so refunds and relinking still work. State this retention in the privacy policy (group F).

---

## 3. Worker: modules, routes, request/response shapes and auth

### 3.0 Conventions

- The error body becomes `{ "error": msg, "message": msg, "code": "snake_case" }`. Extend `fail(status, message, code)` and add `code` to `AuthAPI.Problem`.
- Business errors use 400, 409, 410, 422 or 429. Never 401, 403 or 404, except that owner routes answer 404 to non-owners, so they stay invisible.
- Every time is **epoch seconds (Int)** in JSON, which avoids any disagreement over date-decoding strategy.
- Size limits go in the existing `allowed` ladder: `/apple/notifications` 256 KB; `/account/subscription` 512 KB (up to 20 signed transactions of 16 KB each); everything else 64 KB.
- **GET routing**: add a `GET` branch before `if (request.method !== 'POST')` for `/r/:code`, `/g/:code` and `/a/:slug`. Coordinate with group A, which adds `/s/:id`, the page template and `/.well-known/apple-app-site-association`; B adds `"/r/*"` and `"/g/*"` to the AASA paths.
- **Owner check**, `isOwner(request, env, accountId)`: `isOwnerKey(request, env)`, or `accounts.owner = 1`, or the id is in `OWNER_ACCOUNT_IDS`.

### 3.1 New server files

| File | Contents |
|---|---|
| `server/x509.js` | A DER reader that never throws: `readTLV(bytes, at)`, `parseCert(der) → { tbsRaw, sigAlgOid, sigDer, issuerRaw, subjectRaw, notBefore, notAfter (ms), spkiRaw, curveOid, extOids:Set, isCA }` or `null`. Also `ecdsaDerToRaw(der, size) → Uint8Array` or `null`, and `parseTime` for UTCTime (YY<50 → 20YY) and GeneralizedTime. Long-form lengths up to 4 bytes; indefinite lengths rejected; bounds checked. |
| `server/apple-root.js` | `APPLE_ROOT_CA_G3_DER_BASE64` (the public 583-byte certificate) and `APPLE_ROOT_CA_G3_SHA256 = '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179'`. At module load, check the fingerprint of the embedded DER. Also `setTrustedRootsForTests(ders)`, which is exported but never reachable from `env` or requests. |
| `server/appstore.js` | `verifyAppleJWS`, `verifyTransaction`, `verifyRenewal`, `verifyAppTransaction`, `handleNotification(request, env)`, `applyTransaction`, `applyRenewal`, `linkSigned(env, accountId, body)`, `requestTestNotification(env)` (optional, needs ASC keys). |
| `server/entitlement.js` | `entitlement(env, accountOrId, {activate=true})`, `passUntil(rows)`, `activateBanked`, `snapshot()` (the `/account/status` body). |
| `server/referrals.js` | `referralMe`, `claimReferral`, `settleReferrals(env)` (cron and lazy), `referralPage` (GET `/r/:code`). |
| `server/groups.js` | `joinGroup`, `leaveGroup`, `myGroups`, `groupPage` (GET `/g/:code`), and owner CRUD. |
| `server/owner.js` | `/owner/*` dispatch: groups, ambassadors, billing summary, notification log, test notification, gift. |

**Changes to `server/ai.js`**, kept small because another job is editing it:
- `isPro(env, account)` → `(await entitlement(env, account)).pro`. Keep the `askApple` recheck only when ASC keys are set and `checked_at` is more than 24 hours old.
- `askApple` returns `null` when the keys are missing (blocker 2).
- `wallet()` returns `null`, meaning free models only, when the entitlement is not `paying`. Referral, welcome, sandbox and unpaid-group Pro never spend money. A group with `paid_models=1` gets the wallet key `group:<id>` with `cap = monthly_budget_usd`.
- `budget()` counts subscribers as `paid_until > now`, with a try/catch fallback to the current query.

**Changes to `server/worker.js`**: the new routes, the GET branch, the `scheduled()` handler, `deleteAccount` additions, and setting `account_token` in `upsert()`.

### 3.2 Verifying Apple's JWS: `verifyAppleJWS(jws, { now = Date.now() })`

The function returns the payload or `null` and never throws. Every step is required.

1. `jws` is a string of at most 64 KB with exactly 3 parts, each valid base64url.
2. The header JSON has `alg === 'ES256'`, and `x5c` is an array of **exactly 3** standard-base64 strings, each at most 8 KB. Cheap early reject: the DER of `x5c[2]` must be byte-equal to a trusted root. Otherwise return `null` before doing any crypto; this matters for Workers CPU.
3. Parse `leaf = x5c[0]` and `inter = x5c[1]`. The root comes from the **pinned** DER parsed at module load, never from the header.
4. Chain:
   - `inter.issuerRaw == root.subjectRaw` and `leaf.issuerRaw == inter.subjectRaw` (byte-equal).
   - `inter` is verified with root's key, then `leaf` with inter's key, using `crypto.subtle.verify({name:'ECDSA', hash})`.
   - The hash comes from `sigAlgOid`: `1.2.840.10045.4.3.2` is SHA-256 and `1.2.840.10045.4.3.3` is SHA-384. The curve comes from the issuer's SPKI: `1.2.840.10045.3.1.7` is P-256 and `1.3.132.0.34` is P-384.
   - The DER signature is converted to raw r‖s (32 or 48 bytes).
5. `inter.isCA === true` and `inter.extOids.has('1.2.840.113635.100.6.2.1')`. `leaf.extOids.has('1.2.840.113635.100.6.11.1')`.
6. Decode the payload JSON (an object, not an array). `signedDate` must be a number and no later than `now + 5 min`. Leaf, intermediate and root must each be within `notBefore ≤ signedDate ≤ notAfter`. This matches Apple's library when online checks are off.
7. The leaf SPKI curve is P-256, the signature part decodes to exactly 64 bytes, and `subtle.verify(ECDSA/SHA-256)` passes over the ASCII of `part0.part1`.
8. Cache per isolate: a Map from `sha256(leafDer‖interDer)` to `{leafKey, validity}`, at most 32 entries. Dates are still checked on every call. Nested JWS (transaction and renewal) then cost one ECDSA verify each.

**Callers then check the contents:**
- `bundleId === env.APPLE_BUNDLE_ID`.
- `environment` is in `APPLE_ENVIRONMENTS`, so Xcode and LocalTesting are refused.
- `appAppleId === APPLE_APP_ID` when known (from the var or `app_facts`) and the environment is Production.
- For a notification: the nested `data.signedTransactionInfo` and `data.signedRenewalInfo` go through the same verifier. **Never** `decodeClaims` for them.

**Deliberately left out: OCSP revocation.** Workers cannot easily build OCSP requests. This is Apple's own offline-mode behaviour. The mitigation is that when ASC keys exist, a SUBSCRIBED or REFUND notification also triggers `askApple` to confirm over TLS.

**CPU**: at most 3 ECDSA verifies on a cold chain and 1 when cached. This fits the free plan's 10 ms CPU limit. Log `Date.now()` deltas in development.

### 3.3 Routes

**`POST /apple/notifications`** (no session: Apple is the caller, and the signature is the authentication)

Request `{ "signedPayload": "<JWS>" }`.

1. Verify the payload. On failure return **401** `{code:"bad_signature"}` with **no D1 writes**. Apple never sees this answer; only forged requests get it.
2. Dedupe with `INSERT ... ON CONFLICT(uuid) DO NOTHING` into `apple_notifications`. If the row already existed, return 200 `{ok:true, duplicate:true}`.
3. Learn `data.appAppleId` into `app_facts.apple_app_id` from the first verified Production notification.
4. Act on the type:

| notificationType (subtype) | Action |
|---|---|
| SUBSCRIBED (INITIAL_BUY, RESUBSCRIBE), DID_RENEW (incl. BILLING_RECOVERY), OFFER_REDEEMED, DID_CHANGE_RENEWAL_PREF, DID_CHANGE_RENEWAL_STATUS, RENEWAL_EXTENDED, REFUND_REVERSED, PRICE_INCREASE, PRICE_CHANGE, METADATA_UPDATE, MIGRATION | `applyTransaction` + `applyRenewal` (upsert state, recompute `entitled_until`) |
| DID_FAIL_TO_RENEW (GRACE_PERIOD) | state `grace`, `entitled_until = renewal.gracePeriodExpiresDate` |
| DID_FAIL_TO_RENEW (no subtype) | state `retry`, `entitled_until = expires_at` (already past) |
| GRACE_PERIOD_EXPIRED, EXPIRED (any subtype) | state `expired` |
| REFUND, REVOKE | subscription: state `revoked`, `entitled_until = 0`; pass: `revoked_at = revocationDate` |
| ONE_TIME_CHARGE | pass product → upsert `apple_passes` |
| TEST, REFUND_DECLINED, CONSUMPTION_REQUEST, RENEWAL_EXTENSION (SUMMARY/FAILURE), RESCIND_CONSENT, EXTERNAL_PURCHASE_TOKEN, unknown | log only |

**How `entitled_until` is computed**: `revocationDate` → 0; otherwise, if `renewal.gracePeriodExpiresDate > now` and the renewal is in billing retry → the grace end; otherwise `expiresDate`.

**Which account it belongs to**, in order: `apple_subscriptions.account_id`, then `accounts.original_transaction_id = otid`, then `accounts.account_token = appAccountToken`. If none matches, the outcome is `unmatched`: the row is stored, and a later `/account/subscription` binds it.

**When an account is found**, one `env.DB.batch` does all of this:
- updates `apple_subscriptions`;
- `UPDATE accounts SET verified_until=?, paid_until=?, checked_at=?, apple_env=?, original_transaction_id=COALESCE(original_transaction_id, ?)`, guarded by the unique index;
- records `converted_at` on the first DID_RENEW after an offer or trial.

**Responses**: 200 `{ok:true}` once processed or logged; **500 on a D1 error**, so Apple retries.

**`POST /account/status`** (session) returns the entitlement snapshot and sets `last_seen_day` and `account_token` if they are empty:

```json
{ "pro": true, "until": 1793000000, "source": "subscription", "paying": true, "owner": false,
  "sources": [
    {"kind":"subscription","productId":"com.redpen.pro.yearly","state":"active","until":1793000000,"autoRenew":true,"environment":"Production"},
    {"kind":"pass","until":1780000000},
    {"kind":"group","groupId":"g_…","name":"Ain Shams Y4 2026","until":1790000000},
    {"kind":"referral","until":1777000000} ],
  "banked": [{"kind":"referral","days":30,"expires":1810000000}],
  "features": {"referrals":true,"groupLicences":true},
  "appStoreId": "6740000000" }
```

- `source` is picked in this order: owner > subscription > pass > group > referral/welcome/gift.
- If the account is not otherwise Pro, it activates the oldest banked credit atomically:

  ```sql
  UPDATE pro_grants SET state='active', starts_at=?, ends_at=?
  WHERE id=(SELECT id FROM pro_grants WHERE account_id=? AND state='banked' AND bank_expires_at>? ORDER BY created_at LIMIT 1)
    AND state='banked'
  ```

  Grants that have ended become `used`.

**`POST /account/subscription`** (session; the existing route, extended)

Request:

```json
{ "plan": "...", "expiresAt": "...", "originalTransactionId": "...",
  "signedTransactions": ["<JWS>", "..."], "signedRenewalInfo": ["<JWS>"] }
```

- Each signed item is verified (§3.2). The ownership rule (§2.4) applies, then `applyTransaction`. Items are at most 20 and each at most 16 KB.
- The old `originalTransactionId`-only path stays for old builds.
- Response `{ ok:true, pro, status:<snapshot> }`. Errors: 409 `bought_by_other_account`, 409 `linked_elsewhere`, 422 `bad_signature`.
- Rate limit: 30 per hour per account, using `allowed()` with the key `acct:<id>`.

**Referral routes** (session). All return 410 `{code:"referrals_off"}` when `REFERRALS != on`.

- **`POST /referrals/me`**
  - Request `{ "appTransaction": "<JWS>"? }`. If present and verified, it sets `accounts.app_transaction_id`.
  - Response `{ code:"K7M2Q9X", link:"https://<host>/r/K7M2Q9X", rewardDays:30, refereeDays:7, pending:1, rewarded:2, rewardedThisYear:2, capPerMonth:3, capPerYear:12 }`.
  - Counts only, never who.
- **`POST /referrals/claim`** (as the referee)
  - Request `{ "code":"K7M2Q9X", "appTransaction":"<JWS>" }`.
  - Checks, in order:
    - 3 claims per hour per IP key (`allowed`);
    - the code exists (else 400 `bad_code`);
    - the referrer is not the caller, and the referrer's `app_transaction_id` differs from the verified one (else 409 `self_referral`);
    - the caller's account is at most `REFERRAL_CLAIM_WINDOW_DAYS` old (else 409 `too_late`);
    - the caller has no referral row (else 409 `already_referred`);
    - the verified `appTransactionID` is not yet in `referrals` (else 409 `already_referred`);
    - the AppTransaction verifies with our bundle and an accepted environment (else 422 `not_eligible`; this is the Playgrounds case).
  - It inserts a `referrals` row in state `pending` and gives the referee a `welcome` grant of `REFERRAL_REFEREE_DAYS` (banked, so it activates at once if the referee is not Pro).
  - Response `{ ok:true, welcomeDays:7, status:<snapshot> }`.
- **`settleReferrals(env)`** (the cron, and lazily on the referrer's `/referrals/me` or `/account/status`)
  - A `pending` row becomes eligible when `now ≥ claimed_at + REFERRAL_HOLD_HOURS` **and** the referee account still exists **and** the referee's `last_seen_day > claim_day` (they came back on a later day).
  - Then it counts the referrer's `rewarded` rows in the calendar month and in the rolling 365 days. Under both caps the row becomes `rewarded` and a `referral` grant (30 days, banked) is added. Otherwise the row becomes `capped`.
  - Rows 30 days old that never become eligible become `void` with reason `inactive`.
- **`GET /r/:code`**: an HTML page in English and Arabic, chosen from `Accept-Language`, with `dir=rtl` for Arabic. It offers "Get Vignette" (App Store link when `appStoreId` is known, otherwise "Coming soon"), "Already installed? Open invite" (a universal link, or `redpen://r/CODE`), and "Copy code". It never names the referrer and has no tracking pixels.

**Group licence routes** (session). All return 410 `groups_off` when `GROUP_LICENCES != on`.

- **`POST /groups/join`**
  - Request `{ "code":"ABCDE-FGHJK" }`, normalised by `pair.js`'s `normalise`, extended to 10 characters.
  - Rate limit: 10 wrong codes per hour per IP key (as in `finishPairing`; a right code gives the try back).
  - Seat allocation in one statement:

    ```sql
    INSERT INTO licence_members (group_id, account_id, joined_at)
    SELECT g.id, ?, ?
    FROM licence_groups g
    WHERE g.join_code = ? AND g.disabled_at IS NULL AND g.ends_at > ?
      AND (SELECT COUNT(*) FROM licence_members m WHERE m.group_id = g.id AND m.removed_at IS NULL) < g.seats
    ON CONFLICT (group_id, account_id) DO UPDATE SET removed_at = NULL
    ```

  - If no row changed, it explains: 400 `bad_code`, 410 `group_ended`, or 409 `group_full`.
  - Response `{ ok:true, group:{id,name,institution,until}, status }`.
- **`POST /groups/leave`**: `{groupId}` sets `removed_at` and frees the seat.
- **`POST /groups/mine`**: returns `[ {id,name,institution,until} ]`.
- **`GET /g/:code`**: a page that says "Your class access from {institution}" with Open in app / App Store / Copy code. **No prices and no ways to buy.**

**Owner routes** (non-owners get 404)

- `POST /owner/groups/create`
  - Request `{ name, institution?, seats (1..5000), endsAt (≤ now + 400 days), paidModels=false, monthlyBudgetUsd=0, classId? }`.
  - Response `{ id, code, link }`.
- `POST /owner/groups/list`: `[ {id,name,institution,seats,used,endsAt,disabled,paidModels} ]`.
- `POST /owner/groups/update`: `{ id, seats?, endsAt?, disabled?, rotateCode? }` returns the new code when rotated.
- `POST /owner/groups/members`: `{id}` returns `[ {member:"m_3f9a", joinedAt} ]`, where `m_` is the first 4 hex digits of `sha256(accountId)`. No names or emails.
- `POST /owner/groups/remove`: `{ id, member }`.
- `POST /owner/ambassadors/upsert`: `{ id, name, school, offerRef, customCode?, accountId? }`.
- `POST /owner/ambassadors/stats`: `[ {id, school, offerRef, redemptions, activeNow, converted, referralsRewarded} ]`. Redemptions come from `apple_subscriptions.first_offer_id` and `apple_passes.offer_id`; referrals come from the ambassador account's referral rows.
- `POST /owner/billing/summary`:

  ```json
  { "subscribers": {"production":n, "sandbox":n}, "byProduct": {...}, "byStorefront": [top 10],
    "passesActive":n, "trialsActive":n, "groupSeatsUsed":n, "referralsRewardedThisMonth":n,
    "notificationsLast24h": {TYPE:n}, "lastNotificationAt": t, "budget": <budget(env)> }
  ```

- `POST /owner/billing/notifications`: the last 50 rows of `apple_notifications`.
- `POST /owner/billing/test-notification`: needs ASC keys. It calls `POST https://api.storekit.itunes.apple.com/inApps/v1/notifications/test`, falling back to the sandbox host, using the existing `appStoreToken()`, and returns `{testNotificationToken}`. Without the keys it returns 410 `asc_keys_missing`.
- `POST /owner/grants/gift`: `{ accountId, days ≤ 90, note }`. A goodwill fix, for example after an outage. Capped at 20 per month.

**`GET /a/:slug`** (public ambassador page): school name, the custom code, "Redeem in the App Store" → `https://apps.apple.com/redeem?ctx=offercodes&id=<appStoreId>&code=<CODE>`, and an App Store link. Shown only when `appStoreId` is known and the ambassador is active.

**`scheduled()`** (daily):
- `settleReferrals`;
- banked grants past `bank_expires_at` become `void`, and active grants past `ends_at` become `used`;
- `DELETE FROM apple_notifications WHERE received_at < now-180d`;
- `DELETE FROM pair_attempts WHERE hour < now/3600-48`;
- if `app_facts.apple_app_id` is missing, fetch `https://itunes.apple.com/lookup?bundleId=<APPLE_BUNDLE_ID>` (public, no key) and store `results[0].trackId`.

### 3.4 Security, privacy and abuse (server)

- **Forged notifications**: blocked by the pinned root, the OIDs, the ES256-only rule, the exact chain length and the byte-equal issuer/subject check. Bundle and environment are checked, and `appAppleId` too when known. Replays do nothing because of UUID dedupe and the per-transaction `signedDate` guard. Invalid requests cause no D1 writes.
- **Taking over someone's subscription**: prevented by the `appAccountToken` ownership rule (§2.4) plus the existing unique index. A transaction id alone is useless.
- **Referral farming** is limited in several ways:
  - one reward per **Apple Account** ever (`appTransactionID` is signed by Apple and unique);
  - self-referral is blocked by account id and by Apple Account;
  - a new referee account must claim within 7 days;
  - the referee must come back on a later day;
  - a 72-hour hold;
  - caps of 3 per month and 12 per year per referrer;
  - 3 claims per hour per IP;
  - a global off switch.

  The reward is Pro time on free models only, so a farmed month costs the owner nothing in AI spend.
- **Group codes**: about 49.5 bits, 10 wrong tries per IP per hour, seat caps, rotation, disabling, member removal, owner-only creation, and a maximum lifetime of 400 days.
- **IP handling**: new counters use `ipKey = first 16 hex of sha256(SESSION_SECRET + ip)` instead of the raw IP. The existing `pair_attempts` stores raw IPs; migrating it to `ipKey` is recommended. The cron deletes counters after 48 hours.
- **What the owner can see**: counts and short hashes only. No referee names, and no group member emails.
- **Money**: only Production subscriptions and passes, and groups with `paid_models=1` and their own budget, can reach paid models. Sandbox, referral, welcome, gift and unpaid-group Pro use free models, which satisfies "no paid credits for the owner".

---

## 4. App side (paths under `ios/RedPen`)

### 4.1 New files

| Path | Imports | Purpose |
|---|---|---|
| `Shared/ServerEntitlement.swift` | Foundation only | `struct ServerStatus: Codable, Equatable` mirroring the `/account/status` JSON (Int epoch times), plus a locally set `fetchedAt: Date`. `func grantUntil(now:) -> Date?` returns `min(until, fetchedAt + 7 days)` when `pro`. The 7-day trust window covers offline use while never trusting a stale grant for ever. Persisted as `redpen-server-entitlement.json` next to `redpen-entitlement.json`. If group C needs Pro inside widgets, move both files into the app-group container. |
| `Shared/InviteLinks.swift` | Foundation only | `enum InviteRoute: Equatable { case referral(String), group(String), ambassador(String) }`. `static func route(from url: URL) -> InviteRoute?` accepts `https://<any host>/r/CODE`, `/g/CODE`, `/a/SLUG`, `redpen://r/CODE` and `redpen://g/CODE`. `normalise(code:length:)` uses the same 31-character alphabet as `pair.js`. `display(code)` groups a 10-character code as `ABCDE-FGHJK`. |
| `Shared/BillingAPI.swift` | Foundation only | Thin wrappers over `AuthAPI.send`: `status(token:)`, `report(token:transactions:renewals:)`, `referralMe(token:appTransaction:)`, `claimReferral(token:code:appTransaction:)`, `joinGroup`, `leaveGroup`, `myGroups`, and `Owner.*` (groups, ambassadors, summary, notifications, testNotification). Error `code`s map to user messages (see `AuthAPI.Problem`). |
| `Features/Paywall/PaywallMarketing.swift` | SwiftUI | Header, perks (localised), `ExamPassRow`, and the line "For education, not clinical decisions" (group F's string). |
| `Features/Paywall/ExamPassRow.swift` | SwiftUI, StoreKit | `ProductView(id: ProPass.productID) { Image(systemName: "calendar.badge.clock") }.productViewStyle(.compact)` with the caption "3 months of Pro, one payment, never renews". Hidden while a subscription is active. |
| `Features/Account/InviteFriendsView.swift` | SwiftUI | Code, `ShareLink(item: link, message: …)`, counts ("2 friends joined · 2 months earned"), banked credits, the rules text (§7), and "Invites work in the App Store version" when `/referrals/me` is refused. |
| `Features/Account/JoinClassAccessView.swift` | SwiftUI | A text field plus `PasteButton(payloadType: String.self)` (no paste prompt), "Join", the current class access with "Leave". Title: "Class access". Copy: "Access provided by your school." |
| `Features/Account/RedeemOfferCodeButton.swift` | SwiftUI, StoreKit | `Button("Redeem a code") { presenting = true }.offerCodeRedemption(isPresented: $presenting) { _ in Task { await subscriptions.refreshAll() } }`. Apple's own sheet. |
| `Features/Account/Owner/OwnerToolsView.swift`, `OwnerGroupsView.swift`, `OwnerAmbassadorsView.swift`, `OwnerBillingView.swift` | SwiftUI | Shown only when `status.owner`. Create, rotate, disable and extend groups; add ambassadors (slug, school, offer reference name, custom code); billing summary, notification log and the "Send test notification" button. This is how the owner runs everything **from the phone, with no repository edits**. |
| `Tests/BillingTests.swift` | top-level suite | See §6.2. |

### 4.2 Changed files

**`Shared/Entitlement.swift`** (stays Foundation-only)

- Add `enum ProPass { static let productID = "com.redpen.pass.exam3m"; static let days = 92 }`.
- Add `struct PassPurchase: Codable, Equatable { var purchasedAt: Date; var revokedAt: Date? }`.
- Add `enum PassMath { static func until(_ purchases: [PassPurchase], days: Int = ProPass.days) -> Date? }`, implementing the stacking rule.
- `SubscriptionPlan`: add `static let paywallOrder: [SubscriptionPlan] = [.yearly, .monthly]` and change `groupName` to "Vignette Pro".
- `EntitlementRecord` gains `passUntil: Date?` and `server: ServerStatus?`. Both are optional, so old JSON still decodes.
- `Entitlement.access(record, now:)`:
  - start from the current StoreKit result;
  - if `passUntil > now` → `.pro(until: passUntil)` when that is later;
  - if `server?.grantUntil(now:) > now` → `.pro(until:)` when that is later;
  - order: pro beats grace beats lapsed beats free.
- New `Entitlement.source(record, now:) -> ProSource?` (`.subscription/.pass/.classAccess(name)/.referral/.owner`).
- `summary()` gains "Exam Pass until {date}", "Class access from {institution} until {date}" and "Free month from an invite until {date}".
- `Access` is unchanged, so existing pattern matches still compile.

**`Shared/SubscriptionStore.swift`**

- Remove the `isPro { true }` hack. It becomes `var isPro: Bool { PersonalBuild.isOn || access.isPro }` (blocker 1).
- `loadProducts()` also loads `ProPass.productID`.
- `refresh()` also iterates `Transaction.all` for the pass product. For each verified transaction it keeps `(purchaseDate, revocationDate)` and the result's `jwsRepresentation`. It sets `record.passUntil = PassMath.until(...)`. It keeps the subscription transactions' `jwsRepresentation` from `Transaction.currentEntitlements`, and the renewal JWS from `Product.SubscriptionInfo.status(for:)` → `status.renewalInfo.jwsRepresentation`.
- `report(token:)` sends `signedTransactions` and `signedRenewalInfo` (at most 20), plus the old fields, and stores the returned snapshot.
- New:
  - `func purchaseOptions() -> Set<Product.PurchaseOption>` adds `.appAccountToken(Self.accountToken(for: accountId))` when there is an account.
  - `func didPurchase(_ result: Result<Product.PurchaseResult, Error>) async`: `.success(.verified)` → `finish()`, `refresh()`, `report()`, `refreshServerStatus()`; `.pending` → the existing "Waiting for approval" message.
  - `func refreshServerStatus(token:) async` calls `BillingAPI.status` and saves it (with `fetchedAt`) into `record.server`.
  - `func refreshAll()`.
  - `func appTransactionJWS() async -> String?`: `try? await AppTransaction.shared`, returns `jwsRepresentation` only when the result is `.verified`.
- `buy(_:)` stays for the owner tools and tests. The paywall no longer calls it.

**`Features/Paywall/PaywallView.swift`** (rewritten on SubscriptionStoreView)

```swift
SubscriptionStoreView(productIDs: SubscriptionPlan.paywallOrder.map(\.rawValue)) {
    PaywallMarketing()                                   // perks + ExamPassRow + notice
}
.subscriptionStoreControlStyle(.prominentPicker)
.subscriptionStoreButtonLabel(.multiline)               // shows "Try 1 week free" + price when eligible
.storeButton(.visible, for: .restorePurchases, .redeemCode, .cancellation)
.subscriptionStorePolicyDestination(url: Legal.terms, for: .termsOfService)   // group F's Worker URLs
.subscriptionStorePolicyDestination(url: Legal.privacy, for: .privacyPolicy)
.inAppPurchaseOptions { _ in await subscriptions.purchaseOptions() }          // tags every purchase with the account
.onInAppPurchaseCompletion { _, result in await subscriptions.didPurchase(result) }
.onChange(of: subscriptions.isPro) { _, pro in if pro { dismiss() } }
```

- Annual is the default because it is listed first. The UI test in §6.2 asserts it; if an iOS release preselects differently, set `.subscriptionStoreControlStyle(.picker)` and re-run the test.
- The intro-offer wording, price, period, renewal terms and cancellation text are rendered by StoreKit itself, in Arabic too, which meets 3.1.2(c) and Schedule 2.
- Under the picker, `PaywallMarketing` adds our own line: "Payment is charged to your Apple Account. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period. Manage in Settings."
- The existing `yearlySaving` percentage can stay as marketing text.

**`Features/Auth/AccountView.swift`**, Subscription section:
- `Entitlement.summary(...)` with its source;
- "See plans" or "Manage or cancel" (existing);
- `RedeemOfferCodeButton`;
- "Restore purchases" (existing);
- then "Invite friends" → `InviteFriendsView` when `features.referrals`;
- "Class access" → `JoinClassAccessView` when `features.groupLicences`;
- "Owner tools" when `status.owner`.

**`RedPenApp.swift`**
- `.onOpenURL { url in if let r = InviteLinks.route(from: url) { invites.pending = r } }`, also reached by universal links in the Xcode build.
- The pending invite is kept in `UserDefaults` until an account exists. If needed, a device account is created with the existing `AuthAPI.deviceAccount()`. It is then claimed or joined, the result is shown, and it is cleared.
- In the existing `.active` scene-phase task, after `report(token:)`: `await subscriptions.refreshServerStatus(token:)`.
- Any `AuthAPI.Failure.needsPro` also triggers `refreshServerStatus` before the paywall opens, so a group or referral grant made seconds earlier is honoured without a paywall.

**Sign-in and onboarding screen** (`Features/Auth`): add a small "Have an invite or class code?" row that opens a sheet with `PasteButton` plus a field. It uses `InviteLinks` to tell a 7-character referral code from a 10-character class code.

**`RedPen.storekit`**: see §1. **`ios/project.yml`**: nothing is required for B. IAP needs no entitlement key on iOS. Group A adds `com.apple.developer.associated-domains: [applinks:<worker host>]`, and B's `/r/*` and `/g/*` then open the app directly.

### 4.3 "Pro updates instantly on every device"

- **Server**: every notification updates D1 immediately, and `proGate` reads the new state on the very next request. Sync, cloud, TTS and jobs switch at once.
- **Devices on the same Apple Account**: StoreKit's `Transaction.updates` (existing listener) fires, then `refresh()` and `report()`.
- **Devices on the same Vignette account but a different Apple Account** (a paired iPad), and all grants: `/account/status` on every foreground and after every 402.
- **Optional, phase 4**: an APNs silent push after `handleNotification`. It needs an APNs key from the developer portal, so it stays off the required list.

### 4.4 Xcode (App Store) build vs Swift Playgrounds build

| Capability | Xcode / App Store build | Playgrounds (owner's personal build via `make_swiftpm.py`) |
|---|---|---|
| Paywall | SubscriptionStoreView with App Store Connect products | Never shown: `PersonalBuild.isOn` → Pro. If opened, StoreKit shows "unavailable" (the bundle id has no products). |
| Exam pass, offer-code sheet | Work | Not available (no products). The button is harmless. |
| Server Pro | Snapshot from `/account/status` | Works: the owner account (`owner=1` via the claim) → `source:"owner"`, which also unlocks **Owner tools** on the phone. |
| Referral as referee | AppTransaction verifies → eligible | AppTransaction is not ours → 422 `not_eligible`, and the UI says "Invites work in the App Store version". Showing one's own invite code still works. |
| Deep links `/r`, `/g` | Universal links (A's associated domains) and `redpen://` | Neither (Playgrounds declares no URL types or entitlements). Use paste or typing. |
| Group join, owner group creation | Work | Work |

`make_swiftpm.py` needs **no change** for B. No new resources are needed: the `.storekit` file is already excluded, and every new file compiles in Playgrounds (StoreKit views exist there).

---

## 5. App Review risks and how to stay compliant

| Feature | Rule | Risk | How to stay compliant |
|---|---|---|---|
| Group licences (class access codes) | **3.1.1** ("may not use their own mechanisms to unlock content… such as license keys"); 3.1.3(b) Multiplatform; 3.1.3(c) Enterprise (only for apps sold **only** to organisations, so it does not cover us) | **Medium**, the main one | (1) Never sold in the app, and no price or "buy for your school" link anywhere in the app (anti-steering outside the US). (2) Frame it as class access **provided by the student's school** or a sponsored pilot, acquired outside the app, which 3.1.3(b) permits because the same Pro is available as an in-app purchase in the app (Amboss, Osmosis and Lecturio work this way). (3) The code joins a *class* (a social object shared with group A), and Pro follows from membership. (4) Describe it specifically in Review Notes and give reviewers a working review group code (2.3.1: nothing hidden). (5) Fallback without an app update: set `GROUP_DELIVERY = "offer-codes"`, and the owner uploads one-time-use offer codes (created in App Store Connect) for a group, which the Worker hands out one per member through Apple's redemption sheet. This is fully Apple-native. |
| Referral free months | 3.1.1 (not a purchase, so OK); 5.6.3 ("manipulating… referrals… is not permitted"); 5.1.1(i) (may not require system features for compensation) | **Low–medium** | The reward is service time, not money; nothing asks for ratings or reviews; the invite is ordinary sharing; no push or tracking permission is required; abuse limits are published (§7); no fake-download incentives. Fallback without an app update: deliver rewards as Apple one-time offer codes (owner-generated pool). |
| Exam Pass (non-renewing) | Apple's rules for non-renewing subscriptions (restore on every device); 3.1.2(c) disclosure; 2.3.1 misleading | Low | Restored on every device via StoreKit `Transaction.all` and the server; copy says "one payment, never renews"; an explicit end date is shown in Account. |
| Free trial on annual, annual preselected | 3.1.2(a)/(c), Schedule 2; "bait-and-switch" | Low | Apple's own view renders the terms; our renewal text and Terms/Privacy links are in the paywall; the App Store description carries an EULA link (Apple's standard EULA is fine). |
| Offer codes and ambassadors | Apple-native | None in the app | Use Apple's redemption sheet and URL. Ambassadors are paid (if at all) off-app; ambassadors must not post fake reviews (5.6.3). Put that in the ambassador agreement (group G). |
| Owner tools visible only to the owner | 2.3.1 hidden features | Low | Mention in Review Notes: "Admin tools are visible only to the developer's own account". |
| Account deletion | 5.1.1(v) | Low | The deletion batch in §2.4 includes the new tables; Apple financial records are kept without personal data, which the privacy policy states. |
| Individual developer, health context | 5.1.1(ix) (regulated fields, healthcare) | Low–medium (group F owns it) | Education, not clinical decisions: a notice in the paywall and the listing (1.4.1). |

**Review Notes text for group B**, to paste into App Store Connect:

> Vignette Pro is sold only through in-app purchase: monthly, or annual with a 1-week free trial, both auto-renewing in one group; plus a 3-month non-renewing Exam Pass. "Class access": a medical school or partner can give its students Pro. Access is arranged outside the app, and no purchase or price is shown or linked in the app (3.1.3(b)). The same Pro is always available by in-app purchase. Review class code: XXXXX-XXXXX. "Invite friends": a friend who joins with your code gets 7 days of Pro, and you get 1 free month after they return on another day. There is no cash value, and ratings or reviews are never asked for. Admin tools appear only on the developer's account.

---

## 6. Tests

### 6.1 Server (`node:sqlite`, same style as `pair.test.mjs`)

- **New helper `server/tests/d1.mjs`**: the shared D1 shim (`prepare/bind/first/all/run`) plus `batch(stmts)` wrapped in `BEGIN`/`COMMIT`. Existing tests can move to it later.
- **Fixtures**:
  - `server/tests/fixtures/AppleRootCA-G3.cer` and `AppleWWDRCAG6.cer` (public);
  - `server/tests/fixtures/billing-vectors.json`, **shared with Swift**: pass stacking cases, code normalisation and display, invite URL routes.
- **`x509.test.mjs`**:
  - the real G3 root parses, its fingerprint equals the pinned constant, the curve is P-384, and it is self-signed and verifies;
  - WWDR G6 verifies against G3 and has OID `…6.2.1` and `isCA`;
  - `ecdsaDerToRaw` round-trips against `node:crypto` signatures (`dsaEncoding:'ieee-p1363'`);
  - 2,000 random truncations and bit-flips of both certificates → `parseCert` returns `null` or an object and never throws.
- **`appstore.test.mjs`** builds a fake chain at run time with `openssl` (installed on ubuntu and macOS runners) through `execFileSync` in a temporary directory:
  - root: P-384, self-signed, CA;
  - intermediate: P-384, `basicConstraints=critical,CA:TRUE`, `1.2.840.113635.100.6.2.1=ASN1:NULL`;
  - leaf: P-256, `1.2.840.113635.100.6.11.1=ASN1:NULL`.

  It signs JWS with the leaf key through `node:crypto` in ES256 (P1363 format), after `setTrustedRootsForTests([fakeRootDer])`.
  - Accepts a valid payload.
  - Rejects each of these:
    - the default pin (real Apple root) against the fake chain;
    - `alg` HS256 or none;
    - x5c of length 2 or 4;
    - x5c[2] not a trusted root;
    - leaf without the OID;
    - intermediate without the OID or without CA;
    - issuer/subject mismatch;
    - leaf expired at `signedDate`;
    - `signedDate` 10 minutes in the future;
    - a tampered payload byte;
    - a signature by another P-256 key;
    - a 65-byte signature;
    - a non-object payload;
    - bundleId mismatch;
    - environment `Xcode`.
- **`billing.test.mjs`** (through `worker.fetch`):
  - INITIAL_BUY carrying A's `appAccountToken` → A is Pro, `verified_until = expires`, `paid_until` set (Production);
  - the same UUID again → `duplicate`, and nothing changes;
  - an older EXPIRED after a newer DID_RENEW → `stale`, still Pro;
  - DID_FAIL_TO_RENEW/GRACE_PERIOD → Pro until the grace end; then GRACE_PERIOD_EXPIRED → not Pro;
  - REFUND → not Pro; REFUND_REVERSED → Pro again;
  - OFFER_REDEEMED with offerType 3 and `amb-cairo` → `first_offer_id`, and the ambassador stats count it;
  - ONE_TIME_CHARGE for a pass → until +92 days; a second pass → +184 days; a refund of the first → +92 days from the second purchase;
  - Sandbox → Pro but `paying:false`, and `wallet()` returns null;
  - an unknown token → `unmatched`, and a later `/account/subscription` with the signed transaction links it;
  - a live other account's token → 409 `bought_by_other_account`;
  - an orphaned token (account deleted) → relinked;
  - TEST → 200 and logged;
  - a bad signature → 401 with zero rows written (count the tables);
  - `/account/status` shape and `source` precedence;
  - `budget()` counts `paid_until`;
  - `proGate` returns 402 for free and 200 for group, referral and pass;
  - `askApple` without keys no longer zeroes `verified_until` (blocker 2).
- **`referrals.test.mjs`**:
  - claim → pending plus a welcome grant (active if not Pro);
  - self by account and by Apple Account → 409;
  - the same `appTransactionID` twice (even after deleting the referee) → 409;
  - an account older than 7 days → 409;
  - `settleReferrals` before the hold → pending; after the hold without a return day → pending; with one → rewarded plus a banked 30-day grant;
  - the 4th in a month → `capped`; the 13th in a year → `capped`;
  - a banked credit does **not** start while subscribed, and starts once the subscription ends (via `/account/status`);
  - the 4th claim per hour from one IP → 429;
  - `REFERRALS=off` → 410;
  - `GET /r/CODE` returns HTML with no referrer name, and `ar` sets `dir="rtl"`.
- **`groups.test.mjs`**:
  - non-owner create → 404; owner key and owner account → created;
  - seats=2: three joins → the third gets 409 `group_full`; leaving frees a seat;
  - an ended or disabled group → no Pro, and join → 410;
  - rotating the code invalidates the old one;
  - 11 wrong codes per hour → 429;
  - deleting a member frees the seat;
  - a `paid_models=0` member's `wallet()` is null.
- **`.github/workflows/server-tests.yml`**: add steps for x509, appstore, billing, referrals and groups. **`worker-deploy.yml` "Tests first"**: append the same five.

### 6.2 Swift

- **`ios/RedPen/Tests/BillingTests.swift`**, a top-level suite:
  - `PassMath` against `server/tests/fixtures/billing-vectors.json`, read from the current directory, which is the repository root on the runner;
  - `Entitlement.access` merging: StoreKit lapsed + pass live → pro; a server grant 8 days old → ignored (trust window); server until earlier than StoreKit → StoreKit wins;
  - `Entitlement.source`;
  - summary strings;
  - `InviteLinks.route` for https `/r/`, `/g/`, `/a/`, `redpen://`, garbage, and lowercase or dashed input;
  - `ServerStatus` decodes the exact JSON in §3.3 and tolerates unknown fields;
  - the old `EntitlementRecord` JSON (without the new fields) still decodes.
- **`swift-tests.yml`**:
  - add `suite billing BillingTests.swift $M/Account.swift $S/Entitlement.swift $S/ServerEntitlement.swift $S/InviteLinks.swift`;
  - add `server/tests/fixtures/**` to `on.push.paths`;
  - the existing `account` suite keeps compiling because `Entitlement.swift` stays Foundation-only.
- **UI test `ios/UITests/PaywallUITests.swift`** (Xcode build, in the workflow that runs `RedPenUITests`):
  - launch with `-previewScreen paywall`;
  - assert the yearly option is selected, "1 week free" text exists, the Exam Pass row exists, Restore and Redeem Code buttons exist, and Terms and Privacy links exist.

  StoreKit products in UI tests need the `.storekit` file on the scheme's **Test** action. XcodeGen only supports `storeKitConfiguration` on `run`, so add a `postGenCommand` that inserts `<StoreKitConfigurationFileReference identifier="../../RedPen/RedPen.storekit"/>` into the `TestAction` of `RedPen.xcscheme`. If the products still do not load on CI, the test only asserts the static parts (header, notice, links).

### 6.3 Deploy-time check (optional, needs ASC keys)

A new `worker-deploy.yml` step after "Secrets", run only if `ASC_KEY_ID` is set:
- compute `OWNER_KEY` exactly as the existing step does;
- `POST $URL/owner/billing/test-notification`;
- poll `/owner/billing/notifications` for a `TEST` row for 60 seconds;
- on failure, `::warning::App Store Server Notifications URL not set in App Store Connect yet`. A warning, never a failed deploy.

---

## 7. Programme rules to show in the app and the docs (group G reuses them)

**Referral**:
- Share your code or link. A friend who is new to Vignette and uses it within 7 days of installing gets 7 days of Pro.
- When they come back on another day (after at least 72 hours), you get 1 free Pro month.
- Up to 3 per month and 12 per year. One reward per Apple Account ever; your own accounts don't count.
- If you already subscribe, the month is banked and starts automatically when your subscription ends (it lapses after 12 months).
- No cash value; not transferable. Abuse voids rewards.

**Ambassadors**:
- One per school, e.g. Cairo, Ain Shams, Alexandria, Mansoura, …
- Each gets a custom offer code ("1 month free", eligibility new and lapsed) and a page `/a/<school>`, plus their normal referral link; their own Pro comes through an owner-created "Ambassadors 2026" group.
- Because App Store Connect allows **10 active offers per product**, give the largest schools their own offer (reference name `amb-<slug>`, attributed exactly on the server). Smaller schools share `amb-general`, with a distinct custom code each; per-code counts are visible in App Store Connect, and server attribution comes through their referral links.

---

## 8. Regional pricing guidance (set in App Store Connect; nothing in code)

- **Base storefront**: USA, with Apple's equalised prices, then manual overrides for price-sensitive and target markets.
- **Existing subscribers**: keep their price when prices change.
- **Exam season**: never raise list prices. Use the free trial, offer codes and win-back offers instead.

| Storefront | Monthly | Annual (7-day trial) | Exam Pass (3 mo) |
|---|---|---|---|
| USA / default | $4.99 | $34.99 | $12.99 |
| UK | £4.99 | £29.99 | £10.99 |
| Egypt (EGP, 14% VAT included) | EGP 99 | EGP 699 | EGP 249 |
| Saudi Arabia, UAE, Kuwait, Qatar | ≈ US level (SAR 19.99, AED 18.99) | SAR 139.99, AED 129.99 | SAR 49.99, AED 44.99 |
| India, Pakistan, Nigeria, Sudan and other low-income markets | ≈ $1.99 equivalent | ≈ $12.99 equivalent | ≈ $4.99 equivalent |

Pick the nearest available Apple price point in each case. Enrol in the Small Business Program for a 15% commission. `PRO_NET_MONTHLY_USD` in `wrangler.toml` should then be the blended net per paying user per month; the owner can read it off `/owner/billing/summary` by storefront after a month of sales.

---

## 9. Owner's unavoidable publish-time steps

Everything else is automatic: CI deploys, tables and indexes create themselves, `appAppleId` is learned, and the owner creates groups and ambassadors from the phone's Owner tools.

1. **Apple Developer Program** ($99/yr) is active. Group G covers this.
2. **App Store Connect → Business**: accept the **Paid Apps Agreement**, add a bank account, and complete the tax forms (W-8BEN for a non-US individual). Products do not load, even in the sandbox, until the agreement is active.
3. **Apply for the App Store Small Business Program** (developer website form, one time): 15% commission.
4. **App record** for bundle `com.cramdown.app`. Group G covers this.
5. **Subscriptions → group "Vignette Pro"**:
   - `com.redpen.pro.yearly` (1 year) and `com.redpen.pro.monthly` (1 month), both **level 1**;
   - English and Arabic display names and descriptions;
   - prices (§8);
   - a review screenshot for each (CI's paywall screenshot; uploading it is manual);
   - **Introductory offer on yearly: Free, 1 week, new subscribers, all storefronts**;
   - **Billing Grace Period: On, 16 days**, so Apple, the server and `Entitlement.billingGrace` agree.
6. **In-App Purchases → Non-Renewing Subscription** `com.redpen.pass.exam3m` "Exam Pass (3 months)": English and Arabic, prices, screenshot.
7. **App Information → App Store Server Notifications**: Production URL **and** Sandbox URL = `https://redpen-auth.vv7sh4rnnw.workers.dev/apple/notifications` (or the final Worker URL), **Version 2**.
8. **Offer codes** (at launch, then per ambassador as needed): create `amb-<slug>` offers with custom codes. Then enter each offer reference name and custom code in the app's Owner tools → Ambassadors. That in-app step is not a repository edit.
9. **First submission**: on the version page, **attach the three products** (the first subscription must go with an app version), and paste the §5 Review Notes, including a review class code created in Owner tools.
10. **App Privacy** (with group F): Purchases → Purchase History (linked to the user, used for app functionality); Identifiers → User ID. No tracking.
11. *Optional, recommended*:
    - App Store Connect → Users and Access → Integrations → **In-App Purchase key**. Download the `.p8` once and add `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY` as GitHub repository secrets (the only non-App Store Connect action, done on the GitHub website from the phone, never in chat), then run "Deploy the worker". This enables the deploy-time test notification (§6.3) and `askApple`.
    - Without it, everything in group B still works.

---

## 10. Build order (after the two running jobs merge; touch points kept small)

1. **Wave 1, launch-critical**:
   - `x509.js`, `apple-root.js`, `appstore.js`, `entitlement.js`;
   - `/apple/notifications`, `/account/status`, signed `/account/subscription`;
   - schema and deploy ALTERs;
   - `ai.js` fixes (blockers 2 and 5, wallet, budget);
   - app `Entitlement`/`ServerEntitlement`/`SubscriptionStore` (blocker 1), SubscriptionStoreView paywall and Exam Pass, `.storekit`;
   - tests: x509, appstore, billing, BillingTests, paywall UI.
2. **Wave 2**: referrals (server, `/r` page, InviteFriendsView, claim on the invite sheet, cron).
3. **Wave 3**: group licences and Owner tools (groups, billing log, test notification); ambassadors, `/a` page and offer-code button.
4. **Wave 4, optional**: APNs silent push; the offer-code delivery fallback (`GROUP_DELIVERY=offer-codes`, owner CSV upload); catching up on missed notifications via Get Notification History (needs ASC keys).

**Sources**:
- [Apple app-store-server-library-node, jws_verification.ts](https://github.com/apple/app-store-server-library-node/blob/main/jws_verification.ts)
- [Apple Root CA G3](https://www.apple.com/certificateauthority/AppleRootCA-G3.cer), [WWDR G6](https://www.apple.com/certificateauthority/AppleWWDRCAG6.cer)
- [SubscriptionStoreView](https://developer.apple.com/documentation/storekit/subscriptionstoreview)
- [inAppPurchaseOptions(_:)](https://developer.apple.com/documentation/swiftui/view/inapppurchaseoptions(_:))
- [preferredSubscriptionOffer](https://developer.apple.com/documentation/swiftui/view/preferredsubscriptionoffer(_:))
- [AppTransaction.appTransactionID](https://developer.apple.com/documentation/storekit/apptransaction/apptransactionid)
- [offerIdentifier](https://developer.apple.com/documentation/appstoreserverapi/offeridentifier)
- [WWDC24 Implement App Store Offers](https://developer.apple.com/videos/play/wwdc2024/10110/)
- [Set up subscription offer codes](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes)
- [Offer codes for in-app purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases)
- [Appbot offer codes guide (10 offers/SKU, 1M/quarter)](https://appbot.co/blog/apple-offer-code/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple pricing and tax update (Egypt VAT)](https://developer.apple.com/news/?id=e1b1hcmv)
- [XcodeGen ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
