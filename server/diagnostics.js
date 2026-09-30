// Crash and failure reports: what went wrong in the app, grouped so each
// problem is one row however many times it happened, for the owner to fix.
//
// The app (Shared/Diagnostics) sends, signed in and at most a few times a day:
//   - crashes, hangs, CPU and disk-write exceptions from MetricKit (a report
//     arrives on the launch after it happened),
//   - an "unclean exit": the app was in use and then simply was not, with no
//     crash report (memory, the watchdog, or a crash MetricKit has not
//     delivered yet),
//   - failures the app caught itself (a cloud model's error, a sync that
//     stopped, a file that would not import), as an area and a fixed message.
//
// What never arrives, and is refused again here if it somehow does: note or
// question text, names, emails, tokens, file paths, audio. The app only ever
// sends message keys written in its own source (StaticString, "sync.failed"),
// an error's type, domain and number, and call-stack addresses. This side
// re-checks every field against a pattern - a message must be a key, a name
// must be an identifier, a breadcrumb must be a name - so a mistake in one app
// version cannot put someone's notes in the database. There is no free-text
// field left to scrub; scrub() is kept for the owner's own tools.
//
// Each report is stored with the account that sent it (so the per-account
// daily cap works and deleting the account deletes them), grouped by a
// fingerprint: the kind of problem plus the top frames in the app's own code,
// or the area plus the message. The owner reads the groups through
// GET /diagnostics/summary, and a GitHub workflow turns each group into an
// issue (server/triage/diagnostics-triage.mjs).

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json' },
});
const fail = (status, message) => json({ error: message, message }, status);
const now = () => Math.floor(Date.now() / 1000);
const today = () => new Date().toISOString().slice(0, 10);

/// Reports one account may send in a day, and in one request. D1 allows 50
/// queries a request on the free plan and each report costs three, so one
/// request carries at most 12.
export const EVENTS_PER_DAY = 60;
export const EVENTS_PER_REQUEST = 12;
/// Requests one account may make in a day (the app sends a few).
export const REQUESTS_PER_DAY = 50;
export const MAX_BODY = 64 * 1024;
/// Newest reports kept per group; the counts are kept regardless.
export const SAMPLES_PER_GROUP = 20;
export const KEEP_DAYS = 90;

export const KINDS = ['crash', 'hang', 'cpu', 'disk', 'unclean', 'error', 'warning'];
export const FATAL = new Set(['crash', 'hang', 'cpu', 'disk', 'unclean']);
export const AREAS = ['app', 'ai', 'cloud_jobs', 'transcribe', 'voice', 'audio', 'sync', 'import',
  'export', 'graph3d', 'metal', 'download', 'account', 'metrickit'];
const FLAVOURS = ['store', 'testflight', 'playgrounds', 'personal', 'dev'];
const THERMAL = ['nominal', 'fair', 'serious', 'critical'];
const GRAPHICS = ['automatic', 'high', 'smooth'];
const IDIOMS = ['phone', 'pad', 'other'];

// MARK: scrubbing

/// A name out of code (an exception, a class, an error domain): letters,
/// digits, dots and underscores, nothing that could be a sentence.
export function identifier(value, max = 80) {
  if (typeof value !== 'string') return null;
  const s = value.trim();
  return new RegExp(`^[A-Za-z_][A-Za-z0-9_.]{0,${max - 1}}$`).test(s) ? s : null;
}

/// Free text from a report, with anything that could identify somebody taken
/// out: emails, links, file paths, ids and tokens, and runs of digits.
/// The app does the same before sending; this is the second pass.
export function scrub(value, max = 160) {
  if (typeof value !== 'string') return null;
  let s = value
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '<email>')
    .replace(/[A-Za-z][A-Za-z0-9+.-]*:\/\/\S+/g, '<url>')
    .replace(/~?(?:\/[^\s/]+){2,}\/?/g, '<path>')
    .replace(/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/g, '<id>')
    .replace(/\b(?:0x)?[0-9A-Fa-f]{12,}\b/g, '<id>')
    .replace(/[A-Za-z0-9_\-]{24,}/g, '<id>')
    .replace(/\d{4,}/g, '#')
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (s.length > max) s = s.slice(0, max);
  return s || null;
}

