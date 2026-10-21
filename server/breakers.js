// Circuit breakers on the model chain's providers (plan Task 5c step 3).
//
// Without them, a provider that is down is asked again by every request: a
// Gemini model that is "overloaded", or a host that accepts the connection and
// never answers, costs each request up to two minutes (UPSTREAM_TIMEOUT_MS in
// ai.js) before the next source is tried - and a background job's alarm the
// same. With them, a provider that keeps failing is skipped for a while, and
// the chain goes straight to the next one.
//
// One breaker per lane: a provider and the model asked of it
// ("gemini:gemini-3.5-flash", "workers-ai:@cf/nvidia/nemotron-3-120b-a12b",
// "anthropic:claude-opus-5-5", "openai:baichuan/baichuan-m2-32b"). Google's
// free models fail one at a time - a preview model overloaded while
// Flash-Lite and Gemma answer - so each has its own.
//
//   closed     calls go through. A failure is counted: no answer in time, the
//              host unreachable, or a 5xx. FAILURES of them inside WINDOW
//              seconds open the breaker.
//   open       the lane is skipped - no call, no wait, nothing spent - for
//              COOLDOWN seconds.
//   half-open  the cooldown is over: exactly one call goes through, as a
//              trial. Any answer that is not a 5xx closes the breaker (a 429
//              or a refusal still means the provider is up); a failure opens
//              it for another cooldown.
//
// The numbers are server configuration (wrangler.toml [vars]):
// STETHOSCORE_BREAKER_FAILURES, STETHOSCORE_BREAKER_WINDOW_SECONDS and
// STETHOSCORE_BREAKER_COOLDOWN_SECONDS, read on every call.
//
// The state lives in this isolate's memory, deliberately. Each Workers isolate
// (and the jobs Durable Object's) learns on its own, and a new isolate starts
// with every breaker closed - at worst it pays for a provider's failures a few
// times more before it too skips it. Nothing is written to D1 per call, so the
// breakers cost nothing on the free plan and cannot fail with the database.

const DEFAULTS = { failures: 3, windowSeconds: 120, cooldownSeconds: 60 };
/// A trial that never reported back (its request was cancelled or the isolate
/// went away mid-call) stops blocking the next one after this long: longer
/// than any call may take (AUDIO_TIMEOUT_MS in ai.js is four minutes).
const TRIAL_LOST_MS = 5 * 60_000;

const whole = (value, fallback, least) => {
  const n = Math.floor(Number(value));
  return value !== undefined && value !== '' && Number.isFinite(n) && n >= least ? n : fallback;
};

export function breakerSettings(env = {}) {
  return {
    failures: whole(env.STETHOSCORE_BREAKER_FAILURES, DEFAULTS.failures, 1),
    windowSeconds: whole(env.STETHOSCORE_BREAKER_WINDOW_SECONDS, DEFAULTS.windowSeconds, 1),
    cooldownSeconds: whole(env.STETHOSCORE_BREAKER_COOLDOWN_SECONDS, DEFAULTS.cooldownSeconds, 1),
  };
}

/// Whether an answer counts against its provider: it is down or sick
/// (a 5xx, or 408 - it gave up waiting). A 429 is a quota, handled where it
/// happens (ai.js dayOut, retryDelay); a 4xx is about the request.
export const failed = status => status >= 500 || status === 408;

export class Breakers {
  constructor(clock = () => Date.now()) {
    this.clock = clock;
    this.lanes = new Map();
  }

  lane(name) {
    let lane = this.lanes.get(name);
    if (!lane) {
      lane = { state: 'closed', failures: [], openedAt: 0, trialAt: 0, opened: 0 };
      this.lanes.set(name, lane);
    }
    return lane;
  }

