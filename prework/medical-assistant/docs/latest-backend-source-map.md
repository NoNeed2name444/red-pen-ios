# Latest native backend source map

Snapshot: `red-pen-ios-latest@faecd8cdccd92387ac777335588ebc548b0ab106`.

Actual full source reading is complete for all 53 UTF-8 files under `server/`, including fixtures, generated exemplar data, tests and scripts. `latest-server-full-read-coverage.json` records each path, SHA-256, bytes and consumed ranges. The original 205-file inventory in `latest-backend-read-coverage.json` includes earlier supporting-file reads; separate reader ledgers cover remaining non-server paths. Decoding or hashing a file alone does not count as source comprehension.

## Existing integration contracts

- `worker.js` routes authentication, subscription, pairing, sync, generation jobs, cloud model calls, transcription, TTS, accuracy, exams, support and diagnostics. Owner-only endpoints use the owner key; signed-in calls use session tokens. D1 schema and R2/Durable Object bindings are defined by `schema.sql` and `wrangler.toml`.
- `accuracy.js` accepts 1–4 items and runs `rules → claims → lookup → evidence → votes → jev → verdict → cache`, with typed timeout/failure outcomes. `accuracy-model.js` requires three model families for verification; MCQs are first solved without the key. Existing decision rules, thresholds and family definitions are source contracts.
- `claims.js` already ports the structured claim checks from Chat-me medical-verifier at `2f4fd4e`. The fixture contains 103 claim/evidence pairs and complete extracted fact expectations. Hard findings can hold a result at Check this; cached signals are gated again. The source explicitly excludes the question-side and date-context checks that do not apply to these items.
- `evidence.js` supplies Europe PMC, MedlinePlus and openFDA evidence. `jev.js` only adds the existing oath check and is inactive without its key and Pro payment configuration.
- `ai.js`, `breakers.js` and `switches.js` define provider chains, per-account allowances, payment reservations, free quotas, circuit cooldowns and feature refusals. `PRO_PAYS` governs paid sources. Tests use injected fake providers and real SQLite.
- `jobs.js` consumes the existing app job specification and MedVAL-style checker template. It preserves useful partial output, source-window attribution, item checks and collection/cancellation behavior. Its legacy checker path is distinct from `/accuracy/check`; the read does not authorize changing that contract.
- `exams.js` and the generated exemplar index correspond to the app catalogue. Tests compare exam IDs, option counts, exemplar sources, strictness and the bundled accuracy/rule tables against Swift source.
- `sync.js` uses revisions and atomic compare-and-set writes; blobs are checked by SHA-256 and scoped by account. Account removal also wipes jobs, TTS and diagnostics, followed by the existing nightly sweep.

## Reproduced mechanical gaps

1. Question-bank validation sends batches of eight, while the existing accuracy Worker accepts at most four. Five copies of the existing good fixture are all dropped solely because the real consumer returns 400, `Send 1 to 4 items.` Reproduction: `/tmp/redpen-qbank-batch-repro.mjs`. Proposed regression uses more than four existing valid fixtures and enforces the existing consumer batch limit; no validation policy changes.
2. `tts.js` checks a cached MeloTTS line after spending the daily line allowance. With free Aura characters disabled and a one-line allowance, the same line returns `200,429,429`, despite one generated/cached file. Existing tests assert cached repetitions cost nothing for Aura but do not cover this fallback cache. Reproduction: `/tmp/redpen-melo-cache-repro.mjs`. Proposed regression uses the existing fake MP3/SQLite fixture and expects `200,200,200`; consider both cache keys before spending, retaining Aura cache preference.

No source changes were made during this read phase.

## Verification and limits

`latest-backend-test-results.json`: 24 source-defined test files run offline, 22 pass with 1,228 passing assertion/check lines. The two remaining runs are environment-limited: claims cold-isolate subprocess and ASR CLI subprocess encounter Node EPERM, after 54 and 42 earlier passing checks respectively. Child network permission retries remained pending until interrupted and produced no execution results; root owns the retry. External global fetch was denied by the offline preload; all tests reported zero external fetch blocks. No live provider, deployment or orchestration was run.

All three source-defined Python Swift-package variants assemble successfully offline; `latest-native-package-results.json` records them. This is packaging validation. Swift compilation, Apple framework tests, simulator rendering and screenshots require the Mac workflow and were not verified here because the local Swift toolchain is unavailable.

The existing design preview workflow builds iPhone graph, iPhone tour and iPad outputs. Its artifact publication force-push conflicts with the repository instruction against force pushes. A mechanical proposal is to retain the newly staged artifact tree, attach its next commit to the fetched existing publication tip, and push normally; an absent publication branch is created normally. A concurrent publication update should reject the ordinary push rather than overwrite history. Existing dispatch filtering for `testDesignTour` can select tour tests while default matrix coverage remains unchanged. No workflow was triggered by this reader.
