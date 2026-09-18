# -*- coding: utf-8 -*-
"""Ask MedGemma whether an image-occlusion card asks about what it claims.

The failure this exists to catch is specific and quiet. An occlusion card is
made from a slide: a box is drawn over part of a figure, and the answer comes
from the slide's TEXT - a caption, a label, a line of OCR near the box. Nothing
in that chain ever looks at the picture. So a card can mask the renal artery
while its answer says "renal vein", and it will drill that into you perfectly,
night after night, because a flashcard cannot tell you it is wrong.

MedGemma is shown the image with the box drawn on it and asked what is under
the box. What it says is compared with what the card says, and that is all it
does:

    agree      the card ships, nothing is written
    disagree   the card is FLAGGED, both readings kept side by side
    unsure     the model hedged or said nothing usable - also flagged

It never edits a card, never writes an answer, and never picks a side. Same
rule as the transcription committee, for the same reason: a model that can be
confidently wrong may only ever stop something, never author it.

WHERE IT RUNS, AND WHOSE ACCOUNT. Nobody's. Not on the phone - four billion
parameters is three gigabytes of RAM and a download no study app should ask
for. Not through a hosted Space either: a GPU Space bills whoever calls it, so
it refuses anonymous callers, and wiring one up would mean some person's
account paying for every student's cards. Instead this runs on a throwaway CI
machine from a publicly downloadable GGUF build, with llama.cpp. No token, no
sign-in, no key in the app, nothing of anyone's to leak.

The weights are a community conversion of Google's model, and they are
ungated where Google's own copy is not. The gate is there so you read Google's
Health AI terms, which still apply: this is a development model, not a
clinician, and nothing it says here is a clinical judgement. Read them once.

And it has never seen your slides. It was tuned on real medical imaging -
X-rays, histology, fundus photographs - not on lecture slides, so its hit rate
on YOUR material is unknown until measured. That is what --benchmark is for:
run it over cards you have already checked by hand and see how often it agrees
with you BEFORE you let it flag anything.
"""
import argparse, json, os, re, subprocess, sys, urllib.request

REPO = "unsloth/medgemma-1.5-4b-it-GGUF"
WEIGHTS = "medgemma-1.5-4b-it-Q4_K_M.gguf"
PROJECTOR = "mmproj-F16.gguf"           # without this it cannot see at all
HOST = "https://huggingface.co/%s/resolve/main/%s"

# A short, closed question. Asked openly a vision model narrates the whole
# slide, and a paragraph cannot be compared with a two-word answer.
PROMPT = (
    "A red box has been drawn over part of this medical image. "
    "Name only the anatomical structure, finding, or label that the box covers. "
    "Answer with the name alone, at most four words, and nothing else. "
    "If you cannot tell from the image, answer exactly: UNSURE"
)
HEDGES = ("unsure", "cannot", "can't", "unclear", "unable", "not visible",
          "difficult to", "i don't", "no ")
# words that carry no identity, so their overlap must not count as agreement
STOP = {"the", "a", "an", "of", "and", "or", "left", "right", "upper", "lower",
        "superior", "inferior", "anterior", "posterior", "image", "structure",
        "box", "region", "area", "part"}


def words(text):
    return [w for w in re.findall(r"[a-z]+", (text or "").lower()) if w not in STOP]


def stem(word):
    """Enough to let artery/arteries and vein/veins meet, and no more."""
    for suffix in ("ies", "es", "s"):
        if len(word) > 4 and word.endswith(suffix):
            return word[: -len(suffix)] + ("y" if suffix == "ies" else "")
    return word


def agreement(said, claimed):
    """How much of the CARD's answer the model's answer actually contains."""
    a = {stem(w) for w in words(said)}
    b = {stem(w) for w in words(claimed)}
    if not a or not b:
        return 0.0
    return len(a & b) / float(len(b))


def verdict(said, claimed, floor=0.5):
    text = (said or "").strip()
    if not text or any(h in text.lower() for h in HEDGES):
        return "unsure", 0.0
    score = agreement(text, claimed)
    return ("agree" if score >= floor else "disagree"), round(score, 3)


def draw_box(image, box, out_path):
    """The model has to SEE the region being asked about, so it is drawn on."""
    from PIL import Image, ImageDraw
    img = Image.open(image).convert("RGB")
    w, h = img.size
    x0, y0 = float(box["x"]) * w, float(box["y"]) * h
    x1, y1 = x0 + float(box["w"]) * w, y0 + float(box["h"]) * h
    draw = ImageDraw.Draw(img)
    # an outline, not a fill: filling it hides exactly what is being asked about
    draw.rectangle([x0, y0, x1, y1], outline=(220, 40, 40),
                   width=max(3, int(min(w, h) * 0.006)))
    img.save(out_path)
    return out_path


