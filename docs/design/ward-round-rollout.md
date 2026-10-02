# Ward Round design language: rollout plan

Written 1 October 2026 from an inventory of every screen (the screen-by-screen inventory is kept with the session; this is the plan). Target: docs/design/targets-2026-10-01.md §1.

# Ward Round rollout plan for Stethoscore

*Read-only survey of `personal` @ 022becc, 1 October 2026. Targets: `docs/design/targets-2026-10-01.md` §1. No Rank, Clerk badge or XP anywhere. The app is called Stethoscore and uses `Brand.name`.*

## 0. Before anything else

- **`design/ward-round` is not on origin.** `git ls-remote origin design/ward-round` returns nothing, so there are no commits to diff against `personal`. This plan therefore sets out the foundation as the contract that branch should deliver. If it pushes something different, rename this plan to match it, not the other way round.
- **Two unmerged branches already use the "Ward" name and touch the same files.**
  - `origin/gaps/wardround` (3 commits, 23 files) adds the types `WardRound`, `WardRoundClock`, `WardRoundTile`, `WardRoundChip`, `WardRoundPanel`, `WardRoundStyle`, `WardRoundFloat`, `OrbitRing`, `StillStarField` and `DailyGoalRing`. Its overlay is still drawn in the space look. It edits `LibraryRows.swift`, `AnalyticsView.swift`, `AnalyticsVisuals.swift`, `ExamPlanView.swift`, `LearnRoutes.swift` and `SupportCenter.swift`.
  - `origin/gaps/wardpocket` adds `WardPocket*`, `WardField`, `WardUnit`, `WardFormula`, `WardCalcView`, `WardScoreView` and `WardUnitsPicker`. It edits `Theme.swift`, `MCQExamTools.swift`, `MCQQuizView.swift` and `ExamPlanView.swift`.
  - **Rule:** design-system types must not use the `WardRound*`, `WardPocket*`, `WardField`, `WardUnit` or `WardScore*` names. `StatusChip` is also taken (`Features/Coverage/CoverageView.swift:511`). I checked every name proposed below against all three branches and none is in use.
- **Naming.** The inventory sometimes says "Theme Blue". The token is **Theatre Blue #1D5FB0**, as in the targets doc.

## 1. Shared foundation

Everything goes in a new folder, `ios/RedPen/Shared/Ward/`.
- That folder is not in `CORE_DROP`, so the Playgrounds core, core1 and core2 all pick it up with no change to `make_swiftpm.py`.
- No file in it may name a type from `Shared/Space`, `PopOut`, `Shared/Learn`, `Features/Analytics` or the gaps branches. This keeps it legal for `tools/playgrounds_cut.py`.
- The core build is at about 34,000 lines against the owner's 36,000 limit. The whole folder should stay under about 900 lines, and the space code it replaces should be deleted as the batches move off it.

### 1a. Tokens

| File | Contents |
|---|---|
| `Shared/Ward/WardPalette.swift` | **Foundation only, no SwiftUI.** A table of the 11 doc tokens plus extra tokens, as `(light, dark)` hex pairs. Also `contrast(a,b)` (WCAG). Tested on Linux. |
| `Shared/Ward/WardTokens.swift` | Under `#if canImport(SwiftUI)`: `extension Color` with `.wardBackground`, `.wardSurface`, `.wardPrimary` (the fill), `.wardPrimaryInk` (blue text and glyphs on a surface), `.wardOnPrimary`, `.wardEcg`, `.wardBeam`, `.wardSuccess`, `.wardWarning`, `.wardDanger`, `.wardInk`, `.wardInkSecondary`, `.wardHairline`, `.wardGridMinor`, `.wardGridMajor`, `.wardMonitor`. Each is built from the table through a dynamic `UIColor { traits in … }`, so there is one source and no colorset drift. Also `WardType`, `WardSpace`, `WardRadius` and `WardShadow`. |
| `Tests/WardPaletteTests.swift` (new suite, add to `tools/swift_suites.txt`) | Every text/surface pair meets its stated ratio in light and dark. AccentColor and LaunchBackground colorset JSON equal the table (read with Foundation, so it runs on Linux). |
| `Assets.xcassets/AccentColor.colorset` | Today it is empty (system blue). Set it to Theatre Blue, with the dark variant from the table. The package copies `Assets.xcassets` and uses `accentColor: .asset("AccentColor")`, so Playgrounds gets it too. |
| `Assets.xcassets/LaunchBackground.colorset` + `Shared/LaunchSplash.swift:25` `midnight` | Change both together. The owner picks Ward White or Theatre Blue. |

