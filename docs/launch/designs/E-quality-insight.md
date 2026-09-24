> **Source design, feature group E** (architect output, 2026-09-24), copied verbatim.
> It is an input to [`../implementation-plan.md`](../implementation-plan.md). Where the two disagree, **the plan wins**:
> see the plan's section 2 (conflict resolutions) and the work package that implements this design.

# Feature group E design: quality and insight (MetricKit, opt-in usage counters, performance)

I read the existing code before designing: `worker.js` (a POST-only switch, `guarded`/`synced`/`proGate`, `holder`), `pair.js` (the `allowed()` hourly limiter), `ai.js` (`isPro`, `isOwnerKey`), `schema.sql`, `wrangler.toml`, `worker-deploy.yml`, `server-tests.yml`, `swift-tests.yml`, `project.yml`, `make_swiftpm.py`, `RedPenApp.swift`, `Store.swift`, `AuthAPI.swift`, `SupportCenter.swift` and `ipa.yml`. Every file path below is relative to the worktree root.

## 0. Facts that shape the design

- **MetricKit.** `MXMetricManager` works on iOS 26. Apple deprecated it in iOS 27 (WWDC26) in favour of the new Swift `MetricManager`, which has `diagnosticReports` and `metricReports` async sequences and Codable reports. The deployment target is iOS 26, so v1 uses `MXMetricManager` only. Deprecated does not mean removed, so it still delivers on iOS 27. The `MetricManager` path is phase 2 (§7).
- **MetricKit only delivers on devices where the user turned on Apple's "Share With App Developers".** Guideline 5.1.1(ii) also requires our own consent for any usage or diagnostic collection, even when it is anonymous. So E is double opt-in and volume will be low. Design for small numbers.
- **D1 free plan.** 50 queries per Worker invocation, 100 bound parameters per statement, 500 MB per database. Rows written per day is limited, and sync already shares that budget. Telemetry must cost about one row write per device per day, so raw reports are stored as a single JSON row and rolled up daily by a cron.
- **I rejected Workers Analytics Engine.** Reading it needs a Cloudflare API token with Analytics Read, which would be a new manual step for the owner. D1 plus `json_each` covers the need.
- **No app-side owner flag exists today.** There is `accounts.owner` and `OWNER_ACCOUNT_IDS` on the server, but the app has no flag. Group F needs one too (owner-only list of error reports), so I propose a shared one in §2.4.
- **Test harness limits.** The server tests' fake D1 supports only `prepare/bind/first/all/run`, and the schema loader splits on `;`. So: no `db.batch()`, no triggers, and no `;` inside SQL comments.
- **Existing code this can reuse.** Swift tests compile only Foundation-only files, so all decision logic goes in Foundation-only files, with thin MetricKit and SwiftUI wrappers around it. `#if SWIFT_PACKAGE` is already used and tells a Playgrounds build apart.

## 1. D1 data model (append to `server/schema.sql`)

None of these tables has an `account_id`, an IP or an install id. That is deliberate: nothing here is linked to a person, so account deletion has nothing to remove.

```sql
-- MARK: E - crash and slowdown reports (MetricKit), opt-in, anonymous
CREATE TABLE IF NOT EXISTS diag_groups (
  signature     TEXT PRIMARY KEY,         -- 16 hex, see telemetry.js signature()
  kind          TEXT NOT NULL,            -- crash | hang | cpu | disk | launch | abnormal
  title         TEXT NOT NULL,            -- "SIGSEGV - RedPen+0x1a2b3c" until symbolicated
  top_frames    TEXT NOT NULL,            -- JSON [{b,u,o}] up to 5
  binary_uuid   TEXT,                     -- app binary UUID (for CI symbolication)
  symbols       TEXT,                     -- JSON [{o,s}] written by CI
  first_seen    INTEGER NOT NULL,
  last_seen     INTEGER NOT NULL,
  first_version TEXT,
  last_version  TEXT,
  n             INTEGER NOT NULL DEFAULT 0,
  status        TEXT NOT NULL DEFAULT 'open',  -- open | fixed | ignored | regressed
  fixed_in      TEXT
);
CREATE INDEX IF NOT EXISTS diag_groups_seen ON diag_groups (last_seen);
CREATE TABLE IF NOT EXISTS diag_counts (
  signature TEXT NOT NULL, day TEXT NOT NULL, version TEXT NOT NULL,
  n INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (signature, day, version)
);
-- at most 5 per group, newest kept; body is the server-scrubbed report, 64 KB max
CREATE TABLE IF NOT EXISTS diag_samples (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  signature TEXT NOT NULL, received_at INTEGER NOT NULL,
  version TEXT, os TEXT, device TEXT, flavour TEXT, body TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS diag_samples_sig ON diag_samples (signature, received_at);
-- one row per device-day of MetricKit daily metrics, rolled into perf_daily after 8 days
CREATE TABLE IF NOT EXISTS perf_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  day TEXT NOT NULL, version TEXT, idiom TEXT, flavour TEXT, metrics TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS perf_reports_day ON perf_reports (day);
CREATE TABLE IF NOT EXISTS perf_daily (
  day TEXT NOT NULL, version TEXT NOT NULL, idiom TEXT NOT NULL, metric TEXT NOT NULL,
  n INTEGER NOT NULL, p50 REAL, p90 REAL, mean REAL,
  PRIMARY KEY (day, version, idiom, metric)
);

-- MARK: E - anonymous usage counts, opt-in
CREATE TABLE IF NOT EXISTS usage_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  day TEXT NOT NULL, received_at INTEGER NOT NULL,
  version TEXT, flavour TEXT, idiom TEXT, lang TEXT,
  cohort TEXT,                              -- ISO week of first launch, only with app_active
  counts TEXT NOT NULL                      -- JSON {event: n}, allow-listed and clamped
);
CREATE INDEX IF NOT EXISTS usage_reports_day ON usage_reports (day);
CREATE TABLE IF NOT EXISTS usage_daily (
  day TEXT NOT NULL, event TEXT NOT NULL, version TEXT NOT NULL, flavour TEXT NOT NULL,
  idiom TEXT NOT NULL, lang TEXT NOT NULL,
  n INTEGER NOT NULL DEFAULT 0, reports INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, event, version, flavour, idiom, lang)
);
CREATE TABLE IF NOT EXISTS usage_cohorts (
  cohort TEXT NOT NULL, day TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (cohort, day)
);
-- a floor under the write bill: telemetry never starves sync
CREATE TABLE IF NOT EXISTS telemetry_budget (
  day TEXT PRIMARY KEY, rows INTEGER NOT NULL DEFAULT 0
);
```

