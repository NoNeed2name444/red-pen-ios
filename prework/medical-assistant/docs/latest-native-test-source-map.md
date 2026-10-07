# Latest native test source map

Scope: 76 current native Tests/UItest Swift files from `/tmp/native_tests-read-scope.json`. All 76 files were genuinely fully consumed in 94 sequential bounded, untruncated source outputs, totaling 1,034,273 source bytes. Exact decoded character ranges and file SHA-256 hashes are tracked separately in `latest-native-test-read-coverage.json`; all manifest byte counts and hashes match current files. No tests executed, source edits, providers or orchestration. Previously read CLAUDE.md and handoff context apply. Existing test expectations are reported as contracts, not clinical, design or pedagogic approval.

## Findings from fully consumed sources

- AccountTests covers PKCE URL safety/state refusal, resumable refresh tokens and entitlement grace/refresh rules.
- AccuracyTests covers Swift/server parity vectors, independent model families, blind answers, source support, claim holds/retries, content hashing, ledger replacement, scheduling/deduplication and mechanical corrections. It requires current server/tests/rule-vectors.json to be found; this reader does not assess clinical vector content.
- AnswerCheckingTests exhausts all 120 option orders, checks original option indices passed to summaries, verifies conversion answer keys, duel side input, Commute spoken option mapping, spoken matches and tolerant mark-number decoding. Its Commute tests only call SpokenAnswer; they do not exercise Store.recordAnswer or durable attempt history.
- BatchWritingTests uses stand-in batches only and covers partial output retention, growing waits, final auth errors, cancellation, page gap filling and missing-count messages.
- CardQualityTests covers existing Python/Swift intended parity examples, deck-only distractors, repeatable option arrays, cloze/token rendering and canonical answer comparison. Its reproducibility assertion compares options, not question IDs/history identity.
- BedPlanTests pins existing bed priorities, weak-topic inclusion, rhythm and words; ChartQuizTests pins chart extraction, mark partition, exam-hidden verdicts and action labels.
- CircuitHierarchyTests and CosmicHierarchyTests use copied design-preview material to verify planner topology, role mapping, containment, deterministic input order, collision-free bounds, random vaults, routes and scale budgets. These are existing tests, not this reader’s design assessment.
- CloudJobRetryTests pins fetch retry waits and distinction between student and system stops. CloudTranscriptTests covers chunk/silence cuts, salvaged JSON, loops, fallback disclosure/model provenance, timing/language, vocabulary and literal prompt clauses.
- ContentCreditsTests verifies deduplicated citations, source catalogue licensing fields and bundled exemplar attribution parity.
- CoverageTests verifies repeat detection, count limits and bounded recent avoidance notes.
- DataIOTests covers reference Zstd/real Anki fixture imports, image and tag preservation, TSV/CSV fields, backwards decoding, backup merging and archive protections. It explicitly confirms that shared cards in differing backup copies receive new IDs and their schedules remain with this phone’s existing copy. This disproves the provisional backup schedule-remap defect candidate from the earlier runtime map; preserve the tested contract.

