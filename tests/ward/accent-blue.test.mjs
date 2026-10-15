// No Ward screen draws a blue of its own: every accent (button words and
// icons, links, toggles, progress, the chosen tab and chip, focus rings) is
// the section's (WardSection.accent, through Color.wardPrimaryInk and the
// .tint each section sets), so a screen in Cards or OSCE never shows the
// Questions blue. The owner saw exactly that (14 Oct): blue words in other
// sections. This reads the Swift sources; WardLookTests checks the colours.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = new URL('../../ios/RedPen/', import.meta.url).pathname;
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
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
// asset (Questions' blue in every section), or a colour argument of .blue.
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
check('WardTone .info is the fixed New blue', /case \.info: return \.wardInfo/.test(controls));
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
check('the New chip keeps the fixed blue', /case \.new: tone = \.info/.test(home));

if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log('all passed');
