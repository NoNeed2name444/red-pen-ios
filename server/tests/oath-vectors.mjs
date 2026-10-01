// The oath check's dose vectors, shared with the app's AccuracyTests.swift
// (the same texts and answers, so the Worker and the phone agree on what a
// dose is). Not a test file of its own: imported by accuracy.test.mjs.
export const DOSE_VECTORS = [
  ['Give amoxicillin 500 mg PO three times a day', true],
  ['Start IV ceftriaxone 2 g once daily', true],
  ['Paracetamol 15 mg/kg every 6 hours', true],
  ['Enoxaparin 1 mg/kg twice daily', true],
  ['Adrenaline IM 0.5 mg', true],
  ['Insulin 10 units at night nocte', true],
  ['Give 1 g stat', true],
  ['Potassium 6.8 mmol/L, glucose 250 mg/dL', false],
  ['A 45-year-old man weighing 80 kg presents', false],
  ['Haemoglobin 9 g/dL with low MCV', false],
  ['What is the most likely diagnosis?', false],
  ['The mechanism of aspirin', false],
];