- DeckTests covers front/back answer hiding, image gating, palette numbers, deck grouping, station steps and explanation splitting. `withNewItemIDs(sharedWith:)` renews only colliding shared cards; unique cards retain their IDs and schedules, confirming the backup contract above.
- DiagnosticsTests covers keyed scrubbing, fake error fixtures, cancellation/offline exclusions, fingerprints, queue/day/upload caps, UTC pruning, trail limits, crash versus background exits and wire fields. DifferentialTests covers backwards optional fields, current retained `qaCards`/`kind: qa` compatibility, lossy raw preservation, tolerant key aliases and existing verification thresholds. These are current files; no deleted history was accessed.
- DocxTests uses a real zipped document fixture and covers XML entities, runs, breaks, paragraphs, images and deflate. ZipTests also constructs hostile archives to cover expansion ceilings, size lies, alias budgets, malformed/ZIP64 overflow, selective Office parts, tracked deletions, fields, AlternateContent and preservation of unaffected entries.
- ExamCatalogTests covers existing catalogue IDs/weights, question ranges, family fallback, option counts, quotas, standings/readiness math, exemplar rotation and literal prompt clauses. ExamToolsTests covers mock uniqueness/pacing/minimums, summary marks, twin queue due/prune rules, hint leak filtering/cache/fallback, calculator evaluation, lab IDs and decimal-safe stems. These tests pin existing behavior rather than establish new educational choices.
- FaultTests covers offline/auth/entitlement/busy responses, usage updates and transcription retry distinctions. FirstRunTests covers version/start/finish state, returning-user terms, simulator preview flags, daily-goal keys and third-sighting tips. GenerationRulesTests covers admission while another job runs and cancellation restricted to the matching UUID.
- FigureTests covers component connectivity, merging, minimum area, normalization, duplicate labels and card image-index padding. IngestTests covers page furniture thresholds, hyphen joining, page counts and text cleanup; it does not execute device PDFKit/Vision. OCRTests pins mixed-script logical ordering and script cleanup rather than live recognition. PhotoOcclusionTests covers fitting/clamping, drag/resize/corner hits, OCR edits, sibling masks and deduplicated cards with source image indices.
- GraphDeathTests covers existing effect durations, motion/link budgets, in-flight buffer indexing, bounds and synapse geometry/coding. GraphLabelTests covers contrast calculations, backdrop estimates, accessibility chooser switches, hysteresis and easing budgets. GraphPerfTests covers deterministic synthetic large graphs, CSR, missing links/cycles, containment, independent spatial queries, tiers/LOD, camera round trips, force slicing/clamps, clusters, pruning and GPU scene/binding structures. Reading these files provides no measured benchmark or Metal execution result.
- GraphTouchTests covers touch thresholds, states, selection/open/dim commands, peek markup, chip limits and VoiceOver names. GraphicsTests pins thermal/memory tiers, rhythm/jitter/stall handling and sampled geometry. LineStyleTests and LinkLengthTests pin stored choices, straight buffers, geometry scales, containment, deterministic sizes, circuit routes and board connector hits. NeuronHierarchyTests and NeuronLookTests pin topology, cycles, roles, containment, palette/state mappings, impulse arrival/refractory rules, drift and shader codes using current copied preview fixtures. SpaceStyleTests pins existing CPU optics math and literal shader agreement; none of these readings constitutes new design assessment.
- ImportTests covers newline variants, invalid/fullwidth/digit/past-bound keys, missing-image rebasing, UUID/tag preservation, cloze HTML and ordinal handling, ZIP round trips/CRC/ceilings and narration language compatibility. It has no sparse column-options fixture where a blank precedes a letter key. SlideTests covers natural XML order/provenance and option-edit positional key following; it does not close that importer gap.
- LLMTests covers thinking/prose stripping, cut JSON arrays, tolerant answer decoding, existing verification grading/risk fields, complete source windows and partial checked text. LensTests covers OCR markers/grids/noise, tracker limits/read gates, answer formats, conversions, sources/tags and cloze options; its numeric keys are one-based while the LLM parser fixtures include zero-based numeric keys, reflecting their separate existing parsers. MCQRepairTests covers positional-reference repair while preserving UUID/options/key, format variants, name collisions and leaving contradictory keys for rules to flag.
- LearnTests covers forecasts, exam caps, existing SecuredRule separated-day/slip/hinted-credit math, mission ordering, tags/interleaving, pretest repeatable options and rhythm dates. It does not integrate LearnStore.lockInPicks. LearningTests covers sound-key examples (including a deliberate collision), correction trust/repetition, overwrite protection, TSV, propagation/undo and word timing. TranscriberTests covers chopping/timing/layout/partial estimates and applied learned corrections rather than a live microphone recognizer. LectureAudioTests covers failed replacement retaining old audio and successful container replacement without disturbing other files.
- LibrarySearchTests covers scoped search, normalization/snippets, caps, tags, rotating unchanged item IDs and CustomSession due/failed/suspended/flagged filtering. Review decks retain card IDs and pictures. PictureTests covers image rebasing, source references, combined-book figure filtering, card picture pools and backwards picture-side encoding. ModeConversionTests preserves set-level images, sources/citations and the original set; its card conversion fixtures do not assert per-question imageIndex or tags, leaving the earlier runtime mapping candidate untested.
- LiveModelTests opts into actual provider requests through LIVE_ONLY/backend credentials, records nonempty/parsed output and existing faithful/planted-risk comparisons, and writes a Markdown report. This read task did not execute it. A reported `passed` is the test's limited assertion, not clinical approval.
- MockSittingSaveTests covers answer positions, option orders, flags, strikes, highlights, time/stamps, replacement, invalid-file handling and clearing. It does not exercise Store attempt history. NarrateTests covers chunk completeness, initial fast chunks, prefetch/cache retention, measured timing, script/UTF-16 mapping and stand-in handoff. ReadingTests covers highlighting, page blocks/tables/callouts and compact valid figure indices. SourceTests covers heading/page lookup, normalization, overlapping snippets and citations.
- OcclusionFilterTests covers furniture/confidence/aspect/vocabulary filtering, minimum labels, siblings, pixel conversion/clamps and backwards decoding. OcclusionPhraseTests covers wraps, hyphens, leaders, gaps, duplicates, independent covered-word expectations and good layouts; it tests individually malformed cards but lacks a mixed good/bad collection retention fixture for the earlier whole-collection validation candidate.
- OsceTests covers numbering cleanup while protecting clinical numbers, duplicate limits/minimums, parsed formats, literal prompt fields, imported cloze/QA content and restarted/restored step state. PatientChartTests covers stem-only extraction, existing accuracy-reference flags, decimals and exclusion of false pulse matches. WardPocketTests pins existing arithmetic/unit fixtures and reachable score bands/boundaries; WardPaletteTests pins numeric contrast and asset-table agreement. No external medical reference verification or new clinical judgment was performed.
- PlatformTests covers auth/file routing, GlanceDigest counts/top entries/age/content equality/due/version and existing exam-day/age gates. It does not test GlancePublisher retry after failed writes. RecoveryTests covers per-record lossy decoding and byte-preserving deduplicated quarantine. StoreFileTests covers missing versus unreadable files and atomic replacement versus failed writes; permission-failure assertions explicitly skip when getuid() is zero.
- ReviewEssentialsTests pins existing FSRS/review vectors, 4am study-day boundaries, new/review limits, learning exceptions, suspend/bury/undo/merge behavior, queue caps/retries/expiry and held-question exclusion/restoration. ScheduleTests covers pure plan ratings, due queues, early-study bounds, duplicate IDs as separate rows, pruning/clock merging and export rows/picture sides; despite restart-oriented comments it does not instantiate a durable Store reload.
- SaveToIdeasTests covers first-sentence titles/decimals/abbreviations, cloze/wiki cleanup, limits, item-kind deduplication, per-page clips, case-folded folders, answers/backlinks/sources and excerpt deduplication. SyncTests covers pure changedAt/tombstone/copy merges, base64 hashes, traversal rejection, missing references, wire/batch caps, UTC refusal/backoff, retained future fields, cursor rereads and cloud-job age/account handling. These are not end-to-end network/persistence tests.
- VerificationScreenTests covers malformed drop counts/reasons, retained held questions, ongoing checker labels and OSCE hold retention. ShaderSourceTests checks token scopes/brackets, material duplicates, probe spellings and noise continuity plus parser self-tests; it does not compile real Metal on this host.
- DesignTourUITests walks many screens using forgiving missing-step screenshots, crash relaunch, identifiers and coordinate fallbacks. Its survival/screenshot assertions do not establish that every absent step worked. ExamplesUITests opens 13 existing example modes, takes retained screenshots and retries taps; its final `while example-ideas exists && !isHittable` return loop has no iteration/time bound, a mechanical test-hang candidate.
- GraphPreviewUITests opens existing themes, exercises preview flags, selection/menu controls, link length and straight lines, uses synthetic launch-driven gestures, captures close-ups and keeps screenshots. Its 100k check waits for the count readout; it does not assert a frame-rate threshold. LocalSignInUITests checks a real hittable sign-in tap and optional terms/exam gates then navigation. OnboardingUITests checks every answered/skipped page and the library dock. TurnIntoUITests checks actual long-press/menu taps, conversion navigation, a quiz stem in the card deck and the newly named library set.

