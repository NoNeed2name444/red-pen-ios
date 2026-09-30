// Crash and failure groups from the worker, turned into GitHub issues: the
// queue the fixing sessions work from. Run daily by
// .github/workflows/diagnostics-triage.yml.
//
//   - a group with no issue gets one (labels "diagnostics" plus "crash" or
//     "failure"), with its counts, builds, devices, breadcrumbs and frames -
//     symbolicated when the build's dSYM was published (tools/publish_dsyms.sh)
//   - an open issue is refreshed when its group has grown
//   - a closed issue whose group happened again on a newer build is reopened
//     ("regressed")
//   - an open issue whose group has not happened on two builds newer than the
//     last one it was seen on is closed
//
// Each issue carries its fingerprint in a hidden comment, which is how the
// next run finds it again. The planning is pure (planTriage) and tested in
// server/tests/diagnostics.test.mjs; main() does the I/O.
//
// Env: WORKER, OWNER_KEY, GITHUB_TOKEN, GITHUB_REPOSITORY, optional DSYM_DIR
// (a folder of <UUID>.zip dSYMs, fetched from the "dsyms" release), MAX_NEW.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

export const FATAL = new Set(['crash', 'hang', 'cpu', 'disk', 'unclean']);
const MARK = /<!--\s*diagnostics-fingerprint:\s*([0-9a-f]{16})\s*-->/;
const MARK_N = /<!--\s*diagnostics-n:\s*(\d+)\s*-->/;
const MARK_BUILD = /<!--\s*diagnostics-last-build:\s*(.*?)\s*-->/;

// MARK: builds

/// "1.2 (45)" -> [1, 2, 45]; any build string compared number by number,
/// then as text.
export function buildKey(build) {
  return String(build || '').match(/\d+/g)?.map(Number) || [];
}

export function compareBuilds(a, b) {
  const x = buildKey(a), y = buildKey(b);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] ?? -1) - (y[i] ?? -1);
    if (d) return d;
  }
  return String(a).localeCompare(String(b));
}

/// Builds newer than `build` that have run (the app says so once a day), of
/// the same flavour where the flavour is known.
/// The newest build a group has happened on (an old build still in use can
/// report after a newer one has).
export function latestBuild(group) {
  const all = (group.builds || []).map(b => b.build).filter(Boolean);
  if (!all.length) return group.lastBuild || '';
  return all.sort(compareBuilds).at(-1);
}

export function newerBuilds(build, builds) {
  if (!build) return [];
  return builds.filter(b => compareBuilds(b.build, build) > 0).map(b => b.build);
}

// MARK: issue text

export const labelFor = group => FATAL.has(group.kind) ? 'crash' : 'failure';

export function issueTitle(group) {
  const tag = labelFor(group) === 'crash' ? '[crash]' : '[failure]';
  return `${tag} ${group.title}`.slice(0, 180);
}

const table = obj => Object.entries(obj || {}).sort((a, b) => b[1] - a[1])
  .map(([k, v]) => `${k} ×${v}`).join(', ') || '-';
const when = t => t ? new Date(t * 1000).toISOString().replace('T', ' ').slice(0, 16) + ' UTC' : '-';

/// One frame as a line: its symbol when the dSYM gave one, else binary+offset.
export function frameLine(frame, i, symbols) {
  const addr = `${frame.b}+0x${Number(frame.o).toString(16)}`;
  const sym = symbols?.get(`${frame.u || ''}:${frame.o}`);
  return `${String(i).padStart(2)}  ${addr}${sym ? `  ${sym}` : ''}`;
}

