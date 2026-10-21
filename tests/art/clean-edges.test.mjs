// The stethoscope's cut edges (the launch mark and the icon's layers): every
// launch image, light and dark at @1x, @2x and @3x, and both icon layers,
// cut by tools/make_launch_logo.py, must have a clean anti-aliased outline:
// no squared-off steps, no specks, no notches or pinholes, no ring of the
// ground's colour. And the opaque icons must be those layers put together.
//
//   node tests/art/clean-edges.test.mjs          the committed art
//   node tests/art/clean-edges.test.mjs <dir>    the same files (by name) from <dir>,
//                                                to measure older art against the bar
//   ART_ROOT=<dir> node tests/art/clean-edges.test.mjs
//                                                the private brand art, kept at the
//                                                same paths under <dir> (tests/art/art.mjs)
import { existsSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readPng, gauss, components, ART_ROOT, isPlaceholder, isClearPlaceholder } from './art.mjs';

let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}

const root = fileURLToPath(new URL('../../', import.meta.url));
const other = process.argv[2];
const at = p => (other ? join(other, basename(p)) : join(root, p));
// the brand art: from ART_ROOT when given; otherwise what is here is a stand-in
const brand = p => (other ? join(other, basename(p)) : join(ART_ROOT || root, p));
const standIn = !other && !ART_ROOT;
let stoodIn = 0;
// clear: the stand-in may also be fully transparent (the icon's front layer)
function checkStandIn(p, clear = false) {
  stoodIn++;
  const path = join(root, p);
  if (!existsSync(path)) { check(`${p}: not in the repository (private)`, true); return; }
  const img = readPng(path);
  check(`${p}: only a plain stand-in here (the art is private)`,
    isPlaceholder(img) || (clear && isClearPlaceholder(img)),
    `${img.width} x ${img.height}, not one colour${clear ? ' or clear' : ''}`);
}
if (standIn) console.log('     the brand art is private: ART_ROOT=<its checkout> measures it');

// The bar. Roughness is how much of the solid body's outline a light
// smoothing (sigma 1.5 px) would move, per pixel of outline: a drawn,
// anti-aliased curve moves almost nowhere; a stepped or notched one does.
// The cut before the clean one (fb24d0e0) measured 0.06 on the light @3x,
// with 18 pixels moved in its worst 12 x 12 patch.
const SOLID = 250;          // alpha at or above this (0.98) is the solid body
const ROUGH = 0.03;         // at most this share of the outline moves
const PATCH = 12;           // the patch the worst place is measured over (px)
const WORST = 9;            // at most this many pixels move in any one patch
const SPECK = 0.01;         // a solid piece smaller than this share of the largest is a speck
const PINHOLE = 0.002;      // an enclosed clear pocket smaller than this share of the image is a pinhole
const NEAR_GROUND = 4;      // a mostly opaque edge pixel this close to the ground's colour is ground left on
const RUN = 3;              // this many of those together is a ring

const LAUNCH = 'ios/RedPen/Assets.xcassets/LaunchLogo.imageset';
const LAYERS = 'design/icon/layers';
const ground = {
  light: [0xE0, 0xE5, 0xEC],
  dark: [0x2A, 0x2E, 0x35],
};
const backgroundOf = suffix => {
  const bg = readPng(at(`${LAYERS}/0-background${suffix}.png`));
  return [bg.data[0], bg.data[1], bg.data[2]];
};

const cuts = [];
for (const [stem, mode] of [['launch-logo', 'light'], ['launch-logo-dark', 'dark']]) {
  for (const n of [1, 2, 3]) cuts.push({ path: `${LAUNCH}/${stem}@${n}x.png`, ground: ground[mode], brand: true });
}
// the stethoscope layers are brand art too; their stand-ins are clear, so the
// base (a plain colour, kept here) shows through in the layered icon
cuts.push({ path: `${LAYERS}/1-stethoscope.png`, ground: () => backgroundOf(''), brand: true, clear: true });
cuts.push({ path: `${LAYERS}/1-stethoscope-dark.png`, ground: () => backgroundOf('-dark'), brand: true, clear: true });

