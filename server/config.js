// Remote config (design D §2.1): one set of flags and limits the owner can
// change without a release, read by the worker for every limit it enforces
// and by the app (GET /config) to adjust its interface.
//
// Precedence, per key: the stored body (the remote_config row 'live', written
// by /owner/config in P1.5), then the legacy env var (AI_DAILY_LIMIT and
// friends, so an existing deployment behaves exactly as before), then
// DEFAULTS. DEFAULTS is docs/launch/config-defaults.json; config.test.mjs
// fails when the two drift apart.
//
// The server enforces the limits. The app reads flags only to adjust what it
// shows. A config is read from D1 at most once a minute per isolate.

import { json, fail } from './lib/http.js';
import { switchedOff } from './switches.js';

export const DEFAULTS = {
  flags: {
    "share.links": { on: true },
    "share.classes": { on: true },
    "share.aiScreen": { on: false },
    "billing.referrals": { on: true },
    "billing.licences": { on: true },
    "billing.licenceOfferCodes": { on: false },
    "billing.examPass": { on: true },
    "cloud.chat": { on: true },
    "cloud.jobs": { on: true },
    "cloud.transcribe": { on: true },
    "cloud.tts": { on: true },
    "cache.account": { on: true },
    "cache.class": { on: false },
    "usage.showAllowance": { on: true },
    "trust.aiConsentEnforced": { on: false },
  },
  limits: {
    sharesPerAccount: 100,
    shareManifestBytes: 4000000,
    shareBlobBytes: 1800000,
    shareBytesD1: 8000000,
    shareBytesR2: 30000000,
    shareStoreSoftCap: 400000000,
    groupsPerAccount: 10,
    groupMembers: 600,
    groupSets: 300,
    publishesPerHour: 20,
    joinsPerHour: 20,
    inviteDevicesPerHour: 300,
    inviteDevicesPerCodeHour: 50,
    publicReadsPerMinute: 120,
    wrongShareCodesPerHour: 60,
    wrongGroupCodesPerHour: 30,
    autoSuspendReporters: 3,
    moderationReportsPerHour: 30,
    anonymousReportsPerHour: 10,
    referralRewardDays: 30,
    referralRefereeDays: 7,
    referralMaxPerMonth: 3,
    referralMaxPerYear: 12,
    referralHoldHours: 72,
    referralClaimWindowDays: 7,
    referralClaimsPerHour: 3,
    bankedCreditDays: 365,
    licenceMaxSeats: 5000,
    licenceMaxDays: 400,
    licencePaidModels: 0,
    licenceMonthlyBudgetUsd: 0,
    giftsPerMonth: 20,
    chatDaily: 400,
    transcribeDaily: 36,
    ttsDaily: 300,
    jobsActive: 3,
    jobsKept: 20,
    jobSteps: 200,
    jobCountMax: 1000,
    proDailyUsd: null,
    globalDailyUsd: 5,
    ownerMonthlyUsd: 20,
    cacheTtlDays: 180,
    cacheLookupsHourly: 60,
    cacheMaxSourceBytes: 2000000,
    cacheMaxBodyBytes: 1900000,
    cacheClaimNeedsPro: 1,
    spotlightMaxItems: 5000,
    siriQuizMax: 50,
    supportPerHour: 3,
    supportGlobalPerHour: 100,
    benchPublishPerHour: 30,
  },
  freeShare: {
    "gemini-3.5-flash": 4,
    "gemini-3.5-flash-lite": 60,
    "gemma-4-31b-it": 150,
    "workers-ai": 80,
  },
  messages: [],
  app: { configTtlSeconds: 21600, minBuild: 0, latestBuild: 0 },
  cache: { salt: "v1" },
};

