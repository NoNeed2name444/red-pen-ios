// Crash and failure reports: validated, scrubbed, capped per account, grouped
// by fingerprint, readable by the owner only, deleted with the account - and
// the triage that turns groups into GitHub issues.
//
// Run: node server/tests/diagnostics.test.mjs
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import worker from '../worker.js';
import { sign } from '../tokens.js';
import { scrub, identifier, template, messageKey, termination, fnv1a64, canonical, fingerprint, cleanEvent, cleanDevice, title,
         pruneDiagnostics, EVENTS_PER_DAY, EVENTS_PER_REQUEST, REQUESTS_PER_DAY } from '../diagnostics.js';
import { planTriage, issueBody, parseIssue, compareBuilds, latestBuild, newerBuilds, frameLine } from '../triage/diagnostics-triage.mjs';

const here = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };
const db = new DatabaseSync(':memory:');
const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8').split('\n').map(l => l.replace(/--.*$/, '')).join('\n');
for (const s of sql.split(';')) if (s.trim()) db.exec(s);
const env = { SESSION_SECRET: 'secret', OWNER_KEY: 'k'.repeat(64), DB: { prepare(q) { const st = db.prepare(q); let a = []; const api = {
  bind(...x) { a = x; return api; }, first() { return st.get(...a) ?? null; },
  all() { return { results: st.all(...a) }; },
  run() { return { meta: { changes: Number(st.run(...a).changes) } }; } }; return api; } } };
db.prepare(`INSERT INTO accounts (id, provider, subject, created_at, owner) VALUES
  ('alice', 'device', 'a', 0, 0), ('bob', 'device', 'b', 0, 0), ('boss', 'device', 'o', 0, 1), ('carol', 'device', 'c', 0, 0)`).run();

const token = who => sign({ sub: who, typ: 'access', iat: Math.floor(Date.now() / 1000) }, 'secret', 600);
const post = async (who, body) => {
  const text = JSON.stringify(body);
  return worker.fetch(new Request('https://w/diagnostics', { method: 'POST',
    headers: { authorization: 'Bearer ' + await token(who), 'content-length': String(text.length) }, body: text }), env);
};
const summary = async auth => worker.fetch(new Request('https://w/diagnostics/summary', {
  headers: auth ? { authorization: 'Bearer ' + auth } : {} }), env);
const nowS = Math.floor(Date.now() / 1000);
const device = { model: 'iPhone17,3', os: '26.0.1', idiom: 'phone', app: '1.2', build: '45', flavour: 'testflight',
                 binary: 'RedPen', memoryGB: 8, freeDiskGB: 52, thermal: 'nominal', lowPower: false, graphics: 'automatic' };

// MARK: scrubbing - nothing a student wrote leaves the phone, and if it did it would stop here

