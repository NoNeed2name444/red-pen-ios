# Native app source map

Repository: `NoNeed2name444/red-pen-ios`. Default-main snapshot
`9eb54309c5edd879b11ce5fa722a972e1652859b` was read completely: all 183 obtainable
UTF-8 files, including workflows, tests and tools. Eleven PNG blobs were not
obtainable through the text connector. The newer, successfully photographed
native snapshot is `faecd8cdccd92387ac777335588ebc548b0ab106`, branch
`cursor/neuron-circuit-perf-d39a`: 686 tracked blobs, 673 obtainable UTF-8 files,
9.09 MB. The app/runtime partition is fully read across two readers: 403 current UTF-8
files, with exact paths, sizes and SHA256 in
[latest-ios-runtime-read-coverage.json](latest-ios-runtime-read-coverage.json).
This reader fully consumed 266 of those paths (including unchanged source
previously read on main); the runtime-tail reader fully consumed 137.
[latest-runtime-tail-source-map.md](latest-runtime-tail-source-map.md) records
its contiguous chunks 135–214. The separate
[latest-ideas-source-map.md](latest-ideas-source-map.md) records all 62 Notes
files fully consumed. Backend/tools/workflows/tests/docs partitions belong
to the other readers and must be joined with their coverage before claiming
the entire latest repository was read. Exact repository download coverage is in
[repository-read-inventory.json](repository-read-inventory.json); reader coverage
is tracked separately while review proceeds.

## Version and existing decisions

- Latest [CLAUDE.md](/workspace/repositories/red-pen-ios-latest/CLAUDE.md) makes
  Chat-me's `docs/architecture/handoff/context.md` authoritative for app state.
  The app is Stethoscore. Its existing visual targets are
  [targets-2026-10-01.md](/workspace/repositories/red-pen-ios-latest/docs/design/targets-2026-10-01.md):
  Ward Round throughout the app, prescribed white/blue/red/amber palette,
  clinical chart presentation, no rank, Clerk badge, XP or leaderboard;
  separate Space/Neurons/Circuit/Performance themes in the 3D Ideas map.
  This map defines no new design or architecture.
- Main's CramDown brand, six-mode QA data and per-mode tinted Liquid Glass
  screens are historical. Latest
  [StudySet.swift](/workspace/repositories/red-pen-ios-latest/ios/RedPen/Models/StudySet.swift)
  supports `mcq`, `anki`, `book`, `osce`, `narrate`; `qa` is retired. It reads
  missing fields tolerantly and refreshes copied item IDs. Latest
  [AnkiCard.swift](/workspace/repositories/red-pen-ios-latest/ios/RedPen/Models/AnkiCard.swift)
  adds sibling masks, tags and answer-side pictures, with tolerant decoding.
- [cases-rebuild.md](/workspace/repositories/red-pen-ios-latest/docs/design/cases-rebuild.md)
  is a clean-room implementation specification. This reader inspected older
  main QA sources before discovering it and must not claim clean-room Cases
  authorship. No deleted history was read. The latest snapshot's model enum
  does not yet contain the specified new `cases` kind.

## Existing app and backend contracts

