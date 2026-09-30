// Generation that carries on when the phone is put away.
//
// The app hands over the whole job - its prompts, already written the way the
// app writes them - and the server works through them one model call at a
// time, keeping every reply until the app comes back for them. The phone can
// be locked, the app swiped away; nothing is lost and nothing has to be
// uploaded anywhere but here.
//
// One Durable Object per account holds that account's jobs and runs them in
// turn on its alarm: a call, save, set the next alarm. Each call goes through
// chat() exactly as a call from the app would, so the Pro check, the daily
// allowance and the budget all hold unchanged.
//
// The prompts may carry two placeholders the server fills in:
//   {{SOURCE}}  - one of the job's sources (sent once, not once per prompt)
//   {{ALREADY}} - on a line of its own (after any prefix, such as "- "), the
//                 items written so far, one per line, so a long set does not
//                 repeat itself
//   {{EXEMPLARS:<exam>:<topic>:<n>}} - n real items in the chosen exam's
//                 style (exams.js), different ones each batch
//
// A job can also carry the accuracy check (`check`: MedVAL's prompt with
// {{INPUT}} and {{OUTPUT}} left open). Once the writing is done the server
// checks every item against the nearest part of the lecture with the cloud
// checker, as the app would - so a set finished while the phone was away is
// checked too.
import { chat, proGate } from './ai.js';
import { fillExemplars } from './exams.js';

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json' },
});
const fail = (status, message) => json({ error: message, message }, status);

export const LIMITS = {
  active: 3,              // jobs running at once, per account
  steps: 200,             // prompts in one job
  // a long lecture arrives as windows of the app's prompt size (40,000
  // characters): sixty of them, and what they add up to, is the real limit
  sources: 60,
  sourceChars: 1_500_000,
  totalSourceChars: 6_000_000,
  // what the accuracy check may queue from one job: past this the rest is
  // left to the app, rather than a job's queue outgrowing its storage
  checkChars: 4_000_000,
  promptChars: 60_000,    // a prompt's own text, before {{SOURCE}} goes in
  count: 1_000,           // items asked for
  alreadyItems: 60,
  keepDays: 7,            // a finished job nobody collected
  kept: 20,               // jobs held at once, finished or not, per account
  // A job still "running" that nothing has touched for this long has lost its
  // alarm (the platform gave up retrying it): it ends, with what it has.
  staleHours: 24,
};
const RETRY_SECONDS = 20;
const MAX_FAILURES = 4;
/// A reply in a job may be as long as the job asked for (checkSpec caps it at
/// 8,000 tokens): a batch of four questions with their differentials needs
/// more than the 2,000 a single request from the app gets.
const JOB_MAX_TOKENS = 8_000;
const DAY_MS = 86_400_000;

// MARK: the worker's side