  /// Whether a call on this lane may go now. Past an open breaker's cooldown
  /// it half-opens and this call is its one trial, so the caller must report
  /// back (success or failure), or give the trial up (release) if it ends up
  /// not calling after all.
  allow(env, name) {
    const lane = this.lanes.get(name);
    if (!lane || lane.state === 'closed') return true;
    const now = this.clock();
    if (lane.state === 'open') {
      if (now - lane.openedAt < breakerSettings(env).cooldownSeconds * 1000) return false;
      lane.state = 'half-open';
      lane.trialAt = now;
      return true;
    }
    if (lane.trialAt && now - lane.trialAt < TRIAL_LOST_MS) return false;
    lane.trialAt = now;
    return true;
  }

  /// What allow() would answer, without taking a trial: true while the lane
  /// would be skipped.
  resting(env, name) {
    const lane = this.lanes.get(name);
    if (!lane || lane.state === 'closed') return false;
    const now = this.clock();
    if (lane.state === 'open') return now - lane.openedAt < breakerSettings(env).cooldownSeconds * 1000;
    return !!lane.trialAt && now - lane.trialAt < TRIAL_LOST_MS;
  }

  /// A trial taken by allow() and not used (the call was not made after all):
  /// the next request may make it.
  release(name) {
    const lane = this.lanes.get(name);
    if (lane?.state === 'half-open') lane.trialAt = 0;
  }

  /// The provider answered. An open or half-open breaker closes: the provider
  /// is back.
  success(env, name) {
    const lane = this.lanes.get(name);
    if (!lane || lane.state === 'closed') return;
    lane.state = 'closed';
    lane.failures = [];
    lane.trialAt = 0;
  }

  /// The provider failed this call.
  failure(env, name) {
    const lane = this.lane(name);
    const now = this.clock();
    const settings = breakerSettings(env);
    // a call that went out before the breaker opened, failing late: the
    // cooldown already running is not started over
    if (lane.state === 'open') return;
    if (lane.state === 'half-open') return this.open(lane, now);
    lane.failures = lane.failures.filter(at => now - at < settings.windowSeconds * 1000);
    lane.failures.push(now);
    if (lane.failures.length >= settings.failures) this.open(lane, now);
  }

  open(lane, now) {
    lane.state = 'open';
    lane.openedAt = now;
    lane.failures = [];
    lane.trialAt = 0;
    lane.opened += 1;
  }

  /// Whole seconds until the soonest of these lanes may be tried again
  /// (at least 1), for a Retry-After.
  retryAfter(env, names) {
    const cooldown = breakerSettings(env).cooldownSeconds * 1000;
    const now = this.clock();
    let soonest = Infinity;
    for (const name of names) {
      const lane = this.lanes.get(name);
      if (!lane || lane.state === 'closed') return 1;
      const at = lane.state === 'open' ? lane.openedAt + cooldown : lane.trialAt + TRIAL_LOST_MS;
      soonest = Math.min(soonest, at - now);
    }
    return Number.isFinite(soonest) ? Math.max(1, Math.ceil(soonest / 1000)) : 1;
  }

  /// Every lane this isolate has seen fail, for the owner's diagnostics
  /// (read-only; GET /diagnostics/summary).
  snapshot(env) {
    const settings = breakerSettings(env);
    const now = this.clock();
    const lanes = {};
    for (const [name, lane] of [...this.lanes].sort(([a], [b]) => a.localeCompare(b))) {
      const recent = lane.failures.filter(at => now - at < settings.windowSeconds * 1000).length;
      lanes[name] = {
        state: lane.state === 'open' && !this.resting(env, name) ? 'half-open' : lane.state,
        recentFailures: recent,
        timesOpened: lane.opened,
        ...(lane.state === 'open' ? { retryInSeconds: Math.max(0, Math.ceil((lane.openedAt + settings.cooldownSeconds * 1000 - now) / 1000)) } : {}),
      };
    }
    return { scope: 'isolate', settings, lanes };
  }
}

/// The breakers of this isolate, shared by every request it serves.
export const breakers = new Breakers();

/// Tests only: every breaker closed, and the clock they read.
export function resetBreakers(clock = () => Date.now()) {
  breakers.clock = clock;
  breakers.lanes.clear();
}
