> **Source design, feature group D** (architect output, 2026-09-24), copied verbatim.
> It is an input to [`../implementation-plan.md`](../implementation-plan.md). Where the two disagree, **the plan wins**:
> see the plan's section 2 (conflict resolutions) and the work package that implements this design.

# Feature group D: cost and intelligence (implementation design)

Worktree root: `/tmp/claude-0/-home-user/8857977a-f678-5988-9658-6061ad2dfd91/scratchpad/rp-prev`. All paths below are relative to it. I only read code and wrote nothing.

## 0. What exists, and what the design builds on

- **Money logic (`server/ai.js`).**
  - `proGate` / `isPro` confirm Pro with the App Store Server API, recheck every 6 h, and honour `owner` and `OWNER_ACCOUNT_IDS`.
  - `spend(env, key, limit)` is an atomic daily counter in `ai_usage`. It is already reused under made-up keys: `transcribe:<id>`, `tts-chars:all`.
  - The monthly wallet is `wallet`, `canPay`, `reserve`, `settle` over `ai_cost`, with `(account_id, month)` rows plus `tx:<origTx>` rows. It only matters while `PRO_PAYS=on`.
  - The model chain is Novita (paid) → Gemini through Firebase → Workers AI. Limits come from `wrangler.toml` `[vars]`, so changing one means a redeploy.
- **Background jobs.** `server/jobs.js` runs one `GenerationJobs` Durable Object per account. The job spec carries whole lecture `sources[]` and `steps[]` with `{{SOURCE}}` and `{{ALREADY}}` placeholders. The DO keeps `out:<id>:<i>` replies and `ver:<id>` verdicts, and the app collects them through `CloudJobCollector`. `checkSpec` ignores unknown fields, so new optional fields are backward compatible.
- **Router (`server/worker.js`).** `/blobs/*` and `/jobs*` are handled first. After that everything is POST-only. Owner-only endpoints (`/costs`) return 404 to anyone who isn't the owner. `wipe()` in `sync.js` runs on account delete.
- **Tests.** Server tests are `server/tests/*.test.mjs`: plain node against `node:sqlite` through a small `d1()` shim, with fake fetch. `worker-deploy.yml` runs a hard-coded list of tests, applies `schema.sql` (all `IF NOT EXISTS`), then runs `ALTER TABLE accounts ADD COLUMN …` lines that are allowed to fail. `server-tests.yml` also lists tests by hand.
- **The app already uses Apple's on-device model.**
  - `AppleFoundationBackend` in `Shared/LLM/LocalLLMService.swift` is an `LLMBackend`.
  - `MCQGenerator.availability` in `Shared/MCQGenerator.swift` maps `SystemLanguageModel.default.availability`.
  - Both are guarded by `#if canImport(FoundationModels) && !NO_FOUNDATION_MODELS`. `live-tests.yml` defines `NO_FOUNDATION_MODELS`.
  - `LLMChoice` is stored as strings: `off`, `device`, `cloud`, `cloud-medical`, or a UUID. `HostedProvider.cloud(for:)` sends `cramdown-writer` / `cramdown-checker` to `<worker>/v1`.
- **Swift tests.** `swift-tests.yml` compiles each `Tests/*.swift` as `main.swift` together with a list of Foundation-only sources, runs it, and fails on `rc≠0`.
- **Playgrounds.** `make_swiftpm.py` copies `ios/RedPen` except `Tests`, `Info.plist`, `*.storekit` and `*.entitlements`, stubs Gemma, and defines no compilation conditions. `AuthAPI.baseURL` falls back to the deployed worker when there is no Info.plist.
- **A bug to flag for group B.** `SubscriptionStore.isPro` returns `true` unconditionally, with the comment "Personal build". Any client-side Pro gating is therefore meaningless until B fixes it. Everything in this design is enforced on the server.

## Platform facts checked (September 2026)

**Cloudflare**
- **D1 free plan:** 5M rows read and 100k rows written per day. Since **1 Sep 2026, queries fail once either limit is exceeded**, until midnight UTC.
- **KV free plan:** 100k reads and 1k writes per day.
- **Workers free plan:** 100k requests per day, 10 ms CPU per request and per cron run, 5 cron triggers per account.

What that means for the design:
- Config is read from D1 once per isolate per minute, as one row. No KV binding is added.
- Nothing hashes megabytes of text in JavaScript.

**Apple FoundationModels**
- `SystemLanguageModel.default.availability` has three unavailable reasons: `.deviceNotEligible`, `.appleIntelligenceNotEnabled`, `.modelNotReady`.
- `supportsLocale(_ locale: Locale = .current) -> Bool` and `supportedLanguages` are iOS 26.0. Arabic is now in the supported set, but check at runtime.
- `contextSize` and `tokenCount(for:)` arrived in 26.4. The on-device context is still 4,096 tokens.
- `init(useCase:guardrails:)` accepts `Guardrails.permissiveContentTransformations`. It allows transforming possibly sensitive input text into **String** output.
- `LanguageModelSession.GenerationError` cases: `exceededContextWindowSize`, `guardrailViolation`, `unsupportedLanguageOrLocale`, `rateLimited`, `assetsUnavailable`, `refusal`, `concurrentRequests`, `decodingFailure`, `unsupportedGuide`.

**Apple Private Cloud Compute (iOS 27)**
- `PrivateCloudComputeLanguageModel` gives 32K context and reasoning levels.
- It needs the managed entitlement `com.apple.developer.private-cloud-compute`.
- Eligibility: App Store Small Business Program, and fewer than 2M first-time downloads across all of the developer's apps.
- It is free, with a daily quota **per user**: `quotaUsage.isLimitReached`, `.status`, `.limitIncreaseSuggestion` (an iCloud+ upsell sheet), and `Error.quotaLimitReached`.
- It only works on devices that support Apple Intelligence.
- It works in App Store, TestFlight and ad hoc builds, so **not in Playgrounds**.

**Apple acceptable-use rules for FoundationModels.** They prohibit "inaccurate or dangerous outputs … in high-risk domains, including … medical", and "circumventing safety policies or guardrails". So on-device output must stay a **transformation of text the app already has** (checked question, explanation, card). It must never be new medical fact generation, and it is always labelled.

---

## 1. Data model (D1): additions to `server/schema.sql`

