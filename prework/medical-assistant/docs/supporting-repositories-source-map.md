# Supporting repository source map

Read-only source reconnaissance for the medical application integration. Facts below describe the pinned source; they do not choose a new architecture, medical interpretation, pedagogy, terminology license, or deployment provider. No runner, orchestrator, provider call, model download, workflow, or repository import was executed during this read.

## Snapshot provenance and completed coverage

Owner: `NoNeed2name444`. Materializer inventory: `docs/repository-read-inventory.json`, with repository path, Git blob SHA, byte size, mode, and materialization status. Materialized paths are under `/workspace/repositories/`.

| Snapshot | Commit | Git tree | UTF-8 blobs fully read | Bytes fully read |
| --- | --- | --- | ---: | ---: |
| red-pen-transcribe | bacceb01a23a4f1e0605a99f7be8555a8551b90b | 7f2f203dc5305fb797818f445062e17ae85a52ab | 77 / 77 | 458870 |
| Claude-Code | 993f8d84ccb092484ba09e52c2ef4ea55d6e9412 | 4b17eddd68620e28c001f993ec0f4b01db210c88 | 11 / 11 | 32170 |
| Chat-me main | f1bfe1f1720c075e2f89517960ac4b21572c3d40 | fb719d1589821e099369df1b16c155c163ce1d1b | 2 / 2 | 2691 |
| Chat-me personal | 4aa7e0641f84acf296c0df18335c6f1ff1006f10 | fa12fea020f8586caa54a5e86f7c2fc68a1336f1 | 194 / 194 | 996290 |

All original 90 files in the first three rows were displayed and read in full, including hidden configurations, 24 transcribe workflows, prompts, reference/fixture text, tests, and the entire 789-line/55,480-byte bridge worker. Large files were read in contiguous chunks. These three snapshots contain no materializer-classified secret or binary files; this says nothing about credentials outside their pinned trees.

All 194 Chat-me personal files were read fully, including its 208,798-byte plan, 56,223-byte Swift core, empty package initializers, tests, audits, research revisions, complete source lists, and `.env.example` (259 bytes, Git blob `ae26a7ca6bb1d8ac3c4594c6acafb32884d2aac3`). The template's API-key values are blank. Its keys include APP_ENV, VERIFIER_VERSION, DATABASE_PATH, NCBI_TOOL, NCBI_EMAIL, NCBI_API_KEY, OPENFDA_API_KEY, MAX_EVIDENCE_ITEMS, EVIDENCE_TIMEOUT_SECONDS, and HIGH_RISK_REQUIRES_REVIEW. Thus supporting coverage is 284 fully read files / 1,490,021 bytes across four snapshots of three repositories. `docs/supporting-read-ledger.json` records all supporting paths and completed contiguous personal read batches. Initially truncated grouped outputs were replaced by complete bounded reads; truncated output was not counted as coverage. All 284 local byte sizes and Git blob SHAs were rechecked against inventory.

Personal's `docs/architecture/handoff/context.md` explicitly supplies current application state and supersedes historical portions of plan.md. Main's two-file spec remains historical evidence. Current native Stethoscore is read separately at commit `faecd8cdccd92387ac777335588ebc548b0ab106`, tree `acf6214ba7ae6654d90a7b0b6e2c841af7494edf`, branch `preview/cursor-neuron-circuit-perf-d39a`; older native-main omissions are not port instructions. This supporting reader fully read only the four latest-native comparison files named in the ledger and searched selected others; it does not claim full native coverage.

## red-pen-transcribe mechanical contracts

### Bridge wire protocol

`bridge/worker.js` is a Cloudflare module Worker, version 2.3. It accepts an exact `/mcp/<SHARED_TOKEN>` path, requires a configured Gemini key and shared token before dispatch, serves a GET liveness string, and accepts POST JSON-RPC 2.0 (single request or batch). Protocol version is `2025-03-26`; methods are initialize, ping, tools/list, tools/call. Notifications return 202; malformed JSON returns parse error; tool execution failures are text content with `isError:true`. The advertised serverInfo version remains `1.0.0`, separate from bridge version 2.3.

Three tools are listed: `bridge`, legacy `transcribe_audio`, legacy `github_job`. The unified tool has `{action, params?, settings?}`. Actions: info, transcribe, github, update, verify. Settings override repository, branch, language codes (up to four), and `rules_pass:false`, per call; keys remain Worker environment bindings. Structured routes return both text content and `structuredContent`; transcription returns text content alone. This is MCP, not a generic application REST `/api` route.

Transcription arguments: `audio_base64`, `mime_type`, `language` (`mixed` or `en`), optional subject/glossary/prompt/model. Output is phrase lines `[m:ss] text`, relative to the current slice, with `[Speaker 2]:` for nonprimary speakers. Maximum accepted base64 length is 19 MiB (~14 MiB decoded). Prompt override is truncated at 8000 characters, glossary at 4000. `prompt="__bridge_info__"` returns metadata. Default requested model is explicitly pinned `gemini-3.5-flash`; a model name containing `transcribe` selects dedicated `gemini-3.5-transcribe`, regardless of the remainder of that requested name.

GenerateContent uses inline audio, text instructions, and temperature 0.1. Dedicated transcription uses resumable Files upload, polling, Interactions API with verbatim word timestamps, then deletes the temporary file in finally. Word annotations are converted into phrases by pauses/punctuation/14-word length. Optional rules pass requests JSON `{edits:[{line,text}]}`; times are retained from source, out-of-range edits and disallowed labels are ignored, and edits that lose Latin word count or change length outside existing bounds are ignored. Failed rules pass leaves the dedicated transcript intact. Unpinned auxiliary calls walk the source model list for retirement/quota errors; key rotation advances on success and retries other configured keys only for quota errors. These are existing source behaviors, not a selected model policy for the new application.

GitHub job actions: begin creates an `rp-...` prerelease and returns `{tag,release_id,url}`; upload_part stores byte pieces as `part-0000`; start writes job.json and dispatches transcribe.yml; status reports uploading/queued/running/finishing/done/failed; log returns failed-step tails; fetch returns `{tag,name,srt}`; list returns jobs; delete removes release and tag. `settings.github_repo` and branch control per-call target. Additional source actions api/get_file/put_file/put_files expose REST and one-commit Git Data operations; they are not needed to parse transcription results. Update/verify use Cloudflare Workers APIs and optional source SHA-256; this reconnaissance did not invoke them.

### Audio/pipeline callables and artifacts

| Source | Existing boundary |
| --- | --- |
| transcribe.py | `window_bounds(wav,sr=16000,window=30,search=3)` covers file with quiet-edge windows; `transcribe_windows(wav,recognise,...)` injects float32 chunk → text and joins nonempty results with spaces. Energy-VAD `speech_regions` is documented for labels only. |
| cohere_asr.py | `load(language="en",max_new_tokens=400)` loads source-defined NAMAA checkpoint and returns recognizer callback. Lazy model imports/download occur only on load. `degenerate(text,floor=20,share=.3)` rejects repeated-token runs. |
| committee.py | Lazy factories for cohere/cohere-ar/whisper-turbo/qwen3-asr; main reads SHARD/SHARDS/PAD/ENGINES and job/full.wav, writes shard metadata, engine texts, timings/errors to out/shard-N.json. Engines share the same window callback. |
| repair.py | Pure `repair(text,glossary,threshold=.86,max_ngram=3,latin_threshold=.90)` → `(text,[(source,term,score)])`, preserving lines. Source-defined skeleton/vowel/negation/stop-word/margin rules and exact glossary content determine substitutions. No model/network. |
| dictionary.py + learn.py | Apply pronunciation table by sound before fuzzy repair; `apply` → `(text,hits)`. `learn`, `confident`, `merge`, `to_lines`, `load_table` retain backer names, tab-separated source→English mappings; review artifacts are written separately from committed table. |
| consensus.py | `build([(engine,text)],lexicon,pivot?,quorum=2)` returns voted/text/repairs/disputes/unsupported/resolved_by_lexicon/per_column/columns/voters/pivot/agreed. Sound-based spacing/alignment retains pivot text for unresolved columns. |
| stitcher.py | Pure norm/overlap/stitch with source defaults; stitch returns text, overlap count, score. |
| join_gemini.py | `join_point`, `cut_at_line`, `join` locate next opening in previous tail; join returns lines plus explicit seam notes. CLI writes joined text. |
| merge_full.py | Merges raw and fixed shard text separately, exports cohere-full.txt/raw/repairs/summary including missing shards and unmatched boundaries. |
| committee_merge.py | Votes per shard, dictionary then repair, stitches, exports committee-record/summary/disputes/resolved/dictionary-hits/engines and learned/candidate pronunciation TSVs. |
| step1.py | `format_step1(segments,primary,timestamps=False)` retains source speaker/overlap/unclear signals; `check_step1` returns mechanical/advisory violations; `coverage` reports durations. Source Step1 forbids timestamps by default, unlike timed bridge output; adapters must preserve this distinction. |
| step2.py | `verify_lossless(source,formatted)` compares normalized word sequence, speaker markers, heading limits, supplementary-table markers/cells. `format_step2` preserves paragraphs. `format_with_model` injects generate callback, bounded attempts, then deterministic fallback and a report. |

The checked reference and fixture are lecture-specific. Their term-recovery/WER comments and test assertions are source evidence, not a measured accuracy result of this session. Lexicon/prompts contain existing medical text; their inclusion is no terminology/license or medical-content approval.

### Existing generation/export formats