**Migration.** Everything is `CREATE ... IF NOT EXISTS`, and `worker-deploy.yml` already runs `schema.sql` on every deploy. No ALTERs are needed.

**Retention**, enforced by the cron in §2.5:

| Data | Kept for |
|---|---|
| `diag_samples` | 90 days |
| `diag_counts` | 180 days |
| `diag_groups` | Deleted when `last_seen` is over 180 days old and status is not `open` |
| Raw `usage_reports` and `perf_reports` | Rolled up, then deleted after 8 days |
| `usage_daily`, `usage_cohorts`, `perf_daily` | 400 days (so last year's exam season can be compared) |
| Rate-limiter rows in `pair_attempts` | 2 days |

`pair_attempts` has no pruning today, so the cron fixes that too.

## 2. Worker

### 2.1 New module `server/telemetry.js`

It exports:

- **Route handlers:** `diagRoute(request, body, env)`, `usageRoute(request, body, env)`, `ownerInsights(env, body)`, `ownerDiagStatus(env, body)`, `ciPending(env, body)`, `ciSymbols(env, body)`.
- **Maintenance:** `dailyMaintenance(env, now)`, called by the cron.
- **Pure helpers, unit-tested:**
  - `scrubDiagnostic(obj)` returns a clean report or null.
  - `signature(report)` returns 16 hex characters.
  - `validUsage(body, today)` returns `{rows, dropped}`.
  - `USAGE_EVENTS`, a map of `{event: dailyCap}`.
  - `ipKey(env, ip, day)` returns the first 16 hex characters of HMAC-SHA256(`SESSION_SECRET`, `rl:${ip}:${day}`). It rotates daily and is never reversible to an IP.
  - `keyMatches(request, secret)`: a constant-time bearer comparison, the same pattern as `isOwnerKey`.
  - `isOwnerAccount(env, id)`: true when `accounts.owner = 1` or the id is in `OWNER_ACCOUNT_IDS`. It goes in a small shared `server/owner.js` if group F doesn't land one first.

### 2.2 `worker.js` changes

- **Size table.** Add `/diag` at 256 KB and `/usage` at 32 KB. Keep the existing 411 rule, extended to both paths: a request with no declared size is refused (the app always declares one).
- **New switch cases:**
  ```js
  case '/diag':            return await diagRoute(request, body, env);
  case '/usage':           return await usageRoute(request, body, env);
  case '/owner/insights':  return await ownerOnly(request, env, () => ownerInsights(env, body));
  case '/owner/diag/status': return await ownerOnly(request, env, () => ownerDiagStatus(env, body));
  case '/ci/diag/pending': return keyMatches(request, env.CI_KEY) ? await ciPending(env, body) : fail(404, 'No such endpoint.');
  case '/ci/diag/symbols': return keyMatches(request, env.CI_KEY) ? await ciSymbols(env, body) : fail(404, 'No such endpoint.');
  ```
  `ownerOnly` works like `guarded` and then calls `isOwnerAccount`. It also accepts `isOwnerKey`. It answers **404** rather than 403 when the caller isn't the owner, so the endpoint doesn't reveal it exists.
- **Owner flag in the session.** `session()` adds `owner: await isOwnerAccount(env, account.id)` to the session JSON. This is shared with group F.
- **Cron.** Add `async scheduled(controller, env, ctx) { ctx.waitUntil(daily(env)) }`. `daily` calls `dailyMaintenance` and also calls other groups' maintenance functions, so there is one cron for the whole Worker.
- **Never log payloads.** `console.error(path, error)` stays as it is. No `console.log(body)` in telemetry code.

### 2.3 Anonymous write endpoints

The app sends these endpoints **no `Authorization` header, on purpose**. The server ignores one if it is present. That keeps the data unlinkable even in request logs.

**`POST /diag`: crash, hang, CPU, disk and launch diagnostics, plus daily performance metrics**

Request:

```json
{ "schema": 1,
  "app":    { "version": "1.2", "build": "45", "flavour": "store|testflight|playgrounds|personal|dev",
              "binary": "RedPen", "binaryUUID": "247F...FB4" },
  "device": { "model": "iPhone17,3", "idiom": "phone|pad", "os": "26.0.1", "arch": "arm64e",
              "lowPower": false },
  "diagnostics": [
    { "kind": "crash", "at": 1758700000,
      "exception": { "type": 1, "code": 0, "signal": 11, "name": "NSRangeException",
                     "className": "__NSArrayM", "termination": "Namespace SIGNAL, Code 11" },
      "frames": [ { "b": "RedPen", "u": "247F...", "o": 1234567, "a": 4296234567 } ] },
    { "kind": "hang", "at": 1758700100, "durationMs": 4200, "frames": [ ... ] },
    { "kind": "abnormal", "at": 1758700200 }
  ],
  "metrics": [ { "day": "2026-09-23", "launchMsP50": 820, "resumeMsP50": 90,
                 "hangMsPerHour": 210, "scrollHitchPct": 0.8, "peakMemMB": 410,
                 "foregroundMin": 46,
                 "exits": { "memory": 0, "watchdog": 0, "crash": 1, "abnormal": 0 },
                 "signposts": { "library_load": { "n": 3, "meanMs": 340 },
                                "pdf_ingest": { "n": 1, "meanMs": 5200 } } } ] }
```

Server rules:

1. **Kill switch.** If `env.TELEMETRY === 'off'`, return `200 {accepted:0, paused:true, retryAfter:86400}` and write nothing.
2. **Rate limits**, using `allowed(env, ipKey, what, n)`:
   - `'diag'`: 12 per hour.
   - `'diag-new'`: 5 new signatures per hour.
   - Past a limit: `429 {error, retryAfter:3600}`.
3. **Validation.** Only the whitelisted fields above are kept.
   - At most 10 diagnostics, 64 frames each, and 7 metrics days.
   - Strings are clipped to 200 characters, numbers must be finite, and `day` must be within [today−8, today+1].
   - The `kind` enum is enforced.
   - Anything else is dropped and counted in `dropped`. Unparseable JSON returns 400.
4. **Re-scrubbing.** The server re-scrubs even though the app scrubs first:
   - `name` and `className` must match `^[A-Za-z_][A-Za-z0-9_.]{0,80}$`.
   - `termination` has emails, paths, UUIDs and runs of 5+ digits replaced with `<redacted>`.
   - Never stored: `composedMessage`, format arguments, `regionFormat`, `pid`, `virtualMemoryRegionInfo`, thread names.
5. **Signature** = sha256 of `kind|type:signal (or kind)|first 5 frames where b == app.binary as "b+o"`, falling back to the first 5 frames of any binary, truncated to 16 hex characters.
6. **Writes**, a maximum of 5 statements per diagnostic, with the budget checked first:
   - Upsert `diag_groups`: `n = n + 1`, `last_seen`, `last_version`. If `status = 'fixed'` and the version is newer than `fixed_in` (compared semver-style), set `status = 'regressed'`.
   - Upsert `diag_counts`.
   - Insert into `diag_samples`, then `DELETE ... WHERE signature = ? AND id NOT IN (SELECT id ... ORDER BY received_at DESC LIMIT 5)`.
7. **Metrics** get one `INSERT INTO perf_reports` per day.
8. **Budget.** `UPDATE telemetry_budget SET rows = rows + ? WHERE day = ? AND rows + ? <= cap`, with an insert-if-missing first. `cap` is `env.TELEMETRY_DAILY_ROWS`, default `"10000"`. Over the cap, return `200 {accepted:0, dropped:n, retryAfter:86400}`.

Response: `200 {"accepted":3,"dropped":0,"paused":false,"retryAfter":0}`, or 400, 413 or 429 as `{error, message}`, the same shape as `fail()`.

**`POST /usage`: anonymous usage counts**

Request:

```json
{ "schema": 1, "app": { "version": "1.2", "flavour": "store" },
  "idiom": "pad", "lang": "ar", "cohort": "2026-W37",
  "days": [ { "day": "2026-09-23", "counts": { "app_active": 1, "quiz_completed": 2 } } ] }
```

- **Rate limit:** `'usage'`, 4 per hour per `ipKey`.
- **Allowed values:**
  - At most 7 days and 40 keys per day.
  - Unknown events are dropped. Each value is clamped to `USAGE_EVENTS[event]`.
  - `lang` must be one of `en | ar | other`, `idiom` one of `phone | pad`, and `flavour` one of the enum values.
  - `cohort` must match `^\d{4}-W\d{2}$` and is kept only when the day has `app_active`.
- **Write:** one `usage_reports` row per day, so at most 7 writes, subject to the budget.
- **Response:** `{accepted, dropped, paused, retryAfter}`.

`USAGE_EVENTS` (name → daily cap), mirrored exactly by Swift's `UsageEvent`:

```
app_active 1, onboarding_done 1, set_created 50, set_imported 50, generation_started 50,
generation_succeeded 50, generation_failed 50, ondevice_model_used 200, quiz_completed 100,
questions_answered 2000, cards_reviewed 2000, case_completed 100, osce_station_completed 100,
narrate_session 50, voice_session 50, ideas_opened 50, analytics_opened 50, accuracy_check_run 50,
paywall_shown 20, purchase_started 10, purchase_completed 5, share_link_created 50,
class_joined 5, widget_answer 200, intent_run 200, error_report_sent 50, sync_conflict 100,
abnormal_exit 5
```

Some events belong to other groups: A (`share_link_created`, `class_joined`), C (`widget_answer`, `intent_run`), D (`ondevice_model_used`) and F (`error_report_sent`). Their owners call `Telemetry.record(...)`, and the hooks are free when consent is off.

### 2.4 Owner and CI endpoints (read side)

**`POST /owner/insights`**

- **Auth:** an owner session, or `isOwnerKey`.
- **Body:** `{ "days": 30 }`, clamped to 7–180.

Response:

```json
{ "crashes": [ { "signature": "...", "kind": "crash", "title": "...", "status": "open",
                 "n7": 4, "n30": 9, "lastSeen": 1758700000, "versions": ["1.2 (45)"],
                 "samples": [ { "os": "26.0.1", "device": "iPad16,3", "flavour": "store",
                                "frames": [...], "symbols": [...] } ] } ],
  "health": [ { "version": "1.2", "activeDays": 812, "crashes": 9,
                "crashesPer1kActiveDays": 11.1, "launchMsP50": 780, "hangMsPerHour": 190,
                "scrollHitchPct": 0.7, "peakMemMBP90": 520 } ],
  "usage":  { "totals": { "quiz_completed": 1203 }, "activeByDay": [["2026-09-23", 118]],
              "byLang": { "en": {...}, "ar": {...} }, "byIdiom": {...},
              "retention": [ { "cohort": "2026-W35", "weeks": [100, 61, 44] } ] },
  "suppressedBelow": 5 }
```

- Figures are aggregated from `usage_daily` and `perf_daily` plus recent raw rows, using `SELECT j.key, SUM(j.value) FROM usage_reports r, json_each(r.counts) j ... GROUP BY ...`.
- **k-anonymity.** Any breakdown cell (lang, idiom, cohort-week) built from fewer than 5 reports is left out and counted in `suppressedBelow`.

**`POST /owner/diag/status`**

- **Body:** `{ "signature": "...", "status": "fixed|ignored|open", "fixedIn": "1.3" }`
- **Response:** `{ ok: true }`

**`POST /ci/diag/pending`** (auth: `CI_KEY`)

- Returns `[{signature, binaryUUID, binary, offsets: [..]}]` for groups whose `symbols` is null and whose `binary_uuid` is known, 100 at most.

**`POST /ci/diag/symbols`** (auth: `CI_KEY`)

- **Body:** `{ "signature": "...", "symbols": [{ "o": 1234567, "s": "LibraryView.body.getter (LibraryView.swift:88)" }] }`
- Stores the symbols and rewrites `title` from the first app symbol.
- Symbols are clipped to 300 characters and there are at most 64.

**`CI_KEY`.** `worker-deploy.yml` derives it with no manual step:

```
printf 'vignette-ci:%s' "$CLOUDFLARE_API_TOKEN" | sha256sum | cut -c1-64 | tr -d '\n' | $W secret put CI_KEY
```

This follows the existing `OWNER_KEY` pattern. `CLOUDFLARE_API_TOKEN` is always present, and any workflow with that secret derives the same value. Group F's bench-publishing endpoint should reuse `CI_KEY`.

### 2.5 `wrangler.toml` and the cron

```toml
[triggers]
crons = ["17 3 * * *"]        # one daily run shared by every group's maintenance
[vars]
TELEMETRY = "on"              # "off" pauses crash and usage collection without an app update
TELEMETRY_DAILY_ROWS = "10000"
```

`dailyMaintenance` runs in this order and stays within 50 queries:

1. Roll `usage_reports` older than 8 days into `usage_daily` and `usage_cohorts`. It reads the rows, sums them in JavaScript, and upserts with multi-row `INSERT ... VALUES (...),(...) ON CONFLICT DO UPDATE SET n = n + excluded.n, reports = reports + excluded.reports`, 12 rows (96 parameters) per statement. Then it deletes the rolled rows.
2. Roll `perf_reports` into `perf_daily`: n, p50, p90 and mean per metric, computed in JavaScript. Then delete them.
3. Apply the retention deletes from §1.
4. Delete `pair_attempts` rows more than 48 hours old and `telemetry_budget` rows more than 7 days old.

If group D ships remote config, the app also honours the flags `telemetry.crash`, `telemetry.usage` and `telemetry.flushHours`. Without remote config, the `TELEMETRY` var plus the `retryAfter` values the server sends back are enough.

## 3. App side (paths under `ios/RedPen`)

### 3.1 New Foundation-only files, all in the Swift test suite

**`Shared/Telemetry/UsageEvent.swift`**
- `enum UsageEvent: String, CaseIterable { case appActive = "app_active", ... }`
- `var dailyCap: Int`: the same caps as the server.

**`Shared/Telemetry/UsageLedger.swift`**
- `struct UsageLedger: Codable` holding `[day: [event: Int]]`.
- Methods:
  - `mutating func record(_ e: UsageEvent, count: Int = 1, on day: String)` clamps to the cap.
  - `func completedDays(before today: String) -> [DayCounts]` returns at most 7, oldest first.
  - `mutating func remove(days:)`.
  - `mutating func prune(olderThan: 14 days)`.
- `static func dayString(_ date: Date, calendar: Calendar) -> String` uses the device's local calendar day.
- `static func cohort(firstLaunch: Date) -> String` returns an ISO week such as `2026-W37`.

**`Shared/Telemetry/TelemetryConsent.swift`**
- `struct TelemetryConsent`, stored in `UserDefaults` under these keys:
  - `vignette.telemetry.crash: Bool`, default false.
  - `vignette.telemetry.usage: Bool`, default false.
  - `vignette.telemetry.askedAt: Double`.
  - `vignette.telemetry.firstLaunch: Double`.
  - `vignette.telemetry.activeDays: Int`.
- `static func shouldAsk(activeDays: Int, askedAt: Double?, isSignedIn: Bool, agreedTerms: Bool) -> Bool` is true only when all four hold: at least 3 active days, never asked, past the recording terms, and not a preview launch.

**`Shared/Telemetry/DiagnosticReport.swift`**
- Our own Codable schema, exactly the `/diag` request above: `DiagnosticBatch`, `DiagnosticItem`, `Frame`, `DailyPerf`.
- `enum DiagnosticScrubber`:
  - `static func clean(_ s: String?) -> String?` redacts emails, `/var/…` and `/Users/…` paths, UUIDs and digit runs of 5 or more, and clips to 200.
  - `static func identifier(_ s: String?) -> String?` keeps the name and className rule from §2.3.
  - `static func trim(_ frames: [Frame], max: Int = 64) -> [Frame]`.

**`Shared/Telemetry/CallStackTree.swift`**
- `enum CallStackTree { static func frames(fromJSON: Data) -> [Frame] }` parses `MXCallStackTree.jsonRepresentation()`: `callStacks[] → threadAttributed → callStackRootFrames → subFrames`.
- It takes the attributed thread, or the first thread if none is marked.
- It flattens the chain root-first, on the assumption that the root is the innermost frame, the crash site.

**`Shared/Telemetry/BuildFlavour.swift`**
- `static var current: String`:
  - `#if SWIFT_PACKAGE` gives `"playgrounds"`.
  - Otherwise `PersonalBuild.isOn` gives `"personal"`.
  - Otherwise `#if DEBUG` gives `"dev"`.
  - Otherwise a TestFlight check gives `"testflight"`, and everything else is `"store"`.
- The TestFlight check is injected as a closure so the file stays Foundation-only. The StoreKit wrapper supplies it from `AppTransaction.shared.environment == .sandbox`.

### 3.2 New platform files, not in the Swift test suite

**`Shared/Telemetry/Telemetry.swift`**
- The front door, a `@MainActor enum Telemetry`:
  - `static func record(_ e: UsageEvent, count: Int = 1)` does nothing when usage consent is off. It hands off to `UsageStore`, an `actor` that persists the ledger to `Application Support/telemetry/usage.json`, debounced.
  - `static func start()` is called from `RedPenApp.init`.
  - `static func flushIfDue()` runs when the app becomes active. At most once per 20 hours, it sends completed days via `TelemetryAPI` and removes them on 200.
- `start()` also handles the abnormal-exit check, which works in every build including Playgrounds:
  - It writes a `running` marker file whenever the app becomes active, and deletes it on `didEnterBackground`.
  - If the marker is still there at the next launch, that counts one `abnormal_exit` (only with consent).

**`Shared/Telemetry/MetricKitBridge.swift`**
- Wrapped in `#if canImport(MetricKit)`.
- `final class MetricKitBridge: NSObject, MXMetricManagerSubscriber`.
- `start()` calls `MXMetricManager.shared.add(self)` and also drains `pastDiagnosticPayloads` and `pastPayloads`.
- `didReceive(_: [MXDiagnosticPayload])` does nothing without crash consent: the payloads are dropped and never stored. With consent, it maps each diagnostic:
  - Metadata from the typed properties: `exceptionType`, `exceptionCode`, `signal`, `terminationReason`, the iOS 17 `exceptionReason.exceptionName` and `className`, `hangDuration`, `applicationBuildVersion`, `osVersion`, `deviceType`, `platformArchitecture`.
  - Stacks via `callStackTree.jsonRepresentation()` into `CallStackTree.frames`.
  - Everything goes through `DiagnosticScrubber` into `DiagnosticsOutbox`.
- `didReceive(_: [MXMetricPayload])` reduces each payload to a `DailyPerf`:
  - p50 of `histogrammedTimeToFirstDraw` and of `histogrammedApplicationResumeTime`.
  - `histogrammedApplicationHangTime` total divided by foreground hours.
  - `animationMetrics.scrollHitchTimeRatio`, `peakMemoryUsage` and `applicationExitMetrics` counts.
  - `signpostMetrics` for the signposts in `Perf`.

**`Shared/Telemetry/DiagnosticsOutbox.swift`**
- An actor storing JSON files in `Application Support/telemetry/outbox/`: at most 20 files, 2 MB and 14 days.
- It sends 10 seconds after launch and on becoming active.
- It deletes a file on 200 or 400. It keeps the file on 429, 5xx or offline, honouring `retryAfter` with exponential backoff.

**`Shared/Telemetry/TelemetryAPI.swift`**
- `send(path:body:)` wraps `AuthAPI.send(path, body:, token: nil, timeout: 15)`.
- Owner calls: `insights(days:token:)` and `setStatus(signature:status:fixedIn:token:)`.

**`Shared/Telemetry/Perf.swift`**
- `enum Perf { static func begin(_ name: StaticString) -> PerfInterval }` uses `mxSignpost(.begin/.end, log: MXMetricManager.makeLogHandle(category: "vignette"), name:)`, also mirrored to `OSSignposter` for Instruments.
- Initial names: `library_load`, `pdf_ingest`, `generation_local`, `sync_round`, `graph3d_layout`.

**`Features/Support/PrivacyChoicesView.swift`**
- A Form section titled "Help improve Vignette" with two toggles, both **off by default**:
  - "Send crash and slowdown reports"
  - "Send anonymous usage counts"
- Plain-language footer: "No account, name, library content, IP address or device ID is sent. Pro never depends on this. Turn it off at any time."
- A "See exactly what is sent" disclosure showing the pending JSON from the outbox and the ledger (transparency).
- A note that sent data is not linked to the user, so it cannot be looked up and deleted, and that it is deleted automatically after the retention periods in the privacy policy.
- It links to the Worker's `/privacy` page (group F).

**`Features/Support/TelemetryAskCard.swift`**
- A one-time, dismissible card on the library, shown when `shouldAsk` is true.
- Two buttons of equal weight: "Share both" and "Don't share". After either answer it is never shown again.
- It never appears on the paywall or during onboarding.

**`Features/Support/OwnerInsightsView.swift`**
- Shown only when `account.isOwner`. Three segments:
  - **Crashes:** grouped, with status chips, a detail page with frames or symbols, and "Mark fixed in <current version>" and "Ignore" buttons.
  - **Health by version:** crashes per 1,000 active days, launch p50, hang ms per hour and scroll hitch percentage.
  - **Usage:** totals, active devices by day, en/ar and phone/iPad split, and a cohort retention grid.
- Plain SwiftUI `Text` only. No web view, so stored strings can't inject anything.

### 3.3 Changed files

- **`RedPenApp.swift`:**
  - `Telemetry.start()` in `init` (skipped when `PreviewLaunch.screen != nil`).
  - `Telemetry.flushIfDue()` and the outbox send when the app becomes active.
  - `Telemetry.record(.appActive)` once per day.
  - The @Observable and async-load changes from §4.
- **`Features/Support/SupportCenter.swift` (`SettingsPage`):**
  - A "Privacy choices" row that opens `PrivacyChoicesView`.
  - An "Owner insights" row when `account.isOwner`.
- **`Models/Account.swift` and `Shared/AuthAPI.swift` (`SessionResponse`):** an optional `owner: Bool?`, defaulting to false, persisted with the session. Shared with group F.
- **One-line `Telemetry.record` calls:**

| Event(s) | File |
|---|---|
| `quiz_completed`, `questions_answered` | `Features/MCQ/MCQSummaryView.swift` |
| `cards_reviewed` | `Features/Anki/AnkiReviewView.swift` |
| `set_created` | `Features/Library/NewSetView.swift` |
| `generation_*` | `Features/Library/MCQGenerateForm.swift`, `LectureWriterSection.swift`, `Features/OSCE/OsceGenerateSection.swift` |
| `case_completed` | `Features/Cases/CaseChatView.swift` |
| `osce_station_completed` | `Features/OSCE/OsceReviewView.swift` |
| `narrate_session` | `Features/Narrate/NarrateReviewView.swift` |
| `voice_session` | `Features/Voice/CommuteModeView.swift`, `SpokenStationView.swift` |
| `ideas_opened` | `Features/Notes/IdeasView.swift` |
| `analytics_opened` | `Features/Analytics/AnalyticsView.swift` |
| `accuracy_check_run` | `Features/Support/AccuracyCheckSheet.swift` |
| `paywall_shown`, `purchase_*` | `Features/Paywall/PaywallView.swift` (group B's rewritten paywall keeps these hooks) |
| `sync_conflict` | `Persistence/SyncEngine.swift` |

- **`ios/RedPen/PrivacyInfo.xcprivacy` (new).** For the Xcode build:
  - `NSPrivacyTracking` false.
  - Collected types: CrashData, PerformanceData, OtherDiagnosticData and ProductInteraction, all with `Linked=false`, `Tracking=false`, and purposes AppFunctionality and Analytics.
  - Required-reason API `NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1`.
  - This file does not exist today and the App Store requires one, so whoever lands it first owns it.
- **`make_swiftpm.py`.** Add `"*.xcprivacy"` to `ignore_patterns` so SwiftPM doesn't warn about an unhandled file.

### 3.4 Xcode build vs Playgrounds build

**Nothing in group E needs an app extension, an entitlement or an Info.plist key.** The same code runs in both builds.

| | Xcode / App Store build | Playgrounds build |
|---|---|---|
| MetricKit | Delivers when "Share With App Developers" is on | Compiles and runs. Delivery to a Playgrounds-signed app is unverified and may never happen; the code tolerates that |
| Abnormal-exit marker | Works | Works |
| Symbolication | Via dSYMs (§3.5) | Crash titles stay as `binary+offset` (the on-device-compiled binary has no dSYM). Tagged `flavour=playgrounds` so the owner can filter |
| Privacy manifest | Included | Not included (not needed off-store) |
| Owner insights | Available | Available (the owner's personal build is an owner account through its claim) |

### 3.5 Symbolication without a Mac

The workflow that builds the App Store archive (group B/G's release workflow) must keep `DEBUG_INFORMATION_FORMAT=dwarf-with-dsym` and do two things:

1. Upload `dSYMs.zip` as a GitHub **release asset**, tag `dsyms-<version>-<build>`. Release assets allow up to 2 GB, whereas branch files are limited to 100 MB and the llama dependency makes the dSYM large.
2. Append `{uuid: tag}` to `dsyms-index.json` on an orphan `dsyms` branch, getting UUIDs from `dwarfdump --uuid`.

A new `.github/workflows/crash-symbols.yml` then runs on macOS, daily at 04:00 and on demand:

1. Derive `CI_KEY` the same way as the deploy workflow.
2. Call `POST /ci/diag/pending`.
3. For each UUID found in the index, `gh release download`.
4. Run `atos -arch arm64 -o <dSYM>/Contents/Resources/DWARF/RedPen -l 0x100000000 $((0x100000000 + offset))`, using the `__TEXT` base for each offset.
5. Call `POST /ci/diag/symbols`.

An optional `.github/workflows/insights.yml` runs weekly on Monday: it calls `/owner/insights` with `OWNER_KEY` derived from `AI_API_KEY` (the existing scheme) and pushes a readable `README.md` to an `insights` branch, which the owner can read in the GitHub app.

## 4. Performance work (the app is read-only here; this is the implementation plan)

Measure first, in both places, so every change is judged by field data per version:

- In the field: `Perf` signposts plus MetricKit data in `perf_daily`.
- In CI: a new `.github/workflows/perf.yml` on a macOS simulator runs a `UITests/PerfUITests.swift` that uses `XCTApplicationLaunchMetric` and `XCTOSSignpostMetric.scrollDecelerationMetric` on the library list. It pushes JSON to a `perf-bench` branch, like `checker-bench`.

### 4.1 Load the library off the main thread (largest win)

**The problem.** `Store.init` → `load()` runs `JSONDecoder` over `redpen-library.json` synchronously on the main actor. That file holds every picture as base64 and can be tens of MB. This is a watchdog risk and dominates time to first draw.

**The fix:**
- Add `nonisolated static func readFiles(fileURL:, studyURL:) -> LoadedFiles`, holding today's decode, set-aside and legacy-migration logic unchanged.
- New `func loadInBackground() async`:
  - Call `MXMetricManager.extendLaunchMeasurement(forTaskID: "library")` before the load starts.
  - Run `readFiles` in a detached task at `.userInitiated` priority.
  - Assign the results on the main actor, set `isLoaded = true`, then call `finishExtendedLaunchMeasurement`.
- **Safety rule, which is mandatory.** `write()` returns early while `!isLoaded` and leaves the dirty flags set. Otherwise a save before the load finishes would overwrite the library with an empty one. This needs a test.
- `init(fileURL:, loadNow: Bool = false)`: `PreviewLaunch.seededStore()` and the tests keep synchronous loading.
- **`RedPenApp` changes:**
  - Move `SampleData.seedPersonalBuild` and `InsightExamples.seed` out of `init` into `.task { await store.loadInBackground(); seed... }`.
  - Show a lightweight placeholder (the backdrop and a small `ProgressView`) until `store.isLoaded`.
  - `SyncEngine.syncNow()` waits on `isLoaded` before its first sync.
- **Later:** `NoteStore`, `ReviewStore`, `ReasoningStore` and `SubscriptionStore` load small files the same way. Convert them only if the `library_load`-style signposts show they cost more than 50 ms.

### 4.2 `@Observable` migration, in order of safety

There are 26 `ObservableObject` classes and no `@AppStorage` inside any of them. The only Combine dependency is `RedPenApp`'s `.onReceive(store.$library…merge(…reviews.objectWillChange))`. There is one `$`-binding site.

**Pattern for each class:**
- `@Published` → a plain stored property (`didSet` still works).
- `@StateObject` → `@State`.
- `@ObservedObject var x = X.shared` → a computed `X.shared` read in `body`.
- `@EnvironmentObject var s: S` → `@Environment(S.self) private var s`.
- `.environmentObject(s)` → `.environment(s)`.
- A binding site uses `@Bindable var s = s`.

**Waves:**
1. **Leaf, view-owned classes:** `CoverageChecker`, `LectureImporter`, `ModeSwitch`, `CommuteSession`, `SpokenStationSession`, `CaseSimulator`, `FloatingAction`, `RecordingTermsStore`, and **`LectureClock`**. `LectureClock` publishes playback time many times a second, so it is the hottest invalidation after `Store`.
2. **Singletons:** `GemmaModel` and `LocalLLMService` (13 environment sites), plus `VoiceSpeaker`, `VoiceListener`, `NarrateVoice`, `LecturePlayer`, `VoiceHistory`, `GenerationCenter`, `StudyLog`, `PronunciationLibrary`, `ReasoningStore`.
3. **Shared stores:** `AccountStore`, `SubscriptionStore`, `NoteStore`, `SyncEngine`.
4. **`Store` and `ReviewStore` (the biggest win).** 32 views observe `Store` today, and every answer (`answerLog`) redraws all of them.
   - Replace the Combine pipeline with `.onChange(of: store.libraryRevision) / .onChange(of: reviews.changeCount)`, followed by a 4-second debounced `Task`.
   - `libraryRevision` is incremented only in `library`, `folders` and `tombstones` `didSet`.
   - Mark `pendingWrite`, `lifecycleObservers`, `flaggedMemo` and the dirty flags `@ObservationIgnored`.
   - Drop `import Combine` where it is no longer used.

### 4.3 Other items

- **`drawingGroup()`** goes only on shape-only layers with no glass, text fields or UIKit views inside:
  - `StudyHeatmap`'s cell grid in `Features/Analytics/AnalyticsVisuals.swift` (about 180 rounded rectangles).
  - The arcs `ForEach` in `ProgressRing`.
  - **Never** on anything with `glassEffect`: flattening breaks Liquid Glass's backdrop sampling. That rules out `IdeaBoardView`, whose capsule uses glass. Its per-note shadows are better done as one shadow on the card's background shape.
- **`AnyView`.** The only use is `Features/Reasoning/ReasoningView.swift:226`. Pass the concrete `ReasoningSheet(...).environment(notes)` to `UIHostingController` instead. The effect is small; this is tidiness.
- **`AppBackdrop`.** Its 30 fps `TimelineView` mesh is already paused under Reduce Motion and Low Power. Add `paused: still || phase != .active`. Don't lower the frame rate unless `scrollHitchPct` shows a need.

## 5. App Store Review risks and how E stays compliant

| Rule | Risk | Mitigation |
|---|---|---|
| 5.1.1(ii) Consent | Analytics and crash data count as collection even when anonymous | Both toggles off by default; the ask is a separate, neutral opt-in with equal-weight buttons; easy to withdraw in Settings; "Pro never depends on this" is stated and true (no code path reads consent when deciding Pro) |
| 5.1.1(i) Privacy policy | Must list what is collected, why, retention, and how to revoke | Text supplied to group F's `/privacy` page, covering: crash/performance/usage counts, no identifiers, not linked, the retention in §1, revoking via Settings → Privacy choices, and that unlinked data can't be looked up so it expires instead of being deleted on request |
| 5.1.1(iii) Minimisation | Over-collection | Field allow-list on both client and server; region format, pid, messages and IP never stored; coarse `lang` only |
| 5.1.1(iv) Manipulation | Dark-pattern consent | No pre-ticked boxes, no repeated nagging, no gating |
| 5.1.2 Use and sharing | Third parties | No third-party SDK or processor beyond Cloudflare, which is our host |
| App Privacy labels (Guideline 2.3 accuracy) | Undeclared collection | Declare Diagnostics (Crash Data, Performance Data, Other Diagnostic Data) and Usage Data (Product Interaction): *Not Linked to You*, *Not Used for Tracking*, purposes Analytics and App Functionality. The optional-disclosure exemption does not apply because upload is automatic after opting in |
| ATT / tracking | None | No IDFA, no IDFV, no install id, and no cross-app linking, so there is no ATT prompt |
| Privacy manifest | Missing manifest leads to an ITMS warning or rejection | Add `PrivacyInfo.xcprivacy` (§3.3) |
| 1.4.1 (medical) | Not affected by E | None needed |

## 6. Security, privacy and abuse

- **Unlinkability.**
  - No `Authorization` header on `/diag` or `/usage`.
  - No account id, IP or install id stored.
  - Rate limiting uses a daily-rotating HMAC of the IP (`ipKey`), kept 48 hours.
  - The cohort is week-granular, attached only to `app_active`, and reported only in cells of 5 or more.
- **Poisoning and flooding.**
  - Per-`ipKey` hourly limits: diag 12, new groups 5, usage 4.
  - Per-event daily caps, at most 7 days per batch, and at most 5 samples per group.
  - A global daily write budget (`TELEMETRY_DAILY_ROWS`) so sync can never be starved.
  - The `TELEMETRY=off` kill switch.
  - Accepted limitation: counts are indicative, not billing-grade. The optional App Attest check (phase 2, Xcode build only) would raise the bar.
- **Input handling.**
  - Declared-size checks plus `boundedText`.
  - JSON field allow-list, clipped strings, numeric validation, and the server re-scrubs.
  - Error bodies never echo input.
  - The owner UI renders plain `Text`, with no HTML or web views.
- **Privileged endpoints.**
  - `/owner/*` needs an owner session or `OWNER_KEY`. `/ci/*` needs `CI_KEY`, compared in constant time.
  - Non-owners get 404.
  - `CI_KEY` and `OWNER_KEY` are derived on GitHub and never appear in code, chat or the repository.
- **Logs.** No payload logging. `wrangler.toml` enables no persistent observability.
- **Account deletion.** It needs no change and stays correct. The tests prove this by checking that no telemetry table has an account column.

## 7. Phase 2 (not v1)

- An iOS 27 `MetricManager` path: `for await report in MetricManager().diagnosticReports`, mapped into the same `DiagnosticItem`, behind `#if compiler(>=6.3)` plus `if #available(iOS 27, *)` once CI's Xcode and Playgrounds have the iOS 27 SDK. StateReporting domains for the current mode (Questions, Cards, Cases…) would give per-mode hang data.
- App Attest on `/diag` and `/usage` in the Xcode build (it needs an entitlement, so not in Playgrounds).

## 8. Tests

**`server/tests/telemetry.test.mjs`**

It uses the same `node:sqlite` harness as `pair.test.mjs` and adds a fake `ctx` for `scheduled`. It checks:

1. A valid crash gives 200 and creates one group, one count and one sample. The stored sample has no `composedMessage`, and an email and a `/var/mobile/...` path in `termination` are redacted.
2. The same crash posted twice has the same signature and `n=2`. After 7 posts there are still 5 samples.
3. A different binary offset gives a new signature. System-only frames fall back correctly.
4. A 300 KB body gives 413. No content-length gives 411. Malformed JSON gives 400. Eleven diagnostics give `accepted:10, dropped:1`. A bad `kind` is dropped.
5. The 13th `/diag` in an hour from one IP gives 429 while another IP passes. No row in any table contains the literal IP `203.0.113.9`.
6. `TELEMETRY=off` gives `paused:true` and zero rows.
7. `/usage`: unknown events are dropped, values are clamped to caps, out-of-window days are dropped, and a cohort without `app_active` is removed.
8. With `TELEMETRY_DAILY_ROWS=3`, the 4th row is refused with `retryAfter`.
9. `/owner/insights` returns 404 anonymously and 404 for a normal account. It returns 200 for `accounts.owner=1`, for `OWNER_ACCOUNT_IDS` and for `OWNER_KEY`. Cells with fewer than 5 reports are suppressed.
10. The `/ci/*` routes return 404 without `CI_KEY`. `pending` lists a group, `symbols` rewrites its title, and too many or too long symbols are clipped.
11. Status: marked fixed in 1.2, a crash in 1.3 sets `regressed`, and a crash in 1.2 leaves it `fixed`.
12. Calling `worker.scheduled(...)` at "now + 10 days" rolls reports into `usage_daily` and `perf_daily` (sums, p50) and deletes raw rows, old `pair_attempts` and expired samples.
13. **Parity with the app:** read `ios/RedPen/Shared/Telemetry/UsageEvent.swift` and regex the `case x = "raw"` lines. The raw values and caps must equal `USAGE_EVENTS`.
14. `PRAGMA table_info` on every telemetry table shows no `account_id` or `ip` column.
15. The session JSON includes `owner:true` only for owner accounts.

**Server CI wiring.** Add a step to `server-tests.yml`, and add `node server/tests/telemetry.test.mjs` to `worker-deploy.yml`'s "Tests first" line.

**`ios/RedPen/Tests/TelemetryTests.swift`**

Top-level code in the same `check()` style as the other suites. It checks:

- **Ledger:** clamps to the cap, `completedDays` excludes today, at most 7 are returned, `remove` works, JSON round-trips, and pruning after 14 days.
- **Cohort week:** at a year boundary, 2026-12-31 gives `2026-W53`.
- **Consent:** defaults are off; `shouldAsk` is false before 3 days, false before the terms are agreed, and false once asked.
- **Scrubber:** emails, paths, UUIDs and long numbers are redacted; valid identifiers are kept and invalid ones become nil; frames are trimmed to 64.
- **CallStackTree:** on a fixture JSON of Apple's documented shape with two threads, it picks the attributed one, flattens nested `subFrames` in order, and returns an empty array for malformed input.
- **`BuildFlavour`** with the closure injected.
- **`DiagnosticBatch`:** encoding matches the server's expected keys (golden JSON).

Add this to `swift-tests.yml`:

```
suite telemetry TelemetryTests.swift $S/Telemetry/UsageEvent.swift $S/Telemetry/UsageLedger.swift \
      $S/Telemetry/TelemetryConsent.swift $S/Telemetry/DiagnosticReport.swift \
      $S/Telemetry/CallStackTree.swift $S/Telemetry/BuildFlavour.swift
```

The existing `Shared/**` path trigger already covers these files.

**Store safety test.** Add `StoreLoadTests.swift` if `Store` can be compiled Foundation-only; otherwise add a UI test. It checks that a `save()` before `loadInBackground` completes never truncates an existing library file.

**UI tests**
- `UITests/PrivacyChoicesUITests.swift`: Settings → Privacy choices exists, and both toggles start off.
- `UITests/PerfUITests.swift`: the launch and scroll metrics, run by `perf.yml`.

## 9. Owner's unavoidable publish-time steps for group E

These are all in App Store Connect:

1. **App Privacy.** Answer "Yes, we collect data" and declare Diagnostics (Crash Data, Performance Data, Other Diagnostic Data) and Usage Data (Product Interaction). For each: *Not linked to the user's identity*, *Not used for tracking*, purposes *Analytics* and *App Functionality*. Combine this with the other groups' declarations.
2. **Privacy Policy URL.** Enter the Worker's `/privacy` URL (group F). It must include the E section described in §5.

Nothing else. There is no third-party account and no key to create. `CI_KEY` is derived automatically by the deploy workflow, the new cron comes from `wrangler.toml`, and the tables are created by the existing schema step. dSYM upload happens inside the release workflow.

Optional, for testing only: on the owner's own phone, turn on Settings → Privacy & Security → Analytics & Improvements → Share iPhone Analytics and Share With App Developers, so a TestFlight build sends MetricKit payloads.

## 10. Coordination points with other groups and open checks

- **The session `owner` flag and `isOwnerAccount`** are shared with F. Whoever lands first owns `server/owner.js`.
- **`CI_KEY` is shared with F** (bench JSON publishing).
- **Maintenance goes through the single cron.** Other groups' maintenance hooks into the same `scheduled()` dispatcher.
- **Other groups call `Telemetry.record` for their events:** A (`share_link_created`, `class_joined`), B (`paywall_shown`, `purchase_*`), C (`widget_answer`, `intent_run`), D (`ondevice_model_used`), F (`error_report_sent`). If D ships remote config, it should expose the `telemetry.*` keys.
- **`PrivacyInfo.xcprivacy`** is owned by whoever lands first. B, C and E each add entries.
- **New E strings go into the String Catalog** as localisable keys for F's Arabic pass. The owner insights page can stay English-only.
- **Two MetricKit behaviours are unverified** and should be checked on the first TestFlight build with a real payload:
  - Whether MetricKit delivers to Playgrounds-signed builds.
  - The exact order of frames in `callStackRootFrames`: I assume the root is the crash site. The parser keeps chain order either way, but the signature and title assume that direction.

Sources:
- [Meet the new MetricKit, WWDC26](https://developer.apple.com/videos/play/wwdc2026/222/)
- [WWDC.ai session 222 notes](https://wwdc.ai/2026/222)
- [sentry-cocoa issue #8123: new MetricKit APIs](https://github.com/getsentry/sentry-cocoa/issues/8123)
- [Swift with Majid: MetricKit](https://swiftwithmajid.com/2025/12/09/monitoring-app-performance-with-metrickit/)
- [MXCallStackTree jsonRepresentation](https://developer.apple.com/documentation/metrickit/mxcallstacktree/jsonrepresentation())
- [Chime: MetricKit crash reporting, part 2](https://www.chimehq.com/blog/metrickit-crash-reporting-part-2)
- [Cloudflare D1 limits](https://developers.cloudflare.com/d1/platform/limits/)
- [Workers Analytics Engine pricing](https://developers.cloudflare.com/analytics/analytics-engine/pricing/)
- App Review Guidelines 5.1.1 and 1.4.1: the local copy at `/tmp/claude-0/-home-user/8857977a-f678-5988-9658-6061ad2dfd91/scratchpad/guidelines.txt`
