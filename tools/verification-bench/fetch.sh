#!/usr/bin/env bash
# Downloads the public exam questions the verification bench runs on, from the
# Hugging Face datasets server (no key): MedMCQA validation (Apache-2.0),
# MedQA USMLE test (GBaker mirror, CC-BY-4.0), MedXpertQA Text test
# (expert level, specialty boards; MIT) and CareQA English test (Spain's
# specialist-training exams; Apache-2.0).
set -euo pipefail
out="${1:-verification-bench-data}"
mkdir -p "$out"
rows() { curl -sf "https://datasets-server.huggingface.co/rows?dataset=$1&config=$2&split=$3&offset=$4&length=100" -o "$out/$5_$4.json"; }
for off in $(seq 0 100 2300); do rows openlifescienceai/medmcqa default validation "$off" medmcqa & done; wait
for off in $(seq 0 100 1200); do rows GBaker/MedQA-USMLE-4-options default test "$off" medqa & done; wait
for off in $(seq 0 100 2400); do rows TsinghuaC3I/MedXpertQA Text test "$off" medxpertqa & done; wait
for off in $(seq 0 100 2700); do rows HPAI-BSC/CareQA CareQA_en test "$off" careqa & done; wait
ls "$out" | wc -l
