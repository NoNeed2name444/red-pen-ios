# Vignette: integrated implementation plan (growth, monetisation, retention, trust, launch)

Written 2026-09-24 against branch `preview/graph` at `effa18d`. It combines the six architect designs A to F, plus the marketing scope G, into one plan organised in waves. The owner rejected **"challenge a friend" duels**, so the plan builds no head-to-head or friend-challenge feature of any kind. The existing single-player "lookalike duels" (`Features/Reasoning/DuelView.swift`) are a different thing and stay as they are.

This file: `/tmp/claude-0/-home-user/8857977a-f678-5988-9658-6061ad2dfd91/scratchpad/rp-prev/docs/launch/implementation-plan.md`. Supporting files, all in the same `docs/launch/` folder, are part of the plan:

| File | What it is |
|---|---|
| `designs/A-share-loops.md` … `designs/F-trust-legal-arabic.md` | The six source designs, verbatim. Packages cite them as "A §4.2". **Where a design and this plan disagree, this plan wins.** |
| `schema/unified-tables.sql`, `schema/accounts-alters.sql`, `schema/accounts-indexes.sql`, `schema/share-store.sql` | The single resolved D1 schema, already loaded into SQLite to check it: old database, fresh database, re-run. |
| `config-defaults.json` | Remote-config flags, limits, ranges, public keys and environment fallbacks for all groups. |
| `api-routes.md` | Every new route: its auth, the module that owns it, and the package that builds it. |
| `package-files.tsv` | Every package's files (wave, package, action, path), generated from the `files` blocks below and checked for overlaps (§8.3). |
| `app-store-listing.md`, `reels.md`, `ambassadors-and-referrals.md`, `pricing.md`, `launch-checklist.md`, `privacy-and-terms-draft.md` | The marketing and launch documents (group G). A separate workflow phase writes them. Package P6.1 turns them into machine-readable inputs. |

---

## 0. Summary for the orchestrator

**How the plan works.** Wave 0 builds the seams first: a route registry on the Worker, hook and slot files in the app, suite and preview manifests in CI, the unified schema, remote config, consent and the owner flag. After that, no two packages in the same wave edit the same file. Every package lists its files in a `files` block. The check in §8.3 confirms those lists are disjoint within each parallel group.

### Waves

| Wave | Packages (parallel inside a row) | Starts after | Gate |
|---|---|---|---|
| **W0a** seams | P0.1 server seams · P0.2 app core seams · P0.3 CI and tooling seams | the two running jobs (UI overhaul, audit) have merged | server tests green, deploy dry-run, swift suites green, app build and existing UI tests green, screenshots unchanged apart from the sign-in footer |
| **W0b** seams | P0.4 screen seams | P0.2 | app build and UI tests green, no visible change |
| **W1** server | P1.1 shares and moderation · P1.2 classes, groups and leaderboards · P1.3 Apple billing core (JWS, notifications, entitlement) · P1.4 referrals, class access, ambassadors, owner billing · P1.5 AI money and limits, config admin, allowance · P1.6 generation cache · P1.7 telemetry · P1.8 trust, legal pages, accuracy page | W0 gate | all `server/tests/*.test.mjs` green; account deletion stays within 50 statements; worker deployed; smoke checks |
| **W2** app | P2.1 share links · P2.2 classes and leaderboards · P2.3 paywall and billing · P2.4 intents, Spotlight, widget data · P2.5 remote config and owner console · P2.6 on-device assist · P2.7 cache offer · P2.8 telemetry and privacy choices · P2.9 consent, legal, error reports | W1 gate | swift suites, app build, all UI tests, preview screenshots, Playgrounds compile |
| **W3** Xcode-only | P3.1 widgets, Live Activity, `project.yml`, privacy manifest · P3.2 release automation (TestFlight, App Store Connect API) · P3.3 Private Cloud Compute | W2 gate (P3.2 may start any time after W0) | extension present in build; TestFlight upload once the owner's key exists |
| **W4** performance | P4.1 `@Observable` migration, off-main loading, drawing fixes (one package, serial) | W3 gate | perf workflow no worse than the W2 baseline; all tests |
| **W5a** localisation | P5.0 localisation infrastructure · P5.1 to P5.6 folder sweeps (strings plus RTL) | W4 gate | lint green, both builds compile |
| **W5b** localisation | P5.7 translation run and Arabic QA | W5a | Arabic coverage gate; Arabic screenshots |
| **W6** launch | P6.1 launch metadata, **then** P6.2 release run | W5 gate and owner steps 1–5 (§6) | submission-ready checklist handed to the owner |

### Decisions that remove conflicts

These are detailed in §2.

1. **Seams before features.** W0 lands a router registry, stub modules, hook files, UI slots, suite manifests and preview lists. From then on, each package edits only files it owns.
2. **One schema, landed once.** It lives in `docs/launch/schema/` and P0.1 lands it. Later schema changes go into new `server/migrations/*` files.
3. **Group licences are class access.** A licence is owner-created and attaches to an A class (`licences.group_id`). The class join code is the access code. Joining takes a seat while seats remain. This drops design B's `/groups/*` licence routes and its `GET /g/`.
4. **Route collisions renamed.**
   - Moderation moves to `/moderation/report` (F keeps `/reports`).
   - Telemetry moves to `/telemetry/diag` and `/telemetry/usage`.
   - D's allowance moves to `/account/allowance`.
   - Every owner route sits under `/owner/*` (owner account or `OWNER_KEY`, 404 for everyone else).
   - CI routes sit under `/ci/*` and use a single `CI_KEY`. Benchmark publishing also accepts `OWNER_KEY`, as the brief asks for an owner-authenticated endpoint.
5. **One remote config (design D)** replaces the feature on/off environment variables from A, B, E and F. The env vars remain as fallbacks.
6. **One owner model.** The session carries `owner`; `/account/me` refreshes it; the app has one Owner hub with rows for billing and class access (B), config and cloud usage (D), insights (E), and reports (F).
7. **One consent route, `/account/consent`**, covering terms v3, third-party-AI consent (5.1.2(i)) and community rules (1.2).
8. **One deep-link parser and router.** Links only navigate or open a confirmation sheet. No link changes data without a tap.
9. **Order of the cross-cutting work:** performance refactor (W4) comes after features, and localisation (W5) comes last.
10. **App Store Connect work runs through the App Store Connect API** from GitHub Actions: products, prices, intro offer, offer codes, notification URLs, metadata, screenshots and review notes. The owner only does what Apple does not expose (§6).

### Launch blockers found in the code

