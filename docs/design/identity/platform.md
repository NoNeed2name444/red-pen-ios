# Brand platform

Written 15 Oct 2026. This is what the identity stands on, whichever route the owner picks ([routes.md](routes.md)). The audit behind it is in [audit.md](audit.md), and the words follow [wording.md](wording.md).

## The idea in one line

**Stethoscore listens to how you revise and tells you, exactly and kindly, where you stand before the exam.**

The name already says it: a stethoscope listens for what is wrong, and a score says where you stand. The A+ on the chest piece is the promise, and the pass mark is the line that matters.

## Three traits

### 1. Exacting

The app is as exact as a mark scheme. Every mark has a reason, and every number means something.

- **UI.** Spacing follows a 4 and 8 pt scale (`WardSpace`). The ECG paper is a separate grid: 6 pt cells with a bold line every 30 pt (`WardRelief.swift:244-245`), like the 1 mm and 5 mm squares of real ECG paper. Numbers use tabular figures (every digit the same width, so columns and timers do not jitter), and scores are shown as numbers ("18 of 25 · 72%"), not as vague bars. Each answer is marked with its reason beside it (a margin note, a mark scheme or a "Why" box, depending on the route). Nothing is there only to decorate.
- **Motion.** The ECG trace draws at a constant paper speed, with no bounce and no overshoot. A mark lands as one short, decisive stroke: a trim (the stroke drawing itself from start to end) of 120 to 180 ms. As the owner set, nothing fades: motion is position, scale, trims, masks (a shape revealing what is under it) and morphs (one shape turning into another).
- **Sound.** Short, dry and tuned: a soft click to select, a quiet two-note tone for a correct answer. No fanfare. Sound follows the silent switch, and haptics do most of the work.
- **Words.** Exam vocabulary used exactly: question, paper, station, mark scheme, score, pass mark, weak topics, results (the end of a paper), progress (the screen that tracks you). A number comes before any adjective. Each thing has one name.

### 2. Calm

Revision is stressful enough. The app is the steady rhythm in the room, not the alarm.

- **UI.** Warm paper, one hero colour, and room to breathe. Each screen has one primary action. A wrong answer is never painted in alarm red across the screen: it gets a mark, a word and the reason.
- **Motion.** Slow enough to read: 200 to 320 ms with an ease-out (fast at the start, settling gently). The opening is brief and never holds the app back. Nothing loops on screen, except the trace while the app is listening (Audio).
- **Sound.** Quiet by default. A light haptic in place of a sound wherever possible. No sound at all for a lost streak.
- **Words.** Short, plain sentences. No exclamation marks, no countdown panic, no hype ("crush", "ace", "magic").

### 3. On your side

The good examiner wants you to pass, and says exactly what would get you there.

- **UI.** Home starts with Today's revision, not with a search field. Weak topics appear as the next thing to do, not as a failure list. You are compared only with the pass mark and with yourself, never with other students: no ranks, levels, XP, badges, leaderboards or challenge-a-friend.
- **Motion.** A correct mark lands with a little more weight (a scale from 0.96 to 1 under the tick's trim) than a wrong one (the cross's trim alone). Progress only moves forward; nothing drains away.
- **Sound.** A correct answer sounds warm. A wrong answer is silent or a muted tap, never a buzzer.
- **Words.** Second person, honest and kind: "below the pass mark for now", "Renal, the weakest, is in today's revision automatically", "All 4 sat. Well done." Explain; don't scold.

## The audience

Medical students in the years before finals and licensing exams, preparing for written papers (single best answer), OSCE stations and vivas. They revise on iPhone in bursts of 5 to 25 minutes, between lectures, placements and sleep, and on iPad at a desk. Many revise late, so dark mode matters as much as light. Junior doctors sitting postgraduate or licensing exams are a second group.

They already know the clinical words, so the app does not need to dress up as a hospital to feel medical. What they want from it is:

- trust that the content is right;
- a clear next step;
- an honest answer to "where do I stand?".

## What it must never feel like

- A hospital role-play: wards, beds, pagers, admissions. The ward is the subject matter, not the setting.
- A game: XP, levels, ranks, badges, leaderboards, confetti, streak-shaming, challenge-a-friend.
- A comparison with other students: no peer histograms and no "top 10%".
- A generic blue health app, or hospital IT.
- A cartoon: mascots, brains with faces.
- An alarm: flashing red, buzzers, countdown panic.
- Glassy, faded UI: no fades or blurs. The neumorphic rim on buttons is the only soft effect.
- Hype: "Crush your exams", "Works like magic".

## What does not change, whichever route

- **The name:** Stethoscore.
- **The mark:** the stethoscope with the A+ on its chest piece, used exactly as drawn. By day it is the white tube with the blue ring round the chest piece; by night it is always the grey tube. The two drawings are shown as they are.
- **The paper:** the ECG grid, a fine line every 6 pt and a bold one every 30 pt, as on ECG paper, drawn in the mode's hue.
- **The rims:** the soft neumorphic rim on buttons only (an option row is an answer button, so it has one), with the light from the top left and a 1 pt edge in the mode's hue. Fields and the tab bar are flat, with a 1 pt edge and no rim.
- **The mode hues:** each mode (Questions, Cards, Textbook, Cases, OSCE, Audio, Ideas) keeps its own hue for its grid, frame and rims. Within a mode, every accent follows that hue, the correct mark included; a wrong answer is neutral. The hues are retuned per route as one family around the hero ([palettes.md](palettes.md)). None of the heroes is blue.

## The ECG line: its role and its colour

The ECG trace is the brand's signature line. It is one complex (P wave, QRS, T wave) taken from the opening's own trace, not a separate icon.

- **Where it appears:** beside the name in the lockup and on home's title; in the opening; as the listening state in Audio, where it takes Audio's hue like every accent in that mode; and on Progress, as the study-rhythm reading. It does not appear on every card. A signature used everywhere stops being one.
- **How it is drawn:** detailed, with a real P wave, a sharp QRS and a rounded T wave. It sits on the text baseline, and its R peak reaches the cap height. Each route sets the stroke (a tapered pen line, a calibrated pulse, or a weighty tube), but the shape is always the opening's.
- **Its colour:** one token, Trace, equal to the hero, used for both the title and the opening, by day and by night. The title's line and the opening's line are then the same colour by definition, which is what the owner asked for. Today they differ: the squiggle beside the name is `wardEcg` (`#BA273B`), while the opening's line on `design/launch-anim` (at `202825ea`) is slate `#43566F` by day and grey `#A9A8A8` by night. That slate is the old slate tube's colour and another stray blue. The launch stream plans to move both lines to one new `ecgLine` token (`#D32F45` by day); it is planned, not yet on any pushed branch, and it should take the chosen route's Trace colour. On that branch the opening's ECG already travels up and lands as the title's squiggle, so one shape and one colour carry the whole journey.
