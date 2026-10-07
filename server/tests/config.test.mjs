// Remote config (config.js): DEFAULTS kept equal to
// docs/launch/config-defaults.json, the precedence stored row > legacy env
// var > DEFAULTS, what an existing deployment reads with no row stored, the
// kill switches over all three, validation, the public view and GET /config.
//
// Run: node server/tests/config.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import worker from '../worker.js';
import {
  DEFAULTS, RANGES, PUBLIC_LIMITS, ENV_MAP, MEMO_MS, envOverrides, merge, validate, effective,
  loadConfig, forgetConfig, flag, limit, accountLimits, killed, publicView, configRoute,
} from '../config.js';

const here = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function d1(db) {
  return {
    prepare(sql) {
      const stmt = db.prepare(sql);
      let args = [];
      const api = {
        bind(...a) { args = a; return api; },
        first() { return stmt.get(...args) ?? null; },
        all() { return { results: stmt.all(...args) }; },
        run() { return { meta: { changes: Number(stmt.run(...args).changes) } }; },
      };
      return api;
    },
  };
}
/// An env whose database has the remote_config table (unified-tables.sql), or
/// none at all, as a deployment that never ran that schema.
function withTable(vars = {}) {
  const db = new DatabaseSync(':memory:');
  db.exec(`CREATE TABLE remote_config (id TEXT PRIMARY KEY, version INTEGER NOT NULL, body TEXT NOT NULL,
           updated_at INTEGER NOT NULL, updated_by TEXT NOT NULL)`);
  return { db, env: { DB: d1(db), ...vars } };
}
function store(db, version, body) {
  db.prepare(`INSERT INTO remote_config (id, version, body, updated_at, updated_by) VALUES ('live', ?, ?, 0, 'test')
              ON CONFLICT (id) DO UPDATE SET version = excluded.version, body = excluded.body`)
    .run(version, typeof body === 'string' ? body : JSON.stringify(body));
}

// MARK: DEFAULTS and the launch document do not drift apart

{
  const doc = JSON.parse(readFileSync(join(here, '..', '..', 'docs', 'launch', 'config-defaults.json'), 'utf8'));
  for (const key of ['flags', 'limits', 'freeShare', 'messages', 'app', 'cache']) {
    ok(same(doc[key], DEFAULTS[key]), `DEFAULTS.${key} is config-defaults.json's ${key}`);
  }
  ok(same(doc._ranges, RANGES), 'RANGES is config-defaults.json _ranges');
  ok(same(doc._public, PUBLIC_LIMITS), 'PUBLIC_LIMITS is config-defaults.json _public');
  const envDoc = Object.fromEntries(Object.entries(doc._env).filter(([k]) => !k.startsWith('any other')));
  ok(same(envDoc, ENV_MAP), 'ENV_MAP is config-defaults.json _env');
  ok(Object.keys(DEFAULTS.limits).every(k => RANGES[k]), 'every limit has a range');
  ok(Object.entries(DEFAULTS.limits).every(([k, v]) => v === null || (v >= RANGES[k][0] && v <= RANGES[k][1])),
     'every default sits inside its range');
  ok(PUBLIC_LIMITS.every(k => k in DEFAULTS.limits), 'every public limit is a limit');
  ok(!PUBLIC_LIMITS.some(k => /usd/i.test(k)), 'no dollar figure is public');
  ok(DEFAULTS.limits.licencePaidModels === 0 && same(RANGES.licencePaidModels, [0, 0]),
     'class access never carries paid AI, and the owner cannot change that');
  ok(validate(Object.fromEntries(['flags', 'limits', 'freeShare', 'messages', 'app', 'cache'].map(k => [k, DEFAULTS[k]]))).ok,
     'DEFAULTS pass their own validation');
}

// MARK: an existing deployment, nothing stored: the worker's numbers today

