// Reads every licence page on the allowlist again and says whether its title
// still matches what was recorded, so a changed or moved licence is noticed.
// Run: node governance/licences/read-live.mjs (exit 1 on any mismatch).
import { allowlist } from './licences.mjs';

let bad = 0;
for (const [id, l] of Object.entries(allowlist.licences)) {
  try {
    const res = await fetch(l.url, { redirect: 'follow', signal: AbortSignal.timeout(20_000) });
    const html = await res.text();
    const title = (html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] || '').replace(/\s+/g, ' ').replace(/&amp;/g, '&').trim();
    const same = res.ok && title.includes(l.title);
    if (!same) bad++;
    console.log(`${same ? 'ok  ' : 'DIFF'} ${id} ${res.status} "${title}"`);
  } catch (e) {
    bad++;
    console.log(`FAIL ${id} ${e.message}`);
  }
}
process.exit(bad ? 1 : 0);
