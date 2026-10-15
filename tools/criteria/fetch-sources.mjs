#!/usr/bin/env node
// Fetches every source in server/criteria/sources.json, turns it into text
// the same way each time, and compares it with the pinned snapshot the
// registry's quotes are proven against (server/criteria/snapshots). A source
// that changed is reported, never silently re-pinned: a changed guideline is
// a new edition (naskh), and its rules are reviewed again.
//
//   node tools/criteria/fetch-sources.mjs            compare (exit 1 on drift)
//   node tools/criteria/fetch-sources.mjs --write    write the snapshots and
//                                                    print their hashes for
//                                                    sources.json
//
// HTML: the page's <main>, scripts and styles dropped, one line per block.
// PDF: pdftotext (poppler), page by page as each source lists, with an
// optional crop box for a page set in columns. Needs network access and
// pdftotext; nothing in the Worker or the tests runs it.
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const dir = join(root, 'server', 'criteria');
const sources = JSON.parse(readFileSync(join(dir, 'sources.json'), 'utf8')).sources;
const write = process.argv.includes('--write');

const ENTITIES = { nbsp: ' ', amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", mdash: '—', ndash: '–', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', hellip: '…',
  alpha: 'α', beta: 'β', gamma: 'γ', delta: 'δ', kappa: 'κ', mu: 'μ', micro: 'µ', deg: '°', plusmn: '±', le: '≤', ge: '≥', times: '×', middot: '·', bull: '•',
  reg: '®', trade: '™', copy: '©', shy: '' };

/// A page's main text, one line per block, whitespace collapsed.
export function htmlText(html) {
  let t = String(html);
  const main = /<main[\s\S]*?<\/main>/i.exec(t);
  if (main) t = main[0];
  t = t.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>|<!--[\s\S]*?-->/gi, '');
  t = t.replace(/<(?:li|p|h\d|tr|div|br|td|th|dt|dd|section|article|ul|ol|table)\b[^>]*>/gi, '\n');
  t = t.replace(/<[^>]+>/g, '');
  t = t.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
    if (e[0] === '#') return String.fromCodePoint(e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10));
    return ENTITIES[e.toLowerCase()] ?? m;
  });
  return tidy(t);
}

const tidy = t => t.replace(/ /g, ' ').split('\n').map(l => l.replace(/[ \t\r\f\v]+/g, ' ').trim()).filter(Boolean).join('\n') + '\n';

function pdfText(file, pages) {
  const parts = [];
  for (const p of pages) {
    const args = ['-f', String(p.page), '-l', String(p.page)];
    if (p.crop) args.push('-x', String(p.crop[0]), '-y', String(p.crop[1]), '-W', String(p.crop[2]), '-H', String(p.crop[3]));
    const text = execFileSync('pdftotext', [...args, file, '-'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    parts.push(`[page ${p.page}${p.crop ? ', column' : ''}]\n` + tidy(text));
  }
  return parts.join('');
}

// curl, not fetch: it goes through the machine's proxy settings as they are
function download(url, file) {
  execFileSync('curl', ['-sSLf', '-m', '120', '-o', file, url], { stdio: ['ignore', 'ignore', 'pipe'] });
}

async function fetchText(src) {
  const tmp = mkdtempSync(join(tmpdir(), 'criteria-'));
  const file = join(tmp, 'source');
  download(src.url, file);
  if (src.snapshot.extract === 'html-main') return htmlText(readFileSync(file, 'utf8'));
  if (src.snapshot.extract === 'pdf-pages') return pdfText(file, src.snapshot.pages);
  throw new Error(`${src.id}: unknown extract ${src.snapshot.extract}`);
}

const sha256 = text => createHash('sha256').update(text, 'utf8').digest('hex');

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  let drift = 0;
  for (const src of sources) {
    if (!src.snapshot) continue;
    const path = join(dir, src.snapshot.file);
    let text;
    try { text = await fetchText(src); } catch (e) { console.log(`UNREAD ${src.id}: ${e.message}`); drift++; continue; }
    const hash = sha256(text);
    if (write) {
      writeFileSync(path, text);
      console.log(`${src.id} ${hash} (${text.length} chars)`);
    } else if (hash !== src.snapshot.sha256) {
      drift++;
      console.log(`CHANGED ${src.id}: now ${hash}, pinned ${src.snapshot.sha256}; review its rules against the new text`);
    } else console.log(`same ${src.id}`);
  }
  process.exit(drift ? 1 : 0);
}
