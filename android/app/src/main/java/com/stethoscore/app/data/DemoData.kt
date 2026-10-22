package com.stethoscore.app.data

/** Verbatim sample content from iOS PreviewLaunch.swift and CaseSamples.swift at be11a56.
 * Examples are opt-in. They never create study history, accuracy, or completed reviews.
 */
object DemoData {
    val sets: List<StudySet> by lazy { StudyJson.decodeSets(sampleJson) }
    private val sampleJson = """
[
  {
    "name": "Nephrology — glomerular disease",
    "subject": "Nephrology",
    "kind": "mcq",
    "questions": [
      {
        "stem": "A 34-year-old Black man presents with frothy urine, periorbital oedema and 6 g/day proteinuria. Serum albumin is 22 g/L. Which finding on light microscopy is most consistent with the most common primary cause of nephrotic syndrome in this patient?",
        "options": [
          "Normal glomeruli",
          "Segmental sclerosis in some glomeruli",
          "Diffuse thickening of the basement membrane",
          "Mesangial IgA deposits"
        ],
        "correctIndex": 1,
        "explanation": "Focal segmental glomerulosclerosis is the most common primary cause of nephrotic syndrome in Black adults; light microscopy shows sclerosis in some (focal) glomeruli, affecting part (segmental) of the tuft. In older white adults membranous nephropathy (basement membrane thickening) is commoner.",
        "id": "6c8562a8-d3ef-50c8-b58b-c5a179d883fe"
      },
      {
        "stem": "Which glomerular disease is classically associated with hepatitis C infection?",
        "options": [
          "Minimal change disease",
          "Membranous nephropathy",
          "Membranoproliferative glomerulonephritis",
          "Post-streptococcal GN"
        ],
        "correctIndex": 2,
        "explanation": "Hepatitis C causes cryoglobulinaemia, which produces an MPGN pattern with low complement.",
        "id": "53dabd84-6030-52c4-84ba-fa1776ed49dc"
      },
      {
        "stem": "Anti-PLA2R antibodies are most specific for which condition?",
        "options": [
          "Primary membranous nephropathy",
          "Lupus nephritis class V",
          "IgA nephropathy",
          "Anti-GBM disease"
        ],
        "correctIndex": 0,
        "explanation": "Anti-phospholipase A2 receptor antibodies are found in roughly 70–80% of primary membranous nephropathy and are useful for diagnosis and monitoring.",
        "id": "8fde8274-e6b8-5d09-a81e-ff166cc0a5b0"
      }
    ],
    "id": "7092e825-3d62-51a4-920d-3d2dd90bb290"
  },
  {
    "name": "Cardiology — heart failure",
    "subject": "Cardiology",
    "kind": "anki",
    "cards": [
      {
        "type": "qa",
        "front": "Four drug classes with mortality benefit in HFrEF?",
        "bullets": [
          "**ACEi / ARB / ARNI**",
          "**Beta-blockers** (bisoprolol, carvedilol, metoprolol succinate)",
          "**MRA** (spironolactone, eplerenone)",
          "**SGLT2 inhibitors**"
        ],
        "why": "These form the ‘four pillars’; loop diuretics relieve congestion but do not improve survival.",
        "id": "452ee749-80be-5335-a553-fc341661cf6c"
      },
      {
        "type": "cloze",
        "clozeText": "An ejection fraction of {{c1::≤ 40%}} defines HFrEF, while {{c1::≥ 50%}} defines HFpEF.",
        "why": "41–49% is the ‘mildly reduced’ band (HFmrEF).",
        "id": "0cc43cc1-1378-5c4d-805c-38d27f70b373"
      },
      {
        "type": "qa",
        "front": "First-line investigation when heart failure is suspected in primary care?",
        "bullets": [
          "**NT-proBNP** (or BNP)"
        ],
        "why": "A normal natriuretic peptide makes heart failure unlikely; a raised one triggers echocardiography.",
        "id": "c45e82ac-f94e-581f-8120-314c31b2b67e"
      }
    ],
    "id": "fb101e09-6e2f-5bfd-9aa2-f3b14e627ef7"
  },
  {
    "name": "Endocrinology — thyroid",
    "subject": "Endocrinology",
    "kind": "book",
    "bookMarkdown": "## Hyperthyroidism\n\n### Definition\n\n**Thyrotoxicosis** is the clinical state of excess thyroid hormone; **hyperthyroidism** is the subset caused by overproduction by the gland itself.\n\n### Causes and risk factors\n\n| Cause | Clue |\n|---|---|\n| **Graves disease** | Diffuse goitre, eye signs, pretibial myxoedema, TRAb positive |\n| Toxic multinodular goitre | Older patient, nodular gland, no eye signs |\n| Toxic adenoma | Single hot nodule on uptake scan |\n| Thyroiditis | Tender gland, *low* uptake, transient |\n\n> **Exam tip:** Eye signs and pretibial myxoedema point to **Graves** - no other cause gives them.\n\n### Investigations\n\n- **TSH** suppressed, free T4 (± T3) raised\n- TSH-receptor antibodies confirm Graves\n- Radioiodine uptake: high and diffuse in Graves, patchy in MNG, low in thyroiditis\n\n```flow\nSuspected hyperthyroidism\nTSH and free T4\nIf TSH low and FT4 high → primary hyperthyroidism\nTSH-receptor antibodies\nIf positive → Graves disease\nIf negative → uptake scan to find the cause\n```\n\n### Management\n\n- Symptom control: **propranolol**\n- Antithyroid drugs: **carbimazole** first line (propylthiouracil in the first trimester)\n- Definitive: radioiodine or thyroidectomy\n\n> **Red flag:** Warn every patient on antithyroid drugs to report a sore throat or fever at once - **agranulocytosis**.\n\n> **Mnemonic:** Graves' eye signs - **NO SPECS** (No signs, Only signs, Soft tissue, Proptosis, Extraocular muscles, Corneal, Sight loss).\n\n## Hypothyroidism\n\n### Definition\n\nToo little thyroid hormone; in iodine-sufficient countries most often from **Hashimoto's thyroiditis**.\n\n### Clinical features\n\n- Tiredness, weight gain, cold intolerance, constipation\n- **Slow-relaxing reflexes**, dry skin, bradycardia\n\n### Management\n\n- **Levothyroxine**, adjusted to keep TSH in range\n- Start low in the elderly and in ischaemic heart disease\n\n> **Key point:** Recheck TSH 6-8 weeks after any dose change - that is how long it takes to settle.",
    "id": "a91feda1-d189-5658-bf2a-7c08a7b45c32"
  },
  {
    "name": "Skills — venepuncture & catheterisation",
    "subject": "Clinical skills",
    "kind": "osce",
    "osceChecklists": [
      {
        "title": "Venepuncture",
        "steps": [
          "Wash hands and don gloves",
          "Confirm patient identity and explain the procedure, gain consent",
          "Select and clean the venepuncture site",
          "Apply tourniquet",
          "Insert needle at 15–30° and advance until flashback",
          "Release tourniquet before withdrawing needle",
          "Withdraw needle, apply pressure, dispose of sharps safely",
          "Label samples at the bedside and thank the patient"
        ],
        "id": "8dc369a0-d59b-54e7-bd2e-8886f98737f9"
      },
      {
        "title": "Male urinary catheterisation",
        "steps": [
          "Wash hands, explain procedure and gain consent",
          "Position patient supine, expose and drape",
          "Clean the glans with antiseptic, retracting the foreskin if present",
          "Instil local anaesthetic gel and allow it to take effect",
          "Insert catheter fully to the hilt",
          "Inflate balloon only once urine is seen draining",
          "Withdraw gently until resistance is felt, reduce foreskin",
          "Connect to drainage bag and document the procedure"
        ],
        "id": "97779540-af12-53d3-a08a-f9e7fa1ca358"
      }
    ],
    "id": "03392287-1982-53dc-8090-1dd5786110df"
  },
  {
    "name": "Lecture — acid–base physiology",
    "subject": "Renal physiology",
    "kind": "narrate",
    "narrateSegments": [
      {
        "text": "Today we're covering how the body defends its blood pH.",
        "lang": "en",
        "id": "67ed4f03-04c5-5ffe-962f-ebdd4e2ee3ff"
      },
      {
        "text": "Three systems do the work: buffers, the lungs, and the kidneys.",
        "lang": "en",
        "id": "79e51b3d-b84a-5042-95b4-faace58d3b93"
      },
      {
        "text": "Buffers act in seconds, the lungs in minutes, the kidneys over hours to days.",
        "lang": "en",
        "id": "1172681b-1bc7-5f54-9369-41b8ca1c3c83"
      },
      {
        "text": "The bicarbonate buffer system is the one you'll use clinically most often.",
        "lang": "en",
        "id": "d800a639-0df2-5e83-aa94-0872bc7ac71a"
      },
      {
        "text": "Remember the Henderson–Hasselbalch equation links pH to the ratio of bicarbonate to CO2.",
        "lang": "en",
        "id": "d1c6f496-723e-5373-a0f8-9ee50d9ae9e8"
      },
      {
        "text": "A rise in CO2 lowers pH — that's a respiratory acidosis.",
        "lang": "en",
        "id": "d4fc9930-b478-53d0-9e07-f9954575305e"
      },
      {
        "text": "The kidneys compensate slowly, by reabsorbing more bicarbonate.",
        "lang": "en",
        "id": "cb2c46d1-bf7a-5dfd-8449-73a8ae68ef75"
      }
    ],
    "id": "0496062c-21fa-5bb8-a8d5-3f9a52b82d17"
  },
  {
    "name": "Example patients",
    "subject": "Acute medicine",
    "kind": "cases",
    "caseFiles": [
      {
        "id": "CA5E0001-0000-4000-8000-000000000001",
        "title": "Sharp chest pain after a long flight",
        "specialty": "Respiratory",
        "setting": "emergency",
        "patient": {
          "name": "Leah Moreno",
          "age": 34,
          "sex": "F",
          "about": "architect, back from a work trip"
        },
        "complaint": "It hurts on the right when I breathe in, and I can't get my breath since this morning.",
        "clerking": {
          "presenting": "Right-sided pleuritic chest pain and breathlessness since this morning.",
          "history": "Sudden onset on waking, sharp, worse on deep inspiration, not related to exertion. One streak of bright red blood in her sputum this morning. Dry cough, no fever. Flew home from Sydney 3 days ago (about 22 hours in the air).",
          "past": "Nil of note. No previous clots.",
          "drugs": "Combined oral contraceptive pill. No known allergies.",
          "social": "Architect. Never smoked. Alcohol socially."
        },
        "arrival": [
          {
            "sign": "hr",
            "value": 112
          },
          {
            "sign": "bp",
            "value": 118,
            "second": 76
          },
          {
            "sign": "rr",
            "value": 24
          },
          {
            "sign": "spo2",
            "value": 93
          },
          {
            "sign": "temp",
            "value": 37.4
          }
        ],
        "budgetMinutes": 60,
        "steps": [
          {
            "id": "s1",
            "group": "examine",
            "label": "Inspect the chest",
            "finding": "Fast, shallow breathing; she splints the right side on inspiration; both sides expand equally.",
            "minutes": 2,
            "value": "useful",
            "note": "Splinting fits pleural pain; equal expansion makes a large pneumothorax less likely."
          },
          {
            "id": "s2",
            "group": "examine",
            "label": "Examine the legs",
            "finding": "Right calf 3 cm wider than the left, tender along the deep veins, with pitting oedema.",
            "minutes": 3,
            "value": "key",
            "redFlag": true,
            "mustNotMiss": true,
            "note": "Signs of a deep vein thrombosis make pulmonary embolism the leading diagnosis (Wells score above 4)."
          },
          {
            "id": "s3",
            "group": "examine",
            "label": "Listen to the chest",
            "finding": "Equal air entry, clear breath sounds, normal percussion note on both sides.",
            "minutes": 2,
            "value": "useful",
            "note": "A clear chest argues against pneumonia and a pneumothorax."
          },
          {
            "id": "s4",
            "group": "examine",
            "label": "Check the neck veins and heart",
            "finding": "Jugular venous pressure not raised; normal heart sounds; no rub.",
            "minutes": 2,
            "value": "useful",
            "note": "No rub argues against pericarditis; no raised venous pressure, so no sign of right heart strain."
          },
          {
            "id": "s5",
            "group": "examine",
            "label": "Blood pressure in both arms",
            "finding": "118/76 in both arms.",
            "minutes": 2,
            "value": "low",
            "note": "Nothing in the story suggests aortic dissection, so this adds little here."
          },
          {
            "id": "s6",
            "group": "examine",
            "label": "Look in the throat",
            "finding": "Mildly red pharynx; no exudate.",
            "minutes": 2,
            "value": "low",
            "note": "A sore throat is not part of this story and does not explain pleuritic pain."
          },
          {
            "id": "s7",
            "group": "test",
            "label": "12-lead ECG",
            "finding": "Sinus tachycardia at 112 per minute; no ST elevation.",
            "minutes": 5,
            "value": "useful",
            "note": "No sign of a heart attack or pericarditis; tachycardia fits embolism."
          },
          {
            "id": "s8",
            "group": "test",
            "label": "Arterial blood gas on air",
            "finding": "Low oxygen with a low carbon dioxide: type 1 respiratory failure.",
            "minutes": 10,
            "value": "key",
            "redFlag": true,
            "results": [
              {
                "name": "pH",
                "value": 7.47
              },
              {
                "name": "PaO2",
                "value": 8.9,
                "unit": "kPa"
              },
              {
                "name": "PaCO2",
                "value": 4.1,
                "unit": "kPa"
              }
            ],
            "note": "Hypoxaemia with hyperventilation and a clear chest points to a perfusion defect."
          },
          {
            "id": "s9",
            "group": "test",
            "label": "Chest X-ray",
            "finding": "Clear lung fields; no consolidation, effusion or pneumothorax.",
            "minutes": 20,
            "value": "useful",
            "note": "A normal film in a breathless, hypoxic patient makes embolism more likely, not less."
          },
          {
            "id": "s10",
            "group": "test",
            "label": "CRP",
            "finding": "Mildly raised.",
            "minutes": 15,
            "value": "useful",
            "results": [
              {
                "name": "CRP",
                "value": 18,
                "unit": "mg/L",
                "low": 0,
                "high": 5
              }
            ],
            "note": "A mild rise is common in embolism and does not make this pneumonia."
          },
          {
            "id": "s11",
            "group": "test",
            "label": "Troponin",
            "finding": "Slightly raised.",
            "minutes": 15,
            "value": "useful",
            "results": [
              {
                "name": "hs-Troponin T",
                "value": 22,
                "unit": "ng/L",
                "low": 0,
                "high": 14
              }
            ],
            "note": "A small rise is common in embolism; with no ST change and a normal right ventricle it does not change the plan."
          },
          {
            "id": "s12",
            "group": "test",
            "label": "D-dimer",
            "finding": "Raised.",
            "minutes": 15,
            "value": "low",
            "results": [
              {
                "name": "D-dimer",
                "value": 2.1,
                "unit": "mg/L FEU",
                "low": 0,
                "high": 0.5
              }
            ],
            "note": "With embolism likely on the Wells score, a D-dimer changes nothing: go straight to imaging."
          },
          {
            "id": "s13",
            "group": "test",
            "label": "CT pulmonary angiogram",
            "finding": "Filling defects in the right lower lobe pulmonary arteries; right ventricle normal in size.",
            "minutes": 30,
            "value": "key",
            "note": "Confirms the embolism and shows no right ventricular strain."
          }
        ],
        "diagnosis": {
          "name": "Pulmonary embolism",
          "accepted": [
            "PE",
            "Pulmonary thromboembolism"
          ]
        },
        "differentials": [
          {
            "name": "Pulmonary embolism",
            "accepted": [
              "PE",
              "Pulmonary thromboembolism"
            ],
            "supportedBy": [
              "s2",
              "s8",
              "s9",
              "s13"
            ],
            "againstBy": []
          },
          {
            "name": "Pneumonia",
            "accepted": [
              "Community-acquired pneumonia",
              "Chest infection"
            ],
            "supportedBy": [
              "s10"
            ],
            "againstBy": [
              "s3",
              "s9"
            ]
          },
          {
            "name": "Pneumothorax",
            "accepted": [
              "Spontaneous pneumothorax"
            ],
            "supportedBy": [
              "s1"
            ],
            "againstBy": [
              "s3",
              "s9"
            ]
          },
          {
            "name": "Pericarditis",
            "accepted": [
              "Acute pericarditis"
            ],
            "supportedBy": [
              "s11"
            ],
            "againstBy": [
              "s4",
              "s7"
            ]
          }
        ],
        "distractors": [
          "Acute asthma",
          "Panic attack",
          "Aortic dissection"
        ],
        "turningStep": "s2",
        "nextStep": {
          "options": [
            "Start apixaban, a direct oral anticoagulant",
            "Give alteplase for systemic thrombolysis",
            "Insert an inferior vena cava filter today",
            "Start aspirin and arrange outpatient review",
            "Give co-amoxiclav for a chest infection"
          ],
          "key": 0,
          "why": "She has a confirmed embolism and is haemodynamically stable, so she needs anticoagulation; a direct oral anticoagulant such as apixaban is first line. Thrombolysis is kept for embolism with persistent hypotension."
        },
        "teaching": [
          "Pleuritic pain, breathlessness and a swollen tender calf after a long flight make pulmonary embolism the leading diagnosis.",
          "When embolism is likely on the two-level Wells score, go straight to CT pulmonary angiography; a D-dimer is for when it is unlikely.",
          "Stable embolism is treated with anticoagulation, usually a direct oral anticoagulant; thrombolysis is for embolism with shock."
        ],
        "source": {
          "lecture": "Example case",
          "pages": ""
        },
        "verification": "passed"
      },
      {
        "id": "CA5E0002-0000-4000-8000-000000000002",
        "title": "A new headache at 72",
        "specialty": "Rheumatology",
        "setting": "clinic",
        "patient": {
          "name": "Irene Castell",
          "age": 72,
          "sex": "F",
          "about": "retired librarian, lives with her husband"
        },
        "complaint": "I've had this new headache on the right for three weeks, and it even hurts to brush my hair.",
        "clerking": {
          "presenting": "New right-sided headache for 3 weeks.",
          "history": "Constant, worse at night; scalp sore when brushing her hair. Jaw aches after a minute of chewing meat and eases on stopping. Two episodes of blurred vision in the right eye this week, each lasting minutes. Stiff, aching shoulders each morning for 2 months. Lost 3 kg; feels feverish in the evenings. Never had headaches before.",
          "past": "Hypertension. Osteoarthritis of both knees.",
          "drugs": "Amlodipine; paracetamol as needed. No known allergies.",
          "social": "Retired librarian, lives with her husband. Never smoked."
        },
        "arrival": [
          {
            "sign": "hr",
            "value": 78
          },
          {
            "sign": "bp",
            "value": 142,
            "second": 84
          },
          {
            "sign": "rr",
            "value": 14
          },
          {
            "sign": "spo2",
            "value": 97
          },
          {
            "sign": "temp",
            "value": 37.6
          }
        ],
        "budgetMinutes": 50,
        "steps": [
          {
            "id": "s1",
            "group": "examine",
            "label": "Feel the temporal arteries",
            "finding": "Right temporal artery thickened, beaded and tender, with no pulse.",
            "minutes": 2,
            "value": "key",
            "note": "An abnormal temporal artery on examination strongly supports giant cell arteritis."
          },
          {
            "id": "s2",
            "group": "examine",
            "label": "Check acuity and fundi",
            "finding": "Acuity 6/12 in the right eye, 6/9 in the left; the right optic disc is pale and swollen.",
            "minutes": 4,
            "value": "key",
            "redFlag": true,
            "mustNotMiss": true,
            "note": "Ischaemic optic neuropathy has begun: the sight in that eye is at risk now, and the other eye can follow."
          },
          {
            "id": "s3",
            "group": "examine",
            "label": "Swinging light test",
            "finding": "A relative afferent pupillary defect on the right.",
            "minutes": 2,
            "value": "useful",
            "note": "Confirms the right optic nerve is affected."
          },
          {
            "id": "s4",
            "group": "examine",
            "label": "Feel the scalp",
            "finding": "Tender over the right temple and parietal scalp.",
            "minutes": 1,
            "value": "useful",
            "note": "Scalp tenderness is common in giant cell arteritis."
          },
          {
            "id": "s5",
            "group": "examine",
            "label": "Move the shoulders and hips",
            "finding": "Painful, stiff active movement at both shoulders; passive movement better; strength normal.",
            "minutes": 3,
            "value": "useful",
            "note": "Polymyalgia often comes with giant cell arteritis."
          },
          {
            "id": "s6",
            "group": "examine",
            "label": "Neurological examination",
            "finding": "No focal neurological signs; no neck stiffness.",
            "minutes": 4,
            "value": "useful",
            "note": "Argues against a stroke, a mass or meningitis."
          },
          {
            "id": "s7",
            "group": "examine",
            "label": "Look in the ears",
            "finding": "Normal ear canals and eardrums.",
            "minutes": 2,
            "value": "low",
            "note": "An ear problem does not cause jaw claudication or scalp tenderness."
          },
          {
            "id": "s8",
            "group": "test",
            "label": "ESR",
            "finding": "Markedly raised.",
            "minutes": 15,
            "value": "key",
            "results": [
              {
                "name": "ESR",
                "value": 88,
                "unit": "mm/h",
                "low": 0,
                "high": 30
              }
            ],
            "note": "A high ESR supports the diagnosis; a normal one makes it less likely but does not exclude it."
          },
          {
            "id": "s9",
            "group": "test",
            "label": "CRP",
            "finding": "Raised.",
            "minutes": 15,
            "value": "useful",
            "results": [
              {
                "name": "CRP",
                "value": 64,
                "unit": "mg/L",
                "low": 0,
                "high": 5
              }
            ],
            "note": "Inflammatory markers are raised in almost every case."
          },
          {
            "id": "s10",
            "group": "test",
            "label": "Full blood count",
            "finding": "Mild normocytic anaemia; platelets raised.",
            "minutes": 15,
            "value": "useful",
            "results": [
              {
                "name": "Haemoglobin",
                "value": 11.2,
                "unit": "g/dL"
              },
              {
                "name": "Platelets",
                "value": 452,
                "unit": "×10⁹/L",
                "low": 150,
                "high": 400
              }
            ],
            "note": "Anaemia of inflammation and a reactive thrombocytosis are common."
          },
          {
            "id": "s11",
            "group": "test",
            "label": "Temporal artery ultrasound",
            "finding": "A halo around the right temporal artery that does not compress.",
            "minutes": 20,
            "value": "useful",
            "note": "The halo sign supports the diagnosis; it stays visible for the first days of steroids, so it never delays them."
          },
          {
            "id": "s12",
            "group": "test",
            "label": "CT head",
            "finding": "No intracranial abnormality.",
            "minutes": 30,
            "value": "low",
            "note": "A brain scan does not look at the inflamed arteries, and waiting for it delays treatment."
          },
          {
            "id": "s13",
            "group": "test",
            "label": "Urine dipstick",
            "finding": "Normal.",
            "minutes": 5,
            "value": "low",
            "note": "Nothing in the story points to the kidneys."
          }
        ],
        "diagnosis": {
          "name": "Giant cell arteritis",
          "accepted": [
            "Temporal arteritis",
            "GCA"
          ]
        },
        "differentials": [
          {
            "name": "Giant cell arteritis",
            "accepted": [
              "Temporal arteritis",
              "GCA"
            ],
            "supportedBy": [
              "s1",
              "s2",
              "s4",
              "s8",
              "s11"
            ],
            "againstBy": []
          },
          {
            "name": "Polymyalgia rheumatica",
            "accepted": [
              "PMR"
            ],
            "supportedBy": [
              "s5",
              "s8"
            ],
            "againstBy": [
              "s1",
              "s2",
              "s11"
            ]
          },
          {
            "name": "Tension-type headache",
            "accepted": [
              "Tension headache"
            ],
            "supportedBy": [
              "s4"
            ],
            "againstBy": [
              "s1",
              "s8",
              "s11"
            ]
          }
        ],
        "distractors": [
          "Trigeminal neuralgia",
          "Acute angle-closure glaucoma",
          "Sinusitis"
        ],
        "turningStep": "s1",
        "nextStep": {
          "options": [
            "Start high-dose steroids today, before a biopsy",
            "Arrange a temporal artery biopsy, then treat",
            "Prescribe sumatriptan and review in a week",
            "Request an MRI brain and wait for the result",
            "Start amitriptyline at night for the pain"
          ],
          "key": 0,
          "why": "Treatment starts on suspicion, the same day, because sight is already threatened; with visual loss the guideline advises intravenous methylprednisolone and same-day eye and rheumatology review. A biopsy or ultrasound still confirms the diagnosis in the first one to two weeks of steroids."
        },
        "teaching": [
          "A new headache after 50 with jaw claudication or scalp tenderness is giant cell arteritis until proven otherwise.",
          "Visual symptoms, and a pale swollen optic disc above all, make treatment an emergency: steroids start the same day.",
          "Never wait for a biopsy or ultrasound to treat; both stay informative in the first one to two weeks of steroids."
        ],
        "source": {
          "lecture": "Example case",
          "pages": ""
        },
        "verification": "passed"
      }
    ],
    "id": "47f4f47f-abf4-5039-b7a9-40f366af6c0d"
  }
]
    """.trimIndent()
}
