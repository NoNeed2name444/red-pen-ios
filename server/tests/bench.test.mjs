// The benchmark's own arithmetic and parsing: a benchmark that miscounts is
// worse than none.
import { sample, wilson, letterFrom, riskFrom } from '../bench/stats.mjs';
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
ok(letterFrom('The answer is a thiazide diuretic (C)') === null, 'a lower-case "a" in a sentence is not option A');
ok(letterFrom('Option A is unlikely. Option B fits less well, so the best answer is C.') === 'C', 'the last conclusion counts, not the first option mentioned');
ok(letterFrom('Answer: B\nOn reflection the answer is D') === 'D', 'a changed mind is read as the final answer');
ok(riskFrom('[[ ## risk_level ## ]]\n3') === 3 && riskFrom('risk_level: Level 1') === 1, 'the risk level is read like the app reads it');
if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');

// the owner's model switch the verification bench relies on
{
  const { pinnedSource } = await import('../ai.js');
  const env = { FIREBASE_API_KEY: 'k', FIREBASE_PROJECT_ID: 'p', AI: {}, AI_API_KEY: 'h' };
  if (pinnedSource(env, 'gemini:gemini-3.5-flash')?.models?.[0] !== 'gemini-3.5-flash'
      || pinnedSource(env, 'workers-ai:@cf/openai/gpt-oss-120b')?.model !== '@cf/openai/gpt-oss-120b'
      || pinnedSource(env, 'hf:org/model')?.kind !== 'openai'
      || pinnedSource(env, 'nope') !== null || pinnedSource({}, 'gemini:x') !== null) {
    console.log('FAIL model pinning'); process.exit(1);
  }
  console.log('ok   model pinning');
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

// the training run tells a per-day limit from a per-minute one
{
  const { limitKind } = await import('../bench/stats.mjs');
  const ok2 = limitKind('[quota GenerateRequestsPerDayPerProjectPerModel-FreeTier=20; retry 41s]') === 'day'
    && limitKind('[quota GenerateRequestsPerMinutePerProjectPerModel-FreeTier=15; retry 20s]') === 'minute'
    && limitKind('4006: you have used up your daily free allocation of 10,000 neurons') === 'day'
    && limitKind('429: anything', { limit: 'day' }) === 'day' && limitKind('fine') === null;
  if (!ok2) { console.log('FAIL limit handling'); process.exit(1); }
  console.log('ok   limits: per-day stops, per-minute waits');
}
