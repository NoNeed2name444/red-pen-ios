// The transcription benchmark's scorer and prompt-builder (tools/asr_bench.mjs):
// no network, no audio, no lecture text - the fixtures below are written for
// this test, not taken from the recording.
import { readFileSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { TERMS, words, wer, termsIn, score, promptFromSwift, commonTerms, appPrompt,
         transcriptFromReply, summary } from '../../tools/asr_bench.mjs';

let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}
const near = (a, b) => Math.abs(a - b) < 1e-9;

// the 8 terms
const all8 = 'الـ mucocutaneous، بعدين malar rash ده acute فهو reversible والـ anti-inflammatory ' +
             'والـ immunosuppressive، والـ chronic اللي هو discoid rash';
check('there are 8 key terms', Object.keys(TERMS).length === 8);
check('a text with all 8 scores 8/8', termsIn(all8).length === 8, termsIn(all8).join());
check('spelling variants count: muco-cutaneous, anti inflammatory, immuno-suppression',
      termsIn('muco-cutaneous anti inflammatory immuno-suppression').length === 3);
check('Arabic-letter spellings do not count', termsIn('ميكو كيوتينيوس مالار راش أكيوت').length === 0);
check('acute inside subacute does not count', !termsIn('subacute').includes('acute'));
check('"malar" alone is not "malar rash"', !termsIn('the malar area').includes('malar rash'));
check('case does not matter', termsIn('CHRONIC Discoid').length === 2);

// words and WER
check('harakat and tatweel are dropped', words('بيـ كَبِد').join(' ') === 'بي كبد', words('بيـ كَبِد').join('|'));
check('an Arabic comma separates words', words('rash، ده').join('|') === 'rash|ده', words('rash، ده').join('|'));
check('Latin punctuation separates, hyphens stay', words('Anti-inflammatory, (acute).').join('|') === 'anti-inflammatory|acute');
check('[mm:ss] timestamps are not words', words('[01:30] acute').join('|') === 'acute');
check('identical texts: WER 0', wer(all8, all8) === 0);
check('punctuation alone does not count as an error', wer('malar rash، acute', 'malar rash, acute.') === 0);
check('one substitution in four words: 0.25', near(wer('a b c d', 'a x c d'), 0.25));
check('one deletion in four words: 0.25', near(wer('a b c d', 'a b d'), 0.25));
check('one insertion over four words: 0.25', near(wer('a b c d', 'a b c d e'), 0.25));
check('nothing heard: WER 1', wer('a b c d', '') === 1);
check('an empty reference does not divide by zero', wer('', 'a') === 1);

const s = score(all8, 'الـ malar rash ده acute and chronic');
check('score counts terms, misses and words', s.terms === 3 && s.of === 8 && s.missed.length === 5 &&
      s.englishWords === 5 && s.arabicWords === 2, JSON.stringify(s));

// the app's prompt, from its own Swift
const swift = `enum CloudTranscript {
    static func prompt(vocabulary: [String]) -> String {
        var text = """
        Line one, "quoted".

          indented two
        """
        if !vocabulary.isEmpty {
            text += "\\n\\nTerms: "
                + vocabulary.joined(separator: ", ") + "."
        }
        return text
    }
}`;
check('a literal is stripped of the closing delimiter\'s indentation',
      promptFromSwift(swift, []) === 'Line one, "quoted".\n\n  indented two', JSON.stringify(promptFromSwift(swift, [])));
check('the vocabulary sentence is added as Swift adds it',
      promptFromSwift(swift, ['lupus', 'malar']) === 'Line one, "quoted".\n\n  indented two\n\nTerms: lupus, malar.');
let threw = false;
try { promptFromSwift(swift.replace('var text = """', 'var text = "x" + """'), []); } catch { threw = true; }
check('a prompt of another shape stops the benchmark rather than guessing', threw);
threw = false;
try { promptFromSwift(swift.replace('Line one', 'Line \\(n) one'), []); } catch { threw = true; }
check('an interpolated prompt stops it too', threw);

// ...and against the real files, so a change to the app's prompt is noticed here
const real = appPrompt();
const cloud = readFileSync(new URL('../../ios/RedPen/Shared/CloudTranscript.swift', import.meta.url), 'utf8');
const common = commonTerms(readFileSync(new URL('../../ios/RedPen/Shared/LectureTranscriber.swift', import.meta.url), 'utf8'));
check('the real prompt starts as the app\'s does', real.startsWith('Transcribe this medical lecture recording word for word.\n\n'));
check('the real prompt has no Swift indentation left', !/\n {2,}\S/.test(real), real.slice(0, 200));
check('the real prompt asks for English terms in English letters', /English letters/.test(real));
check('MedicalTerms.common is read (lupus first)', common.length >= 10 && common[0] === 'lupus', common.join());
check('the real prompt ends with the common terms, as LectureImporter sends them with no slides',
      real.endsWith(common.join(', ') + '.'));
check('every line of the real prompt is in CloudTranscript.swift',
      real.split('\n').filter(l => l && !l.startsWith('Terms from')).every(l => cloud.includes(l)));

