# Colour roles (23 Oct 2026, task T0134)

The owner, 23 Oct: there is "little to no colour consistency across the app".
The ten hexes stay as they are (palette-2026-10-21.md). This page fixes which
of them each role takes. iPhone and Android read the same table, and code
picks an accent only through the tokens named here, never a literal.

Owner decisions this follows:

- D1 (23 Oct): words on the page are ink, and colour goes on icons, edges
  and fills only (white words on fills, except D8's).
- D3 (23 Oct): a score and a ring keep the section's colour.
- D7 (30 Oct): "right answers have the color of the mode". In every mode a
  right answer takes that mode's colour, through the same mode colour token
  (`wardPrimaryInk` / `WardToken.primaryInk`): Questions' coral, Cases' peach,
  Cards' blue and the others'. There is no separate right-answer green, and
  D3's Fresh Mint exception for Questions is gone.
- D8 (30 Oct, amended the same day): a chosen chip or segment gets a solid
  fill in the mode's accent (`wardPrimary` / `WardToken.primary`) with
  near-black #090E15 words and glyph (`wardOnAccent` / `WardToken.onAccent`;
  the palette doc's "Text on a fill"), on both platforms and in both schemes.
  White words are not used there. A toned chosen chip keeps its tone fill,
  with near-black words (Coverage's status chips; Hint, Flag and the mock's
  Flag in Optimistic Amber).

## Where you are: the mode colour

Each mode's colour is the one its dock tile already carries.

| Mode (section) | Colour | Hex |
|---|---|---|
| Questions | Vital Coral | #FF6B6B |
| Cards | Care Blue | #3B82F6 |
| Textbook | Pulse Teal | #14B8A6 |
| Cases | Peach Glow | #FF9F7A |
| OSCE | Lime Zest | #A3E635 |
| Audio | Soft Lilac | #A78BFA |
| Ideas | Bubblegum Pink | #F472B6 |
| Outside any mode (settings, account, diagnostics, help, tools) | Care Blue | #3B82F6 |

A screen pushed from a mode screen keeps that mode's colour (iOS
`WardSectionMark` is held while its screen is covered, as Android passes its
section down). A mode's own glyph shown somewhere else (home tiles, New set's
kinds, Turn into) takes that mode's colour, not the screen's.

## Roles

| Role | Token, iOS / Android | Colour |
|---|---|---|
| Words, everywhere on the page | `wardInk`, `wardInkSecondary` / `WardToken.ink`, `inkSecondary` | Chart Ink, Biro Grey |
| Words on a fill | `wardOnPrimary` / `WardToken.onPrimary` | white |
| A chosen chip or segment (D8): its fill, and its words and glyph | `wardPrimary` / `WardToken.primary` under `wardOnAccent` / `WardToken.onAccent` | the mode colour under near-black #090E15 |
| The mode's glyphs, edges, rings, chosen tab, chosen chip or segment edge, toggle track, focus ring, link glyph, progress | `wardPrimaryInk`, `wardPrimary`, `wardEdge` / `WardToken.primaryInk`, `primary`, `WardRelief.edgeColor` | the mode colour |
| A given mode's own glyph | `wardAccent(section)` / `wardAccent(section)`, `WardTone.accent` | that mode's colour |
| A right answer (check, letter, ring) | `wardPrimaryInk` / `WardToken.primaryInk`, the mode colour token (D7) | the mode colour, in every mode |
| A wrong answer | the faded row (`wardFaded`, `wardFadedInk`); its cross glyph `wardDanger` | grey; Vital Coral #FF6B6B for a cross outside an option row |
| Scores and rings | the mode colour (D3) | the mode colour |
| Due, warnings | `wardWarning` / `WardToken.warning` (glyphs); words ink | Optimistic Amber #FBBF24 |
| The progress beam, the countdown clock | `wardBeam` / `WardToken.beam` | Optimistic Amber #FBBF24 |
| New | the mode colour (`WardTone.blue`) | the mode colour |
| Done, saved, covered (not an answer) | `wardSuccess` / `WardToken.success` (glyphs) | Fresh Mint #6EE7B7 |
| Danger, destructive | `wardDanger` / `WardToken.danger` (glyphs); a system destructive menu item stays system red on iOS and Vital Coral on Android | Vital Coral #FF6B6B |
| ECG trace | `wardEcg` / `WardToken.ecg` | Vital Coral #FF6B6B |

## Kept on purpose