/// [min, max] for every number an owner may set (limits, and each freeShare entry).
export const RANGES = {
  sharesPerAccount: [0, 1000],
  shareManifestBytes: [100000, 20000000],
  shareBlobBytes: [100000, 1800000],
  "shareBytesD1": [0, 50000000],
  "shareBytesR2": [0, 200000000],
  shareStoreSoftCap: [0, 480000000],
  groupsPerAccount: [0, 100],
  groupMembers: [2, 5000],
  groupSets: [1, 2000],
  publishesPerHour: [1, 500],
  joinsPerHour: [1, 500],
  inviteDevicesPerHour: [5, 2000],
  inviteDevicesPerCodeHour: [1, 1000],
  publicReadsPerMinute: [10, 10000],
  wrongShareCodesPerHour: [5, 1000],
  wrongGroupCodesPerHour: [5, 1000],
  autoSuspendReporters: [2, 50],
  moderationReportsPerHour: [1, 500],
  anonymousReportsPerHour: [1, 500],
  referralRewardDays: [0, 90],
  referralRefereeDays: [0, 30],
  referralMaxPerMonth: [0, 20],
  referralMaxPerYear: [0, 100],
  referralHoldHours: [0, 720],
  referralClaimWindowDays: [1, 30],
  referralClaimsPerHour: [1, 50],
  bankedCreditDays: [30, 730],
  licenceMaxSeats: [1, 20000],
  licenceMaxDays: [1, 730],
  licencePaidModels: [0, 0],
  licenceMonthlyBudgetUsd: [0, 0],
  giftsPerMonth: [0, 200],
  chatDaily: [0, 20000],
  transcribeDaily: [0, 500],
  ttsDaily: [0, 5000],
  jobsActive: [1, 10],
  jobsKept: [1, 100],
  jobSteps: [1, 500],
  jobCountMax: [1, 5000],
  proDailyUsd: [0, 50],
  globalDailyUsd: [0, 500],
  ownerMonthlyUsd: [0, 500],
  cacheTtlDays: [1, 730],
  cacheLookupsHourly: [1, 1000],
  cacheMaxSourceBytes: [10000, 10000000],
  cacheMaxBodyBytes: [10000, 1900000],
  cacheClaimNeedsPro: [0, 1],
  spotlightMaxItems: [0, 20000],
  siriQuizMax: [5, 100],
  supportPerHour: [1, 50],
  supportGlobalPerHour: [1, 5000],
  benchPublishPerHour: [1, 500],
  "freeShare.*": [0, 1000],
};

/// The limits an app may see (GET /config). Never prices, dollar caps, freeShare or the cache salt.
export const PUBLIC_LIMITS = ["chatDaily","transcribeDaily","ttsDaily","jobsActive","jobCountMax","spotlightMaxItems","siriQuizMax"];

/// The legacy env vars, by name, and what each one sets. Every other limit
/// also reads UPPER_SNAKE_CASE of its name (SHARES_PER_ACCOUNT), and every
/// flag FLAG_ plus its key in UPPER_SNAKE_CASE with dots as underscores
/// (FLAG_SHARE_LINKS), 'on' or 'off'.
export const ENV_MAP = {
  AI_DAILY_LIMIT: 'limits.chatDaily',
  TRANSCRIBE_DAILY: 'limits.transcribeDaily',
  TTS_DAILY_LIMIT: 'limits.ttsDaily',
  OWNER_MONTHLY_USD: 'limits.ownerMonthlyUsd',
  REFERRALS: 'flags.billing.referrals',
  GROUP_LICENCES: 'flags.billing.licences',
  AI_CONSENT_ENFORCED: 'flags.trust.aiConsentEnforced',
};
const ZERO_IS_DEFAULT = ['chatDaily', 'transcribeDaily', 'ttsDaily'];

const APP_RANGES = { configTtlSeconds: [60, 604800], minBuild: [0, 1000000000], latestBuild: [0, 1000000000] };
const TOP_KEYS = ['flags', 'limits', 'freeShare', 'messages', 'app', 'cache'];
const FLAG_KEYS = ['on', 'rollout', 'minBuild', 'maxBuild', 'locales'];
const MESSAGE_KEYS = ['id', 'level', 'en', 'ar', 'until', 'minBuild', 'maxBuild'];
export const MAX_BODY_BYTES = 64 * 1024;
export const MAX_MESSAGES = 5;
export const MESSAGE_CHARS = 300;
export const MEMO_MS = 60_000;

const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const isObject = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const clone = v => JSON.parse(JSON.stringify(v));
const snake = name => name.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toUpperCase();
export const envNameForLimit = name => snake(name);
export const envNameForFlag = key => 'FLAG_' + key.split('.').map(snake).join('_');

function inRange(name, value) {
  const range = name.startsWith('freeShare.') ? RANGES['freeShare.*'] : RANGES[name];
  if (typeof value !== 'number' || !Number.isFinite(value)) return false;
  return !range || (value >= range[0] && value <= range[1]);
}