/// A failure's message is a key written in the app's source
/// ("sync.failed", "hosted.http_status"), never a sentence: anything else is
/// refused, so no text anybody typed can arrive as a message.
export function messageKey(value) {
  return typeof value === 'string' && /^[a-z][a-z0-9_.]{0,63}$/.test(value) ? value : null;
}

/// Only the namespace and code of a termination reason ("Namespace SIGNAL,
/// Code 0xb", "Namespace RUNNINGBOARD, Code 0xdead10cc"): the rest is dropped.
export function termination(value) {
  if (typeof value !== 'string') return null;
  const m = value.match(/Namespace ([A-Z_]{1,32}),\s*Code (0x[0-9A-Fa-f]{1,16}|\d{1,12})/);
  return m ? `Namespace ${m[1]}, Code ${m[2]}` : null;
}

/// A message with its numbers taken out, so "status 502" and "status 503"
/// are one problem.
export function template(value) {
  return (scrub(value) || '').replace(/\d+/g, '#');
}

const crumbName = s => typeof s === 'string' && /^[A-Za-z0-9_.:\/-]{1,48}$/.test(s) ? s : null;
const int = (v, lo, hi) => Number.isInteger(v) && v >= lo && v <= hi ? v : null;
const oneOf = (v, list) => list.includes(v) ? v : null;
const pattern = (v, re) => typeof v === 'string' && re.test(v) ? v : null;

// MARK: fingerprint (the same function as DiagnosticsModel.swift)

/// FNV-1a, 64 bits, over UTF-8, as 16 hex characters. Not for security: only
/// so the app and the server name the same problem the same way.
export function fnv1a64(text) {
  let h = 0xcbf29ce484222325n;
  for (const byte of new TextEncoder().encode(text)) {
    h ^= BigInt(byte);
    h = (h * 0x100000001b3n) & 0xffffffffffffffffn;
  }
  return h.toString(16).padStart(16, '0');
}

/// The frames a crash is known by: the top five in the app's own binary, or
/// the top five of any binary when none of the app's is on the stack.
export function keyFrames(frames, binary) {
  const list = Array.isArray(frames) ? frames : [];
  const own = list.filter(f => f.b === binary);
  return (own.length ? own : list).slice(0, 5);
}

/// What makes two reports the same problem.
export function canonical(event, binary) {
  if (FATAL.has(event.kind) && event.kind !== 'unclean') {
    const x = event.exception || {};
    const what = x.name || x.className || `t${x.type ?? -1}:s${x.signal ?? -1}`;
    const frames = keyFrames(event.frames, binary).map(f => `${f.b}+${f.o.toString(16)}`).join(',');
    return `${event.kind}|${event.kind === 'hang' ? '' : what}|${frames}`;
  }
  if (event.kind === 'unclean') {
    const last = (event.breadcrumbs || []).at(-1);
    return `unclean|${event.area}|${last ? last.s : ''}`;
  }
  const e = event.error || {};
  return [event.kind, event.area, event.message || '', e.domain || '', e.code ?? '', e.name || '', event.code ?? ''].join('|');
}

export const fingerprint = (event, binary) => fnv1a64(canonical(event, binary));

const SIGNALS = { 4: 'SIGILL', 5: 'SIGTRAP', 6: 'SIGABRT', 8: 'SIGFPE', 9: 'SIGKILL', 10: 'SIGBUS', 11: 'SIGSEGV' };

/// A one-line name for a group, until somebody symbolicates it.
export function title(event, binary) {
  const top = keyFrames(event.frames, binary)[0];
  const at = top ? ` at ${top.b}+0x${top.o.toString(16)}` : '';
  const x = event.exception || {};
  switch (event.kind) {
    case 'crash': return `Crash: ${x.name || x.className || SIGNALS[x.signal] || `exception ${x.type ?? '?'}`}${at}`;
    case 'hang': return `Hang${event.durationMs ? ` of ${(event.durationMs / 1000).toFixed(1)}s` : ''}${at}`;
    case 'cpu': return `CPU exception${at}`;
    case 'disk': return `Disk-write exception${at}`;
    case 'unclean': {
      const last = (event.breadcrumbs || []).at(-1);
      return `Unclean exit (killed or crashed)${last ? ` after ${last.s}` : ''}`;
    }
    default: {
      const e = event.error;
      const why = e ? ` (${[e.domain, e.code, e.name].filter(v => v !== null && v !== undefined && v !== '').join(' ')})` : '';
      const code = event.code !== null && event.code !== undefined ? ` [${event.code}]` : '';
      return `${event.kind === 'warning' ? 'Warning' : 'Failure'} in ${event.area}: ${event.message}${code}${why}`.slice(0, 200);
    }
  }
}

