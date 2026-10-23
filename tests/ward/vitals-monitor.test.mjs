// Vitals' rhythm card (the owner, 22 Oct: "make it like the monitor"): a
// bedside-monitor panel in both modes, laid out like a real monitor - a status
// strip (what the trace is, the streak's beat), the trace filling the channel
// on the left, a thin rule, and the parameter column on the right, each
// readout its label over its big number in its own colour - the same on both
// platforms, in the ten hexes' tokens only. Android is proved laid out
// (Robolectric): VitalsMonitorTest lays the whole panel out in the dark well
// and checks the layout, the trace as tall as the column, and every word's
// contrast in light and dark. The iOS card is SwiftUI, which only a Mac lays
// out, so here its source is read; colour literals are a source matter on
// both.
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
check('iOS: trace left, rule, readouts right in one HStack, the trace and rule as tall as the readouts',
  /HStack\(alignment: \.top, spacing: WardSpace\.m\) \{\s*trace\s*\.frame\(maxWidth: \.infinity, maxHeight: \.infinity\)\s*Rectangle\(\)\s*\.fill\(Color\.wardHairline\)\s*\.frame\(width: 1\)\s*\.frame\(maxHeight: \.infinity\)\s*readouts\s*\.frame\(width: RhythmMonitor\.column\)\s*\}\s*\.fixedSize\(horizontal: false, vertical: true\)/.test(mon));
check('iOS: no fixed height beside the column; 112 only when the column is under the trace',
  !/\.frame\(width: 1, height:/.test(mon) && (mon.match(/\.frame\(height: RhythmMonitor\.channel\)/g) || []).length === 1
  && /trace\s*\.frame\(height: RhythmMonitor\.channel\)\s*readouts/.test(mon));
check('iOS: RDY, ACC, Q/D in the column', /label: "RDY"[\s\S]*label: "ACC"[\s\S]*label: "Q\/D"/.test(mon));
check('iOS: no ViewThatFits row of readings under the trace', !/ViewThatFits/.test(mon));
check('iOS: a readout is its label over a big mono number, right-aligned, in its colour',
  /WardType\.obsLarge/.test(reading) && /alignment: \.trailing/.test(reading) && /\.foregroundStyle\(tint\)/.test(reading));

const kt = read('android/app/src/main/java/com/stethoscore/app/ui/vitals/VitalsParts.kt');

for (const [name, src] of [['iOS', mon + reading], ['Android', kt.slice(kt.indexOf('fun RhythmMonitor'), kt.indexOf('fun VitalsRings'))]]) {
  check(`${name}: no colour literals on the monitor`, !/#[0-9A-Fa-f]{6}|0x[0-9A-Fa-f]{6,8}|Color\((?:red|0x|\.sRGB)/.test(src));
}

if (failed) { console.log(`\n${failed} FAILED`); process.exit(1); }
console.log('\nvitals monitor: all checks pass');
