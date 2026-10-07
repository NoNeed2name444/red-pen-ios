# Latest native runtime tail source map

Reader scope: manifest chunks 135–214 inclusive in `/tmp/ios-runtime-chunks.json`, source `/workspace/repositories/red-pen-ios-latest`. Fully consumed: all 80 chunks, 135–214 inclusive, covering all contents of 137 current Swift source files (1,382,432 decoded characters). Ledger `/tmp/ios-runtime-tail-read-chunks.json`; exact decoded-character ranges `/tmp/ios-runtime-tail-read-ranges.json`. Coverage was recorded only after consuming each bounded, untruncated source output. There is no shared-file boundary at chunks 134/135: 134 ends with `Exam/TwinQueue.swift`, and 135 begins `ExamTrack.swift`. Read latest CLAUDE.md and full Chat-me-personal handoff context first. Current source reading only; no source edits, historical Cases reads, providers, orchestration, deployment or new medical/design/pedagogic decisions.

## Existing contracts read

- GenerationCenter admits one job, keeps screen owner UUID and cloud Delivery cancellation semantics; floating actions defer to its busy state.
- ExamTrack/ExamChoice feed existing prompts and timing; Apple and Gemma generation use whole-source windows plus MCQCoverage and MCQRepair.
- ImportRouter privately copies incoming files, delegates to registered preview, then front-window inbox; ImportKind accepts current set/backup plus Anki, tables, lectures and images.
- SaveToIdeas retains NoteSource (kind/set/item/page), dedupes item identity, routes backlinks using AppLink.openItem and offers append/Undo through attached NoteStore.
- Learn modules derive daily quizzes, secured standings, exam plan, retention forecast, reminders and question-of-day from stored event/card history. Answer option slots must translate through OptionOrder to original indices.
- LibraryFile and LibraryBackup preserve undecodable sets as raw JSON. Backup merges sets/folders and files without replacement; colliding items are renewed and the plan records old→new mappings.
- FigureFinder, FigureGrid, OcclusionFilter/Phrases and PhotoOcclusion separate OCR/device reading from cover geometry; images use normalized top-left boxes and sibling masks shared across review, PDF and Anki.
- LectureAudio derives local filenames from set id, keeps arbitrary imported extensions and copies before replacement. LecturePlayer uses AVAudioPlayer clock, while LectureTranscriber yields measured word timings.
- Platform modules expose AppLink, intents, app lock, age signal, widgets digest, exam Live Activity and optional focus-round Health writes; Playgrounds paths have explicit capability fences.
- PopOut uses one motion engine plus locked snapshot, nested plane deltas and shared accessibility/thermal/power/focus gates.
- ModeConversion reuses existing questions/cards/stations and copies set images/sources; QuizFromCards builds distractors from the same deck and rejects existing CardQuality fatal tells.
- ReasoningStore persists packs/duel plays separately, invokes existing ReasoningWriter, participates in GenerationCenter and reads bundled examples by fixed IDs.
- SetImport gives received sets a new UUID, drops unavailable blob images and rebases every surviving picture reference. SetPictures carries images/source documents with mistakes and rebases picture positions when joining sets.
- SoundKey explicitly requires parity with `consensus.py` in red-pen-transcribe. No cross-repository parity claim is made by this reader.
- SourceIngest handles embedded text/OCR per PDF page, uses separate PDFDocument per worker, compacts figures in page order, and labels measured versus estimated word timing. Zip and Zstd implement bounded current import formats.
- SyncAPI reads cursor pages and per-document push outcomes; SyncMerge retains losing real edits as copies, resolves tombstones by timestamps, and SyncRules holds documents that would lose fields. StoreFiles distinguishes missing from protected/unreadable files and reports write failure.
- VoiceAccess asks only on use. VoiceListener invalidates stale recognition callbacks, VoiceSpeaker awaits actual playback completion, NarrateVoice queues cached clips with phone fallback, and NowPlaying binds/relinquishes remote command tokens.
- GraphicsBudget and SpaceQuality remain separate existing cost/motion gates. SpaceFeedback leaves the voice modes’ audio session intact. Theme and Ward modules expose existing shared controls, palette and window-width contracts.
- WardPocket and WardPocketScores hold existing formula, input, unit and table contracts plus sources and practice-note exports. Their medical content was read without assessment or revision.

## Mechanical candidates (confirm at call sites/tests before any change)