- Folder colours (Electric Indigo and the others in NoteTone), the occlusion
  cover (Peach Glow), the brand mark and signal, exported decks, and the 3D
  map and Graph scenes: their colours are art or exports, not UI roles.
- The answer letter (A, B, C) is a key, not a word, so it keeps the row's
  colour.
- Destructive menu items: iOS draws them in the system's red and cannot be
  restyled; Android matches with Vital Coral.
- Disease scripts' lookalike chip that jumps to a card (iOS ScriptsView,
  LookalikeChipFace) keeps its name in the accent, as at 10772f07: it is a
  link, not a chosen chip, and moving it to ink brought back a line 9a88b8af
  removed (no-undo U2). It waits on a decision of its own.

## D8: near-black words on each mode's fill

`onAccent` #090E15 on the mode's fill, the same in light and dark (WCAG 2;
ColourRolesTest and WardStatesTest check 4.5:1, WardPaletteTests the promise
on the primary):

| Mode | Fill | Ratio |
|---|---|---|
| Questions | #FF6B6B | 6.97 |
| Cards | #3B82F6 | 5.26 |
| Textbook | #14B8A6 | 7.77 |
| Cases | #FF9F7A | 9.67 |
| OSCE | #A3E635 | 12.83 |
| Audio | #A78BFA | 7.11 |
| Ideas | #F472B6 | 7.31 |

A toned chosen chip keeps its tone fill, with near-black words, the same
in light and dark: Vital Coral (red, danger) 6.97, Fresh Mint (green)
12.69, Optimistic Amber (amber, warning) 11.59, and a section's accent as
above. Biro Grey (grey) would read 3.06 by day, so no chosen chip is toned
grey (ColourRolesTest checks the sources).

A chosen and disabled chip or segment is not filled: it keeps its accent
edge and says its words in Biro Grey, as every disabled control does.

## Guards

- iOS: `tests/ward/colour-roles.test.mjs` fails on a section other than a
  screen's own, a colour literal in a screen, or an accent on a one-line
  word.
- Android: `ColourRolesTest` (unit test) does the same over
  `app/src/main`.

## Audit: the uses this changed

Each row is an accent use that broke the roles above, found by reading the
screens on both platforms and listed from the diff against 10772f07. "Hex
before" for a mode token is the colour of the mode the screen sits in.
Uses whose glyph already took its role and only lost a coloured word are
counted under words.

