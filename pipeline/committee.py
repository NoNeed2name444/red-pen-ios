# -*- coding: utf-8 -*-
"""Run several recognisers over the SAME windows, so their words can be voted on.

Identical windowing is the part that matters. Two engines given different
segmentations produce transcripts that cannot be lined up word for word, and
the whole method depends on lining them up - so every engine here is fed the
exact spans transcribe.window_bounds chooses, one at a time.

Feeding whole windows is also what keeps Whisper honest. Run over long audio it
decodes conditioned on its own previous output and can spiral - on this lecture
it produced "Stable Diffusion", "DALL-E 3" and "BRCA1", none of which were said.
Given a single thirty-second window with that conditioning off, it is a useful
second opinion.
"""
import json, os, re, sys, time
import numpy as np, soundfile as sf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from transcribe import transcribe_windows, SR
import cohere_asr

WHISPER = "openai/whisper-large-v3-turbo"
QWEN = "Qwen/Qwen3-ASR-1.7B-hf"


def _pipe(model, **kw):
    from transformers import pipeline
    return pipeline("automatic-speech-recognition", model=model, device=-1, **kw)


def _text(result):
    if isinstance(result, dict):
        return (result.get("text") or "").strip()
    return str(result).strip()


# Cohere used to go through the generic pipeline and decode as Arabic. Measured
# on the checked window, decoding the same audio as English instead took it from
# 0.527 WER to 0.418 - the lecturer says the medical terms in English, and an
# Arabic decode writes them in Arabic letters for the repair step to guess back.
def cohere():
    return cohere_asr.load("en")


def cohere_ar():
    """The same model decoding as Arabic - worse alone, but a genuinely
    different opinion, which is what a committee is for. Not in the default
    line-up because it is another 45 seconds a window."""
    return cohere_asr.load("ar")


def whisper():
    asr = _pipe(WHISPER)
    gen = {"language": "ar", "task": "transcribe", "condition_on_prev_tokens": False}

    def run(chunk):
        try:
            return _text(asr({"raw": chunk, "sampling_rate": SR}, generate_kwargs=gen))
        except TypeError:
            return _text(asr({"raw": chunk, "sampling_rate": SR}))
    return run


# Qwen3-ASR is not a speech-to-text pipeline model, whatever its name suggests.
# Driven through the generic ASR pipeline it raised a tensor size mismatch on
# every window, in thirty seconds - far too fast to have transcribed anything -
# and eight shards of every committee run quietly voted with two engines instead
# of three. The shapes in that message were both correct (128 mel bins, 3000
# frames): the pipeline was handing them to a model that expects a conversation.
# Only apply_chat_template works, and the answer comes back tagged.
ASR_TEXT = re.compile(r"<asr_text>(.*)", re.S)


def _asr_text(raw):
    match = ASR_TEXT.search(raw or "")
    text = match.group(1) if match else (raw or "")
    text = re.sub(r"</asr_text>.*", "", text, flags=re.S)
    text = re.sub(r"^\s*language\s+\S+\s*", "", text)
    return text.strip()


def qwen():
    import torch
    from transformers import AutoProcessor, Qwen3ASRForConditionalGeneration
    processor = AutoProcessor.from_pretrained(QWEN)
    model = Qwen3ASRForConditionalGeneration.from_pretrained(
        QWEN, dtype=torch.float32).eval()

    def run(chunk):
        messages = [{"role": "user", "content": [
            {"type": "audio", "audio": chunk},
            {"type": "text", "text": ""}]}]
        inputs = processor.apply_chat_template(
            messages, add_generation_prompt=True, tokenize=True,
            return_dict=True, return_tensors="pt", sampling_rate=SR)
        length = inputs["input_ids"].shape[-1]
        with torch.no_grad():
            ids = model.generate(**inputs, max_new_tokens=440, do_sample=False)
        return _asr_text(processor.decode(ids[0][length:], skip_special_tokens=True))
    return run


ENGINES = {"cohere": cohere, "cohere-ar": cohere_ar,
           "whisper-turbo": whisper, "qwen3-asr": qwen}


def main():
    shard = int(os.environ["SHARD"])
    shards = int(os.environ["SHARDS"])
    pad = float(os.environ.get("PAD", "10"))
    wanted = [e.strip() for e in os.environ.get(
        "ENGINES", "cohere,whisper-turbo,qwen3-asr").split(",") if e.strip()]

    wav, _ = sf.read("job/full.wav", dtype="float32")
    if wav.ndim > 1:
        wav = wav.mean(axis=1)
    total = len(wav) / SR
    span = total / shards
    core_start, core_end = shard * span, min((shard + 1) * span, total)
    start = max(0.0, core_start - (pad if shard else 0.0))
    end = min(total, core_end + (pad if shard < shards - 1 else 0.0))
    piece = wav[int(start * SR):int(end * SR)]

    out = {"shard": shard, "shards": shards, "total_seconds": round(total, 2),
           "start": round(start, 2), "end": round(end, 2),
           "core_start": round(core_start, 2), "core_end": round(core_end, 2),
           "pad": pad, "engines": {}, "seconds": {}, "errors": {}}

    for name in wanted:
        t0 = time.time()
        try:
            recognise = ENGINES[name]()
            out["engines"][name] = transcribe_windows(piece, recognise)
        except Exception as exc:
            # One engine failing must not cost the run the others: a committee
            # of two still votes, and the error is recorded rather than hidden.
            out["errors"][name] = "%s: %s" % (type(exc).__name__, exc)
            out["engines"][name] = ""
        out["seconds"][name] = round(time.time() - t0, 1)
        words = len(out["engines"][name].split())
        # A voter that "finished" in seconds did not transcribe anything. That
        # went unnoticed for a whole run, so it is called out in the log now.
        suspicious = " <- suspiciously fast, check it" if (
            not out["errors"].get(name) and words and out["seconds"][name] < 60) else ""
        print("%-14s %6.1fs  %5d words %s%s" % (name, out["seconds"][name], words,
                                                out["errors"].get(name, ""), suspicious))

    os.makedirs("out", exist_ok=True)
    json.dump(out, open("out/shard-%d.json" % shard, "w"), ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