| Interface | Source-defined behavior |
|---|---|
| Saved library | `StudySet` owns UUID items, source pages and shared base64/blob-ref image pool. ISO8601 JSON; separate persistent review schedules; folders and progress. |
| Generators | Existing Apple Foundation Models and Gemma paths plus `LLMBackend`, `LocalLLMService`, `MedicalGenerate`, `LectureWriter`; MCQ/OSCE JSON and card/textbook text formats already parsed natively. |
| Hosted models | [HostedLLMClient.swift](/workspace/repositories/red-pen-ios-latest/ios/RedPen/Shared/LLM/HostedLLMClient.swift) supports OpenAI-compatible, Anthropic and Gemini requests. Student provider keys stay in Keychain. Own cloud uses session bearer, `/v1/chat/completions`, role aliases `cramdown-writer`/`cramdown-checker`. |
| Durable generation | [CloudJobs.swift](/workspace/repositories/red-pen-ios-latest/ios/RedPen/Shared/LLM/CloudJobs.swift): POST `/jobs`, GET `/jobs/:id`, GET with `outputs=1`, DELETE to cancel/forget. Spec contains sources, steps, extraction mode and checker template. Pending recipes, outputs and verdicts are kept locally until delivery is completed; a system stop hands work to the collector. |
| Partial writing | `BatchWriting` retains successful batches/pages, records failed batches and missing parts, and supports writing missing content. `TextSlicing` spreads source windows and chooses matching source paragraphs/pages. |
| Source import | Native PDF embedded text/Vision OCR; DOCX/PPTX ZIP/XML; source page text, local original PDF hash, diagrams and normalized occlusion masks. Citation lookup and source search already exist. |
| Exports | Native JSON, APKG (`collection.anki2` + ZIP/media), flowing PDF and paired question/answer A4 `DeckPDF`. `tools/deck_pdf.py` is desktop/CI export, not an iOS runtime. APKG/COLPKG import supports legacy/modern SQLite plus zstd/protobuf and preserves incoming schedules; native Anki export carries schedules and masked images. |
| Sync | Existing auth + account-specific revisioned docs, conditional pushes and per-document conflicts. Device merge preserves losing edits. SHA256 image blobs; original source files remain local, their text pages sync; blob recovery retries transient and unavailable pictures. |
| Accuracy | [AccuracyItem.swift](/workspace/repositories/red-pen-ios-latest/ios/RedPen/Shared/Accuracy/AccuracyItem.swift) maps native content to item ID/kind/stem/options/key/explanation/text/source, with stable content hashes and 1,400-character source excerpts. Existing engine grades, not this reader's medical judgment. |

