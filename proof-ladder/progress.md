# The proof ladder

Updated 2026-11-04T12:04:52.793Z. Live Worker, every item checked once, half with a distractor keyed (a Verified distractor is an error).

| checked | Verified | errors among Verified | proven accuracy of Verified (95%, one-sided) |
|---|---|---|---|
| 3060 | 0 | 0 | n/a |

| rung | Verified needed with no error | status |
|---|---|---|
| 99.9% | 2,995 | climbing: 2,995 more Verified |
| 99.99% | 29,956 | waiting |
| 99.999% | 299,572 | waiting |

Verified per check so far: 0.00%. Flagged 673, Check this 2387, not checked 0.

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
| 2026-11-03 | 60 | 0 | 0 |
| 2026-11-04 | 60 | 0 | 0 |

The cloud checker this month (2026-11): $2.58 of the $40 cap at the end of the last run, $0.33 of it during that run.

Runner voters, every blind answer for the items sent (a runner holds a seat only at 80% or more by the lower bound, on 200 or more):

| runner | answered | right | right, 95% lower bound | seated |
|---|---|---|---|---|
| granite-4.0-h-tiny | 3013 | 1747 | 56.4811% | no |
| phi-4-mini-instruct | 1927 | 1107 | 55.5608% | no |

Why items were not Verified (each reason counted once per item):

| reason | items |
|---|---|
| Not yet passed by three model families. | 1604 |
| No official source states it word for word yet. | 1460 |
| Checkers from 2 different model families, solving it without the key, chose another answer. | 862 |
| Fewer than three independent blind solves reached the key. | 815 |
| The checkers judged it likely wrong. | 788 |
| A dose, diagnosis or treatment no official source states word for word yet. | 642 |
| The checkers were not confident enough. | 621 |
| Checkers from 3 different model families, solving it without the key, chose another answer. | 345 |

Each family's blind answers against the gold key (one witness per family per question; "runner": run on GitHub's CPU with no key):

| family | answered | right | right, 95% lower bound |
|---|---|---|---|
| anthropic | 3060 | 2764 | 89.4027% |
| google | 2785 | 2396 | 84.9058% |
| ibm (runner) | 584 | 327 | 52.5119% |
| openai | 469 | 398 | 81.8693% |
| nvidia | 448 | 370 | 79.3725% |
| microsoft (runner) | 12 | 5 | 18.1025% |

Today: 60 sent; stopped at the ladder's half of the Workers AI pool (15 batches).