{
  // wrangler.toml [vars], as the deployed worker has them
  const toml = readFileSync(join(here, '..', 'wrangler.toml'), 'utf8');
  const section = toml.split(/^\[vars\]\s*$/m)[1].split(/^\[/m)[0];
  const vars = {};
  for (const line of section.split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*"([^"]*)"/);
    if (m) vars[m[1]] = m[2];
  }
  const cfg = await loadConfig({ ...vars }, () => 0);
  // what ai.js and tts.js compute from the same vars
  const finite = (v, d) => (v !== undefined && v !== '' && Number.isFinite(Number(v)) ? Number(v) : d);
  ok(cfg.limits.chatDaily === (Number(vars.AI_DAILY_LIMIT) || 400), `chatDaily is AI_DAILY_LIMIT, as ai.js reads it (${cfg.limits.chatDaily})`);
  ok(cfg.limits.transcribeDaily === (Number(vars.TRANSCRIBE_DAILY) || 36), 'transcribeDaily is TRANSCRIBE_DAILY or 36, as ai.js reads it');
  ok(cfg.limits.ttsDaily === (Number(vars.TTS_DAILY_LIMIT) || 300), 'ttsDaily is TTS_DAILY_LIMIT, as tts.js reads it');
  ok(cfg.limits.ownerMonthlyUsd === finite(vars.OWNER_MONTHLY_USD, 20), 'ownerMonthlyUsd is OWNER_MONTHLY_USD or 20, as ai.js reads it');
  const shares = Object.fromEntries((vars.FREE_MODEL_SHARES || '').split(',').filter(Boolean).map(e => e.split(':')).map(([m, n]) => [m, Number(n)]));
  ok(Object.keys(shares).length > 0 && Object.entries(shares).every(([m, n]) => cfg.freeShare[m] === n),
     'each FREE_MODEL_SHARES entry wins over the default share');
  ok(limit(cfg, vars, 'freeShare.gemini-3.5-flash-lite') === shares['gemini-3.5-flash-lite'], 'and limit() reads it');
  ok(Object.keys(DEFAULTS.flags).every(k => flag(cfg, k) === DEFAULTS.flags[k].on), 'every flag as the defaults have it');
  ok(cfg.version === 0, 'version 0 with nothing stored');
}

// MARK: precedence: stored row > legacy env var > DEFAULTS

{
  const none = effective(null, {});
  ok(same(none.limits, DEFAULTS.limits) && same(none.flags, DEFAULTS.flags) && same(none.freeShare, DEFAULTS.freeShare),
     'no env and nothing stored: DEFAULTS');

  const env = effective(null, { AI_DAILY_LIMIT: '250', TTS_DAILY_LIMIT: '12', REFERRALS: 'off', FLAG_SHARE_LINKS: 'off' });
  ok(env.limits.chatDaily === 250 && env.limits.ttsDaily === 12, 'a legacy env var wins over DEFAULTS');
  ok(!flag(env, 'billing.referrals') && !flag(env, 'share.links'), 'a legacy or FLAG_ env var switches a flag');

  ok(effective(null, { AI_DAILY_LIMIT: '30000' }).limits.chatDaily === 30000,
     'a legacy var outside the owner range still wins (an existing deployment keeps its number)');
  ok(effective(null, { AI_DAILY_LIMIT: '-5' }).limits.chatDaily === 400, 'a negative legacy var is ignored');
  ok(effective(null, { SHARES_PER_ACCOUNT: '50' }).limits.sharesPerAccount === 50, 'a var named after a limit sets it');
  ok(effective(null, { SHARES_PER_ACCOUNT: '5000' }).limits.sharesPerAccount === 100, 'but only within its range');
  ok(effective(null, { LICENCE_PAID_MODELS: '1' }).limits.licencePaidModels === 0, 'so class access cannot gain paid AI from an env var');
  ok(effective(null, { AI_DAILY_LIMIT: '250', CHAT_DAILY: '90' }).limits.chatDaily === 250, 'the legacy name wins over the derived one');
  ok(effective(null, { AI_DAILY_LIMIT: '', TTS_DAILY_LIMIT: 'lots' }).limits.chatDaily === 400
     && effective(null, { TTS_DAILY_LIMIT: 'lots' }).limits.ttsDaily === 300, 'a blank or unreadable var changes nothing');
  ok(flag(effective(null, { REFERRALS: 'maybe' }), 'billing.referrals'), 'an unreadable flag var changes nothing');

  const stored = effective({ limits: { chatDaily: 100 }, flags: { 'billing.referrals': { on: true } } },
                           { AI_DAILY_LIMIT: '250', TTS_DAILY_LIMIT: '12', REFERRALS: 'off' }, 7);
  ok(stored.limits.chatDaily === 100, 'a stored limit wins over the env var');
  ok(stored.limits.ttsDaily === 12, 'a limit the row leaves out still comes from the env');
  ok(flag(stored, 'billing.referrals'), 'a stored flag wins over the env var');
  ok(stored.version === 7, 'the stored version is carried');

  const junk = effective({ flags: { 'made.up': { on: true } }, limits: { madeUp: 3, chatDaily: 999999, ttsDaily: 'x' }, freeShare: { 'new-model': 3 } }, {});
  ok(!('made.up' in junk.flags) && !('madeUp' in junk.limits) && !('new-model' in junk.freeShare),
     'a stored body cannot add a flag, a limit or a model');
  ok(junk.limits.chatDaily === 400 && junk.limits.ttsDaily === 300, 'and an out-of-range or wrong-typed value is ignored');
  ok(effective({ limits: { proDailyUsd: 3 } }, {}).limits.proDailyUsd === 3 && effective({ limits: { proDailyUsd: null } }, {}).limits.proDailyUsd === null,
     'a nullable limit takes a number or null');
}