`modes/render.js` extracts actual builders from an externally supplied HTML artifact (`red-pen-content.html` default) and writes rendered prompts containing SRC. Builders are buildPrompt, buildAnkiPrompt, buildBookPrompt, buildOscePrompt, buildQaPrompt. `run_modes.py` substitutes source into those prompts and invokes llama_cpp only when explicitly run. Its report keeps complete raw generations and separate hard/soft results.

Existing `validate_modes.py` wire shapes: MCQ `{questions:[{stem,options:[five strings],correctIndex:0..4,explanation}]}`; Anki `{cards:[{type:qa|cloze|occlusion,front,bullets,why,clozeText}]}`; OSCE `{checklists:[{title,steps:[at least two]}]}`; QA `{cards:[{type:recall|case,answer:[one to four bullets],topic,stem}]}`; textbook Markdown headings/tables. Existing validators report formatting/length/positional-reference clauses from existing prompts; this source map does not add pedagogic criteria. The MCQ format differs from the initial browser scaffold's caller-specified choices/choiceId/correctIds contract. That scaffold comparison is historical; the latest native application's own types and option order govern current integration.

`modes/mcq_fix.py` and native `MCQRepair.swift` replace positional explanation references with existing option wording; they report length issues instead of inventing distractors. Native file references Contracts and MCQQuestion from the native application. These are not standalone source files.

`AnkiExport.swift` emits `{deck,cards}` with stable card UUID string, `kind`, optional front/bullets/clozeText/why/image/occlusion/tags. Box is normalized `{x,y,w,h}`. Deck names use `Red Pen::subject::title`; slide media use slide-N.png. `tools/make_apkg.py` uses genanki, stable model/deck IDs and card IDs for GUIDs; input defaults export/cards.json and neighboring media. Generated cards start new in Anki; local scheduling is not serialized. Missing cloze deletion uses QA fallback. Existing export/cards.json is sample content, not user data.

`tools/medgemma_check.py` consumes occlusion cards `{kind:"occlusion",image,occlusion,answer?/front?,truth?}` and emits per-card model/card text, verdict, overlap, optional caller-truth comparison. It does not edit card answers. `medgemma_client.py` implements authenticated Gradio upload/call/chat SSE with bounded retry; model loading is separate. The prose mentions MEDGEMMA_ENDPOINT but code actually follows Space configuration; no dedicated endpoint implementation was found. Hosted-token/model decisions remain external, and no MedGemma semantic assessment was made here.

### Workflows and source-defined unresolved dependencies

The 24 workflow files were fully read. Most are manual-only audio/model probes, recording jobs, artifact joins, OCR diagnoses, export, or repair-maintenance tasks. Cohere-check additionally triggers on selected pushes. Numerous workflows write result branches or releases, sometimes with force pushes; none was run. transcribe.yml receives a release job.json and byte-sliced audio; it reconstructs audio, makes 1200s jobs, emits time-offset SRT from Whisper or Audar, reindexes merged blocks and publishes transcript.srt, or error.txt. Gemini-prep/segments produce independently decodable time slices and manifests; raw upload byte parts must be reassembled before decoding. gemini-narrate explicitly fetches the native repo's personal branch prompt/config and Firebase route, so it is a cross-repository dependency.

Source-defined prerequisites: prompt artifact for modes/render; model/runtime/media assets; native Domain/UI types for export/preview/MCQRepair; OCR Swift shared files referenced by ocr-verify; credentials/config for provider/bridge/hosted MedGemma; actual caller-provided recordings/cards. These omissions refer to the pinned transcribe snapshot only. The latest native application may already provide them and must be checked before copying implementations. The three historical repair-patch scripts are file mutations for exact prior repair states, not application adapters.

## Claude-Code contracts (no execution)

The schema defines AAHP v2 required v/id/attempt/status/objective/scope/accept/base/branch/reply, optional constraints/expires, and no extra fields. IDs T0000+, attempt nonnegative, dispatched|repair, objective max300, 1..20 scope paths, 1..12 acceptance `{id:A1+,check:max300}`, pinned hexadecimal base7..64, branch max200, reply max300. Full JSON Schema includes const/pattern/min/max/etc beyond staging's deliberately narrow external schema validator; use its original schema with a compatible validator or separately implement these mechanical assertions, not silently feed it to that subset.

Architecture/policy specify Git + AAHP durable state, pinned attempts, scoped diffs, one writer, bounded repair, task/result/lock/handoff directories, and reviewer-owned acceptance. Preferred result contains v/id/attempt/status/changed/checks/tests/commit/diffstat/notes. Reading these files does not authorize running Claude or the runner.

Runner source GET /health exposes provider/auth/app-server/protection flags. POST /v1/tasks requires RUNNER_SHARED_SECRET bearer, reads at most512KiB, validates a subset of task fields, serializes tasks on a Promise queue and starts Codex app-server. It returns completed with empty changed/tests/null commit/diffstat and reported_by_worker acceptance entries; actual Git evidence still must be collected. Runtime task validation is less strict than the task schema and does not implement all architecture invariants/lock/scope/Git verification. Source prompt even allows out-of-scope edits "unless required"; that differs from schema/policy strict scope and is an implementation discrepancy to retain in adapter documentation.

`runner/src/index.mjs` starts HTTP listener and provider at module load; do not import for passive validation. Default CODEX_MODEL is gpt-5.6-luna, different from the session's explicit Sol6.1/high model instruction. Protected SIWC records/token refresh and app-server spawn are separate execution functions, not needed for inert task/result validation. `CodexBridge` uses stdio JSON-RPC initialize/initialized/thread/start/turn/start and turn/completed. No actual task/lock/result/handoff state artifacts or result JSON Schema occur among the 11 pinned blobs. Mechanical integration may reuse packet validation/serialization and evidence mapping while leaving execution disconnected.

## Historical Chat-me main spec

Only README and COMMERCIAL_ACCURACY_STACK.md exist on the pinned main tree. Spec defines ASR backend interchangeability, forced alignment, span classes/candidate lattice, lexicon revision, structured comparison dimensions, canonical evidence deduplication and acceptance/abstention reasons. Production-run record fields are exact backend/revision, aligner revision, lexicon snapshot, terminology source revisions, audio segment timestamps, original ASR text, candidate alternatives, verification decision, evidence identifiers, reasons. Spec candidate license statements require checking exact weights/releases; no legal assessment was performed. This tree contains no executable verifier, aligner, API, tests or implementation to import. Canonical personal snapshot supersedes it for current implementation state.

## Canonical Chat-me personal: implemented boundaries

### Declared application state and document precedence

`docs/architecture/handoff/context.md` names the application Stethoscore (formerly Red Pen/CramDown), SwiftUI/SceneKit on iOS 26, with a Cloudflare Worker/D1 backend. It says the §3c folder migrations and cross-repository ports have already occurred, and the native accuracy layer replaces the old MedVAL route. It distinguishes the deterministic Chat-me verifier from the native §8 pipeline. These are source declarations, to be checked against the separately pinned latest native implementation before modifying ports.

The context's current order supersedes old plan task order, full-single-package delivery, and research targets that later became reduced or deferred. Existing owner constraints name iPhone/iPad-only operation, Mac GitHub Actions for native checks, no PRs or force pushes, free tiers, and explicit owner approval for backend deployment. Session instructions continue to govern this work: Sol6.1/high, source mechanics only, no Claude/orchestrator execution. Research briefs and their medical/design/commercial/legal verdicts remain attributed documents; no new verdict or approval is inferred from them.

Context declares a native policy requiring three independent blind model families before committed Verified/Flagged, with no dissent; otherwise Check this. It also records missing externally supplied Groq/Cerebras keys and incomplete real end-to-end measurement. This map does not adopt, weaken, strengthen or clinically evaluate that policy. Latest-native source is the authority for its implementation. Historical research tables referring to two votes or older single-vote findings do not establish current behavior.

### HTTP and serialization contracts

`api/main.py` exposes FastAPI, `GET /health` and the following `/v1` routes. No server authentication middleware, bearer validation, tenancy, model gateway or question-generation implementation occurs in this personal snapshot.

| Route | Source-defined request/result |
| --- | --- |
| POST /verify | ClaimRequest → orchestration.graph.verify → VerificationResponse; this reconnaissance never invokes it. |
| POST /drug/check | drug + search_terms → openFDA label evidence and warning; search_terms is accepted but unused. |
| POST /documents/ingest | Bounded caller text and metadata → persisted evidence ID, structure/extraction metadata. |
| POST /documents/pdf/ingest | Strict base64, max 20 MiB decoded PDF, `%PDF-` header → per-line evidence IDs, raw PDF SHA, page/block metadata, extraction score/warnings, manifest ID/SHA/parent. |
| POST /questions | Caller-provided prompt + answer + required curriculum snapshot and optional source IDs → validated, persisted QuestionArtifact. No writing model is called. |
| GET /questions/{question_id} | Stored QuestionArtifact or 404. |
| POST /benchmark/integrity | Inline/separate train/test records → content-bound manifest SHA, case count and explicit duplicate/provenance/split findings; optional enforcement returns 422. |
| POST /benchmark/snapshot/verify | Serialized schema-1.6 snapshot + optional expected SHA/provenance/split enforcement → validity and findings or 422. |

ClaimRequest contract `1.8`: claim (3–5000 chars), arbitrary JSON context, sources pubmed/openfda/local, evidence level any/authoritative/highest_available, mode current_medical/curriculum_faithful/curriculum_update_aware, curriculum IDs/snapshot, question_context, provenance_mode permissive/bound. Contract mismatch is an explicit result, not silently accepted.

