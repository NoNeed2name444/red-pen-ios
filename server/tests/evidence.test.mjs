// The checker's evidence from official sources, against fake copies of the
// three services: what is looked up, what is kept, and what the checker sees.
//
// Run: node server/tests/evidence.test.mjs

import { medvalParts, parseTerms, gather, groundedMessages, europePMC, medlinePlus, openFDA } from '../evidence.js';

let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };

const medval = '...\n[[ ## instruction ## ]]\nWrite an MCQ\n\n[[ ## input ## ]]\nSLE lecture text\n\n[[ ## output ## ]]\nFirst-line for SLE is hydroxychloroquine 400 mg.\n\n[[ ## reasoning ## ]]\n# TO_BE_FILLED_BY_MODEL';
const parts = medvalParts(medval);
ok(parts.output === 'First-line for SLE is hydroxychloroquine 400 mg.' && parts.input === 'SLE lecture text', 'the checked output and the lecture are found in a MedVAL prompt');
ok(medvalParts('just chat') === null, 'an ordinary message is not a check');

const terms = parseTerms('Sure: {"queries":["systemic lupus erythematosus treatment","<script>x"], "drugs":["hydroxychloroquine"]}');
ok(terms.queries[0] === 'systemic lupus erythematosus treatment' && terms.drugs[0] === 'hydroxychloroquine', 'search terms are read from the model reply');
ok(terms.queries[1] === 'script x', 'and cleaned of anything that is not a word');
ok(parseTerms('no json').queries.length === 0, 'an unreadable reply means no lookup, not a failure');

const calls = [];
const fake = async (url) => {
  calls.push(url);
  if (url.includes('europepmc')) return new Response(JSON.stringify({ resultList: { result: [
    { title: 'EULAR recommendations for SLE: 2023 update', journalTitle: 'Ann Rheum Dis', pubYear: '2024', doi: '10.1136/ard-2023', abstractText: 'Hydroxychloroquine is recommended for all patients with SLE at a dose not exceeding 5 mg/kg real body weight per day.', source: 'MED', id: '1' },
  ] } }), { status: 200 });
  if (url.includes('wsearch.nlm.nih.gov')) return new Response('<nlmSearchResult><list><document rank="0" url="https://medlineplus.gov/lupus.html"><content name="title">Lupus</content><content name="FullSummary">&lt;p&gt;Lupus is a chronic autoimmune disease.&lt;/p&gt;</content></document></list></nlmSearchResult>', { status: 200 });
  if (url.includes('api.fda.gov')) return new Response(JSON.stringify({ results: [{ set_id: 'abc', effective_time: '20250101',
    indications_and_usage: ['Hydroxychloroquine is indicated for lupus.'], dosage_and_administration: ['200 mg to 400 mg daily.'] }] }), { status: 200 });
  return new Response('', { status: 404 });
};

const epmc = await europePMC('lupus', fake);
ok(epmc[0].url === 'https://doi.org/10.1136/ard-2023' && epmc[0].text.includes('5 mg/kg'), 'Europe PMC gives the review, its DOI and its abstract');
ok(calls[0].includes('guideline') && calls[0].includes('FIRST_PDATE'), 'and only recent reviews and guidelines are asked for');
const mlp = await medlinePlus('lupus', fake);
ok(mlp[0].url === 'https://medlineplus.gov/lupus.html' && mlp[0].text === 'Lupus is a chronic autoimmune disease.', 'MedlinePlus gives the topic summary, markup removed');
const fda = await openFDA('hydroxychloroquine', fake);
ok(fda[0].text.includes('Dosage: 200 mg to 400 mg daily.') && fda[0].url.includes('setid=abc'), 'openFDA gives the label dose, linked to DailyMed');

const evidence = await gather({ queries: ['lupus treatment'], drugs: ['hydroxychloroquine'] }, fake);
ok(evidence.map(e => e.id).join(',') === 'S1,S2,S3', 'everything found is numbered for citing');
const silent = await gather({ queries: ['x'], drugs: [] }, async () => { throw new Error('offline'); });
ok(silent.length === 0, 'a source that is down gives no evidence, not an error');

const grounded = groundedMessages([{ role: 'user', content: medval }], evidence);
ok(grounded[0].role === 'system' && grounded[0].content.includes('[S1]') && grounded[0].content.includes('contradicts current evidence'),
   'the checker is told to flag claims that contradict the evidence, citing it');
ok(grounded[0].content.includes('reasoning_issues') && grounded[0].content.includes('Unsupported claim'),
   'and to name a claim neither the lecture nor the evidence supports in the reasoning checks');
ok(groundedMessages([{ role: 'user', content: 'x' }], []).length === 1, 'with no evidence the check is unchanged');

if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
