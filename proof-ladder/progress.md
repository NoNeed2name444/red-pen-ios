# The proof ladder

Updated 2026-10-22T10:07:34.739Z. Live Worker, every item checked once, half with a distractor keyed (a Verified distractor is an error).

| checked | Verified | errors among Verified | proven accuracy of Verified (95%, one-sided) |
|---|---|---|---|
| 1860 | 0 | 0 | n/a |

| rung | Verified needed with no error | status |
|---|---|---|
| 99.9% | 2,995 | climbing: 2,995 more Verified |
| 99.99% | 29,956 | waiting |
| 99.999% | 299,572 | waiting |

Verified per check so far: 0.00%. Flagged 346, Check this 1514, not checked 0.

| day | checked | Verified | errors |
|---|---|---|---|
| 2026-10-14 | 600 | 0 | 0 |
| 2026-10-15 | 660 | 0 | 0 |
| 2026-10-22 | 600 | 0 | 0 |

The cloud checker this month (2026-10): $12.79 of the $40 cap at the end of the last run, $3.78 of it during that run.

Runner voters, every blind answer for the items sent (a runner holds a seat only at 80% or more by the lower bound, on 200 or more):

| runner | answered | right | right, 95% lower bound | seated |
|---|---|---|---|---|
| granite-4.0-h-tiny | 1822 | 1045 | 55.4135% | no |
| phi-4-mini-instruct | 1007 | 590 | 55.9708% | no |

Why items were not Verified (each reason counted once per item):

| reason | items |
|---|---|
| Not yet passed by three model families. | 1029 |
| No official source states it word for word yet. | 762 |
| The checkers were not confident enough. | 574 |
| Checkers from 2 different model families, solving it without the key, chose another answer. | 536 |
| Fewer than three independent blind solves reached the key. | 523 |
| A dose, diagnosis or treatment no official source states word for word yet. | 326 |
| The checkers judged it likely wrong. | 187 |
| It cannot be read into statements a source could prove word for word. | 122 |

Each family's blind answers against the gold key (one witness per family per question; "runner": run on GitHub's CPU with no key):

| family | answered | right | right, 95% lower bound |
|---|---|---|---|
| anthropic | 1860 | 1696 | 90.0257% |
| google | 1781 | 1546 | 85.4130% |
| ibm (runner) | 584 | 327 | 52.5119% |
| nvidia | 84 | 73 | 79.2563% |
| openai | 68 | 62 | 83.3264% |
| microsoft (runner) | 12 | 5 | 18.1025% |

Today: 600 sent; stopped at the day's questions, all sent.
