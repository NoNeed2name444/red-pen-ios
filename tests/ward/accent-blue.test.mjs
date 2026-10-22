// No Ward screen draws a blue of its own: every accent (button words and
// icons, links, toggles, progress, the chosen tab and chip, focus rings) is
// the section's (WardSection.accent, through Color.wardPrimaryInk and the
// .tint each section sets), so a screen in OSCE never shows the primary's
// indigo (Cards' own since palette direction 3). The owner saw exactly that
// (14 Oct): blue words in other sections. And every section's colour reads
// (WCAG AA) in light and dark: its words 4.5:1 on every tier, as large text
// or an icon 3:1, its on-fill words 4.5:1 on its fill, its ink 3:1 as a control's
// edge; and it is told apart from the other sections and from what means
// something (right, wrong, due, the ECG red, the beam). This reads the Swift
// sources: WardPalette's table, WardLook's section table (written by
// tools/ward_accents.py) and WardRelief's edge strengths.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { execFileSync } from 'node:child_process';

const root = new URL('../../ios/RedPen/', import.meta.url).pathname;
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}

// The owner, 22 Oct 2026, about 3:44 AM Cairo, shown that the exact colours
// fail the readability checks: "STOP IMPROVISING DONT CHANGE THE COLORS I
// GAVE U". So every colour is the owner's hex as given, white words on the
// fills included, on the plain ground. A check below that falls short only
// because of that passes only as its exact case on the owner's list
// (tests/ward/owner-accepted.json, under this file's name), measured within
// 0.01 of the value recorded there. Any other case still fails, and so does
// a listed case no check here measures short.
const ownerFile = new URL('./owner-accepted.json', import.meta.url).pathname;
let ownerList = {};
try { ownerList = JSON.parse(readFileSync(ownerFile, 'utf8'))['tests/ward/accent-blue.test.mjs'] ?? {}; } catch { ownerList = {}; }
const ownerSeen = new Set();
// true only when `measured`, short of its check's threshold, is the owner's
// accepted case `key` at the value recorded for it
function owner(key, measured) {
  ownerSeen.add(key);
  if (!(key in ownerList)) { console.log(`owner-accepted miss: ${JSON.stringify(key)}: ${measured.toFixed(3)}`); return false; }
  if (Math.abs(measured - ownerList[key]) > 0.01) {
    console.log(`owner-accepted moved: ${JSON.stringify(key)}: ${measured.toFixed(3)}, listed ${Number(ownerList[key]).toFixed(3)}`);
    return false;
  }
  return true;
}

// Not Ward screens: the night sky and the 3D map draw their own scenes, and
// the PDF and occlusion exports print fixed colours onto paper.
const skip = [/^Shared\/Space\//, /^Features\/Notes\/Graph/, /^Shared\/Deck/, /^Shared\/PDF/,
              /^Features\/Examples\//, /^Tests\//, /GraphPerf/, /GraphicsQuality/, /LaunchSplash/];

function swiftFiles(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) out.push(...swiftFiles(path));
    else if (name.endsWith('.swift')) out.push(path);
  }
  return out;
}

// A blue that is not the section's: the system blue, the app's AccentColor
// asset (the primary's indigo in every section), or a colour argument of .blue.
// WardTone's own `.blue` case (tone: .blue) is the section accent, so it is
// not matched.
const banned = [
  [/\bColor\.blue\b/, 'Color.blue'],
  [/\bUIColor\.(system)?[bB]lue\b/, 'UIColor blue'],
  [/\.systemBlue\b/, 'systemBlue'],
  [/\baccentColor\b/, 'accentColor (the app-wide asset, not the section)'],
  [/"AccentColor"/, 'the AccentColor asset'],
  [/\b(foregroundStyle|foregroundColor|tint|fill|stroke|background|border|accentColor)\(\s*\.blue\b/, 'a .blue colour argument'],
  [/\?\?\s*\.blue\b/, 'a .blue fallback'],
];

function code(line) {
  // drop a trailing comment, not a "//" inside a string
  let inString = false;
  for (let i = 0; i < line.length - 1; i++) {
    if (line[i] === '"' && line[i - 1] !== '\\') inString = !inString;
    if (!inString && line[i] === '/' && line[i + 1] === '/') return line.slice(0, i);
  }
  return line;
}

const hits = [];
let scanned = 0;
for (const file of swiftFiles(root)) {
  const rel = relative(root, file);
  if (skip.some(re => re.test(rel))) continue;
  scanned++;
  readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
    const text = code(line);
    for (const [re, what] of banned) if (re.test(text)) hits.push(`${rel}:${i + 1} ${what}: ${line.trim()}`);
  });
}
check(`scanned the Ward screens (${scanned} files)`, scanned > 100, String(scanned));
check('no Ward screen draws a blue that is not the section accent', hits.length === 0, '\n  ' + hits.join('\n  '));

