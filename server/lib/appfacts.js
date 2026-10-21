// Facts the worker learns about the app on the App Store (plan R6): the
// Apple team id (for the apple-app-site-association file) and the App Store
// id (for links). Kept in app_facts so no redeploy is needed when they become
// known; env vars win when set.

const nowSeconds = () => Math.floor(Date.now() / 1000);
const LOOKUP_EVERY = 3600;

export async function getFact(env, key) {
  try {
    const row = await env.DB.prepare('SELECT value, updated_at FROM app_facts WHERE key = ?').bind(key).first();
    return row || null;
  } catch { return null; }
}

export async function setFact(env, key, value, clock = nowSeconds) {
  await env.DB.prepare(
    `INSERT INTO app_facts (key, value, updated_at) VALUES (?, ?, ?)
     ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`)
    .bind(key, String(value), clock()).run();
}

/// The team id: the apple_team_id fact, then env APPLE_TEAM_ID, else null.
export async function teamId(env) {
  const fact = await getFact(env, 'apple_team_id');
  const value = (fact && fact.value) || env.APPLE_TEAM_ID || '';
  return /^[A-Z0-9]{10}$/.test(value) ? value : null;
}

/// The App Store id: env APPLE_APP_ID, then the app_store_id fact, then
/// Apple's public iTunes lookup by bundle id - asked at most once an hour
/// (app_store_lookup_at), since before release the app is simply not there.
export async function appStoreId(env, fetcher = fetch, clock = nowSeconds) {
  if (/^\d{6,12}$/.test(env.APPLE_APP_ID || '')) return env.APPLE_APP_ID;
  const known = await getFact(env, 'app_store_id');
  if (known && /^\d{6,12}$/.test(known.value)) return known.value;
  const bundle = env.APPLE_BUNDLE_ID || '';
  if (!/^[A-Za-z0-9.-]{3,155}$/.test(bundle)) return null;
  const last = await getFact(env, 'app_store_lookup_at');
  if (last && clock() - Number(last.value || 0) < LOOKUP_EVERY) return null;
  try { await setFact(env, 'app_store_lookup_at', clock(), clock); } catch { return null; }
  try {
    const response = await fetcher(`https://itunes.apple.com/lookup?bundleId=${encodeURIComponent(bundle)}`);
    if (!response.ok) return null;
    const answer = await response.json();
    const id = answer && Array.isArray(answer.results) && answer.results[0] ? String(answer.results[0].trackId || '') : '';
    if (!/^\d{6,12}$/.test(id)) return null;
    await setFact(env, 'app_store_id', id, clock);
    return id;
  } catch { return null; }
}
