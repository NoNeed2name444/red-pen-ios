# -*- coding: utf-8 -*-
"""Join shard transcripts, removing the speech the padding made them share.

Shards are cut with ten seconds of padding on each side so that no word falls
on a boundary, which means consecutive shards transcribe the same twenty-odd
seconds twice. Removing that duplicate is this module's whole job.

The first version compared words for exact equality. It deduplicated ZERO
words at every one of seven boundaries and the duplicated passages stayed in
the record. The cause was orthographic, not acoustic: the same speech came
back with a different hamza seat, a ta-marbuta where the other shard wrote a
ha, or one extra tanween mark. Those are spellings of one word, so the
comparison folds them before it compares.
"""
import re, unicodedata

# combining marks: the harakat, the hamza and madda marks that NFKD frees from
# a carrier letter, the superscript alef, and the tatweel stretcher
DIACRITICS = re.compile(u"[ً-ٰٕـ]")
# NFKD already splits the hamza off its alef, so only the letters that do not
# decompose need a rule: alef maqsura -> ya, ta marbuta -> ha.
FOLD = {u"ى": u"ي", u"ة": u"ه"}


def norm(word):
    w = DIACRITICS.sub("", unicodedata.normalize("NFKD", word))
    w = "".join(FOLD.get(ch, ch) for ch in w)
    return re.sub(u"[^\\w؀-ۿ]", "", w).lower()


def overlap(a_words, b_words, max_words=80, min_words=4, agree=0.8):
    """The longest tail-of-a / head-of-b run whose normalised words agree.

    Exact equality is too strict and a bare similarity ratio is too loose, so
    the rule is: the longest run agreeing on at least `agree` of its words,
    with its first and last word agreeing exactly. Anchoring both ends is what
    stops a chance agreement in the middle of a run from cutting real speech.
    """
    an = [norm(w) for w in a_words]
    bn = [norm(w) for w in b_words]
    top = min(max_words, len(an), len(bn))
    for k in range(top, min_words - 1, -1):
        tail, head = an[-k:], bn[:k]
        if tail[0] != head[0] or tail[-1] != head[-1]:
            continue
        same = sum(1 for x, y in zip(tail, head) if x == y)
        if same / float(k) >= agree:
            return k, same / float(k)
    return 0, 0.0


def stitch(a, b, max_lead=3):
    """Merge b onto a, dropping b's copy of the shared padding.

    b may open mid-word: its first token is the tail of a word the previous
    shard already wrote whole, and an anchored run can never start on it. So
    the head is allowed to start a few words in, and whatever is skipped is
    dropped along with the overlap - it is a fragment of speech already in a.
    """
    aw, bw = a.split(), b.split()
    best = (0, 0, 0.0)
    for lead in range(max_lead + 1):
        if lead >= len(bw):
            break
        k, score = overlap(aw, bw[lead:])
        if k > best[1]:
            best = (lead, k, score)
    lead, k, score = best
    cut = lead + k if k else 0
    return " ".join(aw + bw[cut:]), k, round(score, 3)
