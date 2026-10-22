// Vitals' rhythm card (the owner, 22 Oct: "make it like the monitor"): a
// bedside-monitor panel in both modes, laid out like a real monitor - a status
// strip (what the trace is, the streak's beat), the trace filling the channel
// on the left, a thin rule, and the parameter column on the right, each
// readout its label over its big number in its own colour - the same on both
// platforms, in the ten hexes' tokens only. Reads the sources; Android's
// laid-out screen is VitalsMonitorTest.
import { readFileSync } from 'node:fs';

const repo = new URL('../../', import.meta.url).pathname;
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}
const read = (rel) => readFileSync(repo + rel, 'utf8');
function block(text, start) {
  const at = text.indexOf(start);
  if (at < 0) return '';
  const rest = text.slice(at + start.length);
  const end = rest.search(/\n(?:struct|private struct|extension|enum|final class|class) /);
  return start + (end < 0 ? rest : rest.slice(0, end));
}

const ios = read('ios/RedPen/Features/Analytics/VitalsParts.swift');
const mon = block(ios, 'struct RhythmMonitor: View {');
const reading = block(ios, 'private struct MonitorReading: View {');
check('iOS: still a monitor panel (MonitorCard)', /MonitorCard\(lift: \.low\)/.test(mon));
check('iOS: a status strip with the streak on the right', /private var statusStrip/.test(mon) && /Spacer\(minLength:[^)]*\)\s*streakReading/.test(mon));
check('iOS: trace left, rule, readouts right in one HStack',
  /HStack\(alignment: \.top, spacing: WardSpace\.m\) \{\s*trace\s*\.frame\(maxWidth: \.infinity\)\s*Rectangle\(\)\s*\.fill\(Color\.wardHairline\)[\s\S]*?readouts\s*\.frame\(width: RhythmMonitor\.column\)/.test(mon));
check('iOS: the trace fills the channel', /static let channel: CGFloat = 112/.test(mon) && /\.frame\(height: RhythmMonitor\.channel\)/.test(mon));
check('iOS: RDY, ACC, Q/D in the column', /label: "RDY"[\s\S]*label: "ACC"[\s\S]*label: "Q\/D"/.test(mon));
check('iOS: no ViewThatFits row of readings under the trace', !/ViewThatFits/.test(mon));
check('iOS: a readout is its label over a big mono number, right-aligned, in its colour',
  /WardType\.obsLarge/.test(reading) && /alignment: \.trailing/.test(reading) && /\.foregroundStyle\(tint\)/.test(reading));

const kt = read('android/app/src/main/java/com/stethoscore/app/ui/vitals/VitalsParts.kt');
check('Android: still a monitor panel (WardMonitorCard)', /WardMonitorCard\(/.test(kt));
check('Android: a status strip with the streak on the right',
  /Box\(Modifier\.weight\(1f\)\) \{ WardSmallCapsText\("Study rhythm · " \+ reading\.words\) \}\s*MonitorStreak\(streak\)/.test(kt));
check('Android: trace left, rule, readouts right in one Row',
  /MonitorTrace\(reading, Modifier\.weight\(1f\)\)\s*Box\(Modifier\.width\(1\.dp\)\.height\(MonitorChannel\.channel\.dp\)\.background\(wardColor\(WardToken\.hairline\)\)\)\s*MonitorReadouts\([^)]*Modifier\.width\(MonitorChannel\.column\.dp\)\)/.test(kt));
check('Android: the same channel and column as iOS', /const val channel: Int = 112/.test(kt) && /const val column: Int = 112/.test(kt));
check('Android: a readout is its label over a big mono number, end-aligned',
  /WardType\.obsLarge\.textStyle\(\)/.test(kt) && /textAlign = TextAlign\.End/.test(kt));
check('Android: no MonitorFits row of readings under the trace', !/MonitorFits/.test(kt));

for (const [name, src] of [['iOS', mon + reading], ['Android', kt.slice(kt.indexOf('fun RhythmMonitor'), kt.indexOf('fun VitalsRings'))]]) {
  check(`${name}: no colour literals on the monitor`, !/#[0-9A-Fa-f]{6}|0x[0-9A-Fa-f]{6,8}|Color\((?:red|0x|\.sRGB)/.test(src));
}

if (failed) { console.log(`\n${failed} FAILED`); process.exit(1); }
console.log('\nvitals monitor: all checks pass');
