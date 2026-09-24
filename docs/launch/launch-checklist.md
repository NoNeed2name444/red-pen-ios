# Vignette: App Store launch checklist

Written 2026-09-24 for the App Store (Xcode) build of `com.cramdown.app`, display name **Vignette**. It is one of the group G launch documents named in [`implementation-plan.md`](implementation-plan.md). Package P6.2 (the release run) works through it from top to bottom.

The Swift Playgrounds build the owner installs today is not what gets published. Playgrounds cannot hold app extensions (widgets, the Live Activity, share extensions), it has no `Info.plist` or entitlements of its own, and App Intents metadata may not be extracted there. Everything below is about the build that `xcodegen` makes from `ios/project.yml` and GitHub's macOS runners sign and upload.

**Companion files.** Read these alongside this checklist. Where they already hold the detail, this file points to them instead of repeating it.

| File | What it gives this checklist |
|---|---|
| [`implementation-plan.md`](implementation-plan.md) | The packages (P0.1 … P6.2) that build what this list relies on. §6 lists the owner's steps and §7 the App Review risks. |
| [`app-store-listing.md`](app-store-listing.md) | Name, subtitle, keywords, description, screenshots, age-rating answers (§9) and privacy-label answers (§10). |
| [`pricing.md`](pricing.md) | Products, prices by storefront, the trial, offer codes, the exam-season calendar, and the UK/EEA rule from Google's terms (§6). |
| [`ambassadors-and-referrals.md`](ambassadors-and-referrals.md) | Offer codes for ambassadors, and the referral rules. |
| [`api-routes.md`](api-routes.md) | Every Worker route, including `/apple/notifications` and the legal pages. |

**The owner's rules this checklist follows.**
- The owner buys no credits; Pro users pay once the app is published.
- The owner does nothing by hand except the App Store Connect and Apple steps that nobody else can do. Those are marked **OWNER** and gathered in §0.
- Everything works from an iPhone or iPad.
- **Never paste a key, token or `.p8` file into chat.** Keys go into GitHub repository secrets. The repository is public, so no key goes into code, a workflow file or a log either.
- Vignette is for medical education, not clinical use.
- No "challenge a friend" feature of any kind: no duels between people, no head-to-head contests. The single-player "lookalike conditions side by side" screen is a different thing and stays.

### How each step is marked

| Tag | Meaning |
|---|---|
| **OWNER** | Only the owner can do it (Apple identity, money, legal declarations, the Submit button). Listed in full in §0. |
| **DONE** | The code or CI already does it on the current branch. |
| **PLANNED Px.y** | The code or CI will do it once that package from `implementation-plan.md` lands. Nobody does it by hand. |
| **GAP** | Needed for launch but in no package yet. A code job has to pick it up. This file changes no code. |
| **CHECK** | A check that P6.2 runs before submission, with a pass condition. |

---

## 0. The owner's list: every step that cannot be automated

About 2–3 hours in total, spread over a few days because Apple has waiting times. Each step works on an iPhone or iPad: in the **Apple Developer** app, the **App Store Connect** app, or App Store Connect / GitHub in Safari (use "Request Desktop Website" on an iPhone when a page is cramped).

| # | When | Step | Where | Details |
|---|---|---|---|---|
| O1 | Any time, first | Enrol in the Apple Developer Program as an individual ($99 a year) | Apple Developer app | §2 |
| O2 | After O1 is approved | Create an App Store Connect **Team API key** with the **Admin** role and save it as 3 GitHub secrets | App Store Connect (Safari) → Users and Access → Integrations; github.com → repository Settings → Secrets | §3 |
| O3 | After O2 | **Business:** accept the Paid Apps Agreement, add a bank account, fill in the tax form | App Store Connect → Business | §6 |
| O4 | After O1 | Apply for the **App Store Small Business Program** (15% commission) | developer.apple.com form | §6 |
| O5 | After agents have run `testflight.yml` once (it registers the bundle ID) | Create the **app record** | App Store Connect → Apps → + → New App | §5 |
| O6 | After O5 | Accept the TestFlight invitation and install the build on your iPhone | Email invite → TestFlight app | §12 |
| O7 | Before submitting | Choose EU distribution and answer the **DSA trader** question | App Store Connect → Business, then App Information | §6.4 |
| O8 | Before submitting | Fill in **App Privacy** (web only), using the table in `app-store-listing.md` §10 | App Store Connect → App Privacy | §9.4 |
| O9 | Before submitting | Declare **"not a regulated medical device"** | App Information → App Store Regulations & Permits | §10.3 |
| O10 | Before submitting | Check the **age rating** the agents set (computed 16+, overridden to **18+**) | App Information → Age Rating | §11 |
| O11 | Before submitting | Enter your **App Review contact** (name, phone, email) | Version page → App Review Information | §14 |
| O12 | At submission | Attach the **3 in-app purchases** to version 1.0, then press **Submit for Review** | Version page | §15 |
| O13 | Whenever Apple asks | Accept updated agreements (App Store Connect shows a banner; submissions are blocked until you accept) | App Store Connect home | §16.3 |