**Extra tokens.** Values I checked against the doc:
- Hairline: #E1E7EE light, #2A3A4D dark.
- Grid lines: Theatre Blue at 6% (minor) and 12% (major).
- Monitor card: #0E1B2C (Chart Ink) in both modes.
- Chip fills: the tone colour at 12% over Clean Sheet.

**Dark "night shift" set.** The doc does not specify one; this is a proposal for the owner. Ratios are measured against the dark surface:

| Token | Value | Ratio |
|---|---|---|
| Background | #0B131D | |
| Surface | #152230 | |
| Primary fill | #2A6BC4 | white on it 5.25 |
| Primary ink | #7DB0F2 | 7.2 |
| ECG Red | #F2788A | 6.0 |
| Pager Amber | #F0A04B | 7.6 |
| Discharge Green | #4CC38A | 7.3 |
| Caution Amber | #E7AE45 | 8.1 |
| Resus Red | #F57A7F | 6.1 |
| Chart Ink | #E8EEF5 | 13.8 |
| Biro Grey | #A3B1C3 | 7.4 |

In dark mode there are no card shadows; edges come from the hairline only.

**Type (`WardType`).** Use system fonts only; bundle no font files.
- The system font is SF Pro: SwiftUI switches to the Display optical size at 20pt and above, and uses Text below.
- SF Mono is `design: .monospaced`.
- Styles:
  - `display`: `.largeTitle.bold`
  - `title`: `.title3.semibold`
  - `body`
  - `smallCaps`: `.caption.weight(.semibold)` + `.textCase(.uppercase)` + `.tracking(0.8)`, in Biro Grey. The source strings stay in mixed case so VoiceOver reads words, not letters.
  - `obs`: `.system(.body, design: .monospaced)`
  - `obsLarge`: `.system(.title2, design: .monospaced).weight(.semibold)`
- Every style is a text style, so Dynamic Type scales all of them. Ring numerals use `@ScaledMetric`.

**Spacing and radii.**
- `WardSpace`: 4, 8, 12, 16 (the gutter), 20, 24.
- `WardRadius`:

| Element | Radius |
|---|---|
| Card / tile | 16 |
| Button | 14 |
| Text field | 12 |
| Icon square | 10 |
| Chip, pill | capsule |
| Bottom bar | 22 |

- `WardShadow` (light mode only): y 1 / r 2 at 4%, plus y 6 / r 16 at 6%.

### 1b. Components

