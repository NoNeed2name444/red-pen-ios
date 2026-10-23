// Bedtime (the owner, 22 Oct): it no longer stays dark in light mode. The
// re-read follows the app's mode on its page colour, in one tone, the same on
// both platforms. Android is proved drawn (Robolectric):
// BedtimeModeTest.bedtimeFollowsTheAppsMode. The iOS view is SwiftUI, which
// only a Mac lays out, so here its source is read.
import { readFileSync } from 'node:fs';

const repo = new URL('../../', import.meta.url).pathname;
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}
const read = (rel) => readFileSync(repo + rel, 'utf8');

const ios = read('ios/RedPen/Features/Learn/BedtimeReviewView.swift');
const view = ios.slice(ios.indexOf('struct BedtimeReviewView'), ios.indexOf('private struct BedtimeItem'));
check('iOS: the bedtime view is there', view.length > 0);
check('iOS: not held dark', !/\.wardHeld\(\.dark\)/.test(view));
check('iOS: no dark bar forced', !/toolbarColorScheme\(\.dark/.test(view) && !/preferredColorScheme\(\.dark/.test(view) && !/colorScheme, \.dark/.test(view));
check('iOS: on the page colour (WardBackground)', /\.background\(WardBackground\(\)\)/.test(view));

if (failed) { console.log(`\n${failed} FAILED`); process.exit(1); }
console.log('\nbedtime mode: all checks pass');
