# CramDown Cloud medical accuracy benchmark

2026-09-25T13:08 UTC · 5 MedQA (USMLE) test questions, seed 20260923 · evidence from Europe PMC, MedlinePlus and openFDA on every call.

Models that answered: gemini-3.5-flash-lite ×4, gemma-4-31b-it ×1.

## The number that matters

**Accuracy of the answers a student would see** (answered, then passed by the grounded checker): 100.0% (3/3; 95% CI 43.8%–100.0%)

Target 98.0%: **NOT PROVEN — measured at or above 98.0%, but the sample is too small to be sure; run with a larger N**

Answers withheld by the checker: 2 of 5 (40.0%).

## Each part

| Measurement | Result |
|---|---|
| Answering with evidence (raw) | 80.0% (4/5; 95% CI 37.6%–96.4%) |
| Checker passes a correct answer (specificity) | 100.0% (4/4; 95% CI 51.0%–100.0%) |
| Checker flags a wrong answer against a correct lecture | 66.7% (2/3; 95% CI 20.8%–93.9%) |
| Checker flags a wrong answer the lecture also states (evidence only) | 66.7% (2/3; 95% CI 20.8%–93.9%) |
| Questions with official-source evidence found | 5/5 |
| Calls that failed | 7 |

## Wrong answers that got through

_None._

## Free limit met

The run stopped early at a daily free limit, so fewer questions were scored: 502: Provider 429: gemini 429: gemma-4-31b-it: Gemini Developer API is overloaded. Please try again later. | workers-ai 429: Workers AI: this account's share of today's free allowance is used.

## Errors

- 502: Provider 429: gemini 429: gemma-4-31b-it: Gemini Developer API is overloaded. Please try again later. | workers-ai 429: Workers AI: this account's share of today's free allowance is used.
- 502: Provider 429: gemini 429: gemma-4-31b-it: You exceeded your current quota, please check your plan and billing details. For more information on this error, head to: https://ai.google.dev/gemini-ap
- skipped: 502: Provider 429: gemini 429: gemma-4-31b-it: Gemini Developer API is overloaded. Please try again later. | workers-ai 429: Workers AI: this account's share of today's free allowance is used.
