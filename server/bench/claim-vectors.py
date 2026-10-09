#!/usr/bin/env python3
"""Make server/tests/claim-vectors.json: what the Chat-me medical verifier's
deterministic guards say about a fixed set of claims and passages, so that
server/claims.js, their JavaScript port, can be held to the same answers
(server/tests/claims.test.mjs).

The verifier is Chat-me's at ff476bd (branch personal, MIT), in
agents/specialists/verification_agent/. Run against a checkout of it:

    git -C <Chat-me> worktree add /tmp/cm ff476bd
    python3 server/bench/claim-vectors.py /tmp/cm > server/tests/claim-vectors.json

Standard library only, besides the verifier's own modules; nothing is
fetched and nothing needs a key. The corpus is the verifier's 41 shared
conformance vectors (answer against passage) and the pairs below, written
the way Stethoscore's cards, questions and lectures are.
"""
import json
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(root))

from agents.specialists.verification_agent import claim_reasoning as cr  # noqa: E402
from agents.specialists.verification_agent import consistency as consistency  # noqa: E402
from agents.specialists.verification_agent import direction  # noqa: E402
from agents.specialists.verification_agent import independent_entailment as ie  # noqa: E402
from agents.specialists.verification_agent import independent_entailment_base as base  # noqa: E402
from agents.specialists.verification_agent import semantic_guard as sg  # noqa: E402
from agents.specialists.verification_agent.entity_normalization import entities_equivalent  # noqa: E402
from agents.specialists.verification_agent.temporal_normalization import extract_explicit_dates  # noqa: E402

VECTORS = root / "clients/ios/MedicalVerifierCore/Tests/MedicalVerifierCoreTests/Resources/conformance_vectors.json"