| Component | File (`Shared/Ward/…`) | Replaces |
|---|---|---|
| `WardBackground` (Ward White + a static ECG grid drawn with `Canvas`, 8pt minor and 40pt major lines; `accessibilityHidden`) and `.wardScreen()` | `WardSurfaces.swift` | AppBackdrop use in `ModeBackdrop` and `LibraryBackdrop`, `.skyScroll` |
| `.wardCard()` / `WardCard {}` (Clean Sheet, hairline, `WardShadow`), `WardGroupedCard` (rows with inset hairline separators), `.wardRowBackground()` | `WardSurfaces.swift` | `ContentCard`, `frostedListRow`, hand-rolled `.regularMaterial` cards |
| `.wardForm()`: hidden scroll background + WardBackground + white rows + small-caps Biro headers + Theatre Blue tint | `WardSurfaces.swift` | Form/List chrome on about 25 screens |
| `MonitorCard` (Chart Ink in both modes, green trace, mono obs) | `WardSurfaces.swift` | none yet (Vitals, commute player) |
| `WardButtonStyle`: `.wardPrimary`, `.wardSecondary`, `.wardDestructive`, `.wardCompact`; 56pt tall, 360pt cap on iPad, disabled in Biro Grey | `WardControls.swift` | `BigButtonStyle` (the old names map to these), `.glass` / `.glassProminent` |
| `WardChip(text, tone: .blue/.green/.amber/.red/.grey/.neutral, symbol:)`, `WardFilterChip`, `WardPill` (Finals countdown), `WardTimerPill` (SF Mono; turns Resus Red under a threshold; shows "Time" at zero), `WardTextLink` | `WardControls.swift` | `liquidGlassChip`, `OptionalTag`, the four timer chips (MCQ `examClock`, Mock, OSCE `stationClock`, `StationTimerChip`), the ExamBadge capsule |
| `WardIconSquare(symbol, tone)`, `WardSectionLabel(text, trailing:)`, `WardRow(icon, overline, title, detail, chip, accessory: .chevron/.check/.radio/.none)`. **BedRow** is `WardRow` with an overline of "BED n · …". `WardTile` (white, icon top left, minimum 112pt) | `WardRows.swift` | `ModeTile` + `CoronaGlow` + `PhotonRim`, `CategoryHeading`, `CategoryRowLabel`, `FeatureTile` |
| `WardRing(value, tone, label)`, `EcgStrip(progress)` (Pager Amber beam), `EcgSquiggle`, `EcgLoader` (indeterminate; static under Reduce Motion), `ObsValue(label, value, flag: .high/.low)`, `VitalsGrid`, `LabsTableRow`, `WardProgressBar` (semantic thresholds) | `WardVitals.swift` | `ScoreRing`/`PhotonArc`, `ThinProgress`, `ProgressView` spinners, `.rounded` numerals, `AuroraCurtain` |
| `WardHeader(title, subtitle, timer:, progress:)` | `WardHeader.swift` | `StudyProgressHeader` |
| `WardBottomBar {}` | `WardHeader.swift` | `StudyActionBar`, `.studyBar` |
| `WardEmptyState(symbol, title, message, primary:, secondary:)`, `WardBanner(tone, text, action:)`, `WardTextField(label:)` | `WardStates.swift` | `FinishHero` (non-celebration uses), `ContentUnavailableView`, red/orange caption text, `popFieldRow` |
| `WardSegmented` (one style for `CategoryDock`, its rail and `FloatingSwitcher`), `WardRoundButton` (Ideas floating button, mic, send), `WardAvatar` | `WardNav.swift` | `liquidGlassPanel` dock, `CoronaGlow`, gold Ideas pill |

Some components live outside `Shared/Ward` because they belong to one area:
- `WardOptionRow`: owned by `design/ward-round`, shared by MCQ and Mock.
- `ConsultTranscript`, `ConsultComposer` and `VoiceCircle`: the B5 batch puts these in `Features/Voice/ConsultParts.swift`.
- `SetRow`: `design/ward-round` builds it for home; B3 reuses it.

### 1c. Batch 0: re-point the old helpers (one agent, after `design/ward-round` lands its tokens)

This step keeps every existing API and only changes what the helpers draw, so the whole app turns Ward Round before any screen is rewritten.

| File | Change |
|---|---|
| `Shared/Theme.swift` | `ModeTintKey.defaultValue` (line 284) becomes `.wardPrimary`. `modeScreen(kind)` (line 180) sets the modeTint to Theatre Blue; the kind's colour now only tints the icon glyph. `ContentCard` becomes a white card. `BigButtonStyle` uses `WardButtonStyle`. `StudyActionBar` uses `WardBottomBar`. `StudyProgressHeader` uses `WardHeader`. `ThinProgress` uses `EcgStrip`. `ScoreRing` uses `WardRing`. `ModeTile` uses `WardIconSquare`, and `CoronaGlow` and `PhotonRim` become no-ops. `ModeBackdrop` uses `WardBackground`. |
| `StudySetKind.tint` (Theme.swift:12-21) | Becomes palette-derived quiet glyph colours. |
| `Shared/LiquidGlass.swift` | The chip and panel become white with a hairline. |
| `Shared/PopOut.swift`, `PopOutMotion.swift` | `PopOutTuning` goes to zero; `popOut` keeps only `WardShadow`. |
| `Features/Library/LibraryChrome.swift` | `LibraryBackdrop` uses `WardBackground`. |
| `Features/Library/CategoryPages.swift:112` | The body of `frostedListRow` becomes the white row background. |
| `Shared/Brand.swift:37-49` | ink → Chart Ink, paper → Ward White, signal → Pager Amber, mark → Theatre Blue. |
| `RedPenApp.swift:257, 291` | Pen red becomes `.wardPrimary`. |
| `Features/Auth/SignInView.swift:22` | The `pen` constant becomes `.wardPrimary`. |
| `Features/Support/AccuracyBadge.swift` | `AccuracyGrade.color` uses the semantic tones; the badge face becomes `WardChip`. |
| `Shared/FloatingSwitcher.swift`, `Shared/FloatingAction.swift` | Use `WardSegmented` and `WardBottomBar`. |
| `tools/playgrounds_stubs/core/CoreStandIns.swift` | The `AppBackdrop` stand-in (line 269) draws `WardBackground`; `PopTileStyle` goes flat; delete the `PhotonArc` and `AuroraCurtain` stand-ins if nothing still names them. |
| `tools/playgrounds_stubs/core/CoreApp.swift:99` | The tint becomes `.wardPrimary`. |

