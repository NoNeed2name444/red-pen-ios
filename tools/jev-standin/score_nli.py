"""Layer 6 of the open stand-in for Jev: score each item with an open NLI
cross-encoder, in batch, on GitHub Actions (jev-standin.yml). Free and open:
the model is downloaded from the Hugging Face Hub and run on the runner's
CPU; nothing paid is ever called.

For a question, each option is scored as how strongly "The answer is
<option>." follows from the stem (the entailment probability); for a card,
how strongly its back follows from its front. triage.mjs turns the scores
into a triage: suspect, review or pass. Never a verdict.

    python score_nli.py --model HUB_ID --items items.jsonl --out scores.jsonl
    python score_nli.py --dry --items items.jsonl --out scores.jsonl   (no model: a fixed fake score, to test the plumbing)

The model id is given at run time (the workflow's input or the
TRIAGE_NLI_MODEL variable): any open NLI cross-encoder whose labels name an
entailment class.
"""
import argparse
import hashlib
import json
import sys


def pairs(item):
    if item.get("kind") == "card":
        return [(item.get("front", ""), item.get("back", ""))]
    stem = item.get("stem", "")
    return [(stem, f"The answer is {opt}.") for opt in item.get("options", [])]


def fake_scores(batch):
    # a stable stand-in in [0, 1), so the plumbing can be tested without a model
    return [int(hashlib.sha256((p + "\x00" + h).encode()).hexdigest()[:8], 16) / 2**32 for p, h in batch]


def model_scorer(model_id, max_len):
    import torch
    from transformers import AutoModelForSequenceClassification, AutoTokenizer

    tok = AutoTokenizer.from_pretrained(model_id)
    model = AutoModelForSequenceClassification.from_pretrained(model_id)
    model.eval()
    labels = {i: str(n).lower() for i, n in model.config.id2label.items()}
    entail = [i for i, n in labels.items() if n.startswith("entail")]
    if len(entail) != 1:
        sys.exit(f"The model's labels name no single entailment class: {labels}")
    entail = entail[0]

    def score(batch):
        enc = tok([p for p, _ in batch], [h for _, h in batch], truncation=True, max_length=max_len,
                  padding=True, return_tensors="pt")
        with torch.no_grad():
            probs = torch.softmax(model(**enc).logits, dim=-1)
        return probs[:, entail].tolist()

    return score


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--items", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--max-len", type=int, default=512)
    a = ap.parse_args()
    if not a.dry and not a.model:
        sys.exit("Give --model (an open NLI cross-encoder's Hub id) or --dry.")
    score = fake_scores if a.dry else model_scorer(a.model, a.max_len)
    items = [json.loads(line) for line in open(a.items, encoding="utf-8") if line.strip()]
    with open(a.out, "w", encoding="utf-8") as out:
        for n, item in enumerate(items):
            ps = pairs(item)
            got = []
            for i in range(0, len(ps), a.batch):
                got.extend(score(ps[i:i + a.batch]))
            row = {"id": item.get("id"), "kind": item.get("kind", "mcq"), "scores": [round(float(x), 6) for x in got]}
            out.write(json.dumps(row) + "\n")
            if n % 50 == 0:
                print(f"{n + 1}/{len(items)} scored", file=sys.stderr)


if __name__ == "__main__":
    main()
