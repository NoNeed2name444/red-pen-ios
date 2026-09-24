> **Source design, feature group F** (architect output, 2026-09-24), copied verbatim.
> It is an input to [`../implementation-plan.md`](../implementation-plan.md). Where the two disagree, **the plan wins**:
> see the plan's section 2 (conflict resolutions) and the work package that implements this design.

# Group F: Trust, legal, error reporting, public accuracy page, Arabic and RTL

## 0. What exists today and what changes

I read `server/worker.js`, `tokens.js`, `pair.js`, `sync.js`, `ai.js` (`isOwnerKey`, `proGate`, `isPro`, `linkSubscription`), `jobs.js`, `tts.js`, `evidence.js`, `schema.sql`, `wrangler.toml`, the deploy, server-test, bench and swift-test workflows, `bench/accuracy.mjs` and `checkers.mjs`, `ios/project.yml`, `make_swiftpm.py`, `AuthAPI`, `Entitlement`, `SubscriptionStore`, `Account`, `RedPenApp`, `AccountView`, `SupportCenter`, `PaywallView`, `RecordingTermsView`, `Theme.swift` (`StudyMoreMenu`/`AccuracyAsk`), `AccuracyCheckSheet`, `PersonalBuild`/`AppResources` and `OwnerClaim`. The group F design has to fit these facts:

1. **Every non-blob, non-job route is POST-only.** `worker.js` returns 405 for anything else, so web pages need a new GET branch placed before that check. Group A's share landing page needs GET too, so there should be one shared `server/web.js` route table that both groups add to.
2. **The paywall links to `https://redpen.app/terms` and `/privacy`.** Nothing in the repo shows that domain is owned or serves those pages. This is a 3.1.2 rejection risk today and must move to Worker-hosted pages.
3. **Owner is already decided on the server** by `accounts.owner = 1`, `OWNER_ACCOUNT_IDS`, or the `OWNER_KEY` bearer. CI already derives the owner key from `AI_API_KEY`. The app is never told whether it is the owner, and `session()` does not return it.
4. **The terms gate already exists** (`RecordingTermsView` / `RecordingTerms.version = 2`, once per account, 5-second countdown). It is the natural home for the education notice. Bump it to version 3.
5. **Every study screen already goes through one menu**, `studyMoreMenu(for:check:)` in `Shared/Theme.swift`, which has `AccuracyAsk`. "Report an error" goes in the same place, so one change covers MCQ, Anki, QA, OSCE, Book and Narrate.
6. **There is no localisation at all.** There is no `.xcstrings`, `.strings` or `.lproj`, and no `String(localized:)`. About 1,200 unique user-facing literals exist, plus about 250 LLM-prompt literals that must **not** be localised. Many user-facing strings are `String`-returning properties (`SupportPage.title`, `Entitlement.summary`, `HelpPage.what`), which SwiftUI does not localise.
7. **The Playgrounds package cannot compile String Catalogs.** An Apple engineer confirmed Playgrounds has no direct localisation support, but hand-made `.lproj` folders with `.strings`/`.stringsdict` in Resources work. The package manifest also has no `defaultLocalization`.
8. **The test harness loads `schema.sql`** by stripping `--` comments and splitting on `;`. New SQL must have no triggers and no `--` or `;` inside literals.
9. **App Store rules found by research that change the plan:**
   - Guideline 5.1.2(i) (13 Nov 2025): the app must get explicit permission before personal data goes to third-party AI, and name the provider.
   - Gemini API terms:
     - On the unpaid tier, Google may use prompts and outputs to improve products, and human reviewers may read them.
     - Apps using the API must not be directed at under-18s.
     - Clinical use and medical advice are prohibited.
   - Regulated-medical-device status must be declared in App Store Connect (since 26 Mar 2026) for apps in the Medical or Health & Fitness category, or apps that answer "frequent Medical or Treatment Information" in the age rating.

---

## 1. Data model (D1)

All of this goes in `server/schema.sql` as `CREATE ... IF NOT EXISTS`. New `accounts` columns go in the ALTER loop in `worker-deploy.yml`.

```sql
-- Report an error: one row per report
CREATE TABLE IF NOT EXISTS error_reports (
  id           TEXT PRIMARY KEY,            -- client UUIDv4 (idempotent retries)
  account_id   TEXT,                        -- NULL once the reporter deletes their account
  created_at   INTEGER NOT NULL,
  reason       TEXT NOT NULL,               -- wrong_answer|wrong_explanation|outdated|unsafe|unclear|typo|offensive|other
  item_kind    TEXT NOT NULL,               -- mcq|card|qa|case|osce|book|narrate|clue|script|reasoning
  set_id       TEXT,
  item_id      TEXT,
  share_id     TEXT,                        -- group A shared/class set, when the item came from one
  origin       TEXT,                        -- cloud|device|imported|typed|shared|example
  model        TEXT,                        -- the model that wrote it, if known
  source_label TEXT,                        -- "Lupus, p.14"
  note         TEXT,                        -- the student's words (<=1000), NULLed on account deletion
  snapshot     TEXT NOT NULL,               -- JSON of the item as shown (<=16 KB)
  fingerprint  TEXT NOT NULL,               -- sha256 of normalised snapshot, groups duplicates
  app_version  TEXT,
  build        TEXT,                        -- xcode|playgrounds
  locale       TEXT,
  status       TEXT NOT NULL DEFAULT 'open',-- open|fixed|wont_fix|duplicate|spam
  owner_note   TEXT,                        -- shown back to the reporter
  correction   TEXT,                        -- JSON {correctIndex?, explanation?, answer?}
  resolved_at  INTEGER
);
CREATE INDEX IF NOT EXISTS error_reports_by_status  ON error_reports (status, created_at);
CREATE INDEX IF NOT EXISTS error_reports_by_account ON error_reports (account_id, created_at);
CREATE INDEX IF NOT EXISTS error_reports_by_print   ON error_reports (fingerprint);
CREATE INDEX IF NOT EXISTS error_reports_by_share   ON error_reports (share_id) WHERE share_id IS NOT NULL;

-- The /support contact form (Support URL; guideline 1.5), so the owner needs no public mailbox
CREATE TABLE IF NOT EXISTS support_messages (
  id         TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,
  account_id TEXT,                          -- when sent from inside the app
  reply_to   TEXT,                          -- email given voluntarily (<=320)
  topic      TEXT NOT NULL,                 -- account|billing|content|privacy|other
  body       TEXT NOT NULL,                 -- <=4000
  locale     TEXT,
  status     TEXT NOT NULL DEFAULT 'open'   -- open|answered|spam
);
CREATE INDEX IF NOT EXISTS support_by_status ON support_messages (status, created_at);

-- Published benchmark summaries (CI -> /bench/publish), shown on /accuracy
CREATE TABLE IF NOT EXISTS bench_runs (
  id           TEXT PRIMARY KEY,            -- kind:dataset:run_id
  kind         TEXT NOT NULL,               -- accuracy|checker
  dataset      TEXT NOT NULL,               -- medqa|medxpertqa
  run_id       TEXT NOT NULL,
  commit_sha   TEXT,
  ran_at       INTEGER NOT NULL,
  published_at INTEGER NOT NULL,
  summary      TEXT NOT NULL                -- validated, server-normalised JSON
);
CREATE INDEX IF NOT EXISTS bench_runs_latest ON bench_runs (kind, dataset, ran_at);
```