`AppBackdrop.swift` and `Shared/Space/*` stay as they are, for the 3D Ideas map only.

**Batch 0 is done when:**
- `tools/preflight.sh` is green, including the WardPalette suite.
- `swiftpm-check` is green for core, core1 and core2.
- In ios-preview (light and dark), all 18 screens show a white/grid ground with Theatre Blue controls.
- `rg -n 'Color\(red: 0\.78'` finds nothing under `ios/RedPen`.

## 2. Rollout batches

The rules for running batches in parallel:
- **Each file belongs to exactly one batch.** A file that Batch 0 touched may be touched again later; that is sequential, not parallel.
- **No more than 4 or 5 agents at once.** macOS runners are limited to five.
- **Each batch gets its own `design/ward-<batch>` branch**, rebased on `personal` after Batch 0 merges.
- **"Lane W" is `design/ward-round`.** It already owns `LibraryView.swift`, `LibraryRows.swift`, `StudyCategory.swift`, `LibraryCategory.swift`, `MCQQuizView.swift`, `MCQExamTools.swift`, `AnalyticsView.swift`, `AnalyticsVisuals.swift` and `StatsView.swift`. That covers home, dock, tiles, the question screen and Vitals. No batch below touches these files.
- **Merge the gaps branches first.** `gaps/wardround` and `gaps/wardpocket` should merge into `personal` before Lane W finishes and before B11, because they edit Lane W and B11 files.

The batches, in priority order (what a student sees most comes first):

