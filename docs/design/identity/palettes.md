# Identity palettes and their contrast

Written 15 Oct 2026 for the three identity routes in [routes.md](routes.md). Every number is a WCAG 2 contrast ratio, from the relative-luminance formula, measured against all four grounds of its theme:

- **base**: the ECG paper itself;
- **surface**: cards;
- **raised**: buttons and option rows;
- **well**: inset fields, the lab-value well and the search field.

Each range below is the lowest and highest ratio across those four grounds, so the first number is the worst case. The bar is WCAG AA: 4.5:1 for body text, 3:1 for large text (20 pt, or 14 pt bold) and for icons and other graphics. Every text colour here clears 4.5:1 on all four grounds; the light mode hues were fitted to at least 4.6:1 and the dark ones to at least 5.0:1, so each one can carry body text, not only icons.

Each mode keeps its own hue for its grid, frame and button rims, and every accent inside a mode (button text, icons, links) follows that hue. In every route the hero is the Questions hue, and the ECG trace, beside the name and in the opening, is drawn in the hero: one token, Trace, equal to the hero in both themes.

## Route A, Red Pen (hero: Pen Red)

### Grounds and inks

| Token | Light | Dark | Use |
|---|---|---|---|
| base | `#EAE5DD` | `#211D1A` | The paper: page background and grid ground |
| surface | `#F5F2ED` | `#2A2623` | Cards |
| raised | `#F9F7F3` | `#322D29` | Buttons, option rows, chips |
| well | `#DED8CF` | `#1A1614` | Inset fields, lab values, search |
| ink | `#1E1814` | `#F0ECE5` | Body text and titles |
| ink2 | `#5D554E` | `#BBB5AC` | Secondary text (pencil) |
| shade | `#A99C8E` | black at 60% | Tint of the lower-right rim shadow |

### Text on the four grounds

| Text colour | Light | Ratio, light | Dark | Ratio, dark |
|---|---|---|---|---|
| Ink | `#1E1814` | 12.40 to 16.41 | `#F0ECE5` | 11.56 to 15.26 |
| Pencil (secondary) | `#5D554E` | 5.16 to 6.83 | `#BBB5AC` | 6.69 to 8.83 |
| Questions, Pen Red (hero) | `#BE0222` | 4.60 to 6.09 | `#FF6F6C` | 5.02 to 6.62 |
| Cards, Rust | `#934A03` | 4.60 to 6.09 | `#EB8229` | 5.03 to 6.64 |
| Textbook, Green ink | `#006C2F` | 4.65 to 6.16 | `#4DB068` | 5.01 to 6.61 |
| Cases, Teal ink | `#016869` | 4.66 to 6.16 | `#22AEAE` | 5.01 to 6.62 |
| OSCE, Ochre | `#725B01` | 4.62 to 6.11 | `#BA9A28` | 5.02 to 6.62 |
| Audio, Violet ink | `#7444B3` | 4.60 to 6.09 | `#B386FB` | 5.00 to 6.60 |
| Ideas, Magenta ink | `#A5287B` | 4.65 to 6.15 | `#F06FBE` | 5.00 to 6.61 |
| Correct (the hero) | `#BE0222` | 4.60 to 6.09 | `#FF6F6C` | 5.02 to 6.62 |
| Wrong (pencil) | `#5D554E` | 5.16 to 6.83 | `#BBB5AC` | 6.69 to 8.83 |

Correct is marked in the hero, as an examiner ticks in red; a wrong answer is marked in pencil, never in alarm red. See the open question on this in routes.md.

## Route B, Answer Sheet (hero: Signal Orange)

### Grounds and inks

| Token | Light | Dark | Use |
|---|---|---|---|
| base | `#E8E8E6` | `#181716` | The paper: page background and grid ground |
| surface | `#F5F4F3` | `#201F1E` | Cards |
| raised | `#F9F9F8` | `#272725` | Buttons, option rows, chips |
| well | `#DBDBD8` | `#11100F` | Inset fields, lab values, search |
| ink | `#1B1B19` | `#F0F0EF` | Body text and titles |
| ink2 | `#5A5957` | `#B6B6B3` | Secondary text (pencil) |
| shade | `#A6A5A0` | black at 60% | Tint of the lower-right rim shadow |

### Text on the four grounds

