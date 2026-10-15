// The stethoscope's tube by night is grey, not blue: the owner had the
// slate-blue tube replaced with a grey one (15 Oct). Over every dark file of
// the mark and the icon, no pixel of the tube may have a saturation above
// 0.25 at a hue between 190 and 250 degrees.
//
// The tube's pixels: the mark's solid pixels (alpha at least 0.98; on the
// opaque pictures, where the mark is lit, a value of at least 0.35, which the
// dark ground, 0.21, and its shadows never reach), outside the chest piece,
// whose blue A+ engraving is meant to be blue. Darker than 0.35 a hue barely
// shows, so it is not judged.
//
//   node tests/art/no-blue-tube.test.mjs          the committed art
//   node tests/art/no-blue-tube.test.mjs <dir>    the same files (by name) from <dir>
import { existsSync, readFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readPng, hsv, chestPiece } from './art.mjs';

let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}

const root = fileURLToPath(new URL('../../', import.meta.url));
const other = process.argv[2];
const at = p => (other ? join(other, basename(p)) : join(root, p));

const SATURATION = 0.25;
const HUE = [190, 250];
const LIT = 0.35;
const MARGIN = 1.08;        // the chest piece's disc, a little wider for its rim and shadow
const DARK_GROUND = [0x2A, 0x2E, 0x35];

// Known in the art, and sent back to be redrawn (15 Oct): the dark launch
// drawing has a thin blue line where the grey tube meets the chest piece's
// stem, at the tube's top end (the day drawing has none). It is allowed for,
// no more than that, only there: just under the chest piece, at most
// COLLAR x its radius in pixels. Take this out once the drawing is fixed.
const COLLAR = 0.6;

// LaunchArt.chest(dark: true), as tools/make_launch_logo.py measured it
const swift = readFileSync(join(root, 'ios/RedPen/Shared/LaunchOpening.swift'), 'utf8');
const found = swift.match(/dark \? \(([0-9.]+), ([0-9.]+), ([0-9.]+)\)/);
check('LaunchArt.chest has the dark mark\'s chest piece', !!found);
const launchChest = found ? found.slice(1, 4).map(Number) : [0, 0, 0];

// the dark launch drawing's square, as the tool crops it: round the pixels
// off the ground, padded by 5% a side
function launchSquare(img) {
  let x0 = Infinity, y0 = Infinity, x1 = -1, y1 = -1;
  for (let y = 0; y < img.height; y++) {
    for (let x = 0; x < img.width; x++) {
      const o = (y * img.width + x) * 4;
      const d = Math.max(...[0, 1, 2].map(c => Math.abs(img.data[o + c] - DARK_GROUND[c])));
      if (d > 2) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x + 1); y1 = Math.max(y1, y + 1); }
    }
  }
  const side = Math.floor(Math.max(x1 - x0, y1 - y0) * 1.1);
  return { left: Math.round((x0 + x1) / 2 - side / 2), top: Math.round((y0 + y1) / 2 - side / 2), side };
}

const layer = 'design/icon/layers/1-stethoscope-dark.png';
const layerChest = existsSync(at(layer)) ? chestPiece(readPng(at(layer))) : null;
const files = [
  ...[1, 2, 3].map(n => ({
    path: `ios/RedPen/Assets.xcassets/LaunchLogo.imageset/launch-logo-dark@${n}x.png`, cut: true, collar: true,
    chest: img => ({ x: launchChest[0] * img.width, y: launchChest[1] * img.width, r: launchChest[2] * img.width }),
  })),
  {
    path: 'design/launch-logo/dark.png', cut: false, collar: true,
    chest: img => {
      const s = launchSquare(img);
      return { x: s.left + launchChest[0] * s.side, y: s.top + launchChest[1] * s.side, r: launchChest[2] * s.side };
    },
  },
  { path: layer, cut: true, chest: img => chestPiece(img) },
  { path: 'ios/RedPen/Assets.xcassets/AppIcon.appiconset/icon-1024-dark.png', cut: false, chest: () => layerChest },
  { path: 'ios/AppResources/AppIcon.icon/Assets/icon-dark.png', cut: false, chest: () => layerChest },
  {
    path: 'design/icon/source/icon-dark.png', cut: false,
    // the icon is this picture scaled to 1024 (tools/make_icon.py), so its
    // chest piece is the layer's, scaled back
    chest: img => layerChest && { x: layerChest.x * img.width / 1024, y: layerChest.y * img.width / 1024, r: layerChest.r * img.width / 1024 },
  },
];

let judged = 0;
for (const f of files) {
  const path = at(f.path);
  if (!existsSync(path)) { if (!other) check(`${f.path} exists`, false, 'missing'); continue; }
  const img = readPng(path);
  const c = f.chest(img);
  if (!c) { check(`${basename(f.path)}: its chest piece is found`, false); continue; }
  let tube = 0, blue = 0, collar = 0, most = 0, where = null;
  for (let y = 0; y < img.height; y++) {
    for (let x = 0; x < img.width; x++) {
      const o = (y * img.width + x) * 4;
      if (f.cut && img.data[o + 3] < 250) continue;
      const p = hsv(img.data[o], img.data[o + 1], img.data[o + 2]);
      if (p.v < LIT) continue;
      const dx = x + 0.5 - c.x, dy = y + 0.5 - c.y;
      if (dx * dx + dy * dy <= (MARGIN * c.r) ** 2) continue;
      tube++;
      if (p.h < HUE[0] || p.h > HUE[1] || p.s <= SATURATION) continue;
      const underChest = Math.abs(dx) <= 0.35 * c.r && dy >= c.r && dy <= 1.25 * c.r;
      if (f.collar && underChest) { collar++; continue; }
      blue++;
      if (p.s > most) { most = p.s; where = [x, y]; }
    }
  }
  judged++;
  const name = f.path.split('/').slice(-2).join('/');
  console.log(`     ${name}: ${tube} tube pixels judged, ${blue} blue${f.collar ? `, ${collar} on the stem's collar (known)` : ''}`);
  check(`${name}: no blue in the tube`, blue === 0, `${blue} px, the bluest (saturation ${most.toFixed(2)}) at (${where})`);
  check(`${name}: enough of the tube judged`, tube > 0.01 * img.width * img.height, `${tube} px`);
  if (f.collar) check(`${name}: the collar's known blue line is no bigger`, collar <= COLLAR * c.r, `${collar} px`);
}
check('every dark file was judged', judged > 0);

console.log(failed ? `\n${failed} BLUE TUBE FAILURE(S)` : '\nALL BLUE TUBE TESTS PASS');
process.exit(failed ? 1 : 0);