/// /jobs and /jobs/<id>, for a signed-in account (or the owner key).
export async function jobsRoute(request, env, accountId, { owner = false } = {}) {
  if (!env.JOBS) return fail(503, 'Background generation is not set up on this server.');
  const url = new URL(request.url);
  const id = url.pathname.slice('/jobs'.length).replace(/^\//, '');
  const stub = env.JOBS.get(env.JOBS.idFromName(accountId));
  const forward = (path, init = {}) => stub.fetch(new Request('https://jobs' + path, init));

  if (!id && request.method === 'POST') {
    if (!owner) {
      const refused = await proGate(env, accountId, fetch, 'Background generation is part of Pro.');
      if (refused) return refused;
    }
    let spec;
    try { spec = await request.json(); } catch { return fail(400, 'That job could not be read.'); }
    const checked = checkSpec(spec);
    if (checked.error) return fail(400, checked.error);
    return forward('/create', { method: 'POST', body: JSON.stringify({ accountId, owner, spec: checked.spec }) });
  }
  if (!id && request.method === 'GET') return forward('/list');
  if (!/^[a-f0-9-]{36}$/.test(id)) return fail(404, 'No such job.');
  if (request.method === 'GET') return forward(`/get?id=${id}&outputs=${url.searchParams.get('outputs') ? 1 : 0}`);
  if (request.method === 'DELETE') return forward(`/cancel?id=${id}`, { method: 'POST' });
  return fail(405, 'GET, POST or DELETE.');
}

/// Everything a phone sends is checked before it is kept: a job is stored and
/// then run for minutes, so a malformed one must be refused at the door.
export function checkSpec(raw) {
  if (!raw || typeof raw !== 'object') return { error: 'No job.' };
  const title = typeof raw.title === 'string' ? raw.title.slice(0, 120) : 'Writing';
  const mode = raw.mode === 'each' ? 'each' : raw.mode === 'loop' ? 'loop' : null;
  if (!mode) return { error: 'Unknown job mode.' };
  const extract = ['lines', 'questions', 'stations', 'pages'].includes(raw.extract) ? raw.extract : null;
  if (!extract) return { error: 'Unknown job output.' };
  const sources = Array.isArray(raw.sources) ? raw.sources : [];
  if (sources.length > LIMITS.sources || sources.some(s => typeof s !== 'string' || s.length > LIMITS.sourceChars)
      || sources.reduce((n, s) => n + (typeof s === 'string' ? s.length : 0), 0) > LIMITS.totalSourceChars) {
    return { error: 'The lecture is too large for one job.' };
  }
  const steps = Array.isArray(raw.steps) ? raw.steps : [];
  if (!steps.length || steps.length > LIMITS.steps) return { error: 'A job needs between 1 and 200 prompts.' };
  const cleanSteps = [];
  for (const step of steps) {
    const system = typeof step?.system === 'string' ? step.system : '';
    const user = typeof step?.user === 'string' ? step.user : '';
    if (!user.trim() || system.length + user.length > LIMITS.promptChars) return { error: 'A prompt in that job could not be used.' };
    const source = Number.isInteger(step.source) ? step.source : -1;
    if (source >= sources.length) return { error: 'A prompt names a source the job does not have.' };
    cleanSteps.push({
      system, user, source,
      maxTokens: Math.min(Math.max(Number(step.maxTokens) || 800, 16), 8_000),
      temperature: Math.min(Math.max(Number(step.temperature ?? 0.7), 0), 1.5),
    });
  }
  let check = null;
  if (raw.check != null) {
    const template = typeof raw.check?.template === 'string' ? raw.check.template : '';
    if (!template.includes('{{OUTPUT}}') || template.length > 20_000) return { error: 'The accuracy check in that job could not be used.' };
    check = { template: withReasoningChecks(template), limit: Math.min(Math.max(Number(raw.check.limit) || 40_000, 2_000), 60_000) };
  }
  const count = mode === 'each' ? cleanSteps.length : Math.min(Math.max(Number(raw.count) || 0, 1), LIMITS.count);
  return {
    spec: {
      title, mode, extract, count, sources, steps: cleanSteps, check,
      minFields: Math.min(Math.max(Number(raw.minFields) || 2, 1), 8),
      keyFields: Math.min(Math.max(Number(raw.keyFields) || 1, 1), 8),
      cloze: raw.cloze === true,
      // loop jobs stop after this many batches in a row bring nothing new
      patience: Math.min(Math.max(Number(raw.patience) || 3, 1), 12),
    },
  };
}

// MARK: reading replies

/// The items a reply adds, with the short key each is remembered by.
export function itemsIn(reply, spec) {
  if (spec.extract === 'pages') return [{ key: String(Math.random()), text: reply }];
  if (spec.extract === 'lines') {
    return reply.split('\n')
      .map(line => line.trim().replace(/^(\d+[.)]|[-*•])\s*/, ''))
      .filter(line => line.split('|').length >= spec.minFields || (spec.cloze && line.includes('{{c')))
      .map(line => ({
        key: line.split('|').map(p => p.trim()).slice(0, spec.keyFields).join(' | ').slice(0, 140),
        text: line,
        same: line.toLowerCase(),
      }));
  }
  const object = parseObject(reply);
  if (spec.extract === 'questions') {
    return (Array.isArray(object?.questions) ? object.questions : [])
      .filter(q => typeof q?.stem === 'string' && Array.isArray(q.options) && q.options[q.correctIndex] != null)
      .map(q => {
        const stem = q.stem.trim();
        const letters = ['A', 'B', 'C', 'D', 'E'];
        const options = q.options.map((o, i) => `${letters[Math.min(i, 4)]}. ${o}`);
        return {
          key: (stem.length > 90 ? stem.slice(0, 90) + '…' : stem) + `  [answer: ${String(q.options[q.correctIndex]).trim()}]`,
          same: sameText(stem),
          // what the checker is shown, as the app's own screen writes it
          check: `${stem}\n${options.join('\n')}\nAnswer: ${letters[Math.min(q.correctIndex, 4)]}\nExplanation: ${q.explanation || ''}`
            + differentialBlock(q.differential),
        };
      });
  }
  return (Array.isArray(object?.stations) ? object.stations : [])
    .filter(s => typeof s?.title === 'string' && s.title.trim())
    .map(s => ({
      key: s.title.trim(), same: sameText(s.title),
      check: s.title.trim() + '\n' + (Array.isArray(s.steps) ? s.steps : []).map(x => '- ' + x).join('\n'),
    }));
}