PAIRS = [
    # doses, units, frequencies
    ("Amoxicillin 500 mcg orally three times daily for otitis media.", "Amoxicillin 500 mg orally three times daily for otitis media."),
    ("Amoxicillin 500 mg orally three times daily for otitis media.", "Amoxicillin 500 mg orally three times daily for otitis media."),
    ("Amoxicillin 500 mg twice daily for otitis media.", "Amoxicillin 500 mg three times daily for otitis media."),
    ("Amoxicillin 875 mg every 12 hours.", "Amoxicillin 500 mg every 8 hours or 875 mg every 12 hours."),
    ("Give 1 g of paracetamol every 6 hours.", "Paracetamol 1000 mg every 6 hours, maximum 4 g daily."),
    ("Give 2.5 mg of salbutamol nebulised.", "Salbutamol 5 mg nebulised in acute asthma."),
    ("Digoxin 125 mcg once daily.", "Digoxin 0.125 mg daily for rate control."),
    ("Ceftriaxone 2 g IV every 12 hours for meningitis.", "Ceftriaxone 2 g IV every 12 hours in bacterial meningitis."),
    ("Vancomycin 15 mg/kg every 12 hours.", "Ceftriaxone 2 g every 12 hours for meningitis."),
    ("The daily dose is 1500 mg.", "Take 500 mg three times daily."),
    ("Give 10 mL of a 5 mg/mL solution twice daily.", "The daily dose is 100 mg."),
    ("Use 10 mg/kg/day for a 30 kg child.", "The daily dose is 300 mg for a 30 kg child."),
    ("Levothyroxine 100 micrograms daily.", "Levothyroxine 100 mcg daily."),
    ("Alendronate 70 mg once a week.", "Alendronate 70 mg weekly."),
    ("Methotrexate 15 mg twice a week.", "Methotrexate 15 mg once a week."),
    ("Insulin infusion at 0.1 units/kg/hour.", "Insulin 0.1 units/kg/hour in DKA."),
    ("Gentamicin q8h dosing.", "Gentamicin every 8 hours."),
    ("Metformin 500 mg bid.", "Metformin 500 mg twice a day."),
    # percentages and statistics
    ("Aspirin reduces mortality by 23 percent.", "Aspirin reduces mortality by 23 percent in acute MI."),
    ("Aspirin reduces mortality by 50 percent.", "Aspirin reduces mortality by 23 percent in acute MI."),
    ("Statins reduce events by 25%.", "Statins reduce events by 25% overall."),
    ("The drug lowers risk by 5 percentage points.", "The drug lowers risk by 5 percent."),
    ("The hazard ratio was 0.75.", "The odds ratio was 0.75."),
    # negation and double negation
    ("Metformin is not first-line in type 2 diabetes.", "Metformin is first-line in type 2 diabetes."),
    ("Insulin lowers blood glucose.", "Insulin lowers blood glucose, with no effect on potassium."),
    ("Insulin does not lower blood glucose.", "Insulin lowers blood glucose."),
    ("Hypoglycaemia is not uncommon with sulfonylureas.", "Hypoglycaemia is common with sulfonylureas."),
    ("Beta blockers do not cause bronchospasm.", "Beta blockers cause bronchospasm in asthma."),
    ("Smoking is not associated with lung cancer.", "Smoking is associated with lung cancer."),
    ("Aspirin should not be given to children under 16.", "Aspirin should be given to children with Kawasaki disease."),
    # scope, population, conditions
    ("Metformin always lowers HbA1c.", "Metformin lowers HbA1c in most patients."),
    ("Only ACE inhibitors reduce proteinuria.", "ACE inhibitors reduce proteinuria."),
    ("Warfarin is safe in all patients.", "Warfarin is safe in selected patients."),
    ("Doxycycline is safe in children.", "Doxycycline is safe in adults."),
    ("Methotrexate is contraindicated in pregnancy.", "Methotrexate is contraindicated in pregnancy and breastfeeding."),
    ("Reduce the dose if renal impairment is severe.", "Reduce the dose if renal impairment is severe."),
    ("Reduce the dose.", "Reduce the dose if renal impairment is severe."),
    ("In patients with heart failure, avoid verapamil.", "Avoid verapamil in patients with heart failure."),
    # relations: causal, association, interaction, contraindication, safety, effectiveness
    ("Smoking causes lung cancer.", "Smoking is associated with lung cancer."),
    ("Smoking causes lung cancer.", "Smoking causes lung cancer."),
    ("Clarithromycin interacts with simvastatin.", "Clarithromycin has an interaction with simvastatin."),
    ("Clarithromycin interacts with simvastatin.", "Clarithromycin is associated with simvastatin."),
    ("Trimethoprim is contraindicated in the first trimester.", "Trimethoprim is associated with the first trimester."),
    ("Ibuprofen increases bleeding risk with warfarin.", "Ibuprofen increases bleeding risk with warfarin."),
    ("Ibuprofen reduces bleeding risk with warfarin.", "Ibuprofen increases bleeding risk with warfarin."),
    ("Paracetamol reduces fever.", "Acetaminophen reduces fever."),
    ("Paracetamol reduces fever.", "Paracetamol reduces fevers."),
    ("Drug A increases bleeding and Drug A reduces blood pressure.", "Drug A increases bleeding. Drug A reduces blood pressure."),
    ("Ethosuximide is effective for absence seizures.", "Ethosuximide works for absence seizures."),
    ("Lithium is dangerous in renal failure.", "Lithium is harmful in renal failure."),
    # temporal
    ("The patient previously took warfarin.", "The patient currently takes warfarin."),
    ("The guideline changed on 2024-03-01.", "The guideline changed on 2024-03-01."),
    ("The guideline changed on 2024-03-01.", "The guideline changed on 2023-03-01."),
    ("The label was updated 2024/02/30.", "The label was updated in 2024."),
    ("Give antibiotics within 1 hour of sepsis recognition.", "Give antibiotics within 1 hour in sepsis."),
    ("Give antibiotics after cultures are taken.", "Give antibiotics before cultures are taken."),
    # which way: turned around, a way the evidence never gives, the same way
    # in other words, a part's name, a cut-off, a comparison either way round
    ("Statin therapy is associated with a reduced risk of new-onset diabetes.", "Statin therapy is associated with a modestly increased risk of new-onset diabetes."),
    ("Statins have a high incidence of clinically apparent liver injury.", "Clinically apparent liver injury attributed to statins is rare."),
    ("SGLT2 inhibitors have a lower risk of genital infection.", "SGLT2 inhibitors have a higher risk of genital infection."),
    ("Hyperkalaemia is a common side effect of spironolactone.", "Hyperkalaemia is a rare side effect of spironolactone."),
    ("Vitamin K has a stronger anticoagulant effect on warfarin.", "Vitamin K interacts with warfarin, whose anticoagulant activity depends on vitamin K."),
    ("Statins lower LDL cholesterol.", "Statins are effective in lowering LDL cholesterol."),
    ("Statin-associated myopathy is uncommon.", "Myopathy is listed as a rare adverse effect of statins."),
    ("Metformin lowers blood glucose.", "Metformin is a glucose-lowering drug."),
    ("Metformin does not increase lactate.", "Metformin increases lactate."),
    ("Low-dose aspirin is given after the stent.", "Aspirin is given after the stent."),
    ("Lower limb ischaemia needs urgent review.", "Lower limb ischaemia needs urgent vascular review."),
    ("Metformin is contraindicated when eGFR is below 30 mL/min.", "Metformin is contraindicated when eGFR is < 30 mL/min."),
    ("The dose is halved when eGFR is below 45 mL/min.", "The dose is halved when eGFR is above 45 mL/min."),
    ("Warfarin has a higher risk of intracranial hemorrhage than DOACs.", "DOACs have a lower risk of intracranial hemorrhage than warfarin."),
    ("DOACs have a higher rate of recurrent intracranial hemorrhage than warfarin.", "DOACs had a lower risk of recurrent intracranial hemorrhage than warfarin."),
    ("Gout is less common in women than in men.", "Gout is more common in men than in women."),
    ("Gout is more common in women than in men.", "Gout is more common in men than in women."),
    ("Risk is higher in women than in the elderly.", "Risk is lower in the young than in women."),
    # multilingual, as the verifier knows it, whole words only
    ("El tratamiento reduce el riesgo.", "El tratamiento reduce el riesgo en adultos."),
    ("Le traitement réduit le risque.", "Le traitement ne réduit pas le risque."),
    ("Smoking has a causal role in lung cancer.", "Smoking causes lung cancer."),
    # Stethoscore-shaped: card answers against lecture sentences
    ("Dose of amoxicillin for otitis media: 500 mg PO three times a day.", "Amoxicillin is first-line for acute otitis media."),
    ("Antidote to warfarin: vitamin K and prothrombin complex concentrate.", "PCC reverses warfarin within minutes; vitamin K acts over hours."),
    ("Adrenaline 0.5 mg IM for anaphylaxis in adults.", "Adrenaline 0.5 mg IM (1 mg/mL) is given for anaphylaxis in adults."),
    ("Adrenaline 0.5 mg IV for anaphylaxis in adults.", "Adrenaline 0.5 mg IM is given for anaphylaxis in adults."),
    ("Primary PCI is the treatment of choice for STEMI.", "Primary PCI within 120 minutes is the treatment of choice for STEMI."),
    ("Normal potassium is 3.5-5.0 mmol/L.", "Normal potassium is 3.5 to 5.0 mmol/L."),
    ("Sodium 128 mmol/L indicates hyponatraemia.", "Sodium below 135 mmol/L is hyponatraemia."),
    ("A 30-year-old with fever and neck stiffness has meningitis.", "Meningitis presents with fever and neck stiffness."),
    ("", "Anything."),
    ("Short.", ""),
]

