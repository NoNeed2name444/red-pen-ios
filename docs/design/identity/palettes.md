# Identity palettes and their contrast

Written 15 Oct 2026 for the three identity routes in [routes.md](routes.md). Every number is a WCAG 2 contrast ratio, from the relative-luminance formula, measured against all four grounds of its theme:

- **base**: the ECG paper itself;
- **surface**: cards, which are flat: a tonal fill and a 1 pt edge, with no blur and no glow;
- **raised**: buttons, including option rows (an option row is an answer button), the only things that carry the soft rim; fields and the tab bar sit on this tone too, but flat, with a 1 pt edge and no rim;
- **well**: flat plates (the lab value, the countdown, B's mark scheme) and pressed controls.

Each range below is the lowest and highest ratio across those four grounds, so the first number is the worst case. The bar is WCAG AA: 4.5:1 for body text, 3:1 for large text (18 pt, or 14 pt bold, as WCAG defines it) and for icons and other graphics. Every text colour here clears 4.5:1 on all four grounds; the light mode hues were fitted to at least 4.6:1 and the dark ones to at least 5.0:1, so each one can carry body text, not only icons. One exception to the 5.0 margin: Route A's dark Pen Red is fitted to 4.55:1, so that it can be a vivid crimson rather than a light coral.

Text set straight on the grid is also measured over the grid's bold lines, the ground with the least contrast that it can meet (see "On the grid" under each route).

The colours are fitted in OKLCH, a colour space that keeps lightness, chroma (how colourful a colour is) and hue angle apart, so a hue can be made darker or lighter without drifting. The sRGB gamut is the set of colours a phone screen can show.

Each mode keeps its own hue for its grid, frame and button rims, and every accent inside a mode (button text, icons, links, the correct mark, the progress beam) follows that hue. In every route the hero is the Questions hue, and the ECG trace, beside the name and in the opening, is drawn in the hero: one token, Trace, equal to the hero in both themes. Inside a mode the trace takes that mode's hue: the listening trace in Audio is drawn in Audio's hue. There are no exceptions left: a correct answer is marked in the mode's own hue in every route, and a wrong one is neutral (pencil in A and B, steel in C).

## Route A, Red Pen (hero: Pen Red)

### Grounds and inks

| Token | Light | Dark | Use |
|---|---|---|---|
| base | `#EAE5DD` | `#211D1A` | The paper: page background and grid ground |
| surface | `#F5F2ED` | `#2A2623` | Cards (flat) |
| raised | `#F9F7F3` | `#322D29` | Buttons and option rows (with the rim); fields and the tab bar (flat) |
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
| Correct (the mode's own hue; Questions shown) | `#BE0222` | 4.60 to 6.09 | `#FF5D6D` | 4.56 to 6.02 |
| Wrong (pencil, struck through) | `#4E463F` | 6.53 to 8.64 | `#BBB5AC` | 6.69 to 8.83 |

### On the grid

WardPaper fills every line with the fine ink and fills a bold line a second time with the bold ink, so a bold line carries 25% of the mode hue by day (9% then 18%) and 20% by night (7% then 14%). The worst case below is text over the bold line that gives it the least contrast among the seven modes: the darkest line by day, the lightest by night.

| Text | Light: worst bold line | Ratio | Dark: worst bold line | Ratio |
|---|---|---|---|---|
| Ink | `#DFABAE` (Questions) | 8.84 | `#40361D` (OSCE) | 10.11 |
| Pencil | `#DFABAE` (Questions) | 4.65 | `#40361D` (OSCE) | 5.85 |

Pencil was darkened so that it clears 4.5:1 over every bold line; it stays well apart from ink. Hero text is never set on the grid. The margin note sits on a plain paper plate, unruled, so Pen Red keeps its 5.20:1 on paper. Where two bold lines cross, a 1 pt dot is darker still; the ratios are measured over the line, as the review asked.

### Chips

A chip is ink, or the hue of the item's own mode (the question-type chip in Questions); it never borrows another mode's hue. Status shows by form: solid for act now ("Due"), an outline for a state ("New", "Weak topic"), a tint for a fact ("34 y"). A hue chip is always an outline, never a tint, so its text keeps the hue's own ratios above (on a card: 5.84 light, 5.03 dark). Tints and solid fills are neutral: ink on the well tint 12.40 (light) and 15.26 (dark); the card colour on solid ink 15.72 (light) and 12.74 (dark).

Pen Red replaces the brief's ECG Red `#D32F45` because `#D32F45` is 3.93:1 on paper and 3.48:1 in wells, under the 4.5:1 that text needs.

The launch stream plans a new `ecgLine` token, one line colour for the opening's trace and the title squiggle, at `#D32F45` by day. It is planned, not yet on any pushed branch. A line needs only 3:1, so `#D32F45` would pass as a line, but Route A keeps one red for line and text: `ecgLine` becomes Pen Red, `#BE0222` by day and `#FF5D6D` by night.

By night Pen Red is the crimson `#FF5D6D`, the most vivid red that clears 4.5:1 on all four dark grounds; it replaces the coral `#FF6F6C`.

Correct is ticked in the mode's own ink, as an examiner ticks in the pen in hand: Pen Red in Questions, Rust in Cards, and so on. A wrong answer is struck through in pencil, never in alarm red. See the open question on red for correct in routes.md.

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

Correct and wrong are marked by material, not by green and red. A correct answer fills its row with the mode's own hue, the silicone: Plum here, with its text in the card colour (7.57:1) by day and in the paper colour (6.29:1) by night. A wrong answer turns its row to bare steel, a neutral plate with a steel disc and a cross, its text struck through in pencil. Steel is exactly neutral grey (OKLCH chroma 0), so it never reads as blue; the steel text token above is for the cross and other marks. A chosen option, before it is marked, shows only a filled letter disc; the whole row fills only once it is marked correct.

Steel tokens:

| Token | Light | Dark | Use |
|---|---|---|---|
| steel | `#CACACA` | `#929292` | Letter bezels, the progress track; the card edge by day |
| steel2 | `#868686` | `#636363` | Hairline on a wrong row; the card edge by night |
| steelPlate | `#E4E3E4` | `#444144` | A wrong row; the neutral chip tint |

On the steel plate: ink 13.26 (light) and 8.69 (dark); pencil 6.82 (light) and 5.03 (dark).

In the second review Plum (331°) sat only 29° from Lilac (302°), ΔE 0.094 by day and 0.076 by night: the closest hero-to-mode pair in any route, so Questions and Audio would have looked alike. (ΔE is the straight-line distance between two colours in OKLCH; the larger it is, the easier two colours are to tell apart.) Three hues move: Plum from 331° to 342°, Lilac from 302° to 298°, and Raspberry from 14° to 20°. Plum to Lilac is now ΔE 0.124 by day and 0.114 by night, and Plum to Raspberry 0.123 and 0.102, in line with A's closest pair (Pen Red to Rust, 0.118 and 0.119).

## Changes after the first review (15 Oct 2026)

- Pencil (light) darkened to clear 4.5:1 over the grid's bold lines: A `#5D554E` to `#4E463F`, B `#5A5957` to `#4C4C49`, C `#625760` to `#524851`.
- Route A, dark Pen Red: `#FF6F6C` (coral) to `#FF5D6D` (crimson).
- Route C: Lilac `#624FAA` / `#A595F7` to `#6F4AAB` / `#B290F8`; Plum `#802C6D` / `#E083C6` to `#86266A` / `#E77FC2`; Raspberry `#AF294E` / `#FF7690` to `#B02A39` / `#FF787D`; correct is now the mode's own hue and wrong is steel, in place of Hunter green and Raspberry.
- Every route: cards are flat; chips follow the chip rule above; the grid worst cases and chip ratios are printed.

## Changes after the second review (15 Oct 2026)

- Route A: correct is ticked in the mode's own ink, not in Pen Red in every mode.
- Route B: the Correct green and Wrong red tokens are gone; correct is the mode's hue, wrong is pencil. The beam follows the mode's hue and a warning is pencil with a symbol.
- Route C: Plum `#7E2A78` / `#DD83D3` to `#86266A` / `#E77FC2` (331° to 342°); Lilac `#7348A8` / `#B88EF4` to `#6F4AAB` / `#B290F8` (302° to 298°); Raspberry `#B02946` / `#FF7789` to `#B02A39` / `#FF787D` (14° to 20°). Steel is now exactly neutral (chroma 0), so the wrong token is `#5E5E5E` / `#A2A2A2`.
- Every route: the soft rim is on buttons only (option rows count as answer buttons); fields and the tab bar are flat. The boards still show the old rims on fields and the tab bar and will change in the next render.

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
| wrong | `.danger`, when used for marking | Pencil (A, B) or steel (C), struck through |
| danger | `.danger`, for destructive actions | Not a marking colour. A Delete button is ink with a trash symbol; iOS alerts and menus keep their own destructive red |
| warning | `.warning` | Pencil with a warning symbol |
| beam | `.beam` | The mode's hue |
| hairline | `.hairline` | A `#D7D3CF` / `#4A4642`; B `#D6D6D4` / `#41403F`; C steel `#CACACA` / steel2 `#636363` |
| monitor | `.monitor` | The route's dark well in both themes: A `#1A1614`, B `#11100F`, C `#1C191C` |
| onPrimary | `.onPrimary` | Text on a solid hue fill: the card colour by day, the paper colour by night. On the hero: A 5.84 / 5.61; B 5.83 / 6.00; C 7.57 / 6.29 |
| steel, steel2, steelPlate | new, Route C only | See Route C |

## How the colours were fitted

Each mode hue is set at a chosen hue angle and pushed to the most vivid chroma that still meets the target on all four grounds, searching lightness in OKLCH and clipping to the sRGB gamut by lowering chroma. Light hues aim at 4.6:1 and dark hues at 5.0:1, a small margin over 4.5:1 for rounding and rendering. None of the heroes is blue, and the Questions hue, the one that used to be blue, is now the hero in every route.

The hue angles are not all today's. Against round 9 (`d52aa6b6`, `WardLook.swift:18-24`) and today's `design/ward-polish` (`5ba53153`, `WardLook.swift:66-71`), measured on the light inks, these modes move by more than 10°:

| Route | Mode | Round 9 | Route | Change from round 9 | Change from ward-polish |
|---|---|---|---|---|---|
| A | Cards, Rust | `#C23048` (17°) | `#934A03` (55°) | +38° | +94° |
| A | Cases, Teal ink | `#0D7C8C` (211°) | `#016869` (196°) | -15° | -88° |
| A | OSCE, Ochre | `#8F6200` (77°) | `#725B01` (92°) | +14° | +0° |
| B | Cases, Teal | `#0D7C8C` (211°) | `#066A6B` (196°) | -15° | -88° |
| B | OSCE, Gold | `#8F6200` (77°) | `#6C5F02` (100°) | +23° | +8° |
| C | Cases, Caribbean | `#0D7C8C` (211°) | `#03696A` (196°) | -15° | -88° |
| C | OSCE, Mustard | `#8F6200` (77°) | `#6F5C02` (95°) | +17° | +3° |
| C | Ideas, Orange | `#A8327E` (345°) | `#944A00` (55°) | +70° | +75° |

Two of these are changes of colour family, not tuning, and are the owner's to accept: Route A's Cards goes from raspberry to Rust, so that red means only Questions and the trace (open question 2 in routes.md); Route C's Ideas goes from magenta to Orange, because C's Plum hero takes the magenta corner (open question 5). Against `design/ward-polish` the moves are larger, because that branch has already moved Cards to a purple (`#9D3EB1`) and Cases to a blue-violet (`#6656D7`); every route takes Cases back to teal, which also removes a near-blue.