export function issueBody(group, { symbols = null, symbolicated = false } = {}) {
  const sample = group.samples?.[0] || {};
  const device = sample.device || {};
  const lines = [];
  lines.push(`**${group.kind}** in **${group.area}**, ${group.n} time${group.n === 1 ? '' : 's'}` +
    (group.accounts ? ` on ${group.accounts} account${group.accounts === 1 ? '' : 's'} (among recent samples)` : '') + '.');
  lines.push('');
  lines.push('| | |', '|---|---|');
  lines.push(`| First seen | ${when(group.firstSeen)} (${group.firstBuild || '-'}) |`);
  lines.push(`| Last seen | ${when(group.lastSeen)} (${group.lastBuild || '-'}) |`);
  const builds = [...(group.builds || [])].sort((a, b) => compareBuilds(b.build, a.build))
    .map(b => `${b.build} ×${b.n}`).join(', ');
  lines.push(`| Builds | ${builds || '-'} |`);
  lines.push(`| Devices | ${table(group.devices)} |`);
  lines.push(`| iOS | ${table(group.os)} |`);
  lines.push(`| Builds of | ${table(group.flavours)} |`);
  lines.push(`| Fingerprint | \`${group.fingerprint}\` |`);
  lines.push('');
  if (sample.exception) {
    const x = sample.exception;
    lines.push('### Exception', '```',
      [x.name && `name: ${x.name}`, x.className && `class: ${x.className}`,
       x.type !== null && x.type !== undefined && `type: ${x.type}`, x.code !== null && x.code !== undefined && `code: ${x.code}`,
       x.signal && `signal: ${x.signal}`, x.termination && `termination: ${x.termination}`].filter(Boolean).join('\n') || '-',
      '```');
  }
  if (sample.error || sample.message) {
    const e = sample.error;
    lines.push('### Failure', '```',
      `message: ${sample.message || '-'}` + (sample.code !== null && sample.code !== undefined ? `\ncode: ${sample.code}` : '') +
      (e ? `\nerror: ${e.domain} ${e.code}${e.name ? ` (${e.name})` : ''}` : ''), '```');
  }
  if (sample.frames?.length) {
    lines.push('### Call stack (crashed thread, innermost first)', '```',
      ...sample.frames.slice(0, 32).map((f, i) => frameLine(f, i, symbols)), '```');
    if (!symbolicated) {
      lines.push(`_Not symbolicated: no dSYM was published for binary ${sample.frames.find(f => f.b === device.binary)?.u || 'UUID unknown'}. ` +
        'App Store/TestFlight/personal Xcode builds publish theirs to the "dsyms" release (tools/publish_dsyms.sh); a Swift Playgrounds build has none, so its frames stay as offsets._');
    }
  }
  if (sample.breadcrumbs?.length) {
    lines.push('### Breadcrumbs (oldest first, seconds before the problem)', '```',
      ...sample.breadcrumbs.map(c => `-${c.t}s  ${c.s}`), '```');
  }
  lines.push('### Device (newest sample)', '```',
    `${device.model || '?'} · iOS ${device.os || '?'} · ${device.idiom || '?'} · ${device.app || '?'} (${device.build || '?'}) ${device.flavour || ''}`,
    `memory ${device.memoryGB ?? '?'} GB · free disk ${device.freeDiskGB ?? '?'} GB · thermal ${device.thermal || '?'} · low power ${device.lowPower ?? '?'} · graphics ${device.graphics || '?'}`,
    '```');
  lines.push('', '### For the fixing session',
    '1. Find the code: the symbolicated frames above, or for a failure the `Diagnostics.record(... area: .' + group.area + ' ...)` call with this message.',
    '2. Reproduce from the breadcrumbs where you can; add a test in ios/RedPen/Tests (or server/tests) that fails first.',
    '3. Fix it and mention `' + group.fingerprint + '` in the commit. This issue closes itself once the problem is absent from two newer builds, and reopens if it comes back.');
  lines.push('', `<!-- diagnostics-fingerprint: ${group.fingerprint} -->`, `<!-- diagnostics-n: ${group.n} -->`,
    `<!-- diagnostics-last-build: ${latestBuild(group)} -->`);
  return lines.join('\n');
}

export function parseIssue(issue) {
  const body = issue.body || '';
  const fp = body.match(MARK)?.[1];
  if (!fp) return null;
  return { number: issue.number, state: issue.state, fingerprint: fp,
           n: Number(body.match(MARK_N)?.[1] || 0), lastBuild: body.match(MARK_BUILD)?.[1] || '',
           closedAt: issue.closed_at ? Math.floor(Date.parse(issue.closed_at) / 1000) : null };
}

// MARK: planning