// MARK: the kill switches win over everything

{
  const cfg = effective({ flags: { 'cloud.tts': { on: true } } }, { STETHOSCORE_OFF: 'tts,write', FLAG_CLOUD_JOBS: 'on' });
  ok(!flag(cfg, 'cloud.tts') && !flag(cfg, 'cloud.chat'), 'a switched-off feature reads as off, over a stored body');
  ok(flag(cfg, 'cloud.jobs') && flag(cfg, 'cloud.transcribe'), 'the rest stay on');
  ok(!flag(effective(null, { STETHOSCORE_OFF: 'all' }), 'cloud.transcribe'), '"all" switches every cloud flag off');
  const refusal = killed(cfg, 'tts');
  ok(refusal && refusal.status === 503, 'killed() refuses a switched-off feature with 503');
  ok(refusal && (await refusal.json()).code === 'feature_off', 'with the code feature_off');
  ok(killed(cfg, 'jobs') === null, 'and lets the rest through');
  const banner = killed(effective({ flags: { 'cloud.chat': { on: false } }, messages: [{ id: 'm', level: 'warn', en: 'Back at six.' }] }, {}), 'chat');
  ok((await banner.json()).message === 'Back at six.', 'a warn message is the refusal\'s text');
}

// MARK: loading from D1, memoised

{
  const missing = await loadConfig({ DB: d1(new DatabaseSync(':memory:')) }, () => 0);
  ok(same(missing.limits, DEFAULTS.limits) && missing.version === 0, 'no remote_config table: defaults, no error');

  const { db, env } = withTable({ AI_DAILY_LIMIT: '250' });
  let now = 1_000_000;
  const clock = () => now;
  ok((await loadConfig(env, clock)).limits.chatDaily === 250, 'no row: the env var');
  store(db, 3, { limits: { chatDaily: 120 } });
  ok((await loadConfig(env, clock)).limits.chatDaily === 250, 'a new row is not read again within the minute');
  now += MEMO_MS;
  const fresh = await loadConfig(env, clock);
  ok(fresh.limits.chatDaily === 120 && fresh.version === 3, 'after a minute the row wins, with its version');
  store(db, 4, '{not json');
  forgetConfig(env);
  const broken = await loadConfig(env, clock);
  ok(broken.limits.chatDaily === 250 && broken.version === 4, 'an unreadable body counts as nothing stored');
}

// MARK: validation

