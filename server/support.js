// "Contact us": a message from a signed-in student to whoever runs the app.
//
// Kept in D1 for the owner to read (POST /support/messages with the owner
// key), removed with the account. Free, so any signed-in account may write,
// but only a few a day: this is a way to reach a person, not a pipe.
//
// Routes (worker.js):
//   POST /support/message   { topic, message, version? }   signed in
//   POST /support/messages  { limit? }                     owner key

import { spend } from './ai.js';

export const TOPICS = ['problem', 'idea', 'account', 'other'];
export const MAX_MESSAGE = 4000;
export const DAILY = 10;

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json' },
});
const fail = (status, message) => json({ error: message, message }, status);
const str = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

/// POST /support/message
export async function supportMessage(env, account, body) {
  const message = str(body?.message, MAX_MESSAGE);
  if (message.length < 3) return fail(400, 'Write a few words first.');
  const topic = TOPICS.includes(body?.topic) ? body.topic : 'other';
  const version = str(body?.version, 40);
  if (!await spend(env, `support:${account}`, Number(env.SUPPORT_DAILY) || DAILY)) {
    return fail(429, "That's today's messages sent. We'll read them - try again tomorrow.");
  }
  const at = Math.floor(Date.now() / 1000);
  const row = await env.DB.prepare(
    'INSERT INTO support_messages (account_id, topic, message, version, created_at) VALUES (?, ?, ?, ?, ?) RETURNING id')
    .bind(account, topic, message, version, at).first();
  return json({ ok: true, id: row?.id ?? null });
}

/// POST /support/messages (owner key): the newest first.
export async function listSupportMessages(env, body) {
  const limit = Math.min(Math.max(Number(body?.limit) || 100, 1), 500);
  const rows = (await env.DB.prepare(
    'SELECT id, account_id, topic, message, version, created_at FROM support_messages ORDER BY id DESC LIMIT ?')
    .bind(limit).all()).results || [];
  return json({ messages: rows });
}

/// With the account.
export async function forgetSupport(env, account) {
  await env.DB.prepare('DELETE FROM support_messages WHERE account_id = ?').bind(account).run();
}