function envFlag(raw) {
  const v = String(raw).trim().toLowerCase();
  if (v === 'on' || v === 'true' || v === '1') return true;
  if (v === 'off' || v === 'false' || v === '0') return false;
  return null;
}

function envNumber(raw) {
  if (raw === undefined || raw === null) return null;
  const s = String(raw).trim();
  if (!s) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

/// What the env vars set, as a partial body {flags, limits, freeShare}. An
/// empty or unparsable value is ignored, so a blank var in wrangler.toml
/// changes nothing. A legacy var (ENV_MAP, FREE_MODEL_SHARES) is taken as the
/// running worker reads it today - any number of 0 or more - so an existing
/// deployment keeps its numbers even outside the owner's ranges; a var named
/// after a limit (SHARES_PER_ACCOUNT) is new, and held to RANGES.
export function envOverrides(env = {}) {
  const out = { flags: {}, limits: {}, freeShare: {} };
  const legacy = {};
  for (const [name, target] of Object.entries(ENV_MAP)) if (env[name] !== undefined) legacy[target] = env[name];
  for (const name of Object.keys(DEFAULTS.limits)) {
    const isLegacy = own(legacy, `limits.${name}`);
    const n = envNumber(isLegacy ? legacy[`limits.${name}`] : env[envNameForLimit(name)]);
    // ai.js and tts.js read these as `Number(x) || default`: 0 is the default there
    if (isLegacy && n === 0 && ZERO_IS_DEFAULT.includes(name)) continue;
    if (n !== null && (isLegacy ? n >= 0 : inRange(name, n))) out.limits[name] = n;
  }
  for (const key of Object.keys(DEFAULTS.flags)) {
    const raw = own(legacy, `flags.${key}`) ? legacy[`flags.${key}`] : env[envNameForFlag(key)];
    if (raw === undefined) continue;
    const on = envFlag(raw);
    if (on !== null) out.flags[key] = { on };
  }
  // "model:requests a day,...", as ai.js freeShare() reads it
  for (const entry of String(env.FREE_MODEL_SHARES ?? '').split(',').map(e => e.trim()).filter(Boolean)) {
    const [model, raw] = entry.split(':');
    const n = envNumber(raw);
    if (model.trim() && n !== null && n >= 0) out.freeShare[model.trim()] = n;
  }
  return out;
}

/// The kill switches (switches.js STETHOSCORE_OFF), as the cloud.* flags they
/// stop. The worker refuses those requests whatever the config says, so a
/// switched-off feature always reads as off here too, over a stored body.
const SWITCH_FLAGS = { write: 'cloud.chat', jobs: 'cloud.jobs', transcribe: 'cloud.transcribe', tts: 'cloud.tts' };

function cleanFlag(v) {
  if (!isObject(v)) return null;
  const out = {};
  if (own(v, 'on')) out.on = v.on === true;
  if (typeof v.rollout === 'number' && v.rollout >= 0 && v.rollout <= 1) out.rollout = v.rollout;
  if (Number.isInteger(v.minBuild) && v.minBuild >= 0) out.minBuild = v.minBuild;
  if (Number.isInteger(v.maxBuild) && v.maxBuild >= 0) out.maxBuild = v.maxBuild;
  if (Array.isArray(v.locales)) out.locales = v.locales.filter(l => typeof l === 'string').slice(0, 20);
  return out;
}

/// `patch` laid over `base`, deeply, but only for keys already in DEFAULTS and
/// only with values of the right kind: an unknown key in a stored body or an
/// env var can never add a flag or a limit.
export function merge(base, patch) {
  const out = clone(base);
  if (!isObject(patch)) return out;
  if (isObject(patch.flags)) {
    for (const [k, v] of Object.entries(patch.flags)) {
      if (!own(DEFAULTS.flags, k)) continue;
      const f = cleanFlag(v);
      if (f) out.flags[k] = { ...out.flags[k], ...f };
    }
  }
  if (isObject(patch.limits)) {
    for (const [k, v] of Object.entries(patch.limits)) {
      if (!own(DEFAULTS.limits, k)) continue;
      if (v === null && DEFAULTS.limits[k] === null) out.limits[k] = null;
      else if (inRange(k, v)) out.limits[k] = v;
    }
  }
  if (isObject(patch.freeShare)) {
    for (const [k, v] of Object.entries(patch.freeShare)) {
      if (own(DEFAULTS.freeShare, k) && inRange(`freeShare.${k}`, v)) out.freeShare[k] = v;
    }
  }
  if (Array.isArray(patch.messages)) out.messages = patch.messages.filter(isObject).slice(0, MAX_MESSAGES).map(m => ({ ...m }));
  if (isObject(patch.app)) {
    for (const [k, v] of Object.entries(patch.app)) {
      const r = APP_RANGES[k];
      if (r && Number.isInteger(v) && v >= r[0] && v <= r[1]) out.app[k] = v;
    }
  }
  if (isObject(patch.cache) && typeof patch.cache.salt === 'string' && /^[A-Za-z0-9._-]{1,32}$/.test(patch.cache.salt)) {
    out.cache.salt = patch.cache.salt;
  }
  return out;
}

/// Checks a body an owner wants to store (the whole stored body, or a patch).
/// Returns {ok: true, body} or {ok: false, errors: [...]}.
export function validate(body) {
  const errors = [];
  if (!isObject(body)) return { ok: false, errors: ['The config must be an object.'] };
  let size = 0;
  try { size = new TextEncoder().encode(JSON.stringify(body)).length; } catch { errors.push('The config must be JSON.'); }
  if (size > MAX_BODY_BYTES) errors.push(`The config is ${size} bytes; at most ${MAX_BODY_BYTES}.`);
  for (const k of Object.keys(body)) if (!TOP_KEYS.includes(k)) errors.push(`Unknown key ${k}.`);
  if (own(body, 'flags')) {
    if (!isObject(body.flags)) errors.push('flags must be an object.');
    else for (const [k, v] of Object.entries(body.flags)) {
      if (!own(DEFAULTS.flags, k)) { errors.push(`Unknown flag ${k}.`); continue; }
      if (!isObject(v)) { errors.push(`Flag ${k} must be an object.`); continue; }
      for (const f of Object.keys(v)) if (!FLAG_KEYS.includes(f)) errors.push(`Flag ${k} has an unknown field ${f}.`);
      if (own(v, 'on') && typeof v.on !== 'boolean') errors.push(`Flag ${k}.on must be true or false.`);
      if (own(v, 'rollout') && !(typeof v.rollout === 'number' && v.rollout >= 0 && v.rollout <= 1)) errors.push(`Flag ${k}.rollout must be 0 to 1.`);
      for (const b of ['minBuild', 'maxBuild']) if (own(v, b) && !(Number.isInteger(v[b]) && v[b] >= 0)) errors.push(`Flag ${k}.${b} must be a whole number.`);
      if (own(v, 'locales') && !(Array.isArray(v.locales) && v.locales.every(l => typeof l === 'string' && l.length <= 16))) errors.push(`Flag ${k}.locales must be language codes.`);
    }
  }
  if (own(body, 'limits')) {
    if (!isObject(body.limits)) errors.push('limits must be an object.');
    else for (const [k, v] of Object.entries(body.limits)) {
      if (!own(DEFAULTS.limits, k)) { errors.push(`Unknown limit ${k}.`); continue; }
      if (v === null && DEFAULTS.limits[k] === null) continue;
      if (typeof v !== 'number' || !Number.isFinite(v)) { errors.push(`Limit ${k} must be a number.`); continue; }
      if (!inRange(k, v)) errors.push(`Limit ${k} must be between ${RANGES[k][0]} and ${RANGES[k][1]}.`);
    }
  }
  if (own(body, 'freeShare')) {
    if (!isObject(body.freeShare)) errors.push('freeShare must be an object.');
    else for (const [k, v] of Object.entries(body.freeShare)) {
      if (!own(DEFAULTS.freeShare, k)) errors.push(`Unknown freeShare model ${k}.`);
      else if (!inRange(`freeShare.${k}`, v)) errors.push(`freeShare ${k} must be between ${RANGES['freeShare.*'][0]} and ${RANGES['freeShare.*'][1]}.`);
    }
  }
  if (own(body, 'messages')) {
    if (!Array.isArray(body.messages)) errors.push('messages must be a list.');
    else {
      if (body.messages.length > MAX_MESSAGES) errors.push(`At most ${MAX_MESSAGES} messages.`);
      body.messages.forEach((m, i) => {
        if (!isObject(m)) { errors.push(`Message ${i + 1} must be an object.`); return; }
        for (const f of Object.keys(m)) if (!MESSAGE_KEYS.includes(f)) errors.push(`Message ${i + 1} has an unknown field ${f}.`);
        if (typeof m.id !== 'string' || !/^[A-Za-z0-9._-]{1,40}$/.test(m.id)) errors.push(`Message ${i + 1} needs an id.`);
        if (own(m, 'level') && m.level !== 'info' && m.level !== 'warn') errors.push(`Message ${i + 1} level must be info or warn.`);
        for (const lang of ['en', 'ar']) {
          if (own(m, lang) && (typeof m[lang] !== 'string' || m[lang].length > MESSAGE_CHARS)) errors.push(`Message ${i + 1} ${lang} must be text of at most ${MESSAGE_CHARS} characters.`);
        }
        if (typeof m.en !== 'string' || !m.en.trim()) errors.push(`Message ${i + 1} needs English text.`);
        for (const n of ['until', 'minBuild', 'maxBuild']) if (own(m, n) && !(Number.isInteger(m[n]) && m[n] >= 0)) errors.push(`Message ${i + 1} ${n} must be a whole number.`);
      });
    }
  }
  if (own(body, 'app')) {
    if (!isObject(body.app)) errors.push('app must be an object.');
    else for (const [k, v] of Object.entries(body.app)) {
      const r = APP_RANGES[k];
      if (!r) errors.push(`Unknown app setting ${k}.`);
      else if (!(Number.isInteger(v) && v >= r[0] && v <= r[1])) errors.push(`app.${k} must be between ${r[0]} and ${r[1]}.`);
    }
  }
  if (own(body, 'cache')) {
    if (!isObject(body.cache)) errors.push('cache must be an object.');
    else for (const [k, v] of Object.entries(body.cache)) {
      if (k !== 'salt') errors.push(`Unknown cache setting ${k}.`);
      else if (typeof v !== 'string' || !/^[A-Za-z0-9._-]{1,32}$/.test(v)) errors.push('cache.salt must be 1 to 32 letters, digits, dots, dashes or underscores.');
    }
  }
  return errors.length ? { ok: false, errors } : { ok: true, body };
}

/// The config in force, from a stored body (already parsed) and the env.
/// Precedence, per key: the stored body, then the env, then DEFAULTS; a kill
/// switch over all three.
export function effective(stored, env = {}, version = 0) {
  const fromEnv = envOverrides(env);
  const base = merge(DEFAULTS, { flags: fromEnv.flags });
  // already checked by envOverrides, which lets a legacy var past RANGES
  Object.assign(base.limits, fromEnv.limits);
  Object.assign(base.freeShare, fromEnv.freeShare);
  const cfg = merge(base, stored);
  const { off } = switchedOff(env);
  for (const [feature, key] of Object.entries(SWITCH_FLAGS)) {
    if (off.has(feature)) cfg.flags[key] = { ...cfg.flags[key], on: false };
  }
  cfg.version = Number.isInteger(version) ? version : 0;
  return cfg;
}

// MARK: loading, memoised

const memo = new WeakMap();
const memoKey = env => (env && env.DB) || env;

/// The config in force for this env. The stored row is read from D1 at most
/// once per MEMO_MS per isolate; the env and the kill switches are applied on
/// every call, so a switch thrown takes effect at once, as in switches.js. A
/// missing table, a missing row or an unreadable body all mean "nothing
/// stored": defaults and env, never an error.
export async function loadConfig(env, clock = Date.now) {
  const key = memoKey(env);
  const at = clock();
  const cached = key && typeof key === 'object' ? memo.get(key) : null;
  if (cached && at - cached.at < MEMO_MS && at >= cached.at) return effective(cached.stored, env, cached.version);
  let stored = null;
  let version = 0;
  if (env && env.DB) {
    try {
      const row = await env.DB.prepare("SELECT version, body FROM remote_config WHERE id = 'live'").first();
      if (row) {
        version = Number(row.version) || 0;
        try { stored = JSON.parse(row.body); } catch { stored = null; }
      }
    } catch { /* no table yet: defaults */ }
  }
  if (key && typeof key === 'object') memo.set(key, { at, stored, version });
  return effective(stored, env, version);
}

/// Drops the memo (after an owner write, and in tests).
export function forgetConfig(env) {
  const key = memoKey(env);
  if (key && typeof key === 'object') memo.delete(key);
}

// MARK: reading

export function flag(cfg, name) {
  const f = cfg && cfg.flags ? cfg.flags[name] : undefined;
  if (f) return f.on === true;
  const d = DEFAULTS.flags[name];
  return !!(d && d.on === true);
}

/// A limit by name ('chatDaily', or 'freeShare.<model>'). With no cfg at hand
/// the env and DEFAULTS still answer.
export function limit(cfg, env, name) {
  if (name.startsWith('freeShare.')) {
    const model = name.slice('freeShare.'.length);
    const v = cfg && cfg.freeShare ? cfg.freeShare[model] : envOverrides(env || {}).freeShare[model];
    return v !== undefined ? v : (DEFAULTS.freeShare[model] ?? null);
  }
  if (cfg && cfg.limits && own(cfg.limits, name)) return cfg.limits[name];
  const fromEnv = envOverrides(env || {}).limits[name];
  if (fromEnv !== undefined) return fromEnv;
  return own(DEFAULTS.limits, name) ? DEFAULTS.limits[name] : null;
}

/// cfg.limits with this account's own caps (accounts.caps, JSON, set by the
/// owner for a lecturer or an ambassador) laid over them. Caps that fail the
/// same checks as the config are ignored whole.
export function accountLimits(cfg, account) {
  const base = { ...((cfg && cfg.limits) || DEFAULTS.limits) };
  const raw = account && account.caps;
  if (!raw) return base;
  let caps = null;
  try { caps = typeof raw === 'string' ? JSON.parse(raw) : raw; } catch { return base; }
  if (!isObject(caps) || !validate({ limits: caps }).ok) return base;
  return { ...base, ...caps };
}

const PAUSED = 'This is paused for a little while. Please try again later.';

/// The refusal (503 feature_off) when cloud.<feature> is switched off, or null.
/// Enforced here, so old app builds obey it too.
export function killed(cfg, feature, at = Math.floor(Date.now() / 1000)) {
  if (flag(cfg, `cloud.${feature}`)) return null;
  const banner = ((cfg && cfg.messages) || []).find(m => m && m.level === 'warn' && typeof m.en === 'string'
    && (!m.until || m.until > at));
  return fail(503, banner ? banner.en : PAUSED, 'feature_off');
}

/// What an app may see: every flag, the public limits, the messages meant for
/// its build, and the build numbers. Never prices, dollar caps, freeShare or
/// the cache salt.
export function publicView(cfg, { build = 0, at = Math.floor(Date.now() / 1000) } = {}) {
  const limits = {};
  for (const k of PUBLIC_LIMITS) if (cfg.limits && own(cfg.limits, k)) limits[k] = cfg.limits[k];
  const messages = (cfg.messages || []).filter(m => (!m.until || m.until > at)
    && (!Number.isInteger(m.minBuild) || !build || build >= m.minBuild)
    && (!Number.isInteger(m.maxBuild) || !build || build <= m.maxBuild));
  return {
    version: cfg.version || 0,
    ttl: cfg.app.configTtlSeconds,
    flags: clone(cfg.flags),
    limits,
    messages: clone(messages),
    app: { minBuild: cfg.app.minBuild, latestBuild: cfg.app.latestBuild },
  };
}

/// FNV-1a 32-bit of a string, as 8 hex: the ETag's content part.
function fnv(text) {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) { h ^= text.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, '0');
}

export function etagFor(view) {
  return `"${view.version}-${fnv(JSON.stringify(view))}"`;
}

function matches(header, etag) {
  if (!header) return false;
  return header.split(',').map(s => s.trim().replace(/^W\//, '')).some(t => t === etag || t === '*');
}

/// GET /config
async function getConfig(ctx) {
  const build = parseInt(ctx.request.headers.get('x-vignette-build') || '0', 10) || 0;
  const view = publicView(ctx.cfg, { build });
  const etag = etagFor(view);
  const headers = { etag, 'cache-control': 'public, max-age=60', vary: 'x-vignette-build' };
  if (matches(ctx.request.headers.get('if-none-match'), etag)) return new Response(null, { status: 304, headers });
  return json({ ...view, serverTime: Math.floor(Date.now() / 1000) }, 200, headers);
}

/// GET /config as worker.js routes it until the router (P0.1) exists.
export async function configRoute(request, env, clock = Date.now) {
  return getConfig({ request, env, cfg: await loadConfig(env, clock) });
}

export const routes = [
  { method: 'GET', path: '/config', auth: 'public', handler: getConfig },
];
export const cron = [];
export async function onAccountDelete() {}