```sql
-- Remote config: ONE row the worker reads ('live'), JSON body, cached per isolate for 60 s.
CREATE TABLE IF NOT EXISTS remote_config (
  id          TEXT PRIMARY KEY,          -- always 'live'
  version     INTEGER NOT NULL,
  body        TEXT NOT NULL,             -- JSON {flags, limits, messages, app, cache}; <= 64 KB
  updated_at  INTEGER NOT NULL,
  updated_by  TEXT NOT NULL              -- 'owner-key' or an account id
);
CREATE TABLE IF NOT EXISTS remote_config_history (
  version     INTEGER PRIMARY KEY,
  body        TEXT NOT NULL,
  updated_at  INTEGER NOT NULL,
  updated_by  TEXT NOT NULL,
  note        TEXT
);  -- pruned to the newest 50 on each write

-- Generated-set cache, keyed by lecture fingerprint + recipe, within a scope.
CREATE TABLE IF NOT EXISTS gen_cache (
  scope        TEXT NOT NULL,     -- 'acct:<accountId>' | 'class:<classId>'
  source_hash  TEXT NOT NULL,     -- 64 hex (see section 4.2)
  recipe_key   TEXT NOT NULL,     -- 64 hex = sha256(salt + ':' + recipeHash)
  extract      TEXT NOT NULL,     -- lines | questions | stations | pages
  mode         TEXT NOT NULL,     -- loop | each
  items        INTEGER NOT NULL,  -- items the job produced (job.done)
  checked      INTEGER NOT NULL DEFAULT 0,   -- 1 = every item went through the cloud checker
  object_key   TEXT,              -- R2 key when BLOBS exists
  body         TEXT,              -- JSON when there is no R2 (only if <= 1,900,000 bytes)
  bytes        INTEGER NOT NULL,
  created_by   TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  hits         INTEGER NOT NULL DEFAULT 0,
  last_hit_at  INTEGER,
  expires_at   INTEGER NOT NULL,
  PRIMARY KEY (scope, source_hash, recipe_key)
);
CREATE INDEX IF NOT EXISTS gen_cache_by_creator ON gen_cache (created_by);
CREATE INDEX IF NOT EXISTS gen_cache_by_expiry  ON gen_cache (expires_at);
```

Per-account cap overrides go in a column on `accounts`, because `proGate` already runs `SELECT *` there, so reading it costs no extra rows:

```sql
-- Existing deployments: ALTER TABLE accounts ADD COLUMN caps TEXT;
caps TEXT   -- JSON, e.g. {"chatDaily":1200,"microDaily":200} (owner-set for lecturers/ambassadors)
```

**Changes to `worker-deploy.yml`, "Database and bucket" step:**
- Add `"caps TEXT"` to the `for col in …` ALTER loop.
- Nothing else is needed: the new tables are all `CREATE … IF NOT EXISTS`.

**Counters reuse `ai_usage` under namespaced keys**, following the existing pattern. There is no new counter table:

| Key | Meaning |
|---|---|
| `micro:<id>` | hint, reword and explain calls in the cloud |
| `gfree:<model>:<id>` | per-account share of a free Gemini model's shared daily quota |
| `wai:<id>` | per-account share of the free Workers AI neurons |
| `stat:cache-hit:all`, `stat:cache-miss:all`, `stat:micro-device:all` | owner statistics, anonymous |
| `lookup:<id>` | not in `ai_usage`: cache lookups are rate-limited through `pair_attempts` with `allowed(env, 'acct:'+id, 'cache', N)` |

**Paid-spend ceilings reuse `ai_cost`.** A key's period is carried in the `month` column:

| `account_id` | `month` | Purpose |
|---|---|---|
| `<id>` | `YYYY-MM` | existing monthly cap |
| `d:<id>` | `YYYY-MM-DD` | new per-account daily cap |
| `global` | `YYYY-MM-DD` | new daily ceiling for everyone together |

- `budget()`'s `SUM … WHERE month = 'YYYY-MM'` already excludes day rows.
- Extend its `NOT LIKE 'tx:%'` filter to also exclude `d:%` and `global`.

## 2. Server modules and routes

### 2.1 New `server/config.js`

```js
export const DEFAULTS = {
  flags: {                               // each: {on:boolean, rollout?:0..1, minBuild?:int, maxBuild?:int, locales?:string[]}
    'assist.hint':          { on: true },
    'assist.reword':        { on: true },
    'assist.explain':       { on: true },
    'assist.arabic':        { on: true },   // "explain in Arabic" when the device model supports ar
    'assist.cloudFallback': { on: false },  // micro tasks may use Vignette Cloud when no on-device model
    'assist.pcc':           { on: true },   // iOS 27 Private Cloud Compute (Xcode builds with entitlement only)
    'assist.pccWriter':     { on: false },  // offer PCC as a free writer for whole sets
    'cloud.chat':       { on: true }, 'cloud.jobs': { on: true },
    'cloud.transcribe': { on: true }, 'cloud.tts':  { on: true },
    'cache.account':    { on: true }, 'cache.class': { on: false },  // class scope waits for group A
    'usage.showAllowance': { on: true },
  },
  limits: {                               // SERVER-ENFORCED
    chatDaily: 400, microDaily: 60, microMaxTokens: 220, microMaxChars: 4000,
    transcribeDaily: 36, ttsDaily: 300,
    jobsActive: 3, jobsKept: 20, jobSteps: 200, jobCountMax: 1000,
    freeShare: { 'gemini-3.5-flash': 4, 'gemini-3.5-flash-lite': 60, 'gemma-4-31b-it': 150, 'workers-ai': 80 },
    proDailyUsd: null, globalDailyUsd: 5, ownerMonthlyUsd: 20,   // only matter while PRO_PAYS=on
    cacheTtlDays: 180, cacheLookupsHourly: 60, cacheMaxSourceBytes: 2_000_000,
    cacheMaxBodyBytes: 1_900_000, cacheClaimNeedsPro: 1,
  },
  messages: [],   // [{id, level:'info'|'warn', en, ar, until?:epoch, minBuild?, maxBuild?}]
  app:   { configTtlSeconds: 21600, minBuild: 0, latestBuild: 0 },
  cache: { salt: 'v1' },
};
// Public subset returned to apps (never prices, USD caps, freeShare, salt):
export const PUBLIC_LIMITS = ['chatDaily','microDaily','transcribeDaily','ttsDaily','jobsActive','jobCountMax'];
```

**How a config is loaded**
- `loadConfig(env, clock = Date.now)` is memoised in module scope for 60 s: one D1 row read per isolate per minute.
- Precedence: stored body, then the legacy env var, then `DEFAULTS`. Env mapping: `AI_DAILY_LIMIT` → `chatDaily`, `TRANSCRIBE_DAILY` → `transcribeDaily`, `TTS_DAILY_LIMIT` → `ttsDaily`, `OWNER_MONTHLY_USD` → `ownerMonthlyUsd`. Existing deployments therefore behave exactly as before.
- Merging is deep, but only for keys already in `DEFAULTS`.
- `workers.dev` Cache API is not relied on; the module memo is the cache.

**Validation (`validate(body)`)**
- Unknown top-level or flag keys: rejected.
- Each numeric limit has a `[min, max]` range, for example `chatDaily 0..20000`, `microMaxTokens 32..600`, `globalDailyUsd 0..500`, `jobSteps 1..500`.
- Messages: `en` and `ar` at most 300 characters each, at most 5 messages.
- Serialised size at most 64 KB.
- Returns `{ok:true, body}` or `{ok:false, errors:[…]}`.

**Other exports**
- `accountLimits(cfg, account)` returns `cfg.limits` overlaid with the account's `caps` JSON, validated with the same ranges and ignored if invalid.
- `killed(cfg, feature)` returns the refusal (503, with the banner text if one exists) when `cfg.flags['cloud.'+feature].on === false`. It is enforced on the server, so old app builds obey it too.

### 2.2 Routes

Add a GET block in `worker.js` **before** line 112 (`if (request.method !== 'POST')`). Groups A and F will also add GET pages there, so it should be one shared block.