function measure(img, g) {
  const { width: w, height: h, data } = img;
  const n = w * h;
  const solid = new Uint8Array(n);
  for (let i = 0; i < n; i++) solid[i] = data[4 * i + 3] >= SOLID ? 1 : 0;
  // roughness: the solid body against its lightly smoothed self
  const smooth = gauss(Float64Array.from(solid), w, h, 1.5);
  const moved = new Uint8Array(n);
  let move = 0, outline = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * w + x;
      if ((smooth[i] > 0.5 ? 1 : 0) !== solid[i]) { moved[i] = 1; move++; }
      if (solid[i] && (x === 0 || y === 0 || x === w - 1 || y === h - 1
          || !solid[i - 1] || !solid[i + 1] || !solid[i - w] || !solid[i + w])) outline++;
    }
  }
  // the worst patch, from running sums
  const sum = new Int32Array((w + 1) * (h + 1));
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      sum[(y + 1) * (w + 1) + x + 1] = moved[y * w + x] + sum[y * (w + 1) + x + 1]
        + sum[(y + 1) * (w + 1) + x] - sum[y * (w + 1) + x];
    }
  }
  let worst = 0, worstAt = [0, 0];
  for (let y = PATCH; y <= h; y++) {
    for (let x = PATCH; x <= w; x++) {
      const v = sum[y * (w + 1) + x] - sum[(y - PATCH) * (w + 1) + x]
        - sum[y * (w + 1) + x - PATCH] + sum[(y - PATCH) * (w + 1) + x - PATCH];
      if (v > worst) { worst = v; worstAt = [x - PATCH / 2, y - PATCH / 2]; }
    }
  }
  // specks: solid pieces far smaller than the mark
  const pieces = components(solid, w, h);
  const largest = Math.max(...pieces.sizes.slice(1));
  const specks = [];
  for (let k = 1; k <= pieces.count; k++) if (pieces.sizes[k] < SPECK * largest) specks.push(pieces.sizes[k]);
  // pinholes: small clear pockets the solid body closes round
  const clear = solid.map(v => 1 - v);
  const pockets = components(clear, w, h);
  const open = new Set();
  for (let x = 0; x < w; x++) { open.add(pockets.label[x]); open.add(pockets.label[(h - 1) * w + x]); }
  for (let y = 0; y < h; y++) { open.add(pockets.label[y * w]); open.add(pockets.label[y * w + w - 1]); }
  const pinholes = [];
  for (let k = 1; k <= pockets.count; k++) if (!open.has(k) && pockets.sizes[k] < PINHOLE * n) pinholes.push(pockets.sizes[k]);
  // a ring of the ground round the mark: mostly opaque pixels of the
  // ground's own colour at the edge (within 2 px of the clear outside). The
  // grey tube's shaded side is near the dark ground's colour, so a pixel or
  // two of its edge can be too; a ring is a run of them.
  const ringAt = new Uint8Array(n);
  let ring = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * w + x;
      if (data[4 * i + 3] < 128 || Math.abs(data[4 * i] - g[0]) > NEAR_GROUND
          || Math.abs(data[4 * i + 1] - g[1]) > NEAR_GROUND || Math.abs(data[4 * i + 2] - g[2]) > NEAR_GROUND) continue;
      let byClear = false;
      for (let dy = -2; dy <= 2 && !byClear; dy++) {
        for (let dx = -2; dx <= 2; dx++) {
          const xx = x + dx, yy = y + dy;
          if (dx * dx + dy * dy > 4 || xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          if (data[4 * (yy * w + xx) + 3] < 13) { byClear = true; break; }
        }
      }
      if (byClear) { ringAt[i] = 1; ring++; }
    }
  }
  const runs = components(ringAt, w, h);
  const longestRun = runs.count ? Math.max(...runs.sizes.slice(1)) : 0;
  return { rough: move / Math.max(outline, 1), worst, worstAt, specks, pinholes, ring, longestRun, outline };
}

