// The preview's fade gate (tools/ward_frames_check.py) under the owner's
// loosened rule (15 Oct, 6:25 PM Cairo: "loosen the no fade rule a bit"):
// the content fails only when it stays faded for longer than 0.2 s, a
// shorter dip is reported as allowed, and the status bar is measured and
// reported but never fails. Runs the gate's verdict on made-up frames, so
// it needs neither ffmpeg nor Pillow.
import { execFileSync } from 'node:child_process';

const tools = new URL('../../tools/', import.meta.url).pathname;
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}

// each frame: [time, content [mean, spread], status bar [mean, spread]]
const L = [220, 40], D = [60, 38], F = [200, 10];   // light, dark, faded content
const SL = [225, 46], SD = [70, 43], SF = [223, 11]; // the same for the status bar
const frames = (...list) => ({ times: list.map((f) => f[0]), rows: list.map((f) => [f[1], f[2]]) });
const cases = {
  clean: { ...frames([0, L, SL], [1, D, SD], [2, L, SL], [3, D, SD]), end: 4 },
  brief: { ...frames([0, L, SL], [1, D, SD], [2, F, SL], [2.1, L, SL], [3, D, SD]), end: 4 },
  edge: { ...frames([0, L, SL], [1, D, SD], [2, F, SL], [2.2, L, SL], [3, D, SD]), end: 4 },
  long: { ...frames([0, L, SL], [1, D, SD], [2, F, SL], [2.1, F, SL], [2.2, F, SL], [2.35, L, SL], [3, D, SD]), end: 4 },
  rest: { ...frames([0, L, SL], [1, D, SD], [2, L, SL], [3, F, SL]), end: 5 },
  restUnknown: { ...frames([0, L, SL], [1, D, SD], [2, L, SL], [3, F, SL]), end: null },
  // r14's study screen: the clock kept the dark style on the light page and
  // took 0.38 s to fade across, iOS's own status bar transition
  statusBar: { ...frames([0, D, SD], [1.7, L, SF], [1.9, L, SF], [2.083, L, SL], [4.2, D, SD], [7, L, SL]), end: 10 },
  oneMode: { ...frames([0, L, SL], [1, L, SL]), end: 2 },
  mismatch: { times: [0, 1], rows: [[L, SL], [D, SD], [L, SL]], end: 3 },
};

const driver = `
import json, sys
sys.path.insert(0, ${JSON.stringify(tools)})
import ward_frames_check as w
cases = json.load(sys.stdin)
out = {}
for name, c in cases.items():
    rows = [{"content": tuple(r[0]), "status bar": tuple(r[1])} for r in c["rows"]]
    lines, code = w.judge(rows, c["times"], c["end"])
    out[name] = {"lines": lines, "code": code}
out["_parse"] = w.parse_times("0.000000,\\n1.663333\\n\\nN/A\\n2.5,,\\n")
out["_consts"] = [w.FADED, w.BRIEF, w.GATED["content"], w.GATED["status bar"]]
print(json.dumps(out))
`;
const got = JSON.parse(execFileSync('python3', ['-c', driver], { input: JSON.stringify(cases), encoding: 'utf8' }));
const text = (name) => got[name].lines.join('\n');

check('the floor stays at 0.8 of the lower end, 0.2 s is brief, only the content is gated',
  JSON.stringify(got._consts) === JSON.stringify([0.8, 0.2, true, false]), JSON.stringify(got._consts));
check('ffprobe csv: a trailing comma, a blank line and N/A', JSON.stringify(got._parse) === JSON.stringify([0, 1.663333, null, 2.5]),
  JSON.stringify(got._parse));
check('a switch in one step is clean', got.clean.code === 0 && /^clean/m.test(text('clean')), text('clean'));
check('a 0.1 s dip is a brief dip, allowed', got.brief.code === 0 && /brief dip, allowed \(content\): frames 2-2 from 2\.000 s, on screen 0\.100 s/.test(text('brief')),
  text('brief'));
check('a dip of exactly 0.2 s is allowed', got.edge.code === 0 && /brief dip, allowed/.test(text('edge')), text('edge'));
check('0.35 s faded fails, measured to the first frame back', got.long.code === 1 && /FADED content, longer than 0\.2 s: frames 2-4 from 2\.000 s, on screen 0\.350 s/.test(text('long')),
  text('long'));
check('faded until the recording ends is washed out at rest', got.rest.code === 1 && /on screen 2\.000 s/.test(text('rest')), text('rest'));
check('faded to an end of unknown time fails too', got.restUnknown.code === 1 && /to the end, length unknown/.test(text('restUnknown')),
  text('restUnknown'));
check("the status bar's 0.38 s fade is reported and passes", got.statusBar.code === 0
  && /faded status bar, not gated: frames 1-2 from 1\.700 s, on screen 0\.383 s/.test(text('statusBar'))
  && !/FADED/.test(text('statusBar')), text('statusBar'));
check('one mode only has nothing to check', got.oneMode.code === 2, text('oneMode'));
check('frames without times cannot be measured', got.mismatch.code === 2 && /cannot be measured/.test(text('mismatch')), text('mismatch'));

if (failed) { console.log(`FAIL ${failed} checks`); process.exit(1); }
console.log('frames-check: all checks passed');
