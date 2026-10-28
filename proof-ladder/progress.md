# The proof ladder

Updated 2026-10-28T10:31:38.161Z. Live Worker, every item checked once, half with a distractor keyed (a Verified distractor is an error).

| checked | Verified | errors among Verified | proven accuracy of Verified (95%, one-sided) |
|---|---|---|---|
| 2760 | 0 | 0 | n/a |

| rung | Verified needed with no error | status |
|---|---|---|
| 99.9% | 2,995 | climbing: 2,995 more Verified |
| 99.99% | 29,956 | waiting |
| 99.999% | 299,572 | waiting |

Verified per check so far: 0.00%. Flagged 530, Check this 2230, not checked 0.

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

The cloud checker this month (2026-10): $19.87 of the $40 cap at the end of the last run, $0.37 of it during that run.

Runner voters, every blind answer for the items sent (a runner holds a seat only at 80% or more by the lower bound, on 200 or more):

| runner | answered | right | right, 95% lower bound | seated |
|---|---|---|---|---|
| granite-4.0-h-tiny | 2713 | 1562 | 55.9900% | no |
| phi-4-mini-instruct | 1689 | 969 | 55.3539% | no |

Why items were not Verified (each reason counted once per item):

| reason | items |
|---|---|
| Not yet passed by three model families. | 1592 |
| No official source states it word for word yet. | 1298 |
| Checkers from 2 different model families, solving it without the key, chose another answer. | 830 |
| Fewer than three independent blind solves reached the key. | 815 |
| The checkers judged it likely wrong. | 625 |
| The checkers were not confident enough. | 618 |
| A dose, diagnosis or treatment no official source states word for word yet. | 559 |
| It cannot be read into statements a source could prove word for word. | 222 |

Each family's blind answers against the gold key (one witness per family per question; "runner": run on GitHub's CPU with no key):

| family | answered | right | right, 95% lower bound |
|---|---|---|---|
| anthropic | 2760 | 2497 | 89.5015% |
| google | 2621 | 2251 | 84.7158% |
| ibm (runner) | 584 | 327 | 52.5119% |
| openai | 248 | 215 | 82.6138% |
| nvidia | 236 | 197 | 78.9748% |
| microsoft (runner) | 12 | 5 | 18.1025% |

Today: 60 sent; stopped at the ladder's half of the Workers AI pool (15 batches).