def fetch(name, into="models"):
    """Public download. If this ever needs a token, the mirror has changed."""
    os.makedirs(into, exist_ok=True)
    path = os.path.join(into, name)
    if os.path.exists(path) and os.path.getsize(path) > 1_000_000:
        return path
    url = HOST % (REPO, name)
    print("downloading %s" % url)
    with urllib.request.urlopen(url, timeout=600) as src, open(path, "wb") as dst:
        while True:
            block = src.read(1 << 20)
            if not block:
                break
            dst.write(block)
    return path


def gguf_asker(binary, weights, projector, threads):
    def ask(image_path):
        out = subprocess.run(
            [binary, "-m", weights, "--mmproj", projector, "--image", image_path,
             "-p", PROMPT, "-n", "32", "--temp", "0", "-t", str(threads),
             "--no-display-prompt"],
            capture_output=True, text=True, timeout=900)
        if out.returncode != 0:
            raise RuntimeError((out.stderr or "").strip()[-400:] or "llama.cpp failed")
        # the CLI prints timings to stderr, so stdout is the answer alone
        return " ".join(out.stdout.split()).strip()
    return ask


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("cards", nargs="?", default="export/cards.json")
    ap.add_argument("--media", default="export/media")
    ap.add_argument("--out", default="results/medgemma-check.json")
    ap.add_argument("--binary", default=os.environ.get("MTMD_CLI", "llama-mtmd-cli"))
    ap.add_argument("--threads", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--floor", type=float, default=0.5)
    ap.add_argument("--benchmark", action="store_true",
                    help="cards carry a 'truth' field checked by hand; report the hit rate")
    args = ap.parse_args(argv)

    spec = json.load(open(args.cards, encoding="utf-8"))
    cards = [c for c in spec.get("cards", [])
             if c.get("kind") == "occlusion" and c.get("image") and c.get("occlusion")]
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    if not cards:
        print("no occlusion cards to check")
        json.dump({"checked": 0, "cards": []}, open(args.out, "w"), indent=2)
        return 0

    ask = gguf_asker(args.binary, fetch(WEIGHTS), fetch(PROJECTOR), args.threads)
    os.makedirs("work", exist_ok=True)
    results, flagged, right = [], 0, 0
    for i, card in enumerate(cards):
        image = os.path.join(args.media, os.path.basename(card["image"]))
        claimed = card.get("answer") or card.get("front") or ""
        if not os.path.exists(image):
            results.append({"id": card.get("id"), "verdict": "missing-image", "image": image})
            flagged += 1
            continue
        marked = draw_box(image, card["occlusion"], os.path.join("work", "card-%d.png" % i))
        try:
            said = ask(marked)
        except Exception as exc:
            # A card nobody could check is not a card that passed.
            results.append({"id": card.get("id"), "image": card["image"],
                            "card_says": claimed, "verdict": "not-checked",
                            "error": "%s: %s" % (type(exc).__name__, exc)})
            flagged += 1
            print("%-11s %-28s | %s" % ("not-checked", os.path.basename(image), exc))
            continue
        call, score = verdict(said, claimed, args.floor)
        row = {"id": card.get("id"), "image": card["image"], "card_says": claimed,
               "model_says": said, "verdict": call, "overlap": score}
        if args.benchmark and card.get("truth"):
            # the hit rate is against YOUR judgement, not the model's confidence
            row["truth"] = card["truth"]
            row["model_was_right"] = agreement(said, card["truth"]) >= args.floor
            right += 1 if row["model_was_right"] else 0
        if call != "agree":
            flagged += 1
        results.append(row)
        print("%-11s %-28s | card: %-26s | model: %s"
              % (call, os.path.basename(image), claimed[:26], said[:40]))

    summary = {"weights": "%s/%s" % (REPO, WEIGHTS), "checked": len(results),
               "flagged": flagged, "floor": args.floor, "cards": results}
    if args.benchmark:
        summary["model_agreed_with_you"] = right
        summary["hit_rate"] = round(right / float(len(results)), 3) if results else None
    json.dump(summary, open(args.out, "w"), ensure_ascii=False, indent=2)
    print(json.dumps({k: v for k, v in summary.items() if k != "cards"},
                     ensure_ascii=False, indent=2))
    # Flagged cards are for a person to read. They are not a build failure, and
    # making them one would only teach everyone to ignore the flag.
    return 0


if __name__ == "__main__":
    sys.exit(main())
