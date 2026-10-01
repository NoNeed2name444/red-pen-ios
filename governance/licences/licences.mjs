// Whether a passage may feed the question bank: its source is on the
// allowlist and allowed, its licence is one the source allows, and its URL
// is inside the source. Anything else is refused, with the reason, and a
// licence carrying NonCommercial, NoDerivatives or ShareAlike is refused
// whatever the list says (plan §22d: share-alike would force the app open).
import { readFileSync } from 'node:fs';

const here = new URL('./allowlist.json', import.meta.url);
export const allowlist = JSON.parse(readFileSync(here, 'utf8'));

const RESTRICTED = /\b(nc|nd|sa|noncommercial|non-commercial|noderivatives|no-derivatives|noderivs|sharealike|share-alike)\b/i;

/// A licence as written in the wild ("CC BY 4.0", "cc-by", a Creative
/// Commons URL) as an allowlist id, or null when it cannot be read.
export function licenceId(raw) {
  if (typeof raw !== 'string' || !raw.trim()) return null;
  const text = raw.trim();
  if (allowlist.licences[text]) return text;
  const lower = text.toLowerCase();
  const url = lower.match(/creativecommons\.org\/(licenses|publicdomain)\/([a-z-]+)\/(\d\.\d)/);
  if (url) {
    if (url[1] === 'publicdomain') return url[2] === 'zero' && url[3] === '1.0' ? 'CC0-1.0' : null;
    return url[2] === 'by' ? `CC-BY-${url[3]}` : `CC-${url[2].toUpperCase()}-${url[3]}`;
  }
  if (/^cc[\s-]?0(\s*1\.0)?$/.test(lower) || lower === 'cc0 1.0 universal') return 'CC0-1.0';
  const named = lower.match(/^(?:cc|creative commons)[\s-]+(by(?:[\s-]+(?:nc|nd|sa))*)[\s-]*(?:(\d\.\d)(?:\s+\w+)?)?$/);
  if (named) {
    const parts = named[1].split(/[\s-]+/).map(p => p.toUpperCase()).join('-');
    return named[2] ? `CC-${parts}-${named[2]}` : `CC-${parts}`;
  }
  return null;
}

/// {ok: true, source, licence, attribution} or {ok: false, reason}.
export function licenceVerdict({ source, licence, url } = {}) {
  const entry = allowlist.sources.find(s => s.id === source);
  if (!entry) return { ok: false, reason: `source "${source}" is not on the allowlist` };
  if (entry.status !== 'allowed') return { ok: false, reason: `source "${source}" is ${entry.status}: ${entry.note}` };
  if (typeof licence === 'string' && RESTRICTED.test(licence.replace(/creativecommons\.org/gi, ''))) {
    return { ok: false, reason: `licence "${licence}" restricts use (NC, ND or SA)` };
  }
  const id = licenceId(licence);
  if (!id) return { ok: false, reason: `licence "${licence}" cannot be read` };
  if (/-(NC|ND|SA)\b/.test(id)) return { ok: false, reason: `licence ${id} restricts use (NC, ND or SA)` };
  if (!entry.licences.includes(id)) return { ok: false, reason: `licence ${id} is not one ${source} allows` };
  let parsed;
  try { parsed = new URL(url); } catch { return { ok: false, reason: 'no readable URL for the passage' }; }
  if (parsed.protocol !== 'https:') return { ok: false, reason: 'the passage URL is not https' };
  const href = parsed.href;
  if (!entry.urlPrefixes.some(p => href.startsWith(p))) return { ok: false, reason: `URL is outside ${source}` };
  if (entry.excludedPaths.some(p => parsed.pathname.startsWith(p) || parsed.pathname.includes(p))) {
    return { ok: false, reason: `URL is in a part of ${source} that is copyrighted` };
  }
  return { ok: true, source, licence: id, attribution: entry.attribution, licenceUrl: allowlist.licences[id].url };
}
