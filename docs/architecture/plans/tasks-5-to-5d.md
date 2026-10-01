# Tasks 5 to 5d and the folder migration: the plans

Approved by the owner on 1 October 2026 ("go with all 3 decisions"), on the
scope below, which follows the research verdicts in Chat-me
`docs/architecture/research/`. Each plan keeps plan §1 Gate B's fields that
apply; status lines are kept current as the work lands.

## Task 5: Jev, the oath check (§22 Layer 7) and the card and question pilot (Layer 6)

| Field | Plan |
|---|---|
| Goal | No dose, diagnosis or treatment claim is shown as Verified on the models' word alone; Jev may add checks, never remove them. |
| Verdict it follows | §22a: Jev better in specific layers only; Layer 7 now, regex first, fail closed; Layer 6 card and question parts as a pilot; Layers 1 and 8 rejected; 3 and 4 shadow pilots later. Paid per call, so behind Pro money only. |
| Steps | 1. Two votes before Verified, Worker and app (done, 1d828fa). 2. Oath patterns: dose, diagnosis, treatment, identical in both, shared vectors (done, 1d828fa). 3. Jev adapter, inert without key and PRO_PAYS, 1-second budget, adds only (done, 1d828fa). 4. Layer 6 pilot (card quality, question type) in shadow: logged beside the verdict, never shown, once a key and Pro money exist. 5. Threshold tuning: 300 labelled Stethoscore items per gate, recall at least 0.99 for Layer 7, before Jev's answer is used for anything but adding checks. |
| Files | server/accuracy-model.js, server/accuracy.js, server/jev.js, server/wrangler.toml, ios/RedPen/Shared/Accuracy/AccuracyModel.swift, AccuracyLedger.swift, tests on both sides. |
| API models | Jev (jev-latest, pinned once tuned) for Layer 7 only; nothing new on the free chain. |
| Fail-safe | Jev unavailable, slow, refusing or unreadable: the patterns' answer stands. An unreadable dose pattern on the phone holds every item (fail closed). |
| Revenue | Trust in "Verified" is the product's claim; costs nothing until Pro money pays for Jev. |
| Risks | Fewer items Verified than before (intended); a dose phrased in an unusual way is missed by the patterns until Jev or a new pattern catches it. |
| Status | Steps 1 to 3 done; 4 and 5 wait for a Jev key and Pro money. |

## Task 5b: the question bank, from licence-checked free text

| Field | Plan |
|---|---|
| Goal | A pilot of about 100 exam-style questions, every one from openly licensed text, through the seven-step pipeline, before any scale. |
| Verdict it follows | §22d: yes with restrictions. No free bank is reusable; generate from an allowlist (Open RN under CC BY 4.0, MedlinePlus, CC0 and CC BY PMC articles, CC BY MedEdPORTAL items); refuse NC, ND, SA and unknown licences in code; per-item attribution; novelty screening; human review for high-stakes topics. |
| Steps | 1. Licence allowlist as data, with the licence text's URL and the date it was read, and a check that refuses anything else (governance/licences). 2. Source fetcher for the allowlisted texts, keeping each passage's URL and licence. 3. Generation on the free chain through the Worker's existing job path, with the exam exemplar prompts. 4. Validation: licence, the accuracy engine with the oath check, question-quality rules, blueprint tag, novelty against public sets. 5. 100 items to a pilot file with their metrics; nothing student-facing until reviewed. |
| Files | governance/licences/, prompts/question-bank/, evals/question-bank/, a GitHub Actions workflow to run it (secrets stay in Actions). |
| Fail-safe | A source whose licence cannot be read or is not on the allowlist is refused; an item that fails any step is dropped with its reason, never shown. |
| Revenue | The question bank is what students pay for (§22b); a clean licence trail is what lets it be sold. |
| Risks | Share-alike licences forcing the app open (refused in code); AI items' factual error rate (about 22% unreviewed per the brief), which is why the pipeline and review gate exist. |
| Status | Not started. |

## Task 5c: fail-safe, the §22f reduced protocol

| Field | Plan |
|---|---|
| Goal | Data integrity first, then retries and timeouts, then Worker circuit breakers and kill switches, with fault injection in CI. |
| Verdict it follows | §22f: §22e not sound as written; adopt the reduced protocol. |
| Steps | 1. Data integrity: the audit's data-loss P0s (done: unreadable library, failed write, recording replace, crafted zip, mock sitting); then the data P1s (#15 restore duplicates, #22 push-wins merge, #23 schedule too big, #24 restore report, #25 recovery copies). 2. Retries and timeouts: #88 a failed batch, #93 a result fetch, #94 a cancelled job (a system stop keeps the cloud job for the collector; the background task's expiry cannot be told from the student's Stop on the system progress indicator, which shows only while the app is away, so an expiry while away is taken as the student's Stop and deletes the job, as before; only one while the app is active keeps it). 3. Worker: a kill switch per AI feature in server config, read at launch; breakers on the free chain's providers. 4. CI fault injection: stubbed network (500, 429, timeout, garbage, offline) in Swift suites and the Worker's tests. |
| Fail-safe | Closed means Unverified or queued, never a frozen screen. |
| Status | Step 1's P0s done; P1s next. |

## Task 5d: orchestration without LangGraph

| Field | Plan |
|---|---|
| Goal | The verification pipeline as an explicit state machine with typed stage results and a time budget per stage. |
| Verdict it follows | §22g: no LangGraph now. Task 4's audit: the Worker's accuracy engine is the spine; the Python verifier folds in as modules. |
| Steps | 1. accuracy.js checkBatch as named stages (rules, evidence, votes, Jev, verdict, cache), each with a timeout and a result type, the same output as today (tests unchanged). 2. Background verification stays on the jobs Durable Object (already durable and resumable); Cloudflare Workflows only if a run ever needs more than its alarm loop gives. 3. Port the Python verifier's deterministic guards as a pre-vote claim gate (audit §10). |
| Status | Steps 1 and 3 built on design/plan-5d-stages. The gate's hold reaches the student: the reply's `claims.hard` is kept on the device (AccuracyRecord.claimHolds) and AccuracyLedger.assess re-grades from it, so a contradicted item, or one the gate failed on, is never Verified there either; a gate failure is asked about again later (from the cache). The gate's CPU is counted in work (MAX_WORK a batch): about 3 ms warm and 15 ms cold for the worst batch, within the free plan's 10 ms a request once an isolate is warm. Step 2 needs no change. |

## The §3c folder migration

| Field | Plan |
|---|---|
| Contract | agents/, tools/, orchestration/, prompts/, api/, governance/, evals/, tests/, docs/architecture/. |
| Default chosen | red-pen-ios: new non-app work goes into the §3c slots at the top (docs/architecture/, governance/, prompts/, evals/); the app (ios/) and the Worker (server/) stay where they are, as deployment units whose build tools and workflows depend on their paths (the audit gives clients and infrastructure no slot). Chat-me: the medical verifier moves into the tree per the Task 4 audit's mapping table. |
| Blocker | Chat-me is not attached with write access in this session; its part waits for that. |
| Status | docs/architecture/ made in red-pen-ios (this file); the other slots are made as their first files land. |
