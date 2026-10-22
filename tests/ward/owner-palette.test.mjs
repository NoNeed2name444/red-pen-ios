// The owner's ten colours, pinned in the roles docs/design/palette-2026-10-21.md
// gives them. The owner, 22 Oct 2026, about 3:44 AM Cairo, shown that the
// exact colours fail the readability checks: "STOP IMPROVISING DONT CHANGE
// THE COLORS I GAVE U". So every iPhone source that carries one of these
// roles carries the owner's hex exactly, by day and at night: a shade, a tint
// or another hex fails here, whatever the readability checks and the owner's
// accepted cases (tests/ward/owner-accepted.json,
// ios/RedPen/Tests/OwnerAccepted.json) say. The page's own table is read too,
// so the page and this pin move together or not at all.
import { readFileSync } from 'node:fs';

const repo = new URL('../../', import.meta.url).pathname;
const read = rel => readFileSync(repo + rel, 'utf8');
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}

// name, hex and role, as the page's table has them
const TEN = [
  ['Pulse Teal', '#14B8A6', 'Textbook; a folder'],
  ['Fresh Mint', '#6EE7B7', 'a right answer (success)'],
  ['Care Blue', '#3B82F6', 'Cards and the primary (the look outside any section); the brand mark (was Theatre Blue); a folder'],
  ['Electric Indigo', '#6366F1', 'a folder (the Space cluster that was slate blue)'],
  ['Soft Lilac', '#A78BFA', 'Audio; a folder'],
  ['Vital Coral', '#FF6B6B', 'Questions; a wrong answer (danger); the ECG red; the red pen'],
  ['Peach Glow', '#FF9F7A', 'Cases; a folder; the occlusion cover'],
  ['Optimistic Amber', '#FBBF24', 'due and warnings; the progress beam; the brand signal'],
  ['Bubblegum Pink', '#F472B6', 'Ideas; a folder'],
  ['Lime Zest', '#A3E635', 'OSCE; a folder'],
];
const hexOf = Object.fromEntries(TEN.map(([name, hex]) => [name, hex]));
const pinned = new Set();
// a role held to one of the ten: every value found must be its hex
function role(label, name, found) {
  pinned.add(name);
  const list = [].concat(found);
  check(`${label}: ${name} ${hexOf[name]}`, list.length > 0 && list.every(v => v === hexOf[name]), list.join(' / ') || 'not found');
}
const hex6 = s => '#' + s.replace(/^(0x|#)/i, '').toUpperCase();
const bytes = (r, g, b) => '#' + [r, g, b].map(x => Math.round(Number(x)).toString(16).toUpperCase().padStart(2, '0')).join('');

// --- the page --------------------------------------------------------------

const page = read('docs/design/palette-2026-10-21.md');
const table = /\| Name \| Hex \| Role \|\n\|---\|---\|---\|\n((?:\|.*\|\n)+)/.exec(page);
const rows = table ? table[1].trim().split('\n').map(r => r.split('|').slice(1, -1).map(c => c.trim())) : [];
check('the page has its table of ten', rows.length === 10, String(rows.length));
const differ = TEN.filter((t, i) => JSON.stringify(rows[i]) !== JSON.stringify(t)).map(t => t[0]);
check('the page\'s ten are these, in this order, in these roles', differ.length === 0, differ.join(', '));

// --- the sections: ink, accent and fill, by day and at night ---------------

const look = read('ios/RedPen/Shared/Ward/WardLook.swift');
const SECTIONS = { questions: 'Vital Coral', cards: 'Care Blue', textbook: 'Pulse Teal', cases: 'Peach Glow',
                   osce: 'Lime Zest', audio: 'Soft Lilac', ideas: 'Bubblegum Pink' };
const pair = '\\(0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6})\\)';
const sectionRow = new RegExp(`\\.(\\w+): WardSectionColours\\(hue: \\d+, ink: ${pair}, accent: ${pair}, fill: ${pair}\\)`, 'g');
const sections = {};
for (const m of look.matchAll(sectionRow)) sections[m[1]] = m.slice(2, 8).map(hex6);
check('WardLook\'s table has the seven sections', Object.keys(sections).sort().join() === Object.keys(SECTIONS).sort().join(),
      Object.keys(sections).join(' '));
for (const [section, name] of Object.entries(SECTIONS))
  role(`${section}'s ink, accent and fill, by day and at night`, name, sections[section] ?? []);
check('the look outside any section is Cards\'', /static let outside: WardSection = \.cards\b/.test(look));

// --- the palette's tokens ----------------------------------------------------

const palette = read('ios/RedPen/Shared/Ward/WardPalette.swift');
const token = t => {
  const m = new RegExp(`\\.${t}:\\s*\\(0x([0-9A-Fa-f]{6}),\\s*0x([0-9A-Fa-f]{6})\\)`).exec(palette);
  return m ? [hex6(m[1]), hex6(m[2])] : [];
};
for (const [t, name, what] of [['primary', 'Care Blue', 'the primary'],
                               ['primaryInk', 'Care Blue', 'the primary\'s words'],
                               ['success', 'Fresh Mint', 'a right answer'],
                               ['danger', 'Vital Coral', 'a wrong answer'],
                               ['ecg', 'Vital Coral', 'the ECG red'],
                               ['warning', 'Optimistic Amber', 'due and warnings'],
                               ['beam', 'Optimistic Amber', 'the progress beam']])
  role(`WardPalette .${t} (${what}), by day and at night`, name, token(t));
check('words on a fill are white, by day and at night', token('onPrimary').join() === '#FFFFFF,#FFFFFF', token('onPrimary').join(' / '));

// the paper's ink outside any section, and the app's AccentColor asset
const relief = read('ios/RedPen/Shared/Ward/WardRelief.swift');
const paperInk = /static func ink\(dark: Bool, highContrast: Bool\) -> WardPaperInk \{[\s\S]*?WardPaperInk\(hex: 0x([0-9A-Fa-f]{6}),/.exec(relief);
role('the paper\'s ink outside any section (WardPaper.ink)', 'Care Blue', paperInk ? [hex6(paperInk[1])] : []);
const accentAsset = JSON.parse(read('ios/RedPen/Assets.xcassets/AccentColor.colorset/Contents.json'));
role('the AccentColor asset, in both appearances', 'Care Blue',
     (accentAsset.colors ?? []).map(c => c.color?.components)
       .map(c => (c ? '#' + [c.red, c.green, c.blue].map(x => String(x).replace(/^0x/i, '').toUpperCase()).join('') : 'not found')));
check('the AccentColor asset has a light and a dark entry', (accentAsset.colors ?? []).length === 2);

// --- the folders (NoteTone), in their stored order: a folder is matched by index

const notes = read('ios/RedPen/Features/Notes/NotesShared.swift');
const toneBlock = /private static let palette: \[\(fill: UInt32, light: UInt32, dark: UInt32\)\] = \[([\s\S]*?)\n {4}\]/.exec(notes);
const tones = toneBlock ? [...toneBlock[1].matchAll(/\(0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6})\)/g)].map(m => m.slice(1, 4).map(hex6)) : [];
const FOLDERS = ['Pulse Teal', 'Electric Indigo', 'Peach Glow', 'Soft Lilac', 'Lime Zest', 'Bubblegum Pink', 'Care Blue'];
check('seven folder colours, the seven the page gives a folder',
      tones.length === 7 && TEN.filter(t => /a folder/.test(t[2])).map(t => t[0]).sort().join() === [...FOLDERS].sort().join(),
      String(tones.length));
FOLDERS.forEach((name, i) => role(`folder ${i + 1}'s colour and its glyph, by day and at night`, name, tones[i] ?? []));

// --- the brand, the occlusion cover, exported decks, the Anki pen, the widget

const colour = (src, name) => {
  const m = new RegExp(`static let ${name} = Color\\(red: ([0-9.]+) / 255, green: ([0-9.]+) / 255, blue: ([0-9.]+) / 255\\)`).exec(src);
  return m ? [bytes(m[1], m[2], m[3])] : [];
};
const brand = read('ios/RedPen/Shared/Brand.swift');
role('the brand signal (Brand.signal)', 'Optimistic Amber', colour(brand, 'signal'));
role('the brand mark (Brand.mark)', 'Care Blue', colour(brand, 'mark'));

const occlusion = read('ios/RedPen/Shared/OcclusionFilter.swift');
const tuple = (src, name) => /static let NAME: \(red: Double, green: Double, blue: Double\) = \(([^)]*)\)/
  .exec(src.replace(/static let (\w+): \(red/g, (all, n) => (n === name ? 'static let NAME: (red' : all)))?.[1].trim() ?? '';
const thirds = text => { const m = /^([0-9.]+) \/ 255, ([0-9.]+) \/ 255, ([0-9.]+) \/ 255$/.exec(text); return m ? [bytes(m[1], m[2], m[3])] : []; };
role('the occlusion cover (OcclusionCovers.targetRGB)', 'Peach Glow', thirds(tuple(occlusion, 'targetRGB')));
check('the cover\'s "?" is white, as words on a fill are', tuple(occlusion, 'markRGB') === '1, 1, 1', tuple(occlusion, 'markRGB'));
const standIn = read('tools/playgrounds_stubs/core-exports-out/CoreExportsStandIns.swift');
for (const name of ['targetRGB', 'markRGB', 'otherRGB'])
  check(`the Playgrounds stand-in's ${name} is the app's`, tuple(standIn, name) !== '' && tuple(standIn, name) === tuple(occlusion, name),
        `${tuple(standIn, name)} vs ${tuple(occlusion, name)}`);

const deck = read('ios/RedPen/Shared/DeckPalette.swift');
for (const [kind, name] of [['mcq', 'Vital Coral'], ['anki', 'Care Blue'], ['book', 'Pulse Teal'],
                            ['osce', 'Lime Zest'], ['narrate', 'Soft Lilac'], ['cases', 'Peach Glow']]) {
  const m = new RegExp(`case \\.${kind}:\\s*return DeckPalette\\(hex: 0x([0-9A-Fa-f]{6})\\)`).exec(deck);
  role(`an exported ${kind} deck (DeckPalette.of)`, name, m ? [hex6(m[1])] : []);
}
check('an exported deck\'s bars and words are its colour itself, no shade',
      /var ink: DeckPalette \{ self \}/.test(deck) && /var barFill: DeckPalette \{ self \}/.test(deck));

const css = /private static let cardCSS = """([\s\S]*?)"""/.exec(read('ios/RedPen/Shared/ApkgExporter.swift'))?.[1] ?? '';
role('the Anki export\'s red pen: the why box\'s rule, its heading and a cloze', 'Vital Coral',
     [/border-left: 3px solid (#[0-9a-fA-F]{6})/, /\.why b \{[^}]*?color: (#[0-9a-fA-F]{6})/, /\.cloze \{[^}]*?color: (#[0-9a-fA-F]{6})/]
       .map(re => re.exec(css)?.[1]).map(v => (v ? hex6(v) : 'not found')));

const glance = read('ios/StethoscoreWidgets/GlanceTimeline.swift');
role('the widget\'s pen (the red pen)', 'Vital Coral', colour(glance, 'pen'));
role('the widget\'s star', 'Care Blue', colour(glance, 'star'));

check('every one of the ten is pinned in a role here', TEN.every(([name]) => pinned.has(name)),
      TEN.filter(([name]) => !pinned.has(name)).map(t => t[0]).join(', '));

if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log('all passed');