/// A question's differential (most likely / expanded / can't miss, each with
/// findings for and against and the test that settles it), as the checker is
/// shown it - the app's AccuracyChecker.differentialBlock, word for word, so
/// the reasoning checks can test the keyed answer against it.
export function differentialBlock(d) {
  const text = differentialText(d);
  return text ? '\nDifferential:\n' + text : '';
}

const TIERS = [
  ['Most likely', ['mostLikely', 'most_likely', 'Most Likely']],
  ['Expanded', ['expanded', 'Expanded']],
  ['Can\u2019t miss', ['cantMiss', 'cant_miss', "Can't Miss", 'cannotMiss']],
];

export function differentialText(d) {
  if (!d || typeof d !== 'object' || Array.isArray(d)) return '';
  const strings = v => (Array.isArray(v) ? v : typeof v === 'string' ? [v] : [])
    .filter(x => typeof x === 'string').map(x => x.trim()).filter(Boolean);
  const describe = e => {
    if (typeof e === 'string') return e.trim();
    const name = String(e?.name || e?.diagnosis || '').trim();
    if (!name) return '';
    const parts = [];
    const pro = strings(e.for ?? e.supporting);
    const con = strings(e.against);
    const test = typeof e.test === 'string' ? e.test.trim() : '';
    if (pro.length) parts.push('for: ' + pro.join(', '));
    if (con.length) parts.push('against: ' + con.join(', '));
    if (test) parts.push('test: ' + test);
    return parts.length ? `${name} (${parts.join('; ')})` : name;
  };
  const lines = [];
  for (const [title, keys] of TIERS) {
    const raw = keys.map(k => d[k]).find(v => v != null);
    const list = (Array.isArray(raw) ? raw : raw ? [raw] : []).map(describe).filter(Boolean);
    if (list.length) lines.push(`- ${title}: ${list.join('; ')}`);
  }
  return lines.join('\n');
}

/// The clinical-reasoning checks added to MedVAL's own (after the way Glass
/// Health lays out a differential), word for word as the app's
/// MedVAL.reasoningChecks asks for them: does the keyed answer fit every key
/// finding, is a can't-miss diagnosis better supported or left unexcluded, is
/// every claim backed by the lecture or the evidence.
export const REASONING_CHECKS = [
  'Check the clinical reasoning of the output, the way a diagnostic reasoning tool checks a differential:',
  '    a) Does the keyed answer (or the stated diagnosis) fit ALL the key findings given in the output? Name any finding that contradicts it.',
  '    b) Is a can\'t-miss (dangerous) diagnosis better supported by the findings than the keyed answer, or not excluded where the question implies it should be?',
  '    c) Is every factual claim in the explanation or answer supported by the input or by any reference evidence given? Name any claim that is not.',
  "    - Output format: one issue per line, each starting with its kind: `Contradicting finding: <the finding, and why it does not fit>', `Can't miss: <the diagnosis, and why>', or `Unsupported claim: <the claim>'.",
  "    - Return `None' if there are no issues, or if the output has no answer or diagnosis to check.",
  '    - Take these into account in risk_level: a contradicting finding or a can\'t-miss diagnosis left open is at least Level 3; an unsupported claim is at least Level 2, and Level 3 or 4 if it could change a clinical decision.',
].join('\n');

