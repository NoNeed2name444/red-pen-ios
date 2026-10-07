// The Terms of use and the Privacy policy (legal.js): served as pages, and
// saying what the code does - every retention period the policy states is
// read here from the module that enforces it, so changing one without the
// page fails this test.
//
// Run: node server/tests/legal.test.mjs

import worker from '../worker.js';
import { TERMS, PRIVACY, legalPage } from '../legal.js';
import { SUPPORT_KEEP_DAYS, REPORTS_KEEP_DAYS, RELEASED_KEEP_DAYS } from '../limits.js';
import { KEEP_DAYS as DIAGNOSTICS_KEEP_DAYS } from '../diagnostics.js';
import { LIMITS as JOB_LIMITS } from '../jobs.js';

let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };

for (const [path, title] of [['/terms', 'Terms of use'], ['/privacy', 'Privacy policy']]) {
  const res = await worker.fetch(new Request(`https://w${path}`), {});
  const html = await res.text();
  ok(res.status === 200 && res.headers.get('content-type').startsWith('text/html'), `${path} is a page`);
  ok(html.includes(`<h1>${title}</h1>`) && html.includes('href="/terms"') && html.includes('href="/privacy"'),
     `${path} has its title and links to both pages`);
}
ok((await worker.fetch(new Request('https://w/terms', { method: 'POST', body: '{}' }), {})).status !== 200,
   'only a GET reads a page');
ok(legalPage('/nothing') === null, 'no other path is a page');

const days = n => `${n} days`;
ok(PRIVACY.includes(`up to ${days(REPORTS_KEEP_DAYS)}`), 'question reports: the policy states the period limits.js keeps them');
ok(PRIVACY.includes(`kept for up to ${days(SUPPORT_KEEP_DAYS)}.</li>`), 'Contact us messages: likewise');
ok(PRIVACY.includes(`kept for up to ${days(DIAGNOSTICS_KEEP_DAYS)}`), 'crash and failure reports: the period diagnostics.js keeps them');
ok(PRIVACY.includes(`purchase, with no name or email, for up to ${days(RELEASED_KEEP_DAYS)}`), "a deleted account's sign-in identifier: the period limits.js keeps it");
const words = { 7: 'seven' };
ok(PRIVACY.includes(`at most ${words[JOB_LIMITS.keepDays] || JOB_LIMITS.keepDays} days`), 'uncollected generations: the period jobs.js keeps them');
ok(TERMS.includes('It is not a medical tool') && PRIVACY.includes('no tracking'), 'the two promises the app makes on its first screen are here too');

console.log(failures ? `\n${failures} LEGAL TEST FAILURE(S)` : '\nALL LEGAL TESTS PASS');
process.exit(failures ? 1 : 0);