These are fixed early:
- `SubscriptionStore.isPro` returns `true` for everyone (the personal patch is in this branch's history). P0.2 fixes it.
- The paywall links point to `redpen.app`. P0.2 fixes it.
- `askApple` without keys writes `verified_until = 0`. P1.3 fixes it.
- `Product.SubscriptionInfo.status(for: "Red Pen Pro")` passes a group *name* where a group *ID* is required. P2.3 fixes it.
- `linkSubscription` answers 403, which the app reads as "signed out". P1.3 fixes it.

### Owner's unavoidable steps

In full in §6. None of them is typed into chat.
1. Enrol in the Apple Developer Program ($99/yr).
2. Create an App Store Connect **Team API key** and add it as three GitHub secrets.
3. Create the app record once agents have registered the bundle ID.
4. Complete the Paid Apps agreement, bank and tax.
5. Apply to the Small Business Program.
6. At submission:
   - App Privacy answers (supplied in §6).
   - Medical-device declaration: "not a medical device".
   - Confirm the age rating.
   - EU trader status.
   - Review contact details.
   - Attach the in-app purchases to the first version, then press Submit.

### Highest App Store risks

In full in §7:
- **1.2 user-generated content.** Mitigation: filter, report, block, contact page, auto-suspend and owner review.
- **1.4.1 medical, plus the medical-device declaration.** Mitigation: education-only positioning and an accuracy page with confidence intervals.
- **5.1.2(i) third-party AI.** Mitigation: a named-provider consent screen before the first upload.
- **3.1.1 class-access codes.** Mitigation: owner-only, school-provided framing, no price in the app, and a kill switch with an Apple offer-code fallback.
- **2.3.7 keywords.** Mitigation: no "Anki" in the name, subtitle or keywords.
- **5.1.1(ii) telemetry consent.** Mitigation: off by default, one neutral ask.

### Running a package

Give the agent three things:
- this plan's §3 and §4;
- its package section;
- the cited design file sections, plus `api-routes.md`, the schema files and `config-defaults.json`.

Branch `growth/<package-id>` from the integration branch `growth/main`. Merge at the wave gate after CI is green.

---

## 1. Facts from the code that shape the plan

- **Baseline.**
  - `preview/graph` is 147 commits ahead of `origin/main` and contains the personal-build commit `8dc4b16`. That commit:
    - hard-codes Pro;
    - adds "Start without an account" (a local-only session);
    - makes sync skip local sessions.
  - The last two are fine for the App Store build ("no login needed" helps review under 5.1.1(v)). The Pro unlock is not.
  - After P0.2, Pro unlocks at runtime only when `PersonalBuild.isOn`, so one branch builds both the App Store app and the personal Playgrounds app, and the personal patch is no longer needed.
- **Tests today.**
  - All 7 server test files pass: sync, ai, jobs, pair, evidence, bench, tts. CI runs only 4 or 5 of them, from hard-coded lists in `server-tests.yml` and `worker-deploy.yml`.
  - There are 23 Swift suites, listed by hand in `swift-tests.yml`.
  - The preview screens are listed by hand in `ios-preview.yml`. The flag is `-uiPreviewScreen`, not `-previewScreen` as designs A and B wrote it.
- **Worker today.**
  - It is POST-only, except `/blobs/*` and `/jobs*`.
  - There is no cron, no GET page and no owner flag in the session.
  - `fail()` has no `code` field.
  - `proGate` → `isPro` → `askApple`.
  - R2 is not enabled on the account (A), so shared-set bytes use a second D1 database.
- **Free-plan limits** (A, D, E):
  - 10 ms CPU per invocation;
  - 50 D1 queries per invocation;
  - D1 at 5 M rows read and 100 k written per day, enforced since 1 Sep 2026;
  - 5 cron triggers;
  - a 100 k/day request budget.
- **App request paths.**
  - `AuthAPI.send` maps 401 and 403 to `.signedOut`, and 404 to `.notConfigured`.
  - These files build their own requests: SyncAPI (blobs), CloudTranscriber, CloudVoice, CloudJobs, HostedLLMClient and CoverageCloudCheck. All of them need the consent gate and the build headers.
- **UI tests.** `LocalSignInUITests` taps `localSignIn` and `acceptRecordingTerms`. Nothing added may appear at launch or rename these.
- **Playgrounds build.**
  - `SWIFT_PACKAGE` is defined.
  - `make_swiftpm.py` copies `ios/RedPen` whole into the package.
  - There is no Info.plist, no entitlements, no URL types and no app extensions.
  - Extension-only code must therefore live outside `ios/RedPen` (in `ios/RedPenWidgets/`).
- **App Store Connect API.**
  - It cannot create the app record: `POST /v1/apps` is refused for every key role.
  - It *can* do all of the following:
    - set the App Store Server Notifications URLs (the `subscriptionStatusUrl` and `subscriptionStatusUrlForSandbox` attributes on the app);
    - create bundle IDs and capabilities;
    - create subscriptions, prices, intro offers and offer codes;
    - upload metadata and screenshots;
    - write review notes.
  - App Privacy answers remain web-only.
- **Docs phase.** A later phase of this same workflow writes the six G documents listed above. This plan does not write them; P6.1 consumes them.

---

## 2. Conflicts and how they are resolved

| # | Conflict | Resolution |
|---|---|---|
| R1 | **Group licences (B) against classes (A).** B had its own `licence_groups` with join codes, `/groups/join\|leave\|mine` and `GET /g/`. A reserved `groups.licence_id`. | Merged. A `licences` row points at one A class (`group_id UNIQUE`). The class join code is the "class access" code. `groups.js` `/groups/join` calls `licences.onGroupJoin()`, which allocates a seat while any remain. A full class still admits the member, without Pro (`licence.seat = "full"`). Owner-only `/owner/licences/*` creates a licence *by class join code*. B's `licence_members` becomes `licence_seats`, and `groups.licence_id` is dropped. Seats free on leave, remove or delete (`onGroupLeave`). The Pro source is "Class access from ‹institution›". |
| R2 | `server/groups.js` is claimed by both A and B. | A keeps `groups.js`. B's code goes to `licences.js`, `referrals.js`, `ambassadors.js` and `billing-owner.js`. |
| R3 | `POST /reports` and a `reports` table appear in both A (moderation) and F (item errors). | F keeps `POST /reports` and the `error_reports` table. A becomes `POST /moderation/report` and `moderation_reports`, with owner routes `/owner/moderation/list\|resolve`. A's `contact` target is dropped because F's `/support` is the contact channel. When F receives an `offensive` report on an item from a shared set, it calls `moderation.recordModeration()`, which counts towards A's auto-suspend. |
| R4 | `POST /usage` is in both D (allowance) and E (anonymous counters). | D becomes `POST /account/allowance`, with owner routes `/owner/cloud-usage` and `/owner/account-caps`. E becomes `POST /telemetry/usage` and `/telemetry/diag`, with owner route `/owner/insights`. |
| R5 | Owner helpers are defined in B (`owner.js` dispatch), D (`ownerCaller`), E and F (`isOwnerAccount` in `owner.js`). | One `server/lib/owner.js` (P0.1) with `keyMatches`, `isOwnerAccount` and `ownerCaller`. The router's `owner` auth mode answers 404 to non-owners. B's owner dispatch becomes `billing-owner.js`. |
| R6 | A's `app_config` against B's `app_facts`. | One `app_facts` table with keys `apple_team_id`, `app_store_id` and `app_store_lookup_at`, behind one `lib/appfacts.js`. B's `apple_app_id` is the same number as A's App Store id. |
| R7 | Four separate cron designs (B, D, E at 03:17; F at 03:23). | One `scheduled()` in `cron.js` with three slots: 03:17 `maintenance` (D cache, F purge, A stats, counter prune), 03:47 `telemetry` (E roll-ups), 04:17 `billing` (B referrals, grants, notification prune, app-id lookup). Each module exports `cron` tasks by slot. |
| R8 | E's `CI_KEY` (from `CLOUDFLARE_API_TOKEN`) against F's `BENCH_KEY` (from `AI_API_KEY`). | One `CI_KEY = sha256("vignette-ci:" + CLOUDFLARE_API_TOKEN)`, derived by the deploy workflow and by any workflow that needs it. All `/ci/*` routes use it. `/ci/bench/publish` (F's `/bench/publish`) also accepts `OWNER_KEY`, which the benchmark workflows already derive from `AI_API_KEY`, so it stays owner-authenticated as the brief asks. `OWNER_KEY` stays for `/owner/*`. |
| R9 | IP handling differs: A uses raw IPs, B `sha256(secret+ip)`, E a daily HMAC, F `iph:` hashes. | One `ipKey()`: the first 16 hex of HMAC-SHA256(`SESSION_SECRET`, `ip:<addr>:<UTC day>`), for every new limit. `pair.js` is untouched. The W0 cron prunes `pair_attempts` older than 48 h. |
| R10 | Deep-link parsers: A `ShareLinks`, B `InviteLinks` (with `/g/` and `/a/`), C `DeepLink`. | One `Shared/DeepLink.swift` (P0.2) with cases `share`, `join`, `referral`, `code`, `due`, `set`, `quiz`, `exam`. `/a/` stays web-only (it opens Apple's offer-code redemption). AASA paths are `/s/*`, `/j/*` and `/r/*`. C's rule applies to all of them: links navigate or open a confirmation sheet, never mutate. |
| R11 | `StudySet.origin` (A) collides with the "origin" field of F's report. | A's field is `StudySet.shareOrigin` (JSON key `shareOrigin`), added in P0.2. F derives a report's origin as `shared`, `example` or `unknown`. F's `error_reports.share_id` becomes `share_code`, matching moderation's `target_ref`. |
| R12 | Four owner screens (B owner tools, D owner console, E owner insights, F reports review). | One `Features/Owner/OwnerHubView.swift` (P0.4), shown when `OwnerGate.shared.isOwner` or `PersonalBuild.isOn`. It has rows for billing and class access (B), config and cloud usage (D), assist self-test (D), insights (E), and reports: errors, community and support (F). |
| R13 | A's community-rules acceptance (`/shares/terms`, `ugc_terms_at`) against F's terms v3 and AI consent. | One `POST /account/consent {termsVersion?, aiConsent?, rulesVersion?}` (P0.1). Columns are `terms_*`, `ai_consent*` and `rules_*`. `LEGAL = {privacy: 1, terms: 3, aiConsent: 1, rules: 1}` lives in `account.js`. Publishing, creating or joining a group without current rules returns 428 `rules_required`. |
| R14 | Error statuses: A used 403 and 404 for business errors. B found that the app maps those to signed-out and not-configured. | For every new JSON route: 400, 409, 410, 413, 422, 428, 429, 503 or 507, always with a `code`. Owner and CI routes return 404 to others. The app (P0.2) maps any body with a `code` to `.refused(code:message:)` whatever the status, except 401, 402, 428 and 429. |
| R15 | Feature switches as env vars (A `SHARES_*`, B `REFERRALS`/`GROUP_*`, E `TELEMETRY*`, F `REPORTS`/`AI_CONSENT_ENFORCED`) against D's remote config. | All of them are keys in `config-defaults.json`, read through `flag()` and `limit()`. The env vars remain fallbacks (the `_env` map). |
| R16 | Account deletion: A `wipeSocial`, B's batch, D `wipeCache`, F `forgetTrustData`. | Each module exports `onAccountDelete` for its own tables. `worker.js` runs them in a fixed order after `wipe()`. `account-delete.test.mjs` keeps the total within 50 statements. |
| R17 | `worker.js`, `schema.sql`, `wrangler.toml`, `worker-deploy.yml` and `server-tests.yml` are edited by every design. | W0 only (P0.1). W1 modules self-register routes, cron tasks and delete hooks. Tests are picked up by glob. Schema changes after W0 go into `server/migrations/`. |
| R18 | The study screens (MCQ, cards, cases, OSCE, book, narrate, summaries, due) are edited by C, D, E and F. | P0.4 adds: the `report:` menu item and its sheet, `AssistSlot` placements, `AppEvents` calls, and C's `startAt` (P0.2). W2 packages fill only their own stub files. |
| R19 | `RedPenApp.swift`, `AuthAPI.swift` and `AccountStore.swift` are touched by all six designs. | P0.2 only. It adds lifecycle fan-out through `AppHooks`, URL routing through `AppRouter`, root extras and the networking changes. Features use `@Observable` singletons and never inject from `RedPenApp`. |
| R20 | `AccountView`, `SupportCenter`, `ModelSettingsView` and `LibraryView` are touched by several designs. | Slots (P0.4) for account sections, settings rows, the owner hub and the cloud-allowance section. `LibraryView` is P0.2's in W0 and P2.1's in W2. `ModelSettingsView` is P2.4's in W2 and P3.3's in W3. |
| R21 | `project.yml`, `make_swiftpm.py` and `PrivacyInfo.xcprivacy` are touched by A, B, C, D, E and F. | P3.1 owns all three in W3; P5.0 owns `project.yml` and `make_swiftpm.py` in W5. `make_swiftpm.py` moves into the repo as `tools/make_swiftpm.py` (P0.3). |
| R22 | E's `@Observable` migration and F's string sweep both touch every view. | Performance runs as W4 (one serial package) and localisation as W5, last, as the brief asks. New code from W2 on is already `@Observable` and uses localisable literals. |
| R23 | Event names: C uses dotted names (`widget.rate`), E uses snake_case. | Snake_case everywhere. There is one `AppEvent` enum (P0.2) and one server allow-list (P1.7). The list is in §8.1. |
| R24 | C adds shortcuts, and an app may have only one `AppShortcutsProvider`. | C extends the existing `RedPenShortcuts` provider (6 of the 10 allowed shortcuts). No second provider. |
| R25 | Share codes and join codes are both 10 characters (A). Referral codes are 7 (B). | Bare 10-character codes resolve through a new public `POST /codes/lookup` (P1.1). 7-character codes are referrals. |
| R26 | `ai.js` is changed by B (wallet only when paying, `budget` counts `paid_until`) and by D (micro path, fair shares, daily and global caps, config limits). | One package, P1.5, owns `ai.js` and applies both. `proGate` keeps its signature. P0.1 moves the Apple code to `apple.js` so that P1.3 never touches `ai.js`. |
| R27 | Name rules are needed by A1 (titles) and A2 (display names), with JS/Swift parity. | P1.1 writes `server/names.js`, `ios/RedPen/Shared/NameRules.swift` and the shared fixture, so both sides are built by one agent. |
| R28 | Design D's class roles ("lecturer") against A's (owner, admin, member). | Owners and admins contribute to the class cache. Members contribute when `groups.members_share_generated = 1`, a new column set by the class owner in `/groups/update`. |
| R29 | `PrivacyInfo.xcprivacy` is "whoever lands first" in B, C, E and F. | P3.1 writes it once from the §6 table. |
| R30 | The group G marketing docs. | The Docs phase writes the six documents. P3.2 builds the reel-footage job. P6.1 converts the documents into `metadata/`, `pricing.json` and review notes. |

---

## 3. Integrated architecture

### 3.1 Server contract (built in P0.1, used by every W1 package)

**Module shape.** Every feature module exports:

```js
export const routes = [
  { method: 'POST', path: '/shares/publish', auth: 'session', maxBytes: 5 * 1024 * 1024, handler: publish },
  { method: 'GET',  path: '/s/:code.json', auth: 'public', handler: shareMeta },          // HEAD handled by the router
  { method: 'PUT',  path: '/share-blobs/:shareId/:hash', auth: 'session', body: 'raw', maxBytes: 1_800_000, handler: putBlob },
];
export const cron = [{ slot: 'maintenance', name: 'shares.gc', run: async (env, now) => {} }];
export async function onAccountDelete(env, accountId) {}
// handler(ctx): ctx = { request, env, url, params, body, accountId, owner, ip, ipKey, cfg } -> Response
```

**Route fields.**
- `auth` is one of `public`, `session`, `pro` (session plus `entitlement().pro`, otherwise 402), `owner` (otherwise 404), `ci` (otherwise 404) or `apple` (no session).
- `body` is `json` (the default, up to `maxBytes`, default 64 KB), `form` or `raw`.
- A body without `content-length` gets 411.

**Router order in `worker.js`:**
1. the existing `/blobs/*` and `/jobs*` blocks;
2. the router;
3. an unmatched GET or HEAD returns the HTML 404 page;
4. any other non-POST returns 405;
5. the legacy switch.

At load time the router throws if two routes collide, or if a route collides with a legacy path.

**Error convention.**
- The body is `fail(status, message, code)`, giving `{error, message, code}`.
- Codes in use:
  - `bad_request`, `bad_code`
  - `needs_pro` (402)
  - 409s: `not_yours`, `share_banned`, `joining_closed`, `group_full`, `not_member`, `owner_must_transfer`, `bought_by_other_account`, `linked_elsewhere`, `self_referral`, `already_referred`, `too_late`, `too_many_open`
  - 410s: `gone`, `group_ended`, `referrals_off`
  - `too_large` (413), `name_rejected` (422, with a `field`)
  - 428s: `rules_required`, `ai_consent_required`
  - `rate_limited` (429), `feature_off` (503), `storage_full` (507)
- Owner and CI routes send non-owners 404 `not_found`.
- Anything unexpected returns 500 with a generic message; the error itself is never echoed.

**Cross-module functions.** P0.1 creates each as a stub with these exact signatures and a safe default. The listed package fills it in.

| Function | Default in W0 | Filled by |
|---|---|---|
| `invites.inviteBucket(env, code)` → `'share'`, `'group'` or `null` | `null` | P1.1 |
| `names.checkName(kind, raw)` → `{ok, value, reason}`, where kind is `title`, `subject`, `group` or `display` | NFKC, trim, length only | P1.1 |
| `moderation.recordModeration(env, {reporterId, targetType, targetRef, reason, note})` → `{suspended}` | no-op | P1.1 |
| `moderation.blockedIds(env, accountId)` → `Set` | empty | P1.1 |
| `groups.memberRole(env, groupId, accountId)` → `'owner'`, `'admin'`, `'member'` or `null` | `null` | P1.2 |
| `groups.canShareGenerated(env, groupId, accountId)` → bool | `false` | P1.2 |
| `licences.onGroupJoin(env, groupId, accountId)` → `{granted, reason, until, institution}` | `{granted: false, reason: 'none'}` | P1.4 |
| `licences.onGroupLeave(env, groupId, accountId)` | no-op | P1.4 |
| `licences.licenceForMember(env, groupId, accountId)` → `{institution, until, seat}` or `null` | `null` | P1.4 |
| `licences.activeLicenceFor(env, accountId)` → `{licenceId, name, institution, until, paidModels, monthlyBudgetUsd}` or `null` | `null` | P1.4 |
| `entitlement.entitlement(env, accountOrId, {activate, fetcher})` → `{pro, paying, until, source, sources, banked, owner, features, walletKey}` | legacy `isPro` logic (passes `fetcher` to `askApple`, as `proGate` does today) | P1.3 |
| `appstore.verifyAppleJWS(jws, {now})`, `appstore.verifyAppTransaction(env, jws)` → payload or `null` | `null` | P1.3 |
| `cache.publishToCache(env, job)` | no-op | P1.6 |
| `account.consentGate(env, cfg, accountId)` → Response or `null`; `account.LEGAL` | complete in W0 | P0.1 |

**Account-deletion order.**
1. `sync.wipe`
2. `share`
3. `groups`
4. `moderation`
5. `licences`
6. `referrals`
7. `appstore`
8. `cache`
9. `trust`
10. delete from `pair_codes`, then the `accounts` row

Each hook uses at most 6 statements, batched with `env.DB.batch` where possible. E stores no linked data, so it has no hook.

**Helpers.**
- Limits: `limit(cfg, env, name)`. Flags: `flag(cfg, name)`.
- Rate limits: `hit(env, key, what, n)` with `ipKey` or `acct:<id>` keys, never a raw IP.
- Owner check: `ownerCaller`.
- Pages: `web.page()`, `pickLang()` and `esc()`, with the shared CSP (script hashes only), `nosniff` and `no-referrer`. The footer always reads "For medical education, not clinical decisions."

**D1 budget.**
- At most 50 statements per request; the harness counts them.
- Hot paths use no full scans.
- Every query is parameterised.
- Nothing logs a request body.

### 3.2 App contract (P0.2 and P0.4)

**Lifecycle.**
- `AppHooks.launched`, `becameActive`, `enteredBackground`, `signedIn`, `backgroundRefresh` and `wantsBackgroundRefresh` fan out in a fixed order: Config, Trust, Billing, Share, Group, Glance, Telemetry.
- Each fan-out targets one enum per feature in `Shared/Hooks/*Hooks.swift`, all stubs in W0.
- They are called with an `AppContext` of `{store, reviews, account, subscriptions, sync, notes}`.
- Preview launches (`PreviewLaunch.screen != nil`) skip all hooks.
- `becameActive` first runs `account.refreshMe()`, which updates `OwnerGate` and the consent versions.

**Deep links: `DeepLink` and `AppRouter.shared.pending`.**

| Case | Accepted forms | Consumer |
|---|---|---|
| `.share(code)` | `https://<worker>/s/CODE`, `redpen://s/CODE` | `ShareLinkSheets` (P2.1) |
| `.join(code)` | `/j/CODE`, `redpen://j/CODE` | `GroupLinkSheets` (P2.2) |
| `.referral(code)` | `/r/CODE` (7 characters), `redpen://r/CODE` | `InviteLinkSheets` (P2.3) |
| `.code(code)` | a bare 10-character code, typed or pasted | `ShareLinkSheets`, via `POST /codes/lookup`, which may re-route to `.join` |
| `.due(card:)`, `.set(id)`, `.quiz(subject:count:)`, `.exam` | `redpen://due[?card=]`, `redpen://set/UUID`, `redpen://quiz?subject=&count=`, `redpen://exam` | `LibraryView` (P0.2) |

Parsing rules:
- Codes are upper-cased, stripped to `[A-Z0-9]`, and must use the `pair.js` alphabet at an exact length (10, or 7 for referrals).
- `redpen://auth` and unknown hosts give `nil`.
- `https` is accepted only for the worker host.
- `subject` is at most 80 characters; `count` is clamped to 5…50.
- `find(in:)` handles WhatsApp-wrapped text.
- `init(spotlightID:)` handles `set:<uuid>` and `item:<set>:<item>`.
- Consumers sit on `LibraryView`, so a link waits through sign-in and the terms gate.

**Stub types.** P0.2 or P0.4 creates each one; the owning W2 package fills it in without changing the signature.

| Type (file) | API | Filled by |
|---|---|---|
| `ShareCenter` (`Persistence/ShareCenter.swift`) | `shared`, `isAvailable`, `installId`, `importShared(code:into:groupId:) async throws -> StudySet`, `publish(set:includeSources:showName:account:) async throws -> PublishedShare` | P2.1 |
| `GroupCenter` (`Persistence/GroupCenter.swift`) | `shared`, `isAvailable`, `groups: [GroupDTO]`, `classesICanShareTo`, `addSet(shareId:to:account:) async throws` | P2.2 |
| `InviteCenter` (`Shared/Billing/InviteCenter.swift`) | `shared`, `claim(code:account:) async throws` | P2.3 |
| `ReportStore` (`Shared/ReportStore.swift`) | `shared`, `submit(_ item: StudyItemRef, reason:note:) async` | P2.9 |
| `CloudGate` (`Shared/CloudGate.swift`) | `shared`, `ensureConsent(for: CloudPurpose) async throws`; the W0 version returns at once | P2.9 |
| `RemoteConfigStore` (`Shared/RemoteConfigStore.swift`) | `shared`, `config`, `isOn(_:)`, `limit(_:)`; W0 serves built-ins only | P2.5 |
| `OwnerGate` (`Shared/OwnerGate.swift`) | `shared.isOwner`; complete in W0 | — |
| Modifiers `ShareLinkSheets`, `GroupLinkSheets`, `InviteLinkSheets`, `TrustRootSheets`, `ConfigBanner` | no-op | P2.1, P2.2, P2.3, P2.9, P2.5 |
| Views `GroupsView`, `LibraryNotices`, `ReportErrorSheet`, `ModerationReportSheet`, `AssistSlot`, the three `*AccountSection`s, the rows `PrivacyChoicesRow`, `AppLanguageRow` and `CloudAIRow`, `CloudAllowanceSection`, the owner tools and the `*Previews` enums | `EmptyView` with `static let isAvailable = false` | the package named in its file header |

**Network (P0.2).**
- `AuthAPI.send(path, body, token, method)`, `sendData(...)` for raw PUT, and `get(path)` for public JSON.
- Every request to the worker carries `X-Vignette-Build` and `X-Vignette-Surface` (`app` or `playgrounds`) through `VignetteHeaders`.
- Status mapping:
  - 2xx: success.
  - 401: `.signedOut`.
  - 402: `.needsPro`.
  - 428: `.needsConsent(code)`.
  - 429: `.tooManyTries`.
  - Any body with a `code`: `.refused(code, message)`.
  - Otherwise 403 is `.signedOut`, 404 is `.notConfigured`, 410 is `.gone`, and anything else is `.server`.

**Events.** `AppEvents.record(.questionsAnswered, count: n)` forwards to `TelemetryHooks.record`. It does nothing until P2.8 lands and the user opts in. The names are in §8.1.

**Study item references.** `StudyItemRef` is Foundation-only (P0.4): `kind`, `setId`, `itemId`, `prompt`, `options`, `correctIndex`, `answer`, `explanation`, `extra`, `sourceLabel`, `shareCode`. It has adapters for MCQ questions, cards, QA cards, OSCE steps, book pages and narrate segments. It is shared by reports (F) and assist (D).

**Swift suites.** Each suite is a file `ios/RedPen/Tests/Suites/<name>.suite`:
- first line: `test <File>.swift`;
- then one `src <repo path>` per line;
- lines starting with `#` are comments.

The workflow compiles and runs every suite file (P0.3).

**Previews.** Each package adds `ios/previews/<package>.txt`, one `-uiPreviewScreen` name per line, and routes the names through its `*Previews.view(for:)`. P0.4 registers these names in `PreviewExtras`:
- A: `share-preview`, `group-detail`, `leaderboard`
- B: `paywall-store`, `invite-friends`
- C: `surfaces`
- D: `cloud-usage`, `owner-console`, `assist-bar`
- E: `privacy-choices`, `owner-insights`
- F: `report-error`, `about-legal`, `reports-review`

### 3.3 Data model

These are the tables, by owner. The exact DDL is in `docs/launch/schema/`.

- **Shared:** `app_facts`.
- **A:** `shares` (plus `SHARE_STORE`: `share_manifests`, `share_blobs`), `groups` (with `members_share_generated`, without `licence_id`), `group_members`, `group_sets`, `weekly_stats`, `blocks`, `moderation_reports`.
- **B:** `apple_subscriptions`, `apple_passes`, `apple_notifications`, `pro_grants`, `referrals`, `licences`, `licence_seats`, `ambassadors` (with `offer_status`).
- **D:** `remote_config`, `remote_config_history`, `gen_cache`.
- **E:** `diag_*`, `perf_*`, `usage_*`, `telemetry_budget`. None of these has an account, IP or install column; the validation run checked this.
- **F:** `error_reports` (with `share_code`), `support_messages`, `bench_runs`.
- **`accounts` gains 14 columns:**
  - terms, AI consent and rules, with their timestamps;
  - `share_banned`, `joined_via` (attribution only; nothing rewards it);
  - `account_token`, `paid_until`, `referral_code`, `app_transaction_id`, `last_seen_day`;
  - `caps`.
- Indexes on the new `accounts` columns are created after the ALTERs, never in `schema.sql`.

### 3.4 Remote config

`config-defaults.json` has 31 flags and 63 limits, with ranges.

- Flag namespaces: `share.*`, `billing.*`, `surfaces.*`, `assist.*`, `cloud.*`, `cache.*`, `usage.*`, `telemetry.*`, `trust.*`.
- The server enforces the limits. The app reads flags only to adjust the UI.
- All `assist.*`, `cloud.*`, `share.*` and `billing.*` flags stay **on** during App Review (2.3.1).

### 3.5 Xcode (App Store) build against the Playgrounds build

| Capability | Xcode / App Store build | Playgrounds (owner) |
|---|---|---|
| Universal links `/s` `/j` `/r` | yes (Associated Domains) | no. `redpen://` is tried through the plist that `make_swiftpm` writes; otherwise paste the link or code. |
| Paywall, exam pass, offer codes, referral as referee | yes | Pro comes from `PersonalBuild.isOn`. Products are unavailable. Referral claims say "App Store version". |
| Widgets, Control, Live Activity | yes (`ios/RedPenWidgets` extension) | no. Settings says they come with the App Store version. |
| App Intents / Siri | yes | compile and run in the app; Siri may not list them |
| Spotlight, on-device assist (FoundationModels) | yes | yes |
| Private Cloud Compute | only when CI detects the entitlement and the iOS 27 SDK | compiled out |
| MetricKit | yes | compiles; delivery unverified |
| Arabic | String Catalog | generated `.lproj` plus the `LanguageBundle` shim |
| Background refresh (feeds, glance) | yes | on launch and foreground only |

---

## 4. Rules for every package

1. **Read first.** Re-read every file you will edit; the two running jobs are changing them. Implement the cited design sections, applying the overrides in this plan. When the two disagree, follow this plan.
2. **Stay inside your file set.** Touch only the files in your `files` block (`new` means create, `edit` means change, `fill` means replace a W0 stub body without changing its public API). If you need another file, stop and record a follow-up for the wave gate; do not edit it.
3. **Stubs.** Keep W0 signatures. When your feature works, flip `static let isAvailable = true` in your own stub files.
4. **Server.**
   - Declare routes in your module's `routes`.
   - Use `fail(status, message, code)`, `limit()`, `flag()` and `hit()` with `ipKey`. Parameterise all SQL, stay within 50 statements per request, keep CPU well under 10 ms, and never log a body.
   - Tests go in `server/tests/<name>.test.mjs` on `tests/helpers/harness.mjs`, and must be hermetic: no network, fake `fetch`.
5. **App.**
   - New classes are `@MainActor @Observable final class` singletons, using scratch files when `PreviewLaunch.screen != nil`.
   - Heavy work (JSON, images, hashing, FoundationModels) runs off the main actor.
   - No `AnyView`. No UIKit in pure files. No `@main` inside `ios/RedPen` apart from the app.
   - Both builds must compile: Playgrounds defines `SWIFT_PACKAGE` and has no Info.plist or entitlements.
   - Put every pure file into a `.suite`.
   - Keep the accessibility identifiers `localSignIn`, `acceptRecordingTerms`, `studyMore` and `turnInto`.
   - Nothing new may appear at launch. The consent sheet appears only at the first cloud use; the telemetry ask only after 3 active days.
   - UI tests that exist for one workflow (performance, store screenshots, reel footage) call `XCTSkipUnless` on an environment variable their workflow sets (`VIGNETTE_PERF`, `VIGNETTE_STORE_SHOTS`, `VIGNETTE_REELS`), so `app-build` stays fast.
6. **Strings.** User-facing strings are literals or `String(localized:)`. Never build a sentence by concatenation. Prompt strings (`Shared/LLM/*`, `MCQPrompt`, `*Writer`, `@Guide`) stay plain `String`.
7. **Secrets.**
   - Never put a key, token or secret in code, tests, logs, commit messages or chat.
   - Workflows derive `OWNER_KEY` and `CI_KEY` from repository secrets.
   - App Store builds must ship an empty `RedPenOwnerKey`.
8. **Medical.** Use study wording everywhere ("for education, not clinical decisions"). No accuracy claim appears without a link to `/accuracy`.
9. **Done means:**
   - the tests in your package are green in CI;
   - the acceptance checks pass;
   - the preview screens are added;
   - the `isAvailable` flags are flipped;
   - a short note lists any follow-ups for the gate.

---

## 5. Waves and packages

### Pre-flight (orchestrator, before W0)

1. Wait until the UI-overhaul job and the audit job have merged.
2. Create `growth/main` from the result.
3. Re-run all server tests and the Swift suites, and record the pass counts.
4. Run `app-build` and `ios-preview`, and keep the screenshots as the baseline.
5. Check that every `edit` path in this plan still exists. Fix any renamed path in the package text before dispatching.
6. From the W0 gate on, build the owner's Playgrounds package from `growth/main` with `tools/make_swiftpm.py` and a `.personal` bundle id. P0.2 makes the Pro unlock a runtime check, so the old personal patch is no longer applied.

---

### W0a · P0.1 Server seams

**Goal.** Make the Worker modular, and land the schema, config, consent, owner flag, cron, deletion hooks and invite hook that W1 depends on.

Design references: D §2.1 for config; F §2 for owner and consent; A §4.1 and §5.3 for the invite bucket; E §2.2 for the cron; B §2.1 for the column list.

```files
new  server/router.js
new  server/web.js
new  server/cron.js
new  server/config.js
new  server/account.js
new  server/apple.js
new  server/entitlement.js
new  server/lib/http.js
new  server/lib/crypto.js
new  server/lib/codes.js
new  server/lib/owner.js
new  server/lib/limits.js
new  server/lib/appfacts.js
new  server/share.js
new  server/storage.js
new  server/sharepage.js
new  server/names.js
new  server/invites.js
new  server/moderation.js
new  server/groups.js
new  server/appstore.js
new  server/referrals.js
new  server/licences.js
new  server/ambassadors.js
new  server/billing-owner.js
new  server/invitepage.js
new  server/configadmin.js
new  server/allowance.js
new  server/cache.js
new  server/telemetry.js
new  server/trust.js
new  server/legalpages.js
new  server/legal/content.js
new  server/share-store.sql
new  server/schema-alters.sql
new  server/schema-indexes.sql
new  server/migrations/README.md
new  server/tests/helpers/harness.mjs
new  server/tests/seams.test.mjs
new  server/tests/config.test.mjs
new  server/tests/account-delete.test.mjs
new  server/tests/fixtures/config-defaults.json
new  server/tests/fixtures/codes.json
edit server/worker.js
edit server/ai.js
edit server/schema.sql
edit server/wrangler.toml
edit .github/workflows/worker-deploy.yml
edit .github/workflows/server-tests.yml
```

**Instructions**

1. **`lib/*`.**
   - Move `json`, `fail`, `text` and `boundedText` into `lib/http.js`; `worker.js` re-exports `boundedText`. `fail(status, message, code)` omits `code` when it is not given.
   - `lib/crypto.js`: `sha256hex`, `hmacHex`, `b64url`.
   - `lib/codes.js`: `ALPHABET` (the `pair.js` alphabet), `randomCode(len)` by rejection sampling (drop bytes of 248 or more), `normaliseCode(raw, len)`.
   - `lib/owner.js` and `lib/limits.js`: as described in §3.1.
   - `lib/appfacts.js`:
     - `appStoreId(env, fetcher)` checks env `APPLE_APP_ID`, then the `app_store_id` fact, then the iTunes lookup `https://itunes.apple.com/lookup?bundleId=<APPLE_BUNDLE_ID>`, at most once an hour (fact `app_store_lookup_at`);
     - `teamId(env)` checks the `apple_team_id` fact, then env `APPLE_TEAM_ID`.
2. **`config.js`.** Follow D §2.1, with `DEFAULTS` copied from `docs/launch/config-defaults.json` and `_ranges`, `_public` and `_env` implemented exactly as that file describes.
   - Exports: `loadConfig(env, clock)` (memoised for 60 s), `flag`, `limit`, `accountLimits`, `killed`, `publicView`, `validate`, `DEFAULTS`, `RANGES`.
   - Route `GET /config`: `{version, ttl, flags, limits (public), messages, app, serverTime}`, with an ETag, 304 support and `max-age=60`.
3. **`account.js`.**
   - `LEGAL = {privacy: 1, terms: 3, aiConsent: 1, rules: 1, effective: '2026-10-01'}`.
   - `POST /account/me` returns `{userId, owner, termsVersion, aiConsent, rulesVersion, legal}`.
   - `POST /account/consent` clamps each version to `LEGAL`, treats `aiConsent: 0` as a withdrawal, and stamps the `*_at` columns.
   - `consentGate(env, cfg, id)` returns 428 `ai_consent_required` when `trust.aiConsentEnforced` is on and `ai_consent < LEGAL.aiConsent`. The flag is off by default.
4. **`apple.js` and `entitlement.js`.**
   - Move `accountToken`, `ownsIt`, `recordEnvironment`, `linkSubscription`, `askApple`, `appStoreToken` and `isPro` from `ai.js`, unchanged. `ai.js` re-exports them, so `ai.test.mjs` passes untouched.
   - Move `worker.js`'s `setSubscription` into `apple.js`.
   - `entitlement(env, accountOrId, {activate, fetcher})` is the legacy logic (see the §3.1 table), and `proGate` calls it with its own `fetcher`, so the fake fetch in `ai.test.mjs` still reaches `askApple`. Responses must not change.
5. **`router.js`.**
   - Build the table from `MODULES` in this order: config, account, share, sharepage, groups, moderation, invites, appstore, entitlement, referrals, licences, ambassadors, billing-owner, invitepage, configadmin, allowance, cache, telemetry, trust, legalpages.
   - Path patterns support literals, `:name`, `:name.json` and a trailing `*`.
   - Apply auth, size and body handling as in §3.1. `ctx` exposes `cfg = await loadConfig(env)`.
   - `web.js` is as in §3.1. The HTML 404 page is bilingual.
6. **`cron.js`.**
   - `SLOTS = {'17 3 * * *': 'maintenance', '47 3 * * *': 'telemetry', '17 4 * * *': 'billing'}`.
   - Tasks run in sequence, each in its own try/catch.
   - Own task: `DELETE FROM pair_attempts WHERE hour < now/3600 - 48`.
7. **`worker.js`.**
   - Apply the router order from §3.1.
   - `export default { fetch, scheduled }`.
   - `session()` adds `owner`.
   - `deleteAccount` runs the hooks in the §3.1 order.
   - The legacy `/account/subscription` case calls `apple.setSubscription`.
   - Add the consent gate to `/v1/chat/completions`, `/tts`, `/transcribe/chunk` and `POST /jobs`, for bearer sessions only.
   - In `/auth/device`, read `via` (up to 20 characters). If `invites.inviteBucket()` is non-null, use `hit(ipKey, 'device-invite', inviteDevicesPerHour)` and `hit('code:'+CODE, 'device-code', inviteDevicesPerCodeHour)` in place of the 5/h limit, and record `joined_via`.
8. **Stubs.** Each stub module in the files block exports `routes = []`, `cron = []`, `onAccountDelete`, and the §3.1 functions with their defaults. Its header comment names the owning package and the design sections.
9. **Schema.**
   - Append `docs/launch/schema/unified-tables.sql` verbatim to `schema.sql`, and add the 14 columns to `CREATE TABLE accounts`.
   - Copy `accounts-alters.sql` to `server/schema-alters.sql`, `accounts-indexes.sql` to `server/schema-indexes.sql`, and `share-store.sql` to `server/share-store.sql`.
   - `migrations/README.md` defines two file types: `NNNN-name.sql`, which is idempotent, and `NNNN-name.alter`, with one ALTER per line.
10. **`wrangler.toml`.**
    - `[triggers] crons` with the 3 slots.
    - `[[d1_databases]] binding = "SHARE_STORE"`, `database_name = "redpen-shares"`, `database_id = ""`.
    - `[[ratelimits]] name = "SHARE_RL"`, `namespace_id = "7301"`, `simple = { limit = 120, period = 60 }`.
    - `[vars]`: `APPLE_APP_ID = ""`, `APPLE_TEAM_ID = ""`, `TESTFLIGHT_URL = ""`, `LEGAL_SELLER = ""`.
    - Document `CI_KEY` in the secrets comment.
11. **`worker-deploy.yml`.**
    - Tests step: loop `node "$t"` over the glob.
    - Create or find `redpen-shares` and sed its id into `wrangler.toml`; apply `share-store.sql`.
    - After `schema.sql`, run every `schema-alters.sql` line with `|| true` and every `schema-indexes.sql` line with `|| echo ::warning`. Then apply `migrations/*.sql` and the lines of `migrations/*.alter`.
    - Ratelimit fallback: if the deploy fails on `ratelimits`, strip the block and deploy again.
    - `CI_KEY`: `printf 'vignette-ci:%s' "$CLOUDFLARE_API_TOKEN" | sha256sum | cut -c1-64 | tr -d '\n' | $W secret put CI_KEY`.
    - Optional input `apple_team_id`, which writes an `app_facts` row.
    - Post-deploy checks: `curl -sf $URL/config`; the AASA URL gives `::warning` until it returns 200.
12. **`server-tests.yml`.** Run every `server/tests/*.test.mjs` (report all, fail on any), then `npx --yes wrangler@4 deploy --dry-run --outdir /tmp/dist` inside `server/`.

**Tests**

- `harness.mjs` provides:
  - `makeEnv({vars, now, fetch})`, whose DB is `schema.sql` plus the alters, indexes and migrations;
  - `SHARE_STORE`;
  - a Map-backed `BLOBS`, a fake `AI`, a statement counter and `batch()`;
  - `call(env, method, path, {token, body, headers})` and `tokenFor(env, id)`.
- `seams.test.mjs` covers:
  - route collisions;
  - each auth mode, including 404 for owner and CI routes;
  - 411, 413 and HEAD handling;
  - the GET 404 page;
  - cron dispatch by slot;
  - hook order;
  - `owner` in the session;
  - `/account/me` and consent clamping;
  - the consent gate switched on and off;
  - `via` fallback to 5/h;
  - `ipKey` rotating daily, with the raw IP absent from every table;
  - `randomCode` staying in the alphabet over 10 000 draws;
  - the `fixtures/codes.json` vectors.
- `config.test.mjs` covers:
  - D §9.1 items for defaults, env fallback, merge, validation, public view, ETag/304 and the memo (with the clock injected);
  - writing `fixtures/config-defaults.json` from `DEFAULTS` and failing on drift.
- `account-delete.test.mjs`: every hook runs in order, within 50 statements. It is re-run at every later gate.

**Acceptance**

- Every old and new server test passes.
- The dry-run bundle succeeds.
- After the deploy (dispatched by an agent):
  - `GET /config` returns 200 with an ETag;
  - a device account can call `/account/me`;
  - the existing app flows are unchanged.

---

### W0a · P0.2 App core seams

**Goal.** Lifecycle, links, config, consent, owner flag and networking in one place, so that no W2 package edits `RedPenApp`, `AuthAPI` or `AccountStore`. Also fix the app-side launch blockers.

```files
new  ios/RedPen/Shared/Hooks/AppContext.swift
new  ios/RedPen/Shared/Hooks/AppHooks.swift
new  ios/RedPen/Shared/Hooks/AppEvents.swift
new  ios/RedPen/Shared/Hooks/ShareHooks.swift
new  ios/RedPen/Shared/Hooks/GroupHooks.swift
new  ios/RedPen/Shared/Hooks/BillingHooks.swift
new  ios/RedPen/Shared/Hooks/GlanceHooks.swift
new  ios/RedPen/Shared/Hooks/ConfigHooks.swift
new  ios/RedPen/Shared/Hooks/TelemetryHooks.swift
new  ios/RedPen/Shared/Hooks/TrustHooks.swift
new  ios/RedPen/Shared/Hooks/RootExtras.swift
new  ios/RedPen/Shared/Hooks/DeepLinkSheets.swift
new  ios/RedPen/Shared/DeepLink.swift
new  ios/RedPen/Shared/AppRouter.swift
new  ios/RedPen/Shared/OwnerGate.swift
new  ios/RedPen/Shared/RemoteConfig.swift
new  ios/RedPen/Shared/RemoteConfigStore.swift
new  ios/RedPen/Shared/ConfigBanner.swift
new  ios/RedPen/Shared/CloudGate.swift
new  ios/RedPen/Shared/LegalLinks.swift
new  ios/RedPen/Shared/VignetteHeaders.swift
new  ios/RedPen/Shared/ReportStore.swift
new  ios/RedPen/Shared/Billing/InviteCenter.swift
new  ios/RedPen/Models/ShareModels.swift
new  ios/RedPen/Models/ShareOrigin.swift
new  ios/RedPen/Persistence/ShareCenter.swift
new  ios/RedPen/Persistence/GroupCenter.swift
new  ios/RedPen/Persistence/StoreSubjectQuiz.swift
new  ios/RedPen/Features/Support/EducationNotice.swift
new  ios/RedPen/Features/Support/TrustRootSheets.swift
new  ios/RedPen/Features/Share/ShareLinkSheets.swift
new  ios/RedPen/Features/Groups/GroupLinkSheets.swift
new  ios/RedPen/Features/Groups/GroupsView.swift
new  ios/RedPen/Features/Account/InviteLinkSheets.swift
new  ios/RedPen/Features/Library/LibraryNotices.swift
new  ios/RedPen/Tests/DeepLinkTests.swift
new  ios/RedPen/Tests/RemoteConfigTests.swift
new  ios/RedPen/Tests/Suites/deeplink.suite
new  ios/RedPen/Tests/Suites/remoteconfig.suite
edit ios/RedPen/RedPenApp.swift
edit ios/RedPen/Shared/AuthAPI.swift
edit ios/RedPen/Shared/SyncAPI.swift
edit ios/RedPen/Models/Account.swift
edit ios/RedPen/Models/StudySet.swift
edit ios/RedPen/Persistence/AccountStore.swift
edit ios/RedPen/Shared/SubscriptionStore.swift
edit ios/RedPen/Shared/CloudJobCollector.swift
edit ios/RedPen/Shared/LLM/HostedLLMClient.swift
edit ios/RedPen/Shared/CloudTranscriber.swift
edit ios/RedPen/Shared/Voice/CloudVoice.swift
edit ios/RedPen/Shared/LLM/CloudJobs.swift
edit ios/RedPen/Shared/Coverage/CoverageCloudCheck.swift
edit ios/RedPen/Features/Library/LibraryView.swift
edit ios/RedPen/Features/Anki/DueTodayView.swift
edit ios/RedPen/Features/Paywall/PaywallView.swift
edit ios/RedPen/Features/Auth/SignInView.swift
```

**Instructions**

1. **Hooks, context, router and events** as in §3.2.
   - `AppEvents.swift` defines `enum AppEvent: String, CaseIterable` with exactly the §8.1 names, and `AppEvents.record` forwards to `TelemetryHooks.record`, which is a no-op.
2. **`RedPenApp`.**
   - A root `.task` calls `AppHooks.launched`.
   - A root `.onChange(of: phase)` calls `becameActive` and `enteredBackground`.
   - `.onChange(of: account.account?.id)` calls `signedIn`.
   - `.onOpenURL` and `.onContinueUserActivity` handle `NSUserActivityTypeBrowsingWeb`, `CSSearchableItemActionType` and `"com.cramdown.app.set"`, routing to `AppRouter`.
   - Add `.appRootExtras()`.
   - Change no existing branch, store construction or sync behaviour.
3. **`DeepLink`** as specified in §3.2, with `Tests/DeepLinkTests.swift`. The tests use `server/tests/fixtures/codes.json` (from P0.1) plus the cases from A §8.2, B §6.2 (routes) and C §8 (DeepLink).
4. **`RemoteConfig`** (the model, D §5): its built-ins mirror `config-defaults.json` flags and `_public` limits. It decodes tolerantly and provides rollout buckets, min/max build and banners.
   - `RemoteConfigStore` is minimal: built-ins only.
   - `RemoteConfigTests` check against `server/tests/fixtures/config-defaults.json`.
5. **Stubs** as in the §3.2 table. `OwnerGate` is complete: it is set from the session's `owner`, from `/account/me`, or from `PersonalBuild.isOn`.
6. **Models.**
   - `ShareModels.swift` holds A §4's DTOs, with field names exactly as `api-routes.md` and A §4 give them. `GroupDTO` gains `licence: LicenceStatus?`, where `LicenceStatus` is `{institution, until, seat}`.
   - `ShareOrigin` follows A §3.4.
   - `StudySet.shareOrigin` is added with its key and `decodeIfPresent`.
7. **Networking and accounts.**
   - `AuthAPI` changes as in §3.2, plus `me`, `consent` and `deviceAccount(claim:via:)`.
   - `Account.owner: Bool?` stays Optional, so sessions already in the keychain still decode.
   - `AccountStore.ensureServerSession(via:)` and `refreshMe()`.
   - `VignetteHeaders` goes on every request to the worker in the edited files.
8. **Consent seam.** Every cloud request path in HostedLLMClient, CloudTranscriber, CloudVoice, CloudJobs and CoverageCloudCheck starts with `try await CloudGate.shared.ensureConsent(for: …)`.
9. **Launch blockers.**
   - `SubscriptionStore.isPro` becomes `PersonalBuild.isOn || access.isPro`.
   - The paywall's Terms and Privacy go through `LegalLinks` (the Worker `/terms` and `/privacy`, with `?lang=`).
   - The `SignInView` footer reads "By continuing you agree to the Terms and Privacy Policy." Keep the `localSignIn` identifier.
   - `EducationNotice` holds the `EducationFootnote` view and `.simulatedPatientBanner()` (F §3).
10. **`LibraryView`.**
    - Consume `.due`, `.set`, `.quiz` and `.exam`: `.due` goes to `DueTodayView(startAt:)`; `.quiz` uses `store.subjectQuiz(matching:count:)`, and if that returns nil, opens Due Today with a notice; `.exam` opens Settings.
    - Add `.deepLinkSheets()` and `LibraryNotices()` at the top of the list.
    - `DueTodayView` gets `startAt: UUID? = nil`.
11. **`CloudJobCollector`.** The background task also awaits `AppHooks.backgroundRefresh()`. Schedule a refresh when jobs are pending or `AppHooks.wantsBackgroundRefresh` is true.

**Tests.** The `deeplink` and `remoteconfig` suites. The existing `account` suite must still compile, because `Account` changes.

**Acceptance**

- Every Swift suite passes.
- The app builds; `LocalSignInUITests` and the other UI tests pass.
- Screenshots are unchanged apart from the sign-in footer.
- The Playgrounds package made by `tools/make_swiftpm.py` (P0.3) compiles.
- A search of the App Store build finds no `isPro { true }`.

---

### W0a · P0.3 CI and tooling seams

**Goal.** Suites, previews and tool tests become data-driven, so packages add files instead of editing workflows.

```files
new  ios/RedPen/Tests/Suites/quality.suite
new  ios/RedPen/Tests/Suites/learning.suite
new  ios/RedPen/Tests/Suites/transcriber.suite
new  ios/RedPen/Tests/Suites/cloudtranscript.suite
new  ios/RedPen/Tests/Suites/ingest.suite
new  ios/RedPen/Tests/Suites/narrate.suite
new  ios/RedPen/Tests/Suites/figures.suite
new  ios/RedPen/Tests/Suites/docx.suite
new  ios/RedPen/Tests/Suites/coverage.suite
new  ios/RedPen/Tests/Suites/schedule.suite
new  ios/RedPen/Tests/Suites/slides.suite
new  ios/RedPen/Tests/Suites/account.suite
new  ios/RedPen/Tests/Suites/sync.suite
new  ios/RedPen/Tests/Suites/sources.suite
new  ios/RedPen/Tests/Suites/osce.suite
new  ios/RedPen/Tests/Suites/llm.suite
new  ios/RedPen/Tests/Suites/reading.suite
new  ios/RedPen/Tests/Suites/deck.suite
new  ios/RedPen/Tests/Suites/occlusion.suite
new  ios/RedPen/Tests/Suites/phrases.suite
new  ios/RedPen/Tests/Suites/modeconversion.suite
new  ios/RedPen/Tests/Suites/answers.suite
new  ios/RedPen/Tests/Suites/differential.suite
new  ios/previews/README.md
new  .github/workflows/tools-tests.yml
new  tools/make_swiftpm.py
new  tools/tests/test_make_swiftpm.py
edit .github/workflows/swift-tests.yml
edit .github/workflows/ios-preview.yml
edit .github/workflows/app-build.yml
```

**Instructions**

1. **Suite files.** Generate the 23 `.suite` files by script from the current `swift-tests.yml`, with the same test file and sources, expanding `$S`, `$M` and `$F`.
   - Replace the calls with a loop over `Suites/*.suite` that uses the same `swiftc -O … main.swift` recipe and the same log format.
   - Keep the docx fixture step, the failure check and the log push.
   - Add the triggers `ios/RedPen/Tests/Suites/**` and `server/tests/fixtures/**`.
2. **Previews.** `ios-preview.yml` shoots the existing screens plus every non-`#` line of `ios/previews/*.txt`.
3. **App build.** `app-build.yml` also runs on pushes to `growth/**`.
4. **Tool tests.** `tools-tests.yml` runs `python3 tools/tests/test_*.py` and `node tools/asc/tests/*.test.mjs` when they exist, on changes under `tools/`.
5. **Playgrounds script.** `tools/make_swiftpm.py` is a byte-for-byte copy of `…/scratchpad/make_swiftpm.py`.
   - `test_make_swiftpm.py` builds a package from a temporary copy of `ios/RedPen` and checks: `Package.swift` for iOS 26, `AppModule` and `.copy("Samples")`; the Gemma stub; the exclusions; and the personal marker, present only for `.personal` bundles.
   - From now on the orchestrator runs the repo copy, with the same arguments. Later edits go to the repo copy only.

**Acceptance**

- On the same commit, the new swift-tests run lists the same 23 suites with the same pass counts as the old one.
- The preview run produces the same screenshots.
- `tools-tests` is green.

---

### W0b · P0.4 Screen seams (after P0.2)

**Goal.** Put every cross-feature hook into the shared screens once: report item, assist slot, events, account and settings slots, owner hub and preview names. Every hook stays invisible until its package lands.

```files
new  ios/RedPen/Shared/Hooks/StudyItemRef.swift
new  ios/RedPen/Features/Support/ReportErrorSheet.swift
new  ios/RedPen/Features/Share/ModerationReportSheet.swift
new  ios/RedPen/Features/Assist/AssistSlot.swift
new  ios/RedPen/Features/Auth/SocialAccountSection.swift
new  ios/RedPen/Features/Auth/BillingAccountSection.swift
new  ios/RedPen/Features/Auth/TrustAccountSection.swift
new  ios/RedPen/Features/Owner/OwnerHubView.swift
new  ios/RedPen/Features/Owner/OwnerBillingTools.swift
new  ios/RedPen/Features/Owner/OwnerConfigConsole.swift
new  ios/RedPen/Features/Owner/AssistSelfTestView.swift
new  ios/RedPen/Features/Owner/OwnerInsightsView.swift
new  ios/RedPen/Features/Owner/ReportsReviewView.swift
new  ios/RedPen/Features/Support/AboutLegalPage.swift
new  ios/RedPen/Features/Support/PrivacyChoicesRow.swift
new  ios/RedPen/Features/Support/AppLanguageRow.swift
new  ios/RedPen/Features/Support/CloudAIRow.swift
new  ios/RedPen/Features/Support/CloudAllowanceSection.swift
new  ios/RedPen/Features/Share/SharePreviews.swift
new  ios/RedPen/Features/Groups/GroupPreviews.swift
new  ios/RedPen/Features/Paywall/BillingPreviews.swift
new  ios/RedPen/Features/Support/ConfigPreviews.swift
new  ios/RedPen/Features/Assist/AssistPreviews.swift
new  ios/RedPen/Features/Support/TelemetryPreviews.swift
new  ios/RedPen/Features/Support/TrustPreviews.swift
new  ios/RedPen/Shared/Glance/GlancePreviews.swift
new  ios/RedPen/Tests/StudyItemRefTests.swift
new  ios/RedPen/Tests/Suites/studyitem.suite
edit ios/RedPen/Shared/Theme.swift
edit ios/RedPen/Features/MCQ/MCQQuizView.swift
edit ios/RedPen/Features/MCQ/MCQSummaryView.swift
edit ios/RedPen/Features/Anki/AnkiReviewView.swift
edit ios/RedPen/Features/Anki/AnkiCardFace.swift
edit ios/RedPen/Features/Anki/DueTodayView.swift
edit ios/RedPen/Features/QA/QACardsView.swift
edit ios/RedPen/Features/OSCE/OsceReviewView.swift
edit ios/RedPen/Features/Book/BookReaderView.swift
edit ios/RedPen/Features/Narrate/NarrateReviewView.swift
edit ios/RedPen/Features/Cases/CaseChatView.swift
edit ios/RedPen/Features/Reasoning/ClueCaseView.swift
edit ios/RedPen/Features/Voice/CommuteModeView.swift
edit ios/RedPen/Features/Voice/SpokenStationView.swift
edit ios/RedPen/Features/Notes/IdeasView.swift
edit ios/RedPen/Features/Analytics/AnalyticsView.swift
edit ios/RedPen/Features/Support/AccuracyCheckSheet.swift
edit ios/RedPen/Features/Library/NewSetView.swift
edit ios/RedPen/Features/Library/MCQGenerateForm.swift
edit ios/RedPen/Features/Library/LectureWriterSection.swift
edit ios/RedPen/Features/OSCE/OsceGenerateSection.swift
edit ios/RedPen/Features/Paywall/PaywallView.swift
edit ios/RedPen/Features/Account/RecordingTermsView.swift
edit ios/RedPen/Persistence/SyncEngine.swift
edit ios/RedPen/Features/Auth/AccountView.swift
edit ios/RedPen/Features/Support/SupportCenter.swift
edit ios/RedPen/Features/Support/ModelSettingsView.swift
edit ios/RedPen/Shared/PreviewExtras.swift
```

**Instructions**

1. **`StudyItemRef` and adapters** as in §3.2. `shareCode` comes from `set.shareOrigin?.code`.
2. **`Theme.swift`.**
   - Both `studyMoreMenu` overloads gain `report: (() -> StudyItemRef?)? = nil`, so existing calls still compile.
   - The menu item "Report an error" (`exclamationmark.bubble`, identifier `reportError`) shows only when `ReportErrorSheet.isAvailable` is true and `report?()` is non-nil.
   - The modifier owns `@State var reporting: StudyItemRef?` and `.sheet(item:) { ReportErrorSheet(item: $0) }`.
3. **Study screens.**
   - Pass `report:` for the item currently on screen in MCQQuizView, AnkiReviewView, QACardsView, OsceReviewView, BookReaderView and NarrateReviewView.
   - CaseChatView and ClueCaseView get the item and its sheet in their own toolbars.
   - MCQSummaryView rows and DueTodayView cards get a context-menu item.
   - Place `AssistSlot(item:phase:)`:
     - under the MCQ stem (`.beforeAnswer`) and under the explanation (`.afterAnswer`);
     - on the AnkiCardFace front and back;
     - on the QACardsView back.
4. **`AppEvents` calls.** One line at each completion point:

   | Event | Where |
   |---|---|
   | `quiz_completed`, `questions_answered` | MCQSummary |
   | `cards_reviewed` | each rating in AnkiReview |
   | `set_created` | NewSet |
   | `generation_started`, `generation_succeeded`, `generation_failed` | the three generate forms |
   | `case_completed` | CaseChat |
   | `osce_station_completed` | OsceReview |
   | `narrate_session` | NarrateReview |
   | `voice_session` | Commute, SpokenStation |
   | `ideas_opened` | Ideas |
   | `analytics_opened` | Analytics |
   | `accuracy_check_run` | AccuracyCheckSheet |
   | `paywall_shown` | Paywall |
   | `sync_conflict` | SyncEngine, when `copiesKept` grows |
   | `onboarding_done` | RecordingTerms accept |
5. **Account and settings.**
   - `AccountView` gets the three sections. Move the current Subscription section verbatim into `BillingAccountSection`, with identical behaviour. The delete footer adds "Your error reports are kept without your name or note."
   - `SupportCenter`:
     - `SupportPage` gains `.about` (AboutLegalPage) and `.owner` (OwnerHubView, listed only when `OwnerGate.shared.isOwner || PersonalBuild.isOn`);
     - `SettingsPage` gains a "Privacy & language" section of the three rows, shown only if any row `isAvailable`;
     - the FAQ gains F §3's three questions ("Is this medical advice?", "Where does my lecture go when I use cloud AI?", "How accurate is it?").
   - `ModelSettingsView` gets `CloudAllowanceSection()` after the Vignette Cloud section.
   - `OwnerHubView` is complete: rows for the five tools, each shown when its `isAvailable` is true.
6. **`PreviewExtras`.** Register the §3.2 names and route each to its `*Previews` stub.

**Acceptance**

- The app builds and every UI test passes.
- With every `isAvailable` false, screenshots match the W0a baseline.
- The `studyitem` suite passes.

---

### W1 · P1.1 Shares and moderation (server)

**Goal.** Share a set as a link, public pages and AASA, the code lookup, the invite bucket, moderation, and the name rules on both server and app.

**Design:** A §2, §3.1, §3.6, §4.2, §4.4, §4.5, §5, §7 and §8.1 (share, moderation, sharepage, names).

```files
fill server/share.js
fill server/storage.js
fill server/sharepage.js
fill server/names.js
fill server/invites.js
fill server/moderation.js
new  server/assets/og.js
new  ios/RedPen/Shared/NameRules.swift
new  ios/RedPen/Tests/NameRulesTests.swift
new  ios/RedPen/Tests/Suites/namerules.suite
new  server/tests/share.test.mjs
new  server/tests/moderation.test.mjs
new  server/tests/sharepage.test.mjs
new  server/tests/names.test.mjs
new  server/tests/fixtures/name-rules.json
```

**Instructions (overrides of design A)**

1. **Routes** (see `api-routes.md`): add `POST /codes/lookup`, which returns `{type: 'share' | 'group' | 'admin', code}` and counts wrong codes with `hit(ipKey, 'code-lookup', wrongShareCodesPerHour)`. Drop `/shares/terms`.
2. **Consent.** Publishing requires `rules_version >= LEGAL.rules`, otherwise 428 `rules_required`. Use the statuses and codes from §3.1, never 403 or 404.
3. **Moderation.** The table is `moderation_reports`. Routes are `/moderation/report` (session or public), `/blocks/*` and `/owner/moderation/*`.
   - Auto-suspend at `autoSuspendReporters` distinct accounts.
   - Export `recordModeration` and `blockedIds`.
4. **`inviteBucket`.** Returns `'share'` for a live share code and `'group'` for an open join code or any admin code of a live group.
5. **AASA.** Paths `/s/*`, `/j/*` and `/r/*`, with `appIDs` of `<teamId(env)>.com.cramdown.app`. It is 404 until the team id is known.
   - Pages use `web.page`, show the Smart App Banner only when `appStoreId()` is known, and otherwise show "Coming soon" plus `TESTFLIGHT_URL`. They never show prices.
6. **Storage.**
   - Use the `SHARE_STORE` D1 database for bytes, and switch to R2 automatically when `BLOBS` exists.
   - Limits and flags come from config (`share.links`, `share.aiScreen`).
7. **Deletion hooks.**
   - `share.onAccountDelete`: shares, their storage, and marking their `group_sets` rows `removed` with a rev bump.
   - `moderation.onAccountDelete`: blocks in both directions, and `reporter_id` set to NULL.
8. **Name rules.** Write `NameRules.swift` as the Swift twin of `names.js` (A §3.6), using the same `fixtures/name-rules.json`. It covers Arabic normalisation and the Egyptian-colloquial blocklist.

**Tests.** A §8.1 share, moderation, sharepage and names, adapted to the new routes and statuses, plus:
- `/codes/lookup`, including its rate limit;
- `inviteBucket`;
- auto-suspend through `recordModeration`;
- `/r/*` present in the AASA;
- `NameRulesTests` with the shared fixture.

**Acceptance.** Tests green. Every route stays within the statement budget. After deploy:
- `/s/UNKNOWN` returns 404 HTML;
- `/robots.txt` disallows `/s/`, `/j/`, `/r/` and `/a/`;
- the AASA returns 404, which is expected until the team id is known.

---

### W1 · P1.2 Classes, groups and leaderboards (server)

**Goal.** Classes and study groups: join by link or code, lecturers push sets that flow to members, opt-in weekly leaderboards, and the licence seat hook.

**Design:** A §4.3, §4.6 (group part), §5.2–5.3, §8.1 (groups).

```files
fill server/groups.js
new  server/tests/groups.test.mjs
```

**Instructions (overrides of design A)**

1. **Join.** `/groups/join` requires current rules (428), counts wrong codes with `hit(ipKey, 'groupcode', wrongGroupCodesPerHour)` and refunds the count on success.
   - After inserting the membership, call `licences.onGroupJoin`. Add `licence` to `GroupDTO` through `licenceForMember`.
   - Leave, remove and delete call `onGroupLeave`.
2. **Class settings.** `/groups/update` accepts `membersShareGenerated`, owner only.
   - Export `memberRole`, and `canShareGenerated`, which is true for owner and admin, and for members when `members_share_generated = 1`.
3. **Leaderboards** exclude `moderation.blockedIds()` in both directions. Display names go through `names.checkName('display', …)`.
4. **Flags.** `share.classes` and `share.leaderboards` return 503 `feature_off` when off.
   - Stats are purged in a `maintenance` cron task as well as lazily, one call in 50.
5. **Errors** as in §3.1.
   - `onAccountDelete` covers memberships, owned groups (transfer to the oldest admin, otherwise delete) and `weekly_stats`.

**Tests.** A §8.1 groups, plus:
- licence hook calls, through a fake `licences` module injected with `setLicencesForTests`;
- `members_share_generated`;
- `memberRole` and `canShareGenerated`;
- `/j/:code.json`.

**Acceptance.** Tests green; the leaderboard response contains no account ids.

---

### W1 · P1.3 Apple billing core (server)

**Goal.** Verify Apple's signed data properly (the G3 chain), and keep one entitlement answer that every route and every device reads: subscription, exam pass, class access or grant.

**Design:** B §0 (blockers 2, 3 and 5), §1, §2.1, §2.2 (apple\_\* tables), §2.4, §3.0–3.4 (JWS, notifications, status, subscription, owner notification log and test notification) and §6.1 (x509, appstore, billing).

```files
new  server/x509.js
new  server/apple-root.js
fill server/appstore.js
fill server/entitlement.js
edit server/apple.js
new  server/tests/x509.test.mjs
new  server/tests/appstore.test.mjs
new  server/tests/billing.test.mjs
new  server/tests/fixtures/AppleRootCA-G3.cer
new  server/tests/fixtures/AppleWWDRCAG6.cer
new  server/tests/fixtures/billing-vectors.json
```

**Instructions (overrides of design B)**

1. **`entitlement()`** returns `{pro, paying, until, source, sources, banked, owner, features, walletKey}`.
   - Sources, in order: owner > subscription > pass > licence (`licences.activeLicenceFor`) > referral, welcome or gift (`pro_grants`).
   - `paying` means an active Production subscription or pass, or a licence with `paid_models = 1`. For a licence, `walletKey` is `licence:<id>`.
   - `features` is `{referrals, licences, examPass}`, taken from the flags.
2. **`/account/status`** lives in `entitlement.js`. It sets `last_seen_day` and `account_token`, and activates the oldest banked grant atomically, as in B's SQL.
3. **`apple.js`.**
   - `askApple` returns `null` when the ASC keys are missing.
   - `linkSubscription` and signed transactions follow the §2.4 ownership rules and return 409 `bought_by_other_account` or `linked_elsewhere`.
   - `setSubscription` accepts `signedTransactions` and `signedRenewalInfo`.
4. **`/apple/notifications`.**
   - The x5c chain is exactly 3 certificates, and the pinned G3 root is compared byte for byte.
   - OID, date and ES256 checks apply.
   - A request that fails verification gets 401 with **zero D1 writes**.
   - Notifications are de-duplicated by UUID, and the `signedDate` ordering guard applies.
   - The first verified Production notification stores `app_store_id` through `appfacts.setFact`.
5. **Owner routes.** `/owner/billing/notifications` and `/owner/billing/test-notification` (which needs the ASC keys; otherwise 410 `asc_keys_missing`).
   - The `billing` cron prunes notifications older than 180 days.
   - `onAccountDelete` nulls the account ids in the three `apple_*` tables.
6. **Product ids:** `com.redpen.pro.monthly`, `com.redpen.pro.yearly` and the new non-renewing `com.redpen.pass.exam3m` (92 days, stacked).

**Tests.** B §6.1 x509, appstore (a fake chain built with `openssl`) and billing, minus referrals and groups. The two certificate fixtures are Apple's public files from apple.com/certificateauthority; copies are already downloaded as `…/scratchpad/AppleRootCA-G3.cer` and `…/scratchpad/wwdrg6.cer`. Check the G3 SHA-256 against B §3.1 before committing. Also:
- licence and grant precedence, using the fake `activeLicenceFor`;
- `askApple` without keys leaves `verified_until` unchanged.

**Acceptance.** Tests green. A malformed POST to `/apple/notifications` returns 401 and writes no rows. `proGate` behaves as before for existing accounts.

---

### W1 · P1.4 Referrals, class access, ambassadors, owner billing (server)

**Goal.** Referral credits with abuse limits, owner-only class access (licences), ambassadors with their offer-code queue, and the owner's billing tools.

**Design:** B §3.3 (referrals, `/r/`, owner routes, `/a/`), §3.4, §7, and §6.1 (referrals, groups → licences); A §4.5 page style.

```files
fill server/referrals.js
fill server/licences.js
fill server/ambassadors.js
fill server/billing-owner.js
fill server/invitepage.js
new  server/tests/referrals.test.mjs
new  server/tests/licences.test.mjs
new  server/tests/billing-owner.test.mjs
```

**Instructions (overrides of design B)**

1. **Licences** (R1):
   - `/owner/licences/create {joinCode, name, institution?, seats ≤ licenceMaxSeats, endsAt ≤ now + licenceMaxDays, paidModels, monthlyBudgetUsd}` looks up the class by its join code. There is one licence per class.
   - Also `/owner/licences/list`, `/update` (seats, end date, disable), `/seats` (hashed member ids, as in B) and `/remove-seat`.
   - `onGroupJoin` does the seat allocation in a single statement, with B's `INSERT … SELECT … WHERE count < seats` applied to `licence_seats`.
   - Implement `onGroupLeave`, `licenceForMember` and `activeLicenceFor`.
   - There is no public join route and no `/g/` page.
2. **Referrals.** `/referrals/me` and `/referrals/claim`, with the AppTransaction verified through `appstore.verifyAppTransaction`, injectable in tests. `settleReferrals` runs in the `billing` cron and lazily.
   - Limits come from config; the flag is `billing.referrals`.
   - Rewards and welcome days are `pro_grants`, and they get free models only.
3. **Ambassadors.** `/owner/ambassadors/upsert` sets `offer_status = 'pending'` when asked to create the offer automatically. `/owner/ambassadors/stats` is as in B.
   - `/ci/ambassadors/pending` and `/ci/ambassadors/result` form the queue for P3.2's App Store Connect automation.
4. **Owner billing.** `/owner/billing/summary` and `/owner/grants/gift` (at most `giftsPerMonth`).
   - The `billing` cron expires grants and refreshes `appStoreId`.
5. **Pages.** `GET /r/:code` and `GET /a/:slug`, in English and Arabic, never naming the referrer and never showing a price.
   - `/a/` links to `https://apps.apple.com/redeem?ctx=offercodes&id=<appStoreId>&code=<CODE>` only once the App Store id is known.
6. **Deletion hooks** cover `licence_seats`, `pro_grants` and referrals, as in B §2.4.

**Tests.** B §6.1 referrals, plus:
- licences: seat caps (3 joins into 2 seats leaves the third without Pro but still a member), ended and disabled licences, `paid_models = 0` giving no wallet, owner-only creation (404 for others);
- the ambassador queue;
- summary shape and gift caps;
- the pages, including `dir="rtl"` for Arabic.

**Acceptance.** Tests green. `onGroupJoin` is atomic when two joins race for the last seat: exactly one gets it.

---

### W1 · P1.5 AI money and limits, config admin, allowance (server)

**Goal.** Per-user caps and fair shares of the free models, server-enforced kill switches and limits, owner config editing, and B's paying-only wallet, all inside the one package that owns `ai.js`.

**Design:** D §2.1 (owner config), §2.2 (routes, renamed), §2.3, §8 and §9.1 (config admin, usage); B §3.1 (`ai.js` bullets).

```files
edit server/ai.js
edit server/tts.js
fill server/configadmin.js
fill server/allowance.js
edit server/tests/ai.test.mjs
edit server/tests/tts.test.mjs
new  server/tests/configadmin.test.mjs
new  server/tests/allowance.test.mjs
```

**Instructions**

1. **`POST /owner/config`** handles `get`, `set` and `rollback`.
   - `set` uses `expectVersion` and returns 409 on a mismatch.
   - History is kept to the newest 50 versions.
   - Owner writes are limited to 30 per hour through `hit`.
2. **Allowance and owner usage.**
   - `/account/allowance` returns the D "usage" shape, never in dollars.
   - `/owner/cloud-usage` and `/owner/account-caps` write `accounts.caps`.
3. **`ai.js`, from D.**
   - The micro path takes `task` of `hint`, `reword` or `explain`, and its behaviour depends on the flag `assist.cloudFallback`.
   - Fair shares of the free models, through `gfree:`/`wai:` counters.
   - Daily and global USD keys in `ai_cost`, and `budget()` excludes the `d:%` and `global` rows.
   - Limits and kill switches come from config.
   - Add `gate(env, id)`, which returns `{refused, account, ent}`. `proGate` keeps its signature.
4. **`ai.js`, from B.**
   - `wallet()` returns `null` unless `entitlement().paying`.
   - A licence wallet uses the key `licence:<id>`, capped at `monthly_budget_usd`.
   - `budget()` counts subscribers as `paid_until > now`, with the old query as the fallback.
5. **`tts.js`.** `killed('tts')` and the `ttsDaily` limit from config.

**Tests.** D §9.1 usage items, the configadmin items and the `ai.test.mjs`/`tts.test.mjs` additions, plus B's wallet and budget assertions:
- sandbox, referral and licence without paid models all give no wallet;
- `budget` counts `paid_until`.

**Acceptance.** Every existing test in `ai.test.mjs` and `tts.test.mjs` still passes. The micro path never calls a paid source; the fake fetch records the URLs to prove it.

---

### W1 · P1.6 Generation cache (server)

**Goal.** Serve a set already generated from the same lecture (the same account, or the same class when enabled) instead of generating it again.

**Design:** D §2.4, §2.5, §4.2, §4.3 and §9.1 (cache, jobs).

```files
edit server/jobs.js
fill server/cache.js
edit server/tests/jobs.test.mjs
new  server/tests/cache.test.mjs
new  server/tests/fixtures/fingerprint-vectors.json
```

**Instructions (overrides of design D)**

1. **Class scope.** Membership is `groups.memberRole() !== null`. Only `canShareGenerated()` may contribute. The flags are `cache.account` and `cache.class`; `cache.class` is off at launch.
2. **Server-side keys.** Cache keys always come from the checked spec on the server, never from values the client supplies.
3. **Clean-up.** The `maintenance` cron deletes at most 50 expired rows per run. `onAccountDelete` removes the account's rows and their R2 objects.

**Tests.** D §9.1 cache and jobs items. The fixture vectors are shared with P2.7's Swift tests.

**Acceptance.** Tests green. The poisoning test passes: a client-supplied `sourceHash` is ignored.

---

### W1 · P1.7 Telemetry (server)

**Goal.** Opt-in, anonymous crash, hang, performance and usage counts on the Worker, with owner insights and symbolication in CI.

**Design:** E §1, §2, §6 and §8 (telemetry).

```files
fill server/telemetry.js
new  server/tests/telemetry.test.mjs
new  .github/workflows/crash-symbols.yml
new  .github/workflows/insights.yml
```

**Instructions (overrides of design E)**

1. **Routes.**
   - `/telemetry/diag` and `/telemetry/usage` are public and ignore any Authorization header.
   - `/owner/insights` and `/owner/diag/status` are owner routes.
   - `/ci/diag/pending` and `/ci/diag/symbols` use `CI_KEY`.
2. **Kill switches** are the flags `telemetry.crash` and `telemetry.usage`, with env `TELEMETRY=off` as the fallback. The daily row cap is `telemetryDailyRows`.
3. **`USAGE_EVENTS`** is the §8.1 list with its caps.
   - The parity test reads `ios/RedPen/Shared/Hooks/AppEvents.swift` for the names.
   - It checks caps against `Shared/Telemetry/UsageEvent.swift` only when that file exists (P2.8 adds it).
4. **Cron.** The `telemetry` slot runs the roll-ups and retention (E §2.5). Pruning `pair_attempts` belongs to W0's maintenance task.
5. **Crash symbols.** `crash-symbols.yml` derives `CI_KEY` from `CLOUDFLARE_API_TOKEN`, as in R8.

**Tests.** E §8 items 1–15, using the renamed routes.

**Acceptance.** Tests green. No telemetry table has an account or IP column.

---

### W1 · P1.8 Trust, legal pages, accuracy page (server)

**Goal.** Item error reports with an owner review queue, a support contact, the privacy, terms, medical and accuracy pages, and benchmark results published from CI.

**Design:** F §1, §2 (except `/account/me` and `/account/consent`, which are W0's), §6 and §7 (server, bench).

```files
fill server/trust.js
fill server/legalpages.js
fill server/legal/content.js
new  server/bench/summary.mjs
new  server/bench/publish.mjs
new  server/tests/trust.test.mjs
new  server/tests/legalpages.test.mjs
edit server/tests/bench.test.mjs
edit .github/workflows/accuracy-bench.yml
edit .github/workflows/checker-bench.yml
```

**Instructions (overrides of design F)**

1. **Routes.**
   - Reports: `/reports`, `/reports/mine`, and `/owner/reports/list`, `/update` and `/stats`.
   - Support: `/support/message`, the `POST /support` form, and `/owner/support/*`.
   - Benchmarks: `/ci/bench/publish`, authenticated with `CI_KEY` or `OWNER_KEY` (R8).
   - Pages: `/privacy`, `/terms`, `/medical`, `/support`, `/accuracy`, `/accuracy.json` and `/legal.json`, all built with `web.page`.
2. **Report fields.** `error_reports.share_code` (R11). An `offensive` report that carries `shareCode` calls `moderation.recordModeration(env, {targetType: 'share', targetRef: shareCode, reason: 'abuse', …})`.
3. **Legal content.**
   - `LEGAL` versions come from `account.js`.
   - `{{PROCESSORS}}` is built from `env`, as in F.
   - The legal texts in `content.js` must match `docs/launch/privacy-and-terms-draft.md` from the Docs phase; P6.1 reconciles them.
   - The flag is `trust.reports`.
4. **Benchmark publishing.** The workflows publish only when there are at least 100 results.
   - They send the `OWNER_KEY` they already compute, so no new secret is needed.
   - The server recomputes the Wilson intervals and the verdict itself.
5. **Cron and deletion.** Purge runs in the `maintenance` slot. `onAccountDelete` is `forgetTrustData`.

**Tests.** F §7 server items (trust, web, bench), using the renamed routes.

**Acceptance.** Tests green. After deploy:
- `/privacy?lang=ar` returns `dir="rtl"`;
- `/accuracy` renders with no script;
- `/legal.json` versions equal `LEGAL`.

### W1 gate

1. `account-delete.test.mjs` passes with every real hook, within 50 statements.
2. The whole glob is green.
3. An agent dispatches `worker-deploy.yml`.
4. Smoke checks with `curl`:
   - `/config`, `/privacy`, `/terms`, `/support`, `/accuracy`;
   - `POST /apple/notifications` with garbage returns 401;
   - `POST /telemetry/usage {}` returns 400;
   - `POST /codes/lookup` with a random code returns 400 `bad_code`.

---

### W2 · P2.1 Share links (app)

**Goal.** Share any set as a link; open or paste it on another device, add it to the library and receive the publisher's updates.

**Design:** A §1 (A1), §3.2–3.4, §6 (share parts) and §8.2 (ShareTests, SyncTests).

```files
new  ios/RedPen/Shared/StableIDs.swift
new  ios/RedPen/Shared/SharePacking.swift
new  ios/RedPen/Shared/ShareMerge.swift
new  ios/RedPen/Shared/ShareImages.swift
new  ios/RedPen/Shared/ShareAPI.swift
new  ios/RedPen/Features/Share/ShareSetSheet.swift
new  ios/RedPen/Features/Share/SharedSetPreview.swift
new  ios/RedPen/Features/Share/OpenLinkView.swift
new  ios/RedPen/Features/Share/CommunityRulesSheet.swift
new  ios/RedPen/Features/Share/BlockedPeopleView.swift
new  ios/RedPen/Features/Share/MySharedLinksView.swift
fill ios/RedPen/Persistence/ShareCenter.swift
fill ios/RedPen/Shared/Hooks/ShareHooks.swift
fill ios/RedPen/Features/Share/ShareLinkSheets.swift
fill ios/RedPen/Features/Share/ModerationReportSheet.swift
fill ios/RedPen/Features/Share/SharePreviews.swift
fill ios/RedPen/Features/Auth/SocialAccountSection.swift
edit ios/RedPen/Persistence/Store.swift
edit ios/RedPen/Features/Library/LibraryRows.swift
edit ios/RedPen/Features/Library/LibraryView.swift
new  ios/RedPen/Tests/ShareTests.swift
new  ios/RedPen/Tests/Suites/share.suite
edit ios/RedPen/Tests/SyncTests.swift
edit ios/RedPen/Tests/Suites/sync.suite
new  ios/UITests/ShareUITests.swift
new  ios/previews/share.txt
```

**Instructions (overrides of design A)**

1. **Links.** There is no `ShareLinks.swift` and no `onOpenURL` here: `DeepLink` and `AppRouter` handle links.
   - `ShareLinkSheets` consumes `.share` and `.code`. It resolves a bare code through `/codes/lookup` and re-routes group codes to `.join`.
   - Every link opens `SharedSetPreview`; nothing is imported without "Add to library".
2. **Provenance.** Use `StudySet.shareOrigin` (R11). `ShareCenter` persists `Documents/redpen-shares.json` and exposes `installId`, a random UUID.
3. **Moderation and people.**
   - The rules sheet posts `AuthAPI.consent(rules:)`.
   - Reports use `ModerationReportSheet` (`/moderation/report`).
   - `BlockedPeopleView` and `MySharedLinksView` (list and revoke) are reached from `SocialAccountSection`.
4. **Library.**
   - Row menus:
     - own sets: "Share link…", "Update shared link", and "Add to class…" (`GroupCenter.shared.classesICanShareTo`, hidden when empty);
     - imported sets: "Share original link" and "Report";
     - badges: the provenance caption and "Update available".
   - The toolbar adds "Classes & groups", which opens `GroupsView`. Show it only when `GroupCenter.isAvailable` (P2.2 flips it).
   - The empty library shows a `PasteButton` card.
5. **Store.** `Store.importShared(_:)` and `folder(named:)`.
   - `ShareHooks.becameActive` runs `checkUpdates`, throttled to once every 6 h.
   - Packing, image recompression, hashing and merging run off the main actor.
6. **Events and availability.** Record `share_link_created` and `set_imported`. Flip `ShareCenter.isAvailable` when done.

**Tests.** A §8.2 ShareTests (parsing is already covered by DeepLinkTests) and the SyncTests tombstone case. `ShareUITests` launches with `-uiPreviewScreen share-preview`, taps "Add to library" and sees the row.

**Acceptance**

- Suites, build and UI tests green.
- Previews include `share-preview`.
- The Playgrounds build compiles.
- Sharing and importing a sample set against the deployed worker works end to end, run by an agent in the simulator.

---

### W2 · P2.2 Classes, groups and leaderboards (app)

**Goal.** Classes and study groups in the app: create, join, lecturer controls, auto-imported class sets, update notifications and opt-in leaderboards.

**Design:** A §1 (A2, A3), §3.5, §6 (group parts) and §8.2 (GroupTests).

```files
new  ios/RedPen/Features/Groups/CreateGroupView.swift
new  ios/RedPen/Features/Groups/GroupDetailView.swift
new  ios/RedPen/Features/Groups/LeaderboardView.swift
new  ios/RedPen/Features/Groups/JoinGroupView.swift
new  ios/RedPen/Features/Groups/GroupNotifications.swift
new  ios/RedPen/Shared/WeeklyStats.swift
new  ios/RedPen/Shared/GroupFeedPlan.swift
new  ios/RedPen/Shared/GroupAPI.swift
fill ios/RedPen/Persistence/GroupCenter.swift
fill ios/RedPen/Shared/Hooks/GroupHooks.swift
fill ios/RedPen/Features/Groups/GroupsView.swift
fill ios/RedPen/Features/Groups/GroupLinkSheets.swift
fill ios/RedPen/Features/Groups/GroupPreviews.swift
new  ios/RedPen/Tests/GroupTests.swift
new  ios/RedPen/Tests/Suites/groups.suite
new  ios/UITests/GroupsUITests.swift
new  ios/previews/groups.txt
```

**Instructions**

1. **Joining.**
   - `JoinGroupView` is a confirmation sheet. It calls `account.ensureServerSession(via: code)`, asks for rules consent if the server returns 428, then joins.
   - It shows the licence result: "Class access from ‹institution›: Pro until ‹date›", or "Class access seats are full — you still get the class sets".
2. **`GroupHooks`.**
   - `becameActive` runs `pollFeed` (not for local-only sessions) and `pushStats` (only when opted in to some leaderboard).
   - `backgroundRefresh` runs `pollFeed` and posts a local notification through `AppNotifications.notifyGroupUpdate`, defined as an extension in `GroupNotifications.swift`.
   - `wantsBackgroundRefresh` is true when the user is in any group.
3. **Screens.**
   - `GroupDetailView` has owner and admin controls: rotate the code, close joining, the co-lecturer link, "Let members share generated sets" (classes), and delete.
   - Adding a set uses `ShareCenter.shared.publish` and then `/groups/sets/add`.
   - `LeaderboardView` is opt-in, validates names with `NameRules`, offers "Hide me", and has Report (through `ModerationReportSheet`) and Block on each row.
4. **Events and rules.** Record `class_joined`. There are no prizes, challenges or "win" language (5.3, and the owner's no-duels rule).

**Tests.** A §8.2 GroupTests (WeeklyStats boundaries and feed plan). `GroupsUITests` uses the `group-detail` preview.

**Acceptance.** Suites, build, UI tests and previews (`group-detail`, `leaderboard`) green. A second simulator account joins a class created by the first (agent-run end-to-end check).

---

### W2 · P2.3 Paywall and billing (app)

**Goal.** The StoreKit 2 paywall (annual with a free trial as the default, then monthly, then the exam pass), server-backed Pro on every device, offer-code redemption, invites, and the owner's billing tools.

**Design:** B §0 (blocker 1), §1, §4, §5 and §6.2.

```files
new  ios/RedPen/Shared/ServerEntitlement.swift
new  ios/RedPen/Shared/BillingAPI.swift
new  ios/RedPen/Features/Paywall/PaywallMarketing.swift
new  ios/RedPen/Features/Paywall/ExamPassRow.swift
new  ios/RedPen/Features/Account/InviteFriendsView.swift
new  ios/RedPen/Features/Account/InviteCodeSheet.swift
new  ios/RedPen/Features/Account/RedeemOfferCodeButton.swift
new  ios/RedPen/Features/Owner/OwnerLicencesView.swift
new  ios/RedPen/Features/Owner/OwnerAmbassadorsView.swift
new  ios/RedPen/Features/Owner/OwnerBillingView.swift
edit ios/RedPen/Shared/Entitlement.swift
edit ios/RedPen/Shared/SubscriptionStore.swift
edit ios/RedPen/Features/Paywall/PaywallView.swift
edit ios/RedPen/Features/Auth/SignInView.swift
edit ios/RedPen/RedPen.storekit
fill ios/RedPen/Shared/Billing/InviteCenter.swift
fill ios/RedPen/Shared/Hooks/BillingHooks.swift
fill ios/RedPen/Features/Auth/BillingAccountSection.swift
fill ios/RedPen/Features/Account/InviteLinkSheets.swift
fill ios/RedPen/Features/Owner/OwnerBillingTools.swift
fill ios/RedPen/Features/Paywall/BillingPreviews.swift
new  ios/RedPen/Tests/BillingTests.swift
new  ios/RedPen/Tests/Suites/billing.suite
edit ios/RedPen/Tests/AccountTests.swift
edit ios/RedPen/Tests/Suites/account.suite
new  ios/UITests/PaywallUITests.swift
new  ios/previews/billing.txt
```

**Instructions (overrides of design B)**

1. **Entitlement.**
   - `isPro = PersonalBuild.isOn || access.isPro`, where `access` merges StoreKit, the stacked exam pass and the server grant, with the 7-day trust window.
   - **Fix `Product.SubscriptionInfo.status(for:)`:** pass `product.subscription?.subscriptionGroupID` from a loaded product, never the group name.
2. **Paywall.**
   - `SubscriptionStoreView` with yearly listed first (a 1-week free trial), then monthly, then the `ExamPassRow`.
   - `.subscriptionStorePolicyDestination` points at `LegalLinks`.
   - Show `EducationFootnote`.
   - Record `paywall_shown`, `purchase_started` and `purchase_completed`.
   - `.inAppPurchaseOptions` sets `appAccountToken`.
3. **Links and codes.**
   - `DeepLink` replaces `InviteLinks`.
   - `InviteLinkSheets` handles `.referral` with a confirmation sheet.
   - The sign-in row "Have an invite or class code?" opens `InviteCodeSheet`: a 7-character code is a referral claim; a 10-character code goes to `AppRouter.shared.open(.code(…))`.
   - There is no `JoinClassAccessView` (R1).
4. **`BillingAccountSection`.**
   - The summary with its source ("Class access from X until Y", "Exam Pass until…", "Free month from an invite until…").
   - Manage / See plans, `RedeemOfferCodeButton`, Restore, and "Invite friends" when `features.referrals`.
5. **Owner tools.**
   - Licences: create by class code, list, extend, disable, seats.
   - Ambassadors: upsert, with the switch "create the offer in App Store Connect automatically", which sets `pending`.
   - Billing: summary, notification log, test notification.
6. **`BillingHooks.becameActive`** calls `refreshServerStatus`. A `.needsPro` failure refreshes the status before the paywall opens.
7. **`RedPen.storekit`** changes as in B §1:
   - the intro offer;
   - `AMB-TEST`;
   - the exam pass;
   - `ar` localisations;
   - group name "Vignette Pro";
   - yearly $34.99.

**Tests.** B §6.2 BillingTests, and AccountTests updated for the `Entitlement` changes. `PaywallUITests` asserts the static parts: header, notice, Terms, Privacy, Restore, Redeem. The product rows start passing once P3.1 adds the StoreKit file to the Test action.

**Acceptance.** Suites, build and UI tests green. The `paywall-store` preview shows the yearly option with the trial. No price or buy link appears anywhere outside the paywall.

---

### W2 · P2.4 Intents, Spotlight and widget data (app; works in Playgrounds)

**Goal.** Siri and Shortcuts ("Quiz me on cardiology in Vignette"), Spotlight, and the shared data layer the widgets read, all working in both builds.

**Design:** C §0, §1, §2.1 (except GlanceViews and ExamDayAttributes), §2.2 (except GlanceIntents), §2.3 (except ExamDayScheduler and SystemSurfaces), §2.5, §5, §7 and §8 (glance and surfaces suites).

```files
new  ios/RedPen/Shared/Intents/StudySetEntity.swift
new  ios/RedPen/Shared/Intents/SubjectEntity.swift
new  ios/RedPen/Shared/Intents/SubjectMatch.swift
new  ios/RedPen/Features/Intents/QuizIntents.swift
new  ios/RedPen/Shared/Spotlight/SpotlightPlan.swift
new  ios/RedPen/Shared/Spotlight/SpotlightIndexer.swift
new  ios/RedPen/Shared/Glance/GlanceModels.swift
new  ios/RedPen/Shared/Glance/GlanceBuilder.swift
new  ios/RedPen/Shared/Glance/GlanceJournal.swift
new  ios/RedPen/Shared/Glance/GlanceStore.swift
new  ios/RedPen/Shared/Glance/ExamCountdown.swift
new  ios/RedPen/Persistence/GlancePublisher.swift
new  ios/RedPen/Features/Support/SurfacesSection.swift
fill ios/RedPen/Persistence/StoreSubjectQuiz.swift
fill ios/RedPen/Shared/Hooks/GlanceHooks.swift
edit ios/RedPen/Features/Library/DeckExportIntents.swift
edit ios/RedPen/Shared/ExamTrack.swift
edit ios/RedPen/Features/Support/ModelSettingsView.swift
edit ios/RedPen/Features/Library/CategoryPages.swift
new  ios/RedPen/Tests/GlanceTests.swift
new  ios/RedPen/Tests/SurfacesTests.swift
new  ios/RedPen/Tests/Suites/glance.suite
new  ios/RedPen/Tests/Suites/surfaces.suite
new  ios/UITests/DeepLinkUITests.swift
```

**Instructions (overrides of design C)**

1. **Already built.** `DeepLink`, `AppRouter` and the `LibraryView` consumers are done (W0). Do not recreate them.
2. **`ExamTrack`** stays Foundation-only. `static var defaults: UserDefaults = .standard` is set to `GlanceStore.defaults` in `GlanceHooks.launched`, with a one-time copy of `exam.date`. `ModelSettingsView` gets the "Starts at" time picker and embeds `SurfacesSection`, which covers Spotlight toggles, the Siri tip and `ShortcutsLink`. In Playgrounds, the section instead says "Widgets, Live Activities and Siri phrases come with the App Store version."
3. **`GlancePublisher`.**
   - It is triggered from `GlanceHooks` (launched, active, background, background refresh) and by its own 3-second debounce on `store.changeCount` and `reviews.changeCount`.
   - It writes the snapshot and library index. Widget reloads are guarded by `SystemSurfaces` only from W3 on; call `WidgetCenter` only on a digest change.
4. **Shortcuts and intents.** Extend `RedPenShortcuts` (R24). Intents record `intent_quiz`, `intent_due` and `intent_countdown`; Spotlight opens record `spotlight_open`.

**Tests.** C §8 GlanceTests and SurfacesTests (the DeepLink part is already in W0). `DeepLinkUITests` opens `redpen://due` and `redpen://quiz?subject=cardiology`.

**Acceptance.** Suites, build and UI tests green. The Playgrounds build compiles and shows the "App Store version" line.

---

### W2 · P2.5 Remote config and owner console (app)

**Goal.** Flags, limits and banners from the Worker without an app update, the student's cloud allowance, and the owner console.

**Design:** D §5, §7 (1) and §9.2 (remote config).

```files
new  ios/RedPen/Shared/CloudUsage.swift
new  ios/RedPen/Shared/RemoteConfigPolicy.swift
new  ios/RedPen/Features/Support/CloudUsageView.swift
edit ios/RedPen/Shared/RemoteConfigStore.swift
fill ios/RedPen/Shared/ConfigBanner.swift
fill ios/RedPen/Shared/Hooks/ConfigHooks.swift
fill ios/RedPen/Features/Support/CloudAllowanceSection.swift
fill ios/RedPen/Features/Owner/OwnerConfigConsole.swift
fill ios/RedPen/Features/Support/ConfigPreviews.swift
new  ios/RedPen/Tests/RemoteConfigPolicyTests.swift
new  ios/RedPen/Tests/Suites/configpolicy.suite
new  ios/previews/config.txt
```

**Instructions**

1. **`RemoteConfigStore`.**
   - `GET /config` with `If-None-Match`.
   - Cache in `Application Support/remote-config.json`; the TTL comes from the config (6 h).
   - The rollout bucket is local and never sent.
   - `ConfigHooks` refreshes it on launch and when the app becomes active.
   - The pure decisions (stale, retry, apply) live in `RemoteConfigPolicy`.
2. **`ConfigBanner`** shows `messages` in the app language.
3. **`CloudAllowanceSection` / `CloudUsageView`** read `/account/allowance` and show "Cloud today: 37 of 400 · resets 02:00", behind `usage.showAllowance`.
4. **`OwnerConfigConsole`.** Flags, rollout, limits (the server validates), banners in English and Arabic, history and rollback, cloud usage, account caps and cache purge.

**Tests.** RemoteConfigPolicyTests.

**Acceptance.** Suites and build green. A flag flipped with `/owner/config` shows up in the app after a foreground (agent-run check).

---

### W2 · P2.6 On-device assist (app)

**Goal.** Hints, rewording and short explanations from Apple's on-device model, cutting cloud cost, with guards against changed facts.

**Design:** D §3 (not Private Cloud Compute), §7 (2, 7) and §9.2 (assist).

```files
new  ios/RedPen/Shared/LLM/Assist.swift
new  ios/RedPen/Shared/LLM/OnDeviceAssist.swift
new  ios/RedPen/Shared/LLM/AssistRouter.swift
new  ios/RedPen/Shared/LLM/AssistCache.swift
new  ios/RedPen/Features/Assist/AssistBar.swift
fill ios/RedPen/Features/Assist/AssistSlot.swift
fill ios/RedPen/Features/Assist/AssistPreviews.swift
fill ios/RedPen/Features/Owner/AssistSelfTestView.swift
edit ios/RedPen/Shared/LLM/HostedLLMClient.swift
new  ios/RedPen/Tests/AssistTests.swift
new  ios/RedPen/Tests/Suites/assist.suite
new  ios/UITests/AssistUITests.swift
new  ios/previews/assist.txt
```

**Instructions**

1. **`AssistSlot`** renders `AssistBar` for its `StudyItemRef` and phase. Buttons are hidden by the `assist.*` flags.
2. **Output rules.** Every output passes `AssistCheck` and is labelled with its source and "For study only". It carries the "Report an error" action through `ReportErrorSheet` (P2.9 fills that file; call it only when `ReportErrorSheet.isAvailable`).
3. **Cloud path.** `HostedLLMClient` gains a `task` field for Vignette Cloud's micro path. Record `ondevice_model_used`.
4. **FoundationModels** code sits behind `#if canImport(FoundationModels) && !NO_FOUNDATION_MODELS` with availability checks. It uses `permissiveContentTransformations` and stays transform-only.

**Tests.** D §9.2 AssistTests. `AssistUITests` launches with `-assistStub`.

**Acceptance.** Suites, build and UI tests green. On a device without Apple Intelligence (the simulator), Hint still works through the fallback and Reword is hidden.

---

### W2 · P2.7 Generation cache offer (app)

**Goal.** Offer a set already generated from the same lecture before starting a new generation.

**Design:** D §4.1, §4.2 and §9.2 (fingerprint).

```files
new  ios/RedPen/Shared/LLM/LectureFingerprint.swift
new  ios/RedPen/Shared/LLM/CloudJobSpec.swift
new  ios/RedPen/Features/Library/CachedSetOffer.swift
edit ios/RedPen/Shared/LLM/CloudJobs.swift
edit ios/RedPen/Features/Library/MCQGenerateForm.swift
edit ios/RedPen/Features/Library/LectureWriterSection.swift
edit ios/RedPen/Features/OSCE/OsceGenerateSection.swift
new  ios/RedPen/Tests/FingerprintTests.swift
new  ios/RedPen/Tests/Suites/fingerprint.suite
```

**Instructions**

1. **Split the spec types.** Move `Spec`, `Step` and `Check` into `CloudJobSpec.swift` as `extension CloudJobs`, so that existing references still compile.
2. **Generate forms.** Show `CachedSetOffer`: "Ready now: N made from this lecture (free, instant)", with a "Write fresh instead" option.
3. **Class sharing.** "Share with ‹class›" draws on `GroupCenter.shared.classesICanShareTo`.
4. **Hashes.** `canonical()` is applied to every source before upload. The hashes must equal the JS vectors in `server/tests/fixtures/fingerprint-vectors.json`.

**Tests.** FingerprintTests.

**Acceptance.** Suites and build green. A second generation from the same lecture is served from the cache (agent-run check against the deployed worker).

---

### W2 · P2.8 Telemetry and privacy choices (app)

**Goal.** Opt-in crash, hang and usage reporting from the app, the privacy choices screen, owner insights, and the performance baseline.

**Design:** E §0, §3, §5 and §8 (Swift, UI).

```files
new  ios/RedPen/Shared/Telemetry/UsageEvent.swift
new  ios/RedPen/Shared/Telemetry/UsageLedger.swift
new  ios/RedPen/Shared/Telemetry/TelemetryConsent.swift
new  ios/RedPen/Shared/Telemetry/DiagnosticReport.swift
new  ios/RedPen/Shared/Telemetry/CallStackTree.swift
new  ios/RedPen/Shared/Telemetry/BuildFlavour.swift
new  ios/RedPen/Shared/Telemetry/MetricKitBridge.swift
new  ios/RedPen/Shared/Telemetry/DiagnosticsOutbox.swift
new  ios/RedPen/Shared/Telemetry/TelemetryAPI.swift
new  ios/RedPen/Shared/Telemetry/Perf.swift
new  ios/RedPen/Shared/Telemetry/Telemetry.swift
new  ios/RedPen/Features/Support/PrivacyChoicesView.swift
new  ios/RedPen/Features/Support/TelemetryAskCard.swift
fill ios/RedPen/Shared/Hooks/TelemetryHooks.swift
fill ios/RedPen/Features/Support/PrivacyChoicesRow.swift
fill ios/RedPen/Features/Library/LibraryNotices.swift
fill ios/RedPen/Features/Owner/OwnerInsightsView.swift
fill ios/RedPen/Features/Support/TelemetryPreviews.swift
edit ios/RedPen/Persistence/SyncEngine.swift
edit ios/RedPen/Shared/SourceIngest.swift
edit ios/RedPen/Shared/MCQGenerator.swift
edit ios/RedPen/Features/Notes/ForceLayout3D.swift
new  ios/RedPen/Tests/TelemetryTests.swift
new  ios/RedPen/Tests/Suites/telemetry.suite
new  ios/UITests/PrivacyChoicesUITests.swift
new  ios/UITests/PerfUITests.swift
new  .github/workflows/perf.yml
new  ios/previews/telemetry.txt
```

**Instructions (overrides of design E)**

1. **Events.** `AppEvent` (from W0) is the event enum. `UsageEvent.swift` is `extension AppEvent { var dailyCap: Int }`, using the §8.1 caps.
2. **Routes.** `/telemetry/diag` and `/telemetry/usage` carry no Authorization header.
3. **Placement.**
   - The ask card sits in `LibraryNotices` and appears only after 3 active days, once.
   - Both toggles default to off.
   - `PrivacyChoicesRow` opens `PrivacyChoicesView`, which includes "See exactly what is sent".
4. **Signposts.** `sync_round` (SyncEngine), `pdf_ingest` (SourceIngest), `generation_local` (MCQGenerator) and `graph3d_layout` (ForceLayout3D). `library_load` is added in W4.
5. **Baseline.** `perf.yml` and `PerfUITests` record the W2 baseline on the `perf-bench` branch. W4 is judged against it.

**Tests.** E §8 Swift items. PrivacyChoicesUITests: both toggles are off.

**Acceptance.** Suites, build and UI tests green. Nothing is sent with consent off (the outbox test).

---

### W2 · P2.9 Consent, legal, error reports (app)

**Goal.** Terms gate v3 with the education notice, consent for third-party AI, "Report an error" everywhere, the student's report history, and the owner's review queue.

**Design:** F §0 (items 3–5), §3 (not the localisation infrastructure), §5, §6 and §7 (Swift, UI).

```files
new  ios/RedPen/Shared/LegalTerms.swift
new  ios/RedPen/Shared/ErrorReport.swift
new  ios/RedPen/Shared/ReportOutbox.swift
new  ios/RedPen/Shared/ReportsAPI.swift
new  ios/RedPen/Shared/ServerMessages.swift
new  ios/RedPen/Features/Account/CloudAIConsentView.swift
new  ios/RedPen/Features/Support/MyReportsView.swift
fill ios/RedPen/Shared/ReportStore.swift
fill ios/RedPen/Shared/CloudGate.swift
fill ios/RedPen/Shared/Hooks/TrustHooks.swift
fill ios/RedPen/Features/Support/ReportErrorSheet.swift
fill ios/RedPen/Features/Support/AboutLegalPage.swift
fill ios/RedPen/Features/Support/CloudAIRow.swift
fill ios/RedPen/Features/Support/TrustRootSheets.swift
fill ios/RedPen/Features/Support/TrustPreviews.swift
fill ios/RedPen/Features/Owner/ReportsReviewView.swift
fill ios/RedPen/Features/Auth/TrustAccountSection.swift
edit ios/RedPen/Features/Account/RecordingTermsView.swift
new  ios/RedPen/Tests/TrustTests.swift
new  ios/RedPen/Tests/Suites/trust.suite
new  ios/UITests/TrustUITests.swift
new  ios/previews/trust.txt
```

**Instructions (overrides of design F)**

1. **Terms gate v3.**
   - It adds the education-only point and the no-patient-data point.
   - Keep the `acceptRecordingTerms` identifier and the `RecordingTermsStore` API.
   - On accept, post `/account/consent {termsVersion: 3}` in the background.
2. **`CloudGate`.**
   - It suspends the first cloud request until the root consent sheet (`TrustRootSheets`) is answered. The sheet names the providers from `/legal.json`, requires 18+ and forbids patient data.
   - "Keep everything on this device" declines consent.
   - The sheet **never appears at launch**.
   - Consent can be withdrawn through `CloudAIRow`.
3. **Reports.**
   - `ReportErrorSheet` posts `/reports` with `shareCode` from `StudyItemRef.shareCode`; its outbox retries with backoff.
   - `ReportsReviewView` has three segments: Errors (`/owner/reports/*`), Community (`/owner/moderation/*`) and Support (`/owner/support/*`). Everything is rendered with `Text(verbatim:)`.
4. **Pages and account.**
   - `AboutLegalPage` shows the notice text and links to Privacy, Terms, Accuracy and Support.
   - `TrustAccountSection` holds "Your reports" (MyReportsView, with Apply correction when the fingerprint still matches, via `Store.update`) and "About & legal".
5. **Wrap-up.** Record `error_report_sent`. Flip the `isAvailable` flags, including `ReportErrorSheet`.

**Tests.** F §7 TrustTests, including the regression that old `Account` JSON still decodes. `TrustUITests` uses `-reportsDryRun` and checks the gate v3 text.

**Acceptance.** Suites, build and UI tests green. `LocalSignInUITests` still passes. "Report an error" appears in the More menu of every study screen.

### W2 gate

1. Every suite passes, plus the app build and all UI tests.
2. `ios-preview` includes every new screen.
3. The Playgrounds package compiles.
4. An agent runs a scripted smoke test in the simulator against the deployed worker: share → import → join class → report → consent → paywall preview.

---

### W3 · P3.1 Widgets, Live Activity, `project.yml`, privacy manifest, Playgrounds script

**Goal.** Home Screen and Lock Screen widgets (including the interactive due card), the Control, the exam-day Live Activity, and every Xcode-only setting, in the one package that owns `project.yml`.

**Design:** C §2.1 (GlanceViews, ExamDayAttributes), §2.2 (GlanceIntents), §2.3 (ExamDayScheduler, SystemSurfaces), §2.4, §3, §4, §6 and §8 (CI); A §6.4; B §6.2 (StoreKit test action); E §3.3 and F §3 (privacy manifest).

```files
new  ios/RedPenWidgets/RedPenWidgetsBundle.swift
new  ios/RedPenWidgets/DueCardWidget.swift
new  ios/RedPenWidgets/ExamCountdownWidget.swift
new  ios/RedPenWidgets/TodayWidget.swift
new  ios/RedPenWidgets/ReviewControl.swift
new  ios/RedPenWidgets/ExamDayLiveActivity.swift
new  ios/RedPenWidgets/Info.plist
new  ios/RedPenWidgets/RedPenWidgets.entitlements
new  ios/RedPenWidgets/Localizable.xcstrings
new  ios/RedPen/Shared/Glance/GlanceViews.swift
new  ios/RedPen/Shared/Glance/ExamDayAttributes.swift
new  ios/RedPen/Shared/Intents/GlanceIntents.swift
new  ios/RedPen/Shared/LiveActivities/ExamDayScheduler.swift
new  ios/RedPen/Shared/SystemSurfaces.swift
new  ios/RedPen/PrivacyInfo.xcprivacy
new  ios/UITests/SurfacesUITests.swift
new  ios/previews/surfaces.txt
fill ios/RedPen/Shared/Glance/GlancePreviews.swift
edit ios/RedPen/Features/Support/SurfacesSection.swift
edit ios/RedPen/Shared/Hooks/GlanceHooks.swift
edit ios/RedPen/Persistence/GlancePublisher.swift
edit ios/project.yml
edit tools/make_swiftpm.py
edit .github/workflows/app-build.yml
```

**Instructions**

1. **`project.yml`.** Follow C §3: the `RedPenWidgets` target, `RED_PEN_APP_GROUP`, the app group on both targets, `NSSupportsLiveActivities`, `NSUserActivityTypes` and `RedPenAppGroup`. In addition:
   - `com.apple.developer.associated-domains: [applinks:redpen-auth.vv7sh4rnnw.workers.dev]`, with the `?mode=developer` variant for Debug;
   - a `postGenCommand` that adds `RedPen.storekit` to the scheme's Test action (B §6.2).
2. **`PrivacyInfo.xcprivacy`** matches the §6 table.
   - `NSPrivacyTracking` is false.
   - Accessed-API reasons are UserDefaults `CA92.1` and file timestamp `C617.1`. Search for any other required-reason API and add it.
3. **`tools/make_swiftpm.py`.**
   - Ignore `*.xcprivacy` and `*.xcstrings`; the second becomes a real conversion in P5.0.
   - Write `AdditionalInfo.plist` with `CFBundleURLTypes` (`redpen`) and reference it through `additionalInfoPlistContentFilePath` (A §6.4). Verify on a device; if it is ignored, it does no harm.
   - Add a comment that `VIGNETTE_PCC` is never defined.
4. **Widget intents** run in the extension with `isDiscoverable = false` and never use a network or token.
   - The journal drain records `widget_answer`. Also record `widget_open`, `control_open`, `live_activity_scheduled` and `live_activity_started`.
   - `SurfacesSection` gains the widget and Live Activity toggles.
   - `GlanceHooks.becameActive` calls `ExamDayScheduler.sync`.
5. **`app-build.yml` assertions:**
   - `PlugIns/RedPenWidgets.appex` exists;
   - `NSSupportsLiveActivities` is true;
   - `Metadata.appintents` contains `QuizMeIntent`;
   - `PrivacyInfo.xcprivacy` is in the bundle;
   - `RedPenOwnerKey` is empty.

**Tests.** C §8 CI checks. `SurfacesUITests`. The `surfaces` preview in light, dark and RTL.

**Acceptance.** The app build passes the assertions, the Playgrounds package still compiles without the extension, and the widget gallery previews render.

---

### W3 · P3.2 Release automation (App Store Connect API; may start any time after W0)

**Goal.** No Mac and no manual App Store Connect work beyond §6. It covers signed TestFlight uploads, products and prices, offer codes, notification URLs, metadata, screenshots, reel footage and dSYMs.

```files
new  .github/workflows/testflight.yml
new  .github/workflows/appstore-setup.yml
new  .github/workflows/store-screenshots.yml
new  .github/workflows/reel-footage.yml
new  tools/asc/client.mjs
new  tools/asc/register.mjs
new  tools/asc/products.mjs
new  tools/asc/offers.mjs
new  tools/asc/metadata.mjs
new  tools/asc/screenshots.mjs
new  tools/asc/tests/client.test.mjs
new  tools/asc/tests/products.test.mjs
new  tools/screenshots/caption.py
new  tools/tests/test_caption.py
new  ios/UITests/StoreScreenshotsUITests.swift
new  ios/UITests/ReelFootageUITests.swift
```

**Instructions**

1. **`tools/asc/client.mjs`.**
   - ES256 JWT from the Team key secrets `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID` and `ASC_API_PRIVATE_KEY`, reusing the approach of `appStoreToken`.
   - Paging, retry on 429 and 5xx, and a `--dry-run` mode that prints the planned calls.
   - Never print a token or key.
2. **`register.mjs`.**
   - Ensures the bundle IDs `com.cramdown.app` and `com.cramdown.app.widgets` exist.
   - Enables the capabilities Sign in with Apple, Associated Domains and App Groups.
   - Reads the team ID from the bundle ID's `seedId` and writes it to `app_facts.apple_team_id` with `wrangler d1 execute` (the Cloudflare secrets are already in the repo).
3. **`testflight.yml`.**
   - Steps: register, then `ci/pcc_enable.sh` if it exists and is executable (P3.3), then `xcodegen`.
   - Archive with `-allowProvisioningUpdates -authenticationKeyPath/-ID/-IssuerID` and `DEVELOPMENT_TEAM=<seedId>`.
   - Export with `method app-store-connect`, `destination upload`.
   - Set the build number from the run number.
   - Upload dSYMs as the release asset `dsyms-<version>-<build>` and update the index on the `dsyms` branch (E §3.5).
   - Assert that `RedPenOwnerKey` is empty.
   - Skip cleanly with `::warning` when the secrets are missing.
   - If App Store Connect has no app record for `com.cramdown.app` yet, stop after registering, with the message "Create the app record (owner step 3 in §6), then run this again".
4. **`appstore-setup.yml`**, idempotent. It reads `docs/launch/metadata/**` and `docs/launch/pricing.json` (P6.1) and does the following:
   - Creates the subscription group "Vignette Pro", yearly and monthly at level 1, English and Arabic localisations, prices per territory (the nearest price point to `pricing.json`), the 1-week free intro offer on yearly and 16-day grace.
   - Creates the non-renewing Exam Pass.
   - Uploads review screenshots from `store-screenshots`.
   - Sets `subscriptionStatusUrl` and `subscriptionStatusUrlForSandbox`, both to `<worker>/apple/notifications`, with version 2.
   - Uploads metadata and screenshots, primary category Education, the age-rating answers from §6 and the review notes.
   - Processes the ambassador queue (`/ci/ambassadors/pending`): creates an offer code (free month; new and expired customers) plus a custom code, then posts `/ci/ambassadors/result`.
   - If the optional In-App Purchase key secrets exist, it asks the Worker for a test notification (`/owner/billing/test-notification`) and waits up to 60 s for a `TEST` row in `/owner/billing/notifications` (B §6.3). A missing row is a `::warning`, never a failure.
   - Every call Apple refuses is written to the run summary as an owner checklist line; the workflow never fails silently.
5. **`store-screenshots.yml`.**
   - iPhone 6.9" and iPad 13", English and Arabic, from `StoreScreenshotsUITests` driving the preview screens.
   - Captions come from `app-store-listing.md` (via P6.1's metadata) and are drawn by `caption.py` (Pillow, arabic-reshaper and python-bidi for Arabic).
   - Output goes to the `store-screenshots` branch.
6. **`reel-footage.yml`.** `xcrun simctl io recordVideo` while `ReelFootageUITests` plays the reel scripts ("lecture PDF → 40 questions", the black-hole idea map, commute mode, occlusion). MP4s go to the `reels` release through `publish.yml`.

**Acceptance**

- `tools-tests` is green, including the dry-run tests with a fake fetch.
- With the owner's secrets in place, `testflight.yml` uploads a build that installs through TestFlight on the owner's phone.
- `appstore-setup` in dry run prints the full plan.

---

### W3 · P3.3 Private Cloud Compute (optional, compiled only when Apple has granted it)

**Goal.** Free Apple Private Cloud Compute for assist and writing when Apple grants the entitlement; otherwise nothing changes.

**Design:** D §3.2 (PCC), §6 and §7 (4).

```files
new  ci/pcc_enable.sh
edit ios/RedPen/Shared/LLM/OnDeviceAssist.swift
edit ios/RedPen/Shared/LLM/AssistRouter.swift
edit ios/RedPen/Shared/LLM/LocalLLMService.swift
edit ios/RedPen/Features/Support/ModelSettingsView.swift
```

**Instructions**

1. **`ci/pcc_enable.sh`.** When the iOS SDK is 27 or later **and** the App ID has the Private Cloud Compute capability (checked through the App Store Connect API), use `yq` to add `VIGNETTE_PCC` and the entitlement to `project.yml` inside the CI workspace only. Otherwise exit 0 and change nothing.
2. **Swift code** behind `#if VIGNETTE_PCC`:
   - `ApplePCCAssist`;
   - `PCCBackend`;
   - `LLMChoice.appleCloud` (stored as `"pcc"`);
   - the picker entry "Apple Private Cloud Compute (free)" in `ModelSettingsView`.
3. **Flags:** `assist.pcc` and `assist.pccWriter`.

**Acceptance.** Builds with and without `VIGNETTE_PCC`. The Playgrounds build compiles the code out.

### W3 gate

- The app build passes P3.1's assertions.
- The TestFlight build installs, if the owner has done steps 1–3.
- The AASA returns 200 with the team id, once `testflight.yml` has run with the owner's key.

---

### W4 · P4.1 Performance (serial; touches most views)

**Goal.** Faster launch and smoother screens: the library loads off the main thread, the stores become `@Observable`, and drawing gets cheaper.

**Design:** E §4.

The file set is every file that contains `ObservableObject`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject` or `.environmentObject(`, plus the following:
- `Persistence/Store.swift`
- `RedPenApp.swift`
- `Features/Analytics/AnalyticsVisuals.swift`
- `Shared/AppBackdrop.swift`
- `Features/Reasoning/ReasoningView.swift`
- `Features/Library/LibraryView.swift` (the loading placeholder)
- `ios/RedPen/Tests/StoreLoadTests.swift` (new) and `Suites/storeload.suite` (new)

**Instructions**

1. Record the baseline with `perf.yml`.
2. **Load the library off the main actor** (E §4.1):
   - `Store.readFiles` runs detached;
   - `loadInBackground()` wraps it in `MXMetricManager.extendLaunchMeasurement` and emits the `library_load` signpost;
   - **`write()` refuses to run before `isLoaded`**;
   - seeding moves to `.task`;
   - show a placeholder until the library is loaded.
3. **`@Observable` migration** in E §4.2's order (leaf classes, then singletons, shared stores, `Store` and `ReviewStore`). Replace the Combine debounce with `.onChange(of: store.libraryRevision)` plus a 4-second task.
4. **Drawing and rendering.**
   - Add `drawingGroup()` to the `StudyHeatmap` grid and the `ProgressRing` arcs, and nowhere with glass.
   - Remove the `AnyView` in `ReasoningView`.
   - Pause the `AppBackdrop` animation when the scene is not active.

**Tests.** `StoreLoadTests`: a save before the load completes never truncates the library. All suites and UI tests pass.

**Acceptance.**
- Launch p50 and scroll hitch in `perf.yml` are at or better than the W2 baseline.
- No `ObservableObject` is left, apart from any documented exception.
- Screenshots are unchanged.

---

### W5a · P5.0 Localisation infrastructure

**Goal.** The machinery for Arabic: catalogs, the Playgrounds conversion, the language choice, the lint and the translation workflow.

**Design:** F §0 (6–7), §3 (AppLanguage, TextDirection, PlaygroundsLocalization, RTL rules), §4 and §7 (LanguageTests, Arabic UI test, `test_l10n`).

```files
new  ios/RedPen/Localizable.xcstrings
new  ios/RedPen/InfoPlist.xcstrings
new  ios/RedPen/Shared/AppLanguage.swift
new  ios/RedPen/Shared/TextDirection.swift
new  ios/RedPen/Shared/PlaygroundsLocalization.swift
new  ios/RedPen/L10n/glossary-ar.tsv
new  tools/l10n_lint.py
new  tools/l10n_check.py
new  tools/translate_xliff.mjs
new  tools/tests/test_l10n.py
new  .github/workflows/localize.yml
new  ios/RedPen/Tests/LanguageTests.swift
new  ios/RedPen/Tests/Suites/language.suite
new  ios/UITests/ArabicLayoutUITests.swift
fill ios/RedPen/Features/Support/AppLanguageRow.swift
edit ios/RedPen/RedPenApp.swift
edit ios/project.yml
edit tools/make_swiftpm.py
edit .github/workflows/swift-tests.yml
edit .github/workflows/app-build.yml
```

**Instructions**

1. **Catalogs and `project.yml`.** Create empty catalogs with source language `en`. In `project.yml` set `developmentLanguage: en`, `LOCALIZATION_PREFERS_STRING_CATALOGS` and `SWIFT_EMIT_LOC_STRINGS`, and `CFBundleLocalizations: [en]` for now; P5.7 adds `ar`.
2. **`make_swiftpm.py`.** Add `catalog_to_lproj` (Arabic plurals in all six categories), `defaultLocalization: "en"` and `.process("Resources")`.
3. **`RedPenApp`.** Only when `SWIFT_PACKAGE` is defined, install `PlaygroundsLocalization` and set the root `locale` and `layoutDirection`.
4. **Localisation pipeline.**
   - `localize.yml` exports, translates only the untranslated units through the worker's free chain with the owner key, checks format specifiers, imports and opens a PR.
   - `l10n_lint` runs in report-only mode until P5.7.

**Acceptance.**
- The LanguageTests and `test_l10n` pass.
- Both builds compile.
- The Playgrounds package contains `en.lproj`.

### W5a · P5.1 to P5.6 String and RTL sweeps (parallel, by folder)

**Goal.** Every user-facing string localisable, and every screen correct right to left.

| Package | Folder globs (edit only these) |
|---|---|
| P5.1 | `ios/RedPen/Features/{Library,Examples,Sources,Coverage,Insight}/**` |
| P5.2 | `ios/RedPen/Features/{MCQ,Anki,QA,OSCE,Book}/**` |
| P5.3 | `ios/RedPen/Features/{Narrate,Voice,Cases,Reasoning,Recall}/**` |
| P5.4 | `ios/RedPen/Features/{Notes,Analytics,Intents,Assist,Groups,Share}/**` |
| P5.5 | `ios/RedPen/Features/{Auth,Account,Paywall,Support,Owner}/**`, **except** `Features/Support/AppLanguageRow.swift` |
| P5.6 | `ios/RedPen/Shared/**`, `ios/RedPen/Models/**`, `ios/RedPen/Persistence/**`, `ios/RedPenWidgets/**/*.swift`, **except** P5.0's three new Shared files, and except the prompt files `Shared/LLM/**`, `Shared/Reasoning/*Writer.swift`, `Shared/MCQPrompt.swift` and the `@Guide` strings in `Shared/MCQGenerator.swift` |

**Rules for every sweep** (F §3, §4):
- Wrap user-facing literals.
- Keep public `String` return types: return `String(localized:)` from the existing properties instead of changing the type, so no call site elsewhere breaks.
- Use plural variations instead of ternaries.
- Use `.formatted()` for numbers.
- Use `chevron.forward`/`chevron.backward`, and `.leading`/`.trailing`.
- Force left-to-right on occlusion, figure, graph and drawing canvases.
- Use `TextDirection.dominant` for content blocks.
- Keep the MCQ letters A–E in Latin.

### W5b · P5.7 Translation run and Arabic QA

**Goal.** Arabic translated, reviewed and switched on.

**Files:** `ios/RedPen/Localizable.xcstrings`, `ios/RedPen/InfoPlist.xcstrings` (through the `localize.yml` PR), `ios/RedPen/L10n/glossary-ar.tsv` and `ios/project.yml` (`CFBundleLocalizations` gains `ar`).

**Steps:**
1. Dispatch `localize.yml`.
2. Review the glossary terms: medicine, drug and exam names stay in Latin script.
3. Make `l10n_lint` blocking.
4. Run `ArabicLayoutUITests` and check the screenshots (occlusion stays LTR, the paywall is correct in Arabic).
5. Add `ar` only when the wave-1 keys are fully covered (F §4).

The Arabic *listing* text comes from `app-store-listing.md`.

---

### W6 · P6.1 Launch metadata

**Goal.** Turn the Docs-phase documents into validated machine inputs, and reconcile the legal text.

```files
new  docs/launch/metadata/en-US/name.txt
new  docs/launch/metadata/en-US/subtitle.txt
new  docs/launch/metadata/en-US/keywords.txt
new  docs/launch/metadata/en-US/description.txt
new  docs/launch/metadata/en-US/promotional_text.txt
new  docs/launch/metadata/en-US/release_notes.txt
new  docs/launch/metadata/ar-SA/name.txt
new  docs/launch/metadata/ar-SA/subtitle.txt
new  docs/launch/metadata/ar-SA/keywords.txt
new  docs/launch/metadata/ar-SA/description.txt
new  docs/launch/metadata/ar-SA/promotional_text.txt
new  docs/launch/metadata/ar-SA/release_notes.txt
new  docs/launch/metadata/urls.json
new  docs/launch/metadata/screenshot-captions.json
new  docs/launch/metadata/review-notes.txt
new  docs/launch/pricing.json
new  docs/launch/demo-set.json
new  tools/demo_content.mjs
new  .github/workflows/demo-content.yml
new  tools/tests/test_metadata.py
edit server/legal/content.js
```

**Instructions**

1. **Metadata limits:** name ≤ 30, subtitle ≤ 30, keywords ≤ 100 bytes per locale, promotional text ≤ 170, description ≤ 4000.
   - No "Anki" in the name, subtitle or keywords (2.3.7). The description may say "exports .apkg decks".
   - No prices in the metadata.
   - Accuracy numbers appear only with the `/accuracy` link.
2. **`pricing.json`:** per-territory target prices for monthly, yearly and the pass. The defaults are B §8's, overridden by `pricing.md`.
3. **`review-notes.txt`** combines:
   - A §9.2 (4), B §5, C §10, D §10 and F §9;
   - education-only; no login needed ("Start without an account"); where "Report an error" is;
   - AI consent and the on-device path;
   - moderation (filter, report, block, auto-suspend, owner review, `/support`);
   - demo share and class links and a review class-access code (created in P6.2);
   - that owner tools are visible only to the developer's account;
   - that the capacity switches are all on;
   - the Exam Pass is non-renewing;
   - the referral rules;
   - how to see the widgets and the Live Activity;
   - the Siri phrase.
4. **Legal text.** Reconcile `server/legal/content.js` with `privacy-and-terms-draft.md` and with the §6 privacy table.
5. **Review demo content.** `demo-set.json` is a short original MCQ set written for the review. `tools/demo_content.mjs` runs from `demo-content.yml`, which derives `OWNER_KEY` like the deploy workflow. It creates a fresh device account named "Vignette Review Demo", accepts the rules through `/account/consent`, publishes and commits the set (`/shares/publish`, `/shares/commit`), creates a class (`/groups/create`) and attaches a 5-seat, 30-day licence to it (`/owner/licences/create`). It prints the share link, the class link and the class-access code for `review-notes.txt`. It is idempotent: it reuses the account and share it made before.

**Acceptance.** `test_metadata.py` passes the limits, finds no banned words, and confirms the Arabic files exist.

### W6 · P6.2 Release run (operations, no repository files)

**Goal.** A build in App Store Connect with its products, metadata, screenshots and demo content, plus a short checklist for the owner.

1. Deploy the worker.
2. Dispatch `demo-content.yml` (P6.1): a sample share, a demo class, and a review licence with 5 seats and 30 days. Put the links and the code into `review-notes.txt`.
3. Run `testflight.yml`.
4. Run `appstore-setup.yml`: dry run first, then for real.
5. Run `store-screenshots.yml`.
6. Check that the AASA, `/privacy`, `/terms` and `/support` return 200.
7. Post the owner checklist (§6, steps 6–11) with direct App Store Connect links, and the run summary of anything Apple refused.

---

## 6. Owner's unavoidable publish-time steps (App Store Connect and Apple only)

Agents automate everything else. Steps 1–5 can be done any time; they unblock TestFlight, and nothing else waits for them. Each step runs on the iPhone or iPad, in the Apple Developer app, App Store Connect in Safari, or the GitHub app. **Never paste keys into chat.**

1. **Apple Developer Program** ($99/yr), in the Apple Developer app.
   - Individual enrolment works for an education app. If Review ever cites 5.1.1(ix), the fallback is an organisation account (a D-U-N-S number is needed), as §7 says.
2. **App Store Connect → Users and Access → Integrations → Team Keys.**
   - Generate a key with the **Admin** role, which cloud signing and capability registration need.
   - Download the `.p8` once.
   - In GitHub, under repository settings → Secrets, add `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID` and `ASC_API_PRIVATE_KEY` (the file contents).
   - This is the only step outside App Store Connect.
3. **App record.** After agents run `testflight.yml` once, which registers the bundle IDs: go to Apps → + → New App.
   - Platform: iOS.
   - Name: from `app-store-listing.md`. "Vignette" alone is likely to be taken.
   - Primary language: English (U.S.).
   - Bundle ID: `com.cramdown.app`.
   - SKU: `vignette-ios`.
   - The API cannot create app records.
4. **Business.** Accept the Paid Apps agreement and add bank and tax details (W-8BEN). Products do not load, even in the sandbox, until this is done.
5. **App Store Small Business Program** application (15% commission; also required for Private Cloud Compute).
6. **App Privacy** (web only). Answer "Data is collected" and "No tracking". Every type:

   | Type | Linked | Purpose | Why |
   |---|---|---|---|
   | Contact Info → Name, Email | yes | App Functionality | only if Apple or Google provides them |
   | Identifiers → User ID | yes | App Functionality | the account |
   | Purchases → Purchase History | yes | App Functionality | subscriptions and passes |
   | User Content → Other User Content | yes | App Functionality | synced library, lecture text sent for generation, shared sets, group names, display names, error reports |
   | User Content → Audio Data | yes | App Functionality | lecture audio for cloud transcription, only when used |
   | User Content → Customer Support | yes | App Functionality | support messages |
   | Usage Data → Product Interaction | yes | App Functionality | leaderboard weekly counts (opt-in); per-account cloud-usage counters |
   | Usage Data → Product Interaction | no | Analytics | opt-in anonymous counters |
   | Diagnostics → Crash Data, Performance Data, Other Diagnostic Data | no | App Functionality, Analytics | opt-in MetricKit |

7. **Regulated medical device declaration.** "Not a regulated medical device", for the EEA, the UK and the US.
8. **Age rating.**
   - Agents set the answers through the API: Medical/Treatment Information **Frequent**; User-Generated Content **Yes**; no messaging; no ads.
   - Confirm the computed rating. If App Store Connect offers a higher rating, pick 18+: this matches the Gemini API terms (no users under 18) and the cloud-AI consent's 18+ confirmation.
9. **EU Digital Services Act trader status.** Declare it; a subscription seller is likely a trader, so Apple will show an address, phone and email. The alternative is to exclude the EU storefronts at launch; tell the agents and they will set availability.
10. **App Review information.** Enter your contact name, phone and email. These are personal details, so agents never store them. The notes and demo links are pre-filled from `review-notes.txt`.
11. **First submission.** On the version page, attach the three in-app purchases (Apple requires the first subscription to go with a version), then press **Submit for Review**.

Optional, not needed for launch:
- An **In-App Purchase key** for the App Store Server API, stored as the secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY`. It enables `askApple` and the test notification.
- **Enable R2** in Cloudflare (a card on file, $0 under 10 GB) for 30 MB shares.
- **Request the Private Cloud Compute entitlement.**
- **Accessibility Nutrition Labels.**
- **Only if the signing log says the App Group could not be registered:** at developer.apple.com, open Identifiers → App Groups and create `group.com.cramdown.app`, then tick it on both App IDs.
- **Only if the setup summary lists a refused API call:** do that one item by hand.

---

## 7. App Store rule risks and the chosen mitigation

| Rule | Where it bites | Risk | Mitigation built into the plan |
|---|---|---|---|
| **1.2** user-generated content | shared sets, classes, group and display names, leaderboards | High | All four required elements:<br>- **Filter:** `names.js` and `NameRules` (English and Arabic), plus optional Llama Guard.<br>- **Report:** on every shared surface and on the web pages.<br>- **Block:** leaderboard rows and group contexts.<br>- **Contact:** `/support`.<br>Also: rules accepted server-side before any posting (428); auto-suspend at 3 distinct reporters; owner review list; demo links in the review notes. |
| **1.4.1** medical, and the medical-device declaration | the whole app, AI content, accuracy claims | High | Education-only positioning in gate v3, the footers, the paywall, the widget descriptions and the web pages. `/accuracy` publishes confidence intervals and the method. No unqualified accuracy claims. Primary category Education. Declared not a medical device. No dosing or diagnostic features. |
| **5.1.2(i)** third-party AI | lecture text, audio and answers sent to Gemini, Workers AI, Hugging Face or Novita | High | A named-provider consent before the first transmission, 18+, a decline path that stays on the device, withdrawal in Settings, and server enforcement switched on (`trust.aiConsentEnforced`) once the consenting build is live. |
| **3.1.1 / 3.1.3(b)(c)** licence keys | class access | Medium | Owner-only licences attached to a real class. Framed as access provided by the student's school. No price, purchase or "buy for your school" in the app or on the web pages. The same Pro is always available by in-app purchase. Review notes plus a review code. Kill switch `billing.licences`. Fallback `billing.licenceOfferCodes`, using Apple one-time offer codes. |
| **3.1.2** subscriptions | paywall | Low | `SubscriptionStoreView` renders Apple's terms. Terms and Privacy go to Worker pages. Renewal text. Apple's standard EULA. The Exam Pass is non-renewing and says "never renews". |
| **3.2.2(x), 5.6.3** incentives, manipulation | referrals, ambassadors | Low–Medium | Nothing is required to use the app. The reward comes only after the referee returns on another day. One reward per Apple Account, capped per month and year. Ratings and reviews are never asked for. The ambassador agreement forbids fake reviews. Kill switch. |
| **5.3** contests | leaderboards | Low | No prizes, no "win" language, and no friend challenges or duels (the owner rejected them). |
| **5.1.1(ii)–(iv)** consent for analytics | telemetry | Medium | Both toggles off by default. One neutral ask with buttons of equal weight. Withdraw at any time. "Pro never depends on this". Anonymous endpoints and k-anonymity. |
| **5.1.1(v)** account deletion | every new table | Medium | Per-module `onAccountDelete` hooks, tested within the statement budget. Apple financial records are kept without personal data, and the policy says so. |
| **5.1.1(ix)** regulated field, individual developer | the medical context | Medium | Education, not a healthcare service. No patient data (warned in gate v3 and the report sheet). The review notes say so. Fallback: an organisation account. |
| **2.3.1** hidden features | remote flags, owner tools | Low | Config is data only and every feature is on during review. Owner tools show only for the developer's account. Both are disclosed in the notes. |
| **2.5.2** downloaded code | remote config | Low | Only booleans, numbers and banner text. Prompts stay in the binary. |
| **2.3.7** metadata | keywords (Anki, USMLE, PLAB, MRCP, OSCE) | Medium | No competitor or app names in the name, subtitle or keywords. Exam names only where they describe the content. `.apkg` compatibility is mentioned only in the description. |
| **2.5.16, 4.5.3** widgets, Live Activities | extension | Low | Only the student's own content. The Live Activity runs only after the student sets an exam, and only on exam day. There is a toggle, and no marketing. |
| FoundationModels acceptable use | on-device assist | Medium | Transform-only (hint, reword, explain from the set's own text), with `AssistCheck` guards, a source label and a report action. |
| **5.2** intellectual property | shared lecture material | Medium | A rights attestation when publishing. Lecture text is off by default. A copyright report reason. The takedown procedure is in the terms. |
| Privacy labels, manifest and policy consistency | submission | Medium | One table (§6) drives the labels, `PrivacyInfo.xcprivacy` (P3.1) and the policy (P1.8/P6.1). |
| **2.1** completeness | associated domains, products | Medium | The AASA is live with the team id before submission. Products are created and attached. The demo content exists. |
| Gemini API terms | cloud AI | Medium | 18+ for cloud AI, a free-tier disclosure in the consent and the policy. `PRO_PAYS` and the Firebase Blaze plan stay off until there is revenue ("no paid credits"). |

---

## 8. Appendix

### 8.1 Unified event names and daily caps

This is the single list for `AppEvent` (P0.2), the server allow-list (P1.7) and `dailyCap` (P2.8).

| Event | Cap | Event | Cap |
|---|---|---|---|
| `app_active` | 1 | `onboarding_done` | 1 |
| `set_created` | 50 | `set_imported` | 50 |
| `generation_started` | 50 | `generation_succeeded` | 50 |
| `generation_failed` | 50 | `ondevice_model_used` | 200 |
| `quiz_completed` | 100 | `questions_answered` | 2000 |
| `cards_reviewed` | 2000 | `case_completed` | 100 |
| `osce_station_completed` | 100 | `narrate_session` | 50 |
| `voice_session` | 50 | `ideas_opened` | 50 |
| `analytics_opened` | 50 | `accuracy_check_run` | 50 |
| `paywall_shown` | 20 | `purchase_started` | 10 |
| `purchase_completed` | 5 | `share_link_created` | 50 |
| `class_joined` | 5 | `error_report_sent` | 50 |
| `sync_conflict` | 100 | `abnormal_exit` | 5 |
| `widget_answer` | 200 | `widget_open` | 200 |
| `control_open` | 100 | `live_activity_scheduled` | 5 |
| `live_activity_started` | 5 | `intent_quiz` | 100 |
| `intent_due` | 100 | `intent_countdown` | 100 |
| `spotlight_open` | 200 | | |

### 8.2 Deferred on purpose (optional, after launch)

These are left out of the waves so they add no risk before launch. Each can become a package later:
- Silent APNs push after a billing notification, the offer-code delivery fallback for class access, and catching up missed notifications through Get Notification History (B, wave 4). The first needs an APNs key.
- The "study sprint" Live Activity and an interactive Siri snippet (C §9, item 4).
- The iOS 27 `MetricManager` path and App Attest on the telemetry endpoints (E §7).
- A custom domain for share links, so they outlive the `workers.dev` host. This costs about $10 a year and is the owner's call.
- Paid models (`PRO_PAYS=on`, the Firebase Blaze plan), once revenue exists.

### 8.3 Checking that file sets are disjoint

`docs/launch/package-files.tsv` holds one row per package and file, with the columns wave group, package, action and path. It was generated from the `files` blocks above and checked:
- inside each parallel group (W0a, W0b, W1, W2, W3, W5a, W6), no path belongs to two packages;
- the W5a globs do not overlap each other or P5.0's files.

Re-run the check after editing this plan:

```sh
python3 - <<'PY'
import re,collections
t=open('docs/launch/implementation-plan.md').read()
groups={'P0.1':'W0a','P0.2':'W0a','P0.3':'W0a','P0.4':'W0b','P3.1':'W3','P3.2':'W3','P3.3':'W3','P6.1':'W6'}
own=collections.defaultdict(set); bad=0
for m in re.finditer(r'### (W\w+) · (P\d\.\d)[^\n]*\n(.*?)(?=\n### |\Z)', t, re.S):
    pkg=m.group(2); g=groups.get(pkg, m.group(1))
    for fb in re.findall(r'```files\n(.*?)```', m.group(3), re.S):
        for line in fb.strip().splitlines():
            path=line.split()[1]; own[(g,path)].add(pkg)
for (g,p),s in sorted(own.items()):
    if len(s)>1: bad+=1; print('OVERLAP',g,p,sorted(s))
print('overlaps:',bad)
PY
```
