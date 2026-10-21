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

// MARK: the verification bench (tools/verification-bench): T0, docs/verification/rag-plan.md
// Offline: no network, no model. A bench that miscounts is worse than none.
{
  const { spawnSync, execFileSync } = await import('node:child_process');
  const { fileURLToPath } = await import('node:url');
  const { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, statSync, readdirSync } = await import('node:fs');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const bench = new URL('../../tools/verification-bench/', import.meta.url);
  const R = await import(new URL('retrieval-set.mjs', bench));
  const X = await import(new URL('proxy.mjs', bench));
  const G = await import(new URL('gates.mjs', bench));
  const L = await import(new URL('lookup-cache.mjs', bench));
  const P = await import(new URL('proof-only.mjs', bench));
  const Y = await import(new URL('layer.mjs', bench));
  const { DEFAULT_VOTERS } = await import('../accuracy.js');
  let failed = 0;
  const check = (c, w) => { console.log((c ? 'ok   ' : 'FAIL ') + w); if (!c) failed++; };
  const near = (a, b, e = 1e-3) => Math.abs(a - b) <= e;
  const throws = (f, re) => { try { f(); return false; } catch (e) { return re.test(String(e.message)); } };
  const rejects = async (f, re) => { try { await f(); return false; } catch (e) { return re.test(String(e.message)); } };

  // --- the label rules, on fixed examples
  const item = { id: 't1', kind: 'mcq', stem: 'A 60-year-old man has crushing chest pain. An ECG is taken. What is the most likely diagnosis?',
    options: ['Myocardial infarction', 'Pericarditis', 'Aortic dissection', 'Metformin toxicity'], key: 0 };
  // the drugs named come from lookups now (drugsNamed, below), not from labelInputs
  const inputs = { ...R.labelInputs(item, 'Myocardial Infarction'), drugs: ['metformin'] };
  check(inputs.keyWords.join(' ') === 'myocardial infarction' && inputs.meshWords.join(' ') === 'myocardial infarction', 'label inputs: the key\'s words and the MeSH term\'s, normalised');
  check(R.lastSentences(item.stem).startsWith('An ECG is taken.') && !R.lastSentences(item.stem).includes('crushing'), 'the stem\'s last two sentences');
  check(inputs.tail.includes('diagnosis') && inputs.tail.includes('taken') && !inputs.tail.includes('myocardial') && !inputs.tail.includes('likely'), 'the tail: content words of those sentences, never the glue or the key\'s own');
  check(R.drugsIn('Metformin 500 mg or ramipril, or lisinopril').sort().join() === 'lisinopril,metformin,ramipril', 'drugs inside longer options: the engine\'s list and its drug endings');
  // recorded keyless replies (RxNav and openFDA, 16 Oct 2026): what the bench's own drug test reads
  const canned = map => { const asked = []; const f = async url => { asked.push(String(url)); const body = map[String(url)]; return body === undefined ? new Response('{"error":{"code":"NOT_FOUND"}}', { status: 404 }) : new Response(JSON.stringify(body), { status: 200 }); }; f.asked = asked; return f; };
  const rxn = (name, id) => ({ [`https://rxnav.nlm.nih.gov/REST/rxcui.json?name=${name}&search=2`]: { idGroup: id ? { rxnormId: [id] } : {} } });
  const rxp = (id, name) => ({ [`https://rxnav.nlm.nih.gov/REST/rxcui/${id}/properties.json`]: { properties: { rxcui: id, name, synonym: '', tty: 'IN', language: 'ENG', suppress: 'N', umlscui: '' } } });
  const rx = canned({ ...rxn('bupropion', '42347'), ...rxn('modafinil', '30125'), ...rxn('chlorazepate', '2353'), ...rxn('reassurance'), ...rxp('42347', 'bupropion'), ...rxp('30125', 'modafinil'), ...rxp('2353', 'clorazepate') });
  const psych = { id: 'p', stem: 'Which drug?', options: ['Bupropion', 'Modafinil', 'Chlorazepate', 'Reassurance'], key: 0 };
  const look = await R.drugLookups([psych], rx);
  const named = R.drugsNamed(psych, look);
  check(named.map(d => d.name).join() === 'bupropion,modafinil,clorazepate' && named.every(d => d.by === 'rxnav') && named[0].key && !named[1].key, 'drugs named: the bench\'s own test finds Bupropion, Modafinil and clorazepate (RxNav ingredients), not Reassurance');
  check(rx.asked.some(u => u.startsWith('https://api.fda.gov/') && u.includes('reassurance')) && !rx.asked.some(u => u.startsWith('https://api.fda.gov/') && u.includes('bupropion')), 'openFDA\'s exact generic names are asked only for options RxNav does not know');
  check(R.drugsNamed(item, { rx: new Map(), fda: new Set() }).map(d => `${d.name}:${d.by}`).join() === 'metformin:dictionary' && R.drugsNamed({ options: ['Metformin'], key: 0 }, { rx: new Map(), fda: new Set(['metformin']) })[0].by === 'openFDA', 'drugs named: the engine\'s list inside a longer option, and an openFDA generic name');
  // the FDA oracle, past the first hit: the phrase search's first label is the combination (the engine's limit=1 lookup gets it)
  const metTerms = [{ term: 'METFORMIN HYDROCHLORIDE', count: 243 }, { term: 'METFORMIN HCL', count: 26 }, { term: 'SITAGLIPTIN AND METFORMIN HYDROCHLORIDE', count: 16 }];
  const fdaFake = canned({
    'https://api.fda.gov/drug/label.json?search=openfda.generic_name:%22metformin%22&limit=1': { results: [{ set_id: '0098dec4-f0e5-45d5-8aa4-5d0faf9ab142', openfda: { generic_name: ['SITAGLIPTIN AND METFORMIN HYDROCHLORIDE'] } }] },
    'https://api.fda.gov/drug/label.json?search=openfda.generic_name.exact:%22METFORMIN%20HYDROCHLORIDE%22&limit=1&skip=0': { results: [{ set_id: '011de1a5-1ac0-4831-9e8d-26ec79ba2205', effective_time: '20240821', openfda: { generic_name: ['METFORMIN HYDROCHLORIDE'] } }] },
  });
  const met = await R.fdaOracle('metformin', metTerms, fdaFake);
  check(met.status === 'label' && met.id === 'fda:metformin' && met.setId === '011de1a5-1ac0-4831-9e8d-26ec79ba2205' && !fdaFake.asked.some(u => u.endsWith('%22metformin%22&limit=1')), 'FDA oracle: the single-ingredient label is chosen over the combination first hit, by an exact search');
  check((await R.fdaOracle('warfarin', [{ term: 'WARFARIN SODIUM', count: 40 }], fdaFake)).status === 'salt-only' && (await R.fdaOracle('clavulanate', [{ term: 'AMOXICILLIN AND CLAVULANATE POTASSIUM', count: 9 }], fdaFake)).status === 'combination-only' && (await R.fdaOracle('zzz', [], fdaFake)).status === 'none', 'FDA oracle: a drug with labels only as another salt, or only in combinations, stays out of label 2 and is counted apart');
  const topicsXml = '<health-topics><health-topic meta-desc="x" title="Heart Attack" url="https://medlineplus.gov/heartattack.html" id="1" language="English"><also-called>MI</also-called><also-called>Myocardial infarction</also-called><full-summary>&lt;p&gt;x&lt;/p&gt;</full-summary></health-topic>'
    + '<health-topic title="Ataque card\u00edaco" url="https://medlineplus.gov/spanish/heartattack.html" language="Spanish"><also-called>Infarto</also-called></health-topic></health-topics>';
  const index = R.healthTopics(topicsXml);
  check(index.topics === 1 && index.byWords.get('myocardial infarction')?.[0].url === 'https://medlineplus.gov/heartattack.html' && index.byWords.has('heart attack') && !index.byWords.has('infarto'), 'MedlinePlus: the full health-topics XML, English topics by title and "also called" name');
  const orc = await R.oracleFor({ ...inputs, drugs: [{ name: 'metformin', by: 'dictionary', key: false }, { name: 'warfarin', by: 'rxnav', key: true }] }, { terms: [...metTerms, { term: 'WARFARIN SODIUM', count: 40 }], topics: index, fetcher: fdaFake });
  check(orc.oracle.map(o => `${o.id}:${o.key}`).join() === 'fda:metformin:false,https://medlineplus.gov/heartattack.html:true' && orc.oracle[0].setId && orc.drugs.map(d => d.fda).join() === 'label,salt-only', 'the oracle: an FDA label with its set_id and a topic matched on the key, the key\'s own marked; the salt-only drug counted');
  // R-dev's vignettes are case stems, never what the proof declined
  check(R.isVignette({ stem: 'A 45-year-old man presents with crushing chest pain. An ECG shows ST elevation in II, III and aVF. What is the most likely diagnosis?' }) && R.isVignette({ stem: 'A woman comes to the clinic with a rash on her arms. She recently started a new drug. Which drug is the cause?' }), 'a vignette: two or more sentences with a patient presentation');
  check(!R.isVignette({ stem: 'Primary receptor cells of hearing is' }) && !R.isVignette({ stem: 'A 30-year-old man has which of the following?' }) && !R.isVignette({ stem: 'Insulin is made in the pancreas. Which cells make it?' }), 'not a vignette: a one-liner, one sentence, or no patient');
  // runs read the stored label inputs, and refuse inputs the bench's words do not make
  const stored = { id: 't1', mesh: 'Myocardial Infarction', keyWords: inputs.keyWords, meshWords: inputs.meshWords, drugs: [{ name: 'metformin' }], oracle: [{ id: 'fda:metformin', key: false }] };
  const runIn = R.inputsFor(stored, item);
  check(runIn.drugs.join() === 'metformin' && runIn.keyWords === stored.keyWords && runIn.tail.join() === inputs.tail.join() && runIn.oracle.join() === 'fda:metformin', 'a run reads keyWords, meshWords and drugs from the label file; the stored inputs equal what the run computes');
  check(throws(() => R.inputsFor({ ...stored, keyWords: ['myocardial', 'infarct'] }, item), /stored label inputs/) && R.benchWords('β-Blocker (Café)').join() === 'beta,blocker,cafe', 'stored inputs the bench\'s frozen words do not make are refused; the words are its own');
  const fda = { source: 'openFDA label', title: 'metformin (FDA label)', url: 'u', official: { drug: 'Metformin Hydrochloride' } };
  check(R.officialRelevant(fda, inputs) === true, 'label 2: an FDA label whose generic name equals a drug named (a salt aside)');
  check(R.officialRelevant({ ...fda, official: { drug: 'metformin and glipizide' } }, inputs) === false, 'label 2: not a combination label');
  check(R.officialRelevant({ ...fda, official: undefined }, inputs) === false, 'label 2: not an FDA label the engine could not read as the drug\'s alone');
  check(R.officialRelevant({ ...fda, official: { drug: 'ramipril' } }, inputs) === false, 'label 2: not a drug nobody named');
  const topic = { source: 'MedlinePlus', title: 'Heart Attack', alsoCalled: ['MI', 'Myocardial Infarction'], url: 'm' };
  check(R.officialRelevant(topic, inputs) === true, 'label 2: a MedlinePlus topic whose "also called" name equals the key');
  check(R.officialRelevant({ ...topic, alsoCalled: ['MI'] }, { ...inputs, keyWords: ['myocardial', 'infarction'], meshWords: [] }) === false, 'label 2: not a title that only contains the key');
  check(R.officialRelevant({ ...topic, alsoCalled: [] }, { ...inputs, keyWords: ['mi'], meshWords: ['heart', 'attack'] }) === true, 'label 2: a title equal to the MeSH term');
  check(R.officialRelevant({ source: 'Europe PMC', title: 'Myocardial infarction', url: 'p' }, inputs) === false, 'label 2: only official sources');
  const passage = { title: 'Review', text: 'Myocardial infarction is the usual diagnosis after the ECG and troponin.', url: 'p', source: 'Europe PMC' };
  check(R.onTopic(passage, inputs) === true && R.labelOf(passage, inputs) === 1, 'label 1: holds the key\'s words and a word of the stem\'s tail');
  check(R.onTopic({ ...passage, text: 'Myocardial infarction is common.' }, inputs) === false, 'label 1: not without a word of the tail');
  check(R.onTopic({ ...passage, text: 'Troponin and the ECG in infarction.' }, inputs) === false, 'label 1: not without all of the key\'s words');
  check(R.onTopic({ title: 'x', text: 'MI (Myocardial Infarction) is a diagnosis made by ECG.' }, { ...inputs, keyWords: ['zzz'] }) === true, 'label 1: or the stored MeSH term\'s words');
  check(R.labelOf({ title: 'Cooking', text: 'Pasta.' }, inputs) === 0 && R.labelOf(topic, inputs) === 2, 'labels 0 and 2');
  const xml = '<nlmSearchResult><list><document rank="0" url="https://medlineplus.gov/heartattack.html"><content name="title">&lt;span class="qt0"&gt;Heart&lt;/span&gt; Attack</content>'
    + '<content name="altTitle">MI</content><content name="altTitle">&lt;span&gt;Myocardial Infarction&lt;/span&gt;</content></document></list></nlmSearchResult>';
  const topics = R.topicsIn(xml);
  check(topics.length === 1 && topics[0].title === 'Heart Attack' && topics[0].alsoCalled.join('|') === 'MI|Myocardial Infarction' && topics[0].url.endsWith('heartattack.html'), 'MedlinePlus: title and "also called" names read from the answer');
  check(R.docId(fda) === 'fda:metformin' && R.docId(topic) === 'm', 'a document\'s identity: an FDA label by its drug, a topic by its address');

  // --- the metrics, on a hand-made case
  const ranked = ['a', 'b', 'c', 'd', 'e'];
  check(near(R.recallAt(3, ranked, ['b', 'e', 'z']), 1 / 3) && near(R.recallAt(5, ranked, ['b', 'e', 'z']), 2 / 3), 'recall@3 is 1/3 and recall@5 is 2/3 where two of three relevant documents are in the first five, one in the first three');
  check(R.recallAt(5, ranked, []) === null && R.recallAt(3, [], ['a']) === 0, 'recall: not counted when nothing is relevant; 0 when nothing is found');
  // labels 0,2,1,0,2: DCG = 3/log2(3) + 1/log2(4) + 3/log2(6) = 3.5533; the ideal 2,2,1,0,0: 3 + 3/log2(3) + 1/log2(4) = 5.3928
  check(near(R.dcgAt(5, [0, 2, 1, 0, 2]), 3.5533) && near(R.ndcgAt(5, [0, 2, 1, 0, 2]), 0.6589), 'nDCG@5 of labels 0,2,1,0,2 is 0.659');
  // moved (A4): the ideal holds the item's oracle documents, so 1 needs the best order and no official document missed
  // ideal 2,2,2,1,0 = 3 + 3/log2(3) + 3/2 + 1/log2(5) = 6.8235; the list's 5.3928
  check(R.ndcgAt(5, [2, 2, 1, 0, 0]) === 1 && near(R.ndcgAt(5, [2, 2, 1, 0, 0], 1), 0.7903) && R.ndcgAt(5, [0, 0, 0]) === 0 && R.ndcgAt(5, [], 1) === 0 && R.ndcgAt(5, []) === 0, 'nDCG@5: 1 for the best order with no official document missed, less when one was; 0 where nothing relevant is shown');
  check(near(R.ndcgAt(2, [0, 2, 2]), 3 * 0.63093 / (3 + 3 * 0.63093)), 'nDCG@k reads only the first k');
  const s = R.summarize([
    { id: 'a', oracle: ['b', 'e'], retrieved: ['a', 'b', 'c', 'd', 'e'], shown: [2, 1, 0], lookups: 3 },
    { id: 'b', oracle: [], retrieved: ['x'], shown: [0], lookups: 2 },
    { id: 'c', oracle: ['z'], retrieved: [], shown: [], lookups: 1 },
  ]);
  check(s.items === 3 && s.answerable === 2 && s.officialDocs === 3 && near(s.recall3, 1 / 3) && near(s.recall5, 2 / 3), 'summary: recall over the documents that exist, only for items that have one');
  check(near(s.onTopic, 2 / 4) && near(s.official, 1 / 4) && s.passages === 4 && near(s.lookupsPerItem, 2) && s.noPassage === 1, 'summary: the on-topic share of what is shown, lookups per item');
  check(near(s.ndcg5, (R.ndcgAt(5, [2, 1, 0]) + 0 + 0) / 3), 'summary: nDCG@5 is the mean over every item');
  const s2 = R.summarize([
    { id: 'a', oracle: ['b', 'e'], keyDocs: ['e'], retrieved: ['b', 'x'], shown: [2, 0], missing: 1, outside: ['q'], lookups: 1 },
    { id: 'c', oracle: ['z', 'y', 'w', 'v'], keyDocs: [], retrieved: ['z', 'y', 'w', 'v'], shown: [2], missing: 3, outside: [], lookups: 1 },
  ]);
  check(near(s2.recall5, 5 / 6) && near(s2.recall5Macro, (0.5 + 1) / 2) && s2.keyRecall5 === 0 && s2.keyDocs === 1 && s2.outside === 1, 'summary: micro and macro recall@5, key-document recall, label-2 documents outside the oracle');
  check(near(s2.ndcg5, (R.ndcgAt(5, [2, 0], 1) + R.ndcgAt(5, [2], 3)) / 2) && near(s2.ndcg5Order, 1), 'summary: nDCG@5 against the oracle\'s documents, and the order-only figure beside it');
  // a failed lookup is not a miss: left out of recall and nDCG, counted apart
  const okRow = { id: 'a', oracle: ['b'], retrieved: ['b'], shown: [2], missing: 0, lookups: 2, failed: 0, unread: 0 };
  const s3 = R.summarize([okRow, { id: 'f', oracle: ['z'], retrieved: [], shown: [], missing: 1, lookups: 2, failed: 2, unread: 1 }]);
  check(s3.items === 2 && s3.lookupFailed === 1 && s3.lookupFailedUnread === 1 && s3.measured === 1 && s3.answerable === 1 && s3.officialDocs === 1
    && s3.recall5 === 1 && s3.recall3 === 1 && s3.recall5Macro === 1 && s3.ndcg5 === 1 && s3.ndcg5Order === 1, 'summary: a failed lookup is not counted as a miss in recall or nDCG, and is counted apart');
  const s4 = R.summarize([okRow, { id: 'm', oracle: ['z'], retrieved: [], shown: [], missing: 1, lookups: 2, failed: 0, unread: 0 }]);
  check(s4.lookupFailed === 0 && s4.recall5 === 1 / 2 && s4.ndcg5 === 1 / 2, 'summary: the same empty item with no failed lookup is a miss');
  check(/1 had a failed lookup \(1 sources unread; left out of recall and nDCG/.test(R.reportFor('t', [['set', [okRow, { id: 'f', oracle: ['z'], retrieved: [], shown: [], lookups: 2, failed: 2, unread: 1 }]]])), 'report: the failed-lookup count is shown');

  // --- the committed label files and their sha256
  check(readdirSync(R.LABELS_DIR).sort().join() === 'SHA256SUMS,r-dev.json,r-test.json', 'two label files and their sums');
  for (const name of ['r-dev', 'r-test']) {
    const f = R.readLabels(name);
    check(statSync(join(R.LABELS_DIR, `${name}.json`)).size < 1_000_000 && /^[0-9a-f]{64}$/.test(f.sha256), `${name}: under 1 MB, its sha256 matches labels/SHA256SUMS`);
  }
  const dev = R.readLabels('r-dev'), test = R.readLabels('r-test');
  check(dev.items.length === 150 && dev.items.filter(i => i.group === 'one-sentence').length === 100 && dev.items.filter(i => i.group === 'vignette').length === 50, 'R-dev: 150 items, 100 one-sentence and 50 vignettes');
  check(new Set(dev.items.map(i => i.id)).size === 150 && dev.items.every(i => /^(medmcqa|medqa)-train:/.test(i.id) && i.row?.offset >= 0 && /^[0-9a-f]{16}$/.test(i.sha)), 'R-dev: each from a MedMCQA or MedQA training split, by row, with a content hash');
  check(test.items.length === 90 && ['MedXpertQA', 'MedQA', 'CareQA Medicine'].every(g => test.items.filter(i => i.group === g).length === 30), 'R-test: the 90 bench questions, 30 a source');
  check(JSON.stringify(dev).length < 1e6 && !('stem' in dev.items[0]) && !('options' in dev.items[0]), 'the label files hold no question text');
  check([dev, test].every(f => f.words === R.WORDS && f.items.every(i => Array.isArray(i.drugs) && i.drugs.every(d => d.name && d.by && d.fda) && i.oracle.every(o => !o.id.startsWith('fda:') || o.setId))), 'the label files store the drugs named, their FDA status, and each FDA document with its set_id');
  check(dev.vignettes?.medqa + dev.vignettes?.medmcqa === 50 && dev.vignettes.leastSentences >= 2, 'R-dev\'s vignettes are counted, each of two or more sentences');
  const tmp = mkdtempSync(join(tmpdir(), 'bench-labels-'));
  for (const f of ['r-test.json', 'SHA256SUMS']) copyFileSync(join(R.LABELS_DIR, f), join(tmp, f));
  check(R.readLabels('r-test', tmp).items.length === 90, 'a copy of the label files reads');
  writeFileSync(join(tmp, 'r-test.json'), readFileSync(join(tmp, 'r-test.json'), 'utf8').replace('"v": 1', '"v": 2'));
  check(throws(() => R.readLabels('r-test', tmp), /does not match its sha256/), 'a label file that was changed is refused');

  // --- proxy mode: the rewrite, the header, the free-only pins, the claude refusal
  const pins = X.freeVoterPins();
  const live = DEFAULT_VOTERS.split(',').filter(v => !/^claude:/.test(v));
  check(pins.join() === live.map(v => `bench:${v}`).join() && pins[0] === 'bench:gemini:gemini-3.5-flash-lite' && pins[1] === 'bench:workers-ai:@cf/openai/gpt-oss-120b', 'the pins are the live free order, as bench: pins');
  check(pins.every(p => /^bench:(gemini|workers-ai):/.test(p)) && !pins.some(p => /claude/i.test(p)), 'free families only: no claude pin among them');
  const body = { model: 'gemini:gemini-3.5-flash-lite', messages: [{ role: 'user', content: 'hi' }], max_tokens: 900, temperature: 0, stream: false };
  const re = X.rewriteChat(body);
  check(re.model === 'cramdown-writer' && re.use === 'gemini:gemini-3.5-flash-lite' && re.ground === false && re.max_tokens === 900 && re.messages === body.messages, 'the chat call is rewritten to {model: cramdown-writer, use: <pin>, ground: false, ...}');
  const sent = [];
  const fake = async (url, init) => { sent.push({ url, init }); return new Response('{}', { status: 200 }); };
  const fetcher = X.proxyFetcher(fake);
  await fetcher('https://w.example/v1/chat/completions', { method: 'POST', headers: { authorization: 'Bearer k', 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const out = sent[0];
  check(out.url === 'https://w.example/v1/chat/completions' && out.init.headers['x-bench'] === '1' && out.init.headers.authorization === 'Bearer k' && JSON.parse(out.init.body).use === 'gemini:gemini-3.5-flash-lite' && JSON.parse(out.init.body).model === 'cramdown-writer', 'the fetcher sends it to the Worker with x-bench: 1 and the key');
  await fetcher('https://api.fda.gov/drug/label.json?x=1', { headers: { a: 'b' } });
  check(sent[1].url.startsWith('https://api.fda.gov') && !('x-bench' in sent[1].init.headers), 'the lookups go where they were going, untouched');
  for (const pin of ['bench:claude:claude-opus-5-5', 'claude:claude-opus-5-5', 'bench:workers-ai:claude-via-x', 'hf:org/model', 'bench:nothing']) {
    check(throws(() => X.usePin(pin), /refused pin/), `the pin ${pin} is refused`);
  }
  const before = sent.length;
  check(await rejects(() => fetcher('https://w.example/v1/chat/completions', { method: 'POST', body: JSON.stringify({ ...body, model: 'claude:claude-opus-5-5' }) }), /claude is never pinned/) && sent.length === before, 'the fetcher refuses a claude call and sends nothing');
  // the stub spawns never inherit a Worker, a key or a provider
  const offline = Object.fromEntries(Object.entries(process.env).filter(([k]) => k !== 'WORKER' && k !== 'KEY' && !k.startsWith('BENCH_')));
  const refused = spawnSync(process.execPath, [new URL('layer.mjs', bench).pathname, '--proxy', '--stub', '--voters', 'bench:gemini:gemini-3.5-flash-lite,bench:claude:claude-opus-5-5'], { encoding: 'utf8', env: offline });
  check(refused.status === 2 && /refused pin/.test(refused.stderr), 'layer.mjs --proxy exits 2 on a claude voter');
  const proxyEnv = X.proxyEnv({ base: 'https://w.example/v1', key: 'k', voters: pins, route: 'off', db: {} });
  check(proxyEnv.BENCH_MODELS === 'on' && proxyEnv.BENCH_BASE_URL === 'https://w.example/v1' && proxyEnv.VIGNETTE_ROUTE === 'off' && proxyEnv.ACCURACY_VOTERS === pins.join(',') && X.proxyEnv({ base: 'b', key: 'k', voters: pins, db: {} }).VIGNETTE_ROUTE === 'on', 'proxy env: bench models on, the Worker as base, the route on by default');
  const stubDir = mkdtempSync(join(tmpdir(), 'bench-stub-'));
  const stub = spawnSync(process.execPath, [new URL('layer.mjs', bench).pathname, '--stub', '--out', stubDir, '--per-source', '4'], { encoding: 'utf8', env: offline });
  check(stub.status === 0 && /Cost and quality of this run/.test(stub.stdout) && JSON.parse(readFileSync(join(stubDir, 'run.json'), 'utf8')).batches.length > 0, 'layer.mjs --stub runs offline, writes its report and the cost of each batch');
  const stubProxy = spawnSync(process.execPath, [new URL('layer.mjs', bench).pathname, '--proxy', '--stub', '--route', 'off', '--out', stubDir, '--per-source', '2'], { encoding: 'utf8', env: offline });
  check(stubProxy.status === 0 && JSON.parse(readFileSync(join(stubDir, 'run.json'), 'utf8')).mode === 'proxy', 'layer.mjs --proxy --stub runs offline with the free pins');
  const stubLive = spawnSync(process.execPath, [new URL('layer.mjs', bench).pathname, '--stub', '--out', stubDir, '--per-source', '2'], { encoding: 'utf8', env: { ...offline, WORKER: 'http://127.0.0.1:9', KEY: 'dummy' } });
  const stubRun = stubLive.status === 0 && JSON.parse(readFileSync(join(stubDir, 'run.json'), 'utf8'));
  check(stubRun && stubRun.mode !== 'live' && stubRun.stub === true && stubRun.batches.length > 0, 'layer.mjs --stub never goes live, even with WORKER and KEY set');

  // --- gates.mjs on a fixed results.json fragment
  const fam = { a: 'gemini-3.5-flash-lite', b: '@cf/openai/gpt-oss-120b', c: '@cf/nvidia/nemotron-3-120b-a12b' };
  const pass = { voters: 1, families: 3, blind_agree: 3, blind_dissent: 0, source_proof: 1 };
  const rows = [
    { id: 'r1', truth: 'right', verdict: 'verified', p: 0.9, features: pass, proof: { why: undefined, claims: 1, proven: 1 },
      votes: [{ model: fam.a, evidence: 'supports' }, { model: fam.b, evidence: 'none' }, { model: fam.c, evidence: 'supports' }] },
    { id: 'w1', truth: 'wrong', verdict: 'check', p: 0.3, features: { ...pass, families: 2, blind_agree: 1, source_proof: 0 }, proof: { why: 'stem' },
      votes: [{ model: fam.a, evidence: 'none' }, { model: fam.b, evidence: 'none' }] },
    { id: 'r2', truth: 'right', verdict: 'check', p: 0.7, features: { ...pass, source_proof: 0 }, proof: { why: 'no-source' },
      votes: [{ model: fam.a, evidence: 'supports' }, { model: fam.b, evidence: 'none' }, { model: fam.c, evidence: 'none' }] },
  ];
  const run = { batches: [{ items: 2, cpuMs: 4, lookups: 6, calls: [
    { model: 'workers-ai:@cf/openai/gpt-oss-120b', usage: { prompt_tokens: 1000, completion_tokens: 200 } },
    { model: 'gemini:gemini-3.5-flash-lite', chars: 4000, maxTokens: 800 },
    { model: 'workers-ai:@cf/qwen/qwen3-30b-a3b-fp8', chars: 4000, maxTokens: 800 }] },
  { items: 1, cpuMs: 8, lookups: 2, calls: [{ model: 'gemini:gemini-3.5-flash-lite', chars: 100, maxTokens: 10 }] }] };
  check(G.NEURON_RATES['@cf/openai/gpt-oss-120b'].join() === '31818,68182' && Object.keys(G.NEURON_RATES).length >= 8, 'NEURON_RATES are read from server/ai.js, not copied');
  const n1 = G.neuronsOf(run.batches[0].calls[0]), n2 = G.neuronsOf(run.batches[0].calls[2]);
  check(n1.basis === 'usage' && near(n1.neurons, 1000 * 31818 / 1e6 + 200 * 68182 / 1e6), 'neurons from a reply\'s usage times the model\'s rates');
  check(n2.basis === 'estimate' && near(n2.neurons, 1000 * 4625 / 1e6 + 800 * 30475 / 1e6) && G.neuronsOf(run.batches[0].calls[1]).neurons === 0, 'else the Worker\'s estimate (a quarter of the characters in, max_tokens out); a Gemini call takes none');
  const nu = G.neuronSummary(run.batches);
  check(near(nu.total, 45.4544 + 29.005) && near(nu.mean, (74.4594 / 2 * 2 + 0) / 3) && nu.fromUsage === 1 && nu.estimated === 1 && nu.checks === 3, 'neurons per check: each batch shared over its items, the mean over checks');
  const cost = G.costSummary(run.batches);
  check(cost.cpu.max === 8 && cost.cpu.median === 4 && cost.fetches.max === 9 && cost.lookups.max === 6 && cost.models.max === 3, 'CPU and external fetches per batch');
  const cal = G.calibration(rows);
  check(near(cal.brier, (0.01 + 0.09 + 0.09) / 3, 1e-9) && cal.bins.length === 5 && cal.bins[3].n === 1 && cal.bins[4].n === 1 && cal.bins[1].n === 1 && near(cal.bins[4].meanP, 0.9), 'calibration: the Brier score and the five bins');
  const w = G.calibration(rows.filter(r => r.truth === 'wrong'));
  check(near(w.brier, 0.09) && w.bins[1].right === 0, 'calibration by truth');
  const none = G.evidenceNone(rows);
  check(none.none === 5 && none.votes === 8, 'the share of votes saying "evidence: none"');
  const fams = G.familiesPerCheck(rows.filter(r => r.truth === 'right'));
  check(fams.mean === 3 && fams.hist[3] === 2 && G.familiesPerCheck([rows[1]]).hist[2] === 1, 'families answering per check');
  const table = G.conditionsReport(rows);
  const line = (section, name) => table.split(`### ${section}`)[1].split('\n').find(l => l.startsWith(`| ${name}`));
  check(/\| 2 \| 0 \|$/.test(line('Right keys', 'a checker answered')) && /\| 1 \| 0 \|$/.test(line('Right keys', 'an official source')) && /\| 1 \| 0 \|$/.test(line('Right keys', 'P(accurate)')), 'the conditions table: Right keys, met and the only one not met');
  check(/\| 0 \| 0 \|$/.test(line('Wrong keys', 'P(accurate)')) && /\| 0 \| 0 \|$/.test(line('Wrong keys', 'an official source')) && /\| 1 \| 0 \|$/.test(line('Wrong keys', 'no sensor')), 'the conditions table: Wrong keys planted');
  check(table.includes('Every condition met: 1. Every condition but the source proof: 1.') && table.includes('Why the proof said no: proven 1, no-source 1.') && table.includes('Why the proof said no: stem 1.'), 'the conditions table: all met, all but the proof, and why');
  check(G.GATES.length === 8 && G.GATES.filter(([n]) => !/checker answered/.test(n)).length === 7, 'the seven conditions of verdict() and the checker that answered');
  const rep = G.gateReport(rows, run);
  check(/Verified, by truth \| right 1, wrong 0/.test(rep) && /evidence: none"[^|]*\| 62\.5% \(5 of 8\)/.test(rep) && /mean 3\.00; 3 families: 2/.test(rep) && /neurons per check \| mean 24\.8/.test(rep)
    && /CPU per batch \(ms\) \| median 4\.0, p95 8\.0, max 8\.0 \(2 batches; live run, context only\)/.test(rep) && /external fetches per batch \| median 3, p95 9, max 9: lookups max 6, model calls max 3/.test(rep) && /Brier score 0\.063 over 3 checks/.test(rep) && /Checked, by truth \| right 0, wrong 0/.test(rep), 'the whole report on the fragment: every item of the list');

  // --- the lookup cache and P's failed lookups
  const dir = mkdtempSync(join(tmpdir(), 'bench-cache-'));
  const cache = L.diskCache(dir);
  let calls = 0;
  const flaky = async url => { calls++; return String(url).includes('bad') ? new Response('slow down', { status: 429 }) : new Response(String(url).includes('none') ? '' : '{"ok":1}', { status: String(url).includes('none') ? 404 : 200 }); };
  const f = L.cachedFetcher({ cache, fetchImpl: flaky, retryMs: 0, gap: false });
  await f('https://api.fda.gov/a'); await f('https://api.fda.gov/a'); await f('https://api.fda.gov/none');
  check(calls === 2 && f.tally.disk === 1 && f.tally.lookups === 3, 'the disk cache answers a repeated lookup (a 404 is an answer too)');
  const bad = await f('https://api.fda.gov/bad');
  check(bad.status === 429 && f.tally.failed === 1 && f.tally.retried === 1 && f.tally.byStatus['429'] === 1 && calls === 4, 'a rate limit is retried once, counted as failed by status, never kept');
  await f('https://api.fda.gov/bad');
  check(calls === 6, 'and asked again next time');
  const small = L.diskCache(mkdtempSync(join(tmpdir(), 'bench-cap-')), { cap: 50 });
  check(small.put('k', { status: 200, text: 'x'.repeat(10) }) === true && small.put('k2', { status: 200, text: 'y'.repeat(100) }) === false && small.get('k2') === null, 'the cache never grows past its cap');
  const mcq = { id: 'p1#ladder', kind: 'mcq', stem: 'Which drug is the first-line treatment of type 2 diabetes?', options: ['Metformin', 'Insulin', 'Warfarin', 'Heparin'], key: 0, explanation: '' };
  const down = L.cachedFetcher({ cache: null, fetchImpl: async () => new Response('busy', { status: 503 }), retryMs: 0, gap: false });
  const [rec] = await P.proveBatch([{ truth: 'right', group: 'ladder', item: mcq }], down);
  check(rec.failed === true && rec.proven === false && rec.unread > 0 && P.outcomeOf(rec) === 'lookup failed' && down.tally.failed >= 1, 'P: a source that could not be read is a failed lookup, apart from "not proven"');
  const empty = L.cachedFetcher({ cache: null, retryMs: 0, gap: false, fetchImpl: async url => (String(url).includes('api.fda.gov') ? new Response('', { status: 404 }) : new Response('<nlmSearchResult><count>0</count></nlmSearchResult>', { status: 200 })) });
  const [rec2] = await P.proveBatch([{ truth: 'right', group: 'ladder', item: mcq }], empty);
  check(rec2.failed === false && rec2.unread === 0 && P.outcomeOf(rec2) === 'not proven' && rec2.why === 'no-source', 'P: a source that answered with nothing is "not proven", not a failed lookup');
  const sum = P.summarize([
    { id: '1', truth: 'right', group: 'g', proven: true, failed: false, why: null }, { id: '2', truth: 'right', group: 'g', proven: false, failed: false, why: 'unproven' },
    { id: '3', truth: 'right', group: 'g', proven: false, failed: true, why: 'lookup' }, { id: '4', truth: 'wrong', group: 'g', proven: false, failed: false, why: 'distractor' },
    { id: '5', truth: 'wrong', group: 'g', proven: false, failed: true, why: 'error' }]);
  check(sum.right.proven === 1 && sum.right.notProven === 1 && sum.right.lookupFailed === 1 && sum.right.why.unproven === 1 && sum.right.why['LOOKUP FAILED (lookup)'] === 1
    && sum.wrong.notProven === 1 && sum.wrong.lookupFailed === 1 && sum.wrongProven.length === 0, 'P: the report by truth, failed lookups apart from not proven');
  check(P.summarize([{ id: 'x', truth: 'wrong', group: 'g', proven: true, failed: false, why: null }]).wrongProven.join() === 'x', 'P: a wrong key proven is named (a false proof)');
  check(P.interleave(['a', 'b', 'c', 'd'], ['X', 'Y']).join('') === 'aXbcYd' && P.interleave(['a', 'b'], ['X'], 4, 1).join('') === 'abX', 'P: the two lists merged in proportion');

  // --- A9: Checked verdicts counted by truth, wrong key checked is not caught
  const casesA9 = [
    { truth: 'right', result: { verdict: 'checked' } },
    { truth: 'wrong', result: { verdict: 'checked' } },
    { truth: 'wrong', result: { verdict: 'flagged' } },
  ];
  const mA9 = Y.measures(casesA9);
  check(mA9.checked.right === 1 && mA9.checked.wrong === 1 && mA9.checked.n === 2 && mA9.caught.n === 1 && mA9.caught.of === 2, 'A9: measures counts Checked by truth; wrong key checked is not caught');
  const repA9 = G.gateReport(casesA9.map(c => ({ truth: c.truth, verdict: c.result.verdict })));
  check(/Checked, by truth \| right 1, wrong 1/.test(repA9), 'A9: gateReport includes Checked by truth');

  // --- A10: worst-batch CPU fixture
  const cpuWorst = await G.measureWorstBatchCpu();
  check(Number.isFinite(cpuWorst.warm) && cpuWorst.warm > 0 && Number.isFinite(cpuWorst.cold) && cpuWorst.cold > 0, 'A10: worst-batch CPU fixture measures warm and cold CPU time');
  check(/CPU per batch \(ms\) \| [^|]*\(2 batches; live run, context only\)/.test(rep), 'A10: live run CPU labelled context only');

  // --- A11: P counts lookups per batch of 4
  const batchOf4 = [
    { truth: 'right', group: 'ladder', item: { id: 'p1', kind: 'mcq', stem: 'S1', options: ['Metformin', 'Insulin'], key: 0 } },
    { truth: 'right', group: 'ladder', item: { id: 'p2', kind: 'mcq', stem: 'S2', options: ['Aspirin', 'Warfarin'], key: 0 } },
    { truth: 'right', group: 'ladder', item: { id: 'p3', kind: 'mcq', stem: 'S3', options: ['Lisinopril', 'Losartan'], key: 0 } },
    { truth: 'right', group: 'ladder', item: { id: 'p4', kind: 'mcq', stem: 'S4', options: ['Atorvastatin', 'Simvastatin'], key: 0 } },
  ];
  let tally4 = 0;
  const fetcher4 = async () => { tally4++; return new Response('', { status: 404 }); };
  const records4 = await P.proveBatch(batchOf4, fetcher4);
  check(records4.lookups === tally4 && records4.length === 4 && records4.every(r => r.lookups === tally4), 'A11: P counts lookups per batch of 4');
  const sum4 = P.summarize(records4);
  check(sum4.lookupsPerBatch && sum4.lookupsPerBatch.max === tally4 && sum4.lookupsPerBatch.mean === tally4, 'A11: P summarize includes lookupsPerBatch');

  // --- A12: proxy mode neuron label
  const proxyRep = G.gateReport(rows, { ...run, mode: 'proxy' });
  check(/neurons per check \| [^|]*\(1 calls from a reply's usage, 1 estimated as the Worker does\) \|/.test(proxyRep) && !/upper bound/.test(proxyRep), 'A12: in proxy mode with a reply\'s usage, the usage/estimate split is shown and no upper bound is claimed');
  const estimatesOnly = { mode: 'proxy', batches: [{ items: 1, cpuMs: 1, lookups: 0, calls: [{ model: 'workers-ai:@cf/qwen/qwen3-30b-a3b-fp8', chars: 400, maxTokens: 80 }] }] };
  check(/neurons per check \(upper bound\) \| [^|]*\(0 calls from a reply's usage, 1 estimated as the Worker does; upper bound: every call there is the reservation estimate\) \|/.test(G.gateReport(rows, estimatesOnly)), 'A12: with no call from a reply\'s usage, neurons are labelled an upper bound, the split still shown');
  check(!/upper bound/.test(rep) && /\(1 calls from a reply's usage, 1 estimated as the Worker does\)/.test(rep), 'A12: live run shows the split and does not label neurons as upper bound');

  // --- A13: P counts network failures per item apart from budget skips
  const [netFailRec] = await P.proveBatch([{ truth: 'right', group: 'ladder', item: mcq }], async () => new Response('error', { status: 500 }));
  const fdaOkFetcher = async url => {
    if (String(url).includes('api.fda.gov')) {
      return new Response(JSON.stringify({ results: [{ openfda: { generic_name: ['metformin'] }, description: ['metformin treats type 2 diabetes'] }] }), { status: 200, headers: { 'content-type': 'application/json' } });
    }
    return new Response('', { status: 404 });
  };
  const [budgetSkipRec] = await P.proveBatch([{ truth: 'right', group: 'ladder', item: mcq }], fdaOkFetcher, { chars: 0 });
  check(netFailRec.failed === true && P.outcomeOf(netFailRec) === 'lookup failed', 'A13: network failure counts as lookup failed');
  check(budgetSkipRec.failed === false && budgetSkipRec.why === 'budget' && P.outcomeOf(budgetSkipRec) === 'not proven', 'A13: budget skip counts as not proven, not lookup failed');

  // --- A14: question bank fake worker parses path with new URL(url).pathname
  const bankPath = fileURLToPath(new URL('../../tests/question-bank/bank.test.mjs', import.meta.url));
  const bankOut = execFileSync(process.execPath, [bankPath], {
    env: { ...process.env, WORKER: 'http://127.0.0.1:9', KEY: 'dummy' },
    encoding: 'utf8',
  });
  check(bankOut.includes('all question bank tests pass'), 'A14: bank.test.mjs passes with WORKER=http://127.0.0.1:9 and KEY=dummy');

  if (failed) { console.error(`${failed} bench checks failed`); process.exit(1); }
}
