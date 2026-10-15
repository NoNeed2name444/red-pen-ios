// The open stand-in for Jev (§22a): Layer 7, the oath check from our own
// rules and the source proof, fail closed (server/oath.js); and Layer 6's
// triage maths (tools/jev-standin/triage-lib.mjs). The model scoring for
// Layer 6 runs on GitHub Actions (jev-standin.yml); its plumbing is tested
// here with score_nli.py's --dry scorer when Python is there.
//
// Run: node tests/jev-standin/standin.test.mjs
import { readFileSync, writeFileSync, mkdtempSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { oathCheck, oathText, OATH_SECTIONS } from '../../server/oath.js';
import { oathWithJev } from '../../server/jev.js';
import { measure } from '../../tools/jev-standin/oath-bench.mjs';
import { questionFeatures, cardFeatures, triage, half, balanced, kappa, tune, labelsNeeded } from '../../tools/jev-standin/triage-lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };

// MARK: Layer 7, the oath check
{
  const seed = readFileSync(join(root, 'tools/jev-standin/oath-seed.jsonl'), 'utf8').split('\n').filter(Boolean).map(l => JSON.parse(l));
  const m = measure(seed);
  ok(m.fn === 0 && m.tp >= 30, `every oath claim of the seed set is caught (${m.tp}/${m.tp + m.fn}), a miss would block launch`);
  ok(m.fp === 0, `and no plain fact is called one (${m.tn} of them)`);
  ok(oathCheck('Give 0.3 mg × 10⁻³ per kilogram.').why.includes('unreadable') && oathCheck('Platelets 50 x 109/L').oath,
     'fail closed: a number that cannot be read for certain (a superscript, a lost power of ten) is an oath claim');
  ok(oathCheck({ get kind() { throw new Error('bad'); } }).oath, 'fail closed: an error is an oath claim');
  ok(oathCheck('Warfarin is a vitamin K antagonist.', { quotes: [{ section: 'dosage_and_administration' }] }).why.includes('label section')
     && !oathCheck('Warfarin is a vitamin K antagonist.', { quotes: [{ section: 'description' }] }).oath && OATH_SECTIONS.has('contraindications'),
     'a claim the proof found in a label\'s dosing or safety section is an oath claim, whatever its words');
  ok(oathText({ kind: 'mcq', stem: 'S', options: ['a', 'b'], explanation: 'E' }) === 'S\na\nb\nE' && oathText({ kind: 'card', text: 'T' }) === 'T',
     'a question is read with its options and explanation');
  ok(oathWithJev(false, 0.95) && oathWithJev(true, 0.0) && !oathWithJev(false, 0.5), 'Jev, when it is there, can only add the oath check');
}

// MARK: Layer 6, the triage
{
  const f = questionFeatures([0.2, 0.7, 0.1], 0);
  ok(f.key === 0.2 && f.best === 0.7 && Math.abs(f.margin + 0.5) < 1e-9 && f.rank === 1, 'a question: the key\'s score, the best other, the margin, its rank');
  ok(questionFeatures([0.1, 0.2], 5) === null && questionFeatures([NaN, 1], 0) === null && cardFeatures('x') === null, 'unreadable scores give no features');
  ok(triage(null, { suspect: 0, pass: 1 }) === 'review', 'no features: review, never pass');
  const t = { suspect: -0.2, pass: 0.3 };
  ok(triage({ margin: -0.5 }, t) === 'suspect' && triage({ margin: 0 }, t) === 'review' && triage({ margin: 0.4 }, t) === 'pass', 'suspect, review, pass by the margin');
  ok(half('medqa:1#right') === half('medqa:1#wrong'), 'an item and its wrong-key twin fall in the same half');
  // a synthetic labelled set where the margin tells right from wrong, mostly
  let s = 3;
  const r = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  const rows = [];
  for (let i = 0; i < 400; i++) {
    const right = { id: `q${i}#right`, truth: 'right', f: { margin: 0.4 * r() - 0.05 } };
    const wrong = { id: `q${i}#wrong`, truth: 'wrong', f: { margin: -0.4 * r() + 0.05 } };
    rows.push(right, wrong);
  }
  const tuned = tune(rows);
  ok(tuned.fit.n + tuned.held.n === 800 && tuned.held.balanced > 0.8 && tuned.held.kappa > 0.6,
     `tuned on one half, confirmed on the other (held out: balanced ${tuned.held.balanced.toFixed(3)}, kappa ${tuned.held.kappa.toFixed(3)})`);
  ok(tuned.fit.passWrong === 0, '"pass" is set above every wrong item it was tuned on');
  ok(balanced([], t) === 0 && kappa([], t) === 0, 'no labels, no score');
  const need = labelsNeeded(0.01);
  ok(need.tune === 300 && need.kappa === 200 && need.positivesForRecall === 299, 'labels needed: 300 per gate, 200 for kappa, 299 oath claims for recall 0.99 at 95%');
}

// MARK: the batch plumbing, end to end with the dry scorer
{
  const py = spawnSync('python3', ['--version']);
  if (py.status !== 0) console.log('skip the dry run: no python3 here');
  else {
    const dir = mkdtempSync(join(tmpdir(), 'standin-'));
    const items = [];
    for (let i = 0; i < 30; i++) {
      items.push({ id: `x${i}#right`, kind: 'mcq', stem: `Stem ${i}`, options: ['A', 'B', 'C'], key: 0, truth: 'right' });
      items.push({ id: `x${i}#wrong`, kind: 'mcq', stem: `Stem ${i}`, options: ['A', 'B', 'C'], key: 1, truth: 'wrong' });
    }
    items.push({ id: 'card1', kind: 'card', front: 'Antidote to heparin?', back: 'Protamine' });
    writeFileSync(join(dir, 'items.jsonl'), items.map(x => JSON.stringify(x)).join('\n') + '\n');
    const scored = spawnSync('python3', ['-I', join(root, 'tools/jev-standin/score_nli.py'), '--dry', '--items', join(dir, 'items.jsonl'), '--out', join(dir, 'scores.jsonl')], { encoding: 'utf8' });
    const scores = existsSync(join(dir, 'scores.jsonl')) ? readFileSync(join(dir, 'scores.jsonl'), 'utf8').trim().split('\n').map(l => JSON.parse(l)) : [];
    ok(scored.status === 0 && scores.length === 61 && scores[0].scores.length === 3 && scores[60].scores.length === 1,
       'score_nli.py --dry scores every option of every question, and a card once');
    const tri = spawnSync('node', [join(root, 'tools/jev-standin/triage.mjs'), '--items', join(dir, 'items.jsonl'), '--scores', join(dir, 'scores.jsonl'), '--out', dir], { encoding: 'utf8' });
    const th = existsSync(join(dir, 'thresholds.json')) ? JSON.parse(readFileSync(join(dir, 'thresholds.json'), 'utf8')) : null;
    ok(tri.status === 0 && th && th.thresholds?.all && th.labelled === 60 && /never verifies/.test(readFileSync(join(dir, 'report.md'), 'utf8')),
       'triage.mjs tunes each gate on its labels and writes its report and thresholds');
  }
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
