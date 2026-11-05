// The crash summary the App build prints when the app dies under the UI tests
// or the audit (tools/crash_summary.py, T0205). It runs the tool on four
// hand-made reports in fixtures/ (synthetic, no real crash data: a crash .ips,
// a legacy .crash, an ExcUserFault .ips and a CPU limit .ips with a text body)
// and on broken ones made here, and checks every line starts "APP-CRASH ",
// there are at most 40 shared evenly between the reports, no absolute path is
// printed and the exit is 0 whatever it is given. Then it runs app-build.yml's
// "Crash reports of the app" step itself, on this Linux machine, against a
// made-up home and a stand-in xcrun: which reports it keeps and prints. (CI's
// step runs on macOS, with BSD find and the system's bash; the commands it
// uses behave the same in both.)
//
// Run: node tests/crash-summary/crash-summary.test.mjs
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, copyFileSync, readdirSync, existsSync, utimesSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const tool = join(root, 'tools', 'crash_summary.py');
const fixture = (name) => join(here, 'fixtures', name);
const ips = fixture('RedPen-2026-11-05-123505.ips');
const legacy = fixture('RedPen_2026-11-05-124001_fixture.crash');
const userFault = fixture('ExcUserFault_RedPen-2026-11-05-123510.ips');
const cpu = fixture('RedPen.cpu_resource-2026-11-05-123520.ips');
const scratch = mkdtempSync(join(tmpdir(), 'crash-summary-'));

