// Draw from memory (the owner, 22 Oct), drawing and comparing alike: the
// canvas fills most of the page, from under the hint line to just above the
// pen tray; its corners concentric with the display's (WardCorner.concentric);
// the page colour with an inset shadow only - no white sheet - so the ink and
// the pictures of it follow the mode. iOS only: Android has no draw recall
// (android/docs/parity.md). Reads the source; the view needs a Mac to build.
import { readFileSync } from 'node:fs';

const repo = new URL('../../', import.meta.url).pathname;
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}
const src = readFileSync(repo + 'ios/RedPen/Features/Recall/DrawRecallView.swift', 'utf8');
const at = src.indexOf('private var paper: some View {');
const paper = src.slice(at, src.indexOf('\n    }\n', at));

check('the paper is there', at > 0);
check('no white sheet anywhere on the screen', !/Color\.white|UIColor\.white/.test(src));
check('the paper keeps no picture-shaped ratio: it fills the room', !/aspectRatio\(paperRatio/.test(src) && /\.frame\(maxWidth: \.infinity, maxHeight: \.infinity\)/.test(paper));
check('pressed into the page colour: an inset shadow only', /\.wardInset\(in: shape, lift: \.low, fill: Color\.wardBackground\)/.test(paper) && !/wardRaised/.test(paper));
check('its corner is concentric with the display\'s',
  /RoundedRectangle\(cornerRadius: paperRadius/.test(paper) && /WardCorner\.concentric\(device: device, inset: inset, floor: Double\(WardRadius\.card\)\)/.test(src)
  && /WardPaper\.deviceRadius\(/.test(src));
check('its foot stands just above a docked pen tray',
  /\.padding\(\.bottom, comparing \? 0 : Self\.trayGap\(room: paperRoom, picker: pickerFrame\)\)/.test(paper)
  && /static func trayGap\(room: CGRect, picker: CGRect\) -> CGFloat/.test(src) && /room\.maxY - picker\.minY/.test(src));
check('the room is measured outside the padding it sets (no loop)',
  /\.frame\(maxWidth: \.infinity, maxHeight: \.infinity\)\s*\.onGeometryChange\(for: CGRect\.self\)/.test(paper));
check('the canvas takes the app\'s mode (no forced light)', !/overrideUserInterfaceStyle = \.light/.test(src));
check('pictures of the ink are drawn in the mode', /userInterfaceStyle: dark \? \.dark : \.light/.test(src) && !/UITraitCollection\(userInterfaceStyle: \.light\)/.test(src));
check('compare still lines up: the original is fitted in the drawing\'s frame',
  /\.aspectRatio\(Self\.ratio\(drawn\), contentMode: \.fit\)/.test(src));
check('no colour literals added to the paper', !/#[0-9A-Fa-f]{6}|Color\(red:/.test(paper));

if (failed) { console.log(`\n${failed} FAILED`); process.exit(1); }
console.log('\ndraw recall paper: all checks pass');
