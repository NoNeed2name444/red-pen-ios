// The checker's evidence from official sources, against fake copies of the
// three services: what is looked up, what is kept, and what the checker sees.
//
// Run: node server/tests/evidence.test.mjs

import { medvalParts, parseTerms, gather, groundedMessages, europePMC, medlinePlus, openFDA, workKey, forgetEvidence, useOpenFDAKey } from '../evidence.js';

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
const twice = async (url) => (url.includes('europepmc') ? new Response(JSON.stringify({ resultList: { result: [
  { title: 'EULAR recommendations for SLE: 2023 update', journalTitle: 'Ann Rheum Dis', pubYear: '2024', doi: '10.1136/ard-2023', abstractText: 'Hydroxychloroquine for all.', source: 'MED', id: '1' },
  { title: 'Eular recommendations for SLE - 2023 update.', journalTitle: 'medRxiv', pubYear: '2023', doi: '10.1101/pre-2023', abstractText: 'Hydroxychloroquine for all (preprint).', source: 'PPR', id: '2' },
  { title: 'Lupus nephritis: a review', journalTitle: 'Lancet', pubYear: '2024', doi: '10.1016/ln', abstractText: 'Mycophenolate or cyclophosphamide.', source: 'MED', id: '3' },
] } }), { status: 200 }) : new Response('', { status: 404 }));
forgetEvidence(); // a different service answering the same lookups
const once = await gather({ queries: ['lupus', 'lupus treatment'], drugs: [] }, twice);
ok(once.length === 2 && once.map(e => e.url).join(' ') === 'https://doi.org/10.1136/ard-2023 https://doi.org/10.1016/ln',
   'one work counts once: found twice, or as a preprint and as published, it is one source (' + once.length + ')');
ok(workKey('') === '' && workKey('A Review (Lancet, 2024)') === workKey('a review.'), 'a work is known by its title, whatever the listing adds');
const silent = await gather({ queries: ['x'], drugs: [] }, async () => { throw new Error('offline'); });
ok(silent.length === 0, 'a source that is down gives no evidence, not an error');

const grounded = groundedMessages([{ role: 'user', content: medval }], evidence);
ok(grounded[0].role === 'system' && grounded[0].content.includes('[S1]') && grounded[0].content.includes('contradicts current evidence'),
   'the checker is told to flag claims that contradict the evidence, citing it');
ok(grounded[0].content.includes('reasoning_issues') && grounded[0].content.includes('Unsupported claim'),
   'and to name a claim neither the lecture nor the evidence supports in the reasoning checks');
ok(groundedMessages([{ role: 'user', content: 'x' }], []).length === 1, 'with no evidence the check is unchanged');

// a day's answers are kept in memory: caches.default does nothing on workers.dev
{
  forgetEvidence();
  const asked = [];
  const counting = async (url, init) => { asked.push(url); return fake(url, init); };
  await openFDA('metformin', counting);
  await openFDA('metformin', counting);
  ok(asked.length === 1, 'the same lookup within a day is answered from memory, not fetched again');
  forgetEvidence();
  useOpenFDAKey('k3y');
  asked.length = 0;
  await openFDA('metformin', counting);
  ok(asked[0]?.endsWith('&api_key=k3y'), 'openFDA is called with the key when one is set');
  await openFDA('metformin', counting);
  ok(asked.length === 1, 'and the answer is kept under the address without the key');
  useOpenFDAKey(undefined);
  forgetEvidence();
}

// "nothing found" and "could not be read" are told apart: proof counts a
// source it could not read as unread, never as one that says nothing
{
  forgetEvidence();
  const asked = [];
  const answering = (status, body = '') => async url => { asked.push(url); return new Response(body, { status }); };
  const missing = answering(404, JSON.stringify({ error: { code: 'NOT_FOUND', message: 'No matches found!' } }));
  const none = await openFDA('nosuchdrug', missing);
  ok(Array.isArray(none) && none.length === 0, 'openFDA\'s 404 is "no label matches": nothing found, not a failure');
  await openFDA('nosuchdrug', missing);
  ok(asked.length === 1, 'and it is remembered like any answer');
  for (const status of [500, 429]) {
    forgetEvidence(); asked.length = 0;
    const down = answering(status);
    ok(await openFDA('metformin', down) === null, `openFDA answering ${status} is a failed lookup (null)`);
    await openFDA('metformin', down);
    ok(asked.length === 2, `and a ${status} is not remembered: the next check asks again`);
  }
  forgetEvidence();
  ok(await openFDA('metformin', async () => { throw new Error('offline'); }) === null, 'openFDA that cannot be reached is a failed lookup');
  ok(await openFDA('metformin', answering(200, 'not json')) === null, 'and so is an answer that is not JSON');

  forgetEvidence();
  const empty = await medlinePlus('zzz', answering(200, '<?xml version="1.0"?><nlmSearchResult><term>zzz</term><count>0</count><list num="0" start="0" per="1"/></nlmSearchResult>'));
  ok(Array.isArray(empty) && empty.length === 0, 'MedlinePlus with no topic for the term: nothing found');
  for (const status of [404, 503]) {
    forgetEvidence();
    ok(await medlinePlus('lupus', answering(status)) === null, `MedlinePlus answering ${status} is a failed lookup`);
  }
  forgetEvidence();
  ok(await medlinePlus('lupus', async () => { throw new Error('offline'); }) === null, 'MedlinePlus that cannot be reached is a failed lookup');
  ok(await medlinePlus('lupus', answering(200, '<html>maintenance</html>')) === null, 'and so is a page that is not its search result');

  forgetEvidence();
  const nothing = await europePMC('zzz', answering(200, JSON.stringify({ hitCount: 0, resultList: { result: [] } })));
  ok(Array.isArray(nothing) && nothing.length === 0, 'Europe PMC with no result: nothing found');
  forgetEvidence();
  ok(await europePMC('zzz', answering(503)) === null, 'Europe PMC answering 503 is a failed lookup');
  forgetEvidence();
  ok(await europePMC('zzz', answering(200, '<html>oops')) === null, 'and so is an answer that is not JSON');
  forgetEvidence();
  const mixed = await gather({ queries: ['lupus'], drugs: ['hydroxychloroquine'] },
    async url => (url.includes('api.fda.gov') ? new Response('', { status: 500 }) : fake(url)));
  ok(mixed.length === 2 && !mixed.some(e => e.source === 'openFDA label'), 'gather keeps what was read when another source fails');
  forgetEvidence();
}

