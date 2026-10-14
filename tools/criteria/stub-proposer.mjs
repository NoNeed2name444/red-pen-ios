// A stub proposer for the vignette route: turns a plain plan (which rule,
// which written spans, how each other option is ruled out) into a proof
// packet for server/vignette-proof.js. It is untrusted by design: the checker
// re-reads everything, so a wrong plan only costs the item its proof. A real
// proposer (a model writing the plan) is designed, not built
// (docs/verification/vignette-proof-research.md §4); this one is for tests,
// the benches and hand-written seed items. No network, no model.

import { itemDigest, VIGNETTE_PROOF_VERSION } from '../../server/vignette-proof.js';

/// plan: {rule, ver, findings: [{slot, text, nth?}], eliminates: [{option,
/// by, rule?, ver?, uses?}], uses?: finding ids}. Each finding's span is the
/// nth (default first) place its text is written in the stem.
export function propose(item, plan) {
  const findings = plan.findings.map((f, i) => {
    let at = -1;
    for (let n = 0, from = 0; n <= (f.nth || 0); n++) {
      at = item.stem.indexOf(f.text, from);
      if (at < 0) break;
      from = at + 1;
    }
    return { id: f.id || `f${i + 1}`, at: [at, at + f.text.length], text: f.text, slot: f.slot };
  });
  return {
    v: VIGNETTE_PROOF_VERSION,
    item: itemDigest(item),
    key: item.key,
    findings,
    proves: { rule: plan.rule, ver: plan.ver, uses: plan.uses || findings.map(f => f.id) },
    eliminates: plan.eliminates || [],
  };
}

/// A seed item the checker accepts against the shipped registry: a
/// reaction read inside the window, at or over the 5 mm cut-off, in a person
/// with HIV. Every word of it is the guideline's or a plain stem.
export function seedItem(mm = 6, hours = 48, group = 'with HIV') {
  const item = {
    kind: 'mcq',
    stem: `A 34-year-old man ${group} attends clinic. His TB skin test, read ${hours} hours after placement, shows ${mm} mm of induration. What is the most appropriate interpretation of this result?`,
    options: ['Positive', 'Negative'],
    key: 0,
  };
  const packet = propose(item, {
    rule: 'cdc-tst-5mm', ver: '1',
    findings: [
      { slot: 'tst_group', text: group },
      { slot: 'tst', text: 'TB skin test' },
      { slot: 'read_hours', text: `${hours} hours after placement` },
      { slot: 'induration_mm', text: `${mm} mm of induration` },
    ],
    eliminates: [{ option: 1, by: 'exclusive' }],
  });
  return { item, packet };
}
