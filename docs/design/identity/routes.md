# Identity routes

Written 15 Oct 2026. Three routes for Stethoscore's identity, all built on the [platform](platform.md), with palettes and contrast in [palettes.md](palettes.md) and wording from [wording.md](wording.md).

The owner has the three boards; they are not in the repo because they contain the owner's mark images. Each board is a page 1880 pt wide, rendered at 3x, with phone screens at 393 × 852 pt. Each one shows:

- the lockup and its spacing rules;
- the palette in light and dark, with the WCAG ratios printed;
- the type pairing and scale;
- the components: the primary button with its rim, chips, a card, the four states of an MCQ option and the tab bar;
- home in light and dark, with the exam wording;
- an MCQ screen;
- one key frame of the opening.

The mocks are HTML and CSS rendered in Chromium, with the real marks composited, never redrawn. Inter stands in for SF Pro (and Nunito for SF Pro Rounded in Route C), and each board says so.

The boards were revised the same day after an independent review. In every route, cards are now flat, chips follow one rule, and text set on the grid is measured over its bold lines. Route C was rebuilt around its two materials. A second review of these docs changed four things the boards do not show yet and will in their next render: the soft rim is on buttons only, so fields and the tab bar are flat; Route B marks correct in the mode's hue and wrong in pencil; Route C's Plum, Lilac and Raspberry move apart; and C's steel is exactly neutral. The rules that apply to all three routes are under [What every route shares](#what-every-route-shares).

| | A, Red Pen | B, Answer Sheet | C, Steel & Silicone |
|---|---|---|---|
| Idea | Revision, marked the way a good examiner marks a paper: a red pen on ECG paper. | Every mark counts: the clean logic of an answer sheet, read by a calibrated instrument. | The instrument you carry into every exam: soft silicone, bright steel, a tube in every colour. |
| Hero (and Trace) | Pen Red `#BE0222`, dark `#FF5D6D` | Signal Orange: text `#9A4703`, graphics `#C75A0C`, dark `#EF7107` | Plum `#86266A`, dark `#E77FC2` |
| Ground | Warm paper `#EAE5DD`, dark `#211D1A` | Neutral paper `#E8E8E6`, dark `#181716` | Rose-grey silicone `#EBE5E9`, dark `#242023` |
| Display type | Newsreader SemiBold, a serif | Archivo Expanded Bold, with IBM Plex Mono for numbers | SF Pro Rounded Heavy |
| ECG stroke | A pen line that tapers and thins with speed | The trace after a calibration pulse | A tube-weight line, 3 pt, round joins |
| Marking | Ticks, circled scores, margin notes | Answer-sheet lozenges, timing marks, a mark scheme | Steel bezels, silicone fills, a steel-tracked ring |
| Correct / wrong | A tick in the mode's own ink (red in Questions) / pencil, struck through | A lozenge filled in the mode's hue / a pencil lozenge, struck through | The mode's own hue (silicone) / bare steel, struck through |
| Shape | Pill buttons, 20 pt cards | 12 pt buttons, 14 pt cards, 4 pt chips | Pill buttons, 28 pt cards, 24 pt rows |

## Route A: Red Pen (the seed, developed)

**Idea.** Revision, marked the way a good examiner marks a paper: a red pen on ECG paper.

**On the board.**