1. `LearnStore.lockInPicks` treats every correct answer today as already credited, including `hinted == true`, while `SecuredRule.standing` explicitly does not credit hinted correctness. The selection filter can suppress a same-day unaided opportunity for an item still building. Also `SecuredRule.countsToday` examines latest correctness without hinted distinction.
2. Backup schedule candidate withdrawn after full reading of current DataIOTests and DeckTests: shared cards in differing backup copies intentionally receive fresh IDs while their progress remains with this phone’s existing copy. Unique cards retain IDs and schedules. Preserve this explicit tested contract.
3. `ModeConversion.card(from:)` (ModeConversion.swift:71) does not carry question.imageIndex or tags into the produced card despite convert copying set images. A question with a diagram can lose its image attachment in the converted card (mechanical field mapping).

4. `OcclusionPhrases.layout` (OcclusionPhrases.swift:487) filters each cover by calling `problems` with that cover plus all the other made covers. This is the same full cover collection for each predicate call; if one cover makes any problem, every cover can be discarded despite the local comment saying only the bad one is left off. Confirm using the existing geometry checks before changing.
5. `PlainTextImport`’s column-based question reader (PlainTextImport.swift:406) filters empty option columns before translating a supplied option letter. A hole before the keyed column can shift the positional letter away from the intended nonempty option. Confirm the supported table convention at its callers.
6. `GlancePublisher.save` (Platform/GlancePublisher.swift:52) caches `last = digest` before `GlanceShelf.write` succeeds. After a failed write, an unchanged digest is treated as already published and is not retried. This is a persistence ordering issue.

These are existing-contract discrepancies or mechanical mapping/persistence candidates, not approved feature changes. In particular, the hinted-credit discrepancy requires confirming the existing intended filter contract; this reader makes no new pedagogic choice. The backup candidate has now been disproven by the existing restore tests; see `latest-native-test-source-map.md`.

No medical claims were assessed or revised.

## Fully consumed file coverage

Each file below was consumed from decoded offset 0 through its current end; files spanning chunk boundaries were read contiguously.