// The routes the accent takes all lead to the section's accent.
const read = rel => readFileSync(join(root, rel), 'utf8');
const controls = read('Shared/Ward/WardControls.swift');
check('WardTone .blue is the section accent', /case \.blue: return \.wardPrimaryInk/.test(controls));
check('WardTone has no fixed blue of its own (no .info)', !/case \.info\b|wardInfo/.test(controls + read('Shared/Ward/WardTokens.swift')));
const tokens = read('Shared/Ward/WardTokens.swift');
check('Color.ward(.primaryInk) at rest is the section\'s', /WardRestColors\.color\(token, glide\.to\.section\)/.test(tokens));
check('each section sets the tint to its accent',
      /struct WardSectionMark[\s\S]*?\.tint\(Color\.wardPrimaryInk\)/.test(tokens));
const surfaces = read('Shared/Ward/WardSurfaces.swift');
check('the root controls take the accent as their tint', /func wardControls\(\)[\s\S]*?\.tint\(Color\.wardPrimaryInk\)/.test(surfaces));
const look = read('Shared/Ward/WardLook.swift');
check('the accent tokens are sectioned while the hue shifts',
      /case \.primary: return sectioned[\s\S]*?case \.primaryInk: return sectioned/.test(look));
const theme = read('Shared/Theme.swift');
check('a mode\'s glyph is its section\'s accent', /Color\.wardAccent\(WardSection\(kindRaw: rawValue\)\)/.test(theme));
check('the thin progress bar is the accent', /WardGroove\(fraction: fraction, tint: \.wardPrimaryInk/.test(theme));
const home = read('Features/Library/WardHome.swift');
check('the New chip takes the section\'s accent', /case \.new: tone = \.blue/.test(home));
check('the Cases New chip takes the section\'s accent',
      /case \.new: WardChip\(text: "New", tone: \.blue\)/.test(read('Features/Cases/CaseKit.swift')));
check('no chip or pill is given a fixed blue tone', !/tone: \.info\b/.test(
  swiftFiles(root).map(f => readFileSync(f, 'utf8')).join('\n')));

// --- the colours themselves ------------------------------------------------

const palette = {};
for (const m of read('Shared/Ward/WardPalette.swift').matchAll(/\.(\w+):\s*\(0x([0-9A-Fa-f]{6}),\s*0x([0-9A-Fa-f]{6})\)/g))
  palette[m[1]] = [parseInt(m[2], 16), parseInt(m[3], 16)];
const tiers = /static let tiers: \[WardToken\] = \[([^\]]*)\]/.exec(read('Shared/Ward/WardPalette.swift'))[1]
  .split(',').map(t => t.trim().replace(/^\./, ''));
// 18 tokens since direction 3 added the wrong answer's faded and fadedInk
check('the palette is read (18 tokens, 4 tiers)', Object.keys(palette).length === 18 && tiers.length === 4,
      `${Object.keys(palette).length} ${tiers}`);
const relief = read('Shared/Ward/WardRelief.swift');
const num = name => parseFloat(new RegExp(`static let ${name} = ([0-9.]+)`).exec(relief)[1]);
const edgeAlpha = [num('lightEdge'), num('darkEdge')], edgeContrast = num('edgeContrast');

// Every section, Questions too since direction 3, comes from WardLook's table.
const sections = {};
const pair = '\\(0x([0-9A-F]{6}), 0x([0-9A-F]{6})\\)';
const row = new RegExp(`\\.(\\w+): WardSectionColours\\(hue: (\\d+), ink: ${pair}, accent: ${pair}, fill: ${pair}\\)`, 'g');
for (const m of look.matchAll(row)) {
  const hex = i => [parseInt(m[i], 16), parseInt(m[i + 1], 16)];
  sections[m[1]] = { hue: Number(m[2]), ink: hex(3), accent: hex(5), fill: hex(7) };
}
const names = Object.keys(sections);
check('seven sections are read', names.length === 7, names.join(' '));
check('Questions is in the table, at Vital Coral\'s hue 23', sections.questions?.hue === 23, String(sections.questions?.hue));
check('the primary is Cards\' fill and accent (the look outside any section)',
      [0, 1].every(d => palette.primary[d] === sections.cards.fill[d] && palette.primaryInk[d] === sections.cards.accent[d]));