{
  const medical = 'Patient Jane Doe, 34F, MRN 88231907, chest pain radiating to left arm; troponin 2.4 - see jane.doe@uni.ac.uk /var/mobile/Containers/Data/Application/1B2C/Documents/notes.json token eyJhbGciOiJIUzI1NiJ9abcdefghijklmnop';
  const s = scrub(medical);
  ok(!s.includes('jane.doe@uni.ac.uk') && s.includes('<email>'), 'an email is taken out');
  ok(!s.includes('/var/mobile') && s.includes('<path>'), 'a file path is taken out');
  ok(!s.includes('88231907'), 'a record number is taken out');
  ok(!s.includes('eyJhbGciOiJIUzI1NiJ9'), 'a token is taken out');
  ok(messageKey('sync.failed') === 'sync.failed' && messageKey(medical) === null && messageKey('Chest pain') === null,
     'a message must be a key from the app\'s source, never a sentence');
  ok(termination('Namespace SIGNAL, Code 0xb') === 'Namespace SIGNAL, Code 0xb'
     && termination('Namespace RUNNINGBOARD, Code 0xdead10cc Jane Doe') === 'Namespace RUNNINGBOARD, Code 0xdead10cc'
     && termination(medical) === null, 'only the namespace and code of a termination reason are kept');
  ok(s.length <= 160, 'and it is clipped');
  ok(scrub('https://example.com/a?b=c failed') === '<url> failed', 'a link is taken out');
  ok(scrub('1B2C3D4E-1111-2222-3333-444455556666') === '<id>', 'a UUID is taken out');
  ok(identifier('NSRangeException') === 'NSRangeException' && identifier('chest pain radiating') === null,
     'an identifier must look like code, not a sentence');
  ok(template('status 502') === template('status 503'), 'numbers do not split a failure into many');

  // a whole report built to leak: everything free-form is refused or scrubbed
  const leak = cleanEvent({ kind: 'error', area: 'ai', at: nowS, message: medical,
    error: { domain: 'Patient Jane Doe', code: 5, name: 'chest pain' },
    exception: { name: 'Jane Doe', className: 'x@y.com', termination: medical },
    breadcrumbs: [{ t: 3, s: 'screen:library' }, { t: 2, s: 'Jane Doe troponin' }, { t: 1, s: 'note:Chest pain' }],
    frames: [{ b: 'RedPen', o: 12, u: 'not a uuid' }], secret: 'hunter2', email: 'a@b.com' }, nowS);
  const stored = JSON.stringify(leak);
  for (const bad of ['Jane', 'jane.doe', 'hunter2', 'a@b.com', 'x@y.com', '88231907', 'chest pain', 'Chest pain']) {
    ok(!stored.includes(bad), `a report built to leak keeps no "${bad}"`);
  }
  ok(leak.error.domain === 'unknown' && leak.error.name === null, 'an error domain or name that is a sentence is dropped');
  ok(leak.breadcrumbs.length === 1 && leak.breadcrumbs[0].s === 'screen:library', 'only breadcrumbs that are names are kept');
  ok(leak.frames[0].u === null, 'a frame\'s UUID must be a UUID');
  ok(!('secret' in leak) && !('email' in leak), 'unknown fields are not kept');
  ok(cleanEvent({ kind: 'explode', area: 'ai', at: nowS }) === null, 'an unknown kind is refused');
  ok(cleanEvent({ kind: 'error', area: 'ai', at: nowS - 90 * 86400 }) === null, 'a report from months ago is refused');
  ok(cleanDevice({ ...device, model: 'Jane\'s iPhone <script>' }).model === null, 'a device name (not a model id) is refused');
}

// MARK: fingerprints - the same function as the app's (DiagnosticsTests.swift has the same vectors)

{
  ok(fnv1a64('') === 'cbf29ce484222325', 'FNV-1a of nothing');
  ok(fnv1a64('a') === 'af63dc4c8601ec8c', 'FNV-1a of "a"');
  ok(fnv1a64('error|sync|sync.failed|NSURLErrorDomain|-1001||') === 'd9020bac8713b2d5', 'FNV-1a of a canonical failure');
  ok(fnv1a64('crash|t1:s11|RedPen+64,RedPen+c8') === '7f2398553371ac5f', 'FNV-1a of a canonical crash');
  const crash = (o1, extra = {}) => ({ kind: 'crash', area: 'app', exception: { type: 1, signal: 11 },
    frames: [{ b: 'libsystem_kernel.dylib', o: 5 }, { b: 'RedPen', o: o1 }, { b: 'RedPen', o: 200 }], ...extra });
  ok(canonical(crash(100), 'RedPen') === 'crash|t1:s11|RedPen+64,RedPen+c8', 'a crash is known by its exception and its own frames');
  ok(fingerprint(crash(100), 'RedPen') === fingerprint(crash(100, { at: 5, count: 9 }), 'RedPen'), 'the same crash has the same fingerprint');
  ok(fingerprint(crash(100), 'RedPen') !== fingerprint(crash(101), 'RedPen'), 'a different place is a different crash');
  const system = { kind: 'crash', area: 'app', exception: { name: 'NSRangeException' }, frames: [{ b: 'CoreFoundation', o: 1 }] };
  ok(canonical(system, 'RedPen') === 'crash|NSRangeException|CoreFoundation+1', 'with none of the app\'s frames, the system\'s are used');
  const failA = { kind: 'error', area: 'ai', message: 'hosted.http_status', code: 502, error: null };
  const failB = { ...failA, code: 503 };
  ok(fingerprint(failA, 'RedPen') !== fingerprint(failB, 'RedPen'), 'a different status is a different failure');
  ok(title(crash(100), 'RedPen') === 'Crash: SIGSEGV at RedPen+0x64', 'a crash has a readable title');
  ok(title({ kind: 'unclean', area: 'app', breadcrumbs: [{ t: 1, s: 'screen:graph3d' }] }) === 'Unclean exit (killed or crashed) after screen:graph3d',
     'an unclean exit is named by where it happened');
}

