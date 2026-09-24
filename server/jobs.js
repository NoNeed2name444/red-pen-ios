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
import { chat, proGate } from './ai.js';

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json' },
});
const fail = (status, message) => json({ error: message, message }, status);

export const LIMITS = {
  active: 3,              // jobs running at once, per account
  steps: 200,             // prompts in one job
  sources: 40,
  sourceChars: 1_500_000,
  promptChars: 60_000,    // a prompt's own text, before {{SOURCE}} goes in
  count: 1_000,           // items asked for
  alreadyItems: 60,
  keepDays: 7,            // a finished job nobody collected
};
const RETRY_SECONDS = 20;
const MAX_FAILURES = 4;

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
  if (sources.length > LIMITS.sources || sources.some(s => typeof s !== 'string' || s.length > LIMITS.sourceChars)) {
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
  const count = mode === 'each' ? cleanSteps.length : Math.min(Math.max(Number(raw.count) || 0, 1), LIMITS.count);
  return {
    spec: {
      title, mode, extract, count, sources, steps: cleanSteps,
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
        return {
          key: (stem.length > 90 ? stem.slice(0, 90) + '…' : stem) + `  [answer: ${String(q.options[q.correctIndex]).trim()}]`,
          same: stem.toLowerCase().replace(/\s+/g, ' '),
        };
      });
  }
  return (Array.isArray(object?.stations) ? object.stations : [])
    .filter(s => typeof s?.title === 'string' && s.title.trim())
    .map(s => ({ key: s.title.trim(), same: s.title.trim().toLowerCase() }));
}

function parseObject(text) {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try { return JSON.parse(text.slice(start, end + 1)); } catch { return null; }
}

