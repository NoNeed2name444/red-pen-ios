// A List row's traits (listRowInsets, listRowBackground, listRowSeparator,
// frostedListRow, wardRowBackground, wardCardRow, wardButtonRow) have to be
// the row's outermost modifiers: the List reads them off the row's own view,
// and when a custom modifier like `wardPart` wraps them it no longer sees
// them, so the row falls back to the system cell (the Ward pass's N1: set
// rows lost their tile). So in a modifier chain no row trait may come
// before a `.wardPart(`; the part goes first, the traits after. Reads the
// Swift sources.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('../../ios/RedPen/', import.meta.url).pathname;
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}

const TRAIT = /\.(listRow[A-Za-z]*|frostedListRow|wardRowBackground|wardCardRow|wardButtonRow)\(/;

/// Lines (1-based) of a row trait that sits before a wardPart in one chain.
export function misplaced(text) {
  const lines = text.split('\n');
  const found = new Set();
  lines.forEach((line, i) => {
    const at = line.indexOf('.wardPart(');
    const t0 = line.trimStart();
    if (at < 0 || t0.startsWith('//') || t0.startsWith('func ')) return;
    if (TRAIT.test(line.slice(0, at))) found.add(i + 1);
    const indent = line.length - t0.length;
    for (let j = i - 1; j >= 0; j--) {
      const t = lines[j].trimStart();
      const ind = lines[j].length - t.length;
      if (t === '' || ind !== indent) break;
      if (t.startsWith('//')) continue;
      if (!t.startsWith('.')) break;
      if (TRAIT.test(t)) found.add(j + 1);
    }
  });
  return [...found];
}

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((n) => {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) return n === 'Tests' ? [] : swiftFiles(p);
    return n.endsWith('.swift') ? [p] : [];
  });
}

// the check itself catches the old order and passes the fixed one
const old = `
        .listRowInsets(EdgeInsets())
        .frostedListRow()
        // the tile
        .wardPart("a set row", reach: 4)
        .contextMenu { }
`;
const oneLine = `        row.frostedListRow().wardPart("x")`;
const fixed = `
        .wardPart("a set row", reach: 4)
        // the tile
        .listRowInsets(EdgeInsets())
        .frostedListRow()
`;
const plain = `
        .accessibilityIdentifier("x")
        .wardPart("a heading")
`;
check('traits before wardPart are caught', misplaced(old).length === 2, misplaced(old).join());
check('traits before wardPart on one line are caught', misplaced(oneLine).length === 1);
check('traits after wardPart pass', misplaced(fixed).length === 0);
check('a part with no traits passes', misplaced(plain).length === 0);

let parts = 0;
for (const file of swiftFiles(root)) {
  const text = readFileSync(file, 'utf8');
  parts += (text.match(/\.wardPart\(/g) || []).length;
  const hits = misplaced(text);
  check(`${file.slice(root.length)}: no row trait outside a wardPart`, hits.length === 0,
        `row trait after wardPart at line ${hits.join(', ')}`);
}
check('the app uses wardPart (the check is looking at something)', parts >= 10, `${parts} found`);

if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log('all part-trait checks passed');
