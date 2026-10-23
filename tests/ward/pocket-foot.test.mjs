// The Ward pocket on iOS (T0131 item 2, the owner, 22 Oct): ward-score's
// running total and ward-pocket's "For learning only" chip stood over the last
// rows, and the search field at the foot covered them. Now what stands at the
// foot stands under the page, so the page ends above it (Android's
// WardDisclaimerFrame pads its page the same way, WardPocketFootTest), and
// the search field is under the title. Reads the source.
import { readFileSync } from 'node:fs';

const repo = new URL('../../', import.meta.url).pathname;
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}
const src = readFileSync(repo + 'ios/RedPen/Features/Exam/WardPocketView.swift', 'utf8');
const foot = src.slice(src.indexOf('private struct WardFoot<Foot: View>: ViewModifier {'), src.indexOf('private struct WardDisclaimer'));
const disclaimer = src.slice(src.indexOf('private struct WardDisclaimer: ViewModifier {'), src.indexOf('extension View {', src.indexOf('private struct WardDisclaimer')));

check('nothing floats over a pocket page: no bottom safe-area inset', !/safeAreaInset\(edge: \.bottom/.test(src));
check('the foot stands under the page: a VStack of the page then the foot',
  /VStack\(spacing: 0\) \{\s*content\s*foot\(\)\s*\}/.test(foot) && /WardBackground\(\)\.ignoresSafeArea\(\)/.test(foot));
check('the disclaimer is a foot', /content\.modifier\(WardFoot \{/.test(disclaimer) && /WardPocket\.disclaimer/.test(disclaimer));
check('the score total is a foot, above the disclaimer',
  /\.modifier\(WardFoot \{\s*WardScoreTotal\(total: total, band: verdict\)[\s\S]*?\}\)\s*\.wardDisclaimer\(\)/.test(src));
check('the search field is under the title, not at the foot',
  /\.searchable\(text: \$query, placement: \.navigationBarDrawer\(displayMode: \.always\)/.test(src));

if (failed) { console.log(`\n${failed} FAILED`); process.exit(1); }
console.log('\npocket foot: all checks pass');