let measured = 0;
for (const cut of cuts) {
  if (cut.brand && standIn) { checkStandIn(cut.path, cut.clear); continue; }
  const path = cut.brand ? brand(cut.path) : at(cut.path);
  if (!existsSync(path)) { if (!other) check(`${cut.path} exists`, false, 'missing'); continue; }
  const img = readPng(path);
  const g = typeof cut.ground === 'function' ? cut.ground() : cut.ground;
  const m = measure(img, g);
  measured++;
  const name = basename(cut.path);
  console.log(`     ${name}: roughness ${m.rough.toFixed(3)}, worst patch ${m.worst} px at (${m.worstAt.join(', ')}), `
    + `specks ${m.specks.length}, pinholes ${m.pinholes.length}, ground at the edge ${m.ring}`);
  check(`${name}: a smooth outline (roughness ${m.rough.toFixed(3)} <= ${ROUGH})`, m.rough <= ROUGH, `${m.rough.toFixed(3)}`);
  check(`${name}: no stepped or notched place (worst ${PATCH}x${PATCH} patch ${m.worst} <= ${WORST})`, m.worst <= WORST,
    `${m.worst} px at (${m.worstAt.join(', ')})`);
  check(`${name}: no specks`, m.specks.length === 0, `sizes ${m.specks.join(', ')}`);
  check(`${name}: no pinholes`, m.pinholes.length === 0, `sizes ${m.pinholes.join(', ')}`);
  check(`${name}: no ring of the ground's colour at the edge (${m.ring} px, none in a run of ${RUN})`,
    m.longestRun < RUN && m.ring <= 0.001 * m.outline, `${m.ring} px, the longest run ${m.longestRun}`);
}
if (standIn) check('every cut was checked as a stand-in', stoodIn === cuts.length, `${stoodIn} of ${cuts.length}`);
else check('every cut was measured', measured > 0);

// The opaque icons: square, solid, and the layers put back together (the
// layers are cut from them, so a stale layer or icon shows here).
if (!other) {
  for (const [look, suffix] of [['light', ''], ['dark', '-dark']]) {
    const fg = readPng(brand(`${LAYERS}/1-stethoscope${suffix}.png`));
    const bg = readPng(at(`${LAYERS}/0-background${suffix}.png`));
    for (const icon of [`ios/AppResources/AppIcon.icon/Assets/icon-${look}.png`,
                        `ios/RedPen/Assets.xcassets/AppIcon.appiconset/icon-1024${suffix}.png`]) {
      if (standIn) { checkStandIn(icon); continue; }
      const img = readPng(brand(icon));
      const name = icon.split('/').slice(-2).join('/');
      check(`${name} is 1024 x 1024`, img.width === 1024 && img.height === 1024, `${img.width} x ${img.height}`);
      let clearest = 255, off = 0;
      for (let i = 0; i < img.width * img.height; i++) {
        clearest = Math.min(clearest, img.data[4 * i + 3]);
        const a = fg.data[4 * i + 3] / 255;
        for (let c = 0; c < 3; c++) {
          const back = Math.round(fg.data[4 * i + c] * a + bg.data[4 * i + c] * (1 - a));
          off = Math.max(off, Math.abs(back - img.data[4 * i + c]));
        }
      }
      check(`${name} is opaque`, clearest === 255, `alpha down to ${clearest}`);
      check(`${name} is its layers put together, within 2/255`, off <= 2, `off by ${off}`);
    }
  }
}

console.log(failed ? `\n${failed} CLEAN EDGE FAILURE(S)` : '\nALL CLEAN EDGE TESTS PASS');
process.exit(failed ? 1 : 0);