/// A MedVAL check template from an app built before the reasoning checks gets
/// them here, so every job the server checks asks for them. The field goes
/// AFTER MedVAL's own three, so the grade is read exactly as before; a
/// template that already asks for them, or is not MedVAL's, is left alone.
export function withReasoningChecks(template) {
  const described = '\n\nAll interactions will be structured';
  const completed = '[[ ## completed ## ]]';
  if (template.includes('reasoning_issues') || !template.includes('[[ ## risk_level ## ]]')
      || !template.includes(described) || !template.includes(completed)) return template;
  const field = "\n\n4. `reasoning_issues' (str):\n    " + REASONING_CHECKS;
  const at = template.lastIndexOf(completed);
  const withSection = template.slice(0, at) + '[[ ## reasoning_issues ## ]]\n# TO_BE_FILLED_BY_MODEL\n\n' + template.slice(at);
  return withSection.replace(described, field + described);
}

/// How an item is matched between the server and the app: case and spacing aside.
export function sameText(text) {
  return String(text).trim().toLowerCase().replace(/\s+/g, ' ');
}

/// The paragraphs of the lecture sharing the most words with `text`, in
/// reading order - the app's TextSlicing.nearest.
export function nearest(source, text, limit) {
  if (source.length <= limit) return source;
  const words = t => new Set(t.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(w => w.length > 3));
  const wanted = words(text);
  const paragraphs = source.split('\n\n');
  const ranked = paragraphs.map((p, i) => [i, [...words(p)].filter(w => wanted.has(w)).length])
    .sort((a, b) => b[1] - a[1]);
  const chosen = [];
  let size = 0;
  for (const [i, score] of ranked) {
    if (score <= 0) break;
    if (size + paragraphs[i].length > limit) continue;
    chosen.push(i);
    size += paragraphs[i].length;
  }
  if (!chosen.length) return source.slice(0, limit);
  return chosen.sort((a, b) => a - b).map(i => paragraphs[i]).join('\n\n');
}

function parseObject(text) {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try { return JSON.parse(text.slice(start, end + 1)); } catch { return null; }
}

/// A prompt ready to send: its source put in, and what has been written so far.
export function fill(text, source, already, round = 0) {
  // the exemplars first: the lecture itself must never be read as a placeholder
  let out = fillExemplars(text, round).split('{{SOURCE}}').join(source);
  if (out.includes('{{ALREADY}}')) {
    const recent = already.slice(-LIMITS.alreadyItems);
    out = out.split('\n').map(line => {
      const at = line.indexOf('{{ALREADY}}');
      if (at < 0) return line;
      const prefix = line.slice(0, at);
      return recent.length ? recent.map(item => prefix + item).join('\n') : prefix + '(none yet)';
    }).join('\n');
  }
  return out;
}

// MARK: the Durable Object

export class GenerationJobs {
  constructor(state, env, fetcher = fetch) {
    this.state = state;
    this.fetcher = fetcher;
    this.storage = state.storage;
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const id = url.searchParams.get('id');
    switch (url.pathname) {
      case '/create': return this.create(await request.json());
      case '/list': {
        await this.revive();
        return json({ jobs: await this.summaries() });
      }
      case '/get': {
        const job = await this.storage.get(`job:${id}`);
        if (!job) return fail(404, 'No such job.');
        if (job.status === 'running') await this.revive();
        const body = { job: summary(job) };
        if (url.searchParams.get('outputs') === '1') {
          body.outputs = await this.outputs(job);
          body.checks = await this.verdicts(job);
        }
        return json(body);
      }
      case '/cancel': {
        const job = await this.storage.get(`job:${id}`);
        if (!job) return json({ ok: true });
        await this.forget(job);
        return json({ ok: true });
      }
      // the account is being deleted (worker.js): everything here goes, and
      // nothing is left to wake up
      case '/wipe': {
        await this.storage.deleteAll();
        await this.storage.deleteAlarm?.();
        return json({ ok: true });
      }
      default: return fail(404, 'No such endpoint.');
    }
  }

  /// A running job with no alarm (the platform gave up retrying one that kept
  /// failing) is started again when the app asks after it, rather than left
  /// "running" for ever and holding one of the account's three places.
  async revive() {
    if (await this.storage.getAlarm()) return;
    if ((await this.all()).some(j => j.status === 'running')) await this.storage.setAlarm(Date.now() + 50);
  }