**New `accounts` columns** (added to the ALTER loop):

- `terms_version INTEGER NOT NULL DEFAULT 0`
- `terms_at INTEGER NOT NULL DEFAULT 0`
- `ai_consent INTEGER NOT NULL DEFAULT 0` (consent-text version granted; 0 means none or withdrawn)
- `ai_consent_at INTEGER NOT NULL DEFAULT 0`

**Rate limits** reuse `pair_attempts` through the existing `allowed(env, key, what, limit)`, with keys:

- `acct:<id>` (per account)
- `iph:<sha256(SESSION_SECRET+ip)[0:16]>` (a hashed IP, so no new raw IPs are stored)
- `global` (circuit breaker)

**Retention** runs as a new daily cron:

- Delete `error_reports` that were resolved more than 365 days ago.
- Delete `support_messages` older than 365 days.
- Delete `pair_attempts` rows with `hour < now/3600 - 48`.
- Keep the last 50 `bench_runs` per (kind, dataset). This is pruned on insert.

---

## 2. Worker: modules, routes, shapes, auth

### New server files

- **`server/owner.js`** holds the owner helpers. Group B's group-code creation should use the same file.
  - `keyMatches(request, key)`: the constant-time compare taken from `isOwnerKey`, generalised.
  - `isOwnerAccount(env, id)`: `OWNER_ACCOUNT_IDS` includes the id, or `accounts.owner = 1`.
  - `ownerOnly(request, env, holder)`: returns `'key'`, the owner's account id, or null.
- **`server/trust.js`** holds reports, support, consent, `accountMe`, `forgetTrustData(env, id)` and the cron `purge(env)`.
- **`server/web.js`** holds `webRoute(request, env, path)` for GET/HEAD and `supportForm(request, env)` for form POSTs. It exports a `ROUTES` map that group A adds `/s/<id>` to.
- **`server/legal/content.js`** holds the legal text as data: `{ en: {privacy, terms, medical, support}, ar: {...} }`. Each section is `{h, p:[...]}` with tokens `{{APP}} {{EFFECTIVE}} {{PROCESSORS}} {{SELLER}}`. It also exports `LEGAL = { privacy: 1, terms: 3, aiConsent: 1, effective: '2026-10-01' }`. `terms: 3` is deliberately equal to the app's `RecordingTerms` version.
- **`server/bench/summary.mjs`** is pure: `summariseAccuracy(results, meta)` and `summariseCheckers(results, meta)`. It reuses `wilson` and `score`.
- **`server/bench/publish.mjs`** is a CLI: `node server/bench/publish.mjs <accuracy|checker> <dataset> <results.json>`. It POSTs using env `WORKER` and `BENCH_KEY`.

### `worker.js` changes (small hooks only; other jobs are editing this file)

- Before the `POST only` line:
  - `if (request.method === 'GET' || request.method === 'HEAD') return await webRoute(request, env, path);` (unknown path gives an HTML 404)
  - `if (path === '/support' && request.method === 'POST') return await supportForm(request, env);` (form-urlencoded, capped at 8 KB, placed before the JSON parse)
- New switch cases: `/reports`, `/reports/mine`, `/reports/review/list`, `/reports/review/update`, `/reports/review/stats`, `/support/message`, `/support/review/list`, `/support/review/update`, `/account/me`, `/account/consent`, `/bench/publish`.
  - `/bench/publish` gets a 64 KB body cap in the size ladder. Everything else stays at 2 MB, and `/reports` gets a 32 KB cap.
- `session()` adds `owner: !!(account.owner === 1 || ownerIds.includes(account.id))`.
- `deleteAccount()` calls `forgetTrustData(env, id)`:
  - `UPDATE error_reports SET account_id = NULL, note = NULL WHERE account_id = ?`
  - `DELETE FROM support_messages WHERE account_id = ?`
- Consent enforcement goes on the cloud routes (`/v1/chat/completions`, `/jobs`, `/tts`, `/transcribe/chunk`). Only for bearer sessions (never the owner key), and only when `env.AI_CONSENT_ENFORCED === 'on'`:
  - If `ai_consent < LEGAL.aiConsent`, return `428 {error, message, code:'ai_consent_required'}`.
  - It stays `off` until the consenting build has shipped. That way old builds don't break, and the flag can later come from group D's remote config.
- `export default { fetch, scheduled }`: `scheduled` calls `purge(env)`. Group E should add its jobs through the same dispatcher.

### `wrangler.toml` additions

- `[vars]`:
  - `REPORTS = "on"`
  - `AI_CONSENT_ENFORCED = "off"`
  - `LEGAL_SELLER = ""` (empty means "the developer shown as seller on the App Store page")
  - `GEMINI_BILLING` (read if it already exists, to word the policy truthfully)
- `[triggers] crons = ["23 3 * * *"]` (the free plan allows up to 5).

### `worker-deploy.yml` additions

- Add the four new ALTER columns.
- Derive a least-privilege bench key alongside the owner key, the same way it is done today:
  `printf 'cramdown-bench:%s' "$AI_API_KEY" | sha256sum | cut -c1-64 | $W secret put BENCH_KEY`
  No new owner secret is needed.
- Add `trust.test.mjs` and `web.test.mjs` to "Tests first".

### Routes

All errors use the existing `{error, message}` shape plus a stable `code` the app can localise.