## Mechanical integration implications

1. Preserve the existing original-index contract for shuffled answers and durable card/item identities used by search, custom sessions, repair and review. Commute's spoken-letter tests do not cover Store.recordAnswer or restart persistence; a mechanical integration needs to follow the established Store path and preserve history.
2. Preserve screenshot attachment lifetime `.keepAlways` and the existing screenshot publication workflow. Design tours and preview captures are review artifacts; their existence assertions alone do not approve design changes.
3. The backup schedule candidate is disproven by explicit DataIO/Deck fixtures: shared copies intentionally receive fresh IDs and keep progress with the pre-existing phone copy. Do not patch it as a defect.
4. Existing test gaps leave runtime candidates for item image/tag conversion, failed Glance publication retry, mixed occlusion retention and sparse importer option columns unresolved. Any correction must use existing contracts and focused mechanical verification; this source read supplies no new policy decision.
5. Tests were read, not run. LiveModel/provider calls, simulator screenshot publication, benchmark execution and host-specific permission tests remain outside this task's execution scope.

## Complete file coverage

Every listed file has `genuinely_full_model_read` status. SHA-256, bytes, lines and exact consumed ranges are in the JSON ledger.

| Current source file | Lines | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| `ios/RedPen/Tests/AccountTests.swift` | 142 | 7133 | `83801ca2fac2be41dc3de07226cc8ea7942a5021cb569c5ec673b50975c96ca0` |
| `ios/RedPen/Tests/AccuracyTests.swift` | 385 | 34396 | `238fc80e97baaac85999ed3fd98230620cbb001379348e83c8595c790cb7768b` |
| `ios/RedPen/Tests/AnswerCheckingTests.swift` | 315 | 20144 | `a4ee7f39bfcdb06fead18bba6b10643d80149959995361093f688f97cd0d32af` |
| `ios/RedPen/Tests/BatchWritingTests.swift` | 269 | 12419 | `0193cf56f204b30ab5f25e2679405990723761fff8d7b68872772084b9ba74c0` |
| `ios/RedPen/Tests/BedPlanTests.swift` | 332 | 18518 | `c3ff122aab8a12bc928bf1b1e5cef9b99f52be101b82f10f93b2d27715e4a7bb` |
| `ios/RedPen/Tests/CardQualityTests.swift` | 239 | 13059 | `3d4189b5cea966b3631e160adaef86cf7eb24df61b0f59f980ea2a3fc48124a0` |
| `ios/RedPen/Tests/ChartQuizTests.swift` | 127 | 9059 | `dd3a84f05cf9f762e92d37463fce3a4a75d53a737cb1937a567c061eb73f1118` |
| `ios/RedPen/Tests/CircuitHierarchyTests.swift` | 881 | 45505 | `d8b34e1d029ca37df0805c31e93455235f65e78f53954564d522d7db6c56df3c` |
| `ios/RedPen/Tests/CloudJobRetryTests.swift` | 93 | 4681 | `b37535ec0e41f82c55ab9a84be8d2c65326f100f87d133e2b164d5a12889ada8` |
| `ios/RedPen/Tests/CloudTranscriptTests.swift` | 203 | 14724 | `26a067ed4330a16e23004ed287eccdf7eb4444f0c7dacdedc0425b377a5a8d24` |
| `ios/RedPen/Tests/ContentCreditsTests.swift` | 116 | 6803 | `75d8c0962040ad78038d641f8ea0d402856f1ef89de122485301212f912b4159` |
| `ios/RedPen/Tests/CosmicHierarchyTests.swift` | 821 | 43868 | `f92aa6e57d1afb0e1ffdc5d64058da66da5b3327290d66a09bcd01e9b2389f2e` |
| `ios/RedPen/Tests/CoverageTests.swift` | 127 | 7272 | `95ebb492791827a1ebb26a45f60e4933c59d27ea2a3f94ccf928b587e00d0ec5` |
| `ios/RedPen/Tests/DataIOTests.swift` | 469 | 32401 | `506cf8b05f3db803a07f6e986697178437475e2dfabac156a0cd412190317b00` |
| `ios/RedPen/Tests/DeckTests.swift` | 276 | 14819 | `ccab77a0a28874021673c2973f1f03dec6848df31eb64a688911c5d92df6e368` |
| `ios/RedPen/Tests/DiagnosticsTests.swift` | 277 | 15681 | `f816c47217820383692b30a382b9750adcbc42b8d1b30c4f934d87c86e3c4486` |
| `ios/RedPen/Tests/DifferentialTests.swift` | 215 | 16528 | `31485c2a37d0947d15ee5e28effa887749a9de9e092bdb88a8a2c78ce80aa928` |
| `ios/RedPen/Tests/DocxTests.swift` | 94 | 4251 | `ce3cbbab415cebe662a1ad88135060ab84ebe6397204aba0c13297c80fce0a12` |
| `ios/RedPen/Tests/ExamCatalogTests.swift` | 296 | 23693 | `b2614d47900537752fc04fa803535309b71f7b30fc965686c3d01395dd5a65ec` |
| `ios/RedPen/Tests/ExamToolsTests.swift` | 189 | 11976 | `22012bfc55ab2c6091ce83b00d855b8b85d618f276ac9728551735f55645610b` |
| `ios/RedPen/Tests/FaultTests.swift` | 74 | 4411 | `0934d71ac703bf9dcbafaed1b4edcb655313299f70f23ea668211fc295e380a3` |
| `ios/RedPen/Tests/FigureTests.swift` | 132 | 5744 | `00dcaf4a943b0e18f071d8c1376433d8e5646cfcefc212280fea1bfccba0d1ae` |
| `ios/RedPen/Tests/FirstRunTests.swift` | 115 | 6758 | `2fa6a9ab74e66662c56178ebe1bf76418d5054bb61bb00ef666a2b8ddba2a283` |
| `ios/RedPen/Tests/GenerationRulesTests.swift` | 56 | 2687 | `52c4899b6d801d64a5483bf3b1efa254cd27f059cff92d186fb6c2a506d11b95` |
| `ios/RedPen/Tests/GraphDeathTests.swift` | 276 | 15347 | `1d09bce9fac14e1e008eb15e3750b888ca0c9c48f74acfe764d9312530921fcb` |
| `ios/RedPen/Tests/GraphLabelTests.swift` | 172 | 9810 | `0f86a34030af9e353d7f09954cd8de095a36dcabe233e19019459d2dde28d52b` |
| `ios/RedPen/Tests/GraphPerfTests.swift` | 938 | 58286 | `d0eba3a33fcfa9224a81cc993b1b62d7b87111740db9e36c5257ebc20516d315` |
| `ios/RedPen/Tests/GraphTouchTests.swift` | 145 | 10111 | `8884ae135753641879445d9d31c5e976ca775990ba49e55cb85c44ab08a2d31f` |
| `ios/RedPen/Tests/GraphicsTests.swift` | 288 | 15288 | `c688f5d190dd3590484f0b120e8beb4e40909b91e3e7974acb6096cdbdf6e869` |
| `ios/RedPen/Tests/ImportTests.swift` | 173 | 10141 | `8f2febf34168ec2a713501ff22bf1045cd3f1bb3adb9b3701201ed4eb90e5291` |
| `ios/RedPen/Tests/IngestTests.swift` | 90 | 4060 | `a56867c53b5fae3d3144b06abacbe4292f788afea4a2547e16cfe153db92e0a6` |
| `ios/RedPen/Tests/LLMTests.swift` | 244 | 15764 | `b3797ece88b23eed200e48d8650aaf7a92bb5221271e2ba7e63299d6c9b4387c` |
| `ios/RedPen/Tests/LearnTests.swift` | 325 | 20407 | `3af892868ba77e25c9ed3746ef183ac154963a4ecb17c2ecb7864ce8d421eb41` |
| `ios/RedPen/Tests/LearningTests.swift` | 143 | 7857 | `05a0108d4295458b1402ee610f68e996e536f9c859777e015ea66f4b062e16cb` |
| `ios/RedPen/Tests/LectureAudioTests.swift` | 61 | 2694 | `73a7b409b23dbb3133933b1e460be2d94bd6ed0ff8ba42ebc3f6b41fa8d4b1a9` |
| `ios/RedPen/Tests/LensTests.swift` | 433 | 24903 | `6767c6b8a5d9e2dad11d344fe75598135d8fe50fc906d67cf722f03a72cc8864` |
| `ios/RedPen/Tests/LibrarySearchTests.swift` | 254 | 13375 | `f90ca8161760d564cedc2c16cb551c52ac580060d849b9318378b7cb3ffe8ed5` |
| `ios/RedPen/Tests/LineStyleTests.swift` | 241 | 11932 | `ed12d903793d13ea703eee9558629d0d091af46c5f9185ea7d3c5ba122b19790` |
| `ios/RedPen/Tests/LinkLengthTests.swift` | 638 | 29740 | `6f0e047c9241b789640656ec2fb898c1ddf88e275e7b1b469eb9c19ed3cdf4bd` |
| `ios/RedPen/Tests/LiveModelTests.swift` | 184 | 10058 | `f23866042bd6e9fb7b5eba213c589d0c337025c3ce03a7eb38c33f9b9c270d72` |
| `ios/RedPen/Tests/MCQRepairTests.swift` | 121 | 7738 | `4bb3448082814ce41eaece729549d87403408b4ce084cfbba3594b7edd5e89e4` |
| `ios/RedPen/Tests/MockSittingSaveTests.swift` | 46 | 2279 | `cfa8142e4f381ef9a8eb26c27548312304dfddec7a5bf318274087c1da39e49d` |
| `ios/RedPen/Tests/ModeConversionTests.swift` | 126 | 7462 | `a09048c7dcbd1eacc363daf0aafa372384a440cd2f63aed6ae92a25e4120a9b8` |
| `ios/RedPen/Tests/NarrateTests.swift` | 142 | 7269 | `d265cee14e57f3cc9251640dab630084c9a0982c41fe8827b5abfaa60b08ab32` |
| `ios/RedPen/Tests/NeuronHierarchyTests.swift` | 743 | 38900 | `9e4a1f45c556ef6c2f0989d107112d37d2eba698037189f50bb138d9aa2d04cb` |
| `ios/RedPen/Tests/NeuronLookTests.swift` | 175 | 10288 | `909c6a0e1b4b1ac1ddf1a1d969898ec859470018bdae9f0251648d7c27da1f88` |
| `ios/RedPen/Tests/OCRTests.swift` | 64 | 3241 | `f966ceb15176e91d03da289d73b2a6d8e115ec3f2871607df84d716c48210b15` |
| `ios/RedPen/Tests/OcclusionFilterTests.swift` | 269 | 15333 | `8ee885fd393b4256a17d4e5f636493594e2b6053e1433878f5e9884e1c466e5f` |
| `ios/RedPen/Tests/OcclusionPhraseTests.swift` | 289 | 16103 | `aba7a8666aaa9aad1835dcf6778a703b73928628b8476574649f28a6c9c0ccb1` |
| `ios/RedPen/Tests/OsceTests.swift` | 146 | 7627 | `6dc8dcb3434e299698654b7d7e9d8406fb8e68e49ad7076aab7166eac299198d` |
| `ios/RedPen/Tests/PatientChartTests.swift` | 60 | 4215 | `0e734cb23dc5b3c76ccd2c9bc9d6367820052cc7bd0017387122e9e6beadf24f` |
| `ios/RedPen/Tests/PhotoOcclusionTests.swift` | 165 | 9232 | `cde1e7e950f60c9521d954b30a59982b8fb1931aee10faeaede0c9a0a5c08839` |
| `ios/RedPen/Tests/PictureTests.swift` | 93 | 5989 | `84820d7eb7dffc0b4854e17d6dd457ce76ed98b6aed79c6cfbe73af7465bcc0d` |
| `ios/RedPen/Tests/PlatformTests.swift` | 181 | 10527 | `e89ec08348d68a4a85938e28fd0b74b12fe76438906420a0a66252fbf949b4f6` |
| `ios/RedPen/Tests/ReadingTests.swift` | 155 | 6211 | `f34ea1b17f01fb7bc76139e901a864a77c84816884b6d209369327a4e3b344c9` |
| `ios/RedPen/Tests/RecoveryTests.swift` | 53 | 3557 | `55a886029684b7b8f789ccbc9820645a336a87e058661e9fbd7e74e38d8f50a4` |
| `ios/RedPen/Tests/ReviewEssentialsTests.swift` | 267 | 15666 | `d2cb1bde3c296847ca4b1cc33a8e70f82c4a124a1f563363ccabb497dd377ba1` |
| `ios/RedPen/Tests/SaveToIdeasTests.swift` | 188 | 12221 | `f66f47cf9e76108d1cb1a5e6b5cb0c26b3c762c0d7419f17f03531e203ffdfb9` |
| `ios/RedPen/Tests/ScheduleTests.swift` | 260 | 14356 | `381a19bd0edf4d490d85760f6887642f52756a3d18f4cf9a2828c46f68485a0b` |
| `ios/RedPen/Tests/ShaderSourceTests.swift` | 324 | 16122 | `6d2e1f8adfa73583040aecf0146e2b1abb194af753ef62746eba77740ad98269` |
| `ios/RedPen/Tests/SlideTests.swift` | 154 | 8311 | `be989fbbbea3afe8580108d09e58fa924c48b766b2a2f9a4d18b19392ae14828` |
| `ios/RedPen/Tests/SourceTests.swift` | 95 | 3973 | `bc80a331b6c073f3606496ea986f0a2431c8e2962c4efb0350275d3ddb47af99` |
| `ios/RedPen/Tests/SpaceStyleTests.swift` | 226 | 13045 | `17ccdea560e96e65157ce8aa8d8d0ba928c7e3287faa3942199d0db757ab6d25` |
| `ios/RedPen/Tests/StoreFileTests.swift` | 77 | 3023 | `72b469c377ff3e54508e09d96266b8a1b4e7e05f23fa0dee42bcc0d3c9afbfbd` |
| `ios/RedPen/Tests/SyncTests.swift` | 370 | 21415 | `b039b447d796310d7fc174762e29ae538361aff205dae07fa2c4b78b6dc039aa` |
| `ios/RedPen/Tests/TranscriberTests.swift` | 105 | 5281 | `54331ad38c71f88eb13b713f4f84b79df01d6b8f69ea256d20897a5d85625493` |
| `ios/RedPen/Tests/VerificationScreenTests.swift` | 41 | 3485 | `64ecb9351b73b88392d779c16345d59a325b45c4ed03c8c670e1b29fc7c4c616` |
| `ios/RedPen/Tests/WardPaletteTests.swift` | 59 | 3141 | `90a5ca5db24a01f9f96320724766516926249a66f4ce8ca83911951e80dff559` |
| `ios/RedPen/Tests/WardPocketTests.swift` | 449 | 32559 | `e0c1cabe9421cc58d4da43dc8d7bcc13fd80a726b5a3b73e45ed12ae0a395620` |
| `ios/RedPen/Tests/ZipTests.swift` | 370 | 19292 | `3f270adabcbb9558433713667878e60cff42773fa9f7c3e55e1f047919ede224` |
| `ios/UITests/DesignTourUITests.swift` | 754 | 25905 | `14a49715776b22c15982d27c63b030a95ee3c5f02836a6b8a2eefaf2fdaf3040` |
| `ios/UITests/ExamplesUITests.swift` | 73 | 3521 | `c118097a5b59d8ece2524e9b4e5efa5f1e3c3c6b25879d7b5aaf6665e8877ae9` |
| `ios/UITests/GraphPreviewUITests.swift` | 585 | 28332 | `a4a237e55114a638bbd49ee4e040aed36b830b9eac90bd57ff273f6128bc857a` |
| `ios/UITests/LocalSignInUITests.swift` | 54 | 2677 | `e8242d559574f986a1e83783a01b0d80ada4df26bd78a36e5bf54bb1d5f06a84` |
| `ios/UITests/OnboardingUITests.swift` | 117 | 5089 | `13ac3acdcb90d0cf07017811bcf534a42381111ba58121f498fc0d768a06c29f` |
| `ios/UITests/TurnIntoUITests.swift` | 96 | 4585 | `7d79d653b9470ba3efc85fefb8415d51106f521ffa8d9295a506b70d46b1852e` |