  async create({ accountId, owner, spec }) {
    let jobs = await this.all();
    const running = jobs.filter(j => j.status === 'running').length;
    if (running >= LIMITS.active) {
      return fail(429, `${LIMITS.active} jobs are already being written - wait for one to finish.`);
    }
    // Finished jobs wait a week to be collected; without a ceiling, jobs that
    // fail at once could park lecture after lecture here. The oldest finished
    // ones make room first.
    if (jobs.length >= LIMITS.kept) {
      const finished = jobs.filter(j => j.status !== 'running').sort((a, b) => a.updated - b.updated);
      for (const old of finished.slice(0, jobs.length - LIMITS.kept + 1)) await this.forget(old);
      jobs = await this.all();
      if (jobs.length >= LIMITS.kept) return fail(429, 'Too many jobs are waiting to be collected.');
    }
    const id = crypto.randomUUID();
    const now = Date.now();
    const job = {
      id, accountId, owner: !!owner, title: spec.title, mode: spec.mode, extract: spec.extract,
      count: spec.count, minFields: spec.minFields, keyFields: spec.keyFields, cloze: spec.cloze,
      patience: spec.patience, stepCount: spec.steps.length, sourceCount: spec.sources.length,
      status: 'running', done: 0, round: 0, failures: 0, empty: 0, replies: 0,
      phase: 'writing', hasCheck: !!spec.check, checked: 0, checkTotal: 0, checkError: null,
      // the check queue and its verdicts, one stored value per item (a single
      // growing list would pass a Durable Object's limit on one value)
      pendCount: 0, pendChars: 0, verCount: 0, unqueued: 0,
      created: now, updated: now, error: null,
    };
    const writes = { [`job:${id}`]: job, [`keys:${id}`]: [] };
    if (spec.check) writes[`check:${id}`] = spec.check;
    spec.steps.forEach((step, i) => { writes[`step:${id}:${i}`] = step; });
    spec.sources.forEach((source, i) => { writes[`src:${id}:${i}`] = source; });
    // put() takes at most 128 keys at a time
    const entries = Object.entries(writes);
    for (let i = 0; i < entries.length; i += 100) await this.storage.put(Object.fromEntries(entries.slice(i, i + 100)));
    // Start now. An alarm may already be set a week out, to expire finished
    // jobs; with nothing running, it is brought forward rather than waited for.
    const at = await this.storage.getAlarm();
    if (!at || (!running && at > Date.now() + 50)) await this.storage.setAlarm(Date.now() + 50);
    return json({ job: summary(job) }, 201);
  }

  /// One model call for the oldest running job, then the next alarm.
  async alarm() {
    const jobs = await this.all();
    const now = Date.now();
    const expired = now - LIMITS.keepDays * DAY_MS;
    for (const old of jobs.filter(j => j.status !== 'running' && j.updated < expired)) await this.forget(old);
    // running, but untouched for a day: its alarm was lost - it ends here
    for (const stuck of jobs.filter(j => j.status === 'running' && j.updated < now - LIMITS.staleHours * 3_600_000)) {
      stop(stuck, 'The cloud stopped working on this. Try again.');
      stuck.updated = now;
      await this.storage.put(`job:${stuck.id}`, stuck);
      await this.release(stuck);
    }
    const job = jobs.filter(j => j.status === 'running').sort((a, b) => a.created - b.created)[0];
    if (!job) {
      await this.sweep();
      await this.schedule(0);
      return;
    }
    let wait = 0;
    try {
      wait = await this.step(job);
    } catch (error) {
      console.error('job step', error);
      job.failures += 1;
      wait = RETRY_SECONDS;
    }
    if (job.status === 'running' && job.failures >= MAX_FAILURES) {
      if (job.phase === 'checking') {
        job.status = 'done';
        job.checkError = job.checkNote || 'The checker kept failing.';
      } else {
        stop(job, job.error || 'The cloud model kept failing. Try again later.');
      }
    }
    // Written (all of it, or as much as could be): now the accuracy check,
    // before anyone is told it is done. It runs over what was written even
    // when the writing stopped early - if the reason was the day's allowance,
    // its first call is refused at no cost and says so (checkError).
    if (job.status === 'done' && job.phase === 'writing' && job.hasCheck && job.pendCount > 0) {
      job.phase = 'checking';
      job.status = 'running';
      job.checkTotal = job.pendCount;
      job.failures = 0;
      wait = 0;
    }
    job.updated = Date.now();
    // the job may have been cancelled while its call was out
    if (!job.gone && await this.storage.get(`job:${job.id}`)) {
      await this.storage.put(`job:${job.id}`, job);
      // finished: the lecture and prompts are no longer needed, only the
      // replies and verdicts the app comes back for
      if (job.status !== 'running') await this.release(job);
    }
    await this.schedule(wait);
  }