{
  ok(validate({ limits: { chatDaily: 10 }, flags: { 'cloud.tts': { on: false, rollout: 0.5 } } }).ok, 'a good patch passes');
  const bad = validate({ limits: { chatDaily: -1, nope: 1 }, flags: { 'cloud.tts': { on: 'yes' } }, extra: 1,
                         messages: [{ id: 'x', level: 'loud', en: '' }], app: { minBuild: -1 }, cache: { salt: 'has space' } });
  ok(!bad.ok && bad.errors.length >= 7, `a bad body lists each problem (${bad.errors.length})`);
  ok(!validate([]).ok && !validate(null).ok, 'a body must be an object');
  ok(!validate({ messages: 'x'.repeat(70 * 1024) }).ok, 'a body over 64 KB is refused');
  ok(same(merge(DEFAULTS, { messages: Array(9).fill({ id: 'a', en: 'b' }) }).messages.length, 5), 'at most five messages are kept');
}

// MARK: one account's own caps

{
  const cfg = effective(null, {});
  ok(accountLimits(cfg, { caps: '{"chatDaily": 900}' }).chatDaily === 900, 'an account\'s caps lie over the config');
  ok(accountLimits(cfg, { caps: '{"chatDaily": -1}' }).chatDaily === 400, 'caps that fail validation are ignored whole');
  ok(accountLimits(cfg, { caps: 'nope' }).chatDaily === 400 && accountLimits(cfg, null).chatDaily === 400, 'unreadable or no caps: the config');
  ok(limit(null, { TTS_DAILY_LIMIT: '7' }, 'ttsDaily') === 7 && limit(null, {}, 'ttsDaily') === 300 && limit(null, {}, 'nope') === null,
     'limit() with no config at hand: the env, then DEFAULTS');
}

// MARK: what an app sees: GET /config

{
  const cfg = effective({ messages: [
    { id: 'old', en: 'gone', until: 10 },
    { id: 'new', en: 'for new builds', minBuild: 50 },
    { id: 'all', en: 'everyone' },
  ] }, {}, 2);
  const view = publicView(cfg, { build: 40, at: 100 });
  ok(same(Object.keys(view.limits).sort(), [...PUBLIC_LIMITS].sort()), 'only the public limits');
  const text = JSON.stringify(view);
  ok(!/freeShare|Usd|salt|gemini/.test(text), 'never prices, dollar caps, model shares or the cache salt');
  ok(same(view.messages.map(m => m.id), ['all']), 'messages past their time or for other builds are left out');
  ok(view.version === 2 && view.ttl === DEFAULTS.app.configTtlSeconds, 'version and ttl');

  const env = { DB: d1(new DatabaseSync(':memory:')), AI_DAILY_LIMIT: '400' };
  const first = await configRoute(new Request('https://w.example/config'), env);
  const etag = first.headers.get('etag');
  const body = await first.json();
  ok(first.status === 200 && /^"0-[0-9a-f]{8}"$/.test(etag || ''), 'GET /config answers 200 with an ETag');
  ok(first.headers.get('cache-control') === 'public, max-age=60', 'cached for a minute');
  ok(body.limits.chatDaily === 400 && typeof body.serverTime === 'number' && body.flags['cloud.chat'].on === true, 'with the limits, flags and server time');
  const again = await configRoute(new Request('https://w.example/config', { headers: { 'if-none-match': etag } }), env);
  ok(again.status === 304 && (await again.text()) === '', 'the same ETag: 304, no body');

  const viaWorker = await worker.fetch(new Request('https://w.example/config'), { ...env, SESSION_SECRET: 's' });
  ok(viaWorker.status === 200 && viaWorker.headers.get('etag'), 'the worker routes GET /config');
  const off = await (await worker.fetch(new Request('https://w.example/config'), { ...env, STETHOSCORE_OFF: 'tts' })).json();
  ok(off.flags['cloud.tts'].on === false, 'and a kill switch shows in it');
  const post = await worker.fetch(new Request('https://w.example/config', { method: 'POST', body: '{}' }), { ...env, SESSION_SECRET: 's' });
  ok(post.status === 404, 'POST /config is not a route');
}

console.log(failures ? `\n${failures} failed` : '\nall passed');
process.exit(failures ? 1 : 0);