const channels = h => [(h >> 16) & 255, (h >> 8) & 255, h & 255].map(c => c / 255);
const linear = c => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const luminance = h => { const [r, g, b] = channels(h).map(linear); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
const ratio = (a, b) => { const [x, y] = [luminance(a), luminance(b)]; return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
// a control's edge: the ink laid on the ground at the edge's strength, in
// sRGB, as WardRelief.composite does
const composite = (top, alpha, base) => {
  const [b, t] = [channels(base), channels(top)];
  return b.reduce((out, x, i) => (out << 8) | Math.round((x + (t[i] - x) * alpha) * 255), 0);
};
const oklab = h => {
  const [r, g, b] = channels(h).map(linear);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
          1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
          0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s];
};
const distance = (a, b) => Math.hypot(...oklab(a).map((v, i) => v - oklab(b)[i]));
const hueOf = h => { const [, a, b] = oklab(h); return ((Math.atan2(b, a) * 180) / Math.PI + 360) % 360; };
const apart = (a, b) => { const d = Math.abs(a - b) % 360; return Math.min(d, 360 - d); };
const hex = h => '#' + h.toString(16).toUpperCase().padStart(6, '0');

// told apart at a glance: 0.10 would be clearly apart; 0.076 is the most
// these hue families give at text contrast (tools/ward_accents.py)
const APART = 0.075;
const meanings = ['success', 'danger', 'warning', 'ecg', 'beam'];
for (const dark of [0, 1]) {
  const mode = dark ? 'dark' : 'light';
  for (const name of names) {
    const s = sections[name];
    const accent = s.accent[dark];
    // the lowest tier, and which it is (the first, on a tie)
    const [low, lowTier] = tiers.map(t => [ratio(accent, palette[t][dark]), t]).reduce((a, b) => (b[0] < a[0] ? b : a));
    const words = `${mode} ${name}: its words read 4.5:1 on every tier (AA body text)`;
    check(words, low >= 4.5 || owner(`${words} [${lowTier}]`, low), `${hex(accent)} ${low.toFixed(2)} on the ${lowTier}`);
    const large = `${mode} ${name}: as large text or an icon, 3:1 on every tier`;
    check(large, low >= 3 || owner(`${large} [${lowTier}]`, low), `${low.toFixed(2)} on the ${lowTier}`);
    const white = ratio(palette.onPrimary[dark], s.fill[dark]);
    const onFill = `${mode} ${name}: the on-fill words read 4.5:1 on its fill`;
    check(onFill, white >= 4.5 || owner(onFill, white), `${hex(s.fill[dark])} ${white.toFixed(2)}`);
    for (const ground of ['background', 'surface']) {
      const g = palette[ground][dark];
      const edge = ratio(composite(s.ink[dark], edgeAlpha[dark], g), g);
      const label = `${mode} ${name}: its ink reads 3:1 as a control's edge on the ${ground}`;
      check(label, edge >= edgeContrast || owner(label, edge), edge.toFixed(2));
    }
    // a section's colour is its own hue, and never a blue: away from Cards,
    // whose indigo the primary is, it keeps 25 degrees from the primary's hue
    for (const role of ['accent', 'fill', 'ink']) {
      const h = hueOf(s[role][dark]);
      check(`${mode} ${name}: its ${role} is its own hue (${s.hue})`, apart(h, s.hue) <= 2, h.toFixed(1));
      if (name === 'cards') continue;
      const blue = apart(h, sections.cards.hue);
      check(`${mode} ${name}: its ${role} is not a blue`, blue >= 25, blue.toFixed(1));
    }
    // the primary's indigo is Cards' accent, so it is no longer a meaning
    let near = [9, ''];
    for (const k of meanings) {
      const d = distance(accent, palette[k][dark]);
      if (d < near[0]) near = [d, k];
    }
    const meaning = `${mode} ${name}: told apart from what means something`;
    check(meaning, near[0] >= APART || owner(`${meaning} [${near[1]}]`, near[0]), `${near[1]} ${near[0].toFixed(3)}`);
  }
  let closest = [9, ''];
  for (let i = 0; i < names.length; i++)
    for (const b of names.slice(i + 1)) {
      const d = distance(sections[names[i]].accent[dark], sections[b].accent[dark]);
      if (d < closest[0]) closest = [d, `${names[i]}/${b}`];
    }
  check(`${mode}: every section is told apart from the others`, closest[0] >= APART, `${closest[1]} ${closest[0].toFixed(3)}`);
}

// The table is what the generator makes from today's palette, so a palette
// change cannot leave the sections behind.
const tool = new URL('../../tools/ward_accents.py', import.meta.url).pathname;
let current = true, said = '';
try { said = execFileSync('python3', [tool, '--check'], { encoding: 'utf8' }); } catch (e) { current = false; said = String(e.stdout || e.message); }
check('WardLook\'s section table is what tools/ward_accents.py makes', current, said.trim());

// The owner's list holds only cases a check above measured short.
check('the owner\'s list is read (tests/ward/owner-accepted.json, accent-blue.test.mjs)', Object.keys(ownerList).length > 0);
const ownerStale = Object.keys(ownerList).filter(k => !ownerSeen.has(k)).sort();
check('every case on the owner\'s list is one a check here measured short', ownerStale.length === 0, ownerStale.join('; '));

if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log('all passed');