- **Colour.** Pen Red is the hero, the Questions hue and the Trace, on a warm paper ground. It replaces the brief's ECG Red `#D32F45`, which is 3.93:1 on paper and 3.48:1 in wells, too light for text. By night it is the crimson `#FF5D6D`, the most vivid red that clears 4.5:1 on every dark ground. The other modes become inks: Rust (Cards), Green ink (Textbook), Teal ink (Cases), Ochre (OSCE), Violet ink (Audio) and Magenta ink (Ideas). A correct answer gets a tick in the mode's own ink (the red pen in Questions, Rust in Cards, and so on) and the words "Correct answer". A wrong answer is struck through in pencil with "Your answer"; it is never painted red. A lab value's "L" or "H" flag is set in ink, so on the question screen red means only the hero and the mark.
- **Type.** Newsreader carries the wordmark, screen titles, the small-caps labels ("TODAY'S REVISION"), scores and margin notes, which are set in its italic at 17 pt. SF Pro carries everything you read in the interface. Newsreader has an optical-size axis, so its small sizes stay sturdy.
- **ECG.** A pen stroke: round caps, a slight taper at both ends, and thinner where the pen moves fast (the QRS). It is the opening's own complex, 2.2x the cap height wide.
- **Marking.** A tick for right; a circled score ("72%" in a hand-drawn ring); a red margin note under the answers giving the reason ("FSGS is the commonest primary cause in Black adults. Spikes on silver stain mean membranous."). The note sits on a plain paper plate, unruled, so red text never meets the grid's red lines.

**Why it is ownable.**

- It ties together everything the app already is: the name (stetho + **score**), the A+ on the chest piece, the exam wording, and the repo's original name, red-pen.
- Nobody in the category has a warm paper ground, a serif voice or a red-ink hero ([audit.md](audit.md)). The nine competitors set their interfaces in sans-serif (Medscape uses a serif only in its editorial pages), and eight of them lead with blue, navy or teal.
- Red is already the ECG's colour, so the title's line and the opening's line become one colour without any explanation.
- Marking is a behaviour, not a decoration. Every answer gets a mark and a reason, which is the "exacting" and "on your side" traits in one gesture.

**Risks.**

- **Red for correct.** In most quiz apps red means wrong. The board guards against misreading: the tick shape, the words "Correct answer", and a wrong answer that is never red. Even so, it should be tried on a few students before it ships. This is the first open question for the owner.
- **Cards loses its red.** In round 9 (`d52aa6b6`) Cards is raspberry (`#C23048`); `design/ward-polish` has since moved it to a purple (`#9D3EB1`, at `5ba53153`, shown on `shots/ward-r12`). In A it becomes Rust, so that red means only Questions and the trace.
- **A red primary button can read as iOS's red for a destructive action** (Delete). A's primary buttons are raised with red text and a red rim, never a solid red fill, and destructive actions keep the system's own alert.
- **A teacher's red pen can feel punitive.** The words and the margin notes have to carry "on your side": every mark comes with the reason, and wrong answers stay in pencil.
- **Serif in an interface.** Newsreader is kept to the display roles: 17 pt and up (margin notes included), plus the small-caps labels at 12.5 pt with tracking. Body text, buttons and lists stay in SF Pro.
- **Fonts on the iPad build.** The owner's iPad build has no Info.plist, so `UIAppFonts` cannot register Newsreader there; see the font path under "What changes". If registration fails, the app falls back to Apple's New York serif, so the route degrades rather than breaks.
- **A and B are both paper and marking.** What keeps them apart: A is handwriting on paper (a serif, a pen, ticks and margin notes, warm paper), B is a machine reading a sheet (expanded sans, mono numbers, lozenges and timing marks, neutral paper and orange).
- **The pen stroke costs more to draw** than a plain path. Draw it as a fixed set of precomputed segments, not stroked again each frame.

**What changes in the app.**