| Role | Platform | Screen | Token before | Hex before | After | Uses |
|---|---|---|---|---|---|---|
| a mode's own glyph | Android | LibraryList | WardTone.Blue | Care Blue #3B82F6 | that mode colour | 1 |
| a mode's own glyph | Android | LibraryNewSetScreen | WardTone.Blue | Care Blue #3B82F6 | that mode colour | 1 |
| glyph / mark (moved to shared piece) | Android | CoverageScreen | WardToken.primaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | role token via shared control | 1 |
| glyph / mark (moved to shared piece) | Android | LibraryNewSetScreen | WardToken.primaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | role token via shared control | 2 |
| glyph / mark (moved to shared piece) | Android | WardPocketScreen | WardToken.primaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | role token via shared control | 1 |
| glyph / mark (moved to shared piece) | iOS | ChartQuizViews | wardPrimaryInk | Questions #FF6B6B | role token via shared control | 1 |
| glyph / mark (moved to shared piece) | iOS | FirstRunView | wardPrimaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | role token via shared control | 1 |
| glyph / mark (moved to shared piece) | iOS | InsightViews | wardSuccess | Fresh Mint #6EE7B7 | role token via shared control | 1 |
| glyph / mark (moved to shared piece) | iOS | MCQQuizView | wardDanger | Vital Coral #FF6B6B | role token via shared control | 1 |
| glyph / mark (moved to shared piece) | iOS | MCQQuizView | wardSuccess | Fresh Mint #6EE7B7 | role token via shared control | 1 |
| glyph / mark (moved to shared piece) | iOS | MCQQuizView | wardWarning | Optimistic Amber #FBBF24 | role token via shared control | 1 |
| glyph / mark (moved to shared piece) | iOS | NewSetView | wardPrimaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | role token via shared control | 1 |
| glyph / mark (moved to shared piece) | iOS | WardControls | wardDanger | Vital Coral #FF6B6B | role token via shared control | 1 |
| glyph / mark (moved to shared piece) | iOS | WardControls | wardPrimaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | role token via shared control | 1 |
| glyph / mark (moved to shared piece) | iOS | WardPocketView | wardPrimaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | role token via shared control | 1 |
| glyph / mark (moved to shared piece) | iOS | WardStates | wardPrimaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | role token via shared control | 1 |
| right answer | Android | CardsEditorScreen | WardToken.success | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 1 |
| right answer | Android | CardsEditorScreen | WardToken.success | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 2 |
| right answer | Android | GuessFirstScreen | WardToken.success | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 1 |
| right answer | Android | InsightViews | WardToken.success | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 2 |
| right answer | Android | MCQQuizScreen | WardToken.success | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 1 |
| right answer | Android | MCQSummaryScreen | WardToken.success | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 1 |
| right answer | Android | MockResultsScreen | WardToken.success | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 1 |
| right answer | Android | MockResultsScreen | WardToken.success | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 2 |
| right answer | Android | StatsScreen | WardToken.success | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 1 |
| right answer | Android | StatsScreen | WardToken.success | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 2 |
| right answer | Android | VitalsScreen | WardToken.success | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 2 |
| right answer | iOS | AnalyticsView | wardSuccess | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 1 |
| right answer | iOS | CardEditSheets | wardSuccess | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 1 |
| right answer | iOS | CardsEditorView | wardSuccess | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 1 |
| right answer | iOS | DuelView | wardSuccess | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 2 |
| right answer | iOS | GuessFirstView | wardSuccess | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 1 |
| right answer | iOS | MCQSummaryView | wardSuccess | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 1 |
| right answer | iOS | MockResultsView | wardSuccess | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 2 |
| right answer | iOS | LensAnswerSheet | wardSuccess | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 1 |
| right answer | iOS | StatsView | wardSuccess | Fresh Mint #6EE7B7 | wardPrimaryInk (the mode colour, D7) | 1 |
| words | Android | AccuracyWhySheet | WardToken.primaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | ink | 1 |
| words | Android | AnkiCardFace | WardToken.primaryInk | Cards #3B82F6 | ink | 1 |
| words | Android | AnkiReviewScreen | WardToken.primaryInk | Cards #3B82F6 | ink | 1 |
| words | Android | CardsEditorScreen | WardToken.primaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | ink | 1 |
| words | Android | CoverageScreen | WardToken.primaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | ink | 1 |
| words | Android | ExamDayKitScreen | WardToken.primaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | ink | 1 |
| words | Android | FixWordSheet | WardToken.danger | Vital Coral #FF6B6B | ink | 1 |
| words | Android | IdeaTools | WardToken.primaryInk | Ideas #F472B6 | ink | 1 |
| words | Android | IdeasSpace | WardToken.primaryInk | Ideas #F472B6 | ink | 1 |
| words | Android | IdeasView | WardToken.primaryInk | Ideas #F472B6 | ink | 1 |
| words | Android | LectureWriterSection | WardToken.primaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | ink | 1 |
| words | Android | MCQExamTools | WardToken.primaryInk | Questions #FF6B6B | ink | 1 |
| words | Android | MCQSummaryScreen | WardToken.success | Fresh Mint #6EE7B7 | ink | 1 |
| words | Android | MockPaperScreen | WardToken.danger | Vital Coral #FF6B6B | ink | 1 |
| words | Android | MockPaperScreen | WardToken.primaryInk | Questions #FF6B6B | ink | 1 |
| words | Android | MockResultsScreen | WardToken.danger | Vital Coral #FF6B6B | ink | 1 |
| words | Android | NoteEditor | WardToken.primaryInk | Ideas #F472B6 | ink | 3 |
| words | Android | OsceGenerateSection | WardToken.primaryInk | OSCE #A3E635 | ink | 1 |
| words | Android | PictureFromPhotoScreen | WardToken.primaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | ink | 1 |
| words | Android | ReviewCardActions | WardToken.danger | Vital Coral #FF6B6B | ink | 1 |
| words | Android | ReviewCardActions | WardToken.primaryInk | Cards #3B82F6 | ink | 1 |
| words | Android | SourcesCreditsScreen | WardToken.primaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | ink | 1 |
| words | Android | StatsScreen | WardToken.primaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | ink | 1 |
| words | Android | VitalsScreen | WardToken.danger | Vital Coral #FF6B6B | ink | 1 |
| words | Android | WardControls | WardToken.warning | Optimistic Amber #FBBF24 | ink | 1 |
| words | Android | WardPocketScreen | WardToken.primaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | ink | 2 |
| words | Android | WardPocketScreen | WardToken.warning | Optimistic Amber #FBBF24 | ink | 1 |
| words | Android | WardRoundViews | WardToken.danger | Vital Coral #FF6B6B | ink | 1 |
| words | iOS | CardsEditorView | wardPrimaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | ink | 1 |
| words | iOS | CaseMakeSection | wardDanger | Vital Coral #FF6B6B | ink | 1 |
| words | iOS | CaseWardView | wardPrimaryInk | Cases #FF9F7A | ink | 1 |
| words | iOS | DuelView | wardPrimaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | ink | 2 |
| words | iOS | FixWordSheet | wardDanger | Vital Coral #FF6B6B | ink | 1 |
| words | iOS | IdeaBoardView | wardPrimaryInk | Ideas #F472B6 | ink | 1 |
| words | iOS | LensAnswerSheet | wardPrimaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | ink | 1 |
| words | iOS | MCQSummaryView | wardSuccess | Fresh Mint #6EE7B7 | ink | 1 |
| words | iOS | MockPaperView | wardPrimaryInk | Questions #FF6B6B | ink | 1 |
| words | iOS | PaywallView | wardSuccess | Fresh Mint #6EE7B7 | ink | 1 |
| words | iOS | SourcePreviewView | wardPrimaryInk | Care Blue #3B82F6 (or the mode it is pushed from) | ink | 3 |
| words | iOS | SpokenStationView | wardPrimaryInk | Audio #A78BFA | ink | 1 |
| words | iOS | VoiceParts | wardPrimaryInk | Audio #A78BFA | ink | 1 |
| words | iOS | WardControls | wardWarning | Optimistic Amber #FBBF24 | ink | 1 |
| words | iOS | WardRoundView | wardDanger | Vital Coral #FF6B6B | ink | 1 |

