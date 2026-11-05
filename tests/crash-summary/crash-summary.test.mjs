// The crash summary the App build prints when the app dies under the UI tests
// or the audit (tools/crash_summary.py, T0205). It runs the tool on two
// hand-made reports in fixtures/ (synthetic, no real crash data: a .ips and a
// legacy .crash) and on broken ones made here, and checks every line starts
// "APP-CRASH ", there are at most 40, no report path is printed and the exit
// is 0 whatever it is given. Then that app-build.yml runs it where it should.
//
// Run: node tests/crash-summary/crash-summary.test.mjs
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const tool = join(root, 'tools', 'crash_summary.py');
const ips = join(here, 'fixtures', 'RedPen-2026-11-05-123505.ips');
const legacy = join(here, 'fixtures', 'RedPen_2026-11-05-124001_fixture.crash');
const scratch = mkdtempSync(join(tmpdir(), 'crash-summary-'));

let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '\n' + detail}`);
  if (!ok) failed++;
}
function summary(...files) {
  const p = spawnSync('python3', ['-I', tool, ...files], { encoding: 'utf8' });
  const lines = (p.stdout || '').split('\n').filter((l) => l !== '');
  return { code: p.status, lines, out: `${p.stdout || ''}${p.stderr || ''}${p.error ? String(p.error) : ''}` };
}
// every run: exit 0, nothing on stderr, every line prefixed, 40 lines at most, no path
function wellFormed(label, r) {
  check(`${label}: exit 0, every line "APP-CRASH ", at most 40, no path`, r.code === 0
    && r.lines.length > 0 && r.lines.length <= 40 && r.lines.every((l) => l.startsWith('APP-CRASH '))
    && !r.out.includes('/Users/') && !r.out.includes('/Library/'), r.out);
}
const write = (name, text) => { const f = join(scratch, name); writeFileSync(f, text); return f; };

try {
  // a .ips: header, then body; the faulting thread is 1, not the main thread
  {
    const r = summary(ips);
    wellFormed('.ips', r);
    const want = [
      'APP-CRASH RedPen-2026-11-05-123505.ips: RedPen (com.cramdown.app) at 2026-11-05 12:35:05.00 +0000',
      'APP-CRASH exception EXC_BREAKPOINT (SIGTRAP), codes 0x0000000000000001, 0x0000000100a0b0c0',
      'APP-CRASH termination SIGNAL, Trace/BPT trap: 5, by exc handler',
      'APP-CRASH message (libswiftCore.dylib): RedPen/FixtureModel.swift:12: Fatal error: synthetic fixture, not a real crash',
      'APP-CRASH faulting thread 1 (fixture.worker), 15 frames:',
      'APP-CRASH  0 libswiftCore.dylib _assertionFailure(_:_:file:line:flags:)+312',
      'APP-CRASH  1 RedPen.debug.dylib closure #1 in FixtureModel.load()+56',
      'APP-CRASH  2 RedPen.debug.dylib +0x3000',
      'APP-CRASH  3 RedPen.debug.dylib FixtureModel.load()+120',
      'APP-CRASH  4 RedPen +0x5000',
      'APP-CRASH  5 libsystem_kernel.dylib __pthread_kill+8',
      'APP-CRASH  6 ??? +0x7000',
    ];
    check('.ips: process and time, exception, termination, message, then the faulting thread',
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
      'APP-CRASH 0 RedPen.debug.dylib 0x0000000100a01000 FixtureView.body.getter + 40',
    ].every((l, i) => r.lines[i] === l), r.out);
    check('.crash: the first 12 lines of the crashed thread and no more', r.lines.length === 17
      && r.lines[16] === 'APP-CRASH 11 UIKitCore 0x0000000180000b00 fixture_frame_11 + 11'
      && !r.out.includes('not_shown') && !r.out.includes('fixture_other_thread'), r.out);
  }

  // a watchdog end: no exception, a code and reasons in place of an indicator
  {
    const header = { app_name: 'RedPen', timestamp: '2026-11-05 12:50:00.00 +0000', bundleID: 'com.cramdown.app', name: 'RedPen' };
    const body = {
      procName: 'RedPen', faultingThread: 0,
      termination: { namespace: 'FRONTBOARD', code: 2343432205, byProc: 'runningboardd', reasons: ['scene-update watchdog transgression (synthetic)'] },
      threads: [{ triggered: true, frames: [{ imageOffset: 255, imageIndex: 0 }] }],
      usedImages: [{ name: 'RedPen.debug.dylib' }],
    };
    const r = summary(write('RedPen-watchdog.ips', `${JSON.stringify(header)}\n${JSON.stringify(body, null, 2)}\n`));
    wellFormed('watchdog .ips', r);
    check('watchdog .ips: says there was no exception, gives the code in hex and the reasons', r.lines[1] === 'APP-CRASH exception: none in the report'
      && r.lines[2] === 'APP-CRASH termination FRONTBOARD, code 0x8badf00d, by runningboardd: scene-update watchdog transgression (synthetic)'
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

  // many reports: cut to 40 lines, the last saying so
  {
    const r = summary(ips, ips, legacy, ips);
    wellFormed('four reports', r);
    check('four reports: 40 lines, the last says how many were cut', r.lines.length === 40
      && /^APP-CRASH \(\d+ more lines cut; the reports themselves hold them\)$/.test(r.lines[39]), r.out);
  }

  // no reports given
  {
    const r = summary();
    wellFormed('no arguments', r);
    check('no arguments: one line', r.lines.length === 1 && r.lines[0] === 'APP-CRASH no crash reports given', r.out);
  }

  // app-build.yml: the step runs always, after the a11y step and before the
  // upload, calls the tool isolated, and the ui-test artifact takes its folder
  {
    const yml = readFileSync(join(root, '.github', 'workflows', 'app-build.yml'), 'utf8');
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
} finally {
  rmSync(scratch, { recursive: true, force: true });
}

if (failed) { console.log(`FAIL ${failed} checks`); process.exit(1); }
console.log('crash-summary: all checks passed');