- **Where it lands.** On `design/ward-polish`, which has the four tiers in `WardPalette` and each section's colours in `WardLook`; `personal` does not have them yet. The token names map to the code as listed in [palettes.md](palettes.md#token-names-in-the-code) (base is `.background`, ink2 is `.inkSecondary`, and so on).
- **Colour.** Replace the tokens: `.background`, `.surface`, `.raised`, `.well`, `.ink` and `.inkSecondary` in `WardPalette`; the section colours in `WardLook`; `.primary` and `.primaryInk` stop being Theatre Blue and cyan; `.ecg` and the opening's ECG colour become Trace, equal to the hero.
- **Type.** Bundle Newsreader (the TTF from google/fonts `ofl/newsreader`, with its OFL text in the acknowledgements). `UIAppFonts` works only in the Xcode build: the Swift Playgrounds build has no Info.plist (`tools/make_swiftpm.py:171` drops it). So the font goes in as a package resource in every variant (core, core1, core2 and core3: `tools/make_swiftpm.py:272-276`, which today lists only `Samples` and `Localization`, gains a `Fonts` folder), and the app registers it at launch with `CTFontManagerRegisterFontURLs` from `Bundle.module` (from `Bundle.main` in the Xcode build). No code registers fonts today. If registration fails, `WardType` falls back to New York through `.fontDesign(.serif)`. `WardType.display`, `title` and the small-caps style move to Newsreader, scaled with Dynamic Type through `UIFontMetrics`.
- **Components.** Option rows with circled letters and pen marks; a circled-score view; a margin-note view; pencil strike-through for wrong answers.
- **ECG.** `EcgSquiggle` draws the opening's complex (the `ecgHeight` function in `LaunchOpening.swift` on `design/launch-anim`) with the pen-stroke renderer.
- **`ecgLine`.** The launch stream plans a new token, one line colour for the opening's trace and the title squiggle, at `#D32F45` by day. It is planned, not yet on any pushed branch. Lines need only 3:1, so `#D32F45` would pass as a line. Route A still sets `ecgLine` to Pen Red, `#BE0222` by day and `#FF5D6D` by night, because it keeps one red for lines and text.
- **The "Best answer" chip** (`MCQQuizView.swift:607`) is tinted blue today (tone `.blue`). It becomes a Pen Red outline, and shows only on a retest ("Second try"); see [wording.md](wording.md). `ChartQuizTests.swift:31` asserts the chip's words and changes with it.
- **Wording.** As listed in [wording.md](wording.md).

## Route B: Answer Sheet

**Idea.** Every mark counts: the clean logic of an answer sheet, read by a calibrated instrument.

**On the board.**

- **Colour.** Signal Orange is the hero, the Questions hue and the Trace, on a neutral paper ground. As text it is the deep `#9A4703`. The trace, grid, frame and rims use the brighter `#C75A0C` in light mode, which is fine for graphics (3:1) but not for text. The other modes are Raspberry (Cards), Green (Textbook), Teal (Cases), Gold (OSCE), Violet (Audio) and Magenta (Ideas). Correct fills the answer's lozenge in the mode's own hue (orange in Questions); a wrong pick keeps a pencil lozenge and its text is struck through in pencil. There is no green or red: every accent follows the mode.
- **Type.** Archivo Expanded Bold for the wordmark and titles, and Archivo SemiExpanded caps for labels. IBM Plex Mono for every number and readout: "Q 01/03", "13/20 marked", timers, lab values. SF Pro for interface text.
- **ECG.** The trace starts with a calibration pulse: the square 1 mV step every ECG machine prints at the start of a strip. Then comes the opening's complex. The whole is 2.6x the cap height wide.
- **Marking.** Option letters sit in answer-sheet lozenges, filled when chosen. Progress is a row of timing marks, one per question, like the timing track on an optical answer sheet. Chips are square, in mono caps. The explanation sits in a "Mark scheme" well.

**Why it is ownable.**

- The answer sheet's lozenges and timing marks are the exam's own artefacts, and no competitor uses them.
- The calibration pulse is a detail only someone who reads ECGs recognises. It gives insider credibility and a lockup that can't be mistaken for a generic heartbeat.
- Orange is unused in the category and is the colour of instruments and signals.
- Mono numbers give scores and timers an exact, instrument-like voice: the "exacting" trait, made visible.

**Risks.**