VerificationResponse retains verdict, confidence and confidence_semantics, original/normalized claim, claim/risk type, atomic_assertions, evidence/contradictions, curriculum_assessment and current_evidence_assessment, knowledge_divergence, study_hint, source_revalidation, reliability, adversarial_findings, limitations, reasons, missing_context, requires_human_review, verifier/contract/snapshot versions and verification_id. Code defaults are verifier `1.6.0`, contract `1.8`, knowledge snapshot `LIVE-API`, policy `0.2-multi-axis`; verdict remains an unconstrained string. Confidence's source-defined semantics say policy score. There is no session measurement or new medical-copy decision here.

EvidenceItem preserves stable ID/title/type/publisher; URL and exact locator; publication/effective/source dates; page/section/block type/index/related IDs/language; passage; source family/canonical/study/independence/derived IDs; document version/curriculum snapshot; raw-source/passages hashes; retrieved time; extraction quality/warnings; authority/relevance/temporal/quality/support fields. QuestionArtifact carries source IDs and maps of locators/versions/file/passages hashes/pages/sections/types/relations/languages along with validation result, warnings, review requirement and generator version. Existing Swift QuestionArtifact has a related but distinct shape (e.g. locator/version arrays), so serialized shapes must not be assumed identical.

### Engine, storage and offline client mechanics

`orchestration/graph.py` is a synchronous function, not a LangGraph graph. It performs version check, normalization, bounded atomic assertions (at most four evaluated), source retrieval, existing deterministic guards, provenance and supersession, entailment/aggregation, source-defined policy, curriculum assessment, divergence, optional revalidation and persistence. Reading it did not execute its governance or medical policies. PubMed uses esearch/esummary metadata, not abstracts/efetch; its metadata passage is explicitly rejected as entailment by citation_integrity. openFDA fetches label records and binds canonical set ID, dated version, normalized record hash and passage hash. LocalEvidenceProvider reads SQLite rows filtered by source IDs/snapshot, with lexical-overlap fallback.

`AgreementGate` implements an injectable EntailmentProvider protocol, but the current assess_entailment path supplies exactly one StructuredProvider. It is a deterministic heuristic, separate from native multi-family model voting. Pure source helpers exist for assertion/claim decomposition, temporal dates, explicit aliases, measurements, structural alignment, citation/passages hashing, deduplication and grouping. Wrapper `independent_entailment.verify` computes dose-equivalence state before use; the older base `verify` retained below it references that variable before assignment on some paths. Current imports point at the wrapper; this is a source-only discrepancy, not a runtime finding from this session.

`governance/audit/store.py` creates/migrates four SQLite tables: evidence, questions, source_manifests, verification_audit. Evidence insertion preserves caller metadata; question/verdict/manifest writes use INSERT OR REPLACE, while evidence uses INSERT. Source-manifest hashing canonicalizes sorted evidence entries and binds an optional parent hash; storage requires an existing parent. Verification rows are ordinary JSON rows, not source-manifest hashes. The 1.6 benchmark manifest separately hashes each case's content/metadata and binds ordered case IDs/digests, schema version, dataset/snapshot and optional parent. These two manifest formats are distinct.

PDF extraction uses pypdf page text and makes each nonempty normalized line a block. Caption/table typing and immediate-caption linkage are marked as heuristics; warnings cap quality to 0.84 while curriculum threshold is 0.85. It contains no native geometry, OCR fallback or figure-image semantic reconstruction. Preserve those existing signals when transporting extraction results.

Swift Package `clients/ios/MedicalVerifierCore` targets iOS16/macOS13 and exports SourceSnapshot/SourceHasher/SourceManifest/SourceIntegrityChecker/CurriculumVerifier/QuestionArtifactFactory, JSONValue, API request/response/client and OnlineFirstVerifier. The client requires HTTPS, optionally sends a bearer, posts v1/verify, and checks returned contract version. OnlineFirstVerifier performs local curriculum checks, sends IDs/snapshot plus prompt context, and returns the local result alongside either server result or networkError/authoritativeSource. It does not upload/ingest local snapshots automatically. Python and Swift manifest digest payloads use different field naming/serialization; cross-platform equality of manifest SHA must not be inferred from shared semantic-vector tests.

The shared corpus has 35 cases and version1.3; Python question-validation tests and Swift package tests read it. Unit/integration tests, fake-provider probes and reports were all fully read. Historical reports claim 170 offline tests and list later milestones; those reports are not this session's execution evidence. No test, probe, API listener, import, provider or evaluation runner was executed here. `Dockerfile` and verifier README retain `uvicorn app.main:app`, but materialized runtime entrypoint is `api/main.py`, and no app package exists. `pyproject.toml` discovers api/agents/orchestration/governance/tools/evals and excludes clients/tests. The workflow runs Python and Swift jobs on Ubuntu; it was not dispatched.

### Source-defined remaining work and historical documents

The current context records ports/35-vector parity/native spine as existing work, and reserves actual model-family keys and real end-to-end measurements as outstanding. The 2026-09-30 Task4 audit compares older commits, so its absent-module and suggested-port tables are historical until reconciled against latest-native paths. The 127-finding native audit cites older personal commits and marks some fixes; those labels are the document's prior findings, not newly verified defects or permission to fix every item now.

The complete 4121-line plan and all research revisions were read. Their proposals include additional source/version/retraction registry, typed errors, claim provenance, rebuilding/quarantine, comparison of curriculum/current evidence, reviewer workflow, question-bank generation/statistics, model evaluations, optional Jev adapters and future graph work. They do not prove these components are implemented in personal API code. Context's declared reduced fail-safe/no-LangGraph and limited/inert Jev policy wins over earlier plan ambitions. No Jev/LangGraph/NLI/embedding dependency or executable Jev adapter, code-switch lattice/forced aligner, reviewer queue, calibration dataset, clinical holdout or model-generation stage is supplied by this personal verifier code. Retain these as source-defined artifacts or externally decided work, without creating a new schema, content, medical judgment or architecture.

## Latest-native mechanical reconciliation

Comparison base is latest-native commit `faecd8cdccd92387ac777335588ebc548b0ab106`, not old native main. Across pinned tree metadata there are zero nonempty byte-identical Git blobs between that native tree and each supporting snapshot. This establishes file divergence, not absence of functional ports. Complete native read coverage is owned by the native/backend readers; this reader fully read `server/claims.js`, `server/evidence.js`, `ios/RedPen/Shared/MCQRepair.swift`, and `ios/RedPen/Shared/AnkiExportSchedule.swift`, and inspected named integration branches by bounded source excerpts.

| Supporting boundary | Actual latest-native counterpart and mechanical drift |
| --- | --- |
| Python deterministic claim guards | `server/claims.js` expressly names the older Chat-me commit `2f4fd4e`, with claim reasoning, independent entailment/base, semantic guard, consistency, entity/date normalization ports. Its comments identify `server/tests/claim-vectors.json`, `server/tests/claims.test.mjs`, and `server/bench/claim-vectors.py` as the 35-vector and native-pair comparison mechanism. It explicitly omits dated-evidence temporal_guard and question-side adversarial/risk/rules. It adds native item extraction, Unicode/dose normalization, restatement filtering and bounded `{hard,soft,checks,work,complete}` work; these are existing integration adaptations. |
| Guard invocation and result | `server/accuracy.js:419` runs claimsStage with a shared work budget before evidence/votes. `describe` at line247 emits optional `{claims:{hard,soft,partial?}}`; a hard finding changes graded Verified to Check this, while other graded states remain. Exceptions emit gate_failed hard findings and incomplete state. This is already wired and does not call the personal FastAPI orchestrator. |
| Model-family policy implementation | `server/accuracy-model.js:124` defines MIN_VERIFY_VOTERS=3. Actual Verified branch at lines184–198 requires three passing families, evidence or lecture backing, no minor/severe rule, no concerns/evidence contradiction, and three blind MCQ solves reaching the key with no blind dissent. Actual Flagged branches also include no-model severe-rule and severe-rule/low-score paths besides three-family MCQ alternative-answer and unanimous three-family card paths. These are the existing branches; context policy summaries must not conceal their details. |
| Suggested key correction | `server/accuracy.js:280` first groups other blind answers by families and checks MIN_VERIFY_VOTERS, then retains an additional at-least-two unanimous-other-answer fallback. Its preceding comment still says two families. This branch is recorded without a new policy judgment or change. |
| Personal EvidenceItem and source manifests | Native `server/evidence.js` gathers Europe PMC abstracts, MedlinePlus summaries, openFDA label sections; accepts injectable fetch; caches one day; emits `{id,source,title,url,text}` after URL/title deduplication and a 7000-character passage limit. It does not serialize the personal API's EvidenceItem source/passages hashes, revalidation fields, curriculum divergence or manifests. These response contracts and digest payloads are not interchangeable. |
| Transcribe MCQRepair | Latest `ios/RedPen/Shared/MCQRepair.swift` explicitly cites the transcribe copy's `choice B` letter-reading issue, extracts captured capital letters, handles lists, leaves key-conflicting stated answers intact for AccuracyRules, resolves colliding shortened option names using full text, and leaves length rejection with MCQGenerator. Retain this current implementation rather than copying the older Domain file. |
| Transcribe Anki JSON/genanki export | Native `ios/RedPen/Shared/ApkgExporter.swift` is an existing APKG implementation (searched call sites); fully read `AnkiExportSchedule.swift` maps local ReviewRecord to Anki review/new/suspended fields and media signatures. The supporting JSON/genanki path creates new cards without this local schedule. The native schedule path is already present, so the older export's absent schedule is not an instruction to port it. |
| Standalone ASR/repair/consensus | Latest-native path inventory has no transcribe.py/cohere_asr.py/committee.py/repair.py/consensus.py/dictionary.py/lexicon.py/stitcher.py files, and has pipeline/tools/card_quality.py and quiz_from_cards.py. Filename absence alone does not establish missing native behavior: use current native audio/generation paths documented by the native reader before proposing any port. |
| Claude-Code runner | No byte-identical runner/schema copy appears in latest-native tree metadata. The supporting schema and packets remain available as inert artifacts; running the runner or creating a new execution route is outside this read. |

