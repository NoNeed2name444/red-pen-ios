// Bedtime (the owner, 22 Oct): it no longer stays dark in light mode. The
// re-read follows the app's mode on its page colour, in one tone, the same on
// both platforms. Reads the sources; Android's drawn page is
// BedtimeModeTest.bedtimeFollowsTheAppsMode.
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

const routes = read('android/app/src/main/java/com/stethoscore/app/ui/learn/LearnRoutes.kt');
check('Android: the learning sheet takes the app\'s mode, Bedtime or not',
  /StethoscoreTheme\(dark = dark, section = section\)/.test(routes) && !/route == LearnRoute\.Bedtime/.test(routes));
const screen = read('android/app/src/main/java/com/stethoscore/app/ui/learn/BedtimeReviewScreen.kt');
check('Android: the screen itself forces no mode', !/StethoscoreTheme\(/.test(screen) && !/dark = true/.test(screen));

if (failed) { console.log(`\n${failed} FAILED`); process.exit(1); }
console.log('\nbedtime mode: all checks pass');