// MARK: the route

{
  const crash = { kind: 'crash', area: 'app', at: nowS - 60, exception: { type: 1, signal: 11, termination: 'Namespace SIGNAL, Code 11 /private/var/mobile/x/y' },
    frames: [{ b: 'RedPen', u: '247F0C11-9AF0-3D41-9C6A-3C6B0C9D2FB4', o: 123456 }], breadcrumbs: [{ t: 4, s: 'screen:library' }, { t: 1, s: 'action:open_set' }] };
  const failure = { kind: 'error', area: 'sync', at: nowS - 30, message: 'sync.failed', error: { domain: 'NSURLErrorDomain', code: -1001 }, count: 3 };
  let r = await post('alice', { device, events: [crash, failure] });
  let body = await r.json();
  ok(r.status === 200 && body.accepted === 2, 'two reports accepted');
  r = await post('bob', { device: { ...device, build: '46', model: 'iPad16,3' }, events: [crash] });
  ok((await r.json()).accepted === 1, 'the same crash from another account');
  const groups = db.prepare('SELECT * FROM diagnostic_groups').all();
  ok(groups.length === 2, 'two groups, not three');
  const crashGroup = groups.find(g => g.kind === 'crash');
  ok(crashGroup.n === 2 && crashGroup.first_build === '1.2 (45)' && crashGroup.last_build === '1.2 (46)', 'counted, with first and last build');
  ok(groups.find(g => g.kind === 'error').n === 3, 'a report that happened 3 times counts 3');
  ok(db.prepare('SELECT COUNT(*) AS n FROM diagnostic_counts WHERE fingerprint = ?').get(crashGroup.fingerprint).n === 2, 'counts per build');
  const raw = db.prepare('SELECT body FROM diagnostic_events').all().map(e => e.body).join('\n');
  ok(!raw.includes('/private/var'), 'the termination reason\'s path was dropped');
  ok(canonical({ kind: 'error', area: 'sync', message: 'sync.failed', error: { domain: 'NSURLErrorDomain', code: -1001, name: null }, code: null }, 'RedPen')
     === 'error|sync|sync.failed|NSURLErrorDomain|-1001||', 'a failure\'s canonical form');
  ok(groups.find(g => g.kind === 'error').fingerprint === fnv1a64('error|sync|sync.failed|NSURLErrorDomain|-1001||'), 'is what it is grouped by');

  ok((await worker.fetch(new Request('https://w/diagnostics', { method: 'POST', headers: { 'content-length': '2' }, body: '{}' }), env)).status === 401,
     'reports need a signed-in account');
  ok((await post('alice', { events: [failure] })).status === 400, 'a report without its build is refused');
  const huge = JSON.stringify({ device, events: [{ ...failure, message: 'x'.repeat(70 * 1024) }] });
  ok((await worker.fetch(new Request('https://w/diagnostics', { method: 'POST',
    headers: { authorization: 'Bearer ' + await token('alice'), 'content-length': String(huge.length) }, body: huge }), env)).status === 413,
     'a body over 64 KB is refused before it is read');
  r = await post('alice', { device, events: Array.from({ length: 20 }, () => failure) });
  body = await r.json();
  ok(body.accepted === EVENTS_PER_REQUEST && body.dropped === 20 - EVENTS_PER_REQUEST, 'at most 12 reports in one request');
  r = await post('alice', { device, events: [{ kind: 'nope', area: 'ai', at: nowS }, failure] });
  body = await r.json();
  ok(body.accepted === 1 && body.dropped === 1, 'an invalid report is dropped, the rest kept');

  // the account's day runs out
  let last;
  for (let i = 0; i < 6; i++) last = await post('alice', { device, events: Array.from({ length: 12 }, () => failure) });
  ok(last.status === 429, 'past the day\'s reports the account is refused');
  const used = db.prepare("SELECT n FROM diagnostic_quota WHERE account_id = 'alice'").get().n;
  ok(used === EVENTS_PER_DAY, `and never more than ${EVENTS_PER_DAY} a day are kept (${used})`);
  ok((await post('bob', { device, events: [failure] })).status === 200, 'another account still has its own day');
  let ping;
  for (let i = 0; i <= REQUESTS_PER_DAY; i++) ping = await post('carol', { device, events: [] });
  ok(ping.status === 429, `past ${REQUESTS_PER_DAY} requests in a day, even empty ones are refused`);

  // an empty report is the build saying it runs
  await post('bob', { device: { ...device, build: '47' }, events: [] });
  ok(db.prepare("SELECT COUNT(*) AS n FROM diagnostic_builds WHERE build = '1.2 (47)'").get().n === 1, 'a build with nothing wrong is still recorded');

  // owner only
  ok((await summary()).status === 404, 'the summary is not there for anybody');
  ok((await summary(await token('alice'))).status === 404, 'nor for an ordinary account');
  ok((await summary(await token('boss'))).status === 200, 'the owner\'s account reads it');
  const s = await (await summary('k'.repeat(64))).json();
  ok(Array.isArray(s.groups) && s.groups.length === 2, 'the owner key reads it (the triage workflow)');
  const g = s.groups.find(x => x.kind === 'crash');
  ok(g.builds.length === 2 && g.devices['iPhone17,3'] === 1 && g.devices['iPad16,3'] === 1 && g.accounts === 2, 'with builds, devices and how many accounts');
  ok(g.samples.length === 2 && g.samples[0].breadcrumbs.length === 2 && g.samples[0].frames[0].o === 123456, 'and samples with breadcrumbs and frames');
  ok(!JSON.stringify(s).includes('alice') && !JSON.stringify(s).includes('bob'), 'never which accounts');
  ok(s.builds.some(b => b.build === '1.2 (47)'), 'and every build that has run');

  // deleted with the account
  const del = await worker.fetch(new Request('https://w/account/delete', { method: 'POST',
    headers: { authorization: 'Bearer ' + await token('alice'), 'content-length': '2' }, body: '{}' }), { ...env, JOBS: null });
  ok(del.status === 200, 'the account is deleted');
  ok(db.prepare("SELECT COUNT(*) AS n FROM diagnostic_events WHERE account_id = 'alice'").get().n === 0, 'and its reports with it');
  ok(db.prepare("SELECT COUNT(*) AS n FROM diagnostic_quota WHERE account_id = 'alice'").get().n === 0, 'and its daily count');
  ok(db.prepare("SELECT COUNT(*) AS n FROM diagnostic_events WHERE account_id = 'bob'").get().n > 0, 'but not anybody else\'s');

  // nightly: only the newest samples per group, nothing past its time
  for (let i = 0; i < 25; i++) db.prepare("INSERT INTO diagnostic_events (fingerprint, account_id, build, received_at, body) VALUES ('f', 'bob', 'b', ?, '{}')").run(nowS);
  db.prepare("INSERT INTO diagnostic_events (fingerprint, account_id, build, received_at, body) VALUES ('old', 'bob', 'b', 0, '{}')").run();
  await pruneDiagnostics(env);
  ok(db.prepare("SELECT COUNT(*) AS n FROM diagnostic_events WHERE fingerprint = 'f'").get().n === 20, 'the newest 20 per group are kept');
  ok(db.prepare("SELECT COUNT(*) AS n FROM diagnostic_events WHERE fingerprint = 'old'").get().n === 0, 'old reports go');
}