  /// The next alarm: soon while anything runs; otherwise when the oldest
  /// finished job is due to expire, so a job nobody collects is still gone
  /// after keepDays - not kept until the account happens to start another.
  async schedule(wait) {
    const jobs = await this.all();
    if (jobs.some(j => j.status === 'running')) {
      await this.storage.setAlarm(Date.now() + wait * 1000 + 50);
      return;
    }
    if (jobs.length) {
      const due = Math.min(...jobs.map(j => j.updated)) + LIMITS.keepDays * DAY_MS + 60_000;
      await this.storage.setAlarm(Math.max(due, Date.now() + 1000));
    } else {
      await this.storage.deleteAlarm?.();
    }
  }

  /// Anything stored for a job that no longer exists. A cancel that landed
  /// while a model call was out used to leave the call's reply behind, with
  /// nothing pointing at it; this clears what such a cancel left before it was
  /// fixed, and anything else like it.
  async sweep() {
    const jobs = new Set((await this.all()).map(j => j.id));
    const all = await this.storage.list({ prefix: '' });
    const orphans = [...all.keys()].filter(k => !k.startsWith('job:') && !jobs.has(k.split(':')[1]));
    for (let i = 0; i < orphans.length; i += 100) await this.storage.delete(orphans.slice(i, i + 100));
  }

  /// Returns how long to wait before the next call, in seconds.
  async step(job) {
    if (job.phase === 'checking') return this.checkStep(job);
    const index = job.mode === 'each' ? job.done : job.round % job.stepCount;
    const step = await this.storage.get(`step:${job.id}:${index}`);
    const source = step.source >= 0 ? (await this.storage.get(`src:${job.id}:${step.source}`)) || '' : '';
    const keys = (await this.storage.get(`keys:${job.id}`)) || [];
    const already = keys.map(k => k.key);
    const messages = [];
    const round = job.mode === 'each' ? job.done : job.round;
    if (step.system) messages.push({ role: 'system', content: fill(step.system, source, already, round) });
    messages.push({ role: 'user', content: fill(step.user, source, already, round) });

    // One round of trying: a model that is busy is tried again on the next
    // alarm, not waited for here, where waiting is paid for by the second.
    const response = await chat(this.env, job.accountId,
      { model: 'cramdown-writer', messages, max_tokens: step.maxTokens, temperature: step.temperature },
      this.fetcher, { owner: job.owner, maxTokensCap: JOB_MAX_TOKENS, rounds: 1 });
    const body = await response.json().catch(() => ({}));
    // Cancelled (or the account deleted) while the call was out: nothing of
    // it is kept. Everything below is storage only, so nothing else can come
    // between this check and the writes.
    if (!await this.storage.get(`job:${job.id}`)) { job.gone = true; return 0; }
    if (!response.ok) {
      const message = body?.message || `The cloud model refused (HTTP ${response.status}).`;
      // no Pro, the day's allowance spent, a bad request: waiting will not help
      if ([400, 401, 402, 403, 429].includes(response.status)) {
        stop(job, message);
        return 0;
      }
      job.failures += 1;
      job.error = message;
      return RETRY_SECONDS;
    }
    const reply = String(body?.choices?.[0]?.message?.content || '').replace(/<think>[\s\S]*?<\/think>/g, '').trim();
    // which models wrote it, so the check is made by another
    if (typeof body?.source === 'string' && !(job.writers || []).includes(body.source)) {
      job.writers = [...(job.writers || []), body.source].slice(-6);
    }

    const seen = new Set(keys.map(k => k.same));
    const fresh = [];
    for (const item of reply ? itemsIn(reply, job) : []) {
      if (job.extract !== 'pages' && seen.has(item.same)) continue;
      seen.add(item.same);
      fresh.push(item);
      if (job.done + fresh.length >= job.count) break;
    }
    const writes = {};
    let pendCount = job.pendCount || 0, pendChars = job.pendChars || 0, unqueued = job.unqueued || 0;
    if (job.hasCheck) {
      // what the check will look at: each question or station; a textbook
      // page; a batch of card lines as one (they are short) - with the window
      // of the lecture it was written from, which is where the check looks
      const toCheck = job.extract === 'pages' ? (reply ? [{ key: String(job.replies), text: reply }] : [])
        : job.extract === 'lines' ? (fresh.length ? [{ key: 'batch:' + job.replies, text: fresh.map(f => f.text).join('\n') }] : [])
        : fresh.map(f => ({ key: f.same, text: f.check }));
      for (const item of toCheck) {
        if (pendChars + item.text.length > LIMITS.checkChars) { unqueued += 1; continue; }
        writes[`pend:${job.id}:${pendCount}`] = { ...item, source: step.source };
        pendCount += 1;
        pendChars += item.text.length;
      }
    }
    let replies = job.replies;
    if (job.mode === 'each') {
      // a page is kept even when it came back empty, so page i stays page i
      writes[`out:${job.id}:${replies}`] = reply;
      replies += 1;
    } else if (fresh.length) {
      writes[`out:${job.id}:${replies}`] = reply;
      writes[`keys:${job.id}`] = keys.concat(fresh.map(f => ({ key: f.key, same: f.same })));
      replies += 1;
    }
    if (Object.keys(writes).length) await this.storage.put(writes);
    // Only now, with everything stored, is the call a success: a write that
    // fails must count as a failure, or the same paid call would be made again
    // and again with nothing ever counting towards giving up.
    job.pendCount = pendCount;
    job.pendChars = pendChars;
    job.unqueued = unqueued;
    job.replies = replies;
    job.round += 1;
    job.failures = 0;
    job.error = null;
    if (job.mode === 'each') {
      job.done += 1;
    } else {
      job.done += fresh.length;
      job.empty = fresh.length ? 0 : job.empty + 1;
      if (job.empty >= job.patience && job.done < job.count) {
        if (job.done) stop(job, `The model found nothing new to write after ${job.done}.`, { quiet: true });
        else stop(job, 'The model wrote nothing usable from this source.');
      }
    }
    if (job.done >= job.count) { job.status = 'done'; job.partial = false; }
    return 0;
  }

