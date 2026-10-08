#!/usr/bin/env bash
# Downloads the official sources the source-proof mutation bench reads
# (proof-mutations.mjs), with no key: three openFDA drug labels for each of
# 20 drugs and the MedlinePlus health-topic summaries for 32 conditions.
# Usage: tools/verification-bench/fetch-proof.sh [DIR]  (gives DIR/fda, DIR/mlp)
set -euo pipefail
out="${1:-proof-bench-data}"
mkdir -p "$out/fda" "$out/mlp"
for d in acetaminophen amlodipine amoxicillin atorvastatin digoxin furosemide gabapentin heparin ibuprofen insulin \
         levothyroxine lisinopril lithium methotrexate morphine omeprazole prednisone sertraline vancomycin warfarin; do
  curl -sf "https://api.fda.gov/drug/label.json?search=openfda.generic_name:%22$d%22&limit=3" -o "$out/fda/$d.json" || echo "no label: $d"
done
for t in asthma heart_failure anemia appendicitis atrial_fibrillation cirrhosis copd dementia depression diabetes epilepsy gout \
         heart_attack hepatitis_b hypertension hypothyroidism influenza kidney_disease lupus malaria measles migraine \
         multiple_sclerosis osteoporosis pancreatitis parkinson_s_disease pneumonia psoriasis schizophrenia sepsis stroke tuberculosis; do
  curl -sf "https://wsearch.nlm.nih.gov/ws/query?db=healthTopics&retmax=2&term=$(echo "$t" | sed 's/_s_/%27s+/; s/_/+/g')" -o "$out/mlp/$t.xml" || echo "no summary: $t"
  sleep 1
done
ls "$out/fda" "$out/mlp" | wc -l