- **Two tones of the hero.** Light mode needs the deep orange for text and the brighter one for graphics, which is one more rule to keep.
- **Warm hues crowd together.** Orange sits near Gold (OSCE) and Raspberry. They are separated in OKLCH hue, and orange is reserved for Questions. The old Wrong red sat even closer (23° from the orange); it is gone. Today's beam `#C2620B` and warning `#8F5400` were near-copies of the orange: the beam now takes the mode's hue, and a warning is pencil with a symbol.
- **Fonts on the iPad build.** As in A: Archivo and Plex Mono ship as package resources and are registered at launch; if that fails, the titles fall back to SF Pro Expanded (`.fontWidth(.expanded)`) and the numbers to SF Mono (`.monospaced()`).
- **A and B are both paper and marking.** B is the machine's side: no handwriting, no serif, no warm paper.
- **Expanded type is wide.** "Stethoscore" fits at 30 pt, but long titles at large Dynamic Type sizes must wrap or fall back to SF Pro.
- **It can read as cold and technical.** "Calm" and "on your side" then depend on the words and the explanations.
- **IBM Plex Mono has a Reserved Font Name.** Ship the files unmodified; a modified version could not be called "Plex".

**What changes in the app.**

- **Colour.** The tokens per [palettes.md](palettes.md), on `design/ward-polish` as in A, with a separate graphics tone for light Questions. The `.success` and `.danger` marking colours give way to the mode's hue and pencil.
- **Type.** Bundle Archivo (variable, with a width axis) and IBM Plex Mono, both OFL, as package resources in every Playgrounds variant and registered at launch with `CTFontManagerRegisterFontURLs`, as in A. `WardType.obs` moves from the system mono to Plex Mono.
- **Components.** Lozenge letters, the timing-mark progress, square chips, the mark-scheme well, and an indicator bar under the selected tab.
- **ECG.** The calibration pulse is added in both the title and the opening, so the two stay one shape.
- **The "Best answer" chip** (`MCQQuizView.swift:607`) is tinted blue today (tone `.blue`). It becomes a square Signal Orange outline in mono caps, and shows only on a retest ("Second try").
- **Wording.** As listed in [wording.md](wording.md).

## Route C: Steel & Silicone

**Idea.** The instrument you carry into every exam: soft silicone, bright steel, a tube in every colour.

The first board was the A and B template recoloured in plum, with steel only as grey rings round the letters. A route that is not distinct is no use to the owner, so this one was either to be rebuilt or replaced. It is rebuilt: the stethoscope is the one thing every student carries into every exam, and its two materials can carry a whole interface. Silicone is colour, soft and filled. Steel is neutral, crisp and engineered. They now decide every surface, every control, and how answers are marked.

**On the board.**

- **Silicone is the mode's hue, as a solid fill.** It is used for the primary button ("Start revision"), the chosen tab, the chosen letter, and the whole row of a correct answer. A chosen option, before it is marked, fills only its letter disc; the whole row fills only once the answer is marked correct, and its letter stays. Plum is the hero, the Questions hue and the Trace, on a rose-grey ground. The other modes are named like tubing colours: Raspberry (Cards), Hunter (Textbook), Caribbean (Cases), Mustard (OSCE), Lilac (Audio) and Orange (Ideas). Three hues sit apart on purpose: Plum at OKLCH 342°, Lilac at 298° (a violet; at 290° it read as periwinkle) and Raspberry at 20°. At 331° Plum was only 29° from Lilac, too close to tell Questions from Audio; [palettes.md](palettes.md) gives the distances.
- **Steel is neutral grey, and is never tinted blue.** It forms the bezel round every letter, as on the chest piece, the 1 pt edge of every card, the track of the progress ring, and the neutral chips.
- **Tactility follows the material.** Buttons, option rows among them, are silicone or steel-rimmed and carry the soft rim. Fields and the tab bar are flat, with a steel edge. Cards are flat steel-edged plates.
- **Correct and wrong are marked by material, not by green and red.** A correct answer fills with the mode's own hue, with its text in the card colour (7.57:1) and its letter kept. A wrong pick turns to bare steel: a neutral plate, a steel disc with a cross, and the text struck through in pencil. The words "Correct answer" and "Your answer" keep the meaning clear without colour.
- **Type.** SF Pro Rounded (an Apple system font, so nothing to bundle) is used for the wordmark, titles, labels, numbers and buttons; SF Pro for body text. The board shows Nunito ExtraBold in its place and labels each specimen that way.
- **ECG.** A tube-weight line (3 pt, round joins and caps), drawn from the opening's complex at 2.2x the cap height.