  /// One item through the checker (MedVAL's prompt, the cloud checker).
  async checkStep(job) {
    const item = await this.pendItem(job, job.checked);
    if (!item) { job.status = 'done'; return 0; }
    const check = await this.storage.get(`check:${job.id}`);
    // Only the window of the lecture the item was written from is searched.
    // Reading and re-splitting the whole lecture for every item was several
    // times the CPU a free-plan invocation may use, once a lecture was long.
    let lecture;
    if (Number.isInteger(item.source) && item.source >= 0) {
      lecture = (await this.storage.get(`src:${job.id}:${item.source}`)) || '';
    } else {
      const parts = [];
      let size = 0;
      for (let i = 0; i < job.sourceCount && size < 400_000; i++) {
        const part = (await this.storage.get(`src:${job.id}:${i}`)) || '';
        parts.push(part);
        size += part.length;
      }
      lecture = parts.join('\n\n').slice(0, 400_000);
    }
    const input = nearest(lecture, item.text, check.limit);
    const prompt = check.template.split('{{OUTPUT}}').join(item.text.slice(0, check.limit / 2))
      .split('{{INPUT}}').join(input);
    const response = await chat(this.env, job.accountId,
      { model: 'cramdown-checker', messages: [{ role: 'user', content: prompt }], max_tokens: 900, temperature: 0.1,
        avoid: job.writers || [] },
      this.fetcher, { owner: job.owner, rounds: 1 });
    const body = await response.json().catch(() => ({}));
    if (!await this.storage.get(`job:${job.id}`)) { job.gone = true; return 0; }
    if (!response.ok) {
      const message = body?.message || `The checker refused (HTTP ${response.status}).`;
      if ([400, 401, 402, 403, 429].includes(response.status)) {
        // the writing stands; the app checks what is left itself
        job.status = 'done';
        job.checkError = message;
        return 0;
      }
      job.failures += 1;
      job.checkNote = message;
      return RETRY_SECONDS;
    }
    const reply = String(body?.choices?.[0]?.message?.content || '').replace(/<think>[\s\S]*?<\/think>/g, '').trim();
    // the evidence the checker was shown (evidence.js), so the app can cite
    // exactly what was looked up and nothing else
    const evidence = Array.isArray(body?.evidence) ? body.evidence.slice(0, 8) : [];
    await this.storage.put(`ver:${job.id}:${job.verCount || 0}`,
      evidence.length ? { key: item.key, reply, evidence } : { key: item.key, reply });
    job.verCount = (job.verCount || 0) + 1;
    job.checked += 1;
    job.failures = 0;
    job.checkNote = null;
    if (job.checked >= job.checkTotal) {
      job.status = 'done';
      if (job.unqueued) job.checkError = `${job.unqueued} item(s) were too many to check here; the app checks them.`;
    }
    return 0;
  }

