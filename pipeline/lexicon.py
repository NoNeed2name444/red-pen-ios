# -*- coding: utf-8 -*-
"""Load the medical lexicon that bounds what repair can recover.

Two files, deliberately: the base list that the guard tests were tuned against,
and the additions made for a particular recording. Keeping them apart means a
widening for one lecture is visible as a widening, rather than disappearing into
a list nobody can diff.

Order matters more than it looks. Ties in the skeleton match are settled by
iteration order, so terms are returned longest-phrase-first: "lupus nephritis"
has to be considered before "lupus", or the multi-word term can never win.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
FILES = [os.path.join(HERE, "prompts", "medical-lexicon.txt"),
         os.path.join(HERE, "prompts", "medical-lexicon-extra.txt")]


def load(paths=None):
    seen, terms = set(), []
    for path in (paths or FILES):
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                term = line.strip()
                if not term or term.startswith("#"):
                    continue
                key = term.lower()
                if key in seen:
                    continue
                seen.add(key)
                terms.append(term)
    terms.sort(key=lambda t: (-len(t.split()), t.lower()))
    return terms


if __name__ == "__main__":
    loaded = load()
    print("%d terms" % len(loaded))
    print("longest first:", loaded[:3])
