// Which GitHub Models check in the bench: one model from each family, the
// strongest the catalog offers first, so every vote is a separate witness
// (two models of one family share their training and their mistakes).
// Prints "voters=github:a,github:b,..." for $GITHUB_OUTPUT. An explicit list
// (second argument) wins.
import { readFileSync } from 'node:fs';

const PREFERRED = [
  ['openai', ['openai/gpt-4.1', 'openai/gpt-4o', 'openai/gpt-4.1-mini', 'openai/gpt-4o-mini']],
  ['deepseek', ['deepseek/DeepSeek-V3-0324', 'deepseek/DeepSeek-V3']],
  ['meta', ['meta/Llama-4-Maverick-17B-128E-Instruct-FP8', 'meta/Llama-3.3-70B-Instruct', 'meta/Meta-Llama-3.1-405B-Instruct', 'meta/Llama-4-Scout-17B-16E-Instruct']],
  ['mistral', ['mistral-ai/mistral-medium-2505', 'mistral-ai/Mistral-Large-2411', 'mistral-ai/mistral-small-2503']],
  ['microsoft', ['microsoft/Phi-4', 'microsoft/Phi-4-mini-instruct']],
  ['cohere', ['cohere/cohere-command-a']],
];

const [catalogFile, explicit] = process.argv.slice(2);
if (explicit && explicit.trim()) {
  console.log(`voters=${explicit.trim()}`);
} else {
  let ids = [];
  try { ids = JSON.parse(readFileSync(catalogFile, 'utf8')).map(m => m.id); } catch { ids = []; }
  const has = id => !ids.length || ids.some(x => x.toLowerCase() === id.toLowerCase());
  const chosen = PREFERRED.map(([, models]) => models.find(has)).filter(Boolean).slice(0, 5);
  console.error(`catalog: ${ids.length} models; chosen: ${chosen.join(', ')}`);
  console.log(`voters=${chosen.map(m => `github:${m}`).join(',')}`);
}