/// What to do on GitHub, from the worker's summary and the existing issues.
/// Pure: no network.
export function planTriage({ summary, issues, maxNew = 10, symbolsFor = () => ({}) }) {
  const builds = summary.builds || [];
  const known = new Map();
  for (const issue of issues) {
    const parsed = parseIssue(issue);
    // the newest issue wins if a fingerprint somehow has two
    if (parsed && (!known.has(parsed.fingerprint) || known.get(parsed.fingerprint).number < parsed.number)) {
      known.set(parsed.fingerprint, parsed);
    }
  }
  const actions = [];
  const seen = new Set();
  let created = 0;
  // fatal first, then the most frequent
  const groups = [...(summary.groups || [])].sort((a, b) =>
    (FATAL.has(b.kind) - FATAL.has(a.kind)) || (b.n - a.n));
  for (const group of groups) {
    seen.add(group.fingerprint);
    const issue = known.get(group.fingerprint);
    const top = latestBuild(group);
    const newer = newerBuilds(top, builds);
    const quiet = newer.length >= 2;
    const labels = ['diagnostics', labelFor(group)];
    if (!issue) {
      if (quiet || created >= maxNew) continue;
      created++;
      actions.push({ type: 'create', fingerprint: group.fingerprint, title: issueTitle(group),
                     body: issueBody(group, symbolsFor(group)), labels });
      continue;
    }
    if (issue.state === 'closed') {
      // back after it was closed: happened on a build newer than the newest
      // one it had happened on when it was closed (an old build still in
      // somebody's hands reporting it again is not a regression)
      const regressed = top && issue.lastBuild && compareBuilds(top, issue.lastBuild) > 0;
      if (regressed) {
        actions.push({ type: 'reopen', number: issue.number, fingerprint: group.fingerprint,
                       title: issueTitle(group), body: issueBody(group, symbolsFor(group)), labels: [...labels, 'regressed'],
                       comment: `Regressed: seen again on ${top} (${group.n} in total).` });
      }
      continue;
    }
    if (quiet) {
      actions.push({ type: 'close', number: issue.number, fingerprint: group.fingerprint,
                     comment: `Not seen on ${newer.slice(-2).join(' or ')}, both newer than ${top}, the newest build it happened on. Closing as fixed; it reopens if it comes back.` });
      continue;
    }
    if (group.n !== issue.n || top !== issue.lastBuild) {
      actions.push({ type: 'update', number: issue.number, fingerprint: group.fingerprint,
                     title: issueTitle(group), body: issueBody(group, symbolsFor(group)), labels });
    }
  }
  // open issues whose group is not in the summary at all (quiet for the whole
  // window): closed once two newer builds have run
  for (const issue of known.values()) {
    if (seen.has(issue.fingerprint) || issue.state !== 'open') continue;
    const newer = newerBuilds(issue.lastBuild, builds);
    if (newer.length >= 2) {
      actions.push({ type: 'close', number: issue.number, fingerprint: issue.fingerprint,
                     comment: `Not seen for the whole report window, and not on ${newer.slice(-2).join(' or ')}. Closing as fixed.` });
    }
  }
  return actions;
}

// MARK: symbolication (only where the build's dSYM was published)

function symbolizer() {
  for (const name of ['llvm-symbolizer', 'llvm-symbolizer-18', 'llvm-symbolizer-17', 'llvm-symbolizer-16', 'llvm-symbolizer-19']) {
    try { execFileSync(name, ['--version'], { stdio: 'ignore' }); return name; } catch { /* next */ }
  }
  return null;
}

