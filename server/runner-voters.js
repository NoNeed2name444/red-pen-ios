// Runner voters: open-weight models with commercial-use licences, run on
// GitHub's free CPU runners with no key (tools/runner-voter), that solve the
// owner's bench questions blind before they are sent here (the owner, 14 Oct:
// "make free workers without apis", and "use both"). Their answers come in
// the request as ballots and take a family's seat in the first round, so the
// live voters asked are one fewer: free capacity that no shared pool limits.
//
// The rules a runner ballot keeps, so it is a witness like any other:
// - the owner's bench only (the owner key and x-bench): a ballot is the
//   caller's word for what a model answered, so only the owner may send one;
// - only the models named in RUNNER_VOTERS (default DEFAULT_RUNNER_VOTERS),
//   each its own family, and never the model that wrote the items;
// - blind: questions only, every one in the batch answered, a letter among
//   the options and a risk from 1 to 4, never a fix;
// - at most RUNNER_SEATS families (default 1) take a seat, so the live
//   families still hold the rest; one family is one witness (votesStage).
import { familyOf } from './accuracy-model.js';

export const DEFAULT_RUNNER_VOTERS = 'phi-4-mini-instruct,granite-4.0-h-tiny';
export const DEFAULT_RUNNER_SEATS = 1;

/// The models a runner may vote as, in the order their ballots are taken.
export function runnerVoters(env) {
  return String(env.RUNNER_VOTERS ?? DEFAULT_RUNNER_VOTERS).split(',').map(s => s.trim().toLowerCase()).filter(s => /^[a-z0-9._-]{2,80}$/.test(s));
}

/// The ballots votesStage seats first: [{ model, parsed, blind, runner }],
/// `parsed` in `entries` order. `body.runner`: [{ model, votes: [{ answer,
/// risk }] }], each `votes` in the order of `body.items`.
export function runnerBallots(env, body, entries, { owner = false, bench = false } = {}) {
  const sent = Array.isArray(body?.runner) ? body.runner : [];
  if (!owner || !bench || !sent.length || !entries.length) return [];
  if (!entries.every(e => e.item.kind === 'mcq')) return [];
  const allowed = runnerVoters(env);
  const seats = Math.max(0, Math.min(2, Math.floor(Number(env.RUNNER_SEATS ?? DEFAULT_RUNNER_SEATS)) || 0));
  const writer = String(body?.writer || '').trim().toLowerCase();
  const out = [];
  const families = new Set();
  for (const name of allowed) {
    if (out.length >= seats) break;
    if (name === writer || families.has(familyOf(name))) continue;
    const b = sent.find(x => String(x?.model || '').trim().toLowerCase() === name);
    if (!b || !Array.isArray(b.votes)) continue;
    const parsed = entries.map(e => {
      const v = b.votes[e.i];
      const answer = typeof v?.answer === 'string' ? v.answer.trim().toUpperCase() : '';
      if (!/^[A-J]$/.test(answer) || answer.charCodeAt(0) - 65 >= e.item.options.length) return null;
      const risk = Number(v.risk ?? 1);
      if (!Number.isFinite(risk)) return null;
      return { risk: Math.min(4, Math.max(1, Math.round(risk))), answer, evidence: 'none', cites: [], issues: [], fix: null, blind: true, runner: true };
    });
    // a ballot that skipped a question holds no seat: that question would
    // have one witness fewer than the rest of the batch
    if (parsed.some(p => !p)) continue;
    families.add(familyOf(name));
    out.push({ model: name, parsed, blind: true, runner: true });
  }
  return out;
}
