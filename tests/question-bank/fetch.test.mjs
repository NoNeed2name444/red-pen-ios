// The question bank's source fetcher (tools/question-bank/fetch.mjs), run
// against responses recorded from the real endpoints on 2026-10-01 (in
// fixtures/), with no network: what it keeps, what it refuses and why, and
// that it asks politely.
import { readFileSync } from 'node:fs';
import {
  parseMedlinePlus, parsePmcArticles, pmcLicence, parseXml, find, judge, run, throttle, chunk, parseArgs,
  USER_AGENT, htmlToText,
} from '../../tools/question-bank/fetch.mjs';
import { licenceVerdict } from '../../governance/licences/licences.mjs';

let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}
const fixture = name => readFileSync(new URL(`./fixtures/${name}`, import.meta.url), 'utf8');
const retrieved = '2026-10-01';
const REQUIRED = ['source', 'url', 'licence', 'licenceUrl', 'attribution', 'title', 'retrieved', 'text'];
const complete = p => REQUIRED.every(k => typeof p[k] === 'string' && p[k].length > 0);

// --- MedlinePlus -----------------------------------------------------------
const mpXml = fixture('medlineplus-asthma-topic.xml');
const mp = parseMedlinePlus(mpXml, { retrieved });
check('MedlinePlus: both recorded health topics are read', mp.length === 2, JSON.stringify(mp.map(m => m.url)));
check('MedlinePlus: the title is the topic name', mp[0].title === 'Asthma', mp[0].title);
check('MedlinePlus: the summary is plain text, no markup or entities left',
  mp[0].text.startsWith('What is asthma?') && !/[<>]|&[a-z]+;/.test(mp[0].text) && mp[0].text.length > 1000, mp[0].text.slice(0, 120));
check('MedlinePlus: list items keep their own lines', /\n- Allergic asthma/.test(mp[0].text));
const mpKept = judge(mp[0]);
check('MedlinePlus: a health topic summary is kept', mpKept.kept === true, JSON.stringify(mpKept.refusal));
check('MedlinePlus: the kept passage has source, URL, licence and licence URL, attribution, title, date and text', complete(mpKept.passage), JSON.stringify(mpKept.passage).slice(0, 300));
check('MedlinePlus: attribution credits MedlinePlus and the NLM, with the page URL',
  /Courtesy of MedlinePlus from the National Library of Medicine/.test(mpKept.passage.attribution) && mpKept.passage.attribution.includes('https://medlineplus.gov/asthma.html'));
check('MedlinePlus: the licence is the public-domain one, linked to the page that says so',
  mpKept.passage.licence === 'US-GOV-PD-MEDLINEPLUS' && mpKept.passage.licenceUrl === 'https://medlineplus.gov/about/using/usingcontent/');
check('MedlinePlus: the retrieved date is kept', mpKept.passage.retrieved === retrieved);
check('the older highlighted search format reads too',
  parseMedlinePlus('<nlmSearchResult><list><document url="https://medlineplus.gov/asthma.html"><content name="title">&lt;span class="qt0"&gt;Asthma&lt;/span&gt;</content><content name="FullSummary">&lt;p&gt;Asthma is a chronic lung disease of the airways.&lt;/p&gt;</content></document></list></nlmSearchResult>', { retrieved })[0].title === 'Asthma');

// URL exclusion: the same recorded topic, as if the service had pointed at a
// copyrighted part of MedlinePlus or somewhere else.
for (const [label, url] of [
  ['the A.D.A.M. encyclopedia (/ency/)', 'https://medlineplus.gov/ency/article/000141.htm'],
  ['ASHP drug monographs (/druginfo/)', 'https://medlineplus.gov/druginfo/meds/a682878.html'],
  ['images', 'https://medlineplus.gov/images/asthma.jpg'],
  ['another host', 'https://example.com/asthma.html'],
  ['plain http', 'http://medlineplus.gov/asthma.html'],
]) {
  const moved = parseMedlinePlus(mpXml.replaceAll('https://medlineplus.gov/asthma.html', url), { retrieved })[0];
  const v = judge(moved);
  check(`URL exclusion: refused, ${label}`, v.kept === false && v.refusal.reason.length > 0 && v.refusal.url === url, JSON.stringify(v));
}
check('refused: a summary with no text', judge({ ...mp[0], text: '' }).kept === false);