| # | Batch | Files (all under `ios/RedPen/` unless noted) | Depends on |
|---|---|---|---|
| B1 | **Playgrounds core shell** (the build the owner actually runs) | `tools/playgrounds_stubs/core/CoreLibrary.swift`, `core/CoreApp.swift`, `core-audio-out/*`, `core-audio-in/*`, `core-exports-*/*`, `_common.swift` (`NotInThisBuild` becomes `WardEmptyState`), `analytics.swift`, `lens.swift`, `graph3d.swift` | B0. See §3. |
| B2 | **Cards review** | `Features/Anki/AnkiReviewView.swift`, `AnkiCardFace.swift` (with `AnkiFooter`, `AnkiRatingBar`), `DueTodayView.swift`, `ReviewCardActions.swift` | B0 |
| B3 | **Library pages and search** | `Features/Library/CategoryShelves.swift`, `CategoryPages.swift`, `TurnIntoPicker.swift`, `LibrarySearchResults.swift`, `LibrarySearchModel.swift`, `CustomSessionSheet.swift`, `LibrarySheets.swift`, `LibraryChrome.swift` (NameSheet) | B0. Uses Lane W's `SetRow` once it lands; until then, `WardRow`. |
| B4 | **New set (the admission flow)** | `Features/Library/NewSetView.swift`, `NewSetDock.swift`, `MCQGenerateForm.swift`, `LecturePDFSection.swift`, `LectureWriterSection.swift`, `ImportPreviewSheet.swift`, `LibraryImport.swift`, `IncomingImport.swift`, `Features/OSCE/OsceGenerateSection.swift`, `Shared/GenerationCenter.swift` (`GenerationHUD`), `Shared/ImportRouter.swift` (`ImportInboxSheet`) | B0 |
| B5 | **OSCE** | `Features/OSCE/OsceReviewView.swift`, `SpokenStationView.swift`, `VoiceParts.swift`, and the new `ConsultParts.swift` | B0 |
| B6 | **Questions after the question screen** | `Features/MCQ/MCQSummaryView.swift`, `Features/Mock/MockPaperView.swift`, `MockSittingView.swift`, `MockResultsView.swift` | B0 + Lane W's `WardOptionRow` |
| B7 | **Book and sources** | `Features/Book/BookReaderView.swift` (with `FlowchartView`), `Features/Sources/*` | B0 |
| B8 | **Audio, spoken drills, drawing** | `Features/Narrate/*`, `Features/Voice/CommuteModeView.swift`, `ExplainBackView.swift`, `VoiceEntryPoints.swift`, `Features/Recall/DrawRecallView.swift` | B0. B5 owns `VoiceParts.swift` and `ConsultParts.swift`; B8 only calls them. Start after B5 if B8 needs changes to either. |
| B9 | **Settings, account, accuracy sheets** | `Features/Support/ReviewSettingsSection.swift`, `StudyReminderSettings.swift`, `LibraryDataSettingsSection.swift`, `PlatformSettingsSection.swift`, `ModelSettingsView.swift`, `DiagnosticsSettingsView.swift`, `HelpContactSection.swift`, `AccuracyCheckSheet.swift`, `QuestionReportSheet.swift`, `AccuracyBadge.swift` (`AccuracyWhySheet`, `NoteAccuracyButton`), `Features/Auth/AccountView.swift`, `LinkDeviceView.swift`, `Shared/Platform/AppLock.swift` | B0. `SupportCenter.swift` goes in B11 after `gaps/wardround` merges, or in B9 if it has already merged. |
| B10 | **Front door** | `Features/Auth/SignInView.swift`, `Features/Account/RecordingTermsView.swift`, `Features/Exam/ExamPickerView.swift` (with `ExamOnboardingView` and `ExamBadge`), `Features/Paywall/PaywallView.swift`, `Shared/LaunchSplash.swift` | B0 + the owner's launch colour choice |
| B11 | **Plan and insight** | `Features/Learn/*` (including `WardRoundView.swift` and `WardRoundOverlay.swift` from the gaps branch), `Features/Exam/ExamDashboardCard.swift`, `WardPocketView.swift`, `Features/Coverage/CoverageView.swift` (rename its `StatusChip` to use `WardChip`), `Features/Insight/*`, `Features/Examples/*`, `Features/Support/SupportCenter.swift` | B0 + gaps/wardround and gaps/wardpocket merged |
| B12 | **Ideas 2D, Lens, Reasoning** | `Features/Notes/IdeasView.swift`, `IdeaBoardView.swift`, `IdeaTools.swift`, `IdeasBottomBar.swift`, `NoteEditorView.swift`, `NoteMarkdown.swift`, `NoteExamples.swift`, `NotesShared.swift`, `Features/Lens/*`, `Features/Reasoning/*` | B0. The `Graph*.swift` files and `ForceLayout3D.swift` stay in the space look (doc §2-4). |
| B13 | **Editors and picture cards** | `Features/Library/CardsEditorView.swift`, `CardEditSheets.swift`, `TagChips.swift`, `PictureFromPhotoView.swift`, `OcclusionCoverEditor.swift`, `DocumentScannerSheet.swift` | B0 |

**What every batch must do (the screen mappings are in the inventory):**
- Replace the space words with ward words: "Mission Control" becomes "Today's ward round", "lift-off" becomes "Start ward round", a set is a patient, a session is a ward round, Progress is Vitals, weak spots are "Needs a consult".
- Show observations in SF Mono: timers, scores, counts, intervals, lab values, codes.
- Delete the call sites of `popOut`, `skyZoomSource`, `SpaceWarp` and `liftOff` that the batch's files use.
- Do not add any rank, level or XP wording.

**Acceptance checks for every batch:**
1. **Clean code.** In the batch's files, this finds nothing except deliberate system dialogs:
   `rg -n '\.(red|green|orange|yellow|blue|indigo|purple|mint|teal)\b|Color\(red:|accentColor|regularMaterial|thinMaterial|glassEffect|glassProminent|\.glass\b|liquidGlass|popOut\(|AppBackdrop|PhotonArc|CoronaGlow|AuroraCurtain|design: \.rounded'`
   Colours come only from `Color.ward*` tokens.
