// Google retired gemini-3.5-flash and sends its requests to 3.6 Flash, which
// is never to be used: no model list, price, share or comment in server/
// may name either. 3.5 Flash-Lite is still current and stays.
//
// Run: node server/tests/retired-models.test.mjs

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const server = join(here, '..');
const self = fileURLToPath(import.meta.url);
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };

// built from parts so this file does not name them itself
const retired = new RegExp(['gemini-3\\.5-flash(?!-lite)', 'gemini-3\\.6'].join('|'), 'g');

function* files(dir) {
  for (const name of readdirSync(dir)) {
    if (name === 'node_modules' || name.startsWith('.')) continue;
    const path = join(dir, name);
    if (statSync(path).isDirectory()) yield* files(path);
    else if (/\.(m?js|toml|json|sql|md|txt)$/.test(name) && path !== self) yield path;
  }
}

const seen = [];
let scanned = 0;
for (const path of files(server)) {
  scanned++;
  readFileSync(path, 'utf8').split('\n').forEach((line, i) => {
    for (const m of line.matchAll(retired)) seen.push(`${relative(server, path)}:${i + 1} ${m[0]}`);
  });
}
ok(scanned > 20, `server/ scanned (${scanned} files)`);
ok(seen.length === 0, `no file in server/ names gemini-3.5-flash or gemini-3.6${seen.length ? ': ' + seen.join(', ') : ''}`);

// and the lists as the Worker reads them
const toml = readFileSync(join(server, 'wrangler.toml'), 'utf8');
for (const key of ['CLOUD_MODELS', 'FREE_MODEL_SHARES', 'TRANSCRIBE_MODELS', 'PAID_MODELS', 'GEMINI_PRICES', 'GEMINI_AUDIO_PRICES']) {
  const value = toml.match(new RegExp(`^${key} = "([^"]*)"`, 'm'))?.[1];
  ok(value !== undefined && !retired.test(value), `wrangler.toml ${key} has no retired Flash`);
  retired.lastIndex = 0;
}
ok(/^TRANSCRIBE_MODELS = "gemini-3\.8-flash,gemini-3\.5-flash-lite"$/m.test(toml), 'transcription: 3.8 Flash first, Flash-Lite behind it');

if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