**Why it is ownable.**

- It takes the mark itself as the system. Steel and silicone are in every control, and a right answer lights up in the tube's colour. Nothing could feel more continuous with the stethoscope.
- It marks right and wrong by material, which leaves behind "the same green and red every quiz app uses" ([audit.md](audit.md), item 9).
- The rounded system face costs nothing to ship, scales fully with Dynamic Type, and matches the soft rims.
- Plum is unused in the category.

**Risks.**

- **The least distinctive type.** Many iOS apps use SF Pro Rounded, so the identity rests on colour and material.
- **Soft and rounded can feel toy-like,** against the "exacting" trait. The flat steel-edged cards and the neutral steel are there to hold it back.
- **Wrong is quiet.** Bare steel tells you less at a glance than red. The cross and the words have to do that work, and it should be tried on students.
- **Plum has no natural tie to the ECG or to marking,** so the Trace colour is a brand choice rather than a reference.
- **Plum sits between Lilac and Raspberry.** It was moved to keep them apart, but the three are still the closest trio in any route, so the frames and rims must be judged side by side on a device.
- **Ideas changes family.** It goes from magenta to Orange, because Plum takes the magenta corner. This is open question 5.
- **Solid fills need care in dark mode.** On the light Plum, text is set in the dark paper colour (6.29:1).

**What changes in the app.**

- **Colour.** The tokens per [palettes.md](palettes.md), on `design/ward-polish` as in A, plus three exactly neutral steel tokens (steel, steel2, steelPlate; their hexes are in palettes.md).
- **Type.** No font files: `.fontDesign(.rounded)` on the display, title, label, number and button styles.
- **Components.** Steel-bezelled letter discs; silicone fills for the primary button, the chosen tab and a correct answer; a steel plate for a wrong one; steel card edges; a steel-tracked progress ring; the largest radii of the three routes (28 pt cards, 24 pt rows).
- **ECG.** A 3 pt tube stroke for the opening's complex.
- **The "Best answer" chip** (`MCQQuizView.swift:607`) is tinted blue today (tone `.blue`). It becomes a Plum outline, and shows only on a retest ("Second try").
- **Wording.** As listed in [wording.md](wording.md).

## What every route shares

### Lockup

- **x** is the wordmark's cap height, and every distance is in x.
- **The mark** is 3x tall, sits 0.5x before the S, and is centred on the capitals. It is the white tube by day and the grey tube by night, used as drawn.
- **The trace** sits on the baseline, 0.3x after the e. Its R peak reaches 1x, and it is 2.2x wide (2.6x with B's pulse).
- **Clear space** is 1x on every side.
- **Smallest size:** with the mark, 24 pt type; below that, the wordmark and trace alone, never under 17 pt.
- Home's title is the wordmark and trace, which carries the brand onto home after the opening; the mark itself has just been seen in the opening, so home does not repeat it. The full lockup, with the mark, is for the opening, the App Store page and About.

### Cards, chips and the grid

- **Cards are flat:** a tonal fill and a 1 pt edge, with no blur, no glow and no lift. The soft rim is on buttons only, as the owner's rule says; an option row is an answer button, so it carries the rim too. Fields and the tab bar are flat, with a 1 pt edge, and the chosen tab is a flat tint (A, B) or a silicone fill (C). Plates (the countdown, a lab value, B's mark scheme) are flat tonal fills.
- **Chips:** a chip is ink, or the hue of the item's own mode (the question-type chip in Questions). It never borrows another mode's hue. Status shows by form: solid for act now ("Due"), an outline for a state ("New", "Weak topic"), a tint for a fact ("34 y", "Male"). A hue chip is always an outline, so its text keeps the hue's own contrast.
- **Text on the grid** clears 4.5:1 over the grid's bold lines, which WardPaper fills twice (25% of the hue by day, 20% by night). Pencil was darkened in every route to clear them. Hero text is never set on the grid. Each board prints its worst case, and [palettes.md](palettes.md) has the tables.
- **No line under the dock.** The rule that crossed the home screens above "New set" is gone.