## No-undo: the lines this rewrites

`tools/no_undo.py --base 10772f07 --onto 10772f07 --change HEAD` is OK
(nothing landed between). Counted from where the colour work started
(`--base f0fad3d0 --onto 10772f07`), it lists 36 U1 lines, all below, each
changed by a decision, and no U2 (ScriptsView's line is back as it was).
No line is left that no decision covers.

| Platform | File: lines | What changes | Decision |
|---|---|---|---|
| Android | AccuracyWhySheet.kt:397, 427 | a rule's title and a source's reference, accent words to ink | D1 |
| Android | AnkiCardFace.kt:64 | the card's type badge, accent words to ink | D1 |
| Android | AnkiCardFace.kt:224, 231 | a rating tile's words to ink, its tone moved to the tile's ring | D1 |
| Android | AnkiReviewScreen.kt:315 | the card's prompt line, accent words to ink | D1 |
| Android | MCQExamTools.kt:163 | "Attending's hint", accent words to ink | D1 |
| Android | MCQQuizScreen.kt:560 | the verdict line's words to ink; its mark in the mode colour | D1, D7 |
| Android | ReviewCardActions.kt:75 | "Undo", accent words to ink | D1 |
| Android | cases/CaseKit.kt:89, 113 | a patient's initials and the case clock's words to ink | D1 |
| Android | home/WardHome.kt:324 | "Start revision" set in ink, not the content colour | D1 |
| Android | learn/WardRoundViews.kt:330 | "Stop the focus session", danger words to ink (the glyph keeps the colour) | D1 |
| Android | ward/WardControlStates.kt:235 | a chosen segment: the accent fill and near-black words | D8 |
| Android | ward/WardControls.kt:216-217 | WardChipButton's comment: words ink, glyph in the tone | D1 |
| Android | ward/WardControls.kt:255 | WardChipButton's glyph: the chosen colour off the fill, near-black on it | D1, D8 |
| Android | ward/WardStates.kt:124-125, 128, 131, 134 | WardFilterChip: words ink; on, the accent fill and near-black words | D1, D8 |
| Android | test/.../ward/OwnerAccepted.kt:255-352 (7 ranges) | accepted states cases follow the colour from "its words" to "its glyph"; the chosen chip's and segment's cases are gone, as they now pass | D1, D8 |
| iOS | Features/Coverage/CoverageView.swift:465-466 | the count chip's comment: words ink, the status colour on its glyph | D1 |
| iOS | Features/MCQ/MCQQuizView.swift:751 | the verdict label's words to ink; its mark in the mode colour | D1, D7 |
| iOS | Tests/OwnerAccepted.json:188-337 (7 ranges) | as Android's OwnerAccepted.kt | D1, D8 |
