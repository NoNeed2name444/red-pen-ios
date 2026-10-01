// Kill switches: any AI feature switched off from the server's configuration,
// with no code changed (plan Task 5c step 3).
//
// STETHOSCORE_OFF in wrangler.toml [vars] names the features that are off,
// comma-separated ("tts,transcribe"), or "all". It is read on every request,
// so the change takes effect the moment the variable does: edited in the
// Cloudflare dashboard (the redpen-auth worker > Settings > Variables and
// Secrets), which changes no code; or in wrangler.toml, which the next run of
// the deploy workflow applies - and which that run also puts back over a
// dashboard edit, so a switch meant to stay off belongs in wrangler.toml too.
//
// A switched-off feature is refused before anything is read, signed in,
// spent or queued, with a JSON message the app shows as it is (`off` names
// the feature) and Retry-After. Nothing a student has is lost: collecting
// and cancelling background jobs still work, a running job waits (jobs.js),
// and an item that cannot be checked stays Unverified.

/// The features, the status each is refused with and what the student reads.
/// The status is chosen by what the app already does with it:
///   503  AuthAPI and the cloud model clients (LLMError, CloudJobs) show the
///        message; the accuracy store keeps the items Unverified and tries
///        again later (a 429 there would block checking until midnight and
///        say the day's checks are used).
///   429  CloudTranscriber shows the message only for a 429 (a 503 reads as
///        "isn't set up"); CloudVoice leaves the server alone for an hour and
///        reads with the phone's own voice (after a 503 it asks again every
///        two minutes, logging each one).
export const FEATURES = {
  write: {
    status: 503,
    message: 'Writing with the cloud models is switched off for now. On-device models still work; try the cloud again later.',
  },
  check: {
    status: 503,
    message: 'The cloud accuracy check is switched off for now. Items stay Unverified until it is back.',
  },
  jobs: {
    status: 503,
    message: 'Background writing in the cloud is switched off for now. Nothing was queued; on-device models still work.',
  },
  accuracy: {
    status: 503,
    message: 'The accuracy check is switched off for now. Items stay Unverified until it is back.',
  },
  transcribe: {
    status: 429,
    message: 'Cloud transcription is switched off for now. This phone can still transcribe.',
  },
  tts: {
    status: 429,
    message: "The natural voice is switched off for now; the phone's own voice reads instead.",
  },
};

/// How long the app is told to wait before asking again.
const RETRY_AFTER_SECONDS = 600;

/// What STETHOSCORE_OFF says: the features that are off, and any name it
/// gives that is not a feature (a typo, shown in the diagnostics so it is
/// not mistaken for a switch that works).
export function switchedOff(env = {}) {
  const off = new Set();
  const unknown = [];
  for (const name of String(env.STETHOSCORE_OFF || '').toLowerCase().split(/[\s,]+/).filter(Boolean)) {
    if (name === 'all') Object.keys(FEATURES).forEach(f => off.add(f));
    else if (FEATURES[name]) off.add(name);
    else if (!unknown.includes(name)) unknown.push(name);
  }
  return { off, unknown };
}

export const isOff = (env, feature) => switchedOff(env).off.has(feature);

/// The refusal for a switched-off feature.
export function refusal(feature) {
  const { status, message } = FEATURES[feature];
  return new Response(JSON.stringify({ error: message, message, off: feature }), {
    status, headers: { 'content-type': 'application/json', 'retry-after': String(RETRY_AFTER_SECONDS) },
  });
}

/// The refusal for the first of these features that is off, or null.
export function refuseIfOff(env, ...features) {
  const { off } = switchedOff(env);
  const hit = features.find(f => off.has(f));
  return hit ? refusal(hit) : null;
}

/// The features a request uses, from its path alone - so it is refused before
/// its body is read. A new background job writes first (jobs and write);
/// collecting or cancelling one is never refused. The cloud models'
/// endpoint depends on the model asked for (featureOfModel).
export function featuresOf(path, method) {
  if ((path === '/jobs' || path === '/jobs/') && method === 'POST') return ['jobs', 'write'];
  switch (path) {
    case '/accuracy/check': return ['accuracy'];
    case '/transcribe/chunk': return ['transcribe'];
    case '/tts': return ['tts'];
    default: return [];
  }
}

/// The feature a /v1/chat/completions model name belongs to: the writers
/// write, the checkers check (and an unknown name is refused later anyway).
export function featureOfModel(model) {
  if (model === 'cramdown-writer' || model === 'cramdown-doctor') return 'write';
  if (model === 'cramdown-checker' || model === 'cramdown-medval') return 'check';
  return null;
}

/// Every feature on or off, for the owner's diagnostics (read-only).
export function switchStates(env) {
  const { off, unknown } = switchedOff(env);
  return {
    features: Object.fromEntries(Object.keys(FEATURES).map(f => [f, off.has(f) ? 'off' : 'on'])),
    ...(unknown.length ? { unknown } : {}),
  };
}
