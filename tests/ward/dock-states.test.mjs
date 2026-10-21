// The dock, the wide iPad's rail, the Ideas pill, the list button at the
// accessibility sizes and Ideas' floating switcher follow the same states
// as every other Ward control (the review's B2; WardControlStates): chosen
// keeps the pressed-in hollow and adds the 2-point accent edge, an unchosen
// enabled item says its words in Chart Ink (not Biro Grey, which is what
// disabled looks like), held sinks with the Ward press (not the system's
// plain-button dimming), and the switcher's collapse chevron is in Chart
// Ink. Reads the Swift sources.
import { readFileSync } from 'node:fs';

const root = new URL('../../ios/RedPen/', import.meta.url).pathname;
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}
const read = (rel) => readFileSync(root + rel, 'utf8');

// the dock's own code: from CategoryDock to the sheet that lists the places
const category = read('Features/Library/StudyCategory.swift');
const start = category.indexOf('struct CategoryDock');
const end = category.indexOf('private struct DockListSheet');
check('found the dock', start > 0 && end > start, `${start} ${end}`);
const dock = category.slice(start, end);
const switcher = read('Shared/FloatingSwitcher.swift');

for (const [name, source] of [['the dock, rail, pill and list button', dock], ['the floating switcher', switcher]]) {
  check(`${name}: no plain button style (held would dim, not sink)`, !/\.buttonStyle\(\.plain\)/.test(source));
  check(`${name}: no Biro Grey on an enabled item`,
        !/foregroundStyle\(Color\.wardInkSecondary\)/.test(source.replace(/SwitcherBadge[\s\S]*$/, '')), 'wardInkSecondary');
}

check('every dock button is a Ward item or panel button',
      (dock.match(/\.buttonStyle\(/g) || []).length === 4
      && (dock.match(/\.buttonStyle\(Ward(Item|Panel)ButtonStyle\(/g) || []).length === 4,
      String((dock.match(/\.buttonStyle\([^\n]*/g) || []).join(' | ')));
check('the dock item and the rail item draw the accent edge on the chosen hollow',
      (dock.match(/\.wardChosenEdge\(segment, true\)\s*\.matchedGeometryEffect\(id: "chosen"/g) || []).length === 2);
check('the Ideas pill is a panel button that is chosen when Ideas is',
      /WardPanelButtonStyle\(chosen: chosen, lift: \.high, shape: shape\)/.test(dock));
check('the face reads the state: Chart Ink, accent when chosen, Biro Grey when disabled',
      /if !enabled \{ return \.wardDisabledInk \}\s*return chosen \? \.wardPrimaryInk : \.wardInk/.test(category));
check('the list button\'s chevron is in Chart Ink',
      /systemName: "chevron\.up"\)\s*\.font\(\.headline\)\s*\.foregroundStyle\(Color\.wardInk\)/.test(dock));

check('every switcher button is a Ward item button',
      (switcher.match(/WardItemButtonStyle\(/g) || []).length === 2 && !/\.buttonStyle\(\.plain\)/.test(switcher));
check('the switcher\'s chosen item has the accent edge in its ink',
      /\.wardChosenEdge\(shape, true, color: tint\)\s*\.matchedGeometryEffect\(id: "switcherLift"/.test(switcher));
check('the switcher\'s unchosen items are in Chart Ink, disabled ones in Biro Grey',
      /!enabled \? Color\.wardDisabledInk : chosen \? tint : Color\.wardInk/.test(switcher));
check('the switcher\'s collapse chevron is in Chart Ink',
      /systemName: "chevron\.down"\)[\s\S]{0,120}\.foregroundStyle\(Color\.wardInk\)/.test(switcher));

// the styles themselves
const controls = read('Shared/Ward/WardControls.swift');
check('the item style sinks a held item and leaves a chosen one in its hollow',
      /if held && !chosen \{\s*WardReliefFace\(shape: shape, lift: \.low, inset: true\)/.test(controls)
      && /\.capPop\(held\)/.test(controls));
check('the panel style presses in when chosen or held, with the edge when chosen',
      /WardPressFace\(shape: shape, lift: enabled \? lift : \.low, pressed: chosen \|\| held\)\s*\.wardChosenEdge\(shape, chosen\)/.test(controls));

if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log('dock-states: all passed');