| Route | Auth | Request | Response |
|---|---|---|---|
| `GET /config` | none | header `If-None-Match: "<version>"` | `200 {version, ttl, flags, limits:{public subset}, messages, app:{minBuild, latestBuild}, serverTime}`, `ETag: "<version>"`, `Cache-Control: public, max-age=60`; `304` when unchanged |
| `POST /usage` | session (`guarded`) | `{}` | `200 {day, resetsAt, items:[{feature:'chat'\|'micro'\|'transcribe'\|'tts', used, limit}], jobs:{active, limit}, pro:bool}`. No dollars, ever. |
| `POST /owner/config` | owner key **or** an account with `owner=1` or in `OWNER_ACCOUNT_IDS`. Anyone else gets `404 No such endpoint.`, like `/costs`. | `{action:'get'}` or `{action:'set', expectVersion, patch:{…merge…}, note}` or `{action:'rollback', toVersion, note}` | get: `{live:{version, body}, effective, defaults, history:[{version, updated_at, updated_by, note}] (20)}`. set/rollback: `{version, effective}`. Version mismatch: `409 {error, live}`. Invalid: `400 {errors}`. |
| `POST /owner/usage` | owner | `{}` | `{today:{chat, micro, transcribe, tts, jobsCreated, cacheHits, cacheMisses, microOnDevice}, freeModels:{model:{usedToday}}, month: budget(env)}` |
| `POST /owner/account-caps` | owner | `{accountId, caps:{…}\|null}` | `{ok, caps}`: sets `accounts.caps` (lecturers, ambassadors) |
| `POST /owner/cache/purge` | owner | `{scope?, sourceHash?, olderThan?}` | `{deleted}` |
| `POST /cache/lookup` | session + Pro, when `cacheClaimNeedsPro` is on | `{scope:'account'\|'class:<uuid>', sourceHash, recipeHash, count}` | `{hit:false}` or `{hit:true, items, extract, checked, createdAt, from:'account'\|'class'}`. Not a member: 403. Rate limit: 429. |
| `POST /cache/claim` | same | `{scope, sourceHash, recipeHash, count, title}` | `201 {job:{…summary, status:'done', cached:true}}`: the job is then collected by the unchanged `CloudJobCollector` path. Miss: `404`. |
| `POST /v1/chat/completions` | unchanged, plus an optional `task:'hint'\|'reword'\|'explain'` | see 2.3 | unchanged shape |
| `POST /jobs` | unchanged, plus an optional `cache:{scope, share:bool, fresh:bool}` in the spec | server computes the cache keys | adds `cacheKey:{sourceHash, recipeHash}` to the 201 body |

**Owner authentication helper** in `worker.js`:

```js
async function ownerCaller(request, env) {
  if (isOwnerKey(request, env)) return 'owner-key';
  const id = await holder(request, env); if (!id) return null;
  const a = await env.DB.prepare('SELECT id, owner FROM accounts WHERE id = ?').bind(id).first();
  const ids = (env.OWNER_ACCOUNT_IDS||'').split(',').map(s=>s.trim());
  return a && (a.owner === 1 || ids.includes(a.id)) ? a.id : null;
}
```

Every owner write also goes through `allowed(env, clientIP(request), 'owner-write', 30)`, and every change lands in `remote_config_history`.

**Common headers the app sends on every call:** `X-Vignette-Build: <CFBundleVersion or 0>` and `X-Vignette-Surface: app|playgrounds`. They are used only for `messages` (minBuild/maxBuild) and in logs. Never trust them for access.

**Cron.** Add to `wrangler.toml`:

```toml
[triggers]
crons = ["17 3 * * *"]
```

- Plus `export default { fetch, scheduled }`, where `scheduled` calls `cleanupCache(env)`.
- The cleanup deletes at most 50 expired rows per run: `DELETE FROM gen_cache WHERE rowid IN (SELECT rowid FROM gen_cache WHERE expires_at < ? LIMIT 50)`, after a bulk R2 delete of their keys. That stays inside 10 ms of CPU.
- Groups A, E and F should share this single `scheduled` dispatcher. The free plan allows only 5 crons per account.

### 2.3 Changes to `server/ai.js`: per-user caps, fair shares, micro tasks, kill switches

**`chat(env, accountId, body, …)`**
1. `cfg = await loadConfig(env)`.
2. If `killed(cfg, 'chat')`, return the refusal.
3. `proGate` returns the account row. Change it to return `{refused, account}`; the existing callers take `.refused`. Then `lim = accountLimits(cfg, account)`.
4. **Micro path**, when `body.task` is set:
   - Validate against `['hint','reword','explain']`, otherwise 400.
   - Refuse with 503 if `cfg.flags['assist.cloudFallback'].on` is false.
   - Total characters must be at most `lim.microMaxChars`.
   - `max_tokens = min(body.max_tokens, lim.microMaxTokens)`.
   - Count with `spend(env, 'micro:'+id, lim.microDaily)`, not against `chatDaily`.
   - No evidence lookup; model `cramdown-writer`.
   - Chain is `env.MICRO_MODELS || 'gemini-3.5-flash-lite,gemma-4-31b-it'`, then Workers AI. Never the paid-only models, never Novita: set `route.canPay = false`.
5. Otherwise the daily limit is `lim.chatDaily` instead of `Number(env.AI_DAILY_LIMIT)`.

**`geminiModels(…)`: fair share of free quota.**
- Google's free per-model daily quotas are shared by every user, and one heavy account can empty `gemini-3.5-flash`'s 20 a day for everyone.
- While `!canPay`: for each model with a `freeShare` entry, `spend(env, \`gfree:${model}:${id}\`, share)` is taken just before that model is tried. This goes inside `generate()`, through a `beforeModel(model) → bool` hook so nothing is charged when the model isn't reached. If the share is used up, skip the model.
- Same for Workers AI: `spend(env, 'wai:'+id, freeShare['workers-ai'])`.
- Owner calls are exempt.

**`canPay(…)`: daily ceilings, only while `PRO_PAYS=on`.**
- Refactor `wallet().keys` into `[{key, period:'month'|'day', cap}]`:
  - `{key:id, period:'month', cap: perAccount}`
  - `{key:'d:'+id, period:'day', cap: lim.proDailyUsd ?? perAccount/8}`
  - `{key:'global', period:'day', cap: cfg.limits.globalDailyUsd}`
  - plus the existing `tx:` key.
- `reserve`, `adjust` and `settle` bind `period === 'day' ? today() : month()`.
- The "all or nothing" semantics are unchanged.
- Result: a runaway day cannot use a month's budget, and `globalDailyUsd` is a circuit breaker.

**Other callers**
- `transcribeChunk` and `tts.js speech()`: `killed(cfg, 'transcribe' | 'tts')`, with limits from `lim.transcribeDaily` and `lim.ttsDaily`.
- `/costs` keeps working. `/owner/usage` supersedes it for the app, and `/costs` stays for curl.

**D1 write budget.** A normal chat call costs 1–2 row writes today. It becomes 2–3 with a `gfree` counter. At 100k writes a day the ceiling is roughly 35k cloud calls a day, and `/owner/usage` shows it. A job of 200 steps is about 600 writes. If this becomes the constraint, the next move is counting job steps inside the DO; that change is not needed now.

### 2.4 Changes to `server/jobs.js`

