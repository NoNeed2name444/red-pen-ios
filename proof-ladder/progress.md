# The proof ladder

Updated 2026-10-31T10:08:15.525Z. Live Worker, every item checked once, half with a distractor keyed (a Verified distractor is an error).

| checked | Verified | errors among Verified | proven accuracy of Verified (95%, one-sided) |
|---|---|---|---|
| 2940 | 0 | 0 | n/a |

| rung | Verified needed with no error | status |
|---|---|---|
| 99.9% | 2,995 | climbing: 2,995 more Verified |
| 99.99% | 29,956 | waiting |
| 99.999% | 299,572 | waiting |

Verified per check so far: 0.00%. Flagged 610, Check this 2330, not checked 0.

| day | checked | Verified | errors |
|---|---|---|---|
| 2026-10-14 | 600 | 0 | 0 |
| 2026-10-15 | 660 | 0 | 0 |
| 2026-10-22 | 600 | 0 | 0 |
| 2026-10-23 | 60 | 0 | 0 |
| 2026-10-24 | 60 | 0 | 0 |
| 2026-10-25 | 600 | 0 | 0 |
| 2026-10-26 | 60 | 0 | 0 |
| 2026-10-27 | 60 | 0 | 0 |
| 2026-10-28 | 60 | 0 | 0 |
| 2026-10-29 | 60 | 0 | 0 |
| 2026-10-30 | 60 | 0 | 0 |
| 2026-10-31 | 60 | 0 | 0 |

The cloud checker this month (2026-10): $20.94 of the $40 cap at the end of the last run, $0.37 of it during that run.

Runner voters, every blind answer for the items sent (a runner holds a seat only at 80% or more by the lower bound, on 200 or more):

| runner | answered | right | right, 95% lower bound | seated |
|---|---|---|---|---|
| granite-4.0-h-tiny | 2893 | 1672 | 56.2617% | no |
| phi-4-mini-instruct | 1839 | 1056 | 55.4910% | no |

Why items were not Verified (each reason counted once per item):

| reason | items |
|---|---|
| Not yet passed by three model families. | 1601 |
| No official source states it word for word yet. | 1386 |
| Checkers from 2 different model families, solving it without the key, chose another answer. | 847 |
| Fewer than three independent blind solves reached the key. | 815 |
| The checkers judged it likely wrong. | 715 |
| The checkers were not confident enough. | 620 |
| A dose, diagnosis or treatment no official source states word for word yet. | 615 |
| Checkers from 3 different model families, solving it without the key, chose another answer. | 286 |

Each family's blind answers against the gold key (one witness per family per question; "runner": run on GitHub's CPU with no key):

| family | answered | right | right, 95% lower bound |
|---|---|---|---|
| anthropic | 2940 | 2659 | 89.5032% |
| google | 2785 | 2396 | 84.9058% |
| ibm (runner) | 584 | 327 | 52.5119% |
| openai | 351 | 302 | 82.6272% |
| nvidia | 328 | 271 | 78.8112% |
| microsoft (runner) | 12 | 5 | 18.1025% |

Today: 60 sent; stopped at the ladder's half of the Workers AI pool (15 batches).
