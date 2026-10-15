# Identity routes

Written 15 Oct 2026. Three routes for Stethoscore's identity, all built on the [platform](platform.md), with palettes and contrast in [palettes.md](palettes.md) and wording from [wording.md](wording.md).

The owner has the three boards; they are not in the repo because they contain the owner's mark images. Each board is an 1880 pt page rendered at 3x, with phone screens at 393 × 852 pt. Each one shows:

- the lockup and its spacing rules;
- the palette in light and dark, with the WCAG ratios printed;
- the type pairing and scale;
- the components: the primary button with its rim, chips, a card, the four states of an MCQ option and the tab bar;
- home in light and dark, with the exam wording;
- an MCQ screen;
- one key frame of the opening.

The mocks are HTML and CSS rendered in Chromium, with the real marks composited, never redrawn. Inter stands in for SF Pro (and Nunito for SF Pro Rounded in Route C), and each board says so.

| | A, Red Pen | B, Answer Sheet | C, Steel & Silicone |
|---|---|---|---|
| Idea | Revision, marked the way a good examiner marks a paper: a red pen on ECG paper. | Every mark counts: the clean logic of an answer sheet, read by a calibrated instrument. | The instrument you carry into every exam: soft silicone, bright steel, a tube in every colour. |
| Hero (and Trace) | Pen Red `#BE0222`, dark `#FF6F6C` | Signal Orange: text `#9A4703`, graphics `#C75A0C`, dark `#EF7107` | Plum `#802C6D`, dark `#E083C6` |
| Ground | Warm paper `#EAE5DD`, dark `#211D1A` | Neutral paper `#E8E8E6`, dark `#181716` | Rose-grey silicone `#EBE5E9`, dark `#242023` |
| Display type | Newsreader SemiBold, a serif | Archivo Expanded Bold, with IBM Plex Mono for numbers | SF Pro Rounded Heavy |
| ECG stroke | A pen line that tapers and thins with speed | The trace after a calibration pulse | A tube-weight line, 3 pt, round joins |
| Marking | Ticks, circled scores, margin notes | Answer-sheet lozenges, timing marks, a mark scheme | Steel discs, a ring, a "Why" box |
| Correct / wrong | Red tick / pencil, struck through | Green / red, as their own tokens | Hunter green / Raspberry |
| Shape | Pill buttons, 20 pt cards | 12 pt buttons, 14 pt cards, 4 pt chips | Pill buttons, 28 pt cards, 24 pt rows |

## Route A: Red Pen (the seed, developed)

**Idea.** Revision, marked the way a good examiner marks a paper: a red pen on ECG paper.

**On the board.**

- **Colour.** Pen Red is the hero, the Questions hue and the Trace, on a warm paper ground. The other modes become inks: Rust (Cards), Green ink (Textbook), Teal ink (Cases), Ochre (OSCE), Violet ink (Audio) and Magenta ink (Ideas). A correct answer gets the red pen's tick and the words "Correct answer". A wrong answer is struck through in pencil with "Your answer"; it is never painted red.
- **Type.** Newsreader carries the wordmark, screen titles, the small-caps labels ("TODAY'S REVISION"), scores and margin notes, which are set in its italic. SF Pro carries everything you read in the interface. Newsreader has an optical-size axis, so its small sizes stay sturdy.
- **ECG.** A pen stroke: round caps, a slight taper at both ends, and thinner where the pen moves fast (the QRS). It is the opening's own complex, 2.2x the cap height wide.
- **Marking.** A tick for right; a circled score ("72%" in a hand-drawn ring); a red margin note under the answers giving the reason ("FSGS is the commonest primary cause in Black adults. Spikes on silver stain mean membranous.").

**Why it is ownable.**

- It ties together everything the app already is: the name (stetho + **score**), the A+ on the chest piece, the exam wording, and the repo's original name, red-pen.
- Nobody in the category has a warm paper ground, a serif voice or a red-ink hero ([audit.md](audit.md)). All nine competitors are sans-serif, and eight of them lead with blue, navy or teal.
- Red is already the ECG's colour, so the title's line and the opening's line become one colour without any explanation.
- Marking is a behaviour, not a decoration. Every answer gets a mark and a reason, which is the "exacting" and "on your side" traits in one gesture.

