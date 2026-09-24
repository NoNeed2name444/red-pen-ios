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

// the checker comparison's scoring, and the owner's model switch it relies on
{
  const { score } = await import('../bench/checkers.mjs');
  const { pinnedSource } = await import('../ai.js');
  const s = score([
    { case: 'correct', risk: 1 }, { case: 'correct', risk: 4 },
    { case: 'wrongVsCorrect', risk: 4 }, { case: 'wrongEverywhere', risk: 2 },
    { case: 'wrongEverywhere', risk: null, error: 'x' },
  ]);
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  if (!same(s.specificity, [1, 2]) || !same(s.catchWithLecture, [1, 1]) || !same(s.catchByKnowledge, [0, 1]) || s.failed !== 1) {
    console.log('FAIL checker scoring', s); process.exit(1);
  }
  const env = { FIREBASE_API_KEY: 'k', FIREBASE_PROJECT_ID: 'p', AI: {}, AI_API_KEY: 'h' };
  if (pinnedSource(env, 'gemini:gemini-3.5-flash')?.models?.[0] !== 'gemini-3.5-flash'
      || pinnedSource(env, 'workers-ai:@cf/openai/gpt-oss-120b')?.model !== '@cf/openai/gpt-oss-120b'
      || pinnedSource(env, 'hf:org/model')?.kind !== 'openai'
      || pinnedSource(env, 'nope') !== null || pinnedSource({}, 'gemini:x') !== null) {
    console.log('FAIL model pinning'); process.exit(1);
  }
  const { normalise } = await import('../bench/checkers.mjs');
  const x = normalise('medxpertqa', 5, { question: 'Stem here\nAnswer Choices: (A) a (B) b', options: { A: 'a', B: 'b', C: 'c', D: null }, label: 'B' });
  if (x.question !== 'Stem here' || Object.keys(x.options).join() !== 'A,B,C' || x.answer_idx !== 'B') { console.log('FAIL MedXpertQA shape', x); process.exit(1); }
  console.log('ok   checker comparison scoring, MedXpertQA shape and model pinning');
}

// Google's quota details, passed through so the benchmark can pace itself
{
  const { quotaNote } = await import('../ai.js');
  const note = quotaNote({ error: { details: [
    { '@type': 'type.googleapis.com/google.rpc.QuotaFailure', violations: [{ quotaId: 'GenerateRequestsPerDayPerProjectPerModel-FreeTier', quotaValue: '20' }] },
    { '@type': 'type.googleapis.com/google.rpc.RetryInfo', retryDelay: '41s' },
  ] } });
  if (note !== '[quota GenerateRequestsPerDayPerProjectPerModel-FreeTier=20; retry 41s]' || quotaNote({ error: {} }) !== '') {
    console.log('FAIL quota note', note); process.exit(1);
  }
  console.log('ok   Google quota details are read');
}