### One Trace token

Trace equals the hero, by day and by night. It is used for the squiggle beside the name and for the opening's line (inside a mode, such as Audio's listening trace, the line takes that mode's hue), so the two are the same colour by definition. Today they differ: `wardEcg` `#BA273B` beside the name, and in the opening on `design/launch-anim` (at `202825ea`) slate `#43566F` by day and grey `#A9A8A8` by night. That slate is a stray blue. The launch stream plans to move both lines to one new `ecgLine` token, `#D32F45` by day; it is planned, not yet on any pushed branch. Whichever route is chosen, `ecgLine` takes its Trace colour.

### The marks

Both marks come from `LaunchLogo` on `design/launch-anim` at `202825ea`, used as they are: `launch-logo@3x.png`, the white tube with the blue ring, by day, and `launch-logo-dark@3x.png`, the grey tube, by night. On `personal`, and on `design/identity`, that asset path still holds the old blue tile with "LISTEN · LEARN · SCORE".

### Stray blue to remove, whichever route

- Theatre Blue as `primary`, and the cyan dark accent.
- The blue Questions hue (now the hero in every route).
- The blue tone of the "Best answer" chip (`MCQQuizView.swift:607`).
- The opening's slate trace.

The blue ring round the light mark's chest piece stays: it is part of the owner's mark.

### Fonts and licences

| Font | Used for | Licence |
|---|---|---|
| SF Pro, SF Pro Rounded | Interface text in every route; display in C | Apple system fonts, used through the system APIs and not bundled |
| Newsreader | Route A display, labels, scores, notes | SIL OFL 1.1. Copyright 2020 The Newsreader Project Authors |
| Archivo | Route B display and labels | SIL OFL 1.1. Copyright 2020 The Archivo Project Authors |
| IBM Plex Mono | Route B numbers and readouts | SIL OFL 1.1. Copyright 2017 IBM Corp., Reserved Font Name "Plex" |
| Inter, Nunito | Stand-ins on the boards only | SIL OFL 1.1. Copyright 2020 The Inter Project Authors; 2014 The Nunito Project Authors |

The OFL allows bundling these fonts in a commercial app. The licence text must ship with them (the app's acknowledgements will do), and the fonts may not be sold on their own.

## Recommendation

**Route A, Red Pen,** with one detail from B: IBM Plex Mono for readouts (timers, counters and lab values).

- A is the most ownable: it makes the name, the A+ on the mark, the exam wording and the red ECG one idea.
- It is the most different from the category: a serif interface and warm paper against nine sans-serif interfaces, eight of them blue or teal.
- Marking turns the platform into behaviour, and it gives the ECG one natural colour.

Its main risk, a red tick for a correct answer in Questions, is cheap to test and has a fallback: keep the red pen for notes, and tick correct answers in green. Green would then be the one exception to the rule that every accent follows the mode's hue, so it is the owner's call. The fallback keeps the rest of the route intact.

## Open questions for the owner

1. Route A marks a correct answer with a red tick, as an examiner does, and a wrong one in pencil. Is red for correct right for you, or should correct stay green?
2. In Route A, Cards gives up its red (it becomes Rust) so that red means only Questions and the ECG. Is that acceptable?
3. Two words in [wording.md](wording.md) clash with exam usage, so they are yours to pick. The timer's parts: "Block" is what the USMLE calls a timed section of up to 40 questions (usmle.org, Step 1), a UK placement block is weeks long, and on an ECG brand it also reads as heart block; "Part 1 of 4" or "Stint 1 of 4" avoid all three. The plan's count: the NBME calls one question an "item" (its Item-Writing Guide), so "3 items · 22 min" can read as three questions; "3 tasks" or "3 to do" avoid that. Which words do you want?
4. In Route C, the steel and silicone marking replaces green and red entirely. In Route B it now does too (orange and pencil). Is a correct answer without green right for you?
5. In Route C, Ideas changes from magenta to orange, because Plum takes the magenta corner. Is that acceptable?
