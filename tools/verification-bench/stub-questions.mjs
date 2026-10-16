// Questions for `layer.mjs --stub` when there is no data directory: the
// harness's plumbing run offline, with nothing fetched. Made-up stems, never
// meant to be read as medicine; each source gets enough for a bench run.
export function stubQuestions(sources, each = 40) {
  const out = [];
  const tag = { MedXpertQA: 'medxpertqa', MedQA: 'medqa' };
  for (const source of sources) {
    for (let n = 0; n < each; n++) {
      const letters = source === 'MedXpertQA' ? 10 : source === 'MedQA' ? 4 : 4;
      out.push({ id: `${tag[source] || 'careqa'}:stub-${n}`, source, kind: 'mcq',
        stem: `Stub question ${n} for ${source}: which of the following is the best answer?`,
        options: Array.from({ length: letters }, (_, i) => `Stub option ${n}.${i + 1}`), key: n % letters, explanation: '' });
    }
  }
  return out;
}