- `checkSpec(raw, limits = LIMITS)` takes `jobSteps`, `jobCountMax`, `sources` and `sourceChars` from config. `jobsRoute` loads the config and passes `lim`. The DO `create` gets `limits:{active, kept}` in its body instead of the `LIMITS` constants.
- `killed(cfg, 'jobs')` before creating a job.
- New optional `spec.cache`: `{scope:'account'|'class:<uuid>', share:bool, fresh:bool}`. It is kept only when:
  - `cfg.flags['cache.account' | 'cache.class'].on` is on,
  - total source bytes are at most `cacheMaxSourceBytes` (CPU guard),
  - and for a class, `memberRole(env, classId, accountId)` from group A's module returns a role. Contributing (`share`) requires the role `lecturer`, or the class setting `members_share_generated=1`.
- `jobsRoute` computes `sourceHash` and `recipeHash` from the **checked** spec, as in section 4.2, and passes `cache:{scope, sourceHash, recipeKey, share}` to the DO. The keys are always derived from what the server actually ran, **never** from client-claimed hashes, which makes cache poisoning impossible.
- New DO route `/adopt` takes `{accountId, title, extract, mode, count, outputs:[string], checks:[verdict], writers:[…]}`. It writes `out:<id>:<i>` and `ver:<id>`, and a job with `status:'done', phase:'writing', cached:true, done:count`. It respects the `kept` limit. `summary()` gains `cached`.
- In `alarm()`, when a job becomes non-running, **before** `release(job)`, call `publishToCache(env, job)`. It runs only if all of these hold:
  - `job.cache?.share !== false`,
  - `!job.cached`,
  - `!job.error`,
  - `job.done >= min(job.count, 5)`,
  - `!job.hasCheck || (job.checked === job.checkTotal && !job.checkError)`.

  It then:
  1. writes the payload `{v:1, extract, mode, items: job.done, outputs, checks, writers, createdAt}` to R2 at `gencache/<sha256(scope)>/<sourceHash>/<recipeKey>.json`, or, with no R2, to `gen_cache.body` if it is at most `cacheMaxBodyBytes`, otherwise it skips;
  2. runs `INSERT … ON CONFLICT(scope, source_hash, recipe_key) DO UPDATE SET …`, where newest wins, so a "fresh" regeneration replaces the old entry;
  3. sets `expires_at = now + cacheTtlDays`.

  Failures are logged and never fail the job.

### 2.5 New `server/cache.js`

- **`lookup`**
  - Rate limit: `allowed(env, 'acct:'+id, 'cache', lim.cacheLookupsHourly)`.
  - Scope check: a class scope requires membership.
  - One PK read.
  - A hit requires `items >= min(count, items)`. Partial hits return `items`, so the UI can offer "30 ready now, or write 40 fresh".
  - Increments `stat:cache-hit:all` or `stat:cache-miss:all`.
- **`claim`**
  - Same checks, plus Pro when `cacheClaimNeedsPro` is on.
  - Loads the body from R2 or D1.
  - Truncates `outputs` so the cumulative `itemsIn(reply, spec).length` just reaches `count` (reusing `itemsIn` from jobs.js). For `mode:'each'` it keeps everything.
  - Then `stub.fetch('/adopt')`, and updates `hits` and `last_hit_at`, extending `expires_at`.
- **`wipeCache(env, accountId)`**, called from `deleteAccount` next to `wipe()`: deletes the `gen_cache` rows created by that account in every scope, plus their R2 objects. This matches the worker's stated rule that deleting an account takes its content with it.
- **`cleanupCache(env)`**: the cron job above.

## 3. On-device Foundation Models: hints, rewording, short explanations

### 3.1 The three tasks

All three only transform text the app already has.

| Task | Where | Input | Output rule |
|---|---|---|---|
| **Hint** | MCQ before answering; card front | stem, options, keyed answer, explanation | one sentence of at most 25 words that points at the mechanism or category **without** naming the answer |
| **Reword** ("Say it differently") | MCQ stem; card front | the stem or front only | same meaning, simpler words. Every number, unit, negation ("NOT", "EXCEPT", "least") and every drug or eponym kept exactly. Options are never reworded. |
| **Explain simply** | after answering; card back | question, correct answer, the set's own explanation | at most 3 short sentences restating **only** the given explanation. When the app is Arabic and `supportsLocale(ar)`: Arabic, with English medical terms in parentheses, which is how Egyptian schools teach. |

### 3.2 App files

**New: `ios/RedPen/Shared/LLM/Assist.swift`** (Foundation only, so it can be tested on the macOS runner)
- `enum AssistTask: String { case hint, reword, explain }`
- `struct AssistInput { stem, options:[String], answer:String?, explanation:String?, front/back, itemID:String }`
- `enum AssistPrompt`: `instructions(task, language)` and `prompt(task, input)`. Kept under about 1,200 tokens. Instructions say: "Use only the text given. Do not add facts, numbers, doses or diagnoses." The hint prompt includes the answer with "never say it or a synonym".
- `enum AssistCheck`, with every check pure:
  - `leaksAnswer(hint, answer:, options:)`: significant-token overlap with the answer is at least 0.5, or the answer's longest token (5+ letters) appears. It uses its own tokenizer (lowercase, letters and digits, Arabic-Indic digits folded to ASCII), not `ImageSpoiler`, to avoid pulling in dependencies.
  - `keepsFacts(original, rewritten)`: the multiset of numbers-with-units in the original ⊆ the rewritten one (after normalising "5mg"/"5 mg" and Arabic digits); every negation cue present; every capitalised or eponym token and every drug-suffix token (`-mab`, `-pril`, `-olol`, `-azole`, …) kept.
  - `addsNumbers(source, output)`: any number not in the source fails. This applies to explain and to hint.
  - `bounds(task, output)`: word and sentence limits, no markdown, no "As an AI".
- `enum AssistFallback`, deterministic and non-LLM, used when no model is available:
  - hint: "Think about: <two explanation keywords that aren't answer tokens>", or "Starts with ‘X’, N words";
  - explain: `Explanation.split(...)` first step (from the existing `Explanation.swift`), shown as-is;
  - reword: no fallback, so the button is hidden.