/// {`uuid:offset` -> "function (file:line)"} for every frame of the app's
/// binary whose dSYM is in DSYM_DIR (unpacked from <UUID>.zip).
export function symbolicate(groups, dir, textBase = 0x100000000n) {
  const map = new Map();
  if (!dir || !existsSync(dir)) return map;
  const tool = symbolizer();
  if (!tool) { console.log('no llvm-symbolizer on this runner: frames stay as offsets'); return map; }
  const wanted = new Map();
  for (const g of groups) for (const s of g.samples || []) for (const f of s.frames || []) {
    if (f.u) (wanted.get(f.u.toUpperCase()) || wanted.set(f.u.toUpperCase(), new Set()).get(f.u.toUpperCase())).add(f.o);
  }
  for (const [uuid, offsets] of wanted) {
    const zip = join(dir, `${uuid}.zip`);
    if (!existsSync(zip)) continue;
    const out = join(dir, uuid);
    try {
      if (!existsSync(out)) { mkdirSync(out, { recursive: true }); execFileSync('unzip', ['-q', '-o', zip, '-d', out]); }
      const dwarf = findDwarf(out);
      if (!dwarf) continue;
      const list = [...offsets];
      const addrs = list.map(o => '0x' + (textBase + BigInt(o)).toString(16));
      const text = execFileSync(tool, ['--obj=' + dwarf, '--functions=linkage', '--demangle', '--inlining=false', ...addrs], { encoding: 'utf8' });
      const blocks = text.trim().split(/\n\s*\n/);
      blocks.forEach((b, i) => {
        const [fn, loc] = b.split('\n');
        if (fn && fn !== '??') map.set(`${uuid}:${list[i]}`, `${fn}${loc && !loc.startsWith('??') ? ` (${loc.replace(/^.*\/ios\//, 'ios/')})` : ''}`);
      });
    } catch (error) {
      console.log(`symbolication failed for ${uuid}: ${error.message}`);
    }
  }
  // Swift names come out mangled from llvm-symbolizer; the runner's own
  // Swift toolchain reads them (its absence just leaves them mangled)
  const mangled = [...new Set([...map.values()].map(v => v.split(' (')[0]).filter(n => /^_?\$s/.test(n)))];
  if (mangled.length) {
    try {
      const plain = execFileSync('swift', ['demangle', '--simplified', '--compact'], { input: mangled.join('\n'), encoding: 'utf8' }).split('\n');
      const names = new Map(mangled.map((m, i) => [m, plain[i] || m]));
      for (const [k, v] of map) {
        const [fn, ...rest] = v.split(' (');
        if (names.has(fn)) map.set(k, [names.get(fn), ...rest].join(' ('));
      }
    } catch { /* no swift on this runner */ }
  }
  // keys use the frames' own spelling of the uuid
  const byFrame = new Map();
  for (const g of groups) for (const s of g.samples || []) for (const f of s.frames || []) {
    const hit = f.u && map.get(`${f.u.toUpperCase()}:${f.o}`);
    if (hit) byFrame.set(`${f.u}:${f.o}`, hit);
  }
  return byFrame;
}

function findDwarf(root) {
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, e.name);
      if (e.isDirectory()) stack.push(p);
      else if (dir.endsWith(join('Contents', 'Resources', 'DWARF'))) return p;
    }
  }
  return null;
}

// MARK: I/O

async function github(path, { method = 'GET', body } = {}) {
  const response = await fetch(`${process.env.GITHUB_API_URL || 'https://api.github.com'}/repos/${process.env.GITHUB_REPOSITORY}${path}`, {
    method,
    headers: { authorization: `Bearer ${process.env.GITHUB_TOKEN}`, accept: 'application/vnd.github+json',
               'content-type': 'application/json', 'user-agent': 'diagnostics-triage' },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok && response.status !== 422) throw new Error(`GitHub ${method} ${path}: ${response.status}`);
  return response.status === 204 ? null : await response.json().catch(() => null);
}

async function allIssues() {
  const out = [];
  for (let page = 1; page <= 20; page++) {
    const batch = await github(`/issues?labels=diagnostics&state=all&per_page=100&page=${page}`);
    if (!batch?.length) break;
    out.push(...batch.filter(i => !i.pull_request));
    if (batch.length < 100) break;
  }
  return out;
}

async function main() {
  const worker = (process.env.WORKER || 'https://redpen-auth.vv7sh4rnnw.workers.dev').replace(/\/+$/, '');
  const response = await fetch(`${worker}/diagnostics/summary?limit=200`, {
    headers: { authorization: `Bearer ${process.env.OWNER_KEY}` },
  });
  if (response.status === 404) { console.log('the worker has no diagnostics yet (not deployed, or not the owner key)'); return; }
  if (!response.ok) throw new Error(`summary: ${response.status}`);
  const summary = await response.json();
  console.log(`${summary.groups.length} groups, ${summary.builds.length} builds`);

  // only the dSYMs these groups need, from the "dsyms" release
  const dir = process.env.DSYM_DIR;
  if (dir) {
    mkdirSync(dir, { recursive: true });
    const uuids = new Set();
    for (const g of summary.groups) for (const s of g.samples || []) for (const f of s.frames || []) {
      if (f.u && f.b === s.device?.binary) uuids.add(f.u.toUpperCase());
    }
    for (const u of uuids) {
      try { execFileSync('gh', ['release', 'download', 'dsyms', '-p', `${u}.zip`, '-D', dir, '--clobber'], { stdio: 'ignore' }); }
      catch { /* not published: that build's frames stay as offsets */ }
    }
  }
  const symbols = symbolicate(summary.groups, dir);
  const symbolsFor = group => {
    const frames = group.samples?.[0]?.frames || [];
    return { symbols, symbolicated: frames.some(f => symbols.has(`${f.u}:${f.o}`)) };
  };

  for (const [name, color, description] of [['diagnostics', '5319e7', 'From the app\'s crash and failure reports'],
    ['crash', 'b60205', 'A crash, hang or unclean exit'], ['failure', 'd93f0b', 'A failure the app caught'],
    ['regressed', 'fbca04', 'Came back after it was closed']]) {
    await github('/labels', { method: 'POST', body: { name, color, description } });
  }
  const actions = planTriage({ summary, issues: await allIssues(), maxNew: Number(process.env.MAX_NEW) || 10, symbolsFor });
  for (const a of actions) {
    console.log(`${a.type} ${a.fingerprint}${a.number ? ` #${a.number}` : ''}`);
    if (a.type === 'create') await github('/issues', { method: 'POST', body: { title: a.title, body: a.body, labels: a.labels } });
    if (a.type === 'update') await github(`/issues/${a.number}`, { method: 'PATCH', body: { title: a.title, body: a.body, labels: a.labels } });
    if (a.type === 'reopen') {
      await github(`/issues/${a.number}`, { method: 'PATCH', body: { state: 'open', title: a.title, body: a.body, labels: a.labels } });
      await github(`/issues/${a.number}/comments`, { method: 'POST', body: { body: a.comment } });
    }
    if (a.type === 'close') {
      await github(`/issues/${a.number}/comments`, { method: 'POST', body: { body: a.comment } });
      await github(`/issues/${a.number}`, { method: 'PATCH', body: { state: 'closed', state_reason: 'completed' } });
    }
  }
  console.log(`${actions.length} change(s)`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch(error => { console.error(error.message); process.exit(1); });
}
