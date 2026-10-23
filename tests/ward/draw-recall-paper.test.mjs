// Draw from memory (the owner, 22 Oct), drawing and comparing alike: the
// canvas fills most of the page, from under the hint line to just above the
// pen tray; its corners concentric with the display's (WardCorner.concentric);
// the page colour with an inset shadow only - no white sheet - so the ink and
// the pictures of it follow the mode. iOS only: Android has no draw recall
// (android/docs/parity.md). What can be decided without a view is in
// RecallPaper and proved by the recallpaper Swift suite on Linux: the foot
// above a docked tray, the paper held at its drawn size through Compare, and
// the original taking the mode (no white block in dark). The view itself is
// SwiftUI and PencilKit, which only a Mac builds, so here its wiring is read.
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
check('the paper keeps no picture-shaped ratio: it fills the room', !/aspectRatio\(paperRatio/.test(src) && /\.frame\(maxWidth: \.infinity, maxHeight: \.infinity, alignment: \.top\)/.test(paper));
check('pressed into the page colour: an inset shadow only', /\.wardInset\(in: shape, lift: \.low, fill: Color\.wardBackground\)/.test(paper) && !/wardRaised/.test(paper));
check('its corner is concentric with the display\'s',
  /RoundedRectangle\(cornerRadius: paperRadius/.test(paper) && /WardCorner\.concentric\(device: device, inset: inset, floor: Double\(WardRadius\.card\)\)/.test(src)
  && /WardPaper\.deviceRadius\(/.test(src));
check('its foot stands just above a docked pen tray (RecallPaper.trayGap)',
  /\.padding\(\.bottom, held == nil \? RecallPaper\.trayGap\(room: paperRoom, picker: pickerFrame, space: WardSpace\.s\) : 0\)/.test(paper));
check('Compare never resizes it: the drawn size is held, and the panel floats over the foot',
  /let held: CGSize\? = RecallPaper\.size\(comparing: comparing, drawnOn: drawnOn\)/.test(paper)
  && /\.frame\(width: held\?\.width, height: held\?\.height\)/.test(paper)
  && /\.overlay\(alignment: \.bottom\) \{ comparePanelHost\.wardUnlit\(\) \}/.test(src)
  && (src.match(/drawnOn = paperSize/g) || []).length === 2);
check('the original takes the mode (RecallPaper.original)',
  /switch RecallPaper\.original\(dark: scheme == \.dark\)/.test(src) && /\.colorInvert\(\)\.hueRotation\(\.degrees\(180\)\)\.blendMode\(\.screen\)/.test(src));
check('the room is measured outside the padding it sets (no loop)',
  /\.frame\(maxWidth: \.infinity, maxHeight: \.infinity, alignment: \.top\)\s*\.onGeometryChange\(for: CGRect\.self\)/.test(paper));
check('the canvas takes the app\'s mode (no forced light)', !/overrideUserInterfaceStyle = \.light/.test(src));
check('pictures of the ink are drawn in the mode', /userInterfaceStyle: dark \? \.dark : \.light/.test(src) && !/UITraitCollection\(userInterfaceStyle: \.light\)/.test(src));
check('compare still lines up: the original is fitted in the drawing\'s frame',
  /\.aspectRatio\(Self\.ratio\(drawn\), contentMode: \.fit\)/.test(src));
check('no colour literals added to the paper', !/#[0-9A-Fa-f]{6}|Color\(red:/.test(paper));

if (failed) { console.log(`\n${failed} FAILED`); process.exit(1); }
console.log('\ndraw recall paper: all checks pass');