// MARK: triage

{
  ok(compareBuilds('1.2 (45)', '1.2 (46)') < 0 && compareBuilds('1.10 (1)', '1.9 (99)') > 0, 'builds compare number by number');
  const builds = ['1.2 (45)', '1.2 (46)', '1.2 (47)', '1.3 (48)'].map(b => ({ build: b }));
  ok(newerBuilds('1.2 (46)', builds).join() === '1.2 (47),1.3 (48)', 'newer builds');
  const group = (fp, extra = {}) => ({ fingerprint: fp, kind: 'crash', area: 'app', title: 'Crash: SIGSEGV at RedPen+0x64', n: 3,
    firstSeen: 1, lastSeen: 2, firstBuild: '1.2 (45)', lastBuild: '1.2 (47)',
    builds: [{ build: '1.2 (45)', n: 1 }, { build: '1.2 (47)', n: 2 }], devices: { 'iPhone17,3': 2 }, os: { '26.0': 2 }, flavours: {},
    samples: [{ frames: [{ b: 'RedPen', u: 'U', o: 100 }], breadcrumbs: [{ t: 2, s: 'screen:library' }], device: { binary: 'RedPen' } }], ...extra });
  ok(latestBuild(group('a', { lastBuild: '1.2 (45)' })) === '1.2 (47)', 'the newest build a problem happened on, not the last to report');
  const issue = (fp, n, lastBuild, state = 'open', number = 1) => ({ number, state, closed_at: state === 'closed' ? '2026-01-01T00:00:00Z' : null,
    body: issueBody(group(fp, { n, lastBuild, builds: [{ build: lastBuild, n }] })) });
  ok(parseIssue(issue('0123456789abcdef', 3, '1.2 (47)')).fingerprint === '0123456789abcdef', 'an issue carries its fingerprint');

  let plan = planTriage({ summary: { builds, groups: [group('00000000000000a1'), group('00000000000000a2', { kind: 'error', title: 'Failure in sync: sync.failed' })] }, issues: [] });
  ok(plan.length === 2 && plan.every(a => a.type === 'create'), 'new groups become issues');
  ok(plan[0].labels.includes('crash') && plan[1].labels.includes('failure'), 'labelled crash or failure');
  ok(plan[0].title.startsWith('[crash]') && plan[0].body.includes('screen:library') && plan[0].body.includes('RedPen+0x64'), 'with breadcrumbs and frames');
  ok(plan[0].body.includes('Not symbolicated'), 'saying when frames are not symbolicated');
  const symbols = new Map([['U:100', 'LibraryView.body.getter (LibraryView.swift:88)']]);
  ok(frameLine({ b: 'RedPen', u: 'U', o: 100 }, 0, symbols).includes('LibraryView.swift:88'), 'a symbolicated frame shows its function and line');

  plan = planTriage({ summary: { builds, groups: [group('00000000000000a1', { n: 5 })] }, issues: [issue('00000000000000a1', 3, '1.2 (47)')] });
  ok(plan.length === 1 && plan[0].type === 'update', 'an open issue is refreshed when its group grows');
  plan = planTriage({ summary: { builds, groups: [group('00000000000000a1')] }, issues: [issue('00000000000000a1', 3, '1.2 (47)')] });
  ok(plan.length === 0, 'and left alone when nothing changed');

  const quiet = group('00000000000000a1', { builds: [{ build: '1.2 (45)', n: 3 }], lastBuild: '1.2 (45)' });
  plan = planTriage({ summary: { builds, groups: [quiet] }, issues: [issue('00000000000000a1', 3, '1.2 (45)')] });
  ok(plan.length === 1 && plan[0].type === 'close', 'closed once two newer builds ran without it');
  plan = planTriage({ summary: { builds: builds.slice(0, 2), groups: [quiet] }, issues: [issue('00000000000000a1', 3, '1.2 (45)')] });
  ok(plan.length === 0, 'but not after only one newer build');
  plan = planTriage({ summary: { builds, groups: [] }, issues: [issue('00000000000000a9', 3, '1.2 (45)')] });
  ok(plan.length === 1 && plan[0].type === 'close', 'an issue quiet for the whole window closes too');
  plan = planTriage({ summary: { builds, groups: [quiet] }, issues: [] });
  ok(plan.length === 0, 'a group that is already quiet does not get a new issue');

  const back = group('00000000000000a1', { builds: [{ build: '1.2 (45)', n: 3 }, { build: '1.3 (48)', n: 1 }], lastBuild: '1.3 (48)', n: 4 });
  plan = planTriage({ summary: { builds, groups: [back] }, issues: [issue('00000000000000a1', 3, '1.2 (45)', 'closed')] });
  ok(plan.length === 1 && plan[0].type === 'reopen' && plan[0].labels.includes('regressed'), 'a closed issue reopens when it comes back on a newer build');
  const oldBuild = group('00000000000000a1', { builds: [{ build: '1.2 (45)', n: 5 }], lastBuild: '1.2 (45)', n: 5 });
  plan = planTriage({ summary: { builds, groups: [oldBuild] }, issues: [issue('00000000000000a1', 3, '1.2 (45)', 'closed')] });
  ok(plan.length === 0, 'but not when only the old build reports it again');

  const many = Array.from({ length: 15 }, (_, i) => group(i.toString(16).padStart(16, '0'), { kind: i % 2 ? 'error' : 'crash', n: i }));
  plan = planTriage({ summary: { builds, groups: many }, issues: [], maxNew: 10 });
  ok(plan.length === 10 && plan[0].labels.includes('crash'), 'at most ten new issues a run, crashes first');
}

console.log(failures ? `\n${failures} DIAGNOSTICS TEST FAILURE(S)` : '\nALL DIAGNOSTICS TESTS PASS');
process.exit(failures ? 1 : 0);