  /// Item n of the check queue. A job made before the queue was stored item
  /// by item (pendCount unset) still has it as one list.
  async pendItem(job, n) {
    if (job.pendCount === undefined) return ((await this.storage.get(`pend:${job.id}`)) || [])[n];
    return n < job.pendCount ? this.storage.get(`pend:${job.id}:${n}`) : undefined;
  }

  async verdicts(job) {
    if (job.verCount === undefined) return (await this.storage.get(`ver:${job.id}`)) || [];
    const out = [];
    for (let i = 0; i < job.verCount; i++) {
      const verdict = await this.storage.get(`ver:${job.id}:${i}`);
      if (verdict) out.push(verdict);
    }
    return out;
  }

  async outputs(job) {
    const out = [];
    for (let i = 0; i < job.replies; i++) out.push((await this.storage.get(`out:${job.id}:${i}`)) || '');
    return out;
  }

  async all() {
    const map = await this.storage.list({ prefix: 'job:' });
    return [...map.values()];
  }

  async summaries() {
    return (await this.all()).sort((a, b) => b.created - a.created).map(summary);
  }

  /// Drops what only a running job needs - its sources, prompts and queue.
  async release(job) {
    const keys = [`pend:${job.id}`, `check:${job.id}`];
    for (let i = 0; i < (job.pendCount || 0); i++) keys.push(`pend:${job.id}:${i}`);
    for (let i = 0; i < job.stepCount; i++) keys.push(`step:${job.id}:${i}`);
    for (let i = 0; i < job.sourceCount; i++) keys.push(`src:${job.id}:${i}`);
    for (let i = 0; i < keys.length; i += 100) await this.storage.delete(keys.slice(i, i + 100));
  }

  async forget(job) {
    const keys = [`job:${job.id}`, `keys:${job.id}`, `pend:${job.id}`, `ver:${job.id}`, `check:${job.id}`];
    for (let i = 0; i < (job.pendCount || 0); i++) keys.push(`pend:${job.id}:${i}`);
    for (let i = 0; i < (job.verCount || 0); i++) keys.push(`ver:${job.id}:${i}`);
    for (let i = 0; i < job.stepCount; i++) keys.push(`step:${job.id}:${i}`);
    for (let i = 0; i < job.sourceCount; i++) keys.push(`src:${job.id}:${i}`);
    for (let i = 0; i < job.replies; i++) keys.push(`out:${job.id}:${i}`);
    for (let i = 0; i < keys.length; i += 100) await this.storage.delete(keys.slice(i, i + 100));
  }
}

/// Ends the writing early, for a reason. With something written the job is
/// "done" - the app collects what there is - but marked partial with the
/// reason, so the app can say "36 of 80: today's cloud allowance is used"
/// instead of presenting a short set as the whole one.
function stop(job, reason, { quiet = false } = {}) {
  job.status = job.done > 0 ? 'done' : 'failed';
  job.partial = job.done > 0 && job.done < job.count;
  job.reason = reason;
  if (!quiet || !job.done) job.error = reason;
}

function summary(job) {
  const { id, title, status, done, count, error, created, updated, phase, checked, checkTotal, checkError } = job;
  return {
    id, title, status, done, total: count, error, created, updated,
    phase: phase || 'writing', checked: checked || 0, checkTotal: checkTotal || 0, checkError: checkError || null,
    // written short of what was asked, and why (the app shows it; older
    // builds ignore both)
    partial: !!job.partial, reason: job.partial ? job.reason || error || null : null,
  };
}