/// A prompt ready to send: its source put in, and what has been written so far.
export function fill(text, source, already) {
  let out = text.split('{{SOURCE}}').join(source);
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
      case '/list': return json({ jobs: await this.summaries() });
      case '/get': {
        const job = await this.storage.get(`job:${id}`);
        if (!job) return fail(404, 'No such job.');
        const body = { job: summary(job) };
        if (url.searchParams.get('outputs') === '1') body.outputs = await this.outputs(job);
        return json(body);
      }
      case '/cancel': {
        const job = await this.storage.get(`job:${id}`);
        if (!job) return json({ ok: true });
        await this.forget(job);
        return json({ ok: true });
      }
      default: return fail(404, 'No such endpoint.');
    }
  }

  async create({ accountId, owner, spec }) {
    const jobs = await this.all();
    if (jobs.filter(j => j.status === 'running').length >= LIMITS.active) {
      return fail(429, `${LIMITS.active} jobs are already being written - wait for one to finish.`);
    }
    const id = crypto.randomUUID();
    const now = Date.now();
    const job = {
      id, accountId, owner: !!owner, title: spec.title, mode: spec.mode, extract: spec.extract,
      count: spec.count, minFields: spec.minFields, keyFields: spec.keyFields, cloze: spec.cloze,
      patience: spec.patience, stepCount: spec.steps.length, sourceCount: spec.sources.length,
      status: 'running', done: 0, round: 0, failures: 0, empty: 0, replies: 0,
      created: now, updated: now, error: null,
    };
    const writes = { [`job:${id}`]: job, [`keys:${id}`]: [] };
    spec.steps.forEach((step, i) => { writes[`step:${id}:${i}`] = step; });
    spec.sources.forEach((source, i) => { writes[`src:${id}:${i}`] = source; });
    // put() takes at most 128 keys at a time
    const entries = Object.entries(writes);
    for (let i = 0; i < entries.length; i += 100) await this.storage.put(Object.fromEntries(entries.slice(i, i + 100)));
    if (!await this.storage.getAlarm()) await this.storage.setAlarm(Date.now() + 50);
    return json({ job: summary(job) }, 201);
  }

  /// One model call for the oldest running job, then the next alarm.
  async alarm() {
    const jobs = await this.all();
    const expired = Date.now() - LIMITS.keepDays * 86_400_000;
    for (const old of jobs.filter(j => j.status !== 'running' && j.updated < expired)) await this.forget(old);
    const job = jobs.filter(j => j.status === 'running').sort((a, b) => a.created - b.created)[0];
    if (!job) return;
    let wait = 0;
    try {
      wait = await this.step(job);
    } catch (error) {
      console.error('job step', error);
      job.failures += 1;
      wait = RETRY_SECONDS;
    }
    if (job.status === 'running' && job.failures >= MAX_FAILURES) {
      job.status = job.done > 0 ? 'done' : 'failed';
      job.error = job.error || 'The cloud model kept failing. Try again later.';
    }
    job.updated = Date.now();
    // the job may have been cancelled while its call was out
    if (await this.storage.get(`job:${job.id}`)) await this.storage.put(`job:${job.id}`, job);
    const more = (await this.all()).some(j => j.status === 'running');
    if (more) await this.storage.setAlarm(Date.now() + wait * 1000 + 50);
  }

  /// Returns how long to wait before the next call, in seconds.
  async step(job) {
    const index = job.mode === 'each' ? job.done : job.round % job.stepCount;
    const step = await this.storage.get(`step:${job.id}:${index}`);
    const source = step.source >= 0 ? (await this.storage.get(`src:${job.id}:${step.source}`)) || '' : '';
    const keys = (await this.storage.get(`keys:${job.id}`)) || [];
    const already = keys.map(k => k.key);
    const messages = [];
    if (step.system) messages.push({ role: 'system', content: fill(step.system, source, already) });
    messages.push({ role: 'user', content: fill(step.user, source, already) });

    const response = await chat(this.env, job.accountId,
      { model: 'cramdown-writer', messages, max_tokens: step.maxTokens, temperature: step.temperature },
      this.fetcher, { owner: job.owner });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      const message = body?.message || `The cloud model refused (HTTP ${response.status}).`;
      // no Pro, the day's allowance spent, a bad request: waiting will not help
      if ([400, 401, 402, 403, 429].includes(response.status)) {
        job.status = job.done > 0 ? 'done' : 'failed';
        job.error = message;
        return 0;
      }
      job.failures += 1;
      job.error = message;
      return RETRY_SECONDS;
    }
    const reply = String(body?.choices?.[0]?.message?.content || '').replace(/<think>[\s\S]*?<\/think>/g, '').trim();
    job.round += 1;
    job.failures = 0;
    job.error = null;

    const seen = new Set(keys.map(k => k.same));
    const fresh = [];
    for (const item of reply ? itemsIn(reply, job) : []) {
      if (job.extract !== 'pages' && seen.has(item.same)) continue;
      seen.add(item.same);
      fresh.push(item);
      if (job.done + fresh.length >= job.count) break;
    }
    if (job.mode === 'each') {
      // a page is kept even when it came back empty, so page i stays page i
      await this.storage.put(`out:${job.id}:${job.replies}`, reply);
      job.replies += 1;
      job.done += 1;
    } else {
      if (fresh.length) {
        await this.storage.put({
          [`out:${job.id}:${job.replies}`]: reply,
          [`keys:${job.id}`]: keys.concat(fresh.map(f => ({ key: f.key, same: f.same }))),
        });
        job.replies += 1;
      }
      job.done += fresh.length;
      job.empty = fresh.length ? 0 : job.empty + 1;
      if (job.empty >= job.patience) {
        job.status = job.done > 0 ? 'done' : 'failed';
        if (!job.done) job.error = 'The model wrote nothing usable from this source.';
      }
    }
    if (job.done >= job.count) job.status = 'done';
    return 0;
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

  async forget(job) {
    const keys = [`job:${job.id}`, `keys:${job.id}`];
    for (let i = 0; i < job.stepCount; i++) keys.push(`step:${job.id}:${i}`);
    for (let i = 0; i < job.sourceCount; i++) keys.push(`src:${job.id}:${i}`);
    for (let i = 0; i < job.replies; i++) keys.push(`out:${job.id}:${i}`);
    for (let i = 0; i < keys.length; i += 100) await this.storage.delete(keys.slice(i, i + 100));
  }
}

function summary(job) {
  const { id, title, status, done, count, error, created, updated } = job;
  return { id, title, status, done, total: count, error, created, updated };
}