// MARK: validation

export function cleanDevice(d) {
  if (!d || typeof d !== 'object') return null;
  return {
    model: pattern(d.model, /^[A-Za-z0-9,._ -]{1,32}$/),
    os: pattern(d.os, /^[0-9.]{1,16}$/),
    idiom: oneOf(d.idiom, IDIOMS),
    app: pattern(d.app, /^[0-9A-Za-z._-]{1,16}$/),
    build: pattern(d.build, /^[0-9A-Za-z._-]{1,16}$/),
    flavour: oneOf(d.flavour, FLAVOURS),
    binary: pattern(d.binary, /^[A-Za-z0-9_.+ -]{1,64}$/),
    memoryGB: int(d.memoryGB, 0, 64),
    freeDiskGB: int(d.freeDiskGB, 0, 8192),
    thermal: oneOf(d.thermal, THERMAL),
    lowPower: typeof d.lowPower === 'boolean' ? d.lowPower : null,
    graphics: oneOf(d.graphics, GRAPHICS),
  };
}

/// One report, reduced to the fields the schema allows and re-scrubbed - or
/// null when it is not a report at all.
export function cleanEvent(e, at = now()) {
  if (!e || typeof e !== 'object') return null;
  const kind = oneOf(e.kind, KINDS);
  const area = oneOf(e.area, AREAS);
  if (!kind || !area) return null;
  const when = int(e.at, at - 30 * 86400, at + 86400);
  if (when === null) return null;
  const frames = (Array.isArray(e.frames) ? e.frames : []).slice(0, 32).map(f => {
    if (!f || typeof f !== 'object') return null;
    const b = pattern(f.b, /^[A-Za-z0-9_.+ -]{1,64}$/);
    const o = int(f.o, 0, 2 ** 48);
    if (!b || o === null) return null;
    return { b, u: pattern(f.u, /^[0-9A-Fa-f-]{32,36}$/), o };
  }).filter(Boolean);
  const crumbs = (Array.isArray(e.breadcrumbs) ? e.breadcrumbs : []).slice(-50).map(c => {
    if (!c || typeof c !== 'object') return null;
    const s = crumbName(c.s);
    const t = int(c.t, 0, 30 * 86400);
    return s && t !== null ? { t, s } : null;
  }).filter(Boolean);
  const x = e.exception && typeof e.exception === 'object' ? {
    type: int(e.exception.type, -1, 1 << 20),
    code: int(e.exception.code, -(2 ** 31), 2 ** 32),
    signal: int(e.exception.signal, 0, 64),
    name: identifier(e.exception.name),
    className: identifier(e.exception.className),
    termination: termination(e.exception.termination),
  } : null;
  const err = e.error && typeof e.error === 'object' ? {
    domain: identifier(e.error.domain) || 'unknown',
    code: int(e.error.code, -(2 ** 31), 2 ** 32) ?? 0,
    name: identifier(e.error.name, 60),
  } : null;
  return {
    kind, area, at: when,
    message: messageKey(e.message) || 'unknown',
    code: int(e.code, -99999, 99999),
    error: err,
    exception: x,
    frames,
    durationMs: int(e.durationMs, 0, 3600 * 1000),
    count: int(e.count, 1, 1000) ?? 1,
    breadcrumbs: crumbs,
  };
}

// MARK: POST /diagnostics