**New: `ios/RedPen/Shared/LLM/OnDeviceAssist.swift`**
- Guarded by `#if canImport(FoundationModels) && !NO_FOUNDATION_MODELS`.
- `@available(iOS 26.0, *) actor AppleAssist` with:
  - `model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)`. Medical text such as overdose or suicide-risk questions trips the default guardrails. Output is plain `String`, which is what the permissive guardrail covers.
  - `var isReady: Bool { model.availability == .available }`
  - `func language(for appLocale: Locale) -> Locale`: Arabic only if `model.supportsLocale(Locale(identifier: "ar"))` and the flag `assist.arabic` is on, otherwise English.
  - `prewarm()`: calls `LanguageModelSession(model:…).prewarm()` when the MCQ or card view appears, only if the flag is on and not `ProcessInfo.processInfo.isLowPowerModeEnabled`.
  - `run(task, input, language) async throws -> String`:
    - a new session per call (stateless, so the context doesn't grow);
    - `GenerationOptions(temperature: 0.3, maximumResponseTokens: 120)`;
    - a 12 s timeout through a task group;
    - trimming: if `#available(iOS 26.4, *)`, `try await model.tokenCount(for:)` against `model.contextSize`, otherwise a limit of about 3.2 characters per token.
  - Error mapping:
    - `.exceededContextWindowSize`: truncate the explanation by half and retry once;
    - `.unsupportedLanguageOrLocale`: retry in English;
    - `.guardrailViolation` and `.refusal`: `AssistError.declined`, which shows "Can't do this one on the device";
    - `.rateLimited`: the app is in the background, drop the call silently;
    - `.assetsUnavailable`: treat as unavailable.
- **PCC**, inside `#if VIGNETTE_PCC`: `@available(iOS 27.0, *) actor ApplePCCAssist`.
  - It uses `PrivateCloudComputeLanguageModel()`, checks `.availability` and `quotaUsage.isLimitReached`, and maps `Error.quotaLimitReached`, `.networkFailure` and `.serviceUnavailable` to "try next".
  - `limitIncreaseSuggestion?.show()` appears only as a secondary "More Apple requests" button when the limit is reached. That is Apple's own UI, so allowed.
  - The same file adds `PCCBackend: LLMBackend` (label "Apple Private Cloud Compute", `isOnDevice false`, `promptBudgetChars 60_000`) for `assist.pccWriter`.

**New: `ios/RedPen/Shared/LLM/AssistRouter.swift`** (`@MainActor final class AssistRouter`, `@Observable`, `static let shared`)
- `func run(_ task: AssistTask, _ input: AssistInput) async -> AssistResult`, where `AssistResult { text, source: .device|.pcc|.cloud|.ownProvider|.fallback, declined:Bool }`.
- Order:
  1. `AssistCache` hit;
  2. `AppleAssist`, if the flag is on and it is ready;
  3. `ApplePCCAssist`, if compiled in, iOS 27, the flag is on and quota remains;
  4. the student's own hosted provider, if `LocalLLMService.writerChoice` is `.hosted` (their key, their cost);
  5. Vignette Cloud micro: `HostedLLMClient(provider: .cloud(for: .writer), bearer:, task: task.rawValue)`, only if `assist.cloudFallback` is on and `cloudBlocker == nil`;
  6. `AssistFallback`.
- Every model output goes through `AssistCheck`. On failure, retry once with a stricter prompt; if that fails too, move to the next backend, and in the end use the fallback.
- Increments a local counter for group E's opt-in usage counters (`microOnDevice`).

**New: `ios/RedPen/Shared/LLM/AssistCache.swift`**
- An LRU of 2,000 entries, keyed by `AuthRules.sha256Hex(task|lang|itemID|sha(text))`.
- Stored in `Application Support/assist-cache.json` with `isExcludedFromBackup = true`.
- Invalidated when the item text changes, because the text hash is part of the key.

**New: `ios/RedPen/Features/Assist/AssistBar.swift`**
- SwiftUI: `AssistBar(input:, phase: .beforeAnswer|.afterAnswer)`.
- Buttons: Hint, Say it differently, Explain simply, and "Explain in Arabic" when available.
- A result bubble that carries:
  - its source label ("On this iPhone", "Apple Private Cloud Compute", "Vignette Cloud");
  - a fixed line "Reworded from this set's own explanation. For study only.";
  - group F's `ReportErrorButton`.
- Buttons are hidden when their flag is off or when the only possible backend is the fallback and the task is reword.

**Changed files**

| File | Change |
|---|---|
| `Features/MCQ/MCQQuizView.swift` | `AssistBar` under the stem (before answering) and under the explanation (after) |
| `Features/Anki/AnkiReviewView.swift`, `Features/Anki/AnkiCardFace.swift` | hint on the front, explain on the back |
| `Features/QA/QACardsView.swift` | explain on the back |
| `Shared/LLM/HostedLLMClient.swift` | `var task: String? = nil`; `openAIRequest` adds `"task"` when the provider is Vignette Cloud |
| `Shared/LLM/LocalLLMService.swift` | `LLMChoice.appleCloud` stored as `"pcc"`. `backend(for:)` returns `PCCBackend` when compiled in, on iOS 27, with `assist.pccWriter` on. `needsPro` returns false for it (it costs the owner nothing, so it can be a free-tier writer). |
| `Features/Support/ModelSettingsView.swift` | "Apple Private Cloud Compute (free)" option when available; the cloud allowance section (section 5) |

## 4. Cache of generated sets by lecture fingerprint

### 4.1 Flow in the app

**New: `ios/RedPen/Shared/LLM/LectureFingerprint.swift`** (Foundation plus `AuthRules.sha256Hex`)

`canonical(_ text: String) -> String`. This is **applied to every source before it goes into `CloudJobs.Spec.sources`**, so the server hashes exactly what it receives, cheaply and natively, with no JavaScript normalisation:
1. NFC (`precomposedStringWithCanonicalMapping`);
2. `\r\n` and `\r` become `\n`;
3. remove U+00AD, U+200B–U+200D, U+2060, U+FEFF, U+0640;
4. per line: collapse runs of space or tab to one space, and trim trailing whitespace;
5. collapse runs of 3 or more `\n` to `\n\n`;
6. trim.

Case and diacritics are kept, because this text is what the model reads.

Other functions:
- `sourceHash(_ sources: [String])`
- `recipeHash(_ spec: CloudJobs.Spec)` (section 4.2)

**`Shared/LLM/CloudJobs.swift`**
- `Spec` gains `var cache: CacheRequest?` where `CacheRequest: Encodable { scope: String; share: Bool; fresh: Bool }`.
- New `enum CloudCache` with:
  - `lookup(spec, at:) async throws -> Hit?`
  - `claim(spec, title, at:) async throws -> Created`
- `run(...)`: when `spec.cache?.fresh == false` and a lookup hit has `items >= spec.count`, it calls `claim` and polls the returned (already `done`) job id through the existing loop. Nothing downstream changes.

**Generate forms:** `Features/Library/MCQGenerateForm.swift`, `Features/Library/LectureWriterSection.swift`, `Features/OSCE/OsceGenerateSection.swift`.
- Once a lecture and settings are chosen, they build the spec. The builders are deterministic, and the step is debounced by 600 ms.
- They call `CloudCache.lookup` and show "Ready now: 40 questions already made from this lecture (free, instant)", or "…by your class", with a "Write fresh instead" toggle that sets `fresh = true`.
- A "Share with ‹class›" toggle appears when group A reports membership. It defaults to on for lecturers and off for members.

### 4.2 Canonical hashes

This must be byte-identical in Swift and JavaScript. Tests share `server/tests/fixtures/fingerprint-vectors.json`.

```
sourceHash = sha256hex("vignette-src-v1\n" + sources.map(s => sha256hex(utf8(s))).join("\n"))

recipeHash = sha256hex(utf8(
  "vignette-recipe-v1\n" +
  "mode=" + mode + "\n" + "extract=" + extract + "\n" +
  "minFields=" + clamp(minFields||2,1,8) + "\n" + "keyFields=" + clamp(keyFields||1,1,8) + "\n" +
  "cloze=" + (cloze?1:0) + "\n" +
  "check=" + (check ? sha256hex(check.template) : "none") + "\n" +     // template AS SENT, before withReasoningChecks
  "steps=" + steps.length + "\n" +
  steps.map(s => [ (Number.isInteger(s.source)? s.source : -1),
                   clamp(Number(s.maxTokens)||800, 16, 8000),
                   Math.round(clamp(Number(s.temperature ?? 0.7), 0, 1.5) * 100),
                   sha256hex(s.system||""), sha256hex(s.user) ].join("|")).join("\n")))

recipeKey (server only) = sha256hex(cfg.cache.salt + ":" + recipeHash)   // bump salt to invalidate everything
```

- `count`, `patience` and `title` are excluded. A larger cached set serves a smaller request.
- When the app changes its prompts, the hashes change, so a new app version invalidates the cache on its own.
- Swift uses `.rounded()` (schoolbook rounding), which equals `Math.round` for these positive values.

### 4.3 Privacy and abuse

- **No membership oracle for strangers.** Lookups need a session, membership of the scope, and are rate-limited to 60 an hour. Hashes are of whole lecture texts, so guessing is infeasible.
- **No poisoning.** Keys are computed on the server from the sources and prompts it actually ran. The outputs are the server's own model replies, and verdicts are kept with them, so every receiver's app applies the same accuracy filter.
- **What is stored:** generated items, verdicts and hashes. **The lecture text itself is not stored.**
- **Removal:** account deletion removes that account's cache entries. The owner can purge any scope; group F's "Report an error" review screen offers "purge cached copies of this set" via `/owner/cache/purge {sourceHash}`.
- **Class scope** stays behind `cache.class=false` until group A ships `memberRole(env, classId, accountId) → 'lecturer'|'member'|null` and the class setting `members_share_generated`.

## 5. Remote config and feature flags in the app

**New: `ios/RedPen/Shared/RemoteConfig.swift`** (Foundation only)
- `struct RemoteConfig: Codable { version:Int; ttl:Int; flags:[String:Flag]; limits:[String:Int]; messages:[Banner]; app:AppInfo }`
- `struct Flag { on:Bool; rollout:Double?; minBuild:Int?; maxBuild:Int?; locales:[String]? }`
- `static let builtIn`: the same defaults as the server. The app works offline and on first launch.
- Tolerant decoding: unknown keys are ignored; a missing flag falls back to built-in.
- `func isOn(_ name:String, build:Int, bucket:Double, language:String) -> Bool`, where `bucket` is a local random number in `0..<1` created once and stored in UserDefaults (not an identifier, never sent).
- `func banners(now:, build:, language:) -> [Banner]`.

**New: `ios/RedPen/Shared/RemoteConfigStore.swift`** (`@Observable @MainActor final class`, `static let shared`)
- `load()` reads the cached JSON from disk.
- `refresh(force:)` does `GET /config` with `If-None-Match`, no auth, and saves.
- It refreshes on launch and on `scenePhase == .active` when older than `ttl` (default 6 h). At 4 fetches per device per day, this protects the worker's 100k requests a day.
- Where it saves:
  - the Xcode build, when group C adds the app group `group.com.cramdown.app`: `containerURL(forSecurityApplicationGroupIdentifier:)`, so widgets and App Intents honour the flags;
  - otherwise (Playgrounds) `Application Support/remote-config.json`.
- `func isOn(_ name:)` wraps the model with the build number from `CFBundleVersion` (0 in Playgrounds).

**New: `ios/RedPen/Shared/CloudUsage.swift`** and **`ios/RedPen/Features/Support/CloudUsageView.swift`**
- `POST /usage` shows "Cloud today: 37 of 400 · resets 02:00". Percentages only, never dollars.
- Shown in `ModelSettingsView`, behind the `usage.showAllowance` flag.

**New: `ios/RedPen/Features/Support/OwnerConsoleView.swift`**
- Shown only when `PersonalBuild.isOn` or the account is an owner. The server decides; the view just handles a 404.
- Flag toggles, rollout sliders and limit steppers, validated by the server's 400s.
- Banner editor in English and Arabic; version history with rollback; `/owner/usage` numbers; account caps by account id; cache purge.
- An **"Assist self-test"** that runs 20 bundled fixture items through `AppleAssist` on the owner's own phone and shows the `AssistCheck` pass rate. It is optional. CI runners have no Apple Intelligence, so this is the only live evaluation of the on-device model.
- Authenticates with the personal build's owner key, or the owner session.

**Changed files**
- `RedPenApp.swift`: `@State private var remote = RemoteConfigStore.shared`, `.environment(remote)`, a `.task { await remote.refresh(force: false) }`, the existing `phase` handler calls `refresh`, and a top-of-root banner view for `remote.banners`.
- `Shared/AuthAPI.swift` (and `SyncAPI` / `HostedLLMClient` request builders): add the `X-Vignette-Build` and `X-Vignette-Surface` headers through one shared `VignetteHeaders.apply(to:)`.

## 6. Xcode build vs Playgrounds

| Piece | Xcode / App Store build | Swift Playgrounds (`make_swiftpm.py`) |
|---|---|---|
| On-device hint, reword, explain (`AppleAssist`) | yes (iOS 26, Apple Intelligence devices) | yes, same code. `canImport(FoundationModels)` is true on iPadOS 26 and `NO_FOUNDATION_MODELS` is not defined. |
| Private Cloud Compute (`ApplePCCAssist`, `PCCBackend`) | only when compiled with `VIGNETTE_PCC` **and** running iOS 27 **and** the managed entitlement is in the profile | compiled out: no `VIGNETTE_PCC`, and `*.entitlements` is excluded |
| Gemma fallback | as today | stubbed, as today |
| Remote config, usage, caps, cache | yes; config JSON also in the app group for widgets and intents | yes; config in Application Support |
| Owner console | yes (personal build) | yes (personal build) |

**How `VIGNETTE_PCC` gets turned on without a manual step.** In `app-build.yml` and `ipa.yml`, add a step before `xcodegen`:
- if `xcrun --sdk iphoneos --show-sdk-version` is ≥ 27,
- **and** the App ID's capabilities (fetched with the App Store Connect API key already in secrets) include Private Cloud Compute,
- then run `yq` to add `SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) VIGNETTE_PCC` and the entitlement `com.apple.developer.private-cloud-compute: true` to `ios/project.yml`.

Otherwise the build is unchanged. Adding the entitlement without Apple's grant would break signing, which is why the step checks first. `project.yml` in the repository stays as it is, apart from a comment.

`make_swiftpm.py` needs no change: the new folders are copied by `copytree`, and conditional code compiles out. It should get a comment noting that `VIGNETTE_PCC` is deliberately never defined.

## 7. App Store Review and platform-rule risks

1. **Guideline 2.5.2 (no downloaded code) and 2.3.1 (no hidden or dormant features).**
   - Config is data only: booleans, integers and banner text. No scripts or prompts are downloaded; prompts stay in the binary.
   - Every flag-gated feature is fully in the reviewed binary. **Keep all `assist.*`, `cloud.*` and `cache.account` flags on during review.**
   - List the server-side switches in App Review notes: "capacity switches; all features are enabled".
   - `minBuild` only shows a soft banner, never a hard lock.
2. **Foundation Models acceptable use** ("inaccurate or dangerous outputs … medical"; "circumvents … guardrails").
   - The on-device model only transforms text the app already has.
   - `AssistCheck` rejects added numbers, dropped negations and answer leaks.
   - Every output is labelled with its source and "for study only", and carries group F's report button.
   - `permissiveContentTransformations` is Apple's own supported option for exactly this kind of transformation. It is not a circumvention.
   - Nothing is framed as a clinical decision.
   - **Risk: medium.** It is mitigated by the design. Say it explicitly in review notes, alongside group F's disclaimer.
3. **Guideline 1.4.1 (medical).** Group F's "education, not clinical decisions" notice also covers assist outputs. No dosing calculators or diagnosis features are introduced.
4. **PCC programme terms.**
   - Needs the Small Business Program and fewer than 2M first-time downloads across all the developer's apps.
   - Past the limit Apple gives 6 months to migrate. `assist.pcc` and `assist.pccWriter` can switch it off instantly, and the app falls back to on-device, then cloud, then the deterministic fallback.
   - Do not build a custom upsell around Apple's quota; only `limitIncreaseSuggestion.show()`.
5. **Guideline 3.1.1.** Never sell extra cloud allowance or request packs outside in-app purchase, and never mention prices for them. Caps are shown as "resets at …", with Pro as the only upgrade path, and that path is group B's `SubscriptionStoreView`.
6. **Guideline 5.1.1 / privacy labels.**
   - On-device assist collects nothing.
   - PCC is Apple's own service with no retention. Disclose it in group F's privacy policy anyway.
   - Server-side per-account request counters (rate limits) are **Usage Data → Product Interaction, linked, App Functionality**.
   - The class-shared cache adds **User Content → Other User Content, linked, App Functionality**. It is probably already declared for sync.
   - The privacy policy (group F) must say that, when shared with a class, generated items (not the lecture) can be reused by classmates who generate from the same lecture.
7. **Guideline 4.2 / 2.1.** The deterministic fallback keeps the Hint button working on devices without Apple Intelligence. A reviewer on an older iPad never sees a dead button, and reword is hidden rather than broken.

## 8. Security and privacy

- **Owner endpoints.**
  - Owner key compared in constant time (the existing `isOwnerKey`), or an owner account.
  - Everyone else gets 404.
  - Owner writes are limited per IP per hour (`allowed(..., 'owner-write', 30)`).
  - Optimistic version check; every change in `remote_config_history`.
  - Strict schema: unknown keys and out-of-range values are rejected.
  - 64 KB cap; bounded banner text.
- **`GET /config`.** Public but free of personal data, and the same for everyone. Server-only limits (prices, USD caps, free shares, salt) are never serialised.
- **Server-side enforcement throughout.** Kill switches, caps, micro-task limits and Pro checks are all on the server. The app's flags are only for UX, which matters because `SubscriptionStore.isPro` is currently hard-coded `true`.
- **Micro tasks.** Pro only, with a separate daily cap. Clamped to 220 tokens and 4,000 characters. Cheapest free models only; never paid-only models; no evidence fetch.
- **Shared free quotas.** Per-account fair shares stop one account from draining Gemini's or Workers AI's free daily allowance for everyone.
- **Paid era.** A per-account daily USD cap and a global daily USD ceiling act as a circuit breaker on top of the existing monthly wallet.
- **Cache.** Covered in section 4.3. In addition, R2 keys use `sha256(scope)`, so bucket listings never show class or account ids.
- **CPU.**
  - Source hashing uses native `crypto.subtle` over bytes the app already canonicalised, and only when total source size is at most `cacheMaxSourceBytes`.
  - Cron cleanup works in batches of 50.
  - Config is memoised per isolate.
- **On device.**
  - The assist cache is excluded from backup and holds derived text only.
  - FoundationModels calls run in an actor off the main thread.
  - Prewarm is skipped in Low Power Mode.
- **Account deletion.** Add `wipeCache()` next to `wipe()`. Also add `accounts.caps`, which goes with the row. `ai_usage` counters stay: they are anti-abuse data with no personal content, per the existing comment.

## 9. Tests

### 9.1 Server

Add every new test to **both** `server-tests.yml` and the "Tests first" line in `worker-deploy.yml`.

**`server/tests/config.test.mjs`**
- An empty table gives `DEFAULTS`.
- Env var fallback (`AI_DAILY_LIMIT=5` gives `chatDaily 5`), and a stored value beats the env var.
- The deep merge ignores unknown keys.
- `validate` rejects unknown flags, wrong types, out-of-range limits, over-long banners and a body over 64 KB.
- The public view never contains `globalDailyUsd`, `freeShare` or `salt`.
- `GET /config` returns an ETag and a 304 on match.
- Owner set, get and rollback work with the owner key and with an owner account. A normal account and no auth get 404.
- A stale `expectVersion` gives 409.
- History is capped at 50.
- The memo does one D1 read across two loads within 60 s (inject the clock; count `prepare` calls in the shim), and a fresh read after 61 s.

**`server/tests/usage.test.mjs`**
- `Promise.all` of 10 `spend` calls with a cap of 3 gives exactly 3 successes.
- `accounts.caps` override raises the limit, and an invalid override is ignored.
- Micro path:
  - `task` values outside the allowed three give 400;
  - `max_tokens` is clamped to `microMaxTokens`;
  - no paid or Novita source is called (fake fetch records URLs);
  - micro calls don't consume `chatDaily`;
  - with `assist.cloudFallback` off, 503.
- Free share: after N calls, `gemini-3.5-flash` is skipped and the next model is used, while owner calls are unaffected.
- Kill switches: `cloud.jobs`, `cloud.chat`, `cloud.tts` and `cloud.transcribe` off give 503 with the banner text.
- `/usage` has the documented shape.
- With `PRO_PAYS=on`: `globalDailyUsd` reached forces free models; the per-account daily cap works; `budget()` still sums only monthly per-account rows.

**`server/tests/cache.test.mjs`**
- `sourceHash` and `recipeHash` match `fixtures/fingerprint-vectors.json`.
- Recipe excludes `count`; salt changes `recipeKey`.
- Lookup: miss, hit, and partial hit (`items < count`).
- Scope isolation: account B can't see account A's entry; a non-member of a class gets 403 (with a stub `memberRole`).
- The 61st lookup in an hour gets 429.
- Publish happens only when the check completed without `checkError`, never for `cached` jobs, and never for jobs with an `error`.
- R2 path with a fake `BLOBS` Map; D1 `body` fallback without `BLOBS`; a body over the cap is skipped.
- Claim adopts through a fake DO and truncates replies to `count`; `hits` increments.
- Poisoning test: a client-supplied `cache.sourceHash` in the job spec is ignored, and the stored key equals the hash of the sources actually sent.
- `wipeCache` removes rows and objects.
- `cleanupCache` deletes at most 50 per run.

**Additions to `jobs.test.mjs`**
- Limits come from config (a lower `jobSteps` refuses the job).
- `/adopt` creates a `done` job with `cached:true`, collectable with `outputs=1`.
- The alarm publishes to the cache on completion.

**Additions to `ai.test.mjs`**
- `proGate` return-shape refactor.
- `transcribeChunk` and TTS use the config limits.

### 9.2 Swift

Suites for `swift-tests.yml`. The runner runs from the repository root, so suites can read `server/tests/fixtures/*.json`.

```
suite assist AssistTests.swift $S/LLM/Assist.swift $S/LLM/LLMCore.swift \
      $M/MCQQuestion.swift $M/Differential.swift $M/AnkiCard.swift $M/QACard.swift \
      $M/OsceChecklist.swift $M/NarrateSegment.swift $M/SourceDoc.swift $M/StudySet.swift \
      $S/SoundKey.swift $S/PronunciationStore.swift $S/OnDeviceLearning.swift $S/Corrections.swift \
      $S/WordTiming.swift $S/LectureTranscriber.swift $S/Brand.swift $S/BookPages.swift \
      $S/BookFigures.swift $S/Highlight.swift $S/ImageSpoiler.swift $S/DeckPalette.swift \
      $S/DeckCard.swift $S/Explanation.swift        # (fallback uses Explanation.split; same deps as the deck suite)
suite remoteconfig RemoteConfigTests.swift $S/RemoteConfig.swift
suite fingerprint FingerprintTests.swift $S/LLM/LectureFingerprint.swift $S/AuthRules.swift $S/LLM/CloudJobs.swift
```

To keep `CloudJobs.swift` Foundation-only for that suite, move `Spec`, `Step`, `Check` and `CacheRequest` into a new `Shared/LLM/CloudJobSpec.swift` and list that file instead. Add the new paths to the workflow's `on.push.paths`.

**`Tests/AssistTests.swift`**
- Leak detection: an answer word in the hint, or a partial eponym ("Kawasaki"), is caught; an unrelated hint passes.
- Numbers: "5 mg" vs "5mg" is fine; "5 mg" becoming "50 mg" fails; Arabic-Indic digits are folded.
- Dropped "NOT" or "EXCEPT" fails; an added number fails; a dropped drug suffix token fails.
- Word and sentence bounds; markdown is stripped.
- Fallback hints never contain answer tokens and are deterministic.
- Prompt builders put the answer only in the hint prompt, never in the reword prompt.
- Arabic output passes `keepsFacts` when English terms are kept in parentheses.

**`Tests/RemoteConfigTests.swift`**
- Tolerant decode (unknown keys, missing flags fall back to built-in).
- Rollout: bucket 0.24 is on for 0.25 and off for 0.2.
- `minBuild`/`maxBuild`; locale filter; expired banners hidden; built-in values equal the server `DEFAULTS` (compared against a fixture exported by `config.test.mjs`: `server/tests/fixtures/config-defaults.json`, written and checked by that test).

**`Tests/FingerprintTests.swift`**
- `canonical()` rules: CRLF, zero-width characters, tatweel, space runs, triple newlines; idempotent; case and diacritics kept.
- `sourceHash` and `recipeHash` equal the JavaScript vectors.
- Clamping mirrors the server (`maxTokens 99999` becomes 8000, `temperature 2` becomes 150).

**UI test**, optional, in `ios/UITests`: launch with `-assistStub`, which makes `AssistRouter` use a deterministic stub backend. Tap Hint in the example MCQ and assert the bubble and its source label.

## 10. Owner steps

**None are needed for D on Cloudflare or GitHub.** The deploy workflow applies the schema, the `caps` ALTER and the cron automatically. Config defaults live in code; later changes are made from the in-app owner console.

At publish time, in App Store Connect:
1. **App Review notes:** list the server-side capacity switches (all on during review); on-device Apple Intelligence study aids that only reword the set's own text; the educational-use disclaimer (group F).
2. **App Privacy labels:** add Usage Data → Product Interaction (linked, App Functionality) for rate-limit counters. When class caching is turned on, confirm User Content → Other User Content (linked, App Functionality).
3. **Recommended regardless of D:** enrol in the **App Store Small Business Program** (Agreements, Tax and Banking). It lowers Apple's commission to 15%; update `PRO_NET_MONTHLY_USD` accordingly at launch. It is also required for PCC.
4. **Optional, for free PCC:** request the Private Cloud Compute managed entitlement at developer.apple.com/private-cloud-compute (Apple Developer account). Once granted, enable the capability on the App ID `com.cramdown.app` in Certificates, Identifiers & Profiles. CI then detects it and builds with `VIGNETTE_PCC`.

## 11. Order of work, and overlap with the other two jobs

**Phases**
1. `config.js`, config routes, limits wired into `ai.js`, `jobs.js` and `tts.js`, kill switches, `/usage`, free shares, and their tests. The app needs no change for this phase.
2. App: `RemoteConfig` and its store, usage view, owner console, request headers.
3. On-device assist: `Assist`, `OnDeviceAssist`, `AssistRouter`, `AssistCache`, `AssistBar` and the view hooks, plus the server micro path.
4. Fingerprint cache with account scope: `LectureFingerprint`, `CloudJobSpec` split, `cache.js`, DO `/adopt`, publish-on-complete, cron. Class scope follows once group A's `memberRole` exists.
5. PCC: the CI detection step, `ApplePCCAssist`, `PCCBackend`, the `"pcc"` choice.

**Files other jobs also touch, so merge carefully:**
- `server/worker.js`: the GET block, `scheduled`, `deleteAccount`
- `server/schema.sql`
- `server/wrangler.toml`: a single `[triggers]` entry shared by all groups
- `.github/workflows/worker-deploy.yml` and `server-tests.yml`: test lists
- `ios/RedPen/RedPenApp.swift`
- `Shared/LLM/LocalLLMService.swift`
- `Features/MCQ/MCQQuizView.swift`
- `Features/Anki/AnkiReviewView.swift`
- `ios/project.yml`: the app group from group C, the PCC patch from CI

**Interfaces other groups rely on**
- **Group A** provides `memberRole` and `members_share_generated`.
- **Group B** fixes `isPro`; the server's `proGate` is what D actually trusts.
- **Group C** reads the config JSON from the app group.
- **Group E** counts `microOnDevice` locally, opt-in.
- **Group F** provides `ReportErrorButton`, the Arabic strings for `AssistBar` in the String Catalog, and the privacy-policy wording from section 7.

Sources:
- [Cloudflare Workers pricing (D1 and KV free limits)](https://developers.cloudflare.com/workers/platform/pricing/)
- [D1 free-tier enforcement from 1 Sep 2026](https://developers.cloudflare.com/changelog/post/2026-09-01-d1-free-tier-limit-enforcement/)
- [Workers limits (10 ms CPU, crons)](https://developers.cloudflare.com/workers/platform/limits/)
- [Workers Cache API](https://developers.cloudflare.com/workers/runtime-apis/cache/)
- [Apple: SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Apple: supportsLocale(_:)](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/supportslocale(_:))
- [Apple: GenerationError](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror)
- [Apple: PrivateCloudComputeLanguageModel](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel)
- [Apple: Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)
- [Apple: Acceptable use requirements for the Foundation Models framework](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/)
- [Daring Fireball on PCC eligibility limits](https://daringfireball.net/linked/2026/06/13/pcc-severely-limited-third-party-developers)
- [Blake Crosley: Foundation Models on PCC](https://blakecrosley.com/blog/foundation-models-private-cloud-compute)
- [Artem Novichkov: token usage in Foundation Models](https://artemnovichkov.com/blog/tracking-token-usage-in-foundation-models)
- [Ivan Magda: Foundation Models, year two](https://ivanmagda.dev/posts/wwdc26-foundation-models-year-two/)
- [Rudrank Riyam: Foundation Models supported languages](https://rudrank.com/exploring-foundation-models-supported-languages-internationalization)