| Current source path | Decoded characters read |
|---|---:|
| `ios/RedPen/Shared/ExamTrack.swift` | 6158 |
| `ios/RedPen/Shared/FSRS.swift` | 7109 |
| `ios/RedPen/Shared/FigureFinder.swift` | 13840 |
| `ios/RedPen/Shared/FigureGrid.swift` | 9128 |
| `ios/RedPen/Shared/FirstRunRules.swift` | 5770 |
| `ios/RedPen/Shared/FloatingAction.swift` | 5532 |
| `ios/RedPen/Shared/FloatingSwitcher.swift` | 8104 |
| `ios/RedPen/Shared/GemmaDownload.swift` | 4630 |
| `ios/RedPen/Shared/GemmaGenerate.swift` | 5769 |
| `ios/RedPen/Shared/GenerationCenter.swift` | 9122 |
| `ios/RedPen/Shared/GenerationRules.swift` | 2264 |
| `ios/RedPen/Shared/HeadTracker.swift` | 3517 |
| `ios/RedPen/Shared/Highlight.swift` | 3271 |
| `ios/RedPen/Shared/Ideas/SaveToIdeas.swift` | 19426 |
| `ios/RedPen/Shared/Ideas/SaveToIdeasUI.swift` | 26658 |
| `ios/RedPen/Shared/ImageSpoiler.swift` | 6458 |
| `ios/RedPen/Shared/ImportRouter.swift` | 17452 |
| `ios/RedPen/Shared/Insight/InsightModels.swift` | 5239 |
| `ios/RedPen/Shared/Insight/Readiness.swift` | 4963 |
| `ios/RedPen/Shared/Insight/RuleWriter.swift` | 5767 |
| `ios/RedPen/Shared/Insight/StemKeyWords.swift` | 2038 |
| `ios/RedPen/Shared/Insight/StoreInsight.swift` | 9684 |
| `ios/RedPen/Shared/KeyboardShortcuts.swift` | 751 |
| `ios/RedPen/Shared/LaunchSplash.swift` | 2835 |
| `ios/RedPen/Shared/Learn/BedPlan.swift` | 17727 |
| `ios/RedPen/Shared/Learn/ExamWeekPlanner.swift` | 10858 |
| `ios/RedPen/Shared/Learn/LearnNotifications.swift` | 11013 |
| `ios/RedPen/Shared/Learn/LearnRouter.swift` | 1989 |
| `ios/RedPen/Shared/Learn/LearnStore.swift` | 11520 |
| `ios/RedPen/Shared/Learn/Pretest.swift` | 12539 |
| `ios/RedPen/Shared/Learn/RetentionForecast.swift` | 6923 |
| `ios/RedPen/Shared/Learn/RhythmReading.swift` | 6737 |
| `ios/RedPen/Shared/Learn/SecuredRule.swift` | 4687 |
| `ios/RedPen/Shared/Learn/StudyRhythm.swift` | 7471 |
| `ios/RedPen/Shared/Learn/SymptomBlocks.swift` | 17637 |
| `ios/RedPen/Shared/Learn/WardWords.swift` | 2999 |
| `ios/RedPen/Shared/LectureAudio.swift` | 5779 |
| `ios/RedPen/Shared/LecturePlayer.swift` | 6637 |
| `ios/RedPen/Shared/LectureTranscriber.swift` | 7495 |
| `ios/RedPen/Shared/Lens/LensAnswer.swift` | 17860 |
| `ios/RedPen/Shared/Lens/LensConversion.swift` | 16352 |
| `ios/RedPen/Shared/Lens/LensTracking.swift` | 11733 |
| `ios/RedPen/Shared/Lens/QuestionDetector.swift` | 33758 |
| `ios/RedPen/Shared/LibraryBackup.swift` | 21998 |
| `ios/RedPen/Shared/LibraryBackupRunner.swift` | 16727 |
| `ios/RedPen/Shared/LibraryFile.swift` | 2642 |
| `ios/RedPen/Shared/LibrarySearch.swift` | 18231 |
| `ios/RedPen/Shared/LiquidGlass.swift` | 2783 |
| `ios/RedPen/Shared/MCQCoverage.swift` | 7986 |
| `ios/RedPen/Shared/MCQEdit.swift` | 2925 |
| `ios/RedPen/Shared/MCQGenerator.swift` | 10150 |
| `ios/RedPen/Shared/MCQPrompt.swift` | 12523 |
| `ios/RedPen/Shared/MCQRepair.swift` | 11206 |
| `ios/RedPen/Shared/MiniZip.swift` | 5435 |
| `ios/RedPen/Shared/ModeConversion.swift` | 6955 |
| `ios/RedPen/Shared/NarratePlan.swift` | 9636 |
| `ios/RedPen/Shared/NetworkFaults.swift` | 2520 |
| `ios/RedPen/Shared/OcclusionFilter.swift` | 22648 |
| `ios/RedPen/Shared/OcclusionPhrases.swift` | 31287 |
| `ios/RedPen/Shared/OfficeIngest.swift` | 7598 |
| `ios/RedPen/Shared/OptionOrder.swift` | 2229 |
| `ios/RedPen/Shared/OsceGenerator.swift` | 5832 |
| `ios/RedPen/Shared/OsceStations.swift` | 6989 |
| `ios/RedPen/Shared/OwnerClaim.swift` | 659 |
| `ios/RedPen/Shared/PDFExporter.swift` | 8250 |
| `ios/RedPen/Shared/PDFOcclusion.swift` | 7854 |
| `ios/RedPen/Shared/PatientChart.swift` | 14765 |
| `ios/RedPen/Shared/PersonalBuild.swift` | 1931 |
| `ios/RedPen/Shared/PhotoOcclusion.swift` | 10934 |
| `ios/RedPen/Shared/PhotoOcclusionReader.swift` | 11029 |
| `ios/RedPen/Shared/PlainTextImport.swift` | 22629 |
| `ios/RedPen/Shared/Platform/AgeGate.swift` | 3455 |
| `ios/RedPen/Shared/Platform/AgeSignal.swift` | 1325 |
| `ios/RedPen/Shared/Platform/AppLink.swift` | 13099 |
| `ios/RedPen/Shared/Platform/AppLock.swift` | 5393 |
| `ios/RedPen/Shared/Platform/ExamDayAttributes.swift` | 891 |
| `ios/RedPen/Shared/Platform/GlanceDigest.swift` | 8919 |
| `ios/RedPen/Shared/Platform/GlancePublisher.swift` | 4031 |
| `ios/RedPen/Shared/Platform/MindfulMinutes.swift` | 2986 |
| `ios/RedPen/Shared/Platform/ReviewDueIntent.swift` | 1428 |
| `ios/RedPen/Shared/Platform/SetWindow.swift` | 4920 |
| `ios/RedPen/Shared/PopOut.swift` | 27561 |
| `ios/RedPen/Shared/PopOutMotion.swift` | 16162 |
| `ios/RedPen/Shared/PptxText.swift` | 5879 |
| `ios/RedPen/Shared/PreviewExtras.swift` | 5141 |
| `ios/RedPen/Shared/PreviewLaunch.swift` | 16771 |
| `ios/RedPen/Shared/QuizFromCards.swift` | 13352 |
| `ios/RedPen/Shared/Reasoning/ReasoningExamples.swift` | 13707 |
| `ios/RedPen/Shared/Reasoning/ReasoningModels.swift` | 5824 |
| `ios/RedPen/Shared/Reasoning/ReasoningStore.swift` | 7515 |
| `ios/RedPen/Shared/Reasoning/ReasoningWriter.swift` | 16035 |
| `ios/RedPen/Shared/RecoveryFiles.swift` | 4048 |
| `ios/RedPen/Shared/RedPenOCR.swift` | 6219 |
| `ios/RedPen/Shared/ReviewOptions.swift` | 19200 |
| `ios/RedPen/Shared/ReviewPlan.swift` | 13121 |
| `ios/RedPen/Shared/SampleLectures.swift` | 9896 |
| `ios/RedPen/Shared/SetImport.swift` | 3862 |
| `ios/RedPen/Shared/SetPictures.swift` | 3279 |
| `ios/RedPen/Shared/SoundKey.swift` | 6253 |
| `ios/RedPen/Shared/SourceIngest.swift` | 12389 |
| `ios/RedPen/Shared/Space/GraphicsQuality.swift` | 11586 |
| `ios/RedPen/Shared/Space/NebulaBaker.swift` | 18278 |
| `ios/RedPen/Shared/Space/PhotonRing.swift` | 8709 |
| `ios/RedPen/Shared/Space/SkyChart.swift` | 6037 |
| `ios/RedPen/Shared/Space/SpaceFeedback.swift` | 13261 |
| `ios/RedPen/Shared/Space/SpaceQuality.swift` | 12301 |
| `ios/RedPen/Shared/Space/StarLayers.swift` | 16048 |
| `ios/RedPen/Shared/Space/WarpEffect.swift` | 6689 |
| `ios/RedPen/Shared/StoreFiles.swift` | 1604 |
| `ios/RedPen/Shared/StudyLog.swift` | 3425 |
| `ios/RedPen/Shared/SubscriptionStore.swift` | 9380 |
| `ios/RedPen/Shared/SupportOutbox.swift` | 5793 |
| `ios/RedPen/Shared/SupportSender.swift` | 5664 |
| `ios/RedPen/Shared/SyncAPI.swift` | 6746 |
| `ios/RedPen/Shared/SyncMerge.swift` | 6183 |
| `ios/RedPen/Shared/SyncRules.swift` | 10424 |
| `ios/RedPen/Shared/Theme.swift` | 31710 |
| `ios/RedPen/Shared/Voice/CloudVoice.swift` | 10674 |
| `ios/RedPen/Shared/Voice/NarrateVoice.swift` | 32300 |
| `ios/RedPen/Shared/Voice/NowPlaying.swift` | 2910 |
| `ios/RedPen/Shared/Voice/SpokenAnswer.swift` | 22434 |
| `ios/RedPen/Shared/Voice/VoiceAccess.swift` | 5220 |
| `ios/RedPen/Shared/Voice/VoiceExamples.swift` | 10256 |
| `ios/RedPen/Shared/Voice/VoiceHistory.swift` | 5329 |
| `ios/RedPen/Shared/Voice/VoiceListener.swift` | 6743 |
| `ios/RedPen/Shared/Voice/VoiceMarking.swift` | 13074 |
| `ios/RedPen/Shared/Voice/VoiceSpeaker.swift` | 9024 |
| `ios/RedPen/Shared/Ward/WardControls.swift` | 9340 |
| `ios/RedPen/Shared/Ward/WardPalette.swift` | 3487 |
| `ios/RedPen/Shared/Ward/WardSurfaces.swift` | 3487 |
| `ios/RedPen/Shared/Ward/WardTokens.swift` | 3285 |
| `ios/RedPen/Shared/Ward/WardVitals.swift` | 5055 |
| `ios/RedPen/Shared/WardPocket.swift` | 42248 |
| `ios/RedPen/Shared/WardPocketScores.swift` | 32789 |
| `ios/RedPen/Shared/WordTiming.swift` | 6679 |
| `ios/RedPen/Shared/Zip.swift` | 15692 |
| `ios/RedPen/Shared/Zstd.swift` | 32357 |
