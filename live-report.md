# Live model test

Run 35939134389 on 2026-09-24 00:36 (UTC).

## CramDown Cloud: Gemini 3.5 Flash (Workers AI when out of quota)

### ✅ MCQ — 43 s

3 question(s), each with 5 options and a valid answer index (the app's own validity rules).

**Q1.** A 28-year-old woman presents with a malar rash, painless oral ulcers, and joint pain in her hands. Which of the following tests is the most specific for confirming the diagnosis of systemic lupus erythematosus?
- A. Antinuclear antibody
- B. Anti-double-stranded DNA
- C. Anti-Smith antibody
- D. Complement C3 levels
- E. Antiphospholipid antibody

*Answer: C* — Anti-Smith antibodies are highly specific for systemic lupus erythematosus. While antinuclear antibody is the best screening test due to high sensitivity (over 95%), it is not specific. Anti-double-stranded DNA is also highly specific, but Anti-Smith is traditionally highlighted as a hallmark diagnostic marker. Complement C3 levels fall during active disease but are not specific for diagnosis.

**Q2.** A 32-year-old woman with known systemic lupus erythematosus presents with worsening proteinuria and edema. Laboratory results show an increase in anti-dsDNA titers and a decrease in C3 and C4 levels. Which of the following is the most appropriate management for her current condition?
- A. Hydroxychloroquine monotherapy
- B. Oral prednisone monotherapy
- C. Mycophenolate mofetil therapy
- D. Low-dose aspirin therapy
- E. Annual retinal screening

*Answer: C* — The patient is presenting with signs of active lupus nephritis (proteinuria, edema, rising anti-dsDNA, and falling complement). Severe organ involvement, such as class III or IV lupus nephritis, requires immunosuppression with mycophenolate mofetil or cyclophosphamide. Hydroxychloroquine is used for all patients but is insufficient for severe nephritis. Prednisone is used for flares but not as the sole definitive treatment for severe nephritis.

**Q3.** Which of the following clinical features of systemic lupus erythematosus is characterized by chronic scarring plaques with follicular plugging?
- A. Malar rash
- B. Discoid lupus
- C. Pleurisy
- D. Lupus nephritis
- E. Serositis

*Answer: B* — Discoid lupus causes chronic scarring plaques with follicular plugging, most often on the scalp, face, and ears, and can leave permanent scarring and hair loss. The malar rash is an erythematous rash over the cheeks and bridge of the nose that spares the nasolabial folds and does not cause permanent scarring.

### ✅ OSCE — 42 s

**Counselling a Patient with Systemic Lupus Erythematosus (SLE)**
1. Introduces self to the patient
2. Obtains informed consent
3. Explains SLE is a chronic autoimmune disease
4. Advises the patient to use sun protection
5. Explains the need for hydroxychloroquine treatment
6. Mentions the requirement for annual eye screening for retinal toxicity
7. Explains that corticosteroids are used to treat flares
8. Discusses potential for severe organ involvement requiring immunosuppression
9. Mentions risk of thrombosis or recurrent miscarriage if antiphospholipid antibodies are present
10. Offers to answer any questions
11. Performs hand hygiene
12. States what they would do to finish the consultation

### ✅ Anki — 24 s

6 card(s) parsed by the app's own importer.

- **What is the best screening test for SLE?** → **ANA**
- **Which SLE rash spares the nasolabial folds?** → **Malar** (butterfly) rash
- **Which SLE antibody levels correlate with disease activity?** → **anti-dsDNA**
- **Which antibodies in SLE are highly specific?** → **anti-dsDNA**; **anti-Smith**
- **What is the first-line medication for all SLE patients?** → **Hydroxychloroquine**
- **Which drugs treat severe class III or IV lupus nephritis?** → **Mycophenolate mofetil**; **Cyclophosphamide**

### ✅ Cases — 24 s

4 card(s) parsed by the app's own importer.

- [Clinical case] *SLE* — A woman of childbearing age presents with a butterfly rash sparing the nasolabial folds and painless oral ulcers. What is the most likely diagnosis?
  → **Systemic lupus erythematosus**
- [Recall] *SLE* — Which two antibodies are highly specific for SLE?
  → **Anti-double-stranded DNA**; **anti-Smith**
- [Clinical case] *SLE* — A patient with SLE has worsening nephritis and rising anti-dsDNA levels. What are the options for immunosuppression?
  → **Mycophenolate mofetil**; **cyclophosphamide**
- [Recall] *SLE* — What are the screening and monitoring requirements for patients taking hydroxychloroquine?
  → **Annual eye screening**; check for **retinal toxicity**

### ✅ Textbook — 59 s

1 page(s).

```
## Systemic Lupus Erythematosus (SLE)

**Epidemiology**
* Chronic autoimmune disease.
* Primarily affects women of childbearing age (**female:male ratio ~9:1**).

**Clinical Features**
* **Skin**:
    * **Malar (butterfly) rash**: Erythematous rash over cheeks and bridge of nose; **spares nasolabial folds** and is worsened by sunlight.
    * **Discoid lupus**: Chronic scarring plaques with follicular plugging (scalp, face, ears); can cause **permanent scarring and hair loss**.
* **Other Features**:
    * **Non-erosive arthritis** of small joints of the hands.
    * **Oral ulcers** (usually painless).
    * **Serositis** (pleurisy or pericarditis).
    * **Lupus nephritis**.
    * **Cytopenias**: Autoimmune haemolytic anaemia, leucopenia, and thrombocytopenia.

**Antibodies and Markers**
* **Antinuclear antibody (ANA)**: Positive in **>95%** of patients; best **screening test**, but non-specific.
* **Anti-double-stranded DNA (anti-dsDNA)** and **anti-Smith**: Highly specific.
* **Anti-dsDNA**: Levels rise with **disease activity**, particularly **nephritis**.
* **Complement C3 and C4**: Decrease during active disease.
* **Antiphospholipid antibodies**: Increase risk of **venous/arterial thrombosis** and **recurrent miscarriage**.

**Management**
* **Hydroxychloroquine**: Indicated for all patients unless contraindicated; requires **annual eye screening** for retinal toxicity.
* **Sun protection**: Advised for all.
* **Corticosteroids**: Used to treat flares.
* **Immunosuppression**: Required for severe organ involvement (e.g., **class III or IV lupus nephritis**) using **mycophenolate mofetil** or **cyclophosphamide**.
```

### ✅ Accuracy check (MedVAL rubric) — 166 s

Faithful statement → Level 1 — no risk — 

Planted error → Level 4 — high risk — Error 1: Detail misidentification: output states malar rash "involves the nasolabial folds" while input says it "spares the nasolabial folds" | Error 2: Detail misidentification: output states malar rash "always scars" while input indicates discoid lupus scars "unlike the malar rash" | Error 3: Other: contradicts current evidence [S5] and input: output suggests treating SLE rash with "penicillin" 

(Pass means the faithful one passed AND the planted error was graded level 3–4.)

### ✅ Simulated patient — 450 s

Case written from: *A woman of childbearing age presents with a butterfly rash sparing the nasolabial folds and painless oral ulcers. What is the most likely diagnosis?*

Hidden diagnosis: **Systemic lupus erythematosus** · checklist items: 27

**Doctor:** Hello, I'm a medical student. What brings you in today?

**Patient:** (Sighs, looking tired) Hi... I've got this red rash on my face and some sores in my mouth that just won't go away. I'm also feeling really, really tired. _(Level 1 — no risk)_

**Doctor:** Have you noticed any rash, joint pain or mouth ulcers?

**Patient:** Yes, I have. I've got the rash on my cheeks and nose, some sores on the roof of my mouth, and my hands and wrists have been hurting. _(Level 1 — no risk)_

**Doctor:** I'd like to examine your skin and joints.

**Examiner:** On examination, there is a malar rash in a butterfly distribution across the cheeks and nose, sparing the nasolabial folds. Bilateral swelling and tenderness are present in the MCP and PIP joints. _(Level 1 — no risk)_

Marking: **6 of 27** checklist items covered. Missed (first 6):
- [History] Photosensitivity of skin rash
- [History] Presence of oral ulcers
- [History] Systemic symptoms (fatigue, fever)
- [History] Raynaud's phenomenon
- [History] Renal symptoms (frothy urine/edema)
- [History] Chest pain (pleurisy/pericarditis)

**7 passed, 0 failed.**