let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '\n' + detail}`);
  if (!ok) failed++;
}
const split = (text) => (text || '').split('\n').filter((l) => l !== '');
function summary(...files) {
  const p = spawnSync('python3', ['-I', tool, ...files], { encoding: 'utf8' });
  return { code: p.status, lines: split(p.stdout), out: `${p.stdout || ''}${p.stderr || ''}${p.error ? String(p.error) : ''}` };
}
// every run: exit 0, every line prefixed, 40 lines at most, no absolute path
function wellFormed(label, r) {
  check(`${label}: exit 0, every line "APP-CRASH ", at most 40, no path`, r.code === 0
    && r.lines.length > 0 && r.lines.length <= 40 && r.lines.every((l) => l.startsWith('APP-CRASH '))
    && !r.out.includes('/Users/') && !r.out.includes('/Library/') && !r.out.includes('/home/'), r.out);
}
const write = (name, text) => { const f = join(scratch, name); writeFileSync(f, text); return f; };
const named = (r, file) => r.lines.findIndex((l) => l.startsWith(`APP-CRASH ${file}: `));

try {
  // a .ips: header, then body; the faulting thread is 1, not the main thread
  {
    const r = summary(ips);
    wellFormed('.ips', r);
    const want = [
      'APP-CRASH RedPen-2026-11-05-123505.ips: RedPen (com.cramdown.app) at 2026-11-05 12:35:05.00 +0000',
      'APP-CRASH exception EXC_BREAKPOINT (SIGTRAP), codes 0x0000000000000001, 0x0000000100a0b0c0',
      'APP-CRASH termination SIGNAL, Trace/BPT trap: 5, by exc handler',
      'APP-CRASH message (libswiftCore.dylib): FixtureModel.swift:12: Fatal error: synthetic fixture, not a real crash',
      'APP-CRASH faulting thread 1 (fixture.worker), 15 frames:',
      'APP-CRASH  0 libswiftCore.dylib _assertionFailure(_:_:file:line:flags:)+312',
      'APP-CRASH  1 RedPen.debug.dylib closure #1 in FixtureModel.load()+56',
      'APP-CRASH  2 RedPen.debug.dylib +0x3000',
      'APP-CRASH  3 RedPen.debug.dylib FixtureModel.load()+120',
      'APP-CRASH  4 RedPen +0x5000',
      'APP-CRASH  5 libsystem_kernel.dylib __pthread_kill+8',
      'APP-CRASH  6 ??? +0x7000',
    ];
    check('.ips: process and time, exception, termination, message (its path cut to the file), then the faulting thread',
      want.every((l, i) => r.lines[i] === l), r.out);
    check('.ips: an unsymbolicated frame is "<image> +0x<imageOffset>", an image with no name takes its path\'s last part',
      r.lines.includes('APP-CRASH  2 RedPen.debug.dylib +0x3000') && r.lines.includes('APP-CRASH  5 libsystem_kernel.dylib __pthread_kill+8'), r.out);
    const frames = r.lines.filter((l) => /^APP-CRASH [ \d]\d /.test(l));
    check('.ips: the top 12 frames, then how many more', frames.length === 12
      && frames[11] === 'APP-CRASH 11 RedPen.debug.dylib frame11+11' && !r.out.includes('not_shown')
      && r.lines[r.lines.length - 1] === 'APP-CRASH  (3 more frames in the report)', r.out);
    check('.ips: the decoy main thread is not the one printed', !r.out.includes('decoy_main_thread_frame'), r.out);
  }

  // a legacy .crash text report
  {
    const r = summary(legacy);
    wellFormed('.crash', r);
    check('.crash: process and date, Exception Type, Exception Codes, Termination Reason, the crashed thread', [
      'APP-CRASH RedPen_2026-11-05-124001_fixture.crash: RedPen [40002] at 2026-11-05 12:40:01.000 +0000',
      'APP-CRASH Exception Type: EXC_BAD_ACCESS (SIGSEGV)',
      'APP-CRASH Exception Codes: KERN_INVALID_ADDRESS at 0x0000000000000010',
      'APP-CRASH Termination Reason: Namespace SIGNAL, Code 11 Segmentation fault: 11',
      'APP-CRASH Thread 0 Crashed:: Dispatch queue: com.apple.main-thread',
      'APP-CRASH 0 RedPen.debug.dylib 0x0000000100a01000 FixtureView.body.getter + 40 (FixtureView.swift:40)',
    ].every((l, i) => r.lines[i] === l), r.out);
    check('.crash: the first 12 lines of the crashed thread and no more', r.lines.length === 17
      && r.lines[16] === 'APP-CRASH 11 UIKitCore 0x0000000180000b00 fixture_frame_11 + 11'
      && !r.out.includes('not_shown') && !r.out.includes('fixture_other_thread'), r.out);
  }

  // the two other kinds the step keeps: a fault the app survived, and a CPU limit report
  {
    const u = summary(userFault);
    wellFormed('ExcUserFault .ips', u);
    check('ExcUserFault .ips: read like a crash .ips', [
      'APP-CRASH ExcUserFault_RedPen-2026-11-05-123510.ips: RedPen (com.cramdown.app) at 2026-11-05 12:35:10.00 +0000',
      'APP-CRASH exception EXC_GUARD (SIGKILL), codes 0x0000000000000000, 0x0000000000000000, GUARD_TYPE_USER (synthetic)',
      'APP-CRASH termination: none in the report',
      'APP-CRASH faulting thread 0 (com.apple.main-thread), 1 frame:',
      'APP-CRASH  0 RedPen.debug.dylib FixtureGuard.trip()+16',
    ].every((l, i) => u.lines[i] === l) && u.lines.length === 5, u.out);
    const c = summary(cpu);
    wellFormed('cpu_resource .ips', c);
    check('cpu_resource .ips: its text body read for the process, the event, the action and the CPU', [
      'APP-CRASH RedPen.cpu_resource-2026-11-05-123520.ips: RedPen at 2026-11-05 12:33:20.000 +0000',
      'APP-CRASH Event: cpu usage',
      'APP-CRASH Action taken: none',
      'APP-CRASH CPU: 90 seconds cpu time over 120 seconds (75% cpu average), exceeding limit of 50% cpu over 180 seconds',
    ].every((l, i) => c.lines[i] === l) && c.lines.length === 4, c.out);
  }

  // a watchdog end: no exception, a code and reasons in place of an indicator
  {
    const header = { app_name: 'RedPen', timestamp: '2026-11-05 12:50:00.00 +0000', bundleID: 'com.cramdown.app', name: 'RedPen' };
    const body = {
      procName: 'RedPen', faultingThread: 0,
      termination: { namespace: 'FRONTBOARD', code: 2343432205, byProc: 'runningboardd',
        reasons: ['scene-update watchdog transgression (synthetic)', 'held at ~/Library/Fixture/held.txt', 'see https://example.invalid/a/b'] },
      threads: [{ triggered: true, frames: [{ imageOffset: 255, imageIndex: 0 }] }],
      usedImages: [{ name: 'RedPen.debug.dylib' }],
    };
    const r = summary(write('RedPen-watchdog.ips', `${JSON.stringify(header)}\n${JSON.stringify(body, null, 2)}\n`));
    wellFormed('watchdog .ips', r);
    check('watchdog .ips: says there was no exception, gives the code in hex and the reasons, a path cut and a URL kept',
      r.lines[1] === 'APP-CRASH exception: none in the report'
      && r.lines[2] === 'APP-CRASH termination FRONTBOARD, code 0x8badf00d, by runningboardd: scene-update watchdog transgression (synthetic) | held at held.txt | see https://example.invalid/a/b'
      && r.lines.includes('APP-CRASH  0 RedPen.debug.dylib +0xff'), r.out);
  }

  // reports that cannot be read: one line each, exit 0
  {
    const text = readFileSync(ips, 'utf8');
    const cases = {
      'a .ips cut off in its body': write('RedPen-cut.ips', text.slice(0, 900)),
      'a .ips that is not JSON at all': write('RedPen-text.ips', 'not a crash report\nat all\n'),
      'a .ips whose header line is broken': write('RedPen-header.ips', '{"app_name": \n'),
      'a header with no body': write('RedPen-head.ips', `${text.split('\n')[0]}\n`),
      'a header and a text body with nothing to read': write('RedPen-prose.ips', `${text.split('\n')[0]}\nsome words\n`),
      'an empty file': write('RedPen-empty.ips', ''),
      'a binary file': write('RedPen-binary.crash', Buffer.from([0, 1, 2, 255, 254, 10, 0, 7])),
      'a missing file': join(scratch, 'RedPen-missing.ips'),
      'a directory': (() => { const d = join(scratch, 'RedPen-dir.ips'); mkdirSync(d); return d; })(),
    };
    for (const [label, file] of Object.entries(cases)) {
      const r = summary(file);
      wellFormed(label, r);
      check(`${label}: one line saying it could not be read`, r.lines.length === 1
        && /^APP-CRASH RedPen-[a-z]+\.(ips|crash): could not read it \(.+\)$/.test(r.lines[0]), r.out);
    }
    const cut = summary(cases['a .ips cut off in its body']);
    check('a cut-off body still names the process its header gives', cut.lines[0].includes('the header names RedPen'), cut.out);
    // one bad report among good ones does not stop the rest
    const mixed = summary(cases['an empty file'], legacy);
    wellFormed('a bad report then a good one', mixed);
    check('a bad report then a good one: both summarised', mixed.lines.length === 18
      && mixed.lines[1].startsWith('APP-CRASH RedPen_2026-11-05-124001_fixture.crash: '), mixed.out);
  }

  // the 40 lines shared evenly: three long reports each keep 13 and the third still shows
  {
    const r = summary(ips, legacy, ips);
    wellFormed('three reports', r);
    const starts = r.lines.map((l, i) => (/^APP-CRASH \S+\.(ips|crash): /.test(l) ? i : -1)).filter((i) => i >= 0);
    check('three reports: 40 lines, each report its header then its exception line, 13 lines each, the cut said',
      r.lines.length === 40 && starts.join() === '0,13,26'
      && r.lines[1].startsWith('APP-CRASH exception EXC_BREAKPOINT') && r.lines[14] === 'APP-CRASH Exception Type: EXC_BAD_ACCESS (SIGSEGV)'
      && r.lines[27].startsWith('APP-CRASH exception EXC_BREAKPOINT')
      && r.lines[39] === 'APP-CRASH (14 more lines cut; the reports themselves hold them)', r.out);
    const short = summary(cpu, ips, userFault, legacy);
    wellFormed('a short report among long ones', short);
    check('a short report among long ones: it keeps all its lines, the room it leaves goes to the others',
      short.lines.length === 40 && named(short, 'RedPen.cpu_resource-2026-11-05-123520.ips') === 0
      && short.lines[3].startsWith('APP-CRASH CPU: ') && named(short, 'RedPen-2026-11-05-123505.ips') === 4
      && named(short, 'ExcUserFault_RedPen-2026-11-05-123510.ips') === 19 && named(short, 'RedPen_2026-11-05-124001_fixture.crash') === 24
      && short.lines[39] === 'APP-CRASH (5 more lines cut; the reports themselves hold them)', short.out);
    const many = summary(...Array(25).fill(legacy));
    wellFormed('25 reports', many);
    check('25 reports: 19 of them with their header and exception lines (the one line left over to the first), the last line says 6 are not shown',
      many.lines.length === 40 && many.lines.filter((l) => l.startsWith('APP-CRASH Exception Type: ')).length === 19
      && many.lines.filter((l) => l.startsWith('APP-CRASH Exception Codes: ')).length === 1
      && many.lines[39] === 'APP-CRASH (386 more lines cut, 6 reports not shown at all; the reports themselves hold them)', many.out);
  }

  // no reports given
  {
    const r = summary();
    wellFormed('no arguments', r);
    check('no arguments: one line', r.lines.length === 1 && r.lines[0] === 'APP-CRASH no crash reports given', r.out);
  }

  // app-build.yml: the step runs always, after the a11y step and before the
  // upload, calls the tool isolated, and the ui-test artifact takes its folder
  const yml = readFileSync(join(root, '.github', 'workflows', 'app-build.yml'), 'utf8');
  {
    const at = (s) => yml.indexOf(s);
    const step = yml.slice(at('- name: Crash reports of the app'), at('- uses: actions/upload-artifact@v4'));
    check('app-build.yml: the crash step sits after the a11y summary and before the upload',
      at('- name: Summary of the accessibility run') > 0
      && at('- name: Crash reports of the app') > at('- name: Summary of the accessibility run')
      && at('- uses: actions/upload-artifact@v4') > at('- name: Crash reports of the app'), '');
    check('app-build.yml: the crash step runs always, cannot fail the job and runs the tool with -I',
      /\n {8}if: always\(\)\n/.test(step) && /\n {8}continue-on-error: true\n/.test(step)
      && step.includes('python3 -I tools/crash_summary.py') && /\n {10}exit 0\n/.test(step), step);
    const upload = yml.slice(at('- uses: actions/upload-artifact@v4'));
    check('app-build.yml: the ui-test artifact uploads crash-reports', /name: ui-test\n/.test(upload)
      && /\n {12}crash-reports\n/.test(upload) && step.includes('out=crash-reports'), upload);
  }

  // The step itself, run here: its run block, cut from app-build.yml
  {
    const lines = yml.split('\n');
    const start = lines.indexOf('      - name: Crash reports of the app');
    const run = lines.indexOf('        run: |', start);
    const block = [];
    for (const l of lines.slice(run + 1)) {
      if (l.trim() !== '' && !l.startsWith('          ')) break;
      block.push(l.slice(10));
    }
    const script = write('step.sh', block.join('\n') + '\n');
    check('the step\'s run block is found', start > 0 && run > start && block.length > 20, String(block.length));
    // xcrun's stand-in: the export puts a copy of the crash .ips, and another app's report, in the bundle's diagnostics
    const bin = join(scratch, 'bin');
    mkdirSync(bin);
    writeFileSync(join(bin, 'xcrun'), [
      '#!/bin/bash',
      'echo "$*" >> "$RUNNER_TEMP/xcrun.log"',
      'out="${@: -1}"',
      'mkdir -p "$out/session" && cp "$FIXTURE_IPS" "$out/session/RedPen-bundle-2026.ips"',
      'printf \'{"name":"OtherApp"}\\n{"procName" : "OtherApp", "threads" : []}\\n\' > "$out/session/OtherApp-1.ips"',
      '',
    ].join('\n'), { mode: 0o755 });
    let runs = 0;
    const hourAgo = Date.now() / 1000 - 3600;
    function step(outcomes, setup) {
      const dir = join(scratch, `run${++runs}`);
      const home = join(dir, 'home'), temp = join(dir, 'temp'), work = join(dir, 'work');
      for (const d of [home, temp, join(work, 'tools')]) mkdirSync(d, { recursive: true });
      copyFileSync(tool, join(work, 'tools', 'crash_summary.py'));
      writeFileSync(join(temp, 'job-began'), '');
      utimesSync(join(temp, 'job-began'), hourAgo, hourAgo);
      setup(home, work);
      const env = { PATH: `${bin}:${process.env.PATH}`, HOME: home, RUNNER_TEMP: temp, GITHUB_STEP_SUMMARY: join(temp, 'summary.md'),
        FIXTURE_IPS: ips, UI_OUTCOME: outcomes[0], A11Y_OUTCOME: outcomes[1] };
      const p = spawnSync('bash', ['-e', script], { cwd: work, env, encoding: 'utf8' });
      const kept = existsSync(join(work, 'crash-reports')) ? readdirSync(join(work, 'crash-reports')).sort() : null;
      const read = (f) => (existsSync(join(temp, f)) ? readFileSync(join(temp, f), 'utf8') : '');
      return { code: p.status, lines: split(p.stdout), out: `${p.stdout || ''}${p.stderr || ''}`, kept, xcrun: split(read('xcrun.log')), summaryMd: read('summary.md'), work };
    }
    const reports = (home) => { const d = join(home, 'Library', 'Logs', 'DiagnosticReports'); mkdirSync(d, { recursive: true }); return d; };
    const put = (dir, from, name, old = false) => {
      copyFileSync(from, join(dir, name));
      if (old) utimesSync(join(dir, name), hourAgo - 3600, hourAgo - 3600);
    };

    // a green run with no report: one line, no export
    const green = step(['success', 'success'], () => {});
    check('step, a green run with no report: one line, exit 0, nothing kept, no export', green.code === 0
      && green.lines.length === 1 && /^APP-CRASH none: no crash report of RedPen /.test(green.lines[0])
      && green.kept && green.kept.length === 0 && green.xcrun.length === 0 && green.summaryMd === '', green.out);

    // the Mac's reports and a simulator's: only the app's, only since the job began
    const host = step(['success', 'success'], (home) => {
      const d = reports(home);
      put(d, ips, 'RedPen-2026-11-05-123505.ips');
      put(d, userFault, 'ExcUserFault_RedPen-2026-11-05-123510.ips');
      put(d, cpu, 'RedPen.cpu_resource-2026-11-05-123520.ips');
      put(d, ips, 'RedPen-2026-11-05-090000.ips', true);
      put(d, ips, 'RedPenUITests-Runner-2026-11-05-123506.ips');
      put(d, ips, 'Other-2026-11-05-123507.ips');
      put(d, ips, 'ExcUserFault_Other-2026-11-05-123508.ips');
      const sim = join(home, 'Library', 'Developer', 'CoreSimulator', 'Devices', 'AAAA', 'data', 'Library', 'Logs', 'DiagnosticReports');
      mkdirSync(sim, { recursive: true });
      put(sim, legacy, 'RedPen_2026-11-05-124001_fixture.crash');
    });
    const want = ['ExcUserFault_RedPen-2026-11-05-123510.ips', 'RedPen-2026-11-05-123505.ips',
      'RedPen.cpu_resource-2026-11-05-123520.ips', 'RedPen_2026-11-05-124001_fixture.crash'];
    check('step, reports on the Mac and a simulator: keeps the crash, the ExcUserFault, the cpu_resource and the legacy report, not an older one, the runner\'s or another app\'s',
      host.code === 0 && host.kept && host.kept.join() === want.join(), `${host.kept}\n${host.out}`);
    check('step, reports on the Mac and a simulator: each of the four named in the log, 40 lines at most, all prefixed, in the run summary too',
      want.every((f) => named(host, f) >= 0) && host.lines.length <= 40 && host.lines.every((l) => l.startsWith('APP-CRASH '))
      && host.summaryMd.startsWith('### Crash reports of the app\n```\n') && want.every((f) => host.summaryMd.includes(`APP-CRASH ${f}: `)), host.out);

    // a red audit with no report on the Mac: the bundle's diagnostics are exported, the app's crash log in them summarised
    const red = step(['skipped', 'failure'], (home, work) => { mkdirSync(join(work, 'a11y.xcresult')); });
    check('step, a red audit: the a11y bundle exported into crash-reports, its RedPen crash log summarised, another app\'s left out',
      red.code === 0 && red.xcrun.join() === 'xcresulttool export diagnostics --path a11y.xcresult --output-path crash-reports/a11y-diagnostics'
      && /^APP-CRASH none: /.test(red.lines[0]) && named(red, 'RedPen-bundle-2026.ips') === 1 && !red.out.includes('OtherApp')
      && existsSync(join(red.work, 'crash-reports', 'a11y-diagnostics', 'session', 'RedPen-bundle-2026.ips')), red.out);
  }
} finally {
  rmSync(scratch, { recursive: true, force: true });
}

if (failed) { console.log(`FAIL ${failed} checks`); process.exit(1); }
console.log('crash-summary: all checks passed');
