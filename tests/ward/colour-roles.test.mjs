// The colour roles (docs/design/colour-roles.md, task T0134): which of the
// owner's ten hexes each role takes, the same on iPhone and Android. The
// owner, 23 Oct 2026: there is "little to no colour consistency across the
// app"; D1, words on the page are ink and colour goes on icons, edges and
// fills; D7 (30 Oct), a right answer takes the mode's colour in every mode,
// Questions' coral too; D8 (30 Oct), a chosen chip or segment is filled with
// the accent under near-black words. This reads the iPhone's Swift sources
// and fails when a screen
// - names a mode's colour other than its own (a Cards screen with a red ring),
// - draws a colour literal (a hex, an RGB or a system colour) outside the art
//   and export files listed below,
// - marks a right answer in Fresh Mint rather than the mode's colour
//   (wardPrimaryInk), or through a second right-answer colour,
// - or sets one line of words in an accent.
// Android's ColourRolesTest holds the same rules over its sources.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const app = join(repo, 'ios/RedPen');
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}

function swiftFiles(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...swiftFiles(p));
    else if (name.endsWith('.swift')) out.push(p);
  }
  return out;
}
// the screens and the shared pieces they are built from; the Ward token
// layer is where the roles are defined, and the tests read colours on purpose
const sources = [...swiftFiles(join(app, 'Features')), ...swiftFiles(join(app, 'Shared'))]
  .map(p => relative(app, p))
  .filter(p => !p.startsWith('Shared/Ward/'));
const read = rel => readFileSync(join(app, rel), 'utf8');

// --- 1. a screen names only its own mode's colour ---------------------------