// the full texts kept for proof: a label's sections only when the label is
// the drug's alone, a summary whole or not at all, and neither ever shown to
// a model or sent to the app
{
  let label;
  const labelFake = async () => new Response(JSON.stringify({ results: [label] }), { status: 200 });
  const officialOf = async (generic, drug = 'metformin') => {
    forgetEvidence();
    label = { set_id: 'lbl', effective_time: '20250101', ...(generic === undefined ? {} : { openfda: { generic_name: generic } }),
      indications_and_usage: ['Metformin is indicated for type 2 diabetes mellitus.'], boxed_warning: ['Lactic acidosis.', 7],
      spl_unclassified_section: ['Not a section proof reads.'] };
    return (await openFDA(drug, labelFake))[0]?.official;
  };
  const own = await officialOf(['METFORMIN HYDROCHLORIDE']);
  ok(own?.drug === 'metformin' && own.effective === '20250101'
     && own.sections.indications_and_usage[0] === 'Metformin is indicated for type 2 diabetes mellitus.'
     && own.sections.boxed_warning.join('|') === 'Lactic acidosis.' && !('spl_unclassified_section' in own.sections),
     'a label of the drug alone (its salt aside) keeps the sections proof reads, as the label has them');
  ok(!!(await officialOf(['Metformin', 'METFORMIN HCL'])), 'so does one whose every generic name names the drug alone');
  for (const [generic, drug, what] of [
    [['GLIPIZIDE AND METFORMIN HYDROCHLORIDE'], 'metformin', 'a combination'],
    [['METFORMIN HYDROCHLORIDE', 'GLIPIZIDE AND METFORMIN HYDROCHLORIDE'], 'metformin', 'a combination among its names'],
    [['METFORMIN ER 500 MG'], 'metformin', 'a form in its name'],
    [['WARFARIN SODIUM'], 'warfarin', 'a salt a name does not leave out'],
    [['INSULIN LISPRO'], 'insulin', 'one of a class'],
    [[], 'metformin', 'no generic name'],
    [undefined, 'metformin', 'no openfda record'],
  ]) ok(!(await officialOf(generic, drug)), `${what}: not the drug's own label, so nothing for proof`);

  const summary = '&lt;p&gt;&lt;span class="qt0"&gt;Lupus&lt;/span&gt; is a chronic autoimmune disease.&lt;/p&gt;';
  const xml = body => `<nlmSearchResult><list><document rank="0" url="https://medlineplus.gov/lupus.html"><content name="title">Lupus</content><content name="FullSummary">${body}</content></document></list></nlmSearchResult>`;
  forgetEvidence();
  const whole = await medlinePlus('lupus', async () => new Response(xml(summary), { status: 200 }));
  ok(whole[0].html === summary && whole[0].text === 'Lupus is a chronic autoimmune disease.', 'a MedlinePlus summary is kept whole, as sent, for proof');
  forgetEvidence();
  const long = '&lt;p&gt;' + 'Lupus is a chronic autoimmune disease. '.repeat(1100) + '&lt;/p&gt;';
  const cut = await medlinePlus('lupus', async () => new Response(xml(long), { status: 200 }));
  ok(long.length > 40_000 && cut[0].text.length <= 701 && !('html' in cut[0]), 'one past 40,000 characters is not kept at all, never cut');

  forgetEvidence();
  label = { set_id: 'hcq', openfda: { generic_name: ['HYDROXYCHLOROQUINE'] }, indications_and_usage: ['Hydroxychloroquine is indicated for lupus.'] };
  const both = async url => (url.includes('api.fda.gov') ? labelFake() : new Response(xml(summary), { status: 200 }));
  ok((await openFDA('hydroxychloroquine', both))[0].official && (await medlinePlus('lupus', both))[0].html, 'with both kept by the lookups');
  const shown = await gather({ queries: ['lupus'], drugs: ['hydroxychloroquine'] }, both);
  ok(shown.length === 2 && shown.every(e => !('official' in e) && !('html' in e)), 'the evidence models are shown has neither');
  forgetEvidence();
}

if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
