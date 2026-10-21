# Android parity with the iOS app

What the Android app (Kotlin and Compose, `app/src/main/java/com/stethoscore/app/`) has of the iOS app it copies (`upstream/ios/RedPen/`), and the order the rest is ported in. The aim is a one-to-one replica, in shape and in function, of the latest iOS app.

Paths below drop the common prefixes: iOS files are under `upstream/ios/RedPen/`, Kotlin files under `app/src/main/java/com/stethoscore/app/`.

Verdicts: **same** (ported value for value, with tests), **differs** (exists on Android, but not as iOS has it), **missing** (nothing on Android yet).

## Features

One row per folder in `Features/`.

| iOS | Kotlin | Verdict |
|---|---|---|
| `Features/Account/` (RecordingTermsView: the terms every account agrees to) | none | missing |
| `Features/Analytics/` (AnalyticsView, AnalyticsVisuals, VitalsParts: the Vitals screen) | `ui/VitalsScreen.kt` | differs: a 7-day bar card and three rings, not the vitals monitor, readiness rings and trend charts |
| `Features/Anki/` (AnkiReviewView, AnkiCardFace, DueTodayView, ReviewCardActions, AnkiScheduler) | `ui/StudyScreens.kt` (CardsScreen), `data/AnkiScheduler.kt`, `data/ReviewOptions.kt` | differs: scheduling matches; the card face, flip, due-today list and card actions are plain Material |
| `Features/Auth/` (SignInView, AccountView, LinkDeviceView) | `network/BackendClient.kt`, `network/SecureTokenStore.kt` | missing: transport and token store only, no sign-in, account or link-device screens |
| `Features/Book/` (BookReaderView) | `ui/ClinicalScreens.kt` (TextbookScreen) | differs: markdown blocks in a column; no pages, figures, reader bar or highlights |
| `Features/Cases/` (CaseListView, CaseWardView, CaseDecisionView, CaseDebriefView, CaseMaker, CaseRunStore, writers) | `ui/ClinicalScreens.kt` (CasesScreen, CaseWorkupScreen, CaseDebrief), `ui/ClinicalLogic.kt` | differs: work-up, decision and debrief run; no case maker or on-device writers, layout not the ward view |
| `Features/Coverage/` (CoverageView, CoverageChecker: what the exam covers that the library does not) | none | missing |
| `Features/Exam/` (ExamPickerView, ExamDashboardCard, WardPocketView: exam choice and the ward pocket's reference tabs) | `ui/EditorSettings.kt` (exam date), `ui/StethoscoreApp.kt` (countdown) | differs: an exam date only; no picker, dashboard card or ward pocket |
| `Features/Examples/` (ExamplesHubView, OcclusionExample: the tour of every feature) | `data/DemoData.kt`, "Explore example sets" | differs: loads example sets; no hub that opens each feature on its example |
| `Features/Insight/` (InsightViews, InsightExamples, RuleSheetView: drills from Vitals) | none | missing |
| `Features/Learn/` (WardRoundView, WardRoundOverlay, GuessFirstView, BedtimeReviewView, ExamPlanView, ExamDayKitView, SymptomBlocksView, LearnRoutes) | `ui/StethoscoreApp.kt` (RoundCard) | differs: a "round" card on home; the ward round itself, guess-first, bedtime review, exam plan and exam-day kit are missing |
| `Features/Lens/` (StudyLensView, LensCamera, LensModel, LensAddSheet, LensAnswerSheet) | none | missing |
| `Features/Library/` (WardHome, LibraryView, rows, shelves, search, NewSetView and dock, editors, imports, scanner, stats, export intents) | `ui/StethoscoreApp.kt` (home, SetRow, search, CategoryDock), `ui/EditorSettings.kt` (NewSetScreen), `data/StudyStore.kt`, `export/` | differs: one list on home's ground (its category's wash and grid, opening on Questions), with the dock's concentric chosen tab (WardDock, WardDockTest); Ideas sits in the panel rather than a pill of its own, and there are no shelves, sheets, card editors, scanner, stats or picture-from-photo |
| `Features/MCQ/` (MCQQuizView, MCQSummaryView, MCQExamTools, ChartQuiz) | `ui/StudyScreens.kt` (QuizScreen) | differs: question, choices and feedback work; no faded wrong rows, exam tools, summary or chart quiz |
| `Features/Mock/` (MockPaperView, MockSittingView, MockResultsView, MockSittingSave) | none | missing |
| `Features/Narrate/` (NarrateReviewView, listening, reading, audio bar, word flow, fix-word sheet, lecture importer) | `ui/ClinicalScreens.kt` (NarrateScreen, Android TextToSpeech) | differs: reads segments aloud; no spoken-word wash, audio bar, word fixes or lecture import |
| `Features/Notes/` (IdeasView, IdeaBoardView, NoteEditorView, Graph3DView and the Graph* renderer) | `ui/IdeasScreen.kt`, `ui/map/Map3DView.kt`, `ui/map/GlMapRenderer.kt`, `map/` | differs: notes, links and a GL ES 3.0 map run; no idea board, neuron look, shaders or the iOS graph styles |
| `Features/OSCE/` (OsceReviewView, OsceGenerateSection) | `ui/ClinicalScreens.kt` (OsceScreen) | differs: recall-in-order works; no generation section, iOS layout |
| `Features/Onboarding/` (FirstRunView, StudyTips) | none | missing |
| `Features/Paywall/` (PaywallView) | none | missing (nearest Android way: Play Billing; store work needs the owner's word) |
| `Features/Reasoning/` (ReasoningView, DuelView, ScriptsView, HowToReachCard) | none | missing |
| `Features/Recall/` (DrawRecallView, RecallAttempts, RecallExamples) | none | missing |
| `Features/Sources/` (SourcesLibraryView, SourceDocumentView, SourcePageReader, SourcePreviewView, ReaderBar, SourcesCreditsView) | `data/Models.kt` (SourceDoc), shown in `ui/ClinicalScreens.kt` | missing: sources are kept and listed, no source library or reader |
| `Features/Support/` (settings sections, model settings, diagnostics, reminders, report sheet, review prompt, accuracy badge) | `ui/EditorSettings.kt` (SettingsScreen) | differs: night shift, scheduler limits, import and export; most sections, reminders and the accuracy badge missing |
| `Features/Voice/` (CommuteModeView, SpokenStationView, ExplainBackView, sessions, entry points) | none | missing (nearest Android way: SpeechRecognizer and TextToSpeech) |

## The Ward look

One row per file in `Shared/Ward/`.

| iOS | Kotlin | Verdict |
|---|---|---|
| `Shared/Ward/WardPalette.swift` (tokens, light and dark hex, linear-light mix, contrast promises, WardScale, WardSchemeGlide) | `ui/ward/WardPalette.kt` | same (WardPaletteTest) |
| `Shared/Ward/WardLook.swift` (WardSection's ink, accent, fill and wash; WardWash; WardLook, WardGlide, WardLookNow; relief, press and paper mixed by night; WardSection.opening and WardGround, home's ground) | `ui/ward/WardSection.kt`, `ui/ward/WardLook.kt` | same (WardLookTest, WardGroundTest) |
| `Shared/Ward/WardRelief.swift` (lifts, lights, relief and rim, press, paper ink and panel, WardEdge joins) | `ui/ward/WardRelief.kt` | same: every part, WardEdge's joins too (WardReliefTest, every iOS case) |
| `Shared/Ward/WardTokens.swift` (the palette as SwiftUI colours, type, spacing, radii, the look driver) | `ui/Theme.kt` (wardColorScheme, wardColor, wardInk, StethoscoreTheme) | differs: colours come from the Ward core, set per section; no type scale, radii or animated glide yet |
| `Shared/Ward/WardSurfaces.swift` (soft UI surfaces: raised, inset, rimmed faces, paper frame, the ground behind a page; no top scroll-edge line since b3b21c29) | `ui/ward/WardSurfaces.kt` (wardRaised, wardInset, wardRelief, WardCardFace, WardMonitorCard, WardPaperFrame), `ui/Theme.kt` (WardCard, EcgGrid), `ui/WardGroundViews.kt` (WardGroundBackground) | differs: raised, rimmed, inset and pressable faces from WardRelief and WardPress, cards at iOS's radius and gutter, the monitor's well in its bezel, the paper frame round every page but home with iOS's continuous opening (WardEdge.outline) and its bar-line join; corners circular elsewhere, lights drawn live (no cached images), no Increase Contrast, no slab (WardDeckSlab), header band (WardPaperBand) or bar strip (WardEdgeHost: no Android page has a bottom bar yet). No page draws a line under its header (ScrollEdgeTest) |
| `Shared/Ward/WardControls.swift` (buttons, chips, pills, icon squares, rings, segmented, fields) | `ui/Theme.kt` (WardButton, SectionLabel, ScreenHeader) | differs: an outlined Material button in the section's ink; the rest missing |
| `Shared/Ward/WardControlStates.swift` (each control in rest, held, disabled, chosen; WardDock, the dock's concentric chosen tab) | `ui/ward/WardDock.kt` | differs: WardDock and the chosen edge's width are ported (WardDockTest, also for the circular corners Compose draws); the states of every other control are missing |
| `Shared/Ward/WardStatesGallery.swift` (preview screen of every control state) | none | missing |
| `Shared/Ward/WardStates.swift` (empty states, banners) | inline in screens | differs: ad hoc cards, not the shared empty state and banner |
| `Shared/Ward/WardIsland.swift` (window geometry for the page and the paper frame) | `ui/ward/WardIsland.kt` | same (WardIslandTest, every iOS case) |
| `Shared/Ward/WardLightSlice.swift` (the relief's soft lights, drawn once: the maths) | `ui/ward/WardLightSlice.kt` | same: reach, the cut, keys and the census (WardLightSliceTest, every iOS case); nothing draws from it yet (WardLightImages) |
| `Shared/Ward/WardLightImages.swift` (the lights rendered and cached) | none | missing (as above) |
| `Shared/Ward/WardPartLedger.swift` (home's parts that can meet its cut) | none | missing |
| `Shared/Ward/WardVitals.swift` (readiness ring, monitor parts) | `ui/VitalsScreen.kt` (MetricRing, monitor card in Ward tokens) | differs: rings drawn on a Material track, monitor colours now from the palette |

## Where iOS can't be copied

- SwiftUI shadows and blurs: Compose has no inner shadow. Draw the inset lights with `drawBehind` and a blur-masked `Paint` (or `RenderEffect` on API 31+), from WardRelief's numbers.
- Dynamic `UIColor` per trait: Android uses a Compose `CompositionLocal` (`LocalWardLook`) and a Material scheme rebuilt per look; the glide between looks animates a `WardGlide` progress with `animateFloatAsState`.
- Asset catalogue colours (AccentColor, LaunchBackground): Android keeps them as `res/values` colours and the splash theme; the test checks the table against the iOS assets.
- The opening (LaunchScreen, LaunchPaper, LaunchSplash): Android's starting window and Android 12 splash stand on `ward_ground` (values and values-night, checked against WardGround by WardGroundTest); from the app's first frame the window's background is home's ground drawn as vectors (`ui/WardGroundViews.kt`, WardGroundDrawable), so there is no picture. The system's starting window cannot run app code, so it shows the ground's base without the grid; the app's mode is passed to the system (UiModeManager, Android 12 and up) so that colour is in the app's light or dark. There is no animated opening on Android yet.
- Swipe back: the edge swipe and predictive back are the system's back (on by default when targeting 36 and up), handled on every pushed screen by BackHandler (SwipeBackTest); nothing excludes the screen's edges.
- SF Symbols: Material Symbols (rounded), nearest glyph per symbol; SF Mono: `FontFamily.Monospace`.
- Sheets and the dock: `ModalBottomSheet` and a custom bottom bar, not `NavigationBar`.
- Speech (Narrate, Voice): `TextToSpeech` and `SpeechRecognizer`; on-device Gemma: MediaPipe LLM Inference; Apple Foundation Models writer: the cloud writer only.
- Document scanner and camera (Lens, Library): ML Kit document scanner and CameraX.
- App Intents and widgets: app shortcuts and Glance widgets.
- Metal map (Notes): OpenGL ES 3.0 now, Vulkan later.
- StoreKit (Paywall): Play Billing, behind the owner's word.
- PDF contents links (DeckPDF): Android's PdfDocument has no link annotations, so the printed deck lists page numbers instead.
- Account sync: the backend transport (`network/BackendClient.kt`) is not automatic, conflict-preserving sync yet; that comes with Account (batch 19). APKG import and export, transcription and recording, cloud generation and the accuracy UI are still missing too.

## The port, in day-sized batches

Look first, then home and library, each study mode, the rest. Each batch ports the iOS Foundation-only logic with its tests first, then the views, then screenshots against iOS's `shots/`.

1. **The Ward look's core** (done): WardPalette, WardSection, WardLook, WardRelief (but WardEdge) in `ui/ward/`, Theme.kt drawing every colour from them per section; WardPaletteTest and WardLookTest ported.
2. **Ward surfaces** (partial: the maths and its three suites done; the faces, the monitor's well and the paper frame drawn and in use; cached light images, slabs, the header band and bar strips left): WardEdge, WardIsland, WardLightSlice maths; raised, inset and rimmed faces, the paper frame, inset wells (WardSurfaces); WardReliefTests, WardIslandTests, WardLightSliceTests.
3. **Ward controls and type**: WardTokens' type, spacing and radii; WardControls (buttons, chips, pills, icon squares, segmented, fields, rings) with WardControlStates and the states gallery; the animated glide (WardLookDriver); WardStatesTests.
4. **Home**: WardHome and WardPartLedger (paper, header, mode tiles, dock), the exam card and countdown; HomeFitTests, WardRoundTests' home parts.
5. **Library**: LibraryView, shelves, rows, search, tag chips, NewSetView and dock, import preview and incoming import, stats.
6. **Library editors**: card editors, occlusion cover editor, MCQ generate form, lecture PDF and writer sections, picture from photo, document scanner (ML Kit).
7. **Questions**: MCQQuizView with faded wrong rows, MCQExamTools, MCQSummaryView, ChartQuiz.
8. **Cards**: AnkiReviewView, AnkiCardFace, DueTodayView, ReviewCardActions, FSRS.
9. **Textbook and Sources**: BookReaderView, figures, highlights; SourcesLibraryView, SourceDocumentView, SourcePageReader, reader bar, credits.
10. **Cases**: CaseListView, CaseWardView, CaseDecisionView, CaseDebriefView, CaseMaker and run store.
11. **OSCE and Mock**: OsceReviewView, OsceGenerateSection; MockPaperView, MockSittingView, MockResultsView.
12. **Audio**: NarrateReviewView, listening and reading, the spoken word's wash, audio bar, fix-word sheet, lecture importer.
13. **Ideas**: IdeasView, IdeaBoardView, NoteEditorView, the graph's look (GraphLook, GraphTheme, neurons) on the GL map.
14. **Learn**: WardRoundView and overlay, GuessFirstView, BedtimeReviewView, ExamPlanView, ExamDayKitView, SymptomBlocksView.
15. **Vitals and Insight**: AnalyticsView, AnalyticsVisuals, VitalsParts, WardVitals; InsightViews, RuleSheetView; Coverage.
16. **Exam and pocket**: ExamPickerView, ExamDashboardCard, WardPocketView.
17. **Reasoning and Recall**: ReasoningView, DuelView, ScriptsView; DrawRecallView, RecallAttempts.
18. **Voice and Lens**: CommuteMode, SpokenStation, ExplainBack (SpeechRecognizer); StudyLensView (CameraX).
19. **Account and first run**: RecordingTermsView, SignInView, AccountView, LinkDeviceView, FirstRunView, StudyTips, ExamplesHubView.
20. **Settings and support**: every Support section, reminders, diagnostics, model settings, report sheet, accuracy badge; Paywall (Play Billing) only with the owner's word.