Optional owner steps, none needed for launch:
- An **In-App Purchase key**, saved as the secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY`. It lets the Worker ask Apple about a subscription directly and send itself a test notification (§8).
- **Accessibility Nutrition Labels.** Agents can set them through the API instead.
- **Two fallbacks, only if a CI run says so:**
  - create the App Group `group.com.cramdown.app` by hand if the signing log says it could not be registered;
  - do one App Store Connect item by hand if the `appstore-setup` run summary lists it as refused.

---

## 1. Where things stand on 2026-09-24

### 1.1 Already done in the code or CI (DONE)

| Item | Where |
|---|---|
| Bundle ID `com.cramdown.app`, iPhone and iPad (`TARGETED_DEVICE_FAMILY 1,2`), iOS 26 minimum | `ios/project.yml` |
| Sign in with Apple entitlement, and the server checking Apple's token audience against `APPLE_BUNDLE_ID` | `project.yml`, `server/tokens.js`, `server/wrangler.toml` |
| Export compliance answered in the binary (`ITSAppUsesNonExemptEncryption: false`), so no question on each upload | `project.yml` |
| Usage strings for the microphone, speech recognition and camera (face tracking, off by default) | `project.yml` |
| Account deletion inside the app (Account → Delete account), which deletes the account, library, blobs and pairing codes on the server | `Features/Auth/AccountView.swift`, `POST /account/delete` |
| "Start without an account", so App Review needs no demo login | `Features/Auth/SignInView.swift` (`localSignIn`) |
| A terms gate before first use (recording consent, sources, cloud transcription), with a 5-second countdown | `Features/Account/RecordingTermsView.swift` (v2) |
| StoreKit products and a local StoreKit configuration for simulator tests | `RedPen.storekit`: `com.redpen.pro.monthly`, `com.redpen.pro.yearly` |
| Paywall screen | `Features/Paywall/PaywallView.swift` |
| Server-side Pro check through the App Store Server API (only works once the optional In-App Purchase key exists) | `server/ai.js` `askApple`, `proGate` |
| Worker deploy from a phone: D1, R2 binding, Durable Objects, Workers AI, secrets | `.github/workflows/worker-deploy.yml` |
| Whole-app compile on a macOS runner, an unsigned `.ipa`, simulator screenshots, and iPad width and device checks | `app-build.yml`, `ipa.yml`, `ios-preview.yml`, `ipad-*.yml` |
| Accuracy benchmarks, with results committed to the `checker-bench` and `accuracy-bench` branches | `checker-bench.yml`, `accuracy-bench.yml` |
| "Try every feature" examples that work with no model and no network. **They are listed only when `PersonalBuild.isOn`**, so the store build does not show them yet (GAP 5). | `Features/Examples/ExamplesHubView.swift`, `SupportCenter.swift`, `LibraryRows.swift` |

### 1.2 Launch blockers already assigned to a package

| Blocker | Why it blocks | Fixed by |
|---|---|---|
| `SubscriptionStore.isPro` returns `true` for everyone | Every App Store user would get Pro free | **PLANNED P0.2** |
| The paywall links go to `https://redpen.app/terms` and `/privacy`, a domain nobody is known to own | Guideline 3.1.2 needs working Terms and Privacy links | **PLANNED P0.2**, with pages from **P1.8** |
| There is no `/apple/notifications` route | Renewals, refunds and expiries would never reach the server | **PLANNED P1.3** |
| There are no `/privacy`, `/terms`, `/medical` or `/support` pages | The App Store Connect Privacy Policy and Support URLs need live pages | **PLANNED P1.8** |
| There is no consent screen for third-party AI | Guideline 5.1.2(i) needs explicit permission, naming the provider, before any data goes to an outside AI | **PLANNED P2.9** |
| There is no `PrivacyInfo.xcprivacy` | Apple requires a privacy manifest in every upload | **PLANNED P3.1** |
| There is no signed TestFlight upload (`ipa.yml` builds unsigned only) and no App Store Connect automation | Nothing reaches App Store Connect | **PLANNED P3.2** |
| `RedPen.storekit` has yearly at $39.99 and the group named "Red Pen Pro" | `pricing.md` sets $34.99 and "Vignette Pro"; the exam pass and trial are missing | **PLANNED P2.3** |
| `Product.SubscriptionInfo.status(for:)` is passed the group *name* | Subscription status is never found | **PLANNED P2.3** |

### 1.3 GAPs found while writing this checklist (in no package yet)

1. **Sign in with Apple tokens are not revoked when an account is deleted.** Apple's account-deletion rules say apps that offer Sign in with Apple should use its REST API to revoke the user's tokens. `deleteAccount()` in `worker.js` deletes the data but never calls `appleid.apple.com/auth/revoke`, and the server never keeps an Apple refresh token. Apple's TN3194 accepts a fallback when no token is held: delete the data, then tell the user how to revoke access themselves.
   - **Smallest fix, with no new key or owner step:** after "Delete account" succeeds for an Apple-linked account, show "To finish, open Settings → [your name] → Sign-In & Security → Sign in with Apple → Vignette → Stop Using Apple ID".
   - **Full fix:** it needs a "Sign in with Apple" private key. That is another manual owner step at developer.apple.com, so it is not recommended for launch.
   - Owner: the app job, next to P2.9.
