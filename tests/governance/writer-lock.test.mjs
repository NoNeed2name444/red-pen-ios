// "Lock it" (the owner, 23 Oct): only the writer route writes text. Without
// it (not Pro, not signed in) nothing is written on the phone or by a free
// model; the screens show why, the question form with See Pro.
//
// The screens are SwiftUI, which only a Mac lays out, so here their source is
// read: each writes through WriterGate with llm.writer() and nothing else.
// The llm Swift suite proves the gate itself (no writer, nothing run); the
// server's owner-claude test proves the worker side.
import { readFileSync, existsSync } from 'node:fs';

const repo = new URL('../../', import.meta.url).pathname;
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}
const read = (rel) => readFileSync(repo + rel, 'utf8');

const onDevice = /GemmaModel|gemma\.|CaseAppleWriter|MCQGenerator\.generate|OsceGenerator\.generate|MCQGenerator\.availability|OsceGenerator\.availability|FoundationModels|LanguageModelSession|LocalLLMClient/;

const screens = {
  questions: 'ios/RedPen/Features/Library/MCQGenerateForm.swift',
  cases: 'ios/RedPen/Features/Cases/CaseMakeSection.swift',
  'another case': 'ios/RedPen/Features/Cases/CaseDebriefView.swift',
  stations: 'ios/RedPen/Features/OSCE/OsceGenerateSection.swift',
};
const job = { questions: 'questions', cases: 'cases', 'another case': 'cases', stations: 'stations' };
for (const [what, path] of Object.entries(screens)) {
  const src = read(path);
  check(`${what}: written through WriterGate.write(.${job[what]}, ...)`,
    new RegExp(`WriterGate\\.write\\(\\.${job[what]}, with: writer, noWriter: noWriter\\)`).test(src));
  check(`${what}: the writer is the writer route (llm.writer()), or nothing`,
    /llm\.writer\(\)|CaseMaker\.writer\(llm: llm\)/.test(src) && /guard (!text\.isEmpty, )?writer != nil else \{/.test(src));
  check(`${what}: no on-device writer or model download`, !onDevice.test(src), src.match(onDevice)?.[0]);
}
const form = read(screens.questions);
check('questions: with no writer, the reason and See Pro, not a download',
  /if !writerReady \{[\s\S]{0,200}Label\(llm\.noWriter, systemImage: "lock\.fill"\)[\s\S]{0,200}Button\("See Pro"\)/.test(form)
  && !/[Dd]ownload/.test(form));
const caseMaker = read('ios/RedPen/Features/Cases/CaseMaker.swift');
check('cases: the no-writer words are the cloud\'s own, with no offline model in them',
  /static func noWriter\(llm: LocalLLMService\) -> String \{ llm\.noWriter \}/.test(caseMaker) && !/offline|[Dd]ownload|on-device|On-device/.test(caseMaker));
const service = read('ios/RedPen/Shared/LLM/LocalLLMService.swift');
check('the no-writer words: part of Pro, sign in, or out of reach',
  /var noWriter: String \{ cloudBlocker \?\? "\\\(Brand\.name\) Cloud can't be reached right now\." \}/.test(service));

for (const gone of ['ios/RedPen/Shared/GemmaModel.swift', 'ios/RedPen/Shared/GemmaGenerate.swift', 'ios/RedPen/Shared/GemmaDownload.swift',
                    'ios/RedPen/Features/Cases/CaseGemmaWriter.swift', 'ios/RedPen/Features/Cases/CaseAppleWriter.swift',
                    'ios/RedPen/Shared/LLM/MedicalModelCatalog.swift']) {
  check(`${gone.split('/').pop()} is gone`, !existsSync(repo + gone));
}
check('the shared generator files write nothing themselves',
  !onDevice.test(read('ios/RedPen/Shared/MCQGenerator.swift')) && !onDevice.test(read('ios/RedPen/Shared/OsceGenerator.swift'))
  && !/static func generate\(/.test(read('ios/RedPen/Shared/MCQGenerator.swift') + read('ios/RedPen/Shared/OsceGenerator.swift')));
check('the app no longer links the on-device model package', !/LocalLLMClient/.test(read('ios/project.yml')));
check('nor does the Playgrounds build patch for it', !/Gemma/.test(read('tools/make_swiftpm.py')) && !/Gemma/.test(read('tools/playgrounds_stubs/core/CoreApp.swift')));
check('earlier builds\' model files are removed on launch', /RetiredModels\.removeAll\(\)/.test(service));

console.log(failed ? `writer lock: ${failed} check(s) failed` : 'writer lock: all checks pass');
process.exit(failed ? 1 : 0);
