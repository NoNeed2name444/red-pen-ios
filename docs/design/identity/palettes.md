# Identity palettes and their contrast

Written 15 Oct 2026 for the three identity routes in [routes.md](routes.md). Every number is a WCAG 2 contrast ratio, from the relative-luminance formula, measured against all four grounds of its theme:

- **base**: the ECG paper itself;
- **surface**: cards, which are flat: a tonal fill and a 1 pt edge, with no blur and no glow;
- **raised**: buttons, fields and option rows, the only things that carry the soft rim;
- **well**: flat plates (the lab value, the countdown, B's mark scheme) and pressed controls.

Each range below is the lowest and highest ratio across those four grounds, so the first number is the worst case. The bar is WCAG AA: 4.5:1 for body text, 3:1 for large text (20 pt, or 14 pt bold) and for icons and other graphics. Every text colour here clears 4.5:1 on all four grounds; the light mode hues were fitted to at least 4.6:1 and the dark ones to at least 5.0:1, so each one can carry body text, not only icons. One exception to the 5.0 margin: Route A's dark Pen Red is fitted to 4.55:1, so that it can be a vivid crimson rather than a light coral.

Text set straight on the grid is also measured over the grid's bold lines, the darkest ground it can meet (see "On the grid" under each route).

Each mode keeps its own hue for its grid, frame and button rims, and every accent inside a mode (button text, icons, links) follows that hue. In every route the hero is the Questions hue, and the ECG trace, beside the name and in the opening, is drawn in the hero: one token, Trace, equal to the hero in both themes.

## Route A, Red Pen (hero: Pen Red)

### Grounds and inks

| Token | Light | Dark | Use |
|---|---|---|---|
| base | `#EAE5DD` | `#211D1A` | The paper: page background and grid ground |
| surface | `#F5F2ED` | `#2A2623` | Cards (flat) |
| raised | `#F9F7F3` | `#322D29` | Buttons, fields, option rows |
| well | `#DED8CF` | `#1A1614` | Flat plates and pressed controls |
| ink | `#1E1814` | `#F0ECE5` | Body text and titles |
| ink2 | `#4E463F` | `#BBB5AC` | Secondary text (pencil) |
| shade | `#A99C8E` | black at 60% | Tint of the lower-right rim shadow |

### Text on the four grounds

| Text colour | Light | Ratio, light | Dark | Ratio, dark |
|---|---|---|---|---|
| Ink | `#1E1814` | 12.40 to 16.41 | `#F0ECE5` | 11.56 to 15.26 |
| Pencil (secondary) | `#4E463F` | 6.53 to 8.64 | `#BBB5AC` | 6.69 to 8.83 |
| Questions, Pen Red (hero) | `#BE0222` | 4.60 to 6.09 | `#FF5D6D` | 4.56 to 6.02 |
| Cards, Rust | `#934A03` | 4.60 to 6.09 | `#EB8229` | 5.03 to 6.64 |
| Textbook, Green ink | `#006C2F` | 4.65 to 6.16 | `#4DB068` | 5.01 to 6.61 |
| Cases, Teal ink | `#016869` | 4.66 to 6.16 | `#22AEAE` | 5.01 to 6.62 |
| OSCE, Ochre | `#725B01` | 4.62 to 6.11 | `#BA9A28` | 5.02 to 6.62 |
| Audio, Violet ink | `#7444B3` | 4.60 to 6.09 | `#B386FB` | 5.00 to 6.60 |
| Ideas, Magenta ink | `#A5287B` | 4.65 to 6.15 | `#F06FBE` | 5.00 to 6.61 |
| Correct (the hero) | `#BE0222` | 4.60 to 6.09 | `#FF5D6D` | 4.56 to 6.02 |
| Wrong (pencil) | `#4E463F` | 6.53 to 8.64 | `#BBB5AC` | 6.69 to 8.83 |

### On the grid

WardPaper fills every line with the fine ink and fills a bold line a second time with the bold ink, so a bold line carries 25% of the mode hue by day (9% then 18%) and 20% by night (7% then 14%). The worst case below is text over the darkest bold line among the seven modes.

| Text | Light: worst bold line | Ratio | Dark: worst bold line | Ratio |
|---|---|---|---|---|
| Ink | `#DFABAE` (Questions) | 8.84 | `#40361D` (OSCE) | 10.11 |
| Pencil | `#DFABAE` (Questions) | 4.65 | `#40361D` (OSCE) | 5.85 |

Pencil was darkened so that it clears 4.5:1 over every bold line; it stays well apart from ink. Hero text is never set on the grid. The margin note sits on a plain paper plate, unruled, so Pen Red keeps its 5.20:1 on paper. Where two bold lines cross, a 1 pt dot is darker still; the ratios are measured over the line, as the review asked.

### Chips

A chip is ink, or the hue of the item's own mode (the question-type chip in Questions); it never borrows another mode's hue. Status shows by form: solid for act now ("Due"), an outline for a state ("New", "Weak topic"), a tint for a fact ("34 y"). A hue chip is always an outline, never a tint, so its text keeps the hue's own ratios above (on a card: 5.84 light, 5.03 dark). Tints and solid fills are neutral: ink on the well tint 12.40 (light) and 15.26 (dark); the card colour on solid ink 15.72 (light) and 12.74 (dark).

Pen Red replaces the brief's ECG Red `#D32F45` because `#D32F45` is 3.93:1 on paper and 3.48:1 in wells, under the 4.5:1 that text needs.

The launch stream's new `ecgLine` token, the one line colour for the opening's trace and the title squiggle, is `#D32F45` by day today. A line needs only 3:1, so `#D32F45` would pass as a line, but Route A keeps one red for line and text: `ecgLine` becomes Pen Red, `#BE0222` by day and `#FF5D6D` by night.

By night Pen Red is the crimson `#FF5D6D`, the most vivid red that clears 4.5:1 on all four dark grounds; it replaces the coral `#FF6F6C`.

Correct is marked in the hero, as an examiner ticks in red; a wrong answer is marked in pencil, never in alarm red. See the open question on this in routes.md.

## Route B, Answer Sheet (hero: Signal Orange)

### Grounds and inks

| Token | Light | Dark | Use |
|---|---|---|---|
| base | `#E8E8E6` | `#181716` | The paper: page background and grid ground |
| surface | `#F5F4F3` | `#201F1E` | Cards (flat) |
| raised | `#F9F9F8` | `#272725` | Buttons, fields, option rows |
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
| Correct | `#016E29` | 4.64 to 6.11 | `#39AA54` | 5.03 to 6.38 |
| Wrong | `#B91D1F` | 4.65 to 6.12 | `#FC6258` | 5.01 to 6.36 |

### On the grid

WardPaper fills every line with the fine ink and fills a bold line a second time with the bold ink, so a bold line carries 25% of the mode hue by day (9% then 18%) and 20% by night (7% then 14%). The worst case below is text over the darkest bold line among the seven modes.

| Text | Light: worst bold line | Ratio | Dark: worst bold line | Ratio |
|---|---|---|---|---|
| Ink | `#DCB3BF` (Cards) | 9.24 | `#353013` (OSCE) | 11.63 |
| Pencil | `#DCB3BF` (Cards) | 4.61 | `#353013` (OSCE) | 6.52 |

Pencil was darkened so that it clears 4.5:1 over every bold line; it stays well apart from ink. Hero text is never set on the grid; it sits on cards, controls or plates. Where two bold lines cross, a 1 pt dot is darker still; the ratios are measured over the line, as the review asked.

### Chips

A chip is ink, or the hue of the item's own mode (the question-type chip in Questions); it never borrows another mode's hue. Status shows by form: solid for act now ("Due"), an outline for a state ("New", "Weak topic"), a tint for a fact ("34 y"). A hue chip is always an outline, never a tint, so its text keeps the hue's own ratios above (on a card: 5.83 light, 5.51 dark). Tints and solid fills are neutral: ink on the well tint 12.43 (light) and 16.67 (dark); the card colour on solid ink 15.70 (light) and 14.43 (dark).

Signal Orange as text is the deep `#9A4703`; on light grounds the trace, grid, frame and rims use the brighter graphics tone `#C75A0C` (3.09 to 4.07, above the 3:1 bar for graphics), never for text.

## Route C, Steel & Silicone (hero: Plum)

### Grounds and inks

| Token | Light | Dark | Use |
|---|---|---|---|
| base | `#EBE5E9` | `#242023` | The paper: page background and grid ground |
| surface | `#F6F2F4` | `#2E292D` | Cards (flat) |
| raised | `#FAF7F9` | `#353135` | Buttons, fields, option rows |
| well | `#DED8DC` | `#1C191C` | Flat plates and pressed controls |
| ink | `#221A21` | `#F1EDF0` | Body text and titles |
| ink2 | `#524851` | `#BDB5BA` | Secondary text (pencil) |
| shade | `#A69AA4` | black at 60% | Tint of the lower-right rim shadow |

### Text on the four grounds

| Text colour | Light | Ratio, light | Dark | Ratio, dark |
|---|---|---|---|---|
| Ink | `#221A21` | 12.09 to 15.95 | `#F1EDF0` | 11.03 to 15.03 |
| Pencil (secondary) | `#524851` | 6.22 to 8.21 | `#BDB5BA` | 6.38 to 8.70 |
| Questions, Plum (hero) | `#7E2A78` | 6.01 to 7.93 | `#DD83D3` | 5.03 to 6.85 |
| Cards, Raspberry | `#B02946` | 4.60 to 6.07 | `#FF7789` | 5.03 to 6.85 |
| Textbook, Hunter | `#146C33` | 4.64 to 6.12 | `#62B375` | 5.01 to 6.82 |
| Cases, Caribbean | `#03696A` | 4.63 to 6.11 | `#2DB4B4` | 5.05 to 6.89 |
| OSCE, Mustard | `#6F5C02` | 4.66 to 6.15 | `#B9A13E` | 5.01 to 6.83 |
| Audio, Lilac | `#7348A8` | 4.64 to 6.13 | `#B88EF4` | 5.00 to 6.82 |
| Ideas, Orange | `#944A00` | 4.62 to 6.09 | `#ED8A3D` | 5.06 to 6.89 |
| Correct (the mode's own hue) | `#7E2A78` | 6.01 to 7.93 | `#DD83D3` | 5.03 to 6.85 |
| Wrong (steel) | `#5C5E61` | 4.63 to 6.11 | `#A0A3A5` | 5.04 to 6.87 |

### On the grid

WardPaper fills every line with the fine ink and fills a bold line a second time with the bold ink, so a bold line carries 25% of the mode hue by day (9% then 18%) and 20% by night (7% then 14%). The worst case below is text over the darkest bold line among the seven modes.

| Text | Light: worst bold line | Ratio | Dark: worst bold line | Ratio |
|---|---|---|---|---|
| Ink | `#CFB6CC` (Questions) | 9.06 | `#423A28` (OSCE) | 9.70 |
| Pencil | `#CFB6CC` (Questions) | 4.66 | `#423A28` (OSCE) | 5.61 |

Pencil was darkened so that it clears 4.5:1 over every bold line; it stays well apart from ink. Hero text is never set on the grid; it sits on cards, controls or plates. Where two bold lines cross, a 1 pt dot is darker still; the ratios are measured over the line, as the review asked.

### Chips

A chip is ink, or the hue of the item's own mode (the question-type chip in Questions); it never borrows another mode's hue. Status shows by form: solid for act now ("Due"), an outline for a state ("New", "Weak topic"), a tint for a fact ("34 y"). A hue chip is always an outline, never a tint, so its text keeps the hue's own ratios above (on a card: 7.60 light, 5.62 dark). Tints and solid fills are neutral: ink on steel 13.24 (light) and 8.69 (dark); the card colour on solid ink 15.29 (light) and 12.31 (dark).

Correct and wrong are marked by material, not by green and red. A correct answer fills its row with the mode's own hue, the silicone: Plum here, with its text in the card colour (7.60:1) by day and in the paper colour (6.33:1) by night. A wrong answer turns its row to bare steel, a neutral plate with a steel disc and a cross, its text struck through in pencil. Steel is neutral grey (OKLCH chroma 0.004), so it never reads as blue; the steel text token above is for the cross and other marks.

Lilac sits at OKLCH 302°, beside A's and B's violets at 300°; at 290° it read as periwinkle. Plum moved to 331° and Raspberry to 14°, which widens the gap between them.

## Changes after the first review (15 Oct 2026)

- Pencil (light) darkened to clear 4.5:1 over the grid's bold lines: A `#5D554E` to `#4E463F`, B `#5A5957` to `#4C4C49`, C `#625760` to `#524851`.
- Route A, dark Pen Red: `#FF6F6C` (coral) to `#FF5D6D` (crimson).
- Route C: Lilac `#624FAA` / `#A595F7` to `#7348A8` / `#B88EF4`; Plum `#802C6D` / `#E083C6` to `#7E2A78` / `#DD83D3`; Raspberry `#AF294E` / `#FF7690` to `#B02946` / `#FF7789`; correct is now the mode's own hue and wrong is steel, in place of Hunter green and Raspberry.
- Every route: cards are flat; chips follow the chip rule above; the grid worst cases and chip ratios are printed.

## How the colours were fitted

Each mode hue keeps its hue angle and is pushed to the most vivid chroma that still meets the target on all four grounds, searching lightness in OKLCH and clipping to the sRGB gamut by lowering chroma. Light hues aim at 4.6:1 and dark hues at 5.0:1, a small margin over 4.5:1 for rounding and rendering. None of the heroes is blue, and the Questions hue, the one that used to be blue, is now the hero in every route.
