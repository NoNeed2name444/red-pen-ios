# -*- coding: utf-8 -*-
"""Cohere as a committee voter, driven properly.

Three things were wrong with running it through transformers' generic ASR
pipeline, and the decoder probe measured all of them on the same checked
window:

1. It was decoded as Arabic. The same model given the same audio with
   language="en" scored 0.418 WER against the reference passage where the
   Arabic decode scored 0.527 - a 10.9 point drop for one argument. It is not
   that the lecture is English; it is that the lecturer says the medical terms
   in English, and an Arabic decode writes those in Arabic letters, where they
   have to be guessed back afterwards. Decoded as English they come out in
   Latin script already: the en pass wrote "nasolabial fold" itself.

2. The int8 checkpoint comes up on CPU as a MIX of dtypes - bf16 weights beside
   float32 biases - and casting the input in either direction failed on it. So
   every parameter and buffer is forced to float32 after loading.

3. The generic pipeline gives no way to pass the language through.

Two things the probe ruled OUT, recorded so they are not tried again:
sequence_bias towards the lexicon's spellings changed the output not at all at
strength 2 and 5 - byte-identical transcripts - and at strength 10 collapsed it
into the word "skin" four hundred times, 4.396 WER. And merging the ar and en
passes phonetically scored WORSE than either alone (0.549), because it swapped
correct Arabic for the English pass's own mistakes.
"""
import collections

NAME = "NAMAA-Space/cohere-transcribe-arabic-07-2026-int8"


def _model():
    import torch
    from transformers import AutoProcessor, AutoModelForSpeechSeq2Seq
    processor = AutoProcessor.from_pretrained(NAME)
    try:
        from transformers import CohereAsrForConditionalGeneration as M
    except Exception:
        M = AutoModelForSpeechSeq2Seq
    model = M.from_pretrained(NAME, device_map="cpu", torch_dtype=torch.float32)
    for p in model.parameters():
        if p.is_floating_point():
            p.data = p.data.float()
    for b in model.buffers():
        if b.is_floating_point():
            b.data = b.data.float()
    return processor, model.eval()


def degenerate(text, floor=20, share=0.3):
    """One token, over and over, is a decoder that has come off the rails.

    Worth catching rather than voting with: a window of four hundred identical
    words is not a minority opinion to be outvoted, it is noise that drags every
    alignment in the window out of step.
    """
    words = text.split()
    if len(words) < floor:
        return False
    most = collections.Counter(w.lower() for w in words).most_common(1)[0][1]
    return most >= floor and most >= len(words) * share


def load(language="en", max_new_tokens=400):
    import torch
    processor, model = _model()

    def run(chunk):
        try:
            inputs = processor(chunk, sampling_rate=16000, language=language,
                               return_tensors="pt")
        except TypeError:
            inputs = processor(chunk, sampling_rate=16000, return_tensors="pt")
        inputs = {k: (v.float() if torch.is_tensor(v) and v.is_floating_point() else v)
                  for k, v in inputs.items()}
        with torch.no_grad():
            # greedy: a voter that says something different each run cannot be
            # voted with
            out = model.generate(**inputs, max_new_tokens=max_new_tokens,
                                 do_sample=False)
        text = processor.batch_decode(out, skip_special_tokens=True)[0].strip()
        return "" if degenerate(text) else text

    return run
