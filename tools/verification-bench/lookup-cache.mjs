// A disk-cached fetcher for the benches that spend no neurons and use the
// network only (retrieval-set.mjs, proof-only.mjs): the sources are free and
// keyless (MedlinePlus, openFDA, RxNav, Europe PMC, NLM's MeSH lookup, the
// Hugging Face datasets server), and a bench reads the same pages and labels again
// and again, so every answer is kept on disk under one directory, which is
// never in the repository and never grows past a byte cap.
//
// It is a fetcher (url, init) -> Response, so the engine's own lookups
// (server/evidence.js) run on it unchanged. Only answers that say something
// are kept: a 200, or a 404 (openFDA's "no label matches"); a rate limit, a
// server error or a network failure is never kept, so the next run asks
// again, and is counted: `tally` keeps lookups made, answered from disk,
// retried and failed, by status, apart from "the source has nothing".
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export const CACHE_CAP_BYTES = 200 * 1024 * 1024;
const ENTRY_MAX_BYTES = 3 * 1024 * 1024;

const sizeOf = dir => {
  let n = 0;
  if (!existsSync(dir)) return 0;
  for (const f of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, f.name);
    n += f.isDirectory() ? sizeOf(p) : statSync(p).size;
  }
  return n;
};

/// The cache directory, with the bytes it holds counted once and kept up to
/// date; `put` writes nothing past `cap` (the run goes on, uncached).
export function diskCache(dir, { cap = CACHE_CAP_BYTES } = {}) {
  mkdirSync(dir, { recursive: true });
  let used = sizeOf(dir);
  const file = key => join(dir, `${createHash('sha256').update(key).digest('hex').slice(0, 40)}.json`);
  return {
    dir,
    get used() { return used; },
    get(key) {
      try { return JSON.parse(readFileSync(file(key), 'utf8')); } catch { return null; }
    },
    put(key, value) {
      const text = JSON.stringify(value);
      if (text.length > ENTRY_MAX_BYTES || used + text.length > cap) return false;
      try { writeFileSync(file(key), text); used += text.length; return true; } catch { return false; }
    },
  };
}

/// What a bench says of its lookups: made, answered from disk, retried,
/// failed (and how: by status, "network" for no answer), and kept.
export const newTally = () => ({ lookups: 0, disk: 0, network: 0, retried: 0, failed: 0, byStatus: {}, bytes: 0 });

// a politeness gap per host, so a bench is not an abuse of a free service
const GAP_MS = { 'wsearch.nlm.nih.gov': 700, 'api.fda.gov': 300, 'www.ebi.ac.uk': 200, 'id.nlm.nih.gov': 150, 'datasets-server.huggingface.co': 400, 'rxnav.nlm.nih.gov': 60, 'medlineplus.gov': 500 };
const sleep = ms => new Promise(r => setTimeout(r, ms));
// when each host was last asked: shared by every fetcher, so a bench that
// makes a fetcher per item still keeps its gaps
const last = new Map();

/// A fetcher over `fetchImpl` that answers from the disk cache first.
/// A failed answer (429, 5xx, no answer) is asked once more after `retryMs`
/// (the source's Retry-After when it says, up to ten seconds), then returned
/// as it is for the caller to count. `gap: false` is for tests.
export function cachedFetcher({ cache, fetchImpl = fetch, tally = newTally(), retryMs = 3000, gap = true } = {}) {
  const spaced = async host => {
    if (!gap || !GAP_MS[host]) return;
    const now = Date.now();
    const at = Math.max(now, (last.get(host) || 0) + GAP_MS[host]);
    last.set(host, at);
    if (at > now) await sleep(at - now);
  };
  const fetcher = async (url, init = {}) => {
    const key = String(url);
    tally.lookups++;
    const hit = cache?.get(key);
    if (hit) { tally.disk++; return new Response(hit.text, { status: hit.status }); }
    let res = null, status = 'network';
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        await spaced(new URL(key).host);
        tally.network++;
        res = await fetchImpl(key, init);
        status = res.status;
        if (res.status === 200 || res.status === 404) break;
        const after = Number(res.headers?.get?.('retry-after'));
        if (attempt === 0) { tally.retried++; await sleep(Math.min(10_000, after > 0 ? after * 1000 : retryMs)); }
      } catch (error) {
        res = null; status = init.signal?.aborted ? 'timeout' : 'network';
        if (attempt === 0) { tally.retried++; await sleep(retryMs); }
      }
    }
    if (res && (res.status === 200 || res.status === 404)) {
      const text = await res.text();
      tally.bytes += text.length;
      cache?.put(key, { status: res.status, text });
      return new Response(text, { status: res.status });
    }
    tally.failed++;
    tally.byStatus[status] = (tally.byStatus[status] || 0) + 1;
    if (!res) throw new Error(`${key.split('?')[0]}: ${status}`);
    return res;
  };
  fetcher.tally = tally;
  return fetcher;
}

/// A page of JSON by url, through a cached fetcher; throws when it could not
/// be read (a bench that cannot read its questions has nothing to say).
export function jsonPage(fetcher) {
  return async url => {
    const res = await fetcher(url);
    if (!res.ok) throw new Error(`${String(url).split('?')[0]}: ${res.status}`);
    return JSON.parse(await res.text());
  };
}