The already implemented native guard/model spine is distinct from the personal verifier HTTP/SQLite service and Swift Package. The context's remaining externally supplied model-family keys and real end-to-end measurements remain source-defined work; this session's read is not measurement evidence. No new spine, runtime schema or provider path is selected here.

## Container entrypoint correction proposal

`Chat-me-personal/Dockerfile:19` runs `uvicorn app.main:app`; there is no app package in the pinned tree. `api/main.py` defines app, and pyproject package discovery includes api. `docker-compose.yml` provides build/env_file/volume/port settings with no command or entrypoint override, so it inherits that CMD. `docs/architecture/verifier/README.md:26` repeats the obsolete quickstart target.

The prepared patch `docs/proposals/chat-me-container-entrypoint.patch` changes just these two module targets to `api.main:app`. It has not been applied to source. A temporary copy of the pinned originals passed `git apply --check`; static parsing confirmed the Docker JSON CMD, existing api/main.py app assignment, absent app package, and absent Compose override. This validation neither imported API/orchestration/governance nor started Uvicorn.

When runtime execution is separately within scope, the meaningful follow-up is a disposable image build followed by a network-isolated container with no host credentials/volumes, an ephemeral DATABASE_PATH, and a GET /health check from inside that container; no /v1/verify call is necessary to validate the entrypoint. That runtime check would import the API and its orchestrator dependencies and was deliberately not executed under the present no-execution instruction. No deployment is required for this mechanical correction.

## Integration seams identified without new decisions

1. Retain source wire formats and exact source references/revisions. The initial browser scaffold's createApi/createController comparison is historical; current native source contracts govern any existing transport mapping.
2. Adapt recognized audio chunks through existing callback boundaries and preserve raw/fixed/hit/dispute/seam reports; distinguish relative phrase times, word timestamps, absolute SRT offsets, and untimed Step1.
3. Translate existing generation/export field names mechanically using existing native schema/model order. Use existing validators only for their specified mechanical contracts; they are not a newly issued clinical/pedagogic verdict.
4. Represent Claude-Code AAHP packets as inert typed artifacts and validate actual task schema. Keep runtime execution/configuration and reviewer decisions external per session instruction.
5. Retain the existing latest-native ports identified above. Unresolved dependencies refer to their pinned supporting snapshots and do not establish missing native functionality. Parent owns final source changes and integration.

## Fully read path evidence

The following per-file rows identify all 284 fully read supporting blobs; byte size and Git SHA come from materializer inventory and were cross-checked against local files, including the fully read config template.