2. **Light and dark.** `ios-preview.yml` shots of the batch's screens in both modes, plus any new `-uiPreviewScreen` cases the batch adds (`PreviewLaunch.swift`, one line each; batches add cases at the end of the switch to avoid conflicts). Text passes AA against its surface: tokens only, guarded by WardPaletteTests. Increase Contrast darkens hairlines and grid lines (`colorSchemeContrast`).
3. **Dynamic Type.** A preview pass with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`:
   - `WardRow` stacks the icon above the text, and chips wrap below the title, when `dynamicTypeSize.isAccessibilitySize`.
   - No small-caps line or mono value is truncated mid-word, and no fixed heights clip.
   - Buttons grow; nothing is capped at 56pt.
4. **VoiceOver.**
   - Each `WardRow` is one element (label "Bed 1, Cardiology, spaced review, 12 cards due, Due") with the button trait.
   - Chips read their text, never colour alone; right and wrong options also carry an icon.
   - Rings give a value ("68 percent").
   - `WardBackground`, `EcgSquiggle` and the decorative ECG traces are hidden.
   - Timer pills announce changes only at minute marks.
   - Focus order runs top to bottom, then the bottom bar.
5. **iPad.**
   - `ipad-preview.yml` portrait and landscape, and `ipad-widths.yml` at 320, 507, 678 and full width.
   - Reading content stays in `ReadableColumn` (760 or 820); the grid fills the whole window; bottom bars cap at 360 per button.
   - The rail and the dock both use `WardSegmented`.
6. **Playgrounds.** `swiftpm-check.yml` is green for core, core1 and core2. `tools/playgrounds_cut.py --drop … --names` lists no new names the batch's kept files need. Core line count stays under 36,000.
7. **Motion.** Under Reduce Motion, ECG sweeps, loaders and the strip fill are static or crossfade.
8. **Preflight.** `tools/preflight.sh` is green, and `tools/ci_status.py <branch> --wait` exits 0, before the batch merges into `personal`.

## 3. Playgrounds core stand-ins

The owner's iPad zip is `--without core`, so what the owner sees is mostly the stand-in shell, not `LibraryView.swift`. The shell has to be restyled on purpose; without that, the zip shows only Batch 0's recolouring.

1. **Free from Batch 0.**
   - `Shared/Ward/*` is copied into the zip automatically.
   - `Theme.swift`, `LiquidGlass.swift`, `LibraryChrome.swift`, `FloatingSwitcher.swift`, `FloatingAction.swift` and `AccuracyBadge.swift` are already kept files.
   - The colorsets travel with `Assets.xcassets`.
   - So every kept study screen (MCQ, Anki, Book, OSCE, Sources, New set, sign-in, terms, exam) turns Ward Round with no stand-in work.
   - In the stand-ins, `AppBackdrop` draws `WardBackground` and `PopTileStyle` is flat (Batch 0).
2. **B1 restyles `core/CoreLibrary.swift` as a small Ward home:**
   - the date line in small caps, `Brand.name` with `EcgSquiggle`, the Finals `WardPill` from the exam store, and `WardAvatar` opening `CoreSettingsView`;
   - a "TODAY'S WARD ROUND" card in which Due today is BED 1, using only kept types (no `Shared/Learn` planner);
   - "YOUR SETS" as `WardRow` or `SetRow` in a `WardGroupedCard`, with folders as section labels;
   - Sources as a row;
   - a primary `.wardCompact` "New set".
   `CoreSettingsView` uses `.wardForm()`. `CoreBuildNote` and `NotInThisBuild` use `WardEmptyState` ("Not on this ward yet").
3. **Shared home pieces.** If Lane W puts the home's header and set-row pieces in a kept file that names only kept types (for example a new `Features/Library/WardHomeParts.swift`, not in `CORE_DROP`), the core shell can reuse them instead of copying them. Lane W should check this with `playgrounds_cut.py --names` before choosing where those pieces live.
4. **Stand-ins for dropped screens.** `core-audio-out/CoreAudioStandIns.swift` and the `analytics.swift`, `lens.swift` and `graph3d.swift` placeholders use `WardEmptyState`, so the gaps also look Ward Round.
5. **Line budget.** Ward foundation at most about 900 lines; the shell restyle should come out net zero or negative. Delete stand-ins the Ward code no longer needs: `PhotonArc`, `AuroraCurtain`, `FinishScoreKey` if unused, `SpaceQuality` if unused.
6. **Proof.** `swiftpm-launch.yml` on `ci/launch` launches the core in the simulator. Attach its screenshot (light and dark) to the B1 commit. Send the zip only after the owner has reported the core and core1 results (README status, 1 October).

## 4. Risks

- **`design/ward-round` is not pushed yet.** Its token and component names may differ from this plan. Nothing past Batch 0 can start until its foundation is on origin. Agree the names in §1 with it first, or Batch 0 has to be redone.
- **Name collisions with the gaps branches** (`WardRound*`, `WardField`, `StatusChip`). Also, `gaps/wardround` brings new space-styled UI (`StillStarField`, `OrbitRing`, `WardRoundPanel`) and edits Lane W files. Merge it, then restyle it in B11. If not, Lane W will hit merge conflicts in `LibraryRows.swift` and `AnalyticsVisuals.swift`.
- **Pager Amber is not safe for small text.** It is 4.16:1 on Clean Sheet and 3.84:1 on Ward White, so AA large only. Use it for beams, rings, highlights and fills. Pill text, such as "Finals in N days", must use Caution Amber #9A5B00 on an amber tint, or white bold text at 14pt or more. The WardPaletteTests guard this.
- **Dark mode is unspecified.** The night-shift set in §1a is a proposal. The "Always night sky", "Pop-out", face-tracking and Graphics settings (`SupportCenter.swift:150-264`, `SpaceQuality.swift:249-312`) currently force dark for the sky. The owner has to decide whether they move under an "Ideas map" header and whether the app simply follows the system appearance.
- **Launch colour.** The owner has to choose: `LaunchBackground` is midnight today, and `LaunchSplash` plus `project.yml:71-72` must change together, or a dark frame will flash before the white app.
- **Playgrounds ceiling.** The Ward code adds lines to a core sitting at about 34,000 of 36,000. Removing space code offsets this only in the full app; the core already drops `Shared/Space`. Keep the foundation small, and re-measure after B0 and B1.
- **Re-pointing everything at once in Batch 0** (BigButton, ContentCard, ModeBackdrop, PopOut) changes all 18 preview screens in one commit. That makes it easy to miss an unreadable combination, for example a white-on-tint `bigSecondary` that now sits on white. Compare every preview screen in both modes before merging.
- **Keeping the old helper APIs as shims** leaves dead code (`PopOutPlane` arguments, `modeTint`, `kind.tint`). Each batch removes its own call sites; a final sweep deletes the shims and the `CoreStandIns` entries.
- **Mode identity.** One Theatre Blue chrome removes the per-mode colour that students use to tell modes apart. The mode icons and small-caps lines ("MCQ · 42 QUESTIONS") have to carry that instead. Watch for feedback.
- **The space look stays for the 3D Ideas map** (doc §2-4). The 2D board (B12) and the map's panels (`GraphMapPanels.swift`, `GraphLegend.swift`) sit on the boundary. Settle which side they belong to before B12, or the Ideas screens will have two languages.
- **Clinical wording can go too far.** Settings labels ("New admissions a day") or "ward" for folders would be less clear. Keep the real labels and use the metaphors in small-caps lines, headings and empty states.
- **Accessibility traps.** `.textCase(.uppercase)` on short strings can make VoiceOver spell out letters, so keep source strings in natural case and audit acronyms. A Canvas grid behind `List` must stay outside the scroll content so it does not redraw on every frame.

Key paths:
- `/home/user/red-pen-ios/docs/design/targets-2026-10-01.md`
- `/home/user/red-pen-ios/CLAUDE.md`
- `/home/user/red-pen-ios/ios/RedPen/Shared/Theme.swift`
- `/home/user/red-pen-ios/tools/make_swiftpm.py`
- `/home/user/red-pen-ios/tools/playgrounds_stubs/core/CoreLibrary.swift`
- `/home/user/red-pen-ios/tools/playgrounds_stubs/core/CoreStandIns.swift`
- `/home/user/red-pen-ios/.github/workflows/ios-preview.yml`