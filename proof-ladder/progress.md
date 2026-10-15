# The proof ladder

Updated 2026-10-15T07:46:26.035Z. Live Worker, every item checked once, half with a distractor keyed (a Verified distractor is an error).

| checked | Verified | errors among Verified | proven accuracy of Verified (95%, one-sided) |
|---|---|---|---|
| 1260 | 0 | 0 | n/a |

| rung | Verified needed with no error | status |
|---|---|---|
| 99.9% | 2,995 | climbing: 2,995 more Verified |
| 99.99% | 29,956 | waiting |
| 99.999% | 299,572 | waiting |

Verified per check so far: 0.00%. Flagged 292, Check this 968, not checked 0.

| day | checked | Verified | errors |
|---|---|---|---|
| 2026-10-14 | 600 | 0 | 0 |
| 2026-10-15 | 660 | 0 | 0 |

The cloud checker this month (2026-10): $9.02 of the $90 cap at the end of the last run, $3.94 of it during that run.

Runner voters, every blind answer for the items sent (a runner holds a seat only at 80% or more by the lower bound, on 200 or more):

| runner | answered | right | right, 95% lower bound | seated |
|---|---|---|---|---|
| granite-4.0-h-tiny | 1229 | 708 | 55.2368% | no |
| phi-4-mini-instruct | 520 | 312 | 56.3343% | no |

Why items were not Verified (each reason counted once per item):

| reason | items |
|---|---|
| Not yet passed by three model families. | 502 |
| No official source states it word for word yet. | 382 |
| The checkers were not confident enough. | 300 |
| Checkers from 2 different model families, solving it without the key, chose another answer. | 268 |
| Fewer than three independent blind solves reached the key. | 258 |
| A dose, diagnosis or treatment no official source states word for word yet. | 181 |
| The checkers judged it likely wrong. | 103 |
| It cannot be read into statements a source could prove word for word. | 66 |

Each family's blind answers against the gold key (one witness per family per question; "runner": run on GitHub's CPU with no key):

| family | answered | right | right, 95% lower bound |
|---|---|---|---|
| anthropic | 1260 | 1147 | 89.5958% |
| google | 1217 | 1056 | 85.0661% |
| ibm (runner) | 584 | 327 | 52.5119% |
| nvidia | 68 | 59 | 78.0404% |
| openai | 48 | 43 | 79.3371% |
| microsoft (runner) | 12 | 5 | 18.1025% |

Today: 600 sent; stopped at the day's questions, all sent.