| Route | Auth | Request | Response |
|---|---|---|---|
| `POST /reports` | Bearer access | `{id: uuid, reason, note?, item:{kind, setId?, itemId?, shareId?, origin?, model?, source?, snapshot:{prompt, options?[≤10×500], correctIndex?, answer?, explanation?, extra?}}, app:{version, build, locale}}` | `201 {ok, id}`; `200 {ok, id, duplicate:true}` for a same-id retry or the same fingerprint from the same account within 24 h; `400 code:bad_report`; `413`; `429 code:too_many_reports`; `503 code:reports_off` |
| `POST /reports/mine` | Bearer | `{since?: epoch}` | `{reports:[{id, createdAt, reason, itemKind, itemId, setId, status, ownerNote, correction, resolvedAt}]}` (≤100, newest first, only `account_id = caller`) |
| `POST /reports/review/list` | owner account or OWNER_KEY | `{status?='open', reason?, kind?, model?, before?: createdAt, limit?≤100}` | `{reports:[full row + snapshot parsed + sameCount (rows sharing the fingerprint)], next}` |
| `POST /reports/review/update` | owner | `{id, status, ownerNote?≤1000, correction?:{correctIndex?0..9, explanation?≤6000, answer?≤4000}, alsoMatching?:bool}` | `{ok, updated}`. `alsoMatching` applies the same resolution to every open row with the same fingerprint. |
| `POST /reports/review/stats` | owner | `{}` | `{open, last7d, byReason:{}, byKind:{}, byModel:{m:{open,total}}, supportOpen}` |
| `POST /support/message` | Bearer | `{topic, body, replyTo?}` | `{ok, id}` / 429 |
| `POST /support` (form) | none | `topic, body, reply_to, website` (honeypot) | 303 to `/support?sent=1` |
| `POST /support/review/list`, `/support/review/update` | owner | like the reports routes | |
| `POST /account/me` | Bearer | `{}` | `{userId, owner, termsVersion, aiConsent, legal:{privacy, terms, aiConsent, effective}}` |
| `POST /account/consent` | Bearer | `{termsVersion?: int, aiConsent?: int}` (0 withdraws) | `{ok}`. Versions are clamped to ≤ `LEGAL.*`. |
| `POST /bench/publish` | `BENCH_KEY` or `OWNER_KEY` | `{kind, dataset, runId, commit?, ranAt, summary}` | `{ok, id, url:'/accuracy'}`. Idempotent on id. |
| `GET /privacy`, `/terms`, `/medical`, `/support`, `/accuracy` | public | `?lang=en\|ar`, otherwise Accept-Language | HTML with `<html lang dir>` |
| `GET /accuracy.json` | public | | `{updated, accuracy:{medqa: latest summary, history:[{ranAt, shown:{k,n,lo,hi}}]}, checker:{medqa, medxpertqa}}` |
| `GET /legal.json` | public | | `{privacy, terms, aiConsent, effective, urls:{…}}` |

### Validation details for `/reports`

- **Format and enums:** `id` must match `^[0-9a-f-]{36}$`. Enums are whitelisted. Strings have control characters stripped and are truncated.
- **Size and shape:** the snapshot is rebuilt server-side from whitelisted fields only (never stored as sent), must be ≤16 KB after JSON encoding, and gets `fingerprint = sha256(kind + prompt + options.join + correctIndex + answer)`.
- **Same id, different account:** if the id already exists under another account, return `200 {ok, id, duplicate:true}` without revealing anything.
- **Limits:**
  - 20 per account per hour
  - 200 open reports per account (409 `code: too_many_open`)
  - a global cap of 600 per hour
- **Takedown:** when the reason is `offensive` and `shareId` is present, call `env.onShareReported?.(shareId)`. This is group A's takedown hook, used for guideline 1.2.

### `/bench/publish` validation

The server never trusts client percentages. It accepts only counts and recomputes the Wilson intervals itself.

```js
// accuracy
{ dataset:'medqa'|'medxpertqa', questions:int≤5000, seed:int,
  shown:{k,n}, raw:{k,n}, specificity:{k,n}, catchWithLecture:{k,n}, catchByKnowledge:{k,n},
  withheld:{k,n}, evidenceFound:{k,n}, target:0.5..1, models:{ /^[\w.:@\/-]{1,80}$/: int } }
// checker
{ dataset, rows:[{ model:/^[\w.:@\/-]{1,80}$/, questions:int, specificity:{k,n},
  catchWithLecture:{k,n}, catchByKnowledge:{k,n}, medianMs:int }] ≤ 30 }
```

- Integers must satisfy `k ≤ n`.
- The verdict (`pass | not_proven | fail | none`) is computed server-side with the same rule as `accuracy.mjs`.
- **No question stems or model answers are published.** This keeps the page small, avoids republishing dataset content, and avoids publishing wrong medical statements.

### Web pages (`web.js`)

- One `layout({title, lang, body})`. System fonts only. Light and dark via `prefers-color-scheme`, `max-width: 42rem`, and a language switch link. All interpolation goes through `esc()`.
- **Headers:**
  - `content-type: text/html; charset=utf-8`
  - `cache-control: public, max-age=300`
  - `vary: accept-language`
  - `content-security-policy: default-src 'none'; style-src 'unsafe-inline'; img-src data:; form-action 'self'; base-uri 'none'; frame-ancestors 'none'`
  - `x-content-type-options: nosniff`
  - `referrer-policy: no-referrer`
- No scripts and no cookies. HEAD gets the same headers with no body.
- **`{{PROCESSORS}}` is built from `env`,** so the policy always matches what is deployed:
  - Always: Cloudflare (hosting, D1, R2, Workers AI including Deepgram Aura voices), Apple (sign-in, purchases), Europe PMC/NLM/openFDA (search terms only).
  - Google Gemini via Firebase if `FIREBASE_API_KEY` is set.
  - Novita if `AI_WRITER_KEY` is set.
  - Hugging Face if `AI_API_KEY`, `AI_DOCTOR_URL` or `AI_MEDVAL_URL` is set.
  - Google Sign-In if `GOOGLE_CLIENT_ID` is set.
  - The Gemini paragraph states the tier truthfully. When not billing: "on Google's free tier Google may use this content to improve its products and human reviewers may read it". When billing: "not used to improve Google's products".
- **`/accuracy`:**
  - Headline "Accuracy of answers a student would see": k/n, percentage and 95% CI, the verdict against the target, the date and the question count.
  - A table of the parts, the checker comparison per dataset, and an inline SVG of shown-accuracy with its CI over the last 20 runs (bars with whiskers, no JS).
  - Method text: MedQA/MedXpertQA test split, fixed seed, checked through the deployed worker, what "shown" means.
  - Always the caveat: "a measurement on exam-style questions, not a guarantee; Vignette is for study, not clinical decisions".
- **`/support`:** a form with topic, message, an optional email and a hidden honeypot. It shows "Report an error from inside the app for question problems". Limits are 3 per hour per hashed IP and 100 per hour globally.

### Privacy policy sections (content outline)

1. Who we are, with `{{SELLER}}` and contact via `/support`.
2. What we collect:
   - Account: provider id, email or name if the provider gives them.
   - Purchase ids.
   - Synced library (Pro).
   - Lecture text, audio and prompts sent for generation, transcription or voice.
   - Error reports and support messages.
   - Diagnostics and opt-in usage counters (group E).
   - Leaderboard name and stats, opt-in (group A).
   - Shared sets (group A).
