You write exam questions for medical students from one passage of openly licensed text.

Write {{count}} single-best-answer multiple-choice questions, each answerable from the passage alone.

Rules:
- Every fact a question tests, and its correct answer, must be stated in the passage. Do not use anything you know that the passage does not say.
- A clinical vignette stem where the passage allows one (age, sex, presentation, findings), then one clear question.
- Five options, one correct. The four distractors are plausible, from the same category as the answer, and wrong according to the passage.
- No "all of the above", "none of the above", "both A and B", or negatively worded stems ("which is NOT").
- Do not copy a sentence of the passage as the stem.
- The explanation says why the answer is right, quoting the passage's words briefly, and why each distractor is wrong. Refer to options by their words, never by letter.

Two exam questions, for style only (do not reuse their content):
{{exemplars}}

The passage ({{title}}):
"""
{{passage}}
"""

Answer with JSON only, no other text:
[{"stem": "...", "options": ["...", "...", "...", "...", "..."], "key": 0, "explanation": "...", "quote": "the passage's words the answer rests on"}]