/// Reports from a signed-in account: counted against its day, grouped, kept.
/// An empty `events` is the app saying "this build is running" once a day,
/// which is what lets the triage tell a fixed problem from a quiet week.
export async function diagnosticsRoute(env, accountId, body, clock = now) {
  const at = clock();
  const device = cleanDevice(body && body.device);
  if (!device || !device.build) return fail(400, 'Missing the build.');
  const build = device.app ? `${device.app} (${device.build})` : device.build;
  const binary = device.binary || 'RedPen';
  // the account's day: requests first (each one writes), then reports
  const day = today();
  await env.DB.prepare(
    `INSERT INTO diagnostic_quota (account_id, day, n, requests) VALUES (?, ?, 0, 0)
     ON CONFLICT (account_id, day) DO NOTHING`).bind(accountId, day).run();
  const asked = await env.DB.prepare(
    'UPDATE diagnostic_quota SET requests = requests + 1 WHERE account_id = ? AND day = ? AND requests < ?')
    .bind(accountId, day, REQUESTS_PER_DAY).run();
  if (!asked.meta.changes) return json({ error: 'Too many reports today.', message: 'Too many reports today.', retryAfter: 86400 }, 429);
  // the build was running today (once per request, never more than one write)
  await env.DB.prepare(
    `INSERT INTO diagnostic_builds (build, flavour, first_seen, last_seen, pings) VALUES (?, ?, ?, ?, 1)
     ON CONFLICT (build) DO UPDATE SET last_seen = excluded.last_seen, pings = pings + 1`)
    .bind(build, device.flavour || 'store', at, at).run();

  const raw = Array.isArray(body.events) ? body.events : [];
  if (!raw.length) return json({ accepted: 0, dropped: 0 });
  const offered = raw.slice(0, EVENTS_PER_REQUEST);
  let dropped = raw.length - offered.length;

  // as many reports as are left of the day, the rest refused
  const row = await env.DB.prepare('SELECT n FROM diagnostic_quota WHERE account_id = ? AND day = ?')
    .bind(accountId, day).first();
  const left = Math.max(0, EVENTS_PER_DAY - (row ? row.n : 0));
  if (!left) return json({ accepted: 0, dropped: raw.length, retryAfter: 86400 }, 429);
  const taking = offered.slice(0, left);
  dropped += offered.length - taking.length;

  let accepted = 0;
  for (const rawEvent of taking) {
    const event = cleanEvent(rawEvent, at);
    if (!event) { dropped++; continue; }
    const fp = fingerprint(event, binary);
    const name = title(event, binary);
    await env.DB.prepare(
      `INSERT INTO diagnostic_groups (fingerprint, kind, area, title, first_seen, last_seen, first_build, last_build, n)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (fingerprint) DO UPDATE SET last_seen = MAX(last_seen, excluded.last_seen),
         last_build = excluded.last_build, n = n + excluded.n`)
      .bind(fp, event.kind, event.area, name, event.at, event.at, build, build, event.count).run();
    await env.DB.prepare(
      `INSERT INTO diagnostic_counts (fingerprint, build, n, last_seen) VALUES (?, ?, ?, ?)
       ON CONFLICT (fingerprint, build) DO UPDATE SET n = n + excluded.n, last_seen = MAX(last_seen, excluded.last_seen)`)
      .bind(fp, build, event.count, event.at).run();
    await env.DB.prepare(
      `INSERT INTO diagnostic_events (fingerprint, account_id, build, received_at, body) VALUES (?, ?, ?, ?, ?)`)
      // the device as it was when it happened (thermal state, free space),
      // or as it is now
      .bind(fp, accountId, build, at, JSON.stringify({ ...event, device: cleanDevice(rawEvent.device) || device })).run();
    accepted++;
  }
  if (accepted) {
    await env.DB.prepare('UPDATE diagnostic_quota SET n = n + ? WHERE account_id = ? AND day = ?')
      .bind(accepted, accountId, day).run();
  }
  return json({ accepted, dropped });
}

// MARK: GET /diagnostics/summary (owner only)

