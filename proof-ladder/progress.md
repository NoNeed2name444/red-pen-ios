# The proof ladder

Updated 2026-10-15T02:08:32.416Z. Live Worker, every item checked once, half with a distractor keyed (a Verified distractor is an error).

| checked | Verified | errors among Verified | proven accuracy of Verified (95%, one-sided) |
|---|---|---|---|
| 660 | 0 | 0 | n/a |

| rung | Verified needed with no error | status |
|---|---|---|
| 99.9% | 2,995 | climbing: 2,995 more Verified |
| 99.99% | 29,956 | waiting |
| 99.999% | 299,572 | waiting |

Verified per check so far: 0.00%. Flagged 214, Check this 446, not checked 0.

| day | checked | Verified | errors |
|---|---|---|---|
| 2026-10-14 | 600 | 0 | 0 |
| 2026-10-15 | 60 | 0 | 0 |

The cloud checker this month (2026-10): $5.42 of the $90 cap at the end of the last run, $0.34 of it during that run.

Runner voters, every blind answer for the items sent (a runner holds a seat only at 80% or more by the lower bound, on 200 or more):

| runner | answered | right | right, 95% lower bound | seated |
|---|---|---|---|---|
| granite-4.0-h-tiny | 641 | 360 | 52.8444% | no |
| phi-4-mini-instruct | 51 | 31 | 48.3072% | no |

Why items were not Verified (each reason counted once per item):

| reason | items |
|---|---|
| No official source states it word for word yet. | 35 |
| Checkers from 3 different model families, solving it without the key, chose another answer. | 32 |
| The checkers were not confident enough. | 32 |
| A dose, diagnosis or treatment no official source states word for word yet. | 18 |
| A safety rule failed. | 7 |
| The checkers judged it likely wrong. | 7 |
| Checkers from 2 different model families, solving it without the key, chose another answer. | 6 |
| It cannot be read into statements a source could prove word for word. | 4 |

Each family's blind answers against the gold key (one witness per family per question; "runner": run on GitHub's CPU with no key):

| family | answered | right | right, 95% lower bound |
|---|---|---|---|
| anthropic | 660 | 593 | 87.7043% |
| google | 653 | 558 | 82.9866% |
| ibm (runner) | 584 | 327 | 52.5119% |
| nvidia | 40 | 32 | 66.7972% |
| openai | 24 | 21 | 70.7727% |
| microsoft (runner) | 12 | 5 | 18.1025% |

Today: 60 sent; stopped at the ladder's half of the Workers AI pool (15 batches).
