# Question bank: source fetcher

Plan Task 5b step 2. `fetch.mjs` gathers passages that question generation (step 3) can be built from. It reads only from sources that `governance/licences/allowlist.json` allows, only through the interfaces those sources sanction, and every passage goes through `licenceVerdict` (`governance/licences/licences.mjs`) before it is kept. Anything refused goes to the refusals file with its reason, never to the bank.

```
node tools/question-bank/fetch.mjs --out out/passages.jsonl --topics "asthma,heart failure"
node tools/question-bank/fetch.mjs --out out/passages.jsonl --topics-file tools/question-bank/topics.txt --pmc-per-topic 3
```

Options: `--sources medlineplus,pmc` (default: both), `--pmc-per-topic N` (default 2), `--medline-per-topic N` (default 1), `--max-passages N` per article (default 8). The command writes `<out>.jsonl` (kept passages) and `<out>.refused.jsonl` (refusals), and prints the counts. It exits 1 only when nothing was kept and a request failed.

Node 22. It has no dependencies, needs no key and holds no secrets. You can set `NCBI_API_KEY`, which raises NCBI's limit from 3 to 10 requests a second, and `NCBI_EMAIL`, a contact address NCBI asks callers to give. Neither is needed.

## Endpoints used (confirmed live, 1 October 2026)

| Source | Endpoint | Request |
|---|---|---|
| MedlinePlus health topics | `https://wsearch.nlm.nih.gov/ws/query` | `?db=healthTopics&term=<topic>&retmax=<n>&rettype=topic`: the MedlinePlus web service. `rettype=topic` returns the whole health-topic record, and only its `<full-summary>` text is kept. English only (`healthTopics`, not `healthTopicsSpanish`). |
| PMC search | `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi` | `?db=pmc&term=<topic>[Title/Abstract] AND open access[filter]&retmax=<n>&retmode=json&sort=relevance&tool=stethoscore-question-bank` (plus `api_key` and `email` when set). |
| PMC articles | `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi` | `?db=pmc&id=<id>,<id>,...&retmode=xml&tool=stethoscore-question-bank`: JATS XML for every id in one request. |

Things it never requests: medlineplus.gov pages themselves (so nothing is scraped), `/ency/` (A.D.A.M., copyrighted), `/druginfo/` (ASHP, copyrighted), images, the PMC website, or the PMC Open Access FTP/cloud bulk files. The BioC API is also sanctioned for PMC, but E-utilities alone is enough, so the fetcher does not use BioC.

A live run on 1 October 2026 for `asthma,heart failure` with `--pmc-per-topic 2 --max-passages 3` kept 11 passages: two MedlinePlus summaries, plus CC BY 4.0 and CC BY 3.0 PMC passages. It refused one CC BY-NC 3.0 article (PMC11246090) with its reason. It made 6 requests and took about 4 seconds.

## What decides keep or refuse

- **MedlinePlus:** only health topic summaries, which MedlinePlus says are public domain (licence `US-GOV-PD-MEDLINEPLUS`). The gate checks each passage's URL, so a summary pointing into `/ency/`, `/druginfo/` or `/images/`, at another host or over plain http is refused.
- **PMC:** the `open access[filter]` in the search only narrows the list; it is not the decision. Each article's own `<permissions><license>` decides. The fetcher reads the licence from the ALI `license_ref` and the `<license>` or `<ext-link>` `xlink:href`, then from a Creative Commons URL in the statement. Only CC0 1.0 and CC BY 2.0, 3.0 and 4.0 pass. Any NC, ND or SA term is refused, whether it appears in the link, in `license-type` or `content-type`, or in the statement's wording ("not used for commercial purposes"). An article with no licence statement is refused. So is a statement that names no licence ("open access" alone).
- **Both:** a passage with no usable text is refused. Some MedlinePlus topics have no full summary in the web service (for example, Diabetes Type 2 on 1 October 2026), and they are refused this way.

## Output (one JSON object per line)

```json
{"source":"pmc-open-access","url":"https://pmc.ncbi.nlm.nih.gov/articles/PMC13448598/","licence":"CC-BY-4.0",
 "licenceUrl":"https://creativecommons.org/licenses/by/4.0/legalcode.en","licenceStatement":"This is an open access article ...",
 "attribution":"A Author, B Author, C Author, et al. (2026). Title. Journal. doi:10.x/y. PMC13448598. Licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/legalcode.en).",
 "title":"...","section":"Abstract","retrieved":"2026-10-01","text":"...",
 "pmcid":"PMC13448598","pmid":"...","doi":"...","journal":"...","authors":["..."],"year":"2026"}
```

MedlinePlus passages carry the same core fields. Their attribution reads `<Title>. Courtesy of MedlinePlus from the National Library of Medicine. <url>. Retrieved <date>.` Long PMC sections are split at paragraph boundaries into passages of at most about 4,000 characters.

## Politeness and failure

- NCBI: at most 3 requests a second without a key and 10 with one, spaced by a throttle. Articles are fetched in one `efetch` per topic. Requests carry `tool=stethoscore-question-bank`.
- MedlinePlus web service: at most about 1 request a second, under its limit of 85 a minute per IP.
- Every request sends `User-Agent: StethoscoreQuestionBank/0.1 (+https://github.com/NoNeed2name444/red-pen-ios; licence-checked study passages)`.
- On a 429 or 5xx the request is retried twice with backoff. A request that still fails skips that topic for that source and is logged; the rest of the run carries on. Passages are written as they are kept, so a failure never loses them.

## Tests and CI

`tests/question-bank/fetch.test.mjs` runs against responses recorded from the endpoints above on 1 October 2026 (`tests/question-bank/fixtures/`, trimmed), with no network. It runs in the Server tests workflow. `.github/workflows/question-bank.yml` (run by hand) runs the tests, fetches for `topics.txt` or the topics you give, and uploads `out/` as the `question-bank-passages` artifact.