// --- PMC licences -----------------------------------------------------------
const ccBy = parsePmcArticles(fixture('pmc-cc-by-4.0.xml'), { retrieved });
check('PMC CC BY: the article is read as several passages, abstract first', ccBy.length > 1 && ccBy[0].section === 'Abstract', ccBy.map(p => p.section).join());
check('PMC CC BY: its licence is read from the article itself', ccBy[0].licence === 'https://creativecommons.org/licenses/by/4.0/', ccBy[0].licence);
check('PMC CC BY: the PMC id, DOI, journal, year and authors are read',
  ccBy[0].pmcid === 'PMC13626604' && ccBy[0].doi === '10.1002/clt2.70210' && /Clinical and Translational Allergy/.test(ccBy[0].journal) && ccBy[0].year === '2026' && ccBy[0].authors[0] === 'Cagatay Karaaslan');
const kept = ccBy.map(judge);
check('PMC CC BY: every passage is kept', kept.every(k => k.kept), JSON.stringify(kept.find(k => !k.kept)));
const p0 = kept[0].passage;
check('PMC CC BY: the passage has every field the bank needs', complete(p0), JSON.stringify(p0).slice(0, 300));
check('PMC CC BY: licence id CC-BY-4.0 and the legal code URL', p0.licence === 'CC-BY-4.0' && p0.licenceUrl === 'https://creativecommons.org/licenses/by/4.0/legalcode.en');
check('PMC CC BY: the URL is the article on PMC', p0.url === 'https://pmc.ncbi.nlm.nih.gov/articles/PMC13626604/');
check('PMC CC BY: attribution names authors, title, journal, DOI and licence',
  /^Cagatay Karaaslan, .*et al\. \(2026\)\. Bioassays in Allergy/.test(p0.attribution) && p0.attribution.includes('doi:10.1002/clt2.70210') && p0.attribution.includes('CC BY 4.0'), p0.attribution);
check('PMC CC BY: the publisher\'s licence statement is kept as read', /open access article under the terms/.test(p0.licenceStatement));
check('PMC CC BY: citation markers, figures and tables are left out of the text', ccBy.every(p => !/[<>]/.test(p.text)) && !/Figure \d+\s*$/.test(ccBy[1].text));
// Captions, table notes and supplementary material are often reproduced from
// elsewhere "with permission", which the article's CC BY does not cover.
const allCcBy = parsePmcArticles(fixture('pmc-cc-by-4.0.xml'), { retrieved, maxPassages: 1000 });
check('PMC CC BY: no figure caption reaches a passage (FIGURE 2, FIGURE 3)',
  allCcBy.length > 0 && allCcBy.every(p => !p.text.includes('Schematic representation of histological staining') && !p.text.includes('Graphical summary of major molecular biological assays')));
check('PMC CC BY: the prose around the figure is still kept', allCcBy.some(p => p.text.includes('In allergy research, histological methods assess epithelial barrier integrity')));
{
  const synthetic = `<article><front><article-meta><article-id pub-id-type="pmc">PMC2</article-id><title-group><article-title>T</article-title></title-group>
    <permissions><license xlink:href="https://creativecommons.org/licenses/by/4.0/"><license-p>CC BY.</license-p></license></permissions></article-meta></front>
    <body><sec><title>Results</title><p>Own prose that the article's licence covers, long enough to keep as a passage.</p>
      <fig><caption><p>Reproduced with permission from Elsevier, copyright 2019 (figure).</p></caption></fig>
      <table-wrap><caption><p>Reproduced with permission (table caption).</p></caption><table><tr><td><p>cell paragraph</p></td></tr></table>
        <table-wrap-foot><fn><p>Reproduced with permission (table footnote).</p></fn></table-wrap-foot></table-wrap>
      <supplementary-material><caption><p>Reproduced with permission (supplement).</p></caption></supplementary-material>
      <boxed-text><p>Reproduced with permission (box).</p></boxed-text>
      <sec><title>Nested</title><p>A nested section's own paragraph is still read as part of the section.</p></sec></sec></body></article>`;
  const ps = parsePmcArticles(synthetic, { retrieved, maxPassages: 50 });
  const all = ps.map(p => p.text).join(' ');
  check('PMC: paragraphs inside figures, tables, footnotes, supplements and boxes are not collected', !/Reproduced with permission|cell paragraph/.test(all), all);
  check('PMC: the section\'s own and nested paragraphs are kept', all.includes('Own prose that the article') && all.includes('A nested section\'s own paragraph'), all);
}
check('PMC: passages stay a question\'s size', ccBy.every(p => p.text.length <= 4000 || !p.text.includes('\n')));
check('every kept passage passes the licence gate on its own', [p0, mpKept.passage].every(p => licenceVerdict({ source: p.source, licence: p.licence, url: p.url }).ok));

