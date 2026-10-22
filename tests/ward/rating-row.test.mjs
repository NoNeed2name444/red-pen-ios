// Card review's ratings (r066, the owner, 22 Oct): Again, Hard, Good, Easy as
// one word each with no caption lines, side by side in one row (never two by
// two), each 44 pt on iOS and 48 dp on Android. The meaning and when the card
// comes back stay with VoiceOver and TalkBack. Android is proved laid out
// (Robolectric): AnkiReviewScreenTest.theRatingsStandInOneRowOfWords and
// RatingWordFitTest (no word clipped at font scale 1.3 and 1.45, 360 dp).
// The iOS bar is SwiftUI, which only a Mac lays out, so here its source is
// read; the tour's r066 shot is its picture.
import { readFileSync } from 'node:fs';

const repo = new URL('../../', import.meta.url).pathname;
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}
const read = (rel) => readFileSync(repo + rel, 'utf8');
// the text from `start` up to the next top-level declaration
function block(text, start) {
  const at = text.indexOf(start);
  if (at < 0) return '';
  const rest = text.slice(at + start.length);
  const end = rest.search(/\n(?:struct|private struct|extension|enum|final class|class) /);
  return start + (end < 0 ? rest : rest.slice(0, end));
}

const ios = read('ios/RedPen/Features/Anki/AnkiCardFace.swift');
const bar = block(ios, 'struct AnkiRatingBar: View {');
const face = block(ios, 'private struct AnkiRatingFace: View {');
check('iOS: the rating bar is there', bar.length > 0);
check('iOS: no two-by-two rows (no HStack holding only two ratings)',
  !/HStack\(spacing: [^)]*\) \{\s*button\(\.\w+, hints: hints\)\s*button\(\.\w+, hints: hints\)\s*\}/.test(bar));
check('iOS: one HStack holds all four, Again to Easy',
  /HStack\(spacing: [^)]*\) \{\s*button\(\.again, hints: hints\)\s*button\(\.hard, hints: hints\)\s*button\(\.good, hints: hints\)\s*button\(\.easy, hints: hints\)\s*\}/.test(bar));
check('iOS: no window-width switch between layouts', !/oneRow|span > \.slim/.test(bar));
check('iOS: the label is the word alone (no meaning or "back" caption)',
  /let label = Text\(Self\.title\(rating\)\)/.test(bar) && !/Text\(Self\.meaning\(rating\)\)/.test(bar) && !/Text\("back"\)/.test(bar));
check('iOS: the meaning is VoiceOver\'s hint and the interval its value',
  /\.accessibilityHint\(Self\.meaning\(rating\)\)/.test(bar) && /\.accessibilityValue\(SpokenText\.interval\(when\)\)/.test(bar));
check('iOS: each button is 44 pt tall', /static let height: CGFloat = 44/.test(bar) && /minHeight: AnkiRatingBar\.height/.test(face));

if (failed) { console.log(`\n${failed} FAILED`); process.exit(1); }
console.log('\nrating row: all checks pass');