| Repository | Path | Bytes | Git blob SHA | Read |
| --- | --- | ---: | --- | --- |
| red-pen-transcribe | `.github/workflows/apkg.yml` | 1775 | `a4ad4a1b879b173653c2809ca6900d2c3c7206fe` | full |
| red-pen-transcribe | `.github/workflows/asr-shootout.yml` | 18619 | `1ac855d917825d53e16220f5bc8dee75adc5349d` | full |
| red-pen-transcribe | `.github/workflows/cohere-check.yml` | 1819 | `e7c6f3b14f379b66c79e9a0c291c20ea9060ed0d` | full |
| red-pen-transcribe | `.github/workflows/cohere-decoder.yml` | 2603 | `13d4a6cd438b07666e5f17c9d536f4bbd559e3bd` | full |
| red-pen-transcribe | `.github/workflows/cohere-full.yml` | 5900 | `b3ee7eeb7b8d801b40b63a9675d64c018bbcfa26` | full |
| red-pen-transcribe | `.github/workflows/cohere-merge.yml` | 2137 | `95ba33c3a772d45c7108dd0faf3b7cb66c12f1cf` | full |
| red-pen-transcribe | `.github/workflows/cohere-probe.yml` | 9039 | `01ccfe78375a919d6d425193990155ea6946934b` | full |
| red-pen-transcribe | `.github/workflows/cohere-windows.yml` | 9186 | `c199954a571c2be5c65c1cbfaea5c334dee59db5` | full |
| red-pen-transcribe | `.github/workflows/committee-revote.yml` | 2328 | `8f7ae9f3a009ca471d55483d901abec9532dc9b2` | full |
| red-pen-transcribe | `.github/workflows/committee.yml` | 4343 | `71d43759d8f7ad2b35cf367bdae38d7b904ff9d4` | full |
| red-pen-transcribe | `.github/workflows/gemini-narrate.yml` | 6197 | `535d525771213c681c2f315caf44560e14e44b8e` | full |
| red-pen-transcribe | `.github/workflows/gemini-prep.yml` | 4837 | `e16a987b87534a3526a8ad083a2a14c16058040f` | full |
| red-pen-transcribe | `.github/workflows/gemini-probe-window.yml` | 2267 | `7af8683846a74f6dc55ad5b03433faadc160215e` | full |
| red-pen-transcribe | `.github/workflows/gemini-segments.yml` | 5009 | `dee14bc8d05d4ba80558b78090ad721658064e19` | full |
| red-pen-transcribe | `.github/workflows/local-pipeline.yml` | 16013 | `b0a393d728856f76f4d19b3ed4af3a937729e178` | full |
| red-pen-transcribe | `.github/workflows/ocr-diag.yml` | 4979 | `f660005f3c458cdf8bc467d5e19d0d824e3f4f32` | full |
| red-pen-transcribe | `.github/workflows/ocr-shortcut.yml` | 9806 | `26257ebee0f108105c6e9fe4e890ac065b612cde` | full |
| red-pen-transcribe | `.github/workflows/ocr-verify.yml` | 4064 | `b06ffff814d86f4c92f18cf36547167eac3b515f` | full |
| red-pen-transcribe | `.github/workflows/qwen-probe.yml` | 1140 | `0aaab6ddf94587876d2b0b43faad7fa1638d4b29` | full |
| red-pen-transcribe | `.github/workflows/redpen-local.yml` | 16121 | `4e24e0b16c6dab0b7bb4a329469fe10f543ff051` | full |
| red-pen-transcribe | `.github/workflows/repair-lab.yml` | 1022 | `7272b44d6255bb65e88e45c528379b729b205345` | full |
| red-pen-transcribe | `.github/workflows/repo-patch.yml` | 2629 | `62a22cc22d6973a7cd854856e6edaf85dda642a2` | full |
| red-pen-transcribe | `.github/workflows/screens.yml` | 4543 | `3ed5c3345c5cc4d9bf02c96d81b27acc54216618` | full |
| red-pen-transcribe | `.github/workflows/transcribe.yml` | 17800 | `6b82e98d5794346ad32932795691676a0ddb722e` | full |
| red-pen-transcribe | `.gitignore` | 13 | `c18dd8d83ceed1806b50b0aaa46beb7e335fff13` | full |
| red-pen-transcribe | `README.md` | 20 | `4f71b78835ce6f36d202c8df0d91514c01e38cfe` | full |
| red-pen-transcribe | `bridge/worker.js` | 55480 | `050f1ab24f7dc445e5b35cd182a574bc3222de87` | full |
| red-pen-transcribe | `cohere_asr.py` | 4044 | `c9967d295147dfa63863ea39e712c82461b81f89` | full |
| red-pen-transcribe | `committee.py` | 6864 | `117465559939db92cab9036016c3d5dc5b5b2f40` | full |
| red-pen-transcribe | `committee_merge.py` | 6337 | `42e915f691841901ee12569492731b7111e992b3` | full |
| red-pen-transcribe | `consensus.py` | 11135 | `657b0e4f1b8a01db2f1ec362bc0f11524bab6acb` | full |
| red-pen-transcribe | `dictionary.py` | 2391 | `3c58f3cbabae7cfc39c2a55dd5e1cf4c8b56f547` | full |
| red-pen-transcribe | `experiments/decoder.py` | 7114 | `bd39e1a432e165997f4f0226fc60ea7fb1d49b89` | full |
| red-pen-transcribe | `experiments/qwen_probe.py` | 5077 | `87661be14fe3acbae03cfaf9344c466b255a9246` | full |
| red-pen-transcribe | `experiments/repair_lab.py` | 3695 | `5072a7d5f4cda533406e1cfe3b2183b452dc3d1c` | full |
| red-pen-transcribe | `export/cards.json` | 1152 | `eb9b60b70574557d05624f95cfb2c324292fdd16` | full |
| red-pen-transcribe | `ios/RedPen/Domain/AnkiExport.swift` | 4670 | `dde769f9dda61854f2c5547ee0b34942115229f7` | full |
| red-pen-transcribe | `ios/RedPen/Domain/MCQRepair.swift` | 5345 | `209592f1b7e2a2e3fc47507c0e5d6de914cd909f` | full |
| red-pen-transcribe | `ios/RedPen/Preview/PreviewApp.swift` | 10618 | `c7208e7e3defb8821b882729ac21963d1eeeec73` | full |
| red-pen-transcribe | `join_gemini.py` | 4411 | `f97230e590f3d74a36ad91429c6f16a67dc160e3` | full |
| red-pen-transcribe | `learn.py` | 6826 | `842c807220a70cf8651180a196b7fe87cfb5aa26` | full |
| red-pen-transcribe | `lexicon.py` | 1482 | `dc0a950547e337889db869d1c5108491dc20596c` | full |
| red-pen-transcribe | `merge_full.py` | 4655 | `a33bcc609b98ec885847690f03547a200c36d3c1` | full |
| red-pen-transcribe | `modes/mcq_fix.py` | 5414 | `fe70f92d53557e21f7e13748cc909c9369c74508` | full |
| red-pen-transcribe | `modes/render.js` | 2441 | `007010791f1b31000c9468588cc7f0f14fcb8a27` | full |
| red-pen-transcribe | `modes/run_modes.py` | 5158 | `3e0f9f6a20e99250f951d8e09b41e636890aa98c` | full |
| red-pen-transcribe | `modes/validate_modes.py` | 10984 | `807ea3bb6687d9020be2bcf230cd2f1aac87ce11` | full |
| red-pen-transcribe | `prompts/glossary.txt` | 269 | `c0d39c11a456a2cfb9579a36847ecd549d109d99` | full |
| red-pen-transcribe | `prompts/medical-lexicon-extra.txt` | 3934 | `8f1c24bd762b6d1e1c2ab4688083dc82d9b6f3ff` | full |
| red-pen-transcribe | `prompts/medical-lexicon.txt` | 2317 | `479d0eeeebda25652cb41a94a2b13e14b2e21b7f` | full |
| red-pen-transcribe | `prompts/pronunciations.tsv` | 745 | `66994f363a9febb47cca76eff8f4172e55204957` | full |
| red-pen-transcribe | `prompts/rewrite.txt` | 1928 | `3d7d6445cc6f2f255cc61cfa2d4792c051550fe0` | full |
| red-pen-transcribe | `prompts/step1.txt` | 3704 | `20316e355d8fc2518d5fe1f769062d5c3a3fc213` | full |
| red-pen-transcribe | `reference/gemini-3.5-flash-step1.txt` | 717 | `6af5a52d8170e2113df15478f7302dd9a5aa1713` | full |
| red-pen-transcribe | `repair.py` | 20347 | `57ee67b5d9db6a5aa69fcc8767bc0e833ce8eecc` | full |
| red-pen-transcribe | `step1.py` | 7453 | `2947e077b466c44045559cbf796b912b3ed46424` | full |
| red-pen-transcribe | `step2.py` | 10917 | `5a7100fefce7e6e26ba6559b8a35a1f5cffd6505` | full |
| red-pen-transcribe | `stitcher.py` | 2966 | `377302f1c8858227ee33e7f5945b47f24a0e23be` | full |
| red-pen-transcribe | `tests/fixtures/cohere-window-90.txt` | 784 | `b9668eb5a42981396ed07ddf49a330be5d52eab1` | full |
| red-pen-transcribe | `tests/test_apkg.py` | 4251 | `f2e745c96070f0956de1ec0026ee35ea870900cb` | full |
| red-pen-transcribe | `tests/test_cohere.py` | 2708 | `b2887cf60485e1383f4bd401926cd4278012ecdb` | full |
| red-pen-transcribe | `tests/test_consensus.py` | 3642 | `bb646b94c9883c798bf4730e09f2b7bad699eb49` | full |
| red-pen-transcribe | `tests/test_dictionary.py` | 2421 | `ef30ffea4fb1ef6c9ac329be830658b0969f7af3` | full |
| red-pen-transcribe | `tests/test_medgemma.py` | 3081 | `a2daef25c28947b099a7b20ab07909fd9e3a5fdc` | full |
| red-pen-transcribe | `tests/test_repair.py` | 2679 | `600f17ebbaa129eba4cf311b2eb4ae73e032059b` | full |
| red-pen-transcribe | `tests/test_repair_rules.py` | 3498 | `7759762b8e5cf1f295c01d989bf8f2d6a37f9196` | full |
| red-pen-transcribe | `tests/test_repair_vowels.py` | 1842 | `4e94fd935f1ec3c3843627ba42a0e307c5acb55c` | full |
| red-pen-transcribe | `tests/test_repair_window.py` | 2750 | `92b9a5e20275f1679a1fdfe4301973646df9e0e5` | full |
| red-pen-transcribe | `tests/test_step2.py` | 2907 | `8761ecbe83d04d5ecb1acc55b77ca62c006a25b9` | full |
| red-pen-transcribe | `tests/test_stitch.py` | 2126 | `4845dbba755a30d974533bf98af4677f5be7a5dd` | full |
| red-pen-transcribe | `tools/evidence.py` | 11772 | `450943c0c2fc9e1b54bdc98d27e530f07f9e7349` | full |
| red-pen-transcribe | `tools/make_apkg.py` | 7551 | `f9fc9748edc989d4a1712a26ac477de26af0c1aa` | full |
| red-pen-transcribe | `tools/medgemma_check.py` | 10022 | `a661700f221de1c24952e0e2ccae9c42428a73e2` | full |
| red-pen-transcribe | `tools/medgemma_client.py` | 6002 | `c49807fc7ce7a6bbaaea26a792f3a8c63ae2ffd6` | full |
| red-pen-transcribe | `tools/tighten_repair.py` | 6145 | `94502a47c109a3cfdb15fe88d662c74549c31b94` | full |
| red-pen-transcribe | `tools/vowel_floor.py` | 4570 | `6c1269aaf1f69f16f17f2f16f78b7eff15837ff0` | full |
| red-pen-transcribe | `transcribe.py` | 5320 | `ab394f0ddafa73a5eb472b66753fe2a878e74181` | full |
| Claude-Code | `.ai/task-schema.json` | 1757 | `420c8497bbbe83cf82d0a138d29b04e225f66d08` | full |
| Claude-Code | `.claude/CLAUDE.md` | 2937 | `bd8d29f81644d4b25c1f233772dcf6d068c07460` | full |
| Claude-Code | `README.md` | 13 | `1460c2586a0c6705206a48afab1c2c708447e17b` | full |
| Claude-Code | `docs/ARCHITECTURE.md` | 6927 | `4c2abc6463eb7ee00b17bc38bbf89ad357d0714f` | full |
| Claude-Code | `docs/CLOUD-RUNNER.md` | 3540 | `3446e4cdab2960c1c7cdabb972a3228d0f146fb4` | full |
| Claude-Code | `runner/.dockerignore` | 29 | `0c8ddf62e7244a9185cb7b7f525efe4153bee6a5` | full |
| Claude-Code | `runner/Dockerfile` | 460 | `1350f1c28ecc6360989fdb6185d5c43d93fa94d0` | full |
| Claude-Code | `runner/README.md` | 2587 | `f50923588233fb06f14ef4599c5c37269eb6d839` | full |
| Claude-Code | `runner/package.json` | 192 | `ac1fabd50921025391c629ad29c114c2c9ea3efa` | full |
| Claude-Code | `runner/src/codex-bridge.mjs` | 5089 | `86e4de9957b595c0475770e1df9758f1136551e6` | full |
| Claude-Code | `runner/src/index.mjs` | 8639 | `6b0f94f4245365655cbd8d8315f9f9c700e1c10c` | full |
| Chat-me | `README.md` | 9 | `d821bbd1bf9f31a64ec6fb832ea319923fcde6b2` | full |
| Chat-me | `medical-verifier/docs/COMMERCIAL_ACCURACY_STACK.md` | 2682 | `711324b9f2b2c0a4f99f33922b6972492cacff99` | full |