const nc = parsePmcArticles(fixture('pmc-cc-by-nc-4.0.xml'), { retrieved });
check('PMC CC BY-NC: the licence is read as by-nc', nc[0].licence === 'https://creativecommons.org/licenses/by-nc/4.0/', nc[0].licence);
check('PMC CC BY-NC: every passage refused, with the reason', nc.every(c => { const j = judge(c); return !j.kept && /restricts use/.test(j.refusal.reason); }));

const none = parsePmcArticles(fixture('pmc-no-licence.xml'), { retrieved });
check('PMC with no licence: read as having none', none.length >= 1 && none[0].licence === null && /Cochrane/.test(none[0].licenceStatement ?? ''), JSON.stringify(none[0]?.licence));
const noneJ = judge(none[0]);
check('PMC with no licence: refused, and the reason says so', noneJ.kept === false && /no licence stated/.test(noneJ.refusal.reason), JSON.stringify(noneJ));

// Licence statements the recorded articles do not cover.
const art = permissions => find(parseXml(`<article><front><article-meta><permissions>${permissions}</permissions></article-meta></front></article>`), 'article');
const lic = permissions => pmcLicence(art(permissions)).licence;
const gate = permissions => licenceVerdict({ source: 'pmc-open-access', licence: lic(permissions), url: 'https://pmc.ncbi.nlm.nih.gov/articles/PMC1/' });
check('licence on the <license> link: CC0 passes', gate('<license xlink:href="https://creativecommons.org/publicdomain/zero/1.0/"><license-p>Public domain dedication.</license-p></license>').licence === 'CC0-1.0');
check('licence only as a URL in the text: CC BY 2.0 passes', gate('<license><license-p>Distributed under http://creativecommons.org/licenses/by/2.0, which permits use.</license-p></license>').licence === 'CC-BY-2.0');
check('refused: a CC BY link whose text adds a non-commercial term', gate('<license xlink:href="https://creativecommons.org/licenses/by/4.0/"><license-p>Reuse is permitted provided it is not used for commercial purposes.</license-p></license>').ok === false);
check('refused: license-type cc-by-nc-nd with a bare statement', gate('<license license-type="cc-by-nc-nd"><license-p>Open access.</license-p></license>').ok === false);
check('refused: a share-alike link', gate('<license><ali:license_ref>https://creativecommons.org/licenses/by-sa/4.0/</ali:license_ref></license>').ok === false);
check('refused: "open access" with no named licence', gate('<license license-type="open-access"><license-p>This article is open access.</license-p></license>').ok === false);
check('refused: a passage with no PMC id has no URL', judge({ ...ccBy[0], url: null }).kept === false);

// --- a whole run, with recorded responses and no network --------------------
const requests = [];
const waits = [];
const routes = (url, failing) => {
  const u = new URL(url);
  if (failing && url.includes(failing)) return { ok: false, status: 503, text: async () => 'busy' };
  if (u.host === 'wsearch.nlm.nih.gov') return { ok: true, status: 200, text: async () => mpXml };
  if (u.pathname.endsWith('/esearch.fcgi')) return { ok: true, status: 200, text: async () => JSON.stringify({ esearchresult: { idlist: ['13626604', '13625040', '13429289'] } }) };
  if (u.pathname.endsWith('/efetch.fcgi')) {
    const xml = ['pmc-cc-by-4.0.xml', 'pmc-cc-by-nc-4.0.xml', 'pmc-no-licence.xml'].map(f => fixture(f).replace(/^<\?xml[^>]*\?>/, '').replace(/<!DOCTYPE[^>]*>/, '').replace(/<\/?pmc-articleset>/g, '')).join('');
    return { ok: true, status: 200, text: async () => `<?xml version="1.0"?><pmc-articleset>${xml}</pmc-articleset>` };
  }
  return { ok: false, status: 404, text: async () => '' };
};
const fakeFetch = failing => async (url, init) => { requests.push({ url, ua: init?.headers?.['User-Agent'] }); return routes(url, failing); };
const out = [], refused = [], logs = [];
const counts = await run({ topics: ['asthma'], retrieved, fetchImpl: fakeFetch(), apiKey: '', email: '', keep: p => out.push(p), refuse: r => refused.push(r), log: m => logs.push(m), sleep: async ms => { waits.push(ms); } });
check('run: MedlinePlus and CC BY passages kept', out.some(p => p.source === 'medlineplus-health-topics') && out.some(p => p.licence === 'CC-BY-4.0'), JSON.stringify(counts));
check('run: nothing NC or unlicensed reaches the bank', out.every(p => ['CC-BY-4.0', 'US-GOV-PD-MEDLINEPLUS'].includes(p.licence)) && !out.some(p => /PMC13625040|PMC13429289/.test(p.url)));
check('run: each refused article is logged once, with its reason', refused.length === 2 && refused.every(r => r.reason && r.url) && refused.some(r => /restricts use/.test(r.reason)) && refused.some(r => /no licence/.test(r.reason)), JSON.stringify(refused));
check('run: every kept passage is complete', out.every(complete));
check('run: only the sanctioned interfaces are asked',
  requests.every(r => ['https://wsearch.nlm.nih.gov/ws/query', 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi', 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi'].includes(r.url.split('?')[0])), requests.map(r => r.url).join('\n'));
