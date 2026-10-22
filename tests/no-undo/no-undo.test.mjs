// The gate before landing on the one version (tools/no_undo.py, see
// docs/one-version.md): a change that took in the latest tip must not undo
// work that landed after it started. Each case builds a throwaway git
// repository in a temp directory, runs the gate, and checks its exit code and
// the commit it names.
//
// Run: node tests/no-undo/no-undo.test.mjs
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const tool = join(here, '..', '..', 'tools', 'no_undo.py');
const scratch = mkdtempSync(join(tmpdir(), 'no-undo-'));
// git with no global or system config (no signing, no hooks, no aliases) and
// no repository inherited from a hook's environment
const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('GIT_')));
Object.assign(env, {
  GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1',
  GIT_AUTHOR_NAME: 'Test', GIT_AUTHOR_EMAIL: 'test@example.invalid',
  GIT_COMMITTER_NAME: 'Test', GIT_COMMITTER_EMAIL: 'test@example.invalid',
});

let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '\n' + detail}`);
  if (!ok) failed++;
}

let repos = 0;
function repo() {
  const dir = join(scratch, `r${++repos}`);
  mkdirSync(dir);
  const git = (...args) => execFileSync('git', args, { cwd: dir, env, encoding: 'utf8', stdio: 'pipe' }).trim();
  const tryGit = (...args) => spawnSync('git', args, { cwd: dir, env, encoding: 'utf8' }).status;
  git('init', '-q', '-b', 'main');
  let staged = [];
  const r = {
    git, tryGit,
    write(path, content) {
      mkdirSync(dirname(join(dir, path)), { recursive: true });
      writeFileSync(join(dir, path), content);
      staged.push(path);
    },
    remove(path) { git('rm', '-q', '--', path); },
    move(from, to) { git('mv', '--', from, to); },
    commit(subject) {
      if (staged.length) git('add', '--', ...staged);
      staged = [];
      git('commit', '-q', '-m', subject);
      return git('rev-parse', 'HEAD');
    },
    // the task: a branch from the base, its own commit, then the latest tip taken in
    task(base, files, subject = 'Task work') {
      git('checkout', '-q', '-b', `task${repos}`, base);
      for (const [p, c] of Object.entries(files)) r.write(p, c);
      const own = r.commit(subject);
      git('merge', '-q', '--no-edit', 'main');
      return own;
    },
    gate(...args) {
      const p = spawnSync('python3', [tool, ...args], { cwd: dir, env, encoding: 'utf8' });
      return { code: p.status, out: `${p.stdout || ''}${p.stderr || ''}${p.error ? String(p.error) : ''}` };
    },
  };
  return r;
}
const short = (sha) => sha.slice(0, 12);
const names = (out, rule, sha) => out.split('\n').some((l) => l.includes(` ${rule} `) && l.includes(short(sha)));
const run = (r, base, ...more) => r.gate('--base', base, '--onto', 'main', '--change', 'HEAD', ...more);

try {
  // a clean change: the tip's new work and the task's own work sit side by side
  {
    const r = repo();
    r.write('server/a.js', 'export const a = 1;\nexport const b = 2;\n');
    r.write('server/c.js', 'export const c = 3;\n');
    const B = r.commit('Start');
    r.write('server/a.js', 'export const a = 10;\nexport const b = 2;\n');
    const X = r.commit('Raise a');
    r.task(B, { 'server/c.js': 'export const c = 30;\n' });
    const g = run(r, B);
    check('a clean change passes and names no commit', g.code === 0 && /^no-undo: OK \(1 files checked\)$/m.test(g.out)
      && !g.out.includes(short(X)), g.out);
  }

  // a merge conflict resolved to the old side: the tip's newer line is lost
  {
    const r = repo();
    r.write('server/retry.js', 'export function retry(fn) {\n  const tries = 3;\n  const wait = 100;\n  return run(fn, tries, wait);\n}\n');
    const B = r.commit('Start');
    r.write('server/retry.js', 'export function retry(fn) {\n  const tries = 3;\n  const wait = 500;\n  return run(fn, tries, wait);\n}\n');
    const X = r.commit('Wait longer between retries');
    r.git('checkout', '-q', '-b', 'task', B);
    r.write('server/retry.js', 'export function retry(fn) {\n  const tries = 3;\n  const wait = 50;\n  return run(fn, tries, wait);\n}\n');
    r.commit('Retry sooner');
    const conflict = r.tryGit('merge', '-q', '--no-edit', 'main');
    r.git('checkout', '--ours', '--', 'server/retry.js');
    r.git('add', '--', 'server/retry.js');
    r.git('commit', '-q', '--no-edit');
    const g = run(r, B);
    check('a conflict resolved to the old side fails U1 and names the undone commit',
      conflict !== 0 && g.code === 1 && /^server\/retry\.js:3: U1 /m.test(g.out) && names(g.out, 'U1', X)
      && g.out.includes('Wait longer between retries'), g.out);
    const allowed = run(r, B, '--allow', short(X));
    check('--allow exempts the commit the owner approved rewriting', allowed.code === 0
      && /^no-undo: OK \(1 files checked\)$/m.test(allowed.out), allowed.out);
    const other = run(r, B, '--allow', B);
    check('--allow of another commit exempts nothing', other.code === 1 && names(other.out, 'U1', X), other.out);
  }

  // a conflict resolved by keeping both sides: the tip's line only re-indented
  {
    const r = repo();
    const view = (call, y) => `struct V {\n    func a() {\n        ${call}(x: 1,\n${' '.repeat(9 + call.length)}y: ${y})\n    }\n}\n`;
    r.write('ios/V.swift', view('draw', 2));
    const B = r.commit('Start');
    r.write('ios/V.swift', view('draw', 3));
    const X = r.commit('Draw lower');
    r.git('checkout', '-q', '-b', 'task', B);
    r.write('ios/V.swift', view('drawNow', 2));
    r.commit('Draw at once');
    const conflict = r.tryGit('merge', '-q', '--no-edit', 'main');
    r.write('ios/V.swift', view('drawNow', 3));
    r.commit('Merge the tip, both sides kept');
    const g = run(r, B);
    check('a line of the tip that is only re-indented is not undone', conflict !== 0 && g.code === 0
      && /^no-undo: OK \(1 files checked\)$/m.test(g.out) && !g.out.includes(short(X)), g.out);
  }

  // a line the tip removed, put back by the task
  {
    const r = repo();
    r.write('server/flags.js', 'export const flags = {\n  fast: true,\n  legacyMode: true,\n  beta: false,\n};\n');
    const B = r.commit('Start');
    r.write('server/flags.js', 'export const flags = {\n  fast: true,\n  beta: false,\n};\n');
    const X = r.commit('Drop the legacy mode flag');
    r.task(B, { 'server/other.js': 'export const other = 1;\n' });
    r.write('server/flags.js', 'export const flags = {\n  fast: true,\n  legacyMode: true,\n  beta: false,\n};\n');
    r.commit('Bring the flag back');
    const g = run(r, B);
    check('re-adding a removed line fails U2 and names the commit that removed it', g.code === 1
      && /^server\/flags\.js:3: U2 brings back a line removed by /m.test(g.out) && names(g.out, 'U2', X)
      && !/ U1 /.test(g.out), g.out);
  }

  // blank lines, brackets, punctuation and lines under 4 characters coming back say nothing
  {
    const r = repo();
    const full = 'Keep this line\n}\n\n);\nabc\n// ----\n[[ ]]\n  - [ ]\nwxyz\nLast real line\n';
    r.write('notes.txt', full);
    const B = r.commit('Start');
    r.write('notes.txt', 'Keep this line\nLast real line\n');
    const X = r.commit('Tidy the notes');
    r.task(B, { 'other.txt': 'other\n' });
    r.write('notes.txt', 'Keep this line\n}\n\n);\nabc\n// ----\n[[ ]]\n  - [ ]\nLast real line\n');
    r.commit('Put the spacing back');
    const g = run(r, B);
    check('trivial lines are ignored', g.code === 0 && /^no-undo: OK \(2 files checked\)$/m.test(g.out)
      && !g.out.includes(short(X)), g.out);
    r.write('notes.txt', full);
    r.commit('Put the word back');
    const g4 = run(r, B);
    check('a line of 4 characters is not trivial', g4.code === 1 && /^notes\.txt:9: U2 /m.test(g4.out)
      && names(g4.out, 'U2', X), g4.out);
  }

  // a file the tip changed, deleted by the task
  {
    const r = repo();
    r.write('docs/guide.md', '# Guide\n\nStep one.\n');
    r.write('docs/other.md', 'Other\n');
    const B = r.commit('Start');
    r.write('docs/guide.md', '# Guide\n\nStep one.\nStep two.\n');
    const X = r.commit('Add step two to the guide');
    r.task(B, { 'docs/other.md': 'Other, longer\n' });
    r.remove('docs/guide.md');
    r.commit('Retire the guide');
    const g = run(r, B);
    check('deleting a file changed after the base fails U3', g.code === 1
      && /^docs\/guide\.md:0: U3 deletes a file changed by /m.test(g.out) && names(g.out, 'U3', X), g.out);
  }

  // a binary the tip changed, swapped back by the task
  {
    const r = repo();
    const old = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 1, 2, 3, 0, 0, 7]);
    r.write('art/icon.png', old);
    r.write('art/notes.txt', 'icon notes\n');
    const B = r.commit('Start');
    r.write('art/icon.png', Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 9, 9, 9, 0, 0, 7]));
    const X = r.commit('Redraw the icon');
    r.task(B, { 'art/notes.txt': 'icon notes, longer\n' });
    r.write('art/icon.png', old);
    r.commit('Use the old icon');
    const g = run(r, B);
    check('a binary changed after the base fails U3', g.code === 1
      && /^art\/icon\.png:0: U3 replaces a binary changed by /m.test(g.out) && names(g.out, 'U3', X), g.out);
  }

  // --scope: every changed path must sit inside the task's globs
  {
    const r = repo();
    r.write('server/a.js', 'export const a = 1;\n');
    r.write('ios/App.swift', 'let app = 1\n');
    const B = r.commit('Start');
    r.git('checkout', '-q', '-b', 'task', B);
    r.write('server/a.js', 'export const a = 2;\n');
    r.write('ios/App.swift', 'let app = 2\n');
    const K = r.commit('Touch the app too');
    const g = run(r, B, '--scope', 'server/*');
    check('--scope flags a path outside it and names the change that touched it', g.code === 1
      && /^ios\/App\.swift:0: U4 is outside --scope; changed by /m.test(g.out) && names(g.out, 'U4', K)
      && !/^server\/a\.js/m.test(g.out), g.out);
    const dirs = run(r, B, '--scope', 'server', '--scope', 'ios/');
    check('--scope takes a directory as everything under it', dirs.code === 0
      && /^no-undo: OK \(2 files checked\)$/m.test(dirs.out), dirs.out);
  }

  // the tip not taken in
  {
    const r = repo();
    r.write('a.txt', 'one\n');
    r.write('b.txt', 'two\n');
    const B = r.commit('Start');
    r.write('a.txt', 'one, newer\n');
    const T = r.commit('Newer work on the tip');
    r.git('checkout', '-q', '-b', 'task', B);
    r.write('b.txt', 'two, task\n');
    r.commit('Task work');
    const g = run(r, B);
    check('a change that does not contain the tip fails: take in the latest tip first', g.code === 1
      && /take in the latest tip first/.test(g.out) && g.out.includes(short(T)), g.out);
  }

  // renames followed: the tip removed and changed lines, then moved the file
  {
    const r = repo();
    r.write('src/old.js', 'const keep = 1;\nconst legacy = makeLegacy();\nconst limit = 5;\n');
    r.write('src/other.js', 'const other = 1;\n');
    const B = r.commit('Start');
    r.write('src/old.js', 'const keep = 1;\nconst limit = 9;\n');
    const X = r.commit('Drop the legacy helper and raise the limit');
    r.move('src/old.js', 'src/new.js');
    const Y = r.commit('Move old.js to new.js');
    r.task(B, { 'src/other.js': 'const other = 2;\n' });
    r.write('src/new.js', 'const keep = 1;\nconst legacy = makeLegacy();\nconst limit = 5;\n');
    r.commit('Bring back the legacy helper');
    const g = run(r, B);
    check('a renamed file is followed: the line removed before the move is caught (U2)', g.code === 1
      && /^src\/new\.js:2-3: U2 brings back a line removed by /m.test(g.out) && names(g.out, 'U2', X), g.out);
    check('and the line changed before the move is caught (U1)', /^src\/new\.js:2: U1 /m.test(g.out)
      && names(g.out, 'U1', X) && !g.out.includes(short(Y)), g.out);
  }

  // a merge on the tip that dropped a line both sides still had
  {
    const r = repo();
    r.write('lib.js', 'const first = 1;\nconst shared = makeShared();\nconst third = 3;\n');
    r.write('a.txt', 'a\n');
    r.write('b.txt', 'b\n');
    const B = r.commit('Start');
    r.git('checkout', '-q', '-b', 'side', B);
    r.write('b.txt', 'b, side\n');
    r.commit('Side work');
    r.git('checkout', '-q', 'main');
    r.write('a.txt', 'a, main\n');
    r.commit('Main work');
    r.git('merge', '-q', '--no-commit', 'side');
    r.write('lib.js', 'const first = 1;\nconst third = 3;\n');
    r.git('add', '--', 'lib.js');
    r.git('commit', '-q', '--no-edit');
    const M = r.git('rev-parse', 'HEAD');
    r.task(B, { 'c.txt': 'c\n' });
    r.write('lib.js', 'const first = 1;\nconst shared = makeShared();\nconst third = 3;\n');
    r.commit('Bring back the shared helper');
    const g = run(r, B);
    check("a line a merge's own resolution removed is caught (U2)", g.code === 1
      && /^lib\.js:2: U2 /m.test(g.out) && names(g.out, 'U2', M), g.out);
  }

  // bad input
  {
    const r = repo();
    r.write('a.txt', 'one\n');
    const B = r.commit('Start');
    r.write('a.txt', 'two\n');
    const X = r.commit('Later');
    const unknown = r.gate('--base', 'f'.repeat(40), '--onto', 'main', '--change', 'HEAD');
    check('an unknown commit is bad input (exit 2)', unknown.code === 2 && /unknown commit/.test(unknown.out), unknown.out);
    const backwards = r.gate('--base', X, '--onto', B, '--change', 'HEAD');
    check('a base that is not an ancestor of the tip is bad input (exit 2)', backwards.code === 2
      && /not an ancestor/.test(backwards.out) && backwards.out.includes(short(X)), backwards.out);
  }
} finally {
  rmSync(scratch, { recursive: true, force: true });
}

if (failed) { console.log(`FAIL ${failed} checks`); process.exit(1); }
console.log('no-undo: all checks passed');