| Chat-me-personal | `.env.example` | 259 | `ae26a7ca6bb1d8ac3c4594c6acafb32884d2aac3` | full; API-key values blank |
| Chat-me-personal | `.github/workflows/verifier.yml` | 844 | `d9ee67b7632925b64eac5460a514187b36cd5f8d` | full |
| Chat-me-personal | `.gitignore` | 100 | `e645abab8972ccf60fdb4797429bf05e5d732062` | full |
| Chat-me-personal | `Dockerfile` | 341 | `0d81ca4be6556927595befb2bf91b20923a914ac` | full |
| Chat-me-personal | `LICENSE` | 1071 | `f008b1010b979b3da706bb9d0177f8dfda4324b1` | full |
| Chat-me-personal | `NOTICE` | 312 | `f73cd7486949367df8adadc3dfb625b754b6d5c7` | full |
| Chat-me-personal | `README.md` | 9 | `d821bbd1bf9f31a64ec6fb832ea319923fcde6b2` | full |
| Chat-me-personal | `agents/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `agents/specialists/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `agents/specialists/retrieval_agent/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `agents/specialists/retrieval_agent/citation_integrity.py` | 2416 | `053fb67dac5bb90b0221b112f5f89bc0614fc945` | full |
| Chat-me-personal | `agents/specialists/retrieval_agent/local.py` | 4785 | `82e81209d29b85af037997f9714f0d0d4a2943d7` | full |
| Chat-me-personal | `agents/specialists/retrieval_agent/ncbi.py` | 2851 | `34f193d30189e50a0bbeb282215f1b303a4468a2` | full |
| Chat-me-personal | `agents/specialists/retrieval_agent/openfda.py` | 4285 | `9e97733fee080144bb898f6a360d44b5ef304485` | full |
| Chat-me-personal | `agents/specialists/retrieval_agent/provenance.py` | 2765 | `13e55fb2d056caf2a238dac3e4f46a86019bbaec` | full |
| Chat-me-personal | `agents/specialists/retrieval_agent/revalidation.py` | 3810 | `bedbc981f9db22e1d584b2539d1d660033fcd8df` | full |
| Chat-me-personal | `agents/specialists/retrieval_agent/sources.py` | 322 | `bacbf665083560d15ce5a9779259bde482ac77e3` | full |
| Chat-me-personal | `agents/specialists/verification_agent/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `agents/specialists/verification_agent/assertions.py` | 1999 | `bd35e2d56827e47d2ad1c9de26b846de75743a42` | full |
| Chat-me-personal | `agents/specialists/verification_agent/claim_reasoning.py` | 10617 | `8f619675239987b26e8bbfdceda2450d4588ed24` | full |
| Chat-me-personal | `agents/specialists/verification_agent/consistency.py` | 1484 | `2a60d5df0a8fd8fd416a82ff017384714619629c` | full |
| Chat-me-personal | `agents/specialists/verification_agent/contradiction.py` | 2255 | `695af6578dc78ea4069f6f2aedf5ab9bc4bad0b4` | full |
| Chat-me-personal | `agents/specialists/verification_agent/correlation.py` | 1079 | `434ff0972aeb308f0c2e83189d91baff73254c02` | full |
| Chat-me-personal | `agents/specialists/verification_agent/curriculum.py` | 8019 | `b164712cbc379bdc2305ead39c999409350ec27d` | full |
| Chat-me-personal | `agents/specialists/verification_agent/entailment.py` | 2123 | `d30db7cf5123a8bab4d256f19ac1bcebb1575de7` | full |
| Chat-me-personal | `agents/specialists/verification_agent/entailment_provider.py` | 1855 | `9c667b050f03e3003a3d815016f21511f16f8fe9` | full |
| Chat-me-personal | `agents/specialists/verification_agent/entity_normalization.py` | 1024 | `ccbba12a393327cb363574d419b38627df4d3492` | full |
| Chat-me-personal | `agents/specialists/verification_agent/independent_entailment.py` | 5286 | `784ceb99b5688fbc1d7cf993eea8940a32adbc95` | full |
| Chat-me-personal | `agents/specialists/verification_agent/independent_entailment_base.py` | 17040 | `7d29a9ff278956d7ec70b40dce86daba286a0e61` | full |
| Chat-me-personal | `agents/specialists/verification_agent/question_validation.py` | 6993 | `a32f19740e31513a78282dd17d93522111a86ba5` | full |
| Chat-me-personal | `agents/specialists/verification_agent/reliability.py` | 4559 | `0ff23af1f70ca056e02dcfae02dfa83b82775a1b` | full |
| Chat-me-personal | `agents/specialists/verification_agent/reliability_report.py` | 1116 | `f7b1174623ab719ad6dae6e22c28526eb1c6a3a8` | full |
| Chat-me-personal | `agents/specialists/verification_agent/semantic_guard.py` | 7743 | `1207ebe275603165b66e17de493d1354e505518b` | full |
| Chat-me-personal | `agents/specialists/verification_agent/temporal_guard.py` | 781 | `fa8fed5447b7c5baef1b871317b592d25844af5e` | full |
| Chat-me-personal | `agents/specialists/verification_agent/temporal_normalization.py` | 2011 | `cd406444d6fa0df467e20215687b52b192096d03` | full |
| Chat-me-personal | `api/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `api/config.py` | 701 | `439ff19b636a95e98c7c5e09da2cf4bea4b2369b` | full |
| Chat-me-personal | `api/main.py` | 927 | `720c0101f45c72398f3a6d2f34927a1c17709f52` | full |
| Chat-me-personal | `api/routes/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `api/routes/benchmark.py` | 10105 | `55fea92ed1c51cc411a61d2018a21327c7b0d2cf` | full |
| Chat-me-personal | `api/routes/documents.py` | 9024 | `930b91c6994af83704a80fb66eac83c22e48e76e` | full |
| Chat-me-personal | `api/routes/drug.py` | 630 | `b9479a61dddd32f0a0b118a7d2c09c8862763161` | full |
| Chat-me-personal | `api/routes/questions.py` | 3564 | `e01c8f0d6d1a0389277881ab3e8623e1899c03e9` | full |
| Chat-me-personal | `api/routes/verify.py` | 340 | `274ad97fcad21d8aaacd5bc79ea8c6f9fa705e6c` | full |
| Chat-me-personal | `api/schemas/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `api/schemas/benchmark.py` | 2541 | `e987ac3d045957af980196c6d1ec84a5e163dff3` | full |
| Chat-me-personal | `api/schemas/claim.py` | 1118 | `82efb94dbf7798a38a52ce48a7aa6752b8122344` | full |
| Chat-me-personal | `api/schemas/evidence.py` | 1820 | `1b321c826149c2980f00032c6a603a0b9573b24d` | full |
| Chat-me-personal | `api/schemas/question.py` | 1157 | `3d930bffd5e5fc01025ad12eea53765e1d97d265` | full |
| Chat-me-personal | `api/schemas/verification.py` | 1021 | `c4ce4e1948edc0d51101c28babc81b8712a950f9` | full |
| Chat-me-personal | `clients/ios/MedicalVerifierCore/Package.swift` | 606 | `1a85743a10cd503dd3f49ea1c00317643c19a393` | full |
| Chat-me-personal | `clients/ios/MedicalVerifierCore/Sources/MedicalVerifierCore/MedicalVerifierAPIClient.swift` | 7467 | `6639689f7c2f677fc8930a35383b55fc7da1d942` | full |
| Chat-me-personal | `clients/ios/MedicalVerifierCore/Sources/MedicalVerifierCore/MedicalVerifierCore.swift` | 56223 | `4e2626d98b9e051c6d7fdf323eb70d169334da1f` | full |
| Chat-me-personal | `clients/ios/MedicalVerifierCore/Sources/MedicalVerifierCore/OnlineFirstVerifier.swift` | 2794 | `377a12dd66b005242fd5ba4c81504ca8c82235ad` | full |
| Chat-me-personal | `clients/ios/MedicalVerifierCore/Tests/MedicalVerifierAPITests.swift` | 1233 | `72e2e1ee659e2effaed382632a74ad5089bbd563` | full |
| Chat-me-personal | `clients/ios/MedicalVerifierCore/Tests/MedicalVerifierCoreTests/AdvancedClaimReasoningTests.swift` | 4008 | `23fb19d7a3f65a1ca88485274aebec83537b102f` | full |
| Chat-me-personal | `clients/ios/MedicalVerifierCore/Tests/MedicalVerifierCoreTests/CrossPlatformConformanceTests.swift` | 3298 | `9f0d06e5a65bce36a844e13d49767b09241a4505` | full |
| Chat-me-personal | `clients/ios/MedicalVerifierCore/Tests/MedicalVerifierCoreTests/MedicalVerifierAPITests.swift` | 2000 | `8cc2870257b51fc5d9462b118f8d55a2058f2cb8` | full |
| Chat-me-personal | `clients/ios/MedicalVerifierCore/Tests/MedicalVerifierCoreTests/MedicalVerifierCoreTests.swift` | 22217 | `ff3a712377d3f6e0d1ff87a8f0b32a27d16562ec` | full |
| Chat-me-personal | `clients/ios/MedicalVerifierCore/Tests/MedicalVerifierCoreTests/Resources/conformance_vectors.json` | 12803 | `16c3684e7cb0022740447e5ed3df4c507c2b2f41` | full |
| Chat-me-personal | `docker-compose.yml` | 173 | `79d3e755b71bc1fd27185f63615af21c2b505d78` | full |
| Chat-me-personal | `docs/architecture/README.md` | 7142 | `e81c962d93b5bf0f5689a218f3139e4a0fbb0504` | full |
| Chat-me-personal | `docs/architecture/audit/experiments/probe.py` | 5592 | `f712dd18e9b86ad927d58d6d9c8f2b37de76f3b6` | full |
| Chat-me-personal | `docs/architecture/audit/experiments/probe2.py` | 6629 | `c6d9eabebd994ff3816bea900e2da468202677a4` | full |
| Chat-me-personal | `docs/architecture/audit/experiments/probe3.py` | 2359 | `7a15ab200edec8198e2265773d0ac2c35e4d168b` | full |
| Chat-me-personal | `docs/architecture/audit/stethoscore-unverified-findings.md` | 16166 | `50075cdc3cc6dc5d0587548a9a3de8fea2319baa` | full |
| Chat-me-personal | `docs/architecture/audit/stethoscore-verified-findings.md` | 32655 | `86b35f1fc7655de9f50938877d41f4e4bc908c0d` | full |
| Chat-me-personal | `docs/architecture/audit/task4-chat-me-audit.md` | 29795 | `257c1c165a432b9f538ebc72be7192e5837ad70b` | full |
| Chat-me-personal | `docs/architecture/handoff/context.md` | 16422 | `16e1b3e269ab73c54bbdefd57bfd9d389629af58` | full |
| Chat-me-personal | `docs/architecture/handoff/plan.md` | 208798 | `75398e61beda72e0037876ee8aa2c94a3ab1eaaf` | full |
| Chat-me-personal | `docs/architecture/research/16a-dna-brief.md` | 33336 | `010ae1d4769bf8903ebdf6d8743c0306e85b1b3e` | full |
| Chat-me-personal | `docs/architecture/research/17-islamic-verification-brief.md` | 32853 | `0f59f1f5ba0498548e6968fe467e3cd9bd315855` | full |
| Chat-me-personal | `docs/architecture/research/20-revenue-model.md` | 12582 | `6bfe220d3e0d66a853e1bb1850828684718829a1` | full |
| Chat-me-personal | `docs/architecture/research/22a-jev-brief.md` | 10737 | `f18b266ee6980d484b190b7c190726ee510ed06f` | full |
| Chat-me-personal | `docs/architecture/research/22b-app-features-brief.md` | 28052 | `042422d249cae58c6804c2fc2940b294c59d13aa` | full |
| Chat-me-personal | `docs/architecture/research/22c-student-helper-brief.md` | 16357 | `68d60f4aa3c2dbc2b3d1b7645b20515d5237d8bd` | full |
| Chat-me-personal | `docs/architecture/research/22d-question-bank-brief.md` | 15258 | `5f4c51f30a7790a6658db33f5339068c8496b3dc` | full |
| Chat-me-personal | `docs/architecture/research/22f-fail-safe-brief.md` | 22942 | `dc22995eff90fd99b29a6b7a12feec53a18ed749` | full |
| Chat-me-personal | `docs/architecture/research/22g-langgraph-brief.md` | 15529 | `7a4507e4461bf01de92597bf55431d544bdf39f8` | full |
| Chat-me-personal | `docs/architecture/research/23a-competitive-landing-report.md` | 11857 | `9bada6637a4830994a696a970aa0cf88e1c97e8d` | full |
| Chat-me-personal | `docs/architecture/research/model/revenue_model.py` | 6652 | `40ba59c4d40532168bcbcb56065841fbed5f9712` | full |
| Chat-me-personal | `docs/architecture/verifier/ACCEPTANCE_GATES.md` | 1576 | `f00f41dbf76ff08b11cd7c25bd7b1e4e9b66c374` | full |
| Chat-me-personal | `docs/architecture/verifier/BENCHMARK_CONTRACT_V1.4.md` | 464 | `648c903f3bed9542e09dc3f13f5cae257c9fc32c` | full |
| Chat-me-personal | `docs/architecture/verifier/BENCHMARK_RUNNER.md` | 636 | `5b0de0a570ce2bc433add8cc57d5b6938d659bb8` | full |
| Chat-me-personal | `docs/architecture/verifier/CLINICIAN_BENCHMARK.md` | 1631 | `1031ebeda820b6a163b8777db7acfccc5557b6d8` | full |
| Chat-me-personal | `docs/architecture/verifier/COMMERCIAL_ACCURACY_STACK.md` | 2682 | `711324b9f2b2c0a4f99f33922b6972492cacff99` | full |
| Chat-me-personal | `docs/architecture/verifier/CROSS_PLATFORM_CONFORMANCE.md` | 1093 | `014d02f0660abb1c98eab66ffb6c83a106e16a31` | full |
| Chat-me-personal | `docs/architecture/verifier/IOS_ON_DEVICE.md` | 2021 | `ae80b64ec0bdd0d7b42c6b98f72601caec2aaee1` | full |
| Chat-me-personal | `docs/architecture/verifier/NOTICE` | 294 | `cd395cfff2aff387a4608331c563b29955de863c` | full |
| Chat-me-personal | `docs/architecture/verifier/PDF_EXTRACTION_CONTRACT.md` | 2150 | `4fa7fbb5bf68dee4aae003e1b93f8de1263ec908` | full |
| Chat-me-personal | `docs/architecture/verifier/QUESTION_GENERATION_CONTRACT.md` | 2163 | `f22354547a09acec7b2155b233c69f9e2547656b` | full |
| Chat-me-personal | `docs/architecture/verifier/README.md` | 929 | `adf2662c0d96d472032bb362bcf84c94062f6bad` | full |
| Chat-me-personal | `docs/architecture/verifier/RELIABILITY.md` | 2028 | `58bb180983857ee663026feefc7c6492f04e478d` | full |
| Chat-me-personal | `docs/architecture/verifier/VERIFICATION_CONTRACT_V1.md` | 2931 | `32a9143a55b50570d3e9c413776ee3caaf34ef79` | full |
| Chat-me-personal | `docs/architecture/verifier/VERIFICATION_ENGINE_V0.2.md` | 1450 | `155d0e295b17e26f929a2da19d4a76fd17a67026` | full |
| Chat-me-personal | `evals/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `evals/reports/ASSESSMENT_V0.3.md` | 2035 | `3a32284b846364958eb02de8da5746b970082c17` | full |
| Chat-me-personal | `evals/reports/ASSESSMENT_V0.4.md` | 1587 | `124401c4a554ed5ab51e9b174b1f21d70cc7f37b` | full |
| Chat-me-personal | `evals/reports/ASSESSMENT_V0.5.md` | 1166 | `302a1d037f2bd0dd8580322a7599f120bcc87314` | full |
| Chat-me-personal | `evals/reports/ASSESSMENT_V0.6.md` | 1418 | `e85ba632124f42d3eb286ba48b63782a34fc6757` | full |
| Chat-me-personal | `evals/reports/ASSESSMENT_V0.7.md` | 1370 | `291f59d9ee42428cf963b10e7e4ff8b3fb88b70b` | full |
| Chat-me-personal | `evals/reports/ASSESSMENT_V0.8.md` | 1930 | `fc2864ba5917f5f2ce2490bc89efbb61224c8a76` | full |
| Chat-me-personal | `evals/reports/ASSESSMENT_V0.9.md` | 1445 | `93915fe82c6e4af1391eb33e1d81dca0c5d6c070` | full |
| Chat-me-personal | `evals/reports/ASSESSMENT_V1.0.md` | 1347 | `8cfe5b956f6d7189704ff60f7f9766c2d093a194` | full |
| Chat-me-personal | `evals/reports/ASSESSMENT_V1.1.md` | 1765 | `86e753dddbc3258aec43f4e1b0747e8d042a32c5` | full |
| Chat-me-personal | `evals/reports/ASSESSMENT_V1.3.md` | 1446 | `004a5e7a27c8d6900111725d335a15eaca20a044` | full |
| Chat-me-personal | `evals/reports/ASSESSMENT_V1.4.md` | 1143 | `c0be404c879a13d5f9369ce939a836efc81e682a` | full |
| Chat-me-personal | `evals/reports/ASSESSMENT_V1.5.md` | 1197 | `515e0f7b2706fed267f8cc68d90498f1c90c4434` | full |
| Chat-me-personal | `evals/reports/NEMESIS_PLAYBOOK.md` | 2513 | `5a3873a764c56b9c75591f06481ccee08e882b3b` | full |
| Chat-me-personal | `evals/reports/NEMESIS_ROUND_11_INTEGRITY.md` | 540 | `a776e27092ca5121fdc830f59c5bf7914d3eaac6` | full |
| Chat-me-personal | `evals/reports/NEMESIS_ROUND_12_PROVENANCE_BYPASS.md` | 1969 | `81a04d04f98695b1e789bfbe4f4a12bdc79054d4` | full |
| Chat-me-personal | `evals/reports/NEMESIS_ROUND_13_SNAPSHOT_SCHEMA_BYPASS.md` | 1365 | `036ce2d00e2adaf213d2aa566454f7388c8aca03` | full |
| Chat-me-personal | `evals/reports/NEMESIS_ROUND_2.md` | 1419 | `d54cc039870dd6d8148b2d8448e3b3591e4c4b79` | full |
| Chat-me-personal | `evals/reports/NEMESIS_ROUND_3_IOS.md` | 2172 | `6d85c5f455cf147e42abf21b0e72c7870ab7e71f` | full |
| Chat-me-personal | `evals/reports/NEMESIS_ROUND_4_CONFORMANCE.md` | 1470 | `9299a4f8147e94e807dcdd99df616cb4284a67d3` | full |
| Chat-me-personal | `evals/reports/NEMESIS_ROUND_5_SCOPE_EXTRACTION.md` | 939 | `7139251b968b67a6473242d5578951ae6ae27da5` | full |
| Chat-me-personal | `evals/reports/NEMESIS_ROUND_6_CONDITIONS_PROVENANCE.md` | 1298 | `b0a616984be6e15702c356092a8059703f830172` | full |
| Chat-me-personal | `evals/reports/NEMESIS_ROUND_7_LINEAGE_MULTILINGUAL.md` | 1026 | `39fe0785c44047ff1e2707f9ec786f7d77a5f2d8` | full |
| Chat-me-personal | `evals/reports/NEMESIS_ROUND_8_PDF_INTELLIGENCE.md` | 1202 | `0869dd68177887ae19bd6984e322729d09948e01` | full |
| Chat-me-personal | `evals/reports/NEMESIS_ROUND_9_ADVANCED_REASONING.md` | 1075 | `0b47cc8945403d730fcbfa91bf868db1c4ff2862` | full |
| Chat-me-personal | `evals/suites/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `evals/suites/adversarial_mutations.py` | 2165 | `73dc665fb73ae9de0bd87439333f706440b1302e` | full |
| Chat-me-personal | `evals/suites/benchmark.py` | 1449 | `febcb20e03eff6ae11cbe2ac7bff7668fe0ec02a` | full |
| Chat-me-personal | `evals/suites/benchmark_dataset.py` | 3823 | `5a1e8a628e09144be9865747c5c6eac6ceea8d95` | full |
| Chat-me-personal | `evals/suites/benchmark_manifest.py` | 2835 | `91727facf6c243b9da02a419d545c59588d71536` | full |
| Chat-me-personal | `evals/suites/benchmark_snapshot.py` | 7409 | `150d7041962955f9d676711f8bbc08b86cc46cae` | full |
| Chat-me-personal | `evals/suites/dataset_integrity.py` | 7145 | `490f96b83284a13434ad3bea67ec02f308bb26d9` | full |
| Chat-me-personal | `evals/suites/metamorphic.py` | 810 | `51e73a3e3eadb7e473a37610bc2ec2ac84b81237` | full |
| Chat-me-personal | `evals/suites/validation/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `evals/suites/validation/benchmark.py` | 3601 | `b6194aa83a0a0a9d41758aaca4109029de270544` | full |
| Chat-me-personal | `evals/suites/validation/calibration.py` | 2153 | `5b5d3762863a206104d941f87b9bffefd9ba6e16` | full |
| Chat-me-personal | `evals/suites/validation/runner.py` | 1592 | `847c0a837d6cf01d8a20e90785e58e18f9c91ed1` | full |
| Chat-me-personal | `governance/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `governance/audit/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `governance/audit/source_manifest.py` | 4100 | `cbf0685b426893459e1c7de7fced465792a518ce` | full |
| Chat-me-personal | `governance/audit/store.py` | 9000 | `da66e2cc074b4b59c9ad3358eaf7ab22531e9233` | full |
| Chat-me-personal | `governance/guardrails/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `governance/guardrails/adversarial.py` | 3231 | `e1258df62da42e4c73b4d2139ad7249498c76ece` | full |
| Chat-me-personal | `governance/guardrails/risk.py` | 1837 | `d443886c0c5a7c2d498d997e539921ac675054f2` | full |
| Chat-me-personal | `governance/guardrails/rules.py` | 1300 | `d5af33f336955a214f476cf65703fa9bafc28f5d` | full |
| Chat-me-personal | `governance/policies/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `governance/policies/policy.py` | 2286 | `22d41898ccbb9f85abc052b971a2c0147b2a8579` | full |
| Chat-me-personal | `orchestration/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `orchestration/graph.py` | 23702 | `1700eb4a53d7fcf4dc38cb875a4965c9f0008bdf` | full |
| Chat-me-personal | `pyproject.toml` | 660 | `797684ea871025910d1717a6283a947e5f047df2` | full |
| Chat-me-personal | `tests/integration/test_api.py` | 354 | `5b189df6a161233249ab7d9de50fe39fdd2e2b19` | full |
| Chat-me-personal | `tests/integration/test_benchmark_api_v1_5.py` | 1386 | `7ce58d5c4f918b6ad2d2e05e6eddbdceca343b9f` | full |
| Chat-me-personal | `tests/integration/test_contract_version.py` | 646 | `c6dbc792d048d3441b93a1592288c9892332cfcb` | full |
| Chat-me-personal | `tests/integration/test_question_context_safety.py` | 604 | `f1a97c6f6ce1b70d97484184c719610f168e5fb2` | full |
| Chat-me-personal | `tests/integration/test_v1_6_hardening.py` | 10667 | `26bc723abccb2eeb3cfdb7ea9ec89d60add4b651` | full |
| Chat-me-personal | `tests/unit/test_adversarial.py` | 1335 | `f71f06b78e75eb75ba6f667b1183d34310a3684a` | full |
| Chat-me-personal | `tests/unit/test_adversarial_mutations.py` | 775 | `6dfa6ca71e1d3a93e191de8f9dc3240521ab6a3e` | full |
| Chat-me-personal | `tests/unit/test_adversarial_pipeline.py` | 819 | `1d332475fb3ba2be9659834fe93899171b12f75b` | full |
| Chat-me-personal | `tests/unit/test_assertions.py` | 363 | `04d8329146611cff50dbf2b9a20868d2bb3daaff` | full |
| Chat-me-personal | `tests/unit/test_benchmark_dataset_v1_4.py` | 1255 | `6b460879163658c6743fe7f9ebd5b5e798ca637e` | full |
| Chat-me-personal | `tests/unit/test_benchmark_runner.py` | 1133 | `d195f074ccf6d64cf24dbd1ea32a524e32333a4f` | full |
| Chat-me-personal | `tests/unit/test_benchmark_v1_3.py` | 968 | `1e34db94186f84366d471729be46b99f13ea0230` | full |
| Chat-me-personal | `tests/unit/test_citation_integrity.py` | 1479 | `47bf8a9e2b7072f3721d423efe2fd68e761b14d2` | full |
| Chat-me-personal | `tests/unit/test_claim_reasoning_v1_1.py` | 4721 | `46740ba7085eaabc61d33d3fd8c20c89bb719cc0` | full |
| Chat-me-personal | `tests/unit/test_consistency.py` | 1067 | `1d737d295d41b2e542d0bf282c7ce5c57e0b9f3f` | full |
| Chat-me-personal | `tests/unit/test_correlation.py` | 757 | `34482937af6686d80ba46996e7c941a586b5518a` | full |
| Chat-me-personal | `tests/unit/test_cross_platform_conformance.py` | 1972 | `d872b17728648f3d032c93f1f7da3aab75a35499` | full |
| Chat-me-personal | `tests/unit/test_curriculum_dual_truth.py` | 2147 | `ff46fb9ab7a04084734d2240834bfd08d3c32b24` | full |
| Chat-me-personal | `tests/unit/test_curriculum_provenance_storage.py` | 1127 | `5d1a28a3d943a6a0614920c2a2d80743d758f061` | full |
| Chat-me-personal | `tests/unit/test_double_negation.py` | 468 | `bde198c000b9055b0e4689e6559f0c515877fa38` | full |
| Chat-me-personal | `tests/unit/test_entailment.py` | 593 | `d78b4acef372f93fd6e9a536cfa1b91c9e68d3fb` | full |
| Chat-me-personal | `tests/unit/test_entailment_provider.py` | 993 | `e7f27e82435544bcf11879fac8323f1dffce1751` | full |
| Chat-me-personal | `tests/unit/test_independent_entailment.py` | 1471 | `d6b515dbdb327a8934fed765b81c968bec171ac1` | full |
| Chat-me-personal | `tests/unit/test_local_evidence_metadata.py` | 1710 | `be62001f9371e2f00a5e25d13c6abbc122d8132b` | full |
| Chat-me-personal | `tests/unit/test_metamorphic.py` | 737 | `05d84234ef7e7edae8be09009c36c33c1569bbe5` | full |
| Chat-me-personal | `tests/unit/test_named_medication_action.py` | 236 | `3e35c8644912e034ec9d219f031dd5e1f08b7af1` | full |
| Chat-me-personal | `tests/unit/test_nemesis_v1_4.py` | 963 | `43ee4edb4deecac6de58c0f0f47fcd1820162832` | full |
| Chat-me-personal | `tests/unit/test_pdf_structure.py` | 4849 | `3dcec6eafe31ead663116bc87b01669f31c1fa67` | full |
| Chat-me-personal | `tests/unit/test_pipeline_complexity.py` | 1503 | `a824ed38738c5b6cf8deb46b55bed120e0145749` | full |
| Chat-me-personal | `tests/unit/test_question_provenance.py` | 448 | `adeacf5fa7fc21dd0b36145e5b22f6cf6c96a47b` | full |
| Chat-me-personal | `tests/unit/test_question_validation.py` | 1217 | `19f2a09b3f613863fcd41ac8ef53807450345a06` | full |
| Chat-me-personal | `tests/unit/test_reliability.py` | 2417 | `19359537c9edd76e811e3d7904b1bef01e8adf6b` | full |
| Chat-me-personal | `tests/unit/test_revalidation.py` | 2292 | `b50f243ab32e12ae38dc3308e90373c322704ed7` | full |
| Chat-me-personal | `tests/unit/test_runtime_contract.py` | 479 | `f2452090159338704a87a836a3c79877006e0c8c` | full |
| Chat-me-personal | `tests/unit/test_runtime_imports.py` | 213 | `4e161cabd423343d61988ee2f97621f219dedcb1` | full |
| Chat-me-personal | `tests/unit/test_scope_frequency_extraction.py` | 7277 | `9726dee8b04e7e1011d90a83027cd4dc0c1c7211` | full |
| Chat-me-personal | `tests/unit/test_semantic_guard_regressions.py` | 674 | `382b056e9e567eebda5d4a3f40524b3a7133257f` | full |
| Chat-me-personal | `tests/unit/test_semantic_nemesis.py` | 2939 | `e2d370ef90efd24c5e156e183f9d683127f70b37` | full |
| Chat-me-personal | `tests/unit/test_source_manifest.py` | 3261 | `59ed402daaeb88855bf7a681270104d67e020436` | full |
| Chat-me-personal | `tests/unit/test_swift_source_integrity.py` | 504 | `9493e4dc86265685da9611ad00d822a5ff049ebb` | full |
| Chat-me-personal | `tests/unit/test_temporal_guard.py` | 740 | `6327f4849e9c3a8df27167df16c1f7a57b7841c9` | full |
| Chat-me-personal | `tests/unit/test_v1_5_entities_manifest.py` | 1144 | `6ee1764dcf1aa28eaee4ea8e0cd353a9e857fe3d` | full |
| Chat-me-personal | `tests/unit/test_v1_5_integrity.py` | 2167 | `2c475b7d38ffecf5ce0378b77be735d5f1e3a32e` | full |
| Chat-me-personal | `tests/unit/test_v1_6_nemesis_loop.py` | 2998 | `ceea5674146008c2934eb61076a0c7283342e394` | full |
| Chat-me-personal | `tests/unit/test_validation.py` | 1366 | `609d24721dc4236d8e1eafcdafb6c6db7b6344ca` | full |
| Chat-me-personal | `tools/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `tools/definitions/__init__.py` | 0 | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | full |
| Chat-me-personal | `tools/definitions/normalize.py` | 1071 | `65e899f24736f828c07a4918f3eefc95792aaf2c` | full |
| Chat-me-personal | `tools/definitions/pdf_structure.py` | 4365 | `ec5ea55911f813751e344f22476eef341a84167d` | full |