3. What stays on the device: recordings, pronunciations, and everything when cloud AI is declined.
4. Third-party AI and processors (`{{PROCESSORS}}`, per 5.1.2(i)).
5. Retention: library until deletion; jobs 7 days; reports anonymised on account deletion and removed 1 year after resolution; support messages 1 year; rate-limit counters 48 h.
6. No tracking, no ads, no data sale, no third-party SDKs.
7. Rights (GDPR/UK GDPR/Egypt PDPL 151/2020): access, deletion (in-app Delete account), objection; contact form.
8. Age: the app is for university students; cloud AI features need age 18+ (Gemini API terms).
9. **Do not enter information that identifies a real patient.**
10. Changes and version; the English text prevails over translations.

### Terms outline

- Our Terms supplement Apple's Standard EULA; Apple's EULA governs the licence.
- Eligibility: 16+, and 18+ for cloud AI.
- **Education only, not medical advice or clinical decisions.** AI output can be wrong.
- No patient-identifiable data.
- Recording consent (the existing gate text).
- Your content and the licence needed to process it.
- Subscriptions are billed by Apple (auto-renew, cancel in Settings, refunds via Apple). Offer, referral and group-licence rules (group B).
- Shared sets, class groups and leaderboards: acceptable use and takedown (group A).
- The accuracy page is not a warranty. Limitation of liability, termination, changes, contact.

`/medical` is the full education notice.

---

## 3. App side (paths under `ios/RedPen`)

### New files that import only Foundation (testable on the Mac runner)

- **`Shared/LegalLinks.swift`:** `enum LegalLinks { static func url(_ page: Page, base: URL = AuthAPI.baseURL, language: String = AppLanguage.current.code) -> URL }` with `Page = privacy|terms|medical|support|accuracy`. It adds `?lang=`. `AuthAPI.baseURL` is already Foundation-only.
- **`Shared/LegalTerms.swift`:**
  - Moves the logic out of `RecordingTermsView.swift`: `RecordingTerms.version = 3`, `accepted(by:)`, `accept(for:)`.
  - Adds `static func mustAsk(local: Int, server: Int?) -> Bool` so the gate re-asks if `/legal.json` reports a higher version.
  - Adds `enum CloudConsent { static let version = 1; enum State { unknown, granted(Int), declined }; static func mayUseCloud(_:) -> Bool; static func mustAsk(_:) -> Bool }`, stored in UserDefaults per account id.
- **`Shared/ErrorReport.swift`:**
  - `struct ErrorReport: Codable, Identifiable` mirrors the `/reports` body.
  - `enum Reason` has localised titles; `enum ItemKind`; `enum Origin`.
  - `static let limits`, identical to the server's.
  - `func validated() -> ErrorReport?` truncates exactly like the server.
  - Adapters: `ReportSnapshot.init(_ q: MCQQuestion)`, `init(_ c: AnkiCard)`, `init(_ c: QACard)`, `init(kind:prompt:answer:extra:)`.
  - `func fingerprint() -> String` (CryptoKit SHA-256). This is the same normalisation as the server, and it is also used to decide whether a correction may still be applied (the local item is unchanged since it was reported).
- **`Shared/ReportOutbox.swift`:**
  - A pure queue: `enqueue`, `due(now:)` with backoff of 1 min, 5 min, 30 min, 3 h, then 12 h; `markSent`; `drop` for items older than 30 days; a cap of 200 items.
  - File I/O in `redpen-report-outbox.json` (injectable URL, like the other stores).
  - Also keeps "sent ids" so `/reports/mine` results can be matched.
- **`Shared/TextDirection.swift`:** `static func dominant(_ text: String) -> Direction`. It counts strong RTL scalars (Arabic, Hebrew) against strong LTR ones, ignoring digits and punctuation. `isolated(_:)` wraps text in FSI…PDI so English drug names don't reorder inside Arabic sentences.
- **`Shared/AppLanguage.swift`:** `enum AppLanguage: String { system, en, ar }`.
  - `static func resolve(choice:preferred:) -> (code, isRTL)` uses `Bundle.preferredLocalizations(from:["en","ar"], forPreferences:)`.
  - `static var current`, persisted with `@AppStorage("vignette.language")`.
- **`Shared/ServerMessages.swift`:** maps a server `code` to a `String(localized:)`, falling back to the server's English message.

### New SwiftUI files

- **`Shared/PlaygroundsLocalization.swift`** (`#if SWIFT_PACKAGE` only):
  - A `LanguageBundle: Bundle` subclass whose `localizedString(forKey:value:table:)` first checks `<lang>.lproj` inside any of `AppResources.bundles`, then falls back to `super`.
  - `install(language:)` calls `object_setClass(Bundle.main, LanguageBundle.self)`. `RedPenApp.init()` calls it before any view is built.
  - This is needed because in Playgrounds `Bundle.main` may not contain the `.lproj` folders, so the app would otherwise run in English with left-to-right layout.
- **`Features/Support/ReportErrorSheet.swift`:**
  - Reason chips, an optional note (1,000-character counter), and "What will be sent" (a read-only preview of the snapshot; the lecture is never sent).
  - The warning "Don't include anything that identifies a patient".
  - Send puts the report in the outbox and flushes it. The sheet shows "Thanks, we'll review it" when online or "Will send when you're online" when offline.
- **`Features/Support/MyReportsView.swift`:**
  - Status for each report, plus the owner's note.
  - When a `correction` exists and the local item's fingerprint still matches, an **Apply correction** button that edits the item through `Store`.
- **`Features/Support/ReportsReviewView.swift`** (owner only):
  - A segmented Reports / Support control and status filters.
  - A stats header: open count, top reasons, and the models with the most open reports.
  - Rows rendered with `Text(verbatim:)` only, never Markdown.
  - Detail view with the snapshot and the "N students reported this" count.
  - Actions: Fixed, Won't fix, Duplicate, Spam. Owner note, a correction editor (for MCQ: pick the correct option and edit the explanation), "Apply to all matching", and "Open set" if the set is in the owner's own library.
- **`Features/Support/AboutLegalPage.swift`:** the medical notice (full text), links to Privacy, Terms, "How accurate is it?" (`/accuracy`) and Support, "Your reports", Licences, and the language picker. Pages open in an `SFSafariViewController` wrapper (SafariServices is available in Playgrounds).
- **`Features/Account/CloudAIConsentView.swift`:**
  - Names each provider actually used: Google Gemini, Cloudflare Workers AI, Hugging Face, and Novita if it is on. The list comes from `/legal.json` → `processors`.
  - Says what is sent (lecture text, your answers, audio for transcription), the free-tier review/training wording for Gemini, "18 or older", and "no patient-identifiable information".
  - Buttons: **Allow cloud AI** and **Keep everything on this device**. The on-device path uses Foundation Models (group D), Doctor-R1/MedVAL on-device, or Gemma.