// the Worker's reply
check('phrases become one line each', transcriptFromReply({ text: '[{"start":0,"end":1,"text":" malar  rash "},{"start":1,"end":2,"text":"acute"}]' }) === 'malar rash\nacute');
check('a fenced reply still counts', transcriptFromReply({ text: '```json\n[{"start":0,"end":1,"text":"chronic"}]\n```' }) === 'chronic');
check('empty phrases are dropped', transcriptFromReply({ text: '[{"start":0,"end":1,"text":"  "}]' }) === '');
check('not JSON: null', transcriptFromReply({ text: 'Sure! Here is the transcript' }) === null);
check('not an array: null', transcriptFromReply({ text: '{"text":"x"}' }) === null);
check('no reply: null', transcriptFromReply(null) === null);

// the run page
const page = summary({ status: 'ok', model: 'gemini-3.5-flash', result: score(all8, 'malar rash acute'), reference: all8,
                       transcript: 'malar rash acute', window: '90 s + 30 s' });
check('the summary gives the score and the model', page.includes('**2/8**') && page.includes('gemini-3.5-flash'));
check('the summary lists every term', Object.keys(TERMS).every(k => page.includes(`| ${k} |`)));
check('the summary does not publish the transcript unless asked', !page.includes('<details>'));
check('...and does when asked', summary({ status: 'ok', result: score(all8, 'x'), reference: all8, transcript: 'x', showText: true }).includes('<details>'));
check('a skip says why', summary({ status: 'skipped', note: 'the Worker said 429' }).includes('**Skipped:** the Worker said 429'));

// the command line: without the key it skips cleanly and never calls out
const dir = mkdtempSync(join(tmpdir(), 'asr-'));
const out = join(dir, 'summary.md');
const env = { ...process.env, ASR_BENCH_KEY: '', GITHUB_STEP_SUMMARY: out };
const cli = spawnSync(process.execPath, [new URL('../../tools/asr_bench.mjs', import.meta.url).pathname, 'run'], { env, encoding: 'utf8' });
check('no key: exit 0 with a skip on the run page', cli.status === 0 && readFileSync(out, 'utf8').includes('Skipped'), cli.stderr);
writeFileSync(join(dir, 'ref.txt'), all8);
writeFileSync(join(dir, 'hyp.txt'), 'malar rash');
const sc = spawnSync(process.execPath, [new URL('../../tools/asr_bench.mjs', import.meta.url).pathname, 'score',
                     join(dir, 'ref.txt'), join(dir, 'hyp.txt')], { encoding: 'utf8' });
check('score prints JSON', sc.status === 0 && JSON.parse(sc.stdout).terms === 1, sc.stderr);

// the live call, against a fake Worker on this machine
const { createServer } = await import('node:http');
const { spawn } = await import('node:child_process');
let answer = { status: 200, body: { text: '[{"start":0,"end":3,"text":"malar rash ده acute"}]', model: 'gemini-3.5-flash' } };
let seen = null;
const fake = createServer((req, res) => {
  let data = '';
  req.on('data', c => { data += c; });
  req.on('end', () => {
    seen = { path: req.url, auth: req.headers.authorization, body: JSON.parse(data) };
    res.writeHead(answer.status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(answer.body));
  });
});
await new Promise(r => fake.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${fake.address().port}`;
writeFileSync(join(dir, 'a.m4a'), Buffer.from([0, 1, 2, 3, 250]));
const live = (summaryFile) => new Promise(resolve => {
  const child = spawn(process.execPath, [new URL('../../tools/asr_bench.mjs', import.meta.url).pathname, 'run',
    '--audio', join(dir, 'a.m4a'), '--reference', join(dir, 'ref.txt'), '--url', base, '--summary', summaryFile],
    { env: { ...process.env, ASR_BENCH_KEY: 'k'.repeat(64), GITHUB_STEP_SUMMARY: '' } });
  let stdout = '';
  child.stdout.on('data', c => { stdout += c; });
  child.on('close', status => resolve({ status, stdout }));
});
let r = await live(join(dir, 's1.md'));
check('the live call goes to /transcribe/chunk with the owner key as Bearer',
      seen?.path === '/transcribe/chunk' && seen?.auth === 'Bearer ' + 'k'.repeat(64));
check('it sends the audio as base64 and the app\'s own prompt',
      seen?.body.audio === Buffer.from([0, 1, 2, 3, 250]).toString('base64') && seen?.body.prompt === appPrompt());
check('a 200 is scored: 2 of the 8 terms here', r.status === 0 && readFileSync(join(dir, 's1.md'), 'utf8').includes('**2/8**'), r.stdout);
check('the key never reaches the output', !r.stdout.includes('k'.repeat(64)) && !readFileSync(join(dir, 's1.md'), 'utf8').includes('kkkk'));
answer = { status: 429, body: { message: 'Gemini is busy or out of quota right now.' } };
r = await live(join(dir, 's2.md'));
check('a 429 is a skip, not a failure', r.status === 0 && readFileSync(join(dir, 's2.md'), 'utf8').includes('**Skipped:**'));
answer = { status: 410, body: { message: 'gone' } };
r = await live(join(dir, 's3.md'));
check('any other refusal fails the run', r.status === 1 && readFileSync(join(dir, 's3.md'), 'utf8').includes('answered 410'));
answer = { status: 200, body: { text: 'not json', model: 'x' } };
r = await live(join(dir, 's4.md'));
check('an unreadable reply fails the run', r.status === 1 && readFileSync(join(dir, 's4.md'), 'utf8').includes('not the phrases JSON'));
fake.close();

console.log(failed ?`\n${failed} FAILED` : '\nall asr bench tests pass');
process.exit(failed ? 1 : 0);
