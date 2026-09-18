# -*- coding: utf-8 -*-
"""Apply the learned pronunciations before any guessing happens.

An exact lookup cannot make the mistakes the fuzzy matcher makes. ريسك scored
1.000 against both `risk factor` and `rosacea` and the alphabet decided; a
dictionary entry decides it instead, because the committee heard it and wrote
it down. So this runs first, and the phonetic repair only ever sees what the
dictionary could not account for.

The keys are sounds, not spellings, so an entry learned from one engine's
spelling also covers the others': ميكو كوتينيوس and ميكو كوتينياس are one key,
and an entry learned from either covers both.
"""
import re
from repair import ARLETTER, DIAC
from consensus import sound

# the same shape repair.py writes: an optional و/ف/ب/ل then the article
ARTICLE = re.compile(u"^([وفبل]?)(ال[^ا-ي]?)")


def apply(text, table, max_ngram=3):
    """Replace every span whose sound is in the table. Returns (text, hits)."""
    if not table:
        return text, []
    if "\n" in text:
        lines, all_hits = [], []
        for line in text.split("\n"):
            out, hits = apply(line, table, max_ngram)
            lines.append(out)
            all_hits += hits
        return "\n".join(lines), all_hits

    tokens = text.split()
    out, hits, i = [], [], 0
    while i < len(tokens):
        hit = None
        for n in range(min(max_ngram, len(tokens) - i), 0, -1):
            span = tokens[i:i + n]
            if not any(ARLETTER.search(t) for t in span):
                continue
            key = " ".join(sound(t) for t in span)
            if key.strip() and key in table:
                hit = (n, table[key])
                break
        if hit:
            n, english = hit
            # The lecturer's own definite article stays where he put it, and is
            # written the way the rest of the pipeline writes it - "الـ malar rash".
            # Dropping it here cost more word errors than the lookup saved.
            head = DIAC.sub("", tokens[i])
            lead = ARTICLE.match(head)
            prefix = (lead.group(1) + u"الـ ") if lead and len(head) > 3 else ""
            out.append(prefix + english)
            hits.append((" ".join(tokens[i:i + n]), english))
            i += n
        else:
            out.append(tokens[i])
            i += 1
    return " ".join(out), hits
