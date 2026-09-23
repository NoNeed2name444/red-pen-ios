// The benchmark's own arithmetic and parsing: a benchmark that miscounts is
// worse than none.
import { sample, wilson, letterFrom, riskFrom } from '../bench/accuracy.mjs';
let failures = 0;
const ok = (c, w) => { console.log((c ? 'ok   ' : 'FAIL ') + w); if (!c) failures++; };
const s1 = sample(1273, 150, 7), s2 = sample(1273, 150, 7);
ok(s1.length === 150 && new Set(s1).size === 150 && s1.join() === s2.join(), 'the sample is 150 distinct questions, the same every run');
ok(sample(1273, 150, 8).join() !== s1.join(), 'and a different seed gives a different sample');
const [lo, hi] = wilson(147, 150);
ok(lo > 0.94 && lo < 0.95 && hi > 0.99, '98% of 150 is only proven down to about 94%');
const [lo2] = wilson(990, 1000);
ok(lo2 > 0.98, '99% of 1000 proves more than 98%');
ok(letterFrom('{"answer":"c","reason":"x"}') === 'C', 'the answer letter is read from JSON');
ok(letterFrom('The answer is (B) because') === 'B', 'or from prose');
ok(letterFrom('no idea') === null, 'no letter is no answer, not a guess');
ok(riskFrom('[[ ## risk_level ## ]]\n3') === 3 && riskFrom('risk_level: Level 1') === 1, 'the risk level is read like the app reads it');
if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