**Risks.**

- **Red for correct.** In most quiz apps red means wrong. The board guards against misreading: the tick shape, the words "Correct answer", and a wrong answer that is never red. Even so, it should be tried on a few students before it ships. This is the first open question for the owner.
- **Cards loses its red.** Today Cards is raspberry (`#C23048`). In A it becomes Rust, so that red means only Questions and the trace.
- **A teacher's red pen can feel punitive.** The words and the margin notes have to carry "on your side": every mark comes with the reason, and wrong answers stay in pencil.
- **Serif in an interface.** Newsreader is kept to the display roles: 17 pt and up, plus the small-caps labels at 12.5 pt with tracking. Body text, buttons and lists stay in SF Pro.
- **The pen stroke costs more to draw** than a plain path. Draw it as a fixed set of precomputed segments, not stroked again each frame.

**What changes in the app.**

- **Colour.** Replace the tokens: the ground, surface, raised, well, ink and ink2 values in `WardPalette`; the section inks in `WardLook`; `primary` stops being Theatre Blue; `wardEcg` and the opening's ECG colour become Trace, equal to the hero.
- **Type.** Bundle Newsreader (the TTF from google/fonts `ofl/newsreader`, with its OFL text in the acknowledgements) and register it in `UIAppFonts`. `WardType.display`, `title` and the small-caps style move to Newsreader, scaled with Dynamic Type through `UIFontMetrics`.
- **Components.** Option rows with circle badges and pen marks; a circled-score view; a margin-note view; pencil strike-through for wrong answers.
- **ECG.** `EcgSquiggle` draws the opening's complex (the `ecgHeight` function in `LaunchOpening.swift` on `design/launch-anim`) with the pen-stroke renderer.
- **Wording.** As listed in [wording.md](wording.md).

## Route B: Answer Sheet

**Idea.** Every mark counts: the clean logic of an answer sheet, read by a calibrated instrument.

**On the board.**

- **Colour.** Signal Orange is the hero, the Questions hue and the Trace, on a neutral paper ground. As text it is the deep `#9A4703`. The trace, grid, frame and rims use the brighter `#C75A0C` in light mode, which is fine for graphics (3:1) but not for text. The other modes are Raspberry (Cards), Green (Textbook), Teal (Cases), Gold (OSCE), Violet (Audio) and Magenta (Ideas). Correct and wrong are their own green and red tokens, each clearing 4.5:1.
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
- **Warm hues crowd together.** Orange sits near Gold (OSCE) and Raspberry. They are separated in OKLCH hue, and orange is reserved for Questions.
- **Expanded type is wide.** "Stethoscore" fits at 30 pt, but long titles at large Dynamic Type sizes must wrap or fall back to SF Pro.
- **It can read as cold and technical.** "Calm" and "on your side" then depend on the words and the explanations.
- **IBM Plex Mono has a Reserved Font Name.** Ship the files unmodified; a modified version could not be called "Plex".

**What changes in the app.**

- **Colour.** The tokens per [palettes.md](palettes.md), with a separate graphics tone for light Questions, plus correct and wrong tokens.
- **Type.** Bundle Archivo (variable, with a width axis) and IBM Plex Mono, both OFL. `WardType.obs` moves from the system mono to Plex Mono.
- **Components.** Lozenge letters, the timing-mark progress, square chips, the mark-scheme well, and an indicator bar under the selected tab.
- **ECG.** The calibration pulse is added in both the title and the opening, so the two stay one shape.
- **Wording.** As listed in [wording.md](wording.md).

## Route C: Steel & Silicone

**Idea.** The instrument you carry into every exam: soft silicone, bright steel, a tube in every colour.

**On the board.**