ENTITIES = [("paracetamol", "acetaminophen"), ("Paracetamol", " acetaminophen "), ("ibuprofen", "Ibuprofen"), ("aspirin", "aspirin"), ("pains", "pain")]


class Passage:
    """What semantic_guard and guard_specificity read (title, passage) and set."""

    def __init__(self, passage):
        self.title = ""
        self.passage = passage
        self.supports = True
        self.quality_score = 1.0


def atom(a):
    return {"text": a.text, "relation": a.relation, "polarity": a.polarity, "temporal": list(a.temporal),
            "safety": a.safety, "subject": list(a.subject_terms), "object": list(a.object_terms)}


def facts(text):
    return {
        "double_negation": base._normalize_double_negation(text),
        "tokens": sorted(base._tokens(text)),
        "relation_class": base._relation_class(text),
        "numbers": sorted(base._numbers(text)),
        "measurements": sorted([v, u] for v, u in base._measurements(text)),
        "frequency": base._frequency_multiplier(text),
        "frequency_guard": sg._frequency_multiplier(text),
        "daily_dose": base._daily_dose_equivalent(text),
        "measurement_kind": base._measurement_kind(text),
        "populations": sorted(base._populations(text)),
        "conditions": [sorted(s) for s in base._condition_signatures(text)],
        "scope": base._scope_strength(text),
        "quantities": [[v, u] for v, u in sg._quantities(text.lower())],
        "percents": sg._percents(text.lower()),
        "dates": [d.isoformat() for d in extract_explicit_dates(text)],
        "temporal": list(cr.temporal_signature(text)),
        "safety": cr.safety_relation(text),
        "atoms": [atom(a) for a in cr.decompose_claim(text)],
        "directions": direction.directions(text),
        "stated_directions": direction.directions(text, cut_offs=False),
    }


def judge(claim, evidence, source):
    verdict = ie.verify(claim, evidence)
    _, semantic = sg.semantic_guard(Passage(evidence), claim)
    _, specificity = consistency.guard_specificity(Passage(evidence), claim)
    ok, reason = base._condition_supported(claim, evidence)
    return {
        "source": source, "claim": claim, "evidence": evidence,
        "verify": {"label": verdict.label, "reasons": list(verdict.reasons)},
        "opposite": cr.opposite_polarity_entailed(claim, evidence),
        "condition": [ok, reason],
        "direction": list(direction.direction_entailed(claim, evidence)),
        "semantic": semantic,
        "specificity": specificity,
        "claim_facts": facts(claim),
        "evidence_facts": facts(evidence),
    }


def main():
    vectors = json.loads(VECTORS.read_text())
    pairs = [judge(c["answer"], c["source_passage"], f"conformance:{c['id']}") for c in vectors["cases"]]
    pairs += [judge(claim, evidence, "stethoscore") for claim, evidence in PAIRS]
    out = {
        "verifier": "Chat-me ff476bd (personal, agents/specialists/verification_agent)",
        "conformance_version": vectors["version"],
        "pairs": pairs,
        "entities": [[a, b, entities_equivalent(a, b)] for a, b in ENTITIES],
    }
    json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