2. **The "Sign in with Google" button shows even when no Google client ID is set.** `RED_PEN_GOOGLE_CLIENT_ID` is empty in `project.yml`, and a tap then fails with "not configured". A reviewer who taps a button that fails is a guideline 2.1 rejection. Setting up a Google OAuth client would be another manual step outside Apple, so the fix is to **hide the Google option when `GoogleSignIn.clientID` is empty**. Sign in with Apple, "Start without an account" and pairing codes stay. Owner: the app job (P0.2 already edits `SignInView`'s neighbours).
3. **Two privacy-policy mismatches** (already noted in `app-store-listing.md` §10.4):
   - `pair_attempts` rows are never pruned (P0.1's cron fixes this);
   - `/account/delete` leaves generation jobs in the Durable Object for up to 7 days. The policy must say so, or the delete must clear them.
4. **The Arabic privacy URL.** App Store Connect has one Privacy Policy URL per localisation. The Arabic one must be `…/privacy?lang=ar`, so P1.8 has to honour `?lang=ar` as well as `Accept-Language`. P1.8's acceptance test already checks `dir="rtl"`, so this only confirms it.
5. **The App Store build has nothing to try until the student adds material.**
   - "Try every feature" (`SupportPage.examples.isListed`, `LibraryRows.examplesSection`, `CategoryPages`, `CategoryShelves`) and the sample lectures (`SampleLectures`) are all gated on `PersonalBuild.isOn`.
   - A reviewer whose device has Apple Intelligence off would see nothing work without a 3.4 GB model download. That is a likely rejection under guideline 2.1 (and 4.2).
   - `ExamplesHubView` itself does not use the owner's bundled lecture, so the fix is to **list the examples hub in every build** (the bundled lecture stays personal-only).
   - With it, the review notes can point to the account menu → Try every feature.
   - Owner: the app job (P0.4 owns the screen slots). If share links (P2.1) are in 1.0, P6.1's demo share link is a second route in.

---

## 2. Apple Developer Program enrolment (OWNER, step O1)

1. On the iPhone or iPad you will keep using, install the **Apple Developer** app. Sign in with the Apple Account that will own the app. It needs two-factor authentication, and your name, address and phone number must be current.
2. Tap **Account → Enroll Now → Individual**.
   - Enrolment in the app works for individuals and sole proprietors.
   - You photograph a government photo ID (a passport works in most regions).
   - You must finish on the same device you started on.
   - Apple Gift Card balances cannot pay the fee (except in India). Use a card on the Apple Account.
3. Pay the **$99 a year** fee. It renews automatically, and it is the only fixed cost in `pricing.md` §10.
4. Wait for Apple's "Welcome" email before starting §3.

**Individual or organisation.**
- **Individual (recommended):** your legal name appears as the seller on the App Store page.
- **Organisation:** needs a D-U-N-S number and a legal entity. That is more manual work and several weeks.
- Guideline 5.1.1(ix) asks for healthcare *services* to come from a legal entity. Vignette is an education tool, not a healthcare service: it has no patient data and no clinical function. The review notes (§14) say so.
- If Review cites 5.1.1(ix) anyway, the fallback is to move the app to an organisation account. The app can be transferred with its reviews and sales, so nothing is lost by starting as an individual.

---

## 3. Keys and secrets (OWNER, step O2)

### 3.1 The Team API key (needed)

It lets CI:
- register the bundle IDs;
- sign and upload builds ("cloud signing");
- create the subscriptions, prices and offer codes;
- set the notification URL;
- upload metadata and screenshots;
- release the app.

Cloud signing through `xcodebuild` needs a key with the **Admin** role; an App Manager or Developer key fails with a "Cloud signing permission error".

1. App Store Connect in Safari → **Users and Access → Integrations → App Store Connect API → Team Keys → +**. Name: `vignette-ci`. Access: **Admin**.
2. Download the `.p8` file. **Apple lets you download it only once.** It saves to the Files app.
3. On github.com in Safari: repository **Settings → Secrets and variables → Actions → New repository secret**. Add three secrets:
   - `ASC_API_KEY_ID`: the Key ID shown next to the key;
   - `ASC_API_ISSUER_ID`: the Issuer ID shown above the list;
   - `ASC_API_PRIVATE_KEY`: the whole text of the `.p8`, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines.
4. **To copy the `.p8` text on an iPhone:**
   - In Files, long-press the file → Rename → change `.p8` to `.txt`.
   - Open it, then Select All → Copy, and paste it into the secret's value.
   - Then delete the file and copy something else over the clipboard.
   - Never paste it anywhere else, and never into chat.
5. Tell the agents only "the ASC secrets are in". Never send the values.

Because the repository is public:
- The workflows that read these secrets run only on `workflow_dispatch` or on pushes to the repository's own branches, never on a pull request from a fork. GitHub does not pass secrets to fork pull requests anyway.
- They never print a token. P3.2's `client.mjs` has that rule, and its tests check it.

### 3.2 The In-App Purchase key (optional)

This is a different kind of key, for the **App Store Server API**, which the Worker uses. With it, the Worker's `askApple` can check a subscription with Apple, and a deploy can send itself a test notification (design B §6.3).
- Where: App Store Connect → Users and Access → Integrations → **In-App Purchase** → +.
- Save it as the secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY`, then run "Deploy the worker".

Without it, the server learns about purchases from signed transactions and notifications (P1.3), and everything still works.

### 3.3 Secrets that already exist (DONE)

`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `AI_API_KEY` and the `FIREBASE_*` secrets. `SESSION_SECRET` is generated on the first deploy. `OWNER_KEY` and `CI_KEY` are derived in the workflows (plan R8) and are never stored.

---

## 4. Bundle IDs, capabilities and the App Group (PLANNED P3.1 + P3.2)

`tools/asc/register.mjs` in `testflight.yml` does all of this through the App Store Connect API, and does nothing when it is already done:

| Identifier | Kind | Capabilities |
|---|---|---|
| `com.cramdown.app` | App ID (explicit) | Sign in with Apple; Associated Domains; App Groups; In-App Purchase (on by default) |
| `com.cramdown.app.widgets` | App ID for the widget and Live Activity extension (P3.1) | App Groups |
| `group.com.cramdown.app` | App Group, shared by the app and the widgets | – |
| `com.cramdown.uitests` | UI test bundle | never uploaded |

Notes:
- **The Team ID** is read from the bundle ID's `seedId` and written to D1 as `app_facts.apple_team_id`. The Worker's `/.well-known/apple-app-site-association` needs it to serve share links (`/s/*`, `/j/*`, `/r/*`). It returns 404 until the Team ID is known (P1.1).
- **Product IDs keep the old `com.redpen.*` prefix.** Product IDs only have to be unique in the account, and changing them now would break `RedPen.storekit`, the server and the tests. A product ID can never be used again once created, even after the product is deleted, so `appstore-setup.yml` always runs as a dry run first.
- **The Playgrounds build uses its own bundle ID** (the `.personal` suffix in `make_swiftpm.py`), so the Playgrounds app and the TestFlight or App Store app can sit side by side on the owner's phone.
- **CHECK:** `app-build.yml` (P3.1) confirms that `PlugIns/RedPenWidgets.appex` exists, `NSSupportsLiveActivities` is true, `Metadata.appintents` contains `QuizMeIntent`, `PrivacyInfo.xcprivacy` is in the bundle, and **`RedPenOwnerKey` is empty**.

---

## 5. The App Store Connect app record (OWNER, step O5)

The App Store Connect API cannot create an app: there is no `POST /v1/apps`. This is the one listing step the owner must do by hand. Do it after the agents' first `testflight.yml` run has registered the bundle ID; that run stops and says "Create the app record" if the record is missing.

App Store Connect → **Apps → + → New App**:

| Field | Value |
|---|---|
| Platforms | iOS. The iPad is included, because the build targets both. |
| Name | `Vignette: Medical MCQs & OSCE`. If it is taken: `Vignette: Med School Qbank` (`app-store-listing.md` §2). |
| Primary language | English (U.S.) |
| Bundle ID | `com.cramdown.app` (pick from the list) |
| SKU | `vignette-ios` |
| User access | Full Access |

That is all. Agents fill in everything else through the API (P3.2 `appstore-setup.yml`, fed by P6.1's `docs/launch/metadata/`):
- category Education, secondary Reference;
- the en-GB and ar-SA localisations;
- the text and screenshots;
- the content-rights answer (`contentRightsDeclaration`: the app shows third-party content, namely Europe PMC and openFDA search results and what the student imports, with the rights to do so);
- the price (Free);
- availability;
- the copyright line.

---

## 6. Business: agreements, bank, tax, commission, EU (OWNER, steps O3, O4, O7, O13)

### 6.1 Paid Apps Agreement, bank and tax (O3)

App Store Connect → **Business**:
1. Accept the **Paid Apps Agreement**. Only the Account Holder can do this.
2. Add the **bank account** that Apple will pay into.
3. Fill in the **tax forms**: W-8BEN if you are not a US person, W-9 if you are. Add any local tax registration Apple asks for in your country.

**Products do not load, even in the sandbox and in TestFlight, until the agreement's status is Active.** Do this before anyone tests purchases. Apple pays about 45 days after the end of each fiscal month (`pricing.md` §11).

### 6.2 Small Business Program (O4)

Apply once, on developer.apple.com → App Store Small Business Program. The commission then drops from 30% to **15%**. Apply before the first sale so that no sale is charged at 30%. `pricing.md` computes every net figure at 15%.

### 6.3 EU business terms from 1 October 2026 (O13)

Apple is moving every developer who distributes in the EU onto one set of EU terms from **1 October 2026** (Attachment 14 of the Developer Program License Agreement). When App Store Connect shows the updated agreement, accept it. That is all this app needs: it uses only In-App Purchase and the App Store.

### 6.4 EU Digital Services Act trader status (O7, a decision)

Apple requires every account to declare a trader status, **even when the app is not sold in the EU**. A trader distributing in the EU must have an address (an individual may use a P.O. box), phone and email verified and **shown on the EU product page**.

**Recommended at launch: leave the 27 EU storefronts out and declare "not a trader".** The reasons:
- `pricing.md` §6 already keeps Pro out of the UK, the EEA and Switzerland until paid Gemini is on, so the EU would get only the free app.
- It avoids publishing your contact details and uploading documents.
- The UK, Switzerland, Norway, Iceland and Liechtenstein are not covered by the DSA and can stay available.

Agents set availability through the API (`appAvailabilityV2`) if you say "EU off". To distribute in the EU later: declare trader status in Business → set it per app in App Information → tell the agents to add the EU territories.

The other choice is to declare yourself a trader now and keep the EU.

---

## 7. Subscriptions, the Exam Pass and offer codes (PLANNED P3.2 `appstore-setup.yml`; OWNER only for O12)

Created through the API from `docs/launch/pricing.json` (P6.1, built from `pricing.md` §5). The run is idempotent and does a dry run first.

### 7.1 Products

| Product | Type | Period | Price (US base) | Offer |
|---|---|---|---|---|
| `com.redpen.pro.yearly` | Auto-renewable, group **"Vignette Pro"**, level 1, listed first | 1 year | $34.99 | **Introductory: free for 1 week, new subscribers, every storefront where Pro is sold** |
| `com.redpen.pro.monthly` | Auto-renewable, same group, level 1 | 1 month | $4.99 | none |
| `com.redpen.pass.exam3m` | **Non-renewing** subscription, "Exam Pass (3 months)" | 92 days, worked out by the app and server, stacking | $12.99 | offer codes allowed |

For each product the run also sets:
- English and Arabic display names and descriptions;
- a review screenshot of the paywall, from `store-screenshots.yml`;
- **Billing grace period: on, 16 days**, which matches `Entitlement.billingGrace`;
- Family Sharing off;
- prices per storefront from `pricing.md` §5: Egypt EGP 99 / 699 / 249, the Gulf near the US level, UK £4.99 / £29.99 / £10.99 once Pro opens there. The run picks Apple's nearest price point, with no manual prices.

It also applies the **UK, EEA and Switzerland rule**: Pro is not sold there until paid Gemini is on (`pricing.md` §6). The free app stays available in the UK and Switzerland.

**CHECK.** After the run, `GET /v1/apps/{id}/subscriptionGroups` shows one group with two level-1 subscriptions, and `inAppPurchasesV2` shows the pass. Every refused call is listed in the run summary as an owner line (the likely ones are the review screenshot upload and the grace-period switch).

**OWNER at submission (O12).** Apple requires the **first** subscriptions to go to review together with an app version. On the 1.0 version page → **In-App Purchases and Subscriptions** → select all three. The Exam Pass is a separate IAP in the same section.

### 7.2 Offer codes

Apple's rules:
- Offer codes work for auto-renewable subscriptions and, since 2025, for non-renewing subscriptions too.
- A product can have at most **10 active offers**.
- An app can issue at most **1 million codes per quarter**.
- One-time codes come in batches of 500 to 25,000 and expire within 6 months.
- Custom codes (such as `CAIRO26`) can run without an end date.
- Customers can redeem codes only once the app is **Ready for Sale** and the subscriptions are approved.

Plan (`pricing.md` §7, `ambassadors-and-referrals.md`):
- Ambassadors get "1 month free" on yearly, for new and lapsed customers:
  - an offer per large school, `amb-<slug>`, with its own custom code;
  - `amb-general`, with one custom code per smaller school.
- The owner turns on "create in App Store Connect automatically" in Owner tools → Ambassadors.
- The run takes the queue from `/ci/ambassadors/pending` and posts the result back (P1.4 plus P3.2). No owner work in App Store Connect.
- Redemption uses Apple's sheet in the app (`RedeemOfferCodeButton`, P2.3) or Apple's redemption URL on the `/a/<slug>` page. **Never sell codes.**
- **Win-back offers** (lapsed yearly: 50% off the first year) start 6 weeks before each season in `pricing.md` §8. Apple shows them itself.
- **CHECK:** the sandbox code `AMB-TEST` in `RedPen.storekit` redeems in a simulator UI test (P2.3).

---

## 8. App Store Server Notifications (PLANNED P1.3 route, P3.2 URL)

| Setting | Value |
|---|---|
| Production URL | `https://redpen-auth.vv7sh4rnnw.workers.dev/apple/notifications` |
| Sandbox URL | the same URL. P1.3 records `environment` from the signed payload, so sandbox events never count as revenue. |
| Version | **Version 2** (Version 1 is deprecated) |
| Set by | `appstore-setup.yml` through `PATCH /v1/apps/{id}` with `subscriptionStatusUrl`, `subscriptionStatusUrlVersion: V2`, `subscriptionStatusUrlForSandbox` and `subscriptionStatusUrlVersionForSandbox: V2`. **No owner step.** |
| Manual fallback, only if the run lists it as refused | App Store Connect → App Information → App Store Server Notifications → Set Up URL (production, then sandbox) → Version 2 → Save |

**What the route must do before the URL is set** (P1.3 acceptance):
- Verify the JWS: an `x5c` chain of exactly 3 certificates, with Apple Root CA G3 pinned byte for byte, plus the OID, date and ES256 checks.
- A bad signature gets **401 with no D1 writes**.
- De-duplicate by `notificationUUID` and ignore anything older than the stored `signedDate`.
- Handle `SUBSCRIBED`, `DID_RENEW`, `DID_FAIL_TO_RENEW` (grace), `EXPIRED`, `REFUND`, `REVOKE` and `ONE_TIME_CHARGE` (the pass).
- The first verified Production notification stores the App Store app ID (`app_facts.app_store_id`).

**CHECKs:**
- `curl -X POST …/apple/notifications -d 'garbage'` returns 401 (W1 gate).
- With the optional In-App Purchase key: `/owner/billing/test-notification` sends a test and a `TEST` row appears in `/owner/billing/notifications` within 60 s. If it does not, the run prints a warning, never a failure.
- A TestFlight sandbox purchase on the owner's phone (§12) shows up as a sandbox row.

The Worker is on `workers.dev`, and this URL is stored at Apple. If a custom domain is ever added (plan §8.2), update both URLs through the API before retiring the old host.

---

## 9. Privacy policy, terms, support and the privacy label

### 9.1 The Worker pages (PLANNED P1.8)

All of them are served by `server/legalpages.js`, in English and Arabic, with no scripts or cookies and a strict CSP:

| Page | URL | Goes into |
|---|---|---|
| Privacy policy | `https://redpen-auth.vv7sh4rnnw.workers.dev/privacy` (Arabic: `?lang=ar`) | App Store Connect → App Privacy → Privacy Policy URL (one per localisation); the paywall; About & legal; the sign-in footer |
| Terms of use | `…/terms` | The paywall's policy destination; the description (as a line once live); About & legal |
| Medical and education notice | `…/medical` | About & legal; the consent sheet; the review notes |
| Support | `…/support` (a form, rate-limited, with a honeypot) | App Store Connect → Support URL (required); Settings → Support |
| Accuracy | `…/accuracy` and `/accuracy.json`, from the benchmark branches | The optional Marketing URL; any accuracy number anywhere must link here |
| Versions | `…/legal.json` | Read by the app's consent screen to name the providers and versions |

- **Licence agreement:** keep **Apple's Standard EULA**. The description ends with the EULA link (`app-store-listing.md` §6), which satisfies guideline 3.1.2's "functional link to the terms of use" for subscriptions. Vignette's own `/terms` supplements it.
- **Content:** the text must match `privacy-and-terms-draft.md`, the other group G document, reconciled by P6.1 into `server/legal/content.js`. The processor list is built from the Worker's environment, so the policy names exactly what is deployed (Cloudflare, Apple, Google Gemini through Firebase, Hugging Face, Novita if its key is set, Europe PMC, NLM and openFDA). It also states Gemini's free-tier terms honestly.
- **CHECK (P6.2 step 6):**
  - `/privacy`, `/terms`, `/medical`, `/support` and `/accuracy` all return 200;
  - `/privacy?lang=ar` contains `dir="rtl"`;
  - no page contains `<script`;
  - `grep -r "redpen.app" ios/RedPen` finds nothing.

### 9.2 Inside the app (PLANNED P0.2, P2.3 and P2.9)

- Terms and Privacy links on the paywall. They must be tappable before purchase (3.1.2).
- An About & legal page with Privacy, Terms, Medical notice, Accuracy and Support.
- Delete account (DONE), plus the Sign in with Apple revocation note (GAP 1).

### 9.3 Privacy manifest (PLANNED P3.1)

`ios/RedPen/PrivacyInfo.xcprivacy`:
- `NSPrivacyTracking` false, and no tracking domains;
- required-reason APIs: UserDefaults `CA92.1` and file timestamps `C617.1`, plus any others a code search finds;
- collected data types matching §9.4 exactly.

The Playgrounds build ignores the file.

### 9.4 App Privacy label (OWNER, step O8, web only)

App Privacy has no API, so the owner copies the answers from `app-store-listing.md` §10. Plan §6 step 6 has the full post-launch table with telemetry.
- "Yes, we collect data", and "No" to tracking.
- Every type is **linked to the user** and used for **App Functionality**:
  - Name and Email (only with Apple or Google sign-in);
  - User ID;
  - Purchase History;
  - Other User Content;
  - Photos or Videos (slide images in sync);
  - Audio Data (cloud transcription);
  - Customer Support (once P1.8 ships);
  - Product Interaction (cloud-usage counters).
- If opt-in telemetry (P2.8) ships in 1.0, add these as **not linked**: Product Interaction (Analytics) and Crash, Performance and Other Diagnostic Data.
- The label must describe the binary that is submitted. If a package is not in 1.0, leave its row out and add it in the version that ships it.

---

## 10. The medical and education disclaimer

### 10.1 One text, used everywhere

Everything derives from this text: gate v3, the consent sheet, the `/medical` page, the paywall footnote, the description's "FOR EDUCATION ONLY" block and the widget descriptions. The Arabic comes from the P5.7 translation run, reviewed against the glossary in design F §4.

**Short (footnotes, paywall, widget descriptions):**

> For medical education only. Not medical advice, and not for diagnosis, treatment or patient care. AI can be wrong: check the source.

**Full (gate v3, `/medical`, About & legal):**

> Vignette is a study tool for medical students and doctors preparing for exams. It is not a medical device and it does not give medical advice.
> - Do not use anything in Vignette to diagnose, treat or manage a real patient, or to choose a drug or a dose. Follow your supervisor, current local guidelines and the product information.
> - Questions, cards, cases, stations, explanations and accuracy checks are written by AI from the material you add. They can be wrong or out of date. "Check accuracy" and the source page are one tap away; use them.
> - Never enter a real patient's name, record number, images or any other detail that could identify them.
> - Patients in Cases are simulated. They are not real people and are not clinical advice.
> - Exam styles follow the published formats of USMLE, PLAB, MRCP(UK) and MRCS. Vignette is not affiliated with or endorsed by the FSMB, NBME, GMC or the Royal Colleges.

### 10.2 Where it must appear (and who puts it there)

| Surface | Status |
|---|---|
| Terms gate v3: adds the education-only and no-patient-data points and keeps the `acceptRecordingTerms` identifier | **PLANNED P2.9** |
| Consent sheet for third-party AI: names the providers from `/legal.json`, confirms 18+, forbids patient data, offers "Keep everything on this device"; **never shown at launch**, only before the first cloud request | **PLANNED P2.9** |
| Paywall footnote (`EducationFootnote`) | **PLANNED P2.3** |
| Report an error: in the More menu of every study screen | **PLANNED P0.4 + P2.9** |
| App Store description "FOR EDUCATION ONLY" and not-affiliated lines | written in `app-store-listing.md` §6; uploaded by **P6.1 + P3.2** |
| `/medical` page | **PLANNED P1.8** |
| Accuracy numbers: only with a link to `/accuracy` (intervals and method); none in the name, subtitle, keywords or screenshots | rule in **P6.1** `test_metadata.py` |

Rules that keep it true (guideline 1.4.1 and Apple's Foundation Models acceptable-use rules, which forbid inaccurate or dangerous output and unsupervised decisions in medical domains):
- no dosing calculators;
- no symptom checkers;
- no "diagnose" wording;
- no pass guarantees;
- no unqualified accuracy claims.

### 10.3 Regulated medical device declaration (OWNER, step O9)

Apple has required it for new apps since 26 March 2026 whenever the age rating answers "Frequent" for Medical or Treatment Information, which is the honest answer here (§11). It is web only and needs the Account Holder or Admin role; there is no API for it.

App Store Connect → the app → **App Information → App Store Regulations & Permits → Declare Regulated Medical Device** → **No** → Save. That covers the US, the UK and the EEA; choosing "No" asks for nothing else.

Category choice: primary **Education**, secondary **Reference**. Never Medical or Health & Fitness, which bring more scrutiny.

---

## 11. Age rating (PLANNED P3.2 sets it; OWNER step O10 checks it)

The 2025 questionnaire (ratings 4+, 9+, 13+, 16+, 18+) is required for every submission. The API exposes every answer, including `medicalOrTreatmentInformation`, `healthOrWellnessTopics`, `userGeneratedContent`, `messagingAndChat` and `ageRatingOverrideV2`, so the agents fill it in from `app-store-listing.md` §9:
- Medical or Treatment Information: **Frequent**. This alone gives **16+**.
- Alcohol, Tobacco or Drug Use or References: **Infrequent** (pharmacology).
- Health or Wellness Topics: **Yes**.
- Messaging and Chat: **No**. Cases is a chat with a simulated patient, not with people; say so in the notes.
- Advertising: **No**. Unrestricted Web Access: **No**. Contests: **None**. Gambling and loot boxes: **No**.
- **User-Generated Content:** answer for the binary being submitted.
  - **No** if share links and classes (P2.1/P2.2) are not in 1.0.
  - **Yes** if they are. Then the guideline 1.2 tools must all be live: filter, report, block, contact, and rules accepted before posting.
  - (`app-store-listing.md` §9 and plan §6 differ only because they assume different release contents.)
- **Override: 18+.** Google's Gemini API terms forbid apps "directed towards or likely to be accessed by" under-18s, and the cloud consent already asks for 18+. The trade-off, a few 17-year-old first-year students, is described in `app-store-listing.md` §9.

**OWNER (O10):** open App Information → Age Rating and check that the computed rating reads 16+ with the override at **18+**. Nothing to type.

---

## 12. Build and TestFlight (PLANNED P3.2 `testflight.yml`; OWNER step O6)

### 12.1 What the workflow does

1. It runs `register.mjs` (§4), then `ci/pcc_enable.sh` if it exists (P3.3, optional), then `xcodegen generate`.
2. It archives with Xcode 26 and the iOS 26 SDK. Since 28 April 2026 App Store Connect accepts only uploads built with Xcode 26 or later. The macOS runner image must provide it, so `xcodebuild -version` is printed and asserted.
   - Signing: `-allowProvisioningUpdates -authenticationKeyPath/-ID/-IssuerID` with the Team key and `DEVELOPMENT_TEAM=<seedId>` (cloud-managed certificates, so there are no certificate files and nothing expires by hand).
   - Build number = the run number. Marketing version `1.0`.
3. It exports with method `app-store-connect`, destination `upload`.
4. It uploads the dSYMs as the release asset `dsyms-<version>-<build>` (E §3.5), so crash reports can be symbolicated later without a Mac.
5. **Assertions:**
   - `RedPenOwnerKey` is empty;
   - `SubscriptionStore.isPro` is not hard-coded (`grep -n "var isPro: Bool { true }"` finds nothing);
   - the §4 bundle contents;
   - `RED_PEN_AUTH_URL` is the Worker URL.
6. **Missing secrets:** it skips cleanly with a warning. **No app record yet:** it stops after registering, with "Create the app record (owner step O5), then run this again".

### 12.2 Internal testing on the owner's phone

- Agents add the owner (the Account Holder, already an App Store Connect user) to an internal group, "Owner", through the API. Internal testing needs no Beta App Review. The limit is 100 internal testers.
- **OWNER (O6):** open the invitation email on the iPhone → **View in TestFlight** → Install. Builds expire after **90 days**, and the agents upload a fresh one before that.

**TestFlight smoke test** (about 15 minutes, on the iPhone and then the iPad; the list goes into the P6.2 run summary):
- [ ] Fresh install → "Start without an account" → terms gate v3 → the library opens. No consent sheet at launch.
- [ ] Try every feature is listed in this (non-personal) build (GAP 5). In it, an MCQ, a card, an OSCE station, a Case and occlusion all open with no model and no network (test in Airplane Mode).
- [ ] New set from a sample lecture on the device (Apple Intelligence on). With Apple Intelligence off: the Gemma download offer shows its size (about 3.4 GB) and starts only after a tap.
- [ ] The first cloud action shows the consent sheet naming the providers. "Keep everything on this device" works.
- [ ] Paywall: yearly first with "1 week free", then monthly, then the Exam Pass. The Terms and Privacy links open the Worker pages. Restore and Redeem code are present. A sandbox purchase unlocks Pro, and `/owner/billing/notifications` shows a sandbox row.
- [ ] Account → Delete account removes the account. For an Apple-linked account, the Stop Using note appears (GAP 1).
- [ ] No Google button (GAP 2), or a working one.
- [ ] Widgets and the exam-day Live Activity appear (P3.1). Siri: "Quiz me in Vignette".
- [ ] iPad in landscape: occlusion and draw-from-memory are usable. Arabic (if 1.0 ships it): the layout is right-to-left.

### 12.3 External TestFlight (optional)

It is useful for 10–50 students before launch, recruited through the ambassadors. The first external build goes through **Beta App Review**. It needs the test information (a beta description, what to test, a contact email), which agents set through the API from `review-notes.txt`. The owner does nothing else. A public link lets up to 10,000 testers join.

### 12.4 Last-resort fallback

Swift Playgrounds on the iPad can upload to App Store Connect with a paid membership. It is **not** the launch path: it would ship without the widgets, the Live Activity, the privacy manifest and the entitlements that `project.yml` sets. Use it only if cloud signing is impossible for a long time, and only after the agents check what it would drop.

---

## 13. Metadata and screenshots (PLANNED P6.1 + P3.2)

Everything is in `app-store-listing.md`:
- name, subtitle, keywords (100 bytes, **no "Anki"**, exam names only where the content backs them), description, promotional text and What's New, for en-US, en-GB and ar-SA;
- 8 screenshots for iPhone 6.9" and iPad 13", English and Arabic, from `store-screenshots.yml`.

Rules the metadata test (`tools/tests/test_metadata.py`) enforces:
- field limits;
- no prices;
- no "Anki" in the name, subtitle or keywords;
- no `[ship-gated` marker left in the text;
- **no friend challenges, duels between people, "compete" or "win"** anywhere;
- accuracy numbers only with the `/accuracy` link.

Remove every line whose package is not in 1.0 (guideline 2.3.1). Promotional text can change without a new build, so agents rotate the exam-season lines from `app-store-listing.md` §4 and `pricing.md` §8.

---

## 14. App Review notes (PLANNED P6.1 `review-notes.txt`; OWNER step O11 adds the contact)

Over 40% of unresolved submissions come down to missing information (guideline 2.1). These notes answer, in advance, the questions a reviewer is likely to raise about the medical and AI content. P6.1 assembles the final file.
- The `[if shipped]` lines are included only when their package is in the binary.
- The `‹…›` values come from `demo-content.yml`.
- The notes field has a 4,000-character limit. With every `[if shipped]` line the draft is about 3,980 characters (placeholders included), so `test_metadata.py` must check the assembled file, and any overflow moves into an attachment.

**OWNER (O11):** version page → App Review Information → enter your name, phone and email. These are personal details, so agents never store them. "Sign-in required" stays **off**, because the app works without an account.

The draft to paste (agents upload it through `appStoreReviewDetails`):

```text
WHAT VIGNETTE IS
Vignette is a study tool for medical students and doctors preparing for exams (USMLE, PLAB, MRCP, MRCS, university finals). A student adds their own lecture notes, slides or recordings and gets exam-style practice questions, flashcards, OSCE stations and simulated patient cases. It is education only: it is not a medical device, gives no medical advice, and has no diagnosis, treatment or dosing features. We have declared it not a regulated medical device. The primary category is Education.

NO ACCOUNT NEEDED
On the first screen tap "Start without an account". A one-time terms screen follows (recording consent, sources, education-only, no patient data); its button unlocks after 5 seconds. To see every feature without adding material, open the account menu > "Try every feature": ready-made examples of every mode that need no AI model and no network.

WHERE THE AI RUNS
- Free version: questions are written on the device with Apple's Foundation Models. Nothing leaves the device. If Apple Intelligence is off, the app offers an optional on-device model download (about 3.4 GB). The download starts only after the user taps, and shows its size first.
- Vignette Pro (cloud): text or lecture audio is sent to our server and then to Google Gemini (through Firebase) or Cloudflare Workers AI. Before the first cloud request the app shows a consent screen naming these providers, asks the user to confirm they are 18 or over, and forbids patient-identifiable data. "Keep everything on this device" declines, and consent can be withdrawn in Settings > Cloud AI.
- Optional: a student may connect their own AI provider with their own key; those requests go straight from the device to that provider.

ACCURACY SAFEGUARDS
Every item has "Check accuracy", which compares it with the matching pages of the student's own lecture. Cloud-written items are checked by a second medical model first. Measured accuracy, with 95% confidence intervals and the method, is at https://redpen-auth.vv7sh4rnnw.workers.dev/accuracy; the metadata makes no accuracy claim. Every study screen has "Report an error" in its More (…) menu.

SIMULATED PATIENTS
"Cases" is a conversation with an AI-simulated patient for history-taking practice, marked against an OSCE checklist. It is not a chat with other people and not clinical advice.

PURCHASES
Pro is sold only by in-app purchase: monthly, or yearly with a 1-week free trial (one auto-renewing group), and a 3-month Exam Pass, a non-renewing subscription ("one payment, never renews"). The paywall links the Terms (Apple's EULA plus /terms) and the privacy policy.
[if shipped] Class access: a medical school can give its students Pro, arranged outside the app; the app shows no price or link for it, and the same Pro is always sold in-app. Review class code: ‹CODE›.
[if shipped] Invite friends: a friend who joins with an invite code gets 7 days of Pro, and the inviter gets 1 free month after the friend returns on another day. No cash value. Ratings and reviews are never requested. There are no contests, challenges or competitions between users.

[if shipped] SHARING AND CLASSES (user-generated content)
Sets can be shared by link and classes joined. Names are filtered; items and members can be reported and blocked; posting needs accepted rules; 3 reports from different people hide content until the developer reviews it; contact: /support. Demo share: ‹URL›. Demo class: ‹URL›.

OTHER
- Account > Delete account deletes the account and its server data.
- Developer tools appear only on the developer's own account. Server settings are numbers and on/off values only, and all are on for review.
- [if shipped] Widgets: long-press the Home Screen > + > Vignette. The exam-day Live Activity starts only after the user sets an exam date, and only on that day. Siri: "Quiz me in Vignette".
- Privacy policy: https://redpen-auth.vv7sh4rnnw.workers.dev/privacy   Support: https://redpen-auth.vv7sh4rnnw.workers.dev/support
```

Attachments (optional, through the API): a 30-second screen recording of the consent sheet and "Check accuracy", from `reel-footage.yml`.

---

## 15. Submission and release

### 15.1 Final CI gate (P6.2; every item must pass before the owner is asked to submit)

- [ ] The worker is deployed. `/privacy`, `/terms`, `/medical`, `/support` and `/accuracy` return 200. `/privacy?lang=ar` is RTL. The AASA returns 200 with the Team ID.
- [ ] `POST /apple/notifications` with garbage returns 401 with no writes. The notification URLs are set (both V2).
- [ ] `testflight.yml` uploaded a build that passed §12.1's assertions, and the owner's smoke test (§12.2) is ticked.
- [ ] `appstore-setup.yml` (real run) has created the products, prices, trial, grace period, availability, metadata, screenshots, age rating, content rights, review notes and demo content. The run summary lists any refused call.
- [ ] `test_metadata.py` is green; no ship-gated line remains for an unshipped package.
- [ ] Server flags for review: every capacity switch on, `trust.aiConsentEnforced` still **off** (it goes on after release, §15.3), `PRO_PAYS=off`.
- [ ] GAPs 1, 2 and 5 (§1.3) are fixed, or explicitly accepted by the owner. GAP 5 should not be accepted unfixed.
- [ ] The path to "Try every feature" written in the review notes matches the build exactly (menu name and position).
- [ ] Release type set through the API: **manual release** for 1.0, so the Worker can be switched to "store mode" first.

### 15.2 OWNER: submit (O12)

On the 1.0 version page:
1. Check that the build is selected.
2. Under In-App Purchases and Subscriptions, select the **yearly**, **monthly** and **Exam Pass**.
3. Press **Add for Review → Submit**.

Most submissions are reviewed within 24 hours. Status changes arrive by email and in the App Store Connect app.

**If Review rejects:**
- Apple's message appears in App Review in App Store Connect. Copy it to the agents; it holds no secrets.
- The agents draft the reply or the fix and upload the new build or metadata. The owner only presses Submit again.
- For a disagreement about the guidelines, one appeal to the App Review Board is allowed per rejected submission. The agents draft it; the owner sends it.

### 15.3 After approval (PLANNED P6.2; agents)

1. Release 1.0 through the API (`appStoreVersionReleaseRequests`).
2. Switch on `trust.aiConsentEnforced` once the consenting build is the only App Store build.
3. Confirm with a real purchase: `/owner/billing/notifications` shows a Production `SUBSCRIBED`, and `app_facts.app_store_id` is filled.
4. Put the App Store link in the Worker's share pages and in the ambassadors' `/a/<slug>` pages. Offer codes become redeemable now (§7.2).
5. For later versions, use **phased release** (7 days) through the API, so a bad update can be paused.

---

## 16. After launch: monitoring and recurring work

### 16.1 What to watch

Agents do all of this. The owner reads summaries in the Owner hub or the App Store Connect app.

| How often | Signal | Where | Action when it trips |
|---|---|---|---|
| Daily (first 2 weeks), then weekly | New ratings and reviews, especially "wrong answer" or "crash" | App Store Connect API `customerReviews` | Agents draft replies (the owner approves or sends from the App Store Connect app) and cross-check `/owner/reports/*` |
| Daily | Item error reports and support messages | `/owner/reports/list`, `/owner/support/list` (P1.8) | Fix the prompt or checker; answer within 48 h |
| Daily | Billing events: renewals, `DID_FAIL_TO_RENEW`, `REFUND`, `REVOKE` | `/owner/billing/notifications`, `/owner/billing/summary` (P1.3/P1.4) | A refund spike means reading the paywall copy and the reviews |
| Daily | Cloud allowance and free-quota use: Gemini free daily allowances, Workers AI's 10,000 free neurons a day, `TTS_FREE_DAILY_CHARS` | `/costs` (exists), `/owner/cloud-usage` (P1.5) | Lower per-account caps in remote config. **Never turn on paid models before the first Apple payout** (`pricing.md` §11). |
| Daily | Cloudflare free-plan limits: 100k requests a day, D1 5M rows read and 100k written a day, 10 ms CPU | Cloudflare dashboard (Workers → Observability), plus a 70% warning in the maintenance cron | Look for a hot query; batch writes; paid Workers ($5) only from proceeds |
| Weekly | Accuracy of what students see, against the target | the `accuracy-bench` and `checker-bench` branches → `/accuracy` | A drop below the target means changing the model order in remote config, and fixing it before the next promotion |
| Weekly | Crashes and hangs | TestFlight crash feedback (App Store Connect API or webhook), opt-in MetricKit (`/owner/insights`, P1.7/P2.8), dSYMs on the `dsyms` branch | Fewer than 99% crash-free sessions, or any launch crash, means a hotfix build (expedited review allowed for critical bugs) |
| Weekly | Conversion: product-page views → downloads → trial → paid; the search terms that bring people in | App Analytics (App Store Connect app), and the Analytics Reports API through a CI job | Adjust promotional text now; keywords change only with the next version |
| Monthly | Net revenue per storefront; fixed bills; break-even (`pricing.md` §10) | `/owner/billing/summary` | Set `PRO_NET_MONTHLY_USD` from real numbers before any `PRO_PAYS=on` decision |
| Each release | Review status (the `APP_STORE_VERSION_APP_VERSION_STATE_UPDATED` webhook) | App Store Connect webhooks → a Worker route (a small optional package, not yet planned) | – |

A suggested follow-up package, not in the plan: a weekly `store-digest.yml` that pulls customer reviews, the analytics report and the owner routes above into one Markdown summary on a `digest` branch. The owner then reads one page a week.

### 16.2 Things that never change

- Nothing in the app or its promotions invites friends to compete. No challenges, duels or contests between users.
- Prices never go up in an exam season. Use trials, offer codes, win-back offers and the pass instead.
- Never ask for ratings in exchange for anything. The system rating prompt may be used at a neutral moment, at most 3 times a year as iOS allows.

### 16.3 The yearly calendar

| When | What | Who |
|---|---|---|
| Whenever App Store Connect shows a banner | Accept updated agreements. Apple revised them on 8 June 2026, and the EU terms change on 1 October 2026. Submissions stop until they are accepted. | **OWNER** |
| Every 90 days | TestFlight builds expire; upload a fresh one | agents |
| Every 6 months at most | One-time offer codes expire; rotate the ambassador codes | agents (P3.2 queue) |
| Each spring | Apple raises the minimum Xcode/SDK for uploads (Xcode 26 from 28 April 2026). Update the runner image before the deadline. | agents |
| Each June (WWDC) | New iOS beta: run the UI tests and screenshots on it; check the new App Review Guidelines against plan §7 | agents |
| Each July | Re-check next year's exam dates (`pricing.md` §8, `app-store-listing.md` §4) | agents |
| Each January | Propose price changes for Egypt and Pakistan, keeping existing subscribers' prices (`pricing.md` §12) | agents propose, **OWNER** approves |
| Each year | The Developer Program renews ($99). Keep a valid card on the Apple Account. | automatic; **OWNER** if the card fails |
| When revenue exists | Decide on `PRO_PAYS=on` (Firebase Blaze plus a budget alert), which also opens Pro in the UK, EEA and Switzerland (`pricing.md` §6) | **OWNER** decision, agents do the rest |

---

## Sources

Apple:
- [Apple Developer app: enrolling, verifying and renewing (individuals and sole proprietors can enrol in the app; ID photo; same device; no Gift Card payment)](https://developer.apple.com/help/account/membership/enrolling-in-the-app/)
- [Apple Developer Program: become a member](https://developer.apple.com/programs/enroll/)
- [App Store Connect API: Apps endpoints (GET and PATCH only; no create)](https://developer.apple.com/documentation/appstoreconnectapi/apps)
- [App Store Connect API: `AppUpdateRequest` attributes (`subscriptionStatusUrl`, `subscriptionStatusUrlForSandbox`, versions, `contentRightsDeclaration`)](https://developer.apple.com/documentation/appstoreconnectapi/appupdaterequest/data-data.dictionary/attributes-data.dictionary)
- [App Store Connect API: `AgeRatingDeclarationUpdateRequest` attributes (`medicalOrTreatmentInformation`, `ageRatingOverrideV2` and others)](https://developer.apple.com/documentation/appstoreconnectapi/ageratingdeclarationupdaterequest/data-data.dictionary/attributes-data.dictionary)
- [App Store Connect API: webhook event types](https://developer.apple.com/documentation/appstoreconnectapi/webhookeventtype)
- [App Store Connect Help: enter server URLs for App Store Server Notifications (production and sandbox, Version 2)](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications)
- [App Store Server Notifications documentation](https://developer.apple.com/documentation/appstoreservernotifications/)
- [App Store Connect Help: set up subscription offer codes (10 active offers, 1 M codes per quarter, 6-month expiry, Ready for Sale)](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes)
- [App Store Connect Help: offer codes for other In-App Purchase types](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases)
- [Apple: enhancements to help you submit and market your apps (offer codes for all IAP types)](https://developer.apple.com/news/?id=gf6mgrs6)
- [App Store Connect Help: TestFlight overview (100 internal, 10,000 external, Beta App Review, 90 days)](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)
- [Apple: upcoming SDK minimum requirements (Xcode 26 and the iOS 26 SDK from 28 April 2026)](https://developer.apple.com/news/?id=ueeok6yw)
- [Apple: updated age ratings in App Store Connect (13+, 16+, 18+; answers required from 31 Jan 2026; override to a higher rating)](https://developer.apple.com/news/?id=ks775ehf)
- [Apple: age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [Apple: regulated medical device status (new apps from 26 March 2026; EEA, UK, US)](https://developer.apple.com/news/?id=nyqbfz1y)
- [App Store Connect Help: declare regulated medical device status (web only; Account Holder or Admin)](https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status)
- [App Store Connect Help: EU Digital Services Act trader requirements (declare even outside the EU; P.O. box allowed for individuals)](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)
- [Apple: apps without trader status removed from the EU App Store (Feb 2025)](https://developer.apple.com/news/?id=einwn76m)
- [Apple Newsroom: changes for apps in the European Union (Aug 2026; new terms from 1 Oct 2026)](https://www.apple.com/newsroom/2026/08/apple-announces-changes-for-apps-in-the-european-union/)
- [Apple Developer: updates for apps in the EU](https://developer.apple.com/news/?id=awedznci)
- [Apple: updated Developer Program License Agreement and App Review Guidelines (8 June 2026)](https://developer.apple.com/news/?id=a233fmpw)
- [App Review Guidelines (1.2, 1.4.1, 2.1, 2.3.1, 2.3.7, 3.1.1, 3.1.2, 5.1.1(i), (v), (ix), 5.1.2(i))](https://developer.apple.com/app-store/review/guidelines/)
- [Apple: App Review (90% reviewed in under 24 hours; expedited review; appeals; over 40% of unresolved issues are incomplete information)](https://developer.apple.com/distribute/app-review/)
- [Apple: offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [TN3194: handling account deletions and revoking tokens for Sign in with Apple](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
- [Apple: acceptable use requirements for the Foundation Models framework (no inaccurate or dangerous output or unsupervised decisions in medical domains)](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/)
- [Apple: App Store Small Business Program (15%)](https://developer.apple.com/app-store/small-business-program/)
- [Apple: auto-renewable subscriptions (terms and privacy links, disclosure)](https://developer.apple.com/app-store/subscriptions/)
- [Apple Developer Forums: why xcodebuild needs an Admin key to cloud-sign for distribution](https://developer.apple.com/forums/thread/698117)
- [WWDC21: distribute apps in Xcode with cloud signing](https://developer.apple.com/videos/play/wwdc2021/10204/)

Other:
- [Gemini API Additional Terms (no apps for under-18s; paid services only for users in the EEA, Switzerland and the UK; free-tier data use)](https://ai.google.dev/gemini-api/terms)
- Exam dates and keyword practice: see the sources in [`app-store-listing.md`](app-store-listing.md) and [`pricing.md`](pricing.md), which this checklist follows rather than repeats.

Repository files read for this checklist:
- `ios/project.yml`, `ios/RedPen/RedPen.storekit`;
- `Features/Paywall/PaywallView.swift`, `Features/Auth/SignInView.swift`, `Features/Auth/AccountView.swift`, `Features/Account/RecordingTermsView.swift`, `Features/Examples/ExamplesHubView.swift`;
- `Shared/SocialSignIn.swift`, `Shared/SubscriptionStore.swift`, `Shared/GemmaModel.swift`, `Shared/Brand.swift`;
- `server/worker.js`, `server/ai.js`, `server/wrangler.toml`;
- `.github/workflows/{ipa,app-build,worker-deploy,personal,publish,live}.yml`;
- `make_swiftpm.py`;
- `docs/launch/{implementation-plan,app-store-listing,pricing,api-routes}.md`, `docs/launch/designs/B-monetisation.md` and `F-trust-legal-arabic.md`.