- **Colour.** Plum is the hero, the Questions hue and the Trace, on a rose-grey silicone ground. The modes are named like tubing colours: Raspberry (Cards), Hunter (Textbook), Caribbean (Cases), Mustard (OSCE), Lilac (Audio) and Orange (Ideas). Correct borrows Hunter and wrong borrows Raspberry. Option letters sit on steel discs, echoing the chest piece.
- **Type.** SF Pro Rounded (an Apple system font, so nothing to bundle) for the wordmark, titles, labels, numbers and buttons; SF Pro for body text.
- **ECG.** A tube-weight line (3 pt, round joins and caps), drawn from the opening's complex at 2.2x the cap height.
- **Marking.** A progress ring like the chest piece's diaphragm, filled discs with a tick or a cross, and a raised "Why" box for the reason.

**Why it is ownable.**

- It takes the mark itself as the system: steel for the chrome, tube colours for the modes. Nothing could feel more continuous with the stethoscope.
- The rounded system face costs nothing to ship, scales fully with Dynamic Type, and matches the soft rims.
- Plum is unused in the category.

**Risks.**

- **The least distinctive type.** Many iOS apps use SF Pro Rounded, so the identity rests on colour and material, and could drift towards generic-friendly.
- **Soft, rounded and neumorphic together can feel toy-like,** against the "exacting" trait.
- **Plum has no natural tie to the ECG or to marking,** so the Trace colour is a brand choice rather than a reference. It also sits closer to Audio's Lilac than the other routes' heroes sit to any mode.
- **Steel discs need care in dark mode** to keep their letters at 4.5:1.

**What changes in the app.**

- **Colour.** The tokens per [palettes.md](palettes.md).
- **Type.** No font files: `.fontDesign(.rounded)` on the display, title, label, number and button styles.
- **Components.** Steel letter discs, ring progress, the "Why" box, and the largest radii of the three routes (28 pt cards, 24 pt rows).
- **ECG.** A 3 pt tube stroke for the opening's complex.
- **Wording.** As listed in [wording.md](wording.md).

## What every route shares

### Lockup

- **x** is the wordmark's cap height, and every distance is in x.
- **The mark** is 3x tall, sits 0.5x before the S, and is centred on the capitals. It is the white tube by day and the grey tube by night, used as drawn.
- **The trace** sits on the baseline, 0.3x after the e. Its R peak reaches 1x, and it is 2.2x wide (2.6x with B's pulse).
- **Clear space** is 1x on every side.
- **Smallest size:** with the mark, 24 pt type; below that, the wordmark and trace alone, never under 17 pt.
- Home's title is the wordmark and trace without the mark, because the mark has just been seen in the opening.

### One Trace token

Trace equals the hero, by day and by night. It is used for the squiggle beside the name and for the opening's line, so the two are the same colour by definition. Today they differ: `wardEcg` `#BA273B` beside the name, and slate `#43566F` / `#6584AE` in the opening on `design/launch-anim`. That slate is a stray blue.

### The marks

The light mark is `LaunchLogo` from `design/launch-anim`. On `personal`, that asset path still holds the old blue tile with "LISTEN · LEARN · SCORE".

The dark asset on `design/launch-anim` is still the slate-blue tube. The owner's rule is that dark mode always shows the grey tube (`candidates-8/06-grey-flat-dark.png`), so the dark asset should be cut from that file before any route ships. The boards use the grey tube, cut from its flat ground with no redrawing.

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
- It is the most different from the category: a serif and warm paper against nine sans-serif apps, eight of them blue or teal.
- Marking turns the platform into behaviour, and it gives the ECG one natural colour.

Its main risk, a red tick for a correct answer, is cheap to test and has a fallback: keep the red pen for marks and notes, and use a green tick. The fallback keeps the rest of the route intact.

## Open questions for the owner

1. Route A marks a correct answer with a red tick, as an examiner does, and a wrong one in pencil. Is red for correct right for you, or should correct stay green?
2. In Route A, Cards gives up its red (it becomes Rust) so that red means only Questions and the ECG. Is that acceptable?
3. The timer's new name in [wording.md](wording.md) is a "focus session" made of "blocks", in place of a "ward round" made of "rounds". Is that the right exam word for you?