// a feature folder that belongs to one mode, and that mode's section
const MODE_OF_FOLDER = {
  'Features/MCQ/': 'questions', 'Features/Anki/': 'cards', 'Features/Book/': 'textbook',
  'Features/Cases/': 'cases', 'Features/OSCE/': 'osce', 'Features/Narrate/': 'audio',
  'Features/Notes/': 'ideas',
};
// a mode's own glyph shown outside it: Ideas' glyph beside home's dock
const NAMED_ELSEWHERE = { 'Features/Library/StudyCategory.swift': ['ideas'] };
const SECTIONS = ['questions', 'cards', 'textbook', 'cases', 'osce', 'audio', 'ideas'];
const named = /(?:\.wardSection\(|wardAccent\(|wardEdgeInk\(|WardTone\.accent\(|\.accent\(|WardSection)\s*\.?(questions|cards|textbook|cases|osce|audio|ideas)\b/g;
const strayModes = [];
for (const rel of sources) {
  const text = read(rel).replace(/\/\/.*$/gm, '');
  const own = Object.entries(MODE_OF_FOLDER).find(([dir]) => rel.startsWith(dir))?.[1];
  const allowed = new Set([...(own ? [own] : []), ...(NAMED_ELSEWHERE[rel] ?? [])]);
  for (const m of text.matchAll(named)) {
    if (SECTIONS.includes(m[1]) && !allowed.has(m[1])) strayModes.push(`${rel}: ${m[0]}`);
  }
}
check('every screen names only its own mode\'s colour', strayModes.length === 0, strayModes.join('; '));

// --- 2. no colour literal in a screen -----------------------------------------

// art, exports and printed pages whose colours are not UI roles (the 3D
// scenes, the space backdrop, decks and PDFs, the occlusion covers, the
// example pictures, the brand mark, the sign-in providers' own marks)
const ART = [
  /^Features\/Notes\/Graph/, /^Shared\/Space\//, /^Shared\/Deck/, /^Shared\/PDF/, /^Shared\/PhotoOcclusionReader\.swift$/,
  /^Features\/Examples\/OcclusionExample\.swift$/, /^Features\/Recall\/RecallExamples\.swift$/,
  /^Shared\/AppBackdrop\.swift$/, /^Shared\/Brand\.swift$/, /^Shared\/LaunchSplash\.swift$/,
  /^Features\/Auth\/SignInView\.swift$/, /^Features\/Notes\/NotesShared\.swift$/,
];
const literal = /\b(?:Color|UIColor)\((?:red|hex|white):|\b(?:Color|UIColor)\.(?:red|blue|green|orange|pink|purple|yellow|mint|teal|indigo|cyan|brown)\b|(?:foregroundStyle|foregroundColor|tint|fill|stroke|background)\(\.(?:red|blue|green|orange|pink|purple|yellow|mint|teal|indigo|cyan|brown)\)/;
const literals = [];
for (const rel of sources) {
  if (ART.some(r => r.test(rel))) continue;
  read(rel).split('\n').forEach((line, i) => {
    const code = line.replace(/\/\/.*$/, '');
    // the occlusion covers' own constants (OcclusionCovers) are the palette's
    if (literal.test(code) && !/OcclusionCovers\./.test(code)) literals.push(`${rel}:${i + 1}`);
  });
}
check('no screen draws a colour literal', literals.length === 0, literals.join('; '));

// --- 3. a right answer takes the right answer's role -------------------------

// D7: the mode colour token in every mode, Questions too; no second colour
const tokens = read('Shared/Ward/WardTokens.swift');
const split = sources.concat(['Shared/Ward/WardLook.swift', 'Shared/Ward/WardTokens.swift'])
  .filter(rel => /\bwardRight\b|\brightIsOwn\b/.test(read(rel)));
check('no second right-answer colour (D7: one mode colour token)', split.length === 0, split.join('; '));
const quiz = read('Features/MCQ/ChartQuizViews.swift');
check('the option row draws a right answer in the mode\'s colour',
      /case \.chosen, \.right: return \.wardPrimaryInk/.test(quiz));
const handMint = [];
const mintForRight = /\b(?:correct|right|isRight|ok)\s*\?\s*(?:Color)?\.wardSuccess\b/;
for (const rel of sources) {
  read(rel).split('\n').forEach((line, i) => { if (mintForRight.test(line)) handMint.push(`${rel}:${i + 1}`); });
}
check('no screen marks a right answer in Fresh Mint (D7: the mode\'s colour)', handMint.length === 0, handMint.join('; '));

// --- 4. words on the page are ink (D1) ---------------------------------------

// files another task owns at this commit (T0140), and the chart's clinical
// flags (an abnormal value in red, the owner's targets doc; open with D1)
const D1_LATER = [
  'Features/Library/LibraryView.swift', 'Features/Library/WardHome.swift', 'Features/Mock/MockSittingView.swift',
  'Features/Book/BookReaderView.swift', 'Shared/Theme.swift', 'Features/Library/StudyCategory.swift',
];
const accentWords = /\bText\(.*\.(?:foregroundStyle|foregroundColor)\((?:Color)?\.?(?:wardPrimaryInk|wardSuccess|wardWarning|wardBeam|wardEcg|wardRight|tint)\)/;
const words = [];
for (const rel of sources) {
  if (D1_LATER.includes(rel)) continue;
  read(rel).split('\n').forEach((line, i) => { if (accentWords.test(line)) words.push(`${rel}:${i + 1}`); });
}
check('no line of words is set in an accent', words.length === 0, words.join('; '));

const controls = read('Shared/Ward/WardControls.swift');
check('a Ward button\'s words are ink, its glyph the kind\'s colour',
      /private var ink: Color \{\s*enabled \? \.wardInk : \.wardDisabledInk\s*\}/.test(controls)
      && /\.labelStyle\(WardGlyphLabelStyle\(glyph: glyph\)\)/.test(controls));
check('a chip\'s and a pill\'s words are ink', (controls.match(/\.foregroundStyle\(Color\.wardInk\)/g) ?? []).length >= 3);
const states = read('Shared/Ward/WardControlStates.swift');
check('the states model gives buttons and chips ink words',
      /words: enabled \? \.ink : disabledInk, glyph: enabled \? buttonGlyph : disabledInk/.test(states)
      && /words: enabled \? \.ink : disabledInk, glyph: enabled \? chosenInk : disabledInk/.test(states));

// D8: a chosen chip or segment is filled with the accent, its words near-black
check('the states model fills a chosen chip and segment, near-black words',
      /if state\.isChosen && enabled \{\s*return WardControlLook\(words: \.onAccent, face: \.primary, stand: stand, mark: chosenEdge\)/.test(states)
      && /words: !enabled \? disabledInk : filled \? \.onAccent : \.ink,\s*face: filled \? \.primary/.test(states));
check('the chip and segment faces draw the fill under near-black words',
      /fill: filled \? chosenInk : \.wardSurface/.test(controls) && /fill: filled \? Color\.wardPrimary : Color\.wardWell/.test(controls)
      && (controls.match(/filled \? \.wardOnAccent : \.wardInk/g) ?? []).length >= 3);
check('a chosen filter chip is filled, its words near-black',
      /foregroundStyle\(selected \? Color\.wardOnAccent : Color\.wardInk\)/.test(read('Shared/Ward/WardStates.swift'))
      && /fill: selected \? Color\.wardPrimary : Color\.wardSurface/.test(read('Shared/Ward/WardStates.swift')));

// --- 5. a screen pushed from a mode keeps its colour (T0153 F4) -------------

check('a section mark is held while its screen lives, not dropped when covered',
      /struct WardSectionMark[\s\S]*?WardSectionHold/.test(tokens)
      && !/struct WardSectionMark[\s\S]*?\.onDisappear \{ WardLookStore\.shared\.pop/.test(tokens));

// --- 6. the table both platforms read -----------------------------------------

const page = readFileSync(join(repo, 'docs/design/colour-roles.md'), 'utf8');
for (const [mode, hex] of [['Questions', '#FF6B6B'], ['Cards', '#3B82F6'], ['Textbook', '#14B8A6'], ['Cases', '#FF9F7A'],
                           ['OSCE', '#A3E635'], ['Audio', '#A78BFA'], ['Ideas', '#F472B6']]) {
  check(`the roles page gives ${mode} ${hex}`, new RegExp(`\\| ${mode} \\| [A-Za-z ]+ \\| ${hex} \\|`).test(page));
}

if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log('all passed');
