# -*- coding: utf-8 -*-
"""Which studyable details of the source no card or question covers.

The reason a generated deck misses things is that the count is chosen before
the source is read. "Make 20 questions" produces 20 questions whatever the
lecture contained: a dense forty-minute lecture gets skimmed, a thin one gets
padded with restatements, and in both cases nothing ever reports what was left
out. The student finds out in the exam.

So the count is not an input here. The source is broken into the claims a
lecturer could reasonably ask about, each claim is checked against the deck,
and what nothing covers is listed. The generator is then asked again FOR THOSE
CLAIMS specifically, and the deck is finished when the list is empty - which is
a fact about the lecture, not a number somebody picked.

Two honest limits, because this decides what "comprehensive" means:

  * what counts as studyable is a judgement, and this one is deliberately
    generous. A clause earns a place if it carries a number, a technical term,
    or a relation a question could be built on. Generous is the safe direction:
    an extra line in the uncovered list costs you a glance, while a missing one
    costs you the mark;
  * coverage is measured on the WORDS, not the meaning. A card saying the same
    thing in entirely different vocabulary reads as uncovered. That is why the
    output is a list for review and a target for the generator, never a score
    to put in front of a student or a gate that fails a build.
"""
import re

# a clause is worth asking about if it carries one of these
NUMBER = re.compile(r"\d")
RELATIONS = (
    "cause", "causes", "caused", "treat", "treats", "treated", "indicate",
    "indicates", "suggest", "suggests", "confirm", "confirms", "exclude",
    "excludes", "spare", "spares", "present", "presents", "associated",
    "differentiate", "differentiates", "diagnose", "diagnosed", "first",
    "most", "least", "before", "after", "unless", "except", "increase",
    "increases", "decrease", "decreases", "contraindicated", "criterion",
    "criteria", "dose", "risk", "complication", "sign", "symptom",
)
# words that carry no identity, so a clause made only of these is not a fact
COMMON = {
    "the", "a", "an", "of", "in", "is", "are", "to", "and", "or", "with", "for",
    "by", "on", "at", "as", "that", "this", "it", "be", "we", "you", "they",
    "can", "will", "have", "has", "was", "were", "but", "so", "if", "then",
    "what", "which", "here", "there", "okay", "now", "also", "very", "just",
    "like", "about", "one", "two", "some", "any", "all", "more", "other",
}
WORD = re.compile(u"[A-Za-z؀-ۿ][A-Za-z؀-ۿ'\\-]*")
# sentence enders in both scripts, plus the separators a transcript is full of
SPLIT = re.compile(u"[.!?؟؛;\n]+|\\s+-\\s+")
MIN_TERMS = 2


def terms(text):
    """Content words, in either script."""
    found = []
    for w in WORD.findall(text or ""):
        low = w.lower()
        if len(low) >= 3 and low not in COMMON:
            found.append(low)
    return found


def is_studyable(clause):
    """Could a lecturer build a question on this clause?"""
    words = terms(clause)
    if len(words) < MIN_TERMS:
        return False
    if NUMBER.search(clause):
        return True
    if any(w in RELATIONS for w in words):
        return True
    # a technical term is a long word that is not ordinary speech; a clause with
    # two of them is a claim about something, whatever the verb is
    technical = [w for w in words if len(w) >= 7]
    return len(technical) >= 2


def facts(source):
    """The claims the source makes, in order, deduplicated."""
    out, seen = [], set()
    for raw in SPLIT.split(source or ""):
        clause = " ".join(raw.split())
        if not clause or not is_studyable(clause):
            continue
        key = frozenset(terms(clause))
        if key in seen:
            continue
        seen.add(key)
        out.append({"text": clause, "terms": sorted(key)})
    return out


def rarity(all_facts):
    """How many facts each term appears in - a term in every fact proves nothing."""
    counts = {}
    for f in all_facts:
        for t in f["terms"]:
            counts[t] = counts.get(t, 0) + 1
    return counts


def covers(item_text, fact, counts, floor=0.6):
    """Does this card or question cover this claim?

    Two conditions, and the second is what stops a card about the topic being
    counted as a card about the claim: enough of the claim's words must be
    present, AND at least one of them must be a word that does not appear all
    over the lecture.
    """
    said = set(terms(item_text))
    wanted = set(fact["terms"])
    if not wanted:
        return False
    shared = said & wanted
    if len(shared) < floor * len(wanted):
        return False
    distinctive = [t for t in shared if counts.get(t, 0) <= max(2, len(counts) // 50)]
    return bool(distinctive)


def text_of_card(card):
    parts = [card.get("front", ""), card.get("clozeText", ""), card.get("why", "")]
    parts += card.get("bullets", []) or []
    return " ".join(p for p in parts if p)


def text_of_question(q):
    parts = [q.get("stem", ""), q.get("explanation", "")]
    parts += q.get("options", []) or []
    return " ".join(p for p in parts if p)


def report(source, cards=(), questions=(), floor=0.6):
    """What the deck covers, and what it does not.

    `still_to_cover` is the useful output: hand it back to the generator as the
    list of things to write cards for, rather than asking for "more cards" and
    getting the same ground restated.
    """
    found = facts(source)
    counts = rarity(found)
    items = [text_of_card(c) for c in cards] + [text_of_question(q) for q in questions]

    covered, uncovered = [], []
    for fact in found:
        if any(covers(text, fact, counts, floor) for text in items):
            covered.append(fact["text"])
        else:
            uncovered.append(fact["text"])

    return {
        "studyable_claims": len(found),
        "covered": len(covered),
        "coverage": round(len(covered) / float(len(found)), 3) if found else None,
        "cards": len(cards),
        "questions": len(questions),
        # what the deck SHOULD hold, if one claim is worth one card. Not a
        # target to pad towards - a claim already covered twice needs no third.
        "claims_per_card": round(len(found) / float(max(1, len(cards))), 2) if cards else None,
        "still_to_cover": uncovered,
    }


if __name__ == "__main__":
    import json, sys
    spec = json.load(open(sys.argv[1], encoding="utf-8"))
    out = report(spec.get("source", ""), spec.get("cards", []), spec.get("mcq", []))
    for line in out["still_to_cover"]:
        print("uncovered:", line[:100])
    print(json.dumps({k: v for k, v in out.items() if k != "still_to_cover"}, indent=2))
