// The question bank's licence gate (governance/licences): what passes, and
// that everything else is refused with a reason.
import { licenceVerdict, licenceId, allowlist } from '../../governance/licences/licences.mjs';

let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}
const pass = v => v.ok === true;
const refused = v => v.ok === false && typeof v.reason === 'string' && v.reason.length > 0;

const pmc = 'https://pmc.ncbi.nlm.nih.gov/articles/PMC1234567/';
check('a CC BY 4.0 PMC article passes', pass(licenceVerdict({ source: 'pmc-open-access', licence: 'CC BY 4.0', url: pmc })));
check('so does CC0, written as a URL', pass(licenceVerdict({ source: 'pmc-open-access', licence: 'http://creativecommons.org/publicdomain/zero/1.0/', url: pmc })));
check('and CC BY 3.0 as a licence URL', licenceVerdict({ source: 'pmc-open-access', licence: 'https://creativecommons.org/licenses/by/3.0/', url: pmc }).licence === 'CC-BY-3.0');
check('a pass carries its attribution and licence URL', licenceVerdict({ source: 'pmc-open-access', licence: 'CC-BY-4.0', url: pmc }).licenceUrl === allowlist.licences['CC-BY-4.0'].url);
for (const lic of ['CC BY-NC 4.0', 'CC BY-SA 4.0', 'CC BY-ND 4.0', 'CC BY-NC-SA 4.0', 'https://creativecommons.org/licenses/by-nc/4.0/',
                   'Creative Commons Attribution-NonCommercial 4.0', 'Attribution-ShareAlike']) {
  check(`refused: ${lic}`, refused(licenceVerdict({ source: 'pmc-open-access', licence: lic, url: pmc })));
}
check('refused: no licence', refused(licenceVerdict({ source: 'pmc-open-access', url: pmc })));
check('refused: a licence that cannot be read', refused(licenceVerdict({ source: 'pmc-open-access', licence: 'see publisher', url: pmc })));
check('refused: CC BY 1.0, not on the list', refused(licenceVerdict({ source: 'pmc-open-access', licence: 'CC BY 1.0', url: pmc })));
check('refused: an unknown source', refused(licenceVerdict({ source: 'statpearls', licence: 'CC BY 4.0', url: 'https://www.ncbi.nlm.nih.gov/books/NBK1/' })));
check('refused: a pending source, until its licence is read', refused(licenceVerdict({ source: 'open-rn', licence: 'CC BY 4.0', url: 'https://wtcs.pressbooks.pub/nursingfundamentals/' })));
check('refused: a URL outside the source', refused(licenceVerdict({ source: 'pmc-open-access', licence: 'CC BY 4.0', url: 'https://example.com/PMC1/' })));
check('refused: a look-alike host', refused(licenceVerdict({ source: 'pmc-open-access', licence: 'CC BY 4.0', url: 'https://pmc.ncbi.nlm.nih.gov.evil.example/x' })));
check('refused: plain http', refused(licenceVerdict({ source: 'pmc-open-access', licence: 'CC BY 4.0', url: 'http://pmc.ncbi.nlm.nih.gov/articles/PMC1/' })));
check('refused: no URL', refused(licenceVerdict({ source: 'pmc-open-access', licence: 'CC BY 4.0' })));

const mp = 'US-GOV-PD-MEDLINEPLUS';
check('a MedlinePlus health topic passes', pass(licenceVerdict({ source: 'medlineplus-health-topics', licence: mp, url: 'https://medlineplus.gov/asthma.html' })));
check('refused: the A.D.A.M. encyclopedia', refused(licenceVerdict({ source: 'medlineplus-health-topics', licence: mp, url: 'https://medlineplus.gov/ency/article/000141.htm' })));
check('refused: ASHP drug monographs', refused(licenceVerdict({ source: 'medlineplus-health-topics', licence: mp, url: 'https://medlineplus.gov/druginfo/meds/a682878.html' })));
check('refused: a CC licence on a MedlinePlus page', refused(licenceVerdict({ source: 'medlineplus-health-topics', licence: 'CC BY 4.0', url: 'https://medlineplus.gov/asthma.html' })));

check('licence ids: CC BY 4.0 / cc-by-4.0 / CC0', licenceId('CC BY 4.0') === 'CC-BY-4.0' && licenceId('cc-by-4.0') === 'CC-BY-4.0' && licenceId('CC0') === 'CC0-1.0');
check('every allowed source names a licence that was read, with its URL and date',
  allowlist.sources.filter(s => s.status === 'allowed').every(s => s.licences.every(l => allowlist.licences[l]?.url && /^\d{4}-\d{2}-\d{2}$/.test(allowlist.licences[l]?.read))));
check('no licence on the list restricts use',
  Object.keys(allowlist.licences).every(id => !/-(NC|ND|SA)\b/.test(id)));

console.log(failed ? `\n${failed} LICENCE TEST FAILURE(S)` : '\nALL LICENCE TESTS PASS');
process.exit(failed ? 1 : 0);
