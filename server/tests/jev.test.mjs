// Jev for the oath check (jev.js): inert without its key and Pro money; a
// yes only adds the check; anything slow, refused or unreadable changes
// nothing.
//
// Run: node server/tests/jev.test.mjs

import { jevOath, jevAvailable, oathWithJev, OATH_YES } from '../jev.js';

let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };

let calls = 0, lastBody = null;
const answering = (body, status = 200, delay = 0) => async (url, init) => {
  calls++;
  lastBody = JSON.parse(init.body);
  if (delay) await new Promise((resolve, reject) => {
    const t = setTimeout(resolve, delay);
    init.signal?.addEventListener('abort', () => { clearTimeout(t); reject(new Error('aborted')); });
  });
  return new Response(JSON.stringify(body), { status });
};
const yes = p => ({ model: 'jev-1.13.0', answers: { oath: { type: 'noul', noul: p } } });
const paying = { JEV_API_KEY: 'k', PRO_PAYS: 'on' };

ok(!(await jevAvailable({})) && !(await jevAvailable({ JEV_API_KEY: 'k' })) && !(await jevAvailable({ PRO_PAYS: 'on' })),
   'without its key, or without Pro money for paid calls, Jev is not available');
calls = 0;
ok(await jevOath({ PRO_PAYS: 'off', JEV_API_KEY: 'k' }, 'Give 1 g stat', answering(yes(0.99))) === null && calls === 0,
   'and is never called then');

ok(await jevOath(paying, 'Start ceftriaxone for meningitis', answering(yes(0.97))) === 0.97, 'a yes comes back as its probability');
ok(lastBody.questions.oath.type === 'noul' && lastBody.model === 'jev-latest' && typeof lastBody.state === 'string',
   'asked as one yes/no question about the item, as the API describes');
ok(await jevOath(paying, 'x', answering(yes(0.97), 429)) === null, 'a refusal changes nothing');
ok(await jevOath(paying, 'x', answering({ answers: { oath: { type: 'choice', choice: 'yes' } } })) === null,
   'an answer of the wrong type changes nothing');
ok(await jevOath(paying, 'x', answering(yes(1.4))) === null, 'nor does a "probability" outside 0 to 1');
const started = Date.now();
ok(await jevOath({ ...paying, JEV_TIMEOUT_MS: '50' }, 'x', answering(yes(0.99), 200, 2000)) === null && Date.now() - started < 1000,
   'a slow answer is given up on at the timeout');

ok(oathWithJev(true, null) && oathWithJev(true, 0.01), 'what the patterns hold stays held, whatever Jev says');
ok(oathWithJev(false, OATH_YES) && !oathWithJev(false, OATH_YES - 0.01) && !oathWithJev(false, null),
   'Jev adds the check only when it is confident, and never when it did not answer');

console.log(failures ? `\n${failures} JEV TEST FAILURE(S)` : '\nALL JEV TESTS PASS');
process.exit(failures ? 1 : 0);