- **`Shared/CloudGate.swift`** (`@MainActor @Observable`):
  - `func ensureConsent() async -> Bool` suspends on a continuation until a root-level sheet (`.cloudConsentSheet()` on the WindowGroup content) is answered. It records locally and POSTs `/account/consent`.
  - It is called at the top of `HostedLLMClient`, `CloudTranscriber`, `CloudVoice` and `CloudJobs` request paths. Declining throws `CloudConsentError.declined`, which the existing callers already surface as a failed generation, with the message "Cloud AI is off. Turn it on in Settings, or use the on-device model."
- **`Features/Support/EducationNotice.swift`:**
  - `EducationFootnote()` is one line: "For study only, not for clinical decisions. AI can be wrong." It links to `/medical`.
  - `.simulatedPatientBanner()` is for case screens.
- **`ReportStore`** (`@Observable`, in `Shared/ReportStore.swift`) owns the outbox, `flush(token:)`, `mine(token:)`, and the owner review calls (via `Shared/ReportsAPI.swift`, which wraps `AuthAPI.send`). There is no debug stub. UI tests use the launch argument `-reportsDryRun`, which makes `ReportsAPI` succeed locally.
- **Resources:**
  - `Localizable.xcstrings` (source language en, plus ar).
  - `InfoPlist.xcstrings` (Arabic `CFBundleDisplayName`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`).
  - `PrivacyInfo.xcprivacy`:
    - `NSPrivacyTracking` is false.
    - Accessed API types: UserDefaults `CA92.1` (20 files use `@AppStorage`/UserDefaults), File timestamp `C617.1` (`contentModificationDate` in `NarrateVoice`, `attributesOfItem` in `GemmaModel`/`MedicalModelCatalog`).
    - `NSPrivacyCollectedDataTypes` matches the table in section 5.

### Changed files (minimal hooks; coordinate with the other jobs editing these)

- **`Shared/Theme.swift`:**
  - `AccuracyAsk` gains `var report: (() -> ReportTarget?)? = nil`, where `ReportTarget = {kind, setId, itemId, origin, model, source, snapshot}`.
  - `StudyMoreMenu` adds `Label("Report an error", systemImage: "exclamationmark.bubble")` with `.accessibilityIdentifier("reportError")` and a `.sheet(item:)` that presents `ReportErrorSheet`.
- **Report targets per screen:**
  - Supply `report:` in `MCQQuizView` (current question), `AnkiReviewView` (current card), `QACardsView`, `OsceReviewView`, `BookReaderView` (page text, kind `book`), `NarrateReviewView`.
  - Add the menu item directly in `CaseChatView` and `ClueCaseView`, which have their own toolbars.
  - Add a context-menu "Report an error" on each question row in `MCQSummaryView` and on cards in `DueTodayView`.
  - `origin` and `model` come from the set's generation metadata where the set records it. Otherwise `origin = typed` or `imported`.
- **`Features/Account/RecordingTermsView.swift`:**
  - Version 3, logic moved to `LegalTerms.swift`.
  - New first point: "For study, not for patient care. Vignette uses AI to write practice material from your lectures. It can be wrong. Never use it to diagnose, treat or decide anything about a real patient. Check against your lecture, current guidelines and your teachers."
  - New point: "Don't enter information that identifies a real patient."
  - The cloud-transcription point now refers to the cloud AI choice.
  - A footer with "Terms · Privacy" links.
  - On accept, POST `/account/consent {termsVersion:3}` in the background.
- **`Features/Paywall/PaywallView.swift`:**
  - Replace the `redpen.app` links with `LegalLinks.url(.terms)` ("Terms of Use (EULA)") and `.privacy`.
  - Add `EducationFootnote()`.
  - If group B moves to `SubscriptionStoreView`, pass the same URLs via `.subscriptionStorePolicyDestination(url:for: .termsOfService)` and `.privacyPolicy`.
- **`Features/Auth/SignInView.swift`:** footer "By continuing you agree to the Terms and Privacy Policy", with links.
- **`Features/Support/SupportCenter.swift`:**
  - `SupportPage` gains `.about` ("About & legal", in the account section) and `.reports` ("Reports", shown only when `account.account?.owner == true`, with an open-count badge from `/reports/review/stats`).
  - `SettingsPage` gains a Language row and a "Cloud AI" toggle (withdraw or grant; shows providers).
    - Xcode build: the Language row opens `UIApplication.openSettingsURLString`, which is iOS's per-app language setting.
    - Playgrounds build: an in-app picker that relaunch-prompts.
  - `FAQPage` gains: "Is this medical advice?", "Where does my lecture go when I use cloud AI?", "How accurate is it?" (link).
  - Every `title: String` becomes `LocalizedStringResource`, or is wrapped in `String(localized:)`.
- **`Features/Auth/AccountView.swift`:** the delete footer adds "Your error reports are kept without your name or note". Adds a "Your reports" row.
- **`Models/Account.swift`:**
  - Add `var owner: Bool?`. It **must be Optional**, or a custom `init(from:)` with `decodeIfPresent` is needed. Synthesised Decodable ignores default values, so keychain sessions saved before this change would fail to decode and sign everyone out.
  - Add `var isOwner: Bool { owner == true }`.
- **`Shared/AuthAPI.swift`:**
  - `SessionResponse.owner: Bool?`.
  - `Failure.server` carries an optional `code`, and messages resolve through `ServerMessages`.
  - Add `me(token:)` and `consent(token:terms:ai:)`.
  - Refresh `owner` via `/account/me` on launch, since older sessions lack it.
- **`RedPenApp.swift`:**
  - Inject `ReportStore` and `CloudGate`.
  - `PlaygroundsLocalization.install` in `init` (package build only).
  - Root modifiers `.environment(\.locale, …)` and `.environment(\.layoutDirection, …)`, applied **only** when the in-app language override is set (the Playgrounds build). The Xcode build leaves this to the system.
  - `.cloudConsentSheet()` at the root.
  - On `.active`: `reports.flush`, and a `/reports/mine` refresh at most daily.
- **`ios/project.yml`:**
  - `options.developmentLanguage: en`.
  - Info additions: `CFBundleDevelopmentRegion: en`, `CFBundleLocalizations: [en, ar]`.
  - Build settings: `LOCALIZATION_PREFERS_STRING_CATALOGS: YES`, `SWIFT_EMIT_LOC_STRINGS: YES`.
  - `.xcstrings` and `.xcprivacy` are picked up automatically from the `RedPen` sources path, so no other target changes are needed for group F.
- **`make_swiftpm.py`** (in the scratchpad, used for the owner's Playgrounds build):
  - Add `"*.xcstrings", "*.xcprivacy"` to `ignore_patterns`.
  - New function `catalog_to_lproj(xcstrings, out_resources)`:
    - Writes `Resources/en.lproj/Localizable.strings` and `Resources/ar.lproj/Localizable.strings` (UTF-8, escaped `"` and `\n`).
    - Writes `ar.lproj/Localizable.stringsdict` for keys with `variations.plural`. Arabic needs all six categories: zero, one, two, few, many, other. The format key is `%#@v@` with `NSStringFormatValueTypeKey` taken from the specifier (`lld`, `@`).
    - Missing Arabic falls back to English by leaving the key out.
    - Also does the same for `InfoPlist.xcstrings` → `InfoPlist.strings`. This is best effort; the Playgrounds purpose strings stay English in `capabilities:`.
  - Manifest changes: `Package(name:, defaultLocalization: "en", platforms: …)` and `resources: [.copy("Samples"), .process("Resources")]`.

### Xcode build vs Playgrounds build (group F)

| Area | Xcode / App Store build | Playgrounds build |
|---|---|---|
| Report an error, My reports, owner review | Full | Full (same code) |
| Legal pages, notices, consent | Full | Full |
| Arabic strings | Compiled String Catalog | Generated `.lproj/.strings(dict)` plus `LanguageBundle` shim |
| App language choice | iOS Settings, per-app language | In-app picker; root `locale`/`layoutDirection` override |
| Arabic permission prompts | `InfoPlist.xcstrings` | English only (manifest `purposeString`) |
| Privacy manifest | Shipped | Not applicable (never submitted) |

### RTL audit rules (one pass after the strings are wrapped)

- Replace `chevron.right/left` and `arrow.right/left` with the `.forward/.backward` variants.
- Replace `.left/.right` alignment and `offset(x:)` used for direction with `.leading/.trailing`. There are 52 hits to review.
- **Force `.environment(\.layoutDirection, .leftToRight)`** on image-plus-overlay containers: occlusion boxes (`ImageSpoiler`, `OcclusionFilter` editors, `PDFOcclusion` views, `FigureGrid` hotspots), `Graph3DView` and `IdeaBoardView` canvases, and drawing canvases (`DrawRecallView`). Otherwise the covers mirror away from the labels.
- Content blocks such as card text, stems and explanations get `.environment(\.layoutDirection, TextDirection.dominant(text) == .rtl ? .rightToLeft : .leftToRight)`. English lecture content stays left-to-right inside an Arabic UI.
- MCQ option letters stay Latin A–E. Counts use `.formatted()` so they follow the locale's digits. Timers use `.monospacedDigit()`.
- PDF export (CoreGraphics/CoreText) keeps English labels in v1. This is noted in the FAQ.
- **Must not be localised:** LLM prompt strings (`Shared/LLM/*`, `MCQPrompt`, `Reasoning/*Writer`, `LectureWriter`, `MCQGenerator`'s `@Guide` descriptions). They stay plain `String`. The lint excludes those paths.

---

## 4. Localisation pipeline (no owner steps)

1. **Wrap strings in waves.**
   - Wave 1 (launch-critical): terms gate, sign-in, consent, paywall, library chrome, study-screen chrome and menus, Settings, About, Account, error messages, report sheet.
   - Wave 2: all remaining Features.
   - Conversions: `Text(stringVar)` becomes `Text(LocalizedStringKey)`, or the property type changes to `LocalizedStringResource`. Ternary plurals such as `"deck\(n == 1 ? "" : "s")"` become `String(localized: "\(n) decks")` with plural variations in the catalog.
2. **`tools/l10n_lint.py`** fails CI on:
   - `Text(`/`Button(`/`Label(`/`.navigationTitle(` given a non-literal `String` outside the allowed list;
   - string concatenation of literals in user-facing files.
   It excludes the prompt paths above.
3. **`.github/workflows/localize.yml`** (macOS, `workflow_dispatch` plus weekly):
   - `xcodegen`, then `xcodebuild -exportLocalizations -project RedPen.xcodeproj -localizationPath out -exportLanguage ar`.
   - `node tools/translate_xliff.mjs` sends only untranslated units, in batches of 40, to the deployed worker's `/v1/chat/completions` with the owner key (the existing free-tier chain, so no cost).
     - It uses the glossary `ios/RedPen/L10n/glossary-ar.tsv`: MCQ, OSCE, USMLE, PLAB, MRCP, Anki, Pro, Vignette and drug/disease names stay Latin; Egyptian medical-school usage is preferred.
     - It **rejects** any translation whose format specifiers or `%#@…@` tokens differ from the source.
   - `xcodebuild -importLocalizations`. Units are written with state `needs_review` so ambassadors (group G) can review them later.
   - Commit `Localizable.xcstrings` to branch `l10n-ar` and open a PR with auto-merge once `swift-tests` and `app-build` pass.
4. **`tools/l10n_check.py`** runs in `swift-tests.yml` on the Mac runner:
   - Parses the catalog. Every Arabic value has the same specifiers as English, Arabic plurals have all six categories where the English has variations, and there are no empty values. It reports Arabic coverage.
   - `CFBundleLocalizations` keeps `ar` only if wave-1 keys are 100% covered. The check fails otherwise. This avoids advertising Arabic with a half-English first run.
   - Runs `catalog_to_lproj` into a temp directory and runs `plutil -lint` on the output.
5. **`app-build.yml`** gains a post-build assertion that `…/RedPen.app/ar.lproj/Localizable.strings` exists and contains `"Report an error"`. This confirms that `needs_review` values are compiled in, rather than assuming it.

---

## 5. App Store Review risks for F and how to stay compliant

| Rule | Risk | Mitigation in this design |
|---|---|---|
| **1.4.1** medical apps (heightened scrutiny) | Claims of accuracy; AI medical content | Education-only positioning everywhere: gate v3, footers, `/medical`, Terms §3, description. The accuracy page shows intervals and method. **Never** put an unqualified "98% accurate" in metadata. |
| **Regulated medical device status** (since Mar 2026; for the Medical category or frequent medical-info age rating) | Submission blocked without it | Owner declares **not a regulated medical device** for EEA/UK/US. Primary category Education. |
| **5.1.1(i)** privacy policy | Needed in App Store Connect and inside the app | `/privacy` (en/ar), linked from sign-in, paywall, About and Settings. |
| **5.1.2(i)** third-party AI (Nov 2025) | Lecture text, audio and answers go to Gemini, Workers AI, HF or Novita | `CloudAIConsentView` before the first transmission, providers named, decline path on-device, withdrawal in Settings. Server enforcement flag. |
| Gemini API terms (not Apple, but binding) | Unpaid tier: training and human review; not for apps aimed at under-18s; no clinical use | Consent text states it. Cloud AI needs 18+ (confirmation in consent). Terms forbid patient data and clinical use. Enabling billing moves Gemini to paid-tier data terms; that decision belongs to group B/D. |
| **3.1.2** subscriptions | Terms/EULA and privacy links in the purchase flow and metadata | Fix the `redpen.app` links. Worker URLs in the paywall and `SubscriptionStoreView` policy destinations. The description ends with the Terms link. |
| **2.3 / 2.3.1** accurate metadata | Accuracy numbers or Arabic claims that don't match the app | Numbers only with a link to `/accuracy`. Arabic is declared only when the wave-1 coverage gate passes. |
| **1.2** user-generated content (group A shares, class sets, leaderboards) | Must be able to report, filter, block and contact | "Report an error" with reason `offensive` plus `shareId` → group A takedown hook. Owner review list with badge. `/support`. |
| **1.5** developer info | Support URL must reach real contact | `/support` form. No personal mailbox is exposed. |
| **5.1.1(v)** account deletion | New server data must go with the account | `forgetTrustData`: reports anonymised (note removed), support messages deleted. Policy says so. |
| **5.1.1(ix)** highly regulated fields such as healthcare should come from a legal entity | A reviewer might treat a medical app from an individual as a healthcare service | It is education, not a healthcare service: no patient data, no clinical function, disclaimers. Say this in the review notes. **Flag:** if rejected on this, the fallback is an organisation developer account (group G launch checklist). |
| Privacy nutrition labels vs privacy manifest vs policy | Mismatches cause rejection | One table drives all three (below). |

**Privacy label table.** None of the data is used for tracking.

| Data | Linked to the user? | Purpose |
|---|---|---|
| Contact info (name/email, only if the provider gives them) | Linked | App functionality |
| User ID | Linked | App functionality |
| Purchase history (transaction id) | Linked | App functionality |
| Other user content (synced library, lecture text or audio for generation, error reports, support messages) | Linked | App functionality |
| Crash and performance data (group E) | Not linked | Analytics / app functionality |
| Product interaction (opt-in counters, group E) | Not linked | Analytics |

---

## 6. Security and privacy

- **Auth:**
  - Reports, consent and `/account/me` use the existing `holder()` path, so revocation via `signed_out_before` applies.
  - Review routes use `ownerOnly`: an owner account or `OWNER_KEY`.
  - Bench publish uses the narrow `BENCH_KEY` (or `OWNER_KEY`), compared in constant time.
- **Abuse limits:**
  - 20 reports per account per hour; 200 open per account; 600 per hour globally.
  - Fingerprint dedupe within 24 h.
  - Support form: 3 per hour per hashed IP, 100 per hour globally, plus a honeypot.
  - Bench publish: 30 per hour.
  - All counters use existing D1 tables. There is no raw-IP storage for new features.
- **Injection:**
  - Server-side whitelisting and rebuilding of snapshots.
  - Web pages never render report text.
  - The owner app renders with `Text(verbatim:)`.
  - Web pages escape everything, have a strict CSP, and no JS or cookies.
- **IDOR:**
  - `/reports/mine` is filtered by the caller.
  - Client ids are validated. A collision with another account's id reveals nothing.
- **Data minimisation:**
  - A snapshot is the item only, never the lecture.
  - The note is optional and removed on deletion.
  - The sheet previews exactly what is sent.
  - Patient-identifiable data is prohibited, with a warning in the sheet.
- **Owner audit:** `resolved_at` is set on every change. The owner note is shown back to the reporter, so the review UI warns: "Visible to the student".

---

## 7. Tests

### Server

- **`server/tests/trust.test.mjs`** uses the `node:sqlite` harness from `pair.test.mjs`, going through `worker.fetch`. It covers:
  - Report create returns 201; retrying the same id returns `duplicate`.
  - A snapshot with extra fields is stripped; oversized fields are truncated; a bad enum or id returns 400; an oversized body returns 413.
  - Per-account hourly limit returns 429; the open cap returns 409; `REPORTS=off` returns 503.
  - `/reports/mine` returns only the caller's rows.
  - Review list, update and stats return 404/401 for non-owners and work for an `owner=1` account, an `OWNER_ACCOUNT_IDS` account and `OWNER_KEY`. `alsoMatching` resolves all rows with the same fingerprint.
  - The correction is validated and returned by `/reports/mine`.
  - `/account/delete` nulls `account_id` and `note` and deletes support messages.
  - Consent: 428 `ai_consent_required` on `/v1/chat/completions` only when the flag is on and consent is below the current version; the owner key bypasses; `/account/consent` clamps versions.
  - `session()` includes `owner`.
  - `scheduled()` purge removes old resolved reports, old counters and old support messages.
- **`server/tests/web.test.mjs`** covers:
  - GET `/privacy`, `/terms`, `/medical`, `/support` return 200, with `lang="en"` or `lang="ar" dir="rtl"` from `?lang` and from `Accept-Language`.
  - The CSP and nosniff headers are present; HEAD has no body; an unknown GET returns 404 HTML; existing POST routes are unchanged (for example `/sync/changes` still 401/402).
  - The processor list follows `env` (Novita appears only with `AI_WRITER_KEY`; the Gemini tier wording follows `GEMINI_BILLING`).
  - Escaping: a model name with `<script>` is rejected at publish.
  - Support form: the honeypot drops silently with a 303; limits apply.
  - `/bench/publish`: 401 without a key; accepts `BENCH_KEY` and `OWNER_KEY`; rejects `k > n` and non-integers; recomputes CI and verdict server-side (a client-sent `lo` is ignored); idempotent on run id; prunes to 50.
  - `/accuracy` shows the latest summary and history; `/accuracy.json` has the expected shape; `/legal.json` versions equal `LEGAL`.
- **`server/tests/bench.test.mjs`** (extend): `summariseAccuracy` and `summariseCheckers` produce the counts the report tables show for a fixed results fixture.
- **Wiring:** add both new files to `server-tests.yml` and the deploy "Tests first" line.

### CI publishing of benchmark results

- **`accuracy-bench.yml`:** add a step `if: success()` that runs `node server/bench/publish.mjs accuracy medqa out/accuracy-report.json`, only when the result count is at least 100. `BENCH_KEY` is derived as `printf 'cramdown-bench:%s' "$AI_API_KEY" | sha256sum | cut -c1-64`.
- **`checker-bench.yml`:** add the same step per dataset after each run. Results are cumulative.

### Swift (in `swift-tests.yml`)

```
suite trust TrustTests.swift $M/MCQQuestion.swift $M/Differential.swift $M/AnkiCard.swift $M/QACard.swift \
      $S/ErrorReport.swift $S/ReportOutbox.swift $S/LegalTerms.swift $S/LegalLinks.swift $S/AuthAPI.swift \
      $M/Account.swift $S/AuthRules.swift
suite language LanguageTests.swift $S/AppLanguage.swift $S/TextDirection.swift $S/ServerMessages.swift
```

Check that `AuthAPI.swift` compiles on its own. If it pulls in `JSONEncoder.sync` from another file, add that file or pass `base:` explicitly and drop `AuthAPI` from the suite.

- **`TrustTests`:**
  - Snapshot adapters for MCQ, Anki and QA; limits and truncation equal to the server's.
  - Fingerprint is stable across whitespace and changes when the correct index changes.
  - Outbox backoff schedule, 30-day drop, 200 cap, file round-trip.
  - `RecordingTerms` v3 re-asks after v2; `mustAsk(local:server:)`; `CloudConsent` states.
  - `LegalLinks` adds `?lang=ar`.
  - `Account` decodes old JSON without `owner`. This is the regression guard for the Decodable issue.
- **`LanguageTests`:**
  - `AppLanguage.resolve` for `["ar-EG","en"]`, `["fr"]` and an explicit override.
  - `TextDirection.dominant` for pure Arabic, pure English, Arabic with English drug names, and digits only.
  - `ServerMessages` fallback.
- **UI tests:**
  - `ios/UITests/TrustUITests.swift`: open an example MCQ, tap More → `reportError`, pick a reason, Send with `-reportsDryRun`, see "Thanks". The terms gate v3 shows the education point.
  - `ios/UITests/ArabicLayoutUITests.swift`: launch with `-AppleLanguages (ar) -AppleLocale ar_EG`, assert the Arabic Settings title, attach screenshots of the library, MCQ, occlusion card and paywall. The occlusion screenshot guards the left-to-right override.
- **Python:** `tools/test_l10n.py` covers `catalog_to_lproj` (escaping, Arabic six-form stringsdict, English fallback) and `l10n_check`. It runs in `pipeline-tests.yml` on Ubuntu.

---

## 8. Build order (each step can ship on its own)

1. **F1 server:** `owner.js`, `trust.js`, `web.js`, legal content, schema, cron, deploy wiring, tests.
2. **F2 app legal:** `LegalLinks`/`LegalTerms`, gate v3, paywall and sign-in links (fixes the `redpen.app` links), About page, education footers, `Account.owner`, `/account/me`.
3. **F3 consent:** `CloudGate`, `CloudAIConsentView`, Settings toggle. Server flag stays off, then is switched on once the build is live.
4. **F4 reports:** model, outbox, API, sheet, menu hook, My reports, owner review.
5. **F5 accuracy:** `summary.mjs`, `publish.mjs`, workflow steps, `/accuracy` page, in-app link.
6. **F6 localisation:** infrastructure (catalog, `project.yml`, `make_swiftpm` conversion, shim, picker, lint and checks), then wave 1, the translation workflow, the RTL audit, wave 2.
7. **F7:** `PrivacyInfo.xcprivacy` and the label table in the launch checklist.

---

## 9. Owner's unavoidable publish-time steps for group F (App Store Connect only)

1. **App Privacy:**
   - Privacy Policy URL: `https://redpen-auth.vv7sh4rnnw.workers.dev/privacy`. For the Arabic localisation, use the same URL with `?lang=ar`.
   - Fill in the privacy label from the table in section 5. Tracking: **No**.
2. **App Information:**
   - Support URL: `…/support`. Marketing URL (optional): `…/accuracy`.
   - Primary category **Education**. Secondary **Reference** is recommended, because a Medical category adds scrutiny.
3. **Regulated medical device status:** declare **"not a regulated medical device"** for EEA, UK and US. This is required whenever the age rating answers frequent Medical or Treatment Information, which is the honest answer here.
4. **Age rating questionnaire:** Medical or Treatment Information → **Frequent**. Everything else as it is. Accept whatever rating App Store Connect computes.
5. **Add the Arabic localisation** to the listing and paste the group G metadata. Add Arabic display names for the subscriptions (group B).
6. **License agreement:** keep **Apple's Standard EULA**. The description (from group G) ends with "Terms of Use: …/terms" and "Privacy: …/privacy".
7. **EU Digital Services Act trader status:** declare it. If you are a trader, which is likely with paid subscriptions, Apple shows your address, phone and email on the EU product page. There is no way around this if the app is distributed in the EU. The alternative is to exclude EU storefronts at launch.
8. **App Review notes:** paste the text group G drafts. It covers:
   - that the app is education-only for medical students, not clinical;
   - where to find "Report an error" (More menu on any question);
   - the cloud AI consent screen and the on-device alternative;
   - that no login is needed ("Continue on this device");
   - that owner tools are hidden from normal accounts.

Optional, and not an App Store Connect step: to name yourself in the policy instead of "the seller shown on the App Store page", set `LEGAL_SELLER` through a new `worker-deploy.yml` input.

---

## Sources

- [Apple: regulated medical device status (developer news)](https://developer.apple.com/news/?id=nyqbfz1y)
- [MacRumors: medical device status requirement](https://www.macrumors.com/2026/03/26/app-store-medical-device-status/)
- [9to5Mac: medical device disclosure](https://9to5mac.com/2026/03/26/new-app-store-policy-requires-medical-device-disclosures-for-some-health-apps/)
- [Apple: updated age ratings](https://developer.apple.com/news/?id=ks775ehf)
- [Apple: age rating values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [Apple: updated App Review Guidelines, Nov 2025](https://developer.apple.com/news/?id=ey6d8onl)
- [TechCrunch: 5.1.2(i) third-party AI](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai)
- [Gemini API Additional Terms](https://ai.google.dev/gemini-api/terms)
- [Apple Developer Forums: Swift Playgrounds localisation](https://developer.apple.com/forums/thread/773855)
- [Elegant Chaos: String Catalogues in Swift Packages](https://elegantchaos.com/2026/02/12/string-catalogues.html)
- [Daniel Saidi: localising Swift packages with String Catalogs](https://danielsaidi.com/blog/2025/12/02/a-better-way-to-localize-swift-packages-with-xcode-string-catalogs)
