// Who the owner is. One place for it (plan R5), built on what already exists:
//   - the owner key: OWNER_KEY, derived on GitHub from AI_API_KEY and baked
//     only into the owner's personal build (ai.js isOwnerKey);
//   - an owner account: accounts.owner = 1, set by the owner's claim and never
//     by a request, or an id listed in OWNER_ACCOUNT_IDS
//     (diagnostics.js isOwnerAccount).
// The existing owner-key routes (/costs, /support/messages, /accuracy/*,
// /diagnostics/summary) keep their own checks and behave exactly as before.
// Routes on the router with auth 'owner' go through ownerCaller, and anybody
// else is told the route does not exist (404), so it does not reveal itself.

import { isOwnerKey } from '../ai.js';
import { isOwnerAccount } from '../diagnostics.js';

export { isOwnerKey, isOwnerAccount };

/// Whether the request's bearer equals `key`, compared in constant time. An
/// unset or short key (under 32 characters) never matches.
export function keyMatches(request, key) {
  const want = typeof key === 'string' ? key : '';
  const given = (request.headers.get('authorization') || '').replace(/^Bearer /, '');
  if (want.length < 32 || given.length !== want.length) return false;
  let diff = 0;
  for (let i = 0; i < want.length; i++) diff |= want.charCodeAt(i) ^ given.charCodeAt(i);
  return diff === 0;
}

/// Whether an account row (already read) is the owner's, without a query.
export function rowIsOwner(env, account) {
  if (!account) return false;
  if (account.owner === 1) return true;
  const listed = (env.OWNER_ACCOUNT_IDS || '').split(',').map(s => s.trim()).filter(Boolean);
  return listed.includes(account.id);
}

/// 'owner-key' for the owner key, the account id for a signed-in owner
/// account, otherwise null. `holder(request, env)` is the worker's session
/// check (a verified, unrevoked access token's account id, or null).
export async function ownerCaller(request, env, holder) {
  if (isOwnerKey(request, env)) return 'owner-key';
  const id = holder ? await holder(request, env) : null;
  if (!id) return null;
  return await isOwnerAccount(env, id) ? id : null;
}