check('run: never the encyclopedia or the drug monographs', requests.every(r => !/\/ency\/|\/druginfo\//.test(r.url)));
check('run: every request carries the polite User-Agent', requests.every(r => r.ua === USER_AGENT) && /\+https:\/\//.test(USER_AGENT));
check('run: NCBI requests name the tool and ask only the OA subset',
  requests.filter(r => r.url.includes('eutils')).every(r => new URL(r.url).searchParams.get('tool') === 'stethoscore-question-bank') &&
  new URL(requests.find(r => r.url.includes('esearch')).url).searchParams.get('term').includes('open access[filter]'));
check('run: no API key is sent when there is none', requests.every(r => !r.url.includes('api_key')));
check('run: the articles come in one efetch, not one each', requests.filter(r => r.url.includes('efetch')).length === 1);

// Fail-safe: one source failing skips that topic for that source, logs it, and keeps the rest.
const out2 = [], logs2 = [];
const c2 = await run({ topics: ['asthma'], retrieved, fetchImpl: fakeFetch('esearch.fcgi'), apiKey: '', keep: p => out2.push(p), refuse: () => {}, log: m => logs2.push(m), sleep: async () => {} });
check('fail-safe: a failing PMC search is retried, logged and counted', c2.failed === 1 && logs2.some(l => /PMC "asthma" failed: HTTP 503/.test(l)) && requests.filter(r => r.url.includes('esearch')).length === 1 + 3, logs2.join('|'));
check('fail-safe: MedlinePlus passages are still kept', out2.length >= 1 && out2.every(p => p.source === 'medlineplus-health-topics'));

// --- rate limits -------------------------------------------------------------
let t = 0;
const slept = [];
const gate3 = throttle(3, { now: () => t, sleep: async ms => { slept.push(ms); t += ms; } });
for (let i = 0; i < 4; i++) await gate3();
check('NCBI without a key: no more than 3 requests a second', slept.length === 3 && slept.every(ms => ms >= 334), JSON.stringify(slept));
t = 0; slept.length = 0;
const gate10 = throttle(10, { now: () => t, sleep: async ms => { slept.push(ms); t += ms; } });
for (let i = 0; i < 4; i++) await gate10();
check('NCBI with a key: no more than 10 a second', slept.every(ms => ms >= 100) && slept.every(ms => ms < 334), JSON.stringify(slept));
check('run: NCBI calls were spaced by the 3-a-second gate', waits.filter(ms => ms > 0).every(ms => ms >= 300), JSON.stringify(waits));

// --- small pieces ------------------------------------------------------------
check('chunk: paragraphs join up to the limit', JSON.stringify(chunk(['aaaa', 'bbbb', 'cccc'], 9)) === JSON.stringify(['aaaa\nbbbb', 'cccc']));
check('htmlToText: entities and tags', htmlToText('<p>A &amp; B&nbsp;&lt;C&gt;</p><ul><li>one</li></ul>') === 'A & B <C>\n- one');
check('args: --out and --topics are required', (() => { try { parseArgs(['--topics', 'a']); return false; } catch { return true; } })());
check('args: topics split on commas', parseArgs(['--out', 'x.jsonl', '--topics', 'asthma, heart failure']).topics.join('|') === 'asthma|heart failure');

console.log(failed ? `\n${failed} FETCHER TEST FAILURE(S)` : '\nALL FETCHER TESTS PASS');
process.exit(failed ? 1 : 0);
