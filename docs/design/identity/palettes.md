# Identity palettes and their contrast

Written 15 Oct 2026 for the three identity routes in [routes.md](routes.md). Every number is a WCAG 2 contrast ratio, from the relative-luminance formula, measured against all four grounds of its theme:

- **base**: the ECG paper itself;
- **surface**: cards. In Routes B and C they are flat: a tonal fill and a 1 pt edge, with no blur and no glow. In Route A (round 4) they are raised neumorphic shapes on the paper;
- **raised**: buttons, including option rows (an option row is an answer button), the only things that carry the soft rim; fields and the tab bar sit on this tone too, but flat, with a 1 pt edge and no rim. In Route A every control is a raised shape (a light shadow up-left, a dark one down-right) with a crisp 1 pt edge, and chosen or pressed controls are inset;
- **well**: flat plates (the lab value, the countdown, B's mark scheme) and pressed controls.

Each range below is the lowest and highest ratio across those four grounds, so the first number is the worst case. The bar is WCAG AA: 4.5:1 for body text, 3:1 for large text (18 pt, or 14 pt bold, as WCAG defines it) and for icons and other graphics. Every text colour here clears 4.5:1 on all four grounds; the light mode hues were fitted to at least 4.6:1 and the dark ones to at least 5.0:1, so each one can carry body text, not only icons. One exception to the 5.0 margin: Route A's dark Pen Red is fitted to 4.55:1, so that it can be a vivid crimson rather than a light coral.

Text set straight on the grid is also measured over the grid's bold lines, the ground with the least contrast that it can meet (see "On the grid" under each route).

The colours are fitted in OKLCH, a colour space that keeps lightness, chroma (how colourful a colour is) and hue angle apart, so a hue can be made darker or lighter without drifting. The sRGB gamut is the set of colours a phone screen can show.

Each mode keeps its own hue for its grid, frame and button rims, and every accent inside a mode (button text, icons, links, the correct mark, the progress beam) follows that hue. In every route the hero is the Questions hue, and the ECG trace, beside the name and in the opening, is drawn in the hero: one token, Trace, equal to the hero in both themes. Inside a mode the trace takes that mode's hue: the listening trace in Audio is drawn in Audio's hue. There are no exceptions left: a correct answer is marked in the mode's own hue in every route, and a wrong one is neutral (pencil in A and B, steel in C).

## Route A, Red Pen (hero: Pen Red)

### Grounds and inks

| Token | Light | Dark | Use |
|---|---|---|---|
| base | `#F1EEE9` | `#252C34` | The paper: page background and grid ground |
| surface | `#F3F0EB` | `#272D36` | Cards (raised), same tone as raised |
| raised | `#F3F0EB` | `#272D36` | Buttons, option rows, fields, the tab bar, segments and toggles (raised) |
| well | `#EEEBE5` | `#1F252D` | Inset: chosen, pressed or typed-into controls; flat plates |
| ink | `#1E1814` | `#EDF0F6` | Body text and titles |
| ink2 | `#4D4640` | `#B8BEC7` | Secondary text (pencil) |
| fade | `#6C6963` | `#8E959D` | Wrong answers: faded grey text, struck through, with a small cross (static, not a transition) |
| light shadow | `#FFFFFF` | `#39424D` | The shadow toward the top-left, the same light source everywhere |
| dark shadow | `#B4B1A9` | `#0D131C` | The shadow toward the bottom-right |
| edge | `#6B6861` | `#9399A0` | The crisp 1 pt control boundary |
| onFill | `#120E0C` | `#0F131C` | Text on a bright mode fill |

Shadows are drawn as a pair: light `-4px -4px 9px` and dark `4px 4px 10px` for buttons, fields and the tab bar (`-6px -6px 14px` and `6px 6px 16px` for cards); an inset shape reverses them (`inset 3px 3px 6px` dark, `inset -3px -3px 6px` light). The ground is OKLCH L 0.95, chroma 0.007 by day and L 0.29, chroma 0.018 (a cool slate, not near-black) by night. The light shadow is `#FFFFFF`/`#39424D` and the dark one `#B4B1A9`/`#0D131C` (day/night).

Shadows alone never reach 3:1, so every control has a crisp 1 pt edge. The edge is `#6B6861` by day (4.67 to 4.89 on the four grounds) and `#9399A0` by night (4.82 to 5.37), fitted to at least 3.15:1 against the grounds, the grid's bold lines and the shadowed ground beside it. A chosen control uses its mode's text variant as the edge. Shading never covers content: text and icons sit on top at full opacity.

### Text on the four grounds

| Text colour | Light | Ratio, light | Dark | Ratio, dark |
|---|---|---|---|---|
| Ink | `#1E1814` | 14.76 to 15.45 | `#EDF0F6` | 12.14 to 13.52 |
| Pencil (secondary) | `#4D4640` | 7.79 to 8.15 | `#B8BEC7` | 7.41 to 8.25 |
| Faded (wrong answers) | `#6C6963` | 4.60 to 4.81 | `#8E959D` | 4.58 to 5.10 |
| Questions, Pen Red (hero), text variant | `#CF1833` | 4.61 to 4.82 | `#FE8A88` | 6.08 to 6.76 |
| Cards, Sky, text variant | `#016DAD` | 4.65 to 4.87 | `#63B9FE` | 6.54 to 7.28 |
| Textbook, Green ink, text variant | `#037936` | 4.65 to 4.87 | `#56D57B` | 7.39 to 8.23 |
| Cases, Teal ink, text variant | `#067576` | 4.63 to 4.84 | `#3BCFCF` | 7.27 to 8.09 |
| OSCE, Marigold, text variant | `#836503` | 4.61 to 4.83 | `#EFBD24` | 7.90 to 8.80 |
| Audio, Violet ink, text variant | `#834BCB` | 4.60 to 4.82 | `#BF9BFE` | 6.16 to 6.86 |
| Ideas, Magenta ink, text variant | `#BA2B8B` | 4.64 to 4.85 | `#FF7CCB` | 5.94 to 6.61 |
| Correct (the mode's own hue; Questions shown) | `#CF1833` | 4.61 to 4.82 | `#FE8A88` | 6.08 to 6.76 |
| Wrong (faded grey, struck through, with a cross) | `#6C6963` | 4.60 to 4.81 | `#8E959D` | 4.58 to 5.10 |


### Fills, icons and the Trace

Each mode has a bright fill (light L 0.62 to 0.74, chroma up to 0.21; night L 0.76 to 0.82) beside its text variant above. The fill is the brightest tone in that band that still reaches 3:1 as an icon on all four grounds; where none does (Textbook, Cases by day), icons use the text variant. Ratios of the fill against the four grounds, and of near-black text (`#120E0C` by day, `#0F131C` by night) on the fill:

| Mode | OKLCH hue | Fill, light | Ratio, light | On fill | Fill, dark | Ratio, dark | On fill |
|---|---|---|---|---|---|---|---|
| Questions, Pen Red | 22° | `#F1424E` | 3.14 to 3.28 | 5.15 | `#FE8A88` | 6.08 to 6.76 | 8.14 |
| Cards, Sky | 245° | `#168DD9` | 3.02 to 3.16 | 5.34 | `#63B9FE` | 6.54 to 7.28 | 8.76 |
| Textbook, Green ink | 150° | `#03A14A` | 2.85 to 2.98 | 5.67 | `#56D57B` | 7.39 to 8.23 | 9.91 |
| Cases, Teal ink | 195° | `#0C9999` | 2.93 to 3.06 | 5.51 | `#3BCFCF` | 7.27 to 8.09 | 9.74 |
| OSCE, Marigold | 87° | `#A68003` | 3.09 to 3.24 | 5.22 | `#EFBD24` | 7.90 to 8.80 | 10.59 |
| Audio, Violet ink | 300° | `#A06AEC` | 3.06 to 3.20 | 5.27 | `#BF9BFE` | 6.16 to 6.86 | 8.26 |
| Ideas, Magenta ink | 345° | `#DB4DA7` | 3.13 to 3.28 | 5.15 | `#FF7CCB` | 5.94 to 6.61 | 7.96 |

Cards is the new Sky blue, 245°. The closest pair of modes is questions and ideas, 37° apart; Cards is at least 45° from every other mode. The Trace (beside the name and in the opening) is the Questions fill, `#F1424E` by day and `#FE8A88` by night.

### On the grid

WardPaper fills every line with the fine ink and fills a bold line a second time with the bold ink, so a bold line carries 25% of the mode hue by day (9% then 18%) and 20% by night (7% then 14%). The worst case below is text over the bold line that gives it the least contrast among the seven modes: the darkest line by day, the lightest by night.

| Text | Light: worst bold line | Ratio | Dark: worst bold line | Ratio |
|---|---|---|---|---|
| Ink | `#F1C2C2` (Questions) | 11.07 | `#4D4931` (OSCE) | 7.95 |
| Pencil | `#F1C2C2` (Questions) | 5.84 | `#4D4931` (OSCE) | 4.85 |

Pencil was darkened so that it clears 4.5:1 over every bold line; it stays well apart from ink. Hero text is never set on the grid. The margin note sits on a plain paper plate, unruled, so Pen Red keeps its 4.74:1 on paper. Where two bold lines cross, a 1 pt dot is darker still; the ratios are measured over the line, as the review asked.

### Chips

A chip is ink, or the hue of the item's own mode (the question-type chip in Questions); it never borrows another mode's hue. Status shows by form: solid for act now ("Due"), an outline for a state ("New", "Weak topic"), a tint for a fact ("34 y"). A hue chip is always an outline, never a tint, so its text keeps the hue's own ratios above (on a card: 4.82 light, 6.08 dark). Tints and solid fills are neutral: ink on the well tint 14.76 (light) and 13.52 (dark); the card colour on solid ink 15.45 (light) and 12.14 (dark).

Pen Red is now a bright pen red: the fill and Trace are `#F1424E` by day and `#FE8A88` by night, and its text variant is `#CF1833` / `#FE8A88`. The brief's ECG Red `#D32F45` is 4.26:1 on paper and 4.14:1 in wells, under the 4.5:1 that text needs, so text uses the variant.

The launch stream plans a new `ecgLine` token, one line colour for the opening's trace and the title squiggle, at `#D32F45` by day. It is planned, not yet on any pushed branch. Route A sets `ecgLine` to the Pen Red fill, `#F1424E` by day (3.22:1 on paper, above the 3:1 a line needs) and `#FE8A88` by night.

Marking, as the owner asked on 15 Oct 2026: a correct answer takes the active mode's hue, as a tick and a fill, with its text in the mode's text variant (at least 4.5:1); a wrong answer is faded, statically: muted grey text (`#6C6963` by day, `#8E959D` by night, at least 4.5:1 on its ground), struck through, with a small cross. There is no green, and no red unless red is the mode's own hue (Questions). Faded is drawn with a colour, never with opacity, so its contrast is the one printed.

## Route B, Answer Sheet (hero: Signal Orange)

### Grounds and inks

| Token | Light | Dark | Use |
|---|---|---|---|
| base | `#E8E8E6` | `#181716` | The paper: page background and grid ground |
| surface | `#F5F4F3` | `#201F1E` | Cards (flat) |
| raised | `#F9F9F8` | `#272725` | Buttons and option rows (with the rim); fields and the tab bar (flat) |
| well | `#DBDBD8` | `#11100F` | Flat plates and pressed controls |
| ink | `#1B1B19` | `#F0F0EF` | Body text and titles |
| ink2 | `#4C4C49` | `#B6B6B3` | Secondary text (pencil) |
| shade | `#A6A5A0` | black at 60% | Tint of the lower-right rim shadow |

### Text on the four grounds

| Text colour | Light | Ratio, light | Dark | Ratio, dark |
|---|---|---|---|---|
| Ink | `#1B1B19` | 12.43 to 16.37 | `#F0F0EF` | 13.12 to 16.67 |
| Pencil (secondary) | `#4C4C49` | 6.21 to 8.18 | `#B6B6B3` | 7.36 to 9.35 |
| Questions, Signal Orange (hero) | `#9A4703` | 4.62 to 6.08 | `#EF7107` | 5.01 to 6.37 |
| Cards, Raspberry | `#B8194C` | 4.61 to 6.07 | `#FA5F81` | 5.00 to 6.35 |
| Textbook, Green | `#046E31` | 4.61 to 6.08 | `#3BA95D` | 5.00 to 6.35 |
| Cases, Teal | `#066A6B` | 4.61 to 6.07 | `#04A7A7` | 5.05 to 6.42 |
| OSCE, Gold | `#6C5F02` | 4.62 to 6.09 | `#A99605` | 5.03 to 6.38 |
| Audio, Violet | `#7642B9` | 4.66 to 6.13 | `#AE7DF9` | 5.06 to 6.43 |
| Ideas, Magenta | `#A32D85` | 4.63 to 6.09 | `#E369BF` | 5.02 to 6.37 |
| Correct (the mode's own hue; Questions shown) | `#9A4703` | 4.62 to 6.08 | `#EF7107` | 5.01 to 6.37 |
| Wrong (pencil, struck through) | `#4C4C49` | 6.21 to 8.18 | `#B6B6B3` | 7.36 to 9.35 |

### On the grid

WardPaper fills every line with the fine ink and fills a bold line a second time with the bold ink, so a bold line carries 25% of the mode hue by day (9% then 18%) and 20% by night (7% then 14%). The worst case below is text over the bold line that gives it the least contrast among the seven modes: the darkest line by day, the lightest by night.

| Text | Light: worst bold line | Ratio | Dark: worst bold line | Ratio |
|---|---|---|---|---|
| Ink | `#DCB3BF` (Cards) | 9.24 | `#353013` (OSCE) | 11.63 |
| Pencil | `#DCB3BF` (Cards) | 4.61 | `#353013` (OSCE) | 6.52 |

Pencil was darkened so that it clears 4.5:1 over every bold line; it stays well apart from ink. Hero text is never set on the grid; it sits on cards, controls or plates. Where two bold lines cross, a 1 pt dot is darker still; the ratios are measured over the line, as the review asked.

### Chips

A chip is ink, or the hue of the item's own mode (the question-type chip in Questions); it never borrows another mode's hue. Status shows by form: solid for act now ("Due"), an outline for a state ("New", "Weak topic"), a tint for a fact ("34 y"). A hue chip is always an outline, never a tint, so its text keeps the hue's own ratios above (on a card: 5.83 light, 5.51 dark). Tints and solid fills are neutral: ink on the well tint 12.43 (light) and 16.67 (dark); the card colour on solid ink 15.70 (light) and 14.43 (dark).

Signal Orange as text is the deep `#9A4703`; on light grounds the trace, grid, frame and rims use the brighter graphics tone `#C75A0C` (3.09 to 4.07, above the 3:1 bar for graphics), never for text.

Correct and wrong have no tokens of their own any more. A correct answer fills its lozenge in the mode's own hue (orange in Questions); a wrong pick keeps a pencil lozenge and its text is struck through in pencil. This removes the old Wrong red, which sat 23° from the orange hero. The progress beam takes the mode's hue, and a warning is pencil with a warning symbol, so neither is a near-copy of the orange (today's beam `#C2620B` and warning `#8F5400` were ΔE 0.019 and 0.036 from it).

## Route C, Steel & Silicone (hero: Plum)

### Grounds and inks

| Token | Light | Dark | Use |
|---|---|---|---|
| base | `#EBE5E9` | `#242023` | The paper: page background and grid ground |
| surface | `#F6F2F4` | `#2E292D` | Cards (flat) |
| raised | `#FAF7F9` | `#353135` | Buttons and option rows (with the rim); fields and the tab bar (flat) |
| well | `#DED8DC` | `#1C191C` | Flat plates and pressed controls |
| ink | `#221A21` | `#F1EDF0` | Body text and titles |
| ink2 | `#524851` | `#BDB5BA` | Secondary text (pencil) |
| shade | `#A69AA4` | black at 60% | Tint of the lower-right rim shadow |

### Text on the four grounds

| Text colour | Light | Ratio, light | Dark | Ratio, dark |
|---|---|---|---|---|
| Ink | `#221A21` | 12.09 to 15.95 | `#F1EDF0` | 11.03 to 15.03 |
| Pencil (secondary) | `#524851` | 6.22 to 8.21 | `#BDB5BA` | 6.38 to 8.70 |
| Questions, Plum (hero) | `#86266A` | 5.99 to 7.90 | `#E77FC2` | 5.00 to 6.81 |
| Cards, Raspberry | `#B02A39` | 4.62 to 6.10 | `#FF787D` | 5.01 to 6.83 |
| Textbook, Hunter | `#146C33` | 4.64 to 6.12 | `#62B375` | 5.01 to 6.82 |
| Cases, Caribbean | `#03696A` | 4.63 to 6.11 | `#2DB4B4` | 5.05 to 6.89 |
| OSCE, Mustard | `#6F5C02` | 4.66 to 6.15 | `#B9A13E` | 5.01 to 6.83 |
| Audio, Lilac | `#6F4AAB` | 4.61 to 6.09 | `#B290F8` | 5.02 to 6.84 |
| Ideas, Orange | `#944A00` | 4.62 to 6.09 | `#ED8A3D` | 5.06 to 6.89 |
| Correct (the mode's own hue; Questions shown) | `#86266A` | 5.99 to 7.90 | `#E77FC2` | 5.00 to 6.81 |
| Wrong (steel) | `#5E5E5E` | 4.62 to 6.09 | `#A2A2A2` | 5.01 to 6.83 |

### On the grid

WardPaper fills every line with the fine ink and fills a bold line a second time with the bold ink, so a bold line carries 25% of the mode hue by day (9% then 18%) and 20% by night (7% then 14%). The worst case below is text over the bold line that gives it the least contrast among the seven modes: the darkest line by day, the lightest by night.

| Text | Light: worst bold line | Ratio | Dark: worst bold line | Ratio |
|---|---|---|---|---|
| Ink | `#D1B5C9` (Questions) | 9.02 | `#423A28` (OSCE) | 9.70 |
| Pencil | `#D1B5C9` (Questions) | 4.64 | `#423A28` (OSCE) | 5.61 |

Pencil was darkened so that it clears 4.5:1 over every bold line; it stays well apart from ink. Hero text is never set on the grid; it sits on cards, controls or plates. Where two bold lines cross, a 1 pt dot is darker still; the ratios are measured over the line, as the review asked.

### Chips

A chip is ink, or the hue of the item's own mode (the question-type chip in Questions); it never borrows another mode's hue. Status shows by form: solid for act now ("Due"), an outline for a state ("New", "Weak topic"), a tint for a fact ("34 y"). A hue chip is always an outline, never a tint, so its text keeps the hue's own ratios above (on a card: 7.57 light, 5.58 dark). Tints and solid fills are neutral: ink on steel 13.24 (light) and 8.69 (dark); the card colour on solid ink 15.29 (light) and 12.31 (dark).

Correct and wrong are marked by material, not by green and red. A correct answer fills its row with the mode's own hue, the silicone: Plum here, with its text in the card colour (7.57:1) by day and in the paper colour (6.29:1) by night. A wrong answer turns its row to bare steel, a neutral plate with a steel disc (darker by day, so its white letter clears 4.5:1) and a pencil cross, its text struck through in pencil. Steel is exactly neutral grey (OKLCH chroma 0), so it never reads as blue; the steel text token above is for marks on the card. A chosen option, before it is marked, shows only a filled letter disc; the whole row fills only once it is marked correct.

Steel tokens:

| Token | Light | Dark | Use |
|---|---|---|---|
| steel | `#CACACA` | `#929292` | Letter bezels, the progress track; the card edge by day |
| steel2 | `#868686` | `#636363` | Hairline on a wrong row; the card edge by night |
| steelDisc | `#696969` | `#636363` | The letter disc on a wrong row, with white (5.49:1) by day and the ink by night |
| steelPlate | `#E4E3E4` | `#444144` | A wrong row; the neutral chip tint |

On the steel plate: ink 13.26 (light) and 8.69 (dark); pencil 6.82 (light) and 5.03 (dark).

In the second review Plum (331°) sat only 29° from Lilac (302°), ΔE 0.094 by day and 0.076 by night: the closest hero-to-mode pair in any route, so Questions and Audio would have looked alike. (ΔE is the straight-line distance between two colours in OKLCH; the larger it is, the easier two colours are to tell apart.) Three hues move: Plum from 331° to 342°, Lilac from 302° to 298°, and Raspberry from 14° to 20°. Plum to Lilac is now ΔE 0.124 by day and 0.114 by night, and Plum to Raspberry 0.123 and 0.102, in line with A's closest pair (Pen Red to Rust, 0.319 and 0.252).

## Changes after the first review (15 Oct 2026)

- Pencil (light) darkened to clear 4.5:1 over the grid's bold lines: A `#5D554E` to `#4D4640`, B `#5A5957` to `#4C4C49`, C `#625760` to `#524851`.
- Route A, dark Pen Red: `#FF6F6C` (coral) to a crimson, since replaced by the third review.
- Route C: Lilac `#624FAA` / `#A595F7` to `#6F4AAB` / `#B290F8`; Plum `#802C6D` / `#E083C6` to `#86266A` / `#E77FC2`; Raspberry `#AF294E` / `#FF7690` to `#B02A39` / `#FF787D`; correct is now the mode's own hue and wrong is steel, in place of Hunter green and Raspberry.
- Every route (before the third review changed Route A): cards are flat; chips follow the chip rule above; the grid worst cases and chip ratios are printed.

## Changes after the second review (15 Oct 2026)

- Route A: correct is ticked in the mode's own ink, not in Pen Red in every mode.
- Route B: the Correct green and Wrong red tokens are gone; correct is the mode's hue, wrong is pencil. The beam follows the mode's hue and a warning is pencil with a symbol.
- Route C: Plum `#7E2A78` / `#DD83D3` to `#86266A` / `#E77FC2` (331° to 342°); Lilac `#7348A8` / `#B88EF4` to `#6F4AAB` / `#B290F8` (302° to 298°); Raspberry `#B02946` / `#FF7789` to `#B02A39` / `#FF787D` (14° to 20°). Steel is now exactly neutral (chroma 0), so the wrong token is `#5E5E5E` / `#A2A2A2`.

## Changes after the third review (15 Oct 2026)

- Route A, redone from the owner's answers: neumorphism is back (raised cards, buttons, fields, tab bar, segments and toggles; inset when chosen), with a crisp 1 pt edge on every control; a brighter, happier palette on a light ground (`#F1EEE9`) and a soft slate ground by night (`#252C34`); Cards moves from Rust to Sky blue `#168DD9` / `#63B9FE` (text variant `#016DAD` / `#63B9FE`); Ideas stays magenta; a correct answer takes the active mode's hue and a wrong one is faded grey.
- Routes B and C are unchanged.

- Routes B and C: the soft rim is on buttons only (option rows count as answer buttons); fields and the tab bar are flat. The boards now show this, with the marking in B, the moved hues in C and neutral steel.

## Token names in the code

The routes land on `design/ward-polish`, where `WardPalette` has the four tiers and `WardLook` has each section's colours. The names here map to the code like this:

| Here | In the code | What each route sets it to |
|---|---|---|
| base, surface, raised, well | `.background`, `.surface`, `.raised`, `.well` | The grounds above |
| ink, ink2 (pencil) | `.ink`, `.inkSecondary` | The inks above |
| hero | `.primary`, `.primaryInk` | The Questions hue; in B by day `.primary` is the graphics tone `#C75A0C` and `.primaryInk` the text tone `#9A4703` |
| Trace | `.ecg`, and the planned `ecgLine` | The hero |
| mode hues | `WardSectionColours` (ink, accent, fill) in `WardLook` | The mode hues above; Questions is the hero |
| correct | `.success` | The mode's own hue (Questions shown in the tables) |
| wrong | `.danger`, when used for marking | Faded grey (A), pencil (B) or steel (C), struck through |
| danger | `.danger`, for destructive actions | Not a marking colour. A Delete button is ink with a trash symbol; iOS alerts and menus keep their own destructive red |
| warning | `.warning` | Pencil with a warning symbol |
| beam | `.beam` | The mode's hue |
| hairline | `.hairline` | A `#D5D2CD` / `#474C55`; B `#D6D6D4` / `#41403F`; C steel `#CACACA` / steel2 `#636363` |
| monitor | `.monitor` | The route's dark well in both themes: A `#1F252D`, B `#11100F`, C `#1C191C` |
| onPrimary | `.onPrimary` | Text on a solid hue fill: the card colour by day, the paper colour by night. On the hero: A 4.82 / 6.18; B 5.83 / 6.00; C 7.57 / 6.29 |
| steel, steel2, steelPlate | new, Route C only | See Route C |

## How the colours were fitted

Each mode hue is set at a chosen hue angle and pushed to the most vivid chroma that still meets the target on all four grounds, searching lightness in OKLCH and clipping to the sRGB gamut by lowering chroma. Light hues aim at 4.6:1 and dark hues at 5.0:1, a small margin over 4.5:1 for rounding and rendering. None of the heroes is blue, and the Questions hue, the one that used to be blue, is now the hero in every route.

The hue angles are not all today's. Against round 9 (`d52aa6b6`, `WardLook.swift:18-24`) and today's `design/ward-polish` (`5ba53153`, `WardLook.swift:66-71`), measured on the light inks, these modes move by more than 10°:

| Route | Mode | Round 9 | Route | Change from round 9 | Change from ward-polish |
|---|---|---|---|---|---|
| A | Cards, Sky | `#C23048` (17°) | `#016DAD` (245°) | -132° | -75° |
| A | Cases, Teal ink | `#0D7C8C` (211°) | `#067576` (196°) | -15° | -88° |
| A | OSCE, Marigold | `#8F6200` (77°) | `#836503` (88°) | +11° | -4° |
| B | Cases, Teal | `#0D7C8C` (211°) | `#066A6B` (196°) | -15° | -88° |
| B | OSCE, Gold | `#8F6200` (77°) | `#6C5F02` (100°) | +23° | +8° |
| C | Cases, Caribbean | `#0D7C8C` (211°) | `#03696A` (196°) | -15° | -88° |
| C | OSCE, Mustard | `#8F6200` (77°) | `#6F5C02` (95°) | +17° | +3° |
| C | Ideas, Orange | `#A8327E` (345°) | `#944A00` (55°) | +70° | +75° |

Two of these are changes of colour family, not tuning, and are the owner's to accept: Route A's Cards goes from raspberry to the bright Sky blue (the owner rejected Rust on 15 Oct 2026; open question 2 in routes.md); Route C's Ideas goes from magenta to Orange, because C's Plum hero takes the magenta corner (open question 5). Against `design/ward-polish` the moves are larger, because that branch has already moved Cards to a purple (`#9D3EB1`) and Cases to a blue-violet (`#6656D7`); every route takes Cases back to teal, which also removes a near-blue.
