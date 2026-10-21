# Vignette Worker: unified route table

Companion to [`implementation-plan.md`](implementation-plan.md) (§3.1 has the router contract). Each route lives in exactly one module; the module's owning package is the only one that edits it. Existing routes (sign-in, sync, blobs, jobs, `/v1/chat/completions`, `/tts`, `/transcribe/*`, `/costs`) keep their paths and stay in `worker.js`'s legacy switch.

**Auth modes.** `public` means no auth. `session` means a bearer access token (`holder()`). `owner` means `OWNER_KEY` or an owner account; everyone else gets 404. `ci` means `CI_KEY`; everyone else gets 404. `apple` means no session, because the signed JWS is the authentication.

**Error shape** is `{error, message, code}`. Business errors use 400, 409, 410, 413, 422, 428, 429, 503 or 507, each with a `code`, and never 403 or 404 (see plan §2, row R14).

| Route | Auth | Module | Package | Notes |
|---|---|---|---|---|
| `GET /config` | public | config.js | P0.1 | ETag / 304, public subset only |
| `POST /account/me` | session | account.js | P0.1 | `{userId, owner, termsVersion, aiConsent, rulesVersion, legal}` |
| `POST /account/consent` | session | account.js | P0.1 | `{termsVersion?, aiConsent?, rulesVersion?}`; replaces design A's `/shares/terms` |
| `POST /account/subscription` | session | apple.js (moved) | P0.1 moves it, P1.3 extends it | signed transactions (B §3.3) |
| `POST /shares/limits` | session | share.js | P1.1 | A §4.2 |
| `POST /shares/publish` | session | share.js | P1.1 | body ≤ 5 MB; 428 `rules_required` |
| `PUT /share-blobs/:shareId/:hash` | session | share.js | P1.1 | raw body |
| `POST /shares/commit` | session | share.js | P1.1 | |
| `POST /shares/mine` | session | share.js | P1.1 | |
| `POST /shares/revoke` | session | share.js | P1.1 | |
| `POST /shares/versions` | public | share.js | P1.1 | ≤ 200 codes, per-ipKey limit |
| `POST /codes/lookup` | public | share.js | P1.1 | new: returns the type of a bare 10-character code (share / group / admin); wrong codes are counted |
| `GET /s/:code` | public | sharepage.js | P1.1 | HTML, en/ar |
| `GET /s/:code.json` | public | share.js | P1.1 | |
| `GET /s/:code/v/:n.json` | public | share.js | P1.1 | immutable, nosniff |
| `GET /s/:code/b/:hash` | public | share.js | P1.1 | octet-stream, attachment |
| `GET /j/:code` | public | sharepage.js | P1.1 | HTML; shows "class access included" when the class holds a licence |
| `GET /j/:code.json` | public | groups.js | P1.2 | |
| `GET /.well-known/apple-app-site-association` | public | sharepage.js | P1.1 | paths `/s/*`, `/j/*`, `/r/*`; 404 until the team id is known |
| `GET /robots.txt`, `GET /og.png` | public | sharepage.js | P1.1 | |
| `POST /moderation/report` | session or public | moderation.js | P1.1 | design A's `/reports`, renamed |
| `POST /blocks/add`, `/blocks/remove`, `/blocks/list` | session | moderation.js | P1.1 | |
| `POST /owner/moderation/list`, `/owner/moderation/resolve` | owner | moderation.js | P1.1 | design A's `/owner/reports*`, renamed |
| `POST /groups/create`, `/join`, `/mine`, `/feed`, `/update`, `/me`, `/leave`, `/transfer`, `/delete` | session | groups.js | P1.2 | A §4.3; `join` also allocates a licence seat |
| `POST /groups/sets/add`, `/groups/sets/remove`, `/groups/members/remove` | session | groups.js | P1.2 | |
| `POST /groups/leaderboard`, `POST /stats/week` | session | groups.js | P1.2 | |
| `POST /apple/notifications` | apple | appstore.js | P1.3 | B §3.3; 401 with no writes on a bad signature |
| `POST /account/status` | session | entitlement.js | P1.3 | B §3.3 snapshot |
| `POST /owner/billing/notifications`, `/owner/billing/test-notification` | owner | appstore.js | P1.3 | |
| `POST /referrals/me`, `/referrals/claim` | session | referrals.js | P1.4 | |
| `GET /r/:code`, `GET /a/:slug` | public | invitepage.js | P1.4 | no prices, ever |
| `POST /owner/licences/create`, `/list`, `/update`, `/seats`, `/remove-seat` | owner | licences.js | P1.4 | replaces design B's `/owner/groups/*`; a licence attaches to an A class |
| `POST /owner/ambassadors/upsert`, `/owner/ambassadors/stats` | owner | ambassadors.js | P1.4 | |
| `POST /ci/ambassadors/pending`, `/ci/ambassadors/result` | ci | ambassadors.js | P1.4 | new: the queue the App Store Connect automation works from |
| `POST /owner/billing/summary`, `/owner/grants/gift` | owner | billing-owner.js | P1.4 | |
| `POST /owner/config` | owner | configadmin.js | P1.5 | get / set / rollback |
| `POST /account/allowance` | session | allowance.js | P1.5 | design D's `/usage`, renamed |
| `POST /owner/cloud-usage`, `/owner/account-caps` | owner | allowance.js | P1.5 | design D's `/owner/usage`, renamed |
| `POST /cache/lookup`, `/cache/claim` | session | cache.js | P1.6 | |
| `POST /owner/cache/purge` | owner | cache.js | P1.6 | |
| `POST /telemetry/diag`, `/telemetry/usage` | public | telemetry.js | P1.7 | design E's `/diag` and `/usage`; any Authorization header is ignored |
| `POST /owner/insights`, `/owner/diag/status` | owner | telemetry.js | P1.7 | |
| `POST /ci/diag/pending`, `/ci/diag/symbols` | ci | telemetry.js | P1.7 | |
| `POST /reports`, `/reports/mine` | session | trust.js | P1.8 | item error reports (F) |
| `POST /owner/reports/list`, `/update`, `/stats` | owner | trust.js | P1.8 | design F's `/reports/review/*`, renamed |
| `POST /support/message` | session | trust.js | P1.8 | |
| `POST /support` | public (form) | trust.js | P1.8 | honeypot, per-ipKey limit |
| `POST /owner/support/list`, `/owner/support/update` | owner | trust.js | P1.8 | |
| `POST /ci/bench/publish` | ci, or `OWNER_KEY` | trust.js | P1.8 | design F's `/bench/publish`; `BENCH_KEY` dropped |
| `GET /privacy`, `/terms`, `/medical`, `/support`, `/accuracy`, `/accuracy.json`, `/legal.json` | public | legalpages.js | P1.8 | en/ar, no scripts |

Legacy routes whose behaviour changes without a path change:

| Route | Change | Package |
|---|---|---|
| `POST /auth/device` | `via` code: invite bucket, per-code cap, `joined_via` | P0.1 (hook), P1.1 (`inviteBucket`) |
| `POST /v1/chat/completions`, `/tts`, `/transcribe/chunk`, `POST /jobs` | AI-consent gate (flag `trust.aiConsentEnforced`, off by default) | P0.1 |
| `POST /v1/chat/completions` | optional `task: hint | reword | explain` (the micro path) | P1.5 |
| `POST /jobs` | optional `spec.cache` | P1.6 |
| `POST /account/delete` | runs every module's `onAccountDelete` in the fixed order (plan §3.1) | P0.1 |
| every session response | adds `owner: bool` | P0.1 |