/// Every group seen since `since` (default 60 days), with its counts per
/// build, the devices and systems it happened on, and its newest samples;
/// plus every build seen, so the triage knows which builds are newer.
export async function diagnosticsSummary(env, url, clock = now) {
  const at = clock();
  const since = Number(url.searchParams.get('since')) || at - 60 * 86400;
  const limit = Math.min(200, Math.max(1, Number(url.searchParams.get('limit')) || 100));
  const groups = (await env.DB.prepare(
    'SELECT * FROM diagnostic_groups WHERE last_seen >= ? ORDER BY last_seen DESC LIMIT ?')
    .bind(since, limit).all()).results || [];
  const builds = (await env.DB.prepare(
    'SELECT build, flavour, first_seen, last_seen, pings FROM diagnostic_builds WHERE last_seen >= ? ORDER BY first_seen')
    .bind(since - 120 * 86400).all()).results || [];
  const counts = (await env.DB.prepare(
    `SELECT c.fingerprint, c.build, c.n, c.last_seen FROM diagnostic_counts c
     JOIN diagnostic_groups g ON g.fingerprint = c.fingerprint WHERE g.last_seen >= ?`)
    .bind(since).all()).results || [];
  const samples = (await env.DB.prepare(
    `SELECT fingerprint, account_id, received_at, body FROM (
       SELECT e.*, ROW_NUMBER() OVER (PARTITION BY e.fingerprint ORDER BY e.id DESC) AS rn
       FROM diagnostic_events e JOIN diagnostic_groups g ON g.fingerprint = e.fingerprint
       WHERE g.last_seen >= ?) WHERE rn <= ?`)
    .bind(since, SAMPLES_PER_GROUP).all()).results || [];

  const byGroup = new Map(groups.map(g => [g.fingerprint, {
    fingerprint: g.fingerprint, kind: g.kind, area: g.area, title: g.title,
    firstSeen: g.first_seen, lastSeen: g.last_seen, firstBuild: g.first_build, lastBuild: g.last_build,
    n: g.n, builds: [], devices: {}, os: {}, flavours: {}, accounts: 0, samples: [],
  }]));
  for (const c of counts) byGroup.get(c.fingerprint)?.builds.push({ build: c.build, n: c.n, lastSeen: c.last_seen });
  const accounts = new Map();
  for (const s of samples) {
    const g = byGroup.get(s.fingerprint);
    if (!g) continue;
    let body;
    try { body = JSON.parse(s.body); } catch { continue; }
    const d = body.device || {};
    if (d.model) g.devices[d.model] = (g.devices[d.model] || 0) + 1;
    if (d.os) g.os[d.os] = (g.os[d.os] || 0) + 1;
    if (d.flavour) g.flavours[d.flavour] = (g.flavours[d.flavour] || 0) + 1;
    // how many people, never who
    if (!accounts.has(s.fingerprint)) accounts.set(s.fingerprint, new Set());
    accounts.get(s.fingerprint).add(s.account_id);
    if (g.samples.length < 3) g.samples.push({ receivedAt: s.received_at, ...body });
  }
  for (const [fp, set] of accounts) byGroup.get(fp).accounts = set.size;
  return json({
    generatedAt: at, since,
    builds: builds.map(b => ({ build: b.build, flavour: b.flavour, firstSeen: b.first_seen, lastSeen: b.last_seen, pings: b.pings })),
    groups: [...byGroup.values()],
  });
}

// MARK: housekeeping

/// Nightly: reports past their time, and all but the newest few per group.
/// Counts and groups stay (they hold nothing about anybody).
export async function pruneDiagnostics(env, clock = now) {
  const at = clock();
  await env.DB.prepare('DELETE FROM diagnostic_events WHERE received_at < ?').bind(at - KEEP_DAYS * 86400).run();
  await env.DB.prepare(
    `DELETE FROM diagnostic_events WHERE id IN (SELECT id FROM (
       SELECT id, ROW_NUMBER() OVER (PARTITION BY fingerprint ORDER BY id DESC) AS rn FROM diagnostic_events)
     WHERE rn > ?)`).bind(SAMPLES_PER_GROUP).run();
  const cutoff = new Date((at - 7 * 86400) * 1000).toISOString().slice(0, 10);
  await env.DB.prepare('DELETE FROM diagnostic_quota WHERE day < ?').bind(cutoff).run();
}

/// With the account: every report it sent, and its daily count.
export async function forgetDiagnostics(env, accountId) {
  await env.DB.prepare('DELETE FROM diagnostic_events WHERE account_id = ?').bind(accountId).run();
  await env.DB.prepare('DELETE FROM diagnostic_quota WHERE account_id = ?').bind(accountId).run();
}

/// Whether an account is the owner's: marked in the table, or listed in
/// OWNER_ACCOUNT_IDS.
export async function isOwnerAccount(env, id) {
  if (!id) return false;
  const listed = (env.OWNER_ACCOUNT_IDS || '').split(',').map(s => s.trim()).filter(Boolean);
  if (listed.includes(id)) return true;
  const row = await env.DB.prepare('SELECT owner FROM accounts WHERE id = ?').bind(id).first();
  return !!(row && row.owner === 1);
}