Latest [server/README.md](/workspace/repositories/red-pen-ios-latest/server/README.md)
and [tasks-5-to-5d.md](/workspace/repositories/red-pen-ios-latest/docs/architecture/plans/tasks-5-to-5d.md)
document an already-built Chat-me verifier integration: `server/claims.js`
ports deterministic guards, 35 shared conformance vectors, and the accuracy
pipeline's named `rules / claims / lookup / evidence / votes / jev / verdict /
cache` stages. Replies carry `claims: {hard, soft}` and native
`AccuracyRecord.claimHolds` preserves the hard findings when re-grading.
Existing `switches.js` and `breakers.js` implement feature switches and
provider breakers. Do not duplicate these integrations because main lacked them.

## Real native screenshots

[design-preview.yml](/workspace/repositories/red-pen-ios-latest/.github/workflows/design-preview.yml)
runs on `preview/**` pushes. Three macOS jobs build the actual SwiftUI target
and run `GraphPreviewUITests`/`DesignTourUITests` on iPhone/iPad simulators.
Screenshots are exported from xcresult attachments into `shots/iphone/` and
`shots/ipad/`; graph tests also record video. `shots-*` artifacts are gathered
and published to `shots/<name>` (legacy preview/graph uses design-preview).
Build failure and test failure make the run fail while keeping obtainable
pictures. These are native app pixels. A Linux browser scaffold cannot replace
the native build. The older launch-argument `ios-preview.yml` remains available
for light/dark seeded native screens.

Source review executed no workflow, onboarding, Claude orchestrator, paid
model call or Worker deployment. Existing workflow publication code contains
force pushes; latest working rules prohibit an agent force-push. The permitted
agent action is a normal push of a fresh preview branch after required checks.

## Integration follow-through supported so far

1. Continue from the latest Stethoscore snapshot, preserving source-defined
   Ward components, native study modes, Ideas map, cloud and accuracy APIs.
2. Compare supporting repo source with existing latest ports before adding
   anything. Match claim vectors and exported data shapes mechanically.
3. Check missing features against authoritative Chat-me context/plan; main-only
   missing workflow targets and imports are not current defects.
4. Run appropriate local checks and `tools/preflight.sh` before a branch push;
   current native UI compilation and updated screenshots require macOS Actions.

## Completed runtime feature and wiring map

All paths below are relative to `ios/RedPen/` in the pinned latest tree.

| Existing user flow | Concrete source/interface |
|---|---|
| App entry, routing and multiwindow | `RedPenApp.swift`, `Shared/AppIntentsRouting.swift`, `Shared/Platform/AppLink.swift`, `Shared/Platform/SetWindow.swift`: terms/onboarding/import/URL/notification routes, shared library, native Siri/Spotlight/visual-intelligence capability fences. |
| Ward home and exam overview | `Features/Library/WardHome.swift`, `Features/Exam/`, `Shared/Exam/`: current library progress, due cards, secured standings, daily plan, catalog of 21 exams, primary/secondary weighting, mock clocks, hint/twin queues. |
| Questions | `Features/MCQ/`: chart/stem layouts, shuffled slot-to-original option mapping, confidence/reason/highlight/strikeout, resumable/timed quiz, retest/twins, summary/mistake saving, native mock paper/results. |
| Cards | `Features/Anki/`, `Shared/FSRS.swift`, `Persistence/ReviewStore.swift`: basic/cloze/occlusion/answer-side-image cards, daily limits, FSRS/classic scheduler, undo/bury/suspend, Anki import/export schedule mapping. |
| Textbook and OSCE | `Features/Book/`, `Features/OSCE/`: native Markdown pages/figures/progress/recall notes; editable station generation, sequential station review, spoken station marking and saved voice history. |
| Narrate and spoken study | `Features/Narrate/`, `Features/Voice/`, `Shared/CloudTranscriber.swift`, `Shared/CloudTranscript.swift`, `Shared/Voice/`: local recording/audio, timed transcripts, Gemini chunk transcription with device fallback, pronunciation edits, cached voice/player/Now Playing, commute and explain-back. |
| Library, conversion, search and imports | `Features/Library/`, `Shared/LibrarySearch.swift`, `Shared/ModeConversion.swift`, `Shared/CustomSession.swift`, `Shared/ImportRouter.swift`: folders/tagged filters/global search, custom sessions, file preview/import queue, additive backup/restore, generators, mode conversion, incoming lecture/picture/deck/table. |
| Lens | `Features/Lens/`, `Shared/Lens/`: VisionKit camera/native fallback, OCR capture and tracking, stored question answer lookup/writer fallback, saving existing native kinds or Ideas. |
| Accuracy and content credits | `Shared/Accuracy/`, `Shared/ContentCredits.swift`: durable graded item ledger, independent family checking, existing deterministic claim holds, source excerpts and public evidence/licence credits. |
| Source reading and citations | `Models/SourceDoc.swift`, `Shared/SourceIngest.swift`, `Shared/OfficeIngest.swift`, `Shared/Provenance.swift`, `Features/Sources/SourcePreviewView.swift`: page-preserving PDF/Office text/OCR, device-original hashes, per-item string citations and source previews/search. |
| Persistence and recovery | `Persistence/Store.swift`, `Persistence/StoreStudy.swift`, `Persistence/SourceFiles.swift`, `Persistence/SyncEngine.swift`, `Shared/SyncAPI.swift`: atomic delayed library/progress writes, unread-data preservation, additive conflicts/reviews, account-scoped conditional sync; original lectures stay local. |
| Settings and support | `Features/Support/`, `Features/Paywall/`, `Shared/SubscriptionStore.swift`, `Shared/Diagnostics/`, `Shared/SupportOutbox.swift`: StoreKit/restore, role/provider settings, keychain credentials, local review preferences, native backups, optional platform functions, bounded diagnostics and support outbox. |
| Ideas | Separate fully read `Features/Notes/**` partition; backlinks and saved study items also use `Shared/Ideas/SaveToIdeas.swift` and `Shared/Ideas/SaveToIdeasUI.swift`. |
| Existing design | `Shared/Brand.swift`, `Shared/Theme.swift`, `Shared/Ward/`, `Shared/PopOut.swift`, `Shared/PopOutMotion.swift`, `Shared/AppBackdrop.swift`, `Shared/Space/`: existing Ward colors/components, shared motion/thermal/power/accessibility gates and theme assets; no new design prescribed here. |

`AccuracyStore` is attached at app entry and receives saved library items.
Generated MCQ/OSCE/card flows run the existing first-stage checks where their
current source calls for them. Durable cloud recovery also screens reconstructed
sets, persists them successfully before forgetting server output, and preserves
unparseable paid output as text. Supporting-repo ports are already in current
source; main's absent paths are not fresh integration requirements.

## Mechanical multi-import source preservation proposal

The current native model has `StudySet.sources: [SourceDoc]`; question/card
`source` is an optional citation **String**. There are no `SourceRef` or
`sharedLecture` identifiers in this latest tree.

- `Features/Library/NewSetView.swift:115` owns one `readSource`, seeded from
  an incoming/converted `NewSetPreset`. It passes it to `MCQGenerateForm` and
  `LectureWriterSection` and uses it when saving lecture drafts.
- `Features/Library/LecturePDFSection.swift:192` appends each selected file's
  text to `sourceText`, but replaces `readSource` with that newest file. The
  button explicitly offers “Add another file”. Earlier page text and original
  hashes therefore do not reach the generated set's `sources`.
- `Features/Library/MCQGenerateForm.swift:232` snapshots that last source;
  both the foreground result and `CloudRecipe` keep only it. Per-question
  matching runs existing `Provenance.attribute` against that one document.
- `Shared/CloudJobCollector.swift` reconstructs normal results and text
  fallbacks using `recipe.source`, so a foreground-only correction would still
  lose earlier imported documents when the app is closed during writing.

A strictly mechanical fix may keep an imported `[SourceDoc]` list beside
existing `readSource`, initialize it from the preset, append a stable document
once per successfully read file, and copy that list into the MCQ result's
`set.sources`. An optional `CloudRecipe.sources` field can carry that same list
through normal/fallback recovery, falling back to existing singular `source`
for old pending recipes. This preserves existing JSON compatibility and makes
all imported pages available to source previews/credits/reference consumers.

Keep the single-file replacement behavior of `LectureWriterSection` and the
separate picture deck's last-file source. Do not assign a specific question to
an origin merely because a document was imported. Extending current last-file
per-question attribution across multiple origins requires the owner's existing
Claude decision process; this source reader defines no attribution policy.
No change was implemented by this reader.

## Other mechanical observations for existing-contract review

- Spoken commute MCQ answers update session score and `StudyLog` but do not
  call shared `Store.recordAnswer`; spoken card ratings do call `ReviewStore`.
  Consequently spoken question answers do not currently enter the history
  used by Vitals/coverage/mistake selection. This is a field-wiring observation,
  not a request to change the study policy.
- `Store.temporaryQuiz` and `CustomSession.quiz/deck` preserve original item
  IDs and copy/rebase pictures, but do not copy originating `SourceDoc` arrays.
  Per-item citation strings can survive while temporary source previews lack
  the corresponding document. `SetPictures.addMistakes/combined` already
  demonstrate the existing multi-document copy contract.
- Single-file `LectureWriterSection.read` creates a `ReadSource` without
  keeping an original `fileBlob`; its saved text preview still works. The MCQ
  import path keeps the original explicitly. This is existing route variance.
- Runtime-tail source map records additional mapping/persistence candidates;
  these need current caller/test confirmation and are not approved new work.

The parent integration coder owns the independently confirmed question-bank
validator batch-size mismatch and preview-artifact publication correction.
No workflow execution, provider call, deployment, source-code edit, medical
content assessment or new design/architecture decision occurred in this reader.