| Text colour | Light | Ratio, light | Dark | Ratio, dark |
|---|---|---|---|---|
| Ink | `#1B1B19` | 12.43 to 16.37 | `#F0F0EF` | 13.12 to 16.67 |
| Pencil (secondary) | `#5A5957` | 5.04 to 6.64 | `#B6B6B3` | 7.36 to 9.35 |
| Questions, Signal Orange (hero) | `#9A4703` | 4.62 to 6.08 | `#EF7107` | 5.01 to 6.37 |
| Cards, Raspberry | `#B8194C` | 4.61 to 6.07 | `#FA5F81` | 5.00 to 6.35 |
| Textbook, Green | `#046E31` | 4.61 to 6.08 | `#3BA95D` | 5.00 to 6.35 |
| Cases, Teal | `#066A6B` | 4.61 to 6.07 | `#04A7A7` | 5.05 to 6.42 |
| OSCE, Gold | `#6C5F02` | 4.62 to 6.09 | `#A99605` | 5.03 to 6.38 |
| Audio, Violet | `#7642B9` | 4.66 to 6.13 | `#AE7DF9` | 5.06 to 6.43 |
| Ideas, Magenta | `#A32D85` | 4.63 to 6.09 | `#E369BF` | 5.02 to 6.37 |
| Correct | `#016E29` | 4.64 to 6.11 | `#39AA54` | 5.03 to 6.38 |
| Wrong | `#B91D1F` | 4.65 to 6.12 | `#FC6258` | 5.01 to 6.36 |

Signal Orange as text is the deep `#9A4703`; on light grounds the trace, grid, frame and rims use the brighter graphics tone `#C75A0C` (3.09 to 4.07, above the 3:1 bar for graphics), never for text.

## Route C, Steel & Silicone (hero: Plum)

### Grounds and inks

| Token | Light | Dark | Use |
|---|---|---|---|
| base | `#EBE5E9` | `#242023` | The paper: page background and grid ground |
| surface | `#F6F2F4` | `#2E292D` | Cards |
| raised | `#FAF7F9` | `#353135` | Buttons, option rows, chips |
| well | `#DED8DC` | `#1C191C` | Inset fields, lab values, search |
| ink | `#221A21` | `#F1EDF0` | Body text and titles |
| ink2 | `#625760` | `#BDB5BA` | Secondary text (pencil) |
| shade | `#A69AA4` | black at 60% | Tint of the lower-right rim shadow |

### Text on the four grounds

| Text colour | Light | Ratio, light | Dark | Ratio, dark |
|---|---|---|---|---|
| Ink | `#221A21` | 12.09 to 15.95 | `#F1EDF0` | 11.03 to 15.03 |
| Pencil (secondary) | `#625760` | 4.90 to 6.47 | `#BDB5BA` | 6.38 to 8.70 |
| Questions, Plum (hero) | `#802C6D` | 5.99 to 7.90 | `#E083C6` | 5.01 to 6.83 |
| Cards, Raspberry | `#AF294E` | 4.60 to 6.07 | `#FF7690` | 5.02 to 6.84 |
| Textbook, Hunter | `#146C33` | 4.64 to 6.12 | `#62B375` | 5.01 to 6.82 |
| Cases, Caribbean | `#03696A` | 4.63 to 6.11 | `#2DB4B4` | 5.05 to 6.89 |
| OSCE, Mustard | `#6F5C02` | 4.66 to 6.15 | `#B9A13E` | 5.01 to 6.83 |
| Audio, Lilac | `#624FAA` | 4.65 to 6.13 | `#A595F7` | 5.02 to 6.84 |
| Ideas, Orange | `#944A00` | 4.62 to 6.09 | `#ED8A3D` | 5.06 to 6.89 |
| Correct (Textbook hue) | `#146C33` | 4.64 to 6.12 | `#62B375` | 5.01 to 6.82 |
| Wrong (Cards hue) | `#AF294E` | 4.60 to 6.07 | `#FF7690` | 5.02 to 6.84 |

Correct borrows the Textbook green and wrong borrows the Cards raspberry, so the semantic pair needs no extra hues.

## How the colours were fitted

Each mode hue keeps its hue angle and is pushed to the most vivid chroma that still meets the target on all four grounds, searching lightness in OKLCH and clipping to the sRGB gamut by lowering chroma. Light hues aim at 4.6:1 and dark hues at 5.0:1, a small margin over 4.5:1 for rounding and rendering. None of the heroes is blue, and the Questions hue, the one that used to be blue, is now the hero in every route.
