// The accuracy engine's pure parts on the phone: the rule checks (the same
// cases as server/tests/accuracy.test.mjs, since the two ports must agree),
// the accuracy model's inference and grades, the content hash the cache is
// kept by, the order background checks run in, and one-tap corrections.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func card(_ text: String) -> AccuracyItem { AccuracyItem(id: "x", kind: .card, text: text) }
func ids(_ item: AccuracyItem) -> [String] { AccuracyRules.hits(item).map { $0.rule + ":" + $0.severity } }
func has(_ item: AccuracyItem, _ prefix: String) -> Bool { ids(item).contains { $0.hasPrefix(prefix) } }

// MARK: rules - the same cases as the server's

check("paracetamol 10 g is a severe dose error", has(card("Give paracetamol 10 g orally for fever."), "dose-range:severe"))
check("metformin 500 mg is fine", !has(card("Metformin 500 mg twice daily with meals."), "dose-range"))
check("digoxin 25 mg is severe", has(card("Digoxin 25 mg once daily for rate control."), "dose-range:severe"))
check("adrenaline 0.5 mg IM is fine", !has(card("Adrenaline 0.5 mg IM for anaphylaxis."), "dose-range"))
check("a per-kg dose is left alone", !has(card("Vancomycin 15 mg/kg every 12 hours."), "dose-range"))
check("a dose before the drug is read", AccuracyRules.doses("500 mg of amoxicillin three times a day").first?.mg == 500)
check("micrograms are converted", AccuracyRules.doses("levothyroxine 100 micrograms daily").first?.mg == 0.1)
check("atorvastatin 800 mg is severe", has(card("Atorvastatin 800 mg at night."), "dose-range:severe"))
check("glucose 5.5 mg/dL is impossible", has(card("Fasting glucose 5.5 mg/dL is normal."), "lab-implausible"))
check("sodium 128 mmol/L is fine", !has(card("Sodium 128 mmol/L indicates hyponatraemia."), "lab"))
check("sodium in mg/dL is the wrong unit", has(card("Sodium 140 mg/dL is normal."), "lab-unit"))
check("a wrong reference range is severe", has(card("Normal potassium is 5.5-7.5 mmol/L."), "reference-range:severe"))
check("the right reference range passes", !has(card("Normal potassium is 3.5-5.0 mmol/L."), "reference-range"))
check("pH and PaCO2 are read", AccuracyRules.labValues("pH 7.21 and PaCO2 60 mmHg").count == 2)
check("one analyte raised and lowered", has(card("In SIADH sodium is low. Sodium is elevated in SIADH."), "direction-conflict"))
check("vitamin K is not potassium", !has(card("Vitamin K 10 mg IV reverses warfarin."), "lab"))

let q = AccuracyItem(id: "q", kind: .mcq,
                     stem: "A 60-year-old man has crushing chest pain. Which drug reduces mortality first?",
                     options: ["Aspirin", "Morphine", "Oxygen", "Nitrates", "Furosemide"], key: 0,
                     explanation: "Aspirin reduces mortality in acute coronary syndrome.")
check("a clean question has no hits", AccuracyRules.hits(q).isEmpty, "\(ids(q))")
var q2 = q; q2.explanation = "The correct answer is B. Morphine relieves pain."
check("an explanation naming another letter", has(q2, "key-explanation-conflict:severe"))
q2.explanation = "Morphine is the correct answer here."
check("or another option's words", has(q2, "key-explanation-conflict"))
q2.explanation = "Aspirin is not the correct answer here."
check("an explanation calling the key wrong", has(q2, "key-called-wrong"))
var q3 = q; q3.options = ["Aspirin", "aspirin", "Oxygen", "Nitrates", "Furosemide"]
check("a duplicate of the key is severe", has(q3, "duplicate-option:severe"))
q3.options = ["Aspirin", "All of the above", "Oxygen", "Nitrates", "None of the above"]
check("all of the above not last", has(q3, "non-answer-position"))
q3.options = ["Aspirin", "Morphine", "Oxygen", "None of the above", "All of the above"]; q3.key = 4
check("all of the above keyed beside none of the above", has(q3, "all-above-contradiction"))
var q4 = q; q4.key = 7
check("a key outside the options", has(q4, "no-key:severe"))
let numbers = AccuracyItem(id: "n", kind: .mcq, stem: "A woman has sodium 118 mmol/L after a marathon. What is the cause?",
                           options: ["Water excess", "Salt loss"], key: 0, explanation: "Her sodium of 128 mmol/L reflects water excess.")
check("stem and explanation disagree on a value", has(numbers, "numbers-disagree"))
let except = AccuracyItem(id: "e", kind: .mcq, stem: "Which is NOT a feature of nephrotic syndrome?",
                          options: ["Haematuria", "Proteinuria"], key: 0, explanation: "Haematuria is a characteristic feature.")
check("an EXCEPT question whose explanation calls the key true", has(except, "negation-mismatch"))
check("the explanation's letter is read", AccuracyRules.explainedAnswer("Ans. is the correct answer: (C) because", options: ["a", "b", "c"]) == 2)
check("the source match", AccuracyRules.sourceMatch(AccuracyItem(id: "s", kind: .card, text: "Aspirin reduces mortality", source: "aspirin reduces mortality in ACS")) == 1
      && AccuracyRules.sourceMatch(card("x")) == nil)
check("the tables are read", AccuracyRules.drugs.count > 100 && AccuracyRules.drugs["digoxin"] == [0.0625, 1.5]
      && AccuracyRules.labs["glucose"]?["mmol/l"] == [0.5, 140, 3.9, 5.6])

// MARK: the model

let pass = AccuracyModel.featureValues(kind: .mcq, rules: [], votes: [AccuracyVote(model: "gemini-3.5-flash-lite", risk: 1, answer: "A", evidence: "supports", blind: true),
                                                                      AccuracyVote(model: "@cf/openai/gpt-oss-120b", risk: 1, answer: "A", evidence: "supports", blind: true)],
                                       evidenceCount: 3, sourceMatch: 0.7, keyLetter: "A")
let p1 = AccuracyModel.probability(pass)
check("two blind solves from two families reach the key, with support: Verified", p1 > 0.95 && AccuracyModel.grade(p1, pass) == .verified, "\(p1)")
// the briefs' rules for questions, as the server has them (server/accuracy-model.js verdict)
func mcqVotes(_ votes: [AccuracyVote]) -> [String: Double] {
    AccuracyModel.featureValues(kind: .mcq, rules: [], votes: votes, evidenceCount: 3, sourceMatch: 0.7, keyLetter: "A")
}
let anchoredF = mcqVotes([AccuracyVote(model: "gemini-3.5-flash-lite", risk: 1, answer: "A", evidence: "supports"),
                          AccuracyVote(model: "@cf/openai/gpt-oss-120b", risk: 1, answer: "A", evidence: "supports")])
check("votes that saw the key do not verify a question", AccuracyModel.grade(AccuracyModel.probability(anchoredF), anchoredF) == .check)
let againstF = mcqVotes([AccuracyVote(model: "gemini-3.5-flash-lite", risk: 1, answer: "C", blind: true),
                         AccuracyVote(model: "@cf/openai/gpt-oss-120b", risk: 1, answer: "C", blind: true),
                         AccuracyVote(model: "@cf/nvidia/nemotron-3-120b-a12b", risk: 1, answer: "A", evidence: "supports")])
check("two families solving it blind agree on another answer: Flagged", againstF["blind_against"] == 2
      && AccuracyModel.grade(AccuracyModel.probability(againstF), againstF) == .flagged)
let oneFamilyBlind = mcqVotes([AccuracyVote(model: "gemini-3.5-flash-lite", risk: 1, answer: "A", evidence: "supports", blind: true),
                               AccuracyVote(model: "gemma-4-31b-it", risk: 1, answer: "A", evidence: "supports", blind: true)])
check("two blind solves from one family are one witness", oneFamilyBlind["blind_agree"] == 1
      && AccuracyModel.grade(AccuracyModel.probability(oneFamilyBlind), oneFamilyBlind) == .check)
let decodedBlind = try? JSONDecoder().decode(AccuracyVote.self, from: Data(#"{"model":"m","risk":1,"answer":"A","blind":true}"#.utf8))
check("the blind mark comes from the server's reply", decodedBlind?.blind == true)
// two votes from one family are one witness (independence), as on the server
let oneFamily = AccuracyModel.featureValues(kind: .card, rules: [], votes: [AccuracyVote(model: "gemini-3.5-flash-lite", risk: 1, evidence: "supports"),
                                                                           AccuracyVote(model: "gemma-4-31b-it", risk: 1, evidence: "supports")],
                                            evidenceCount: 3, sourceMatch: 0.9, keyLetter: nil)
check("two passing votes from one family (Gemini and Gemma) are Check this", oneFamily["families"] == 1 && AccuracyModel.grade(0.99, oneFamily) == .check)
check("families: Gemma and Gemini are Google, gpt-oss OpenAI, Nemotron NVIDIA",
      AccuracyModel.familyOf("gemma-4-31b-it") == "google" && AccuracyModel.familyOf("@cf/openai/gpt-oss-120b") == "openai"
      && AccuracyModel.familyOf("@cf/nvidia/nemotron-3-120b-a12b") == "nvidia")
let bad = AccuracyModel.featureValues(kind: .mcq, rules: [], votes: [AccuracyVote(risk: 4, answer: "B", evidence: "contradicts"),
                                                                     AccuracyVote(risk: 4, answer: "B", evidence: "contradicts")],
                                      evidenceCount: 0, sourceMatch: 0.7, keyLetter: "A")
check("two flagging votes are Flagged", AccuracyModel.grade(AccuracyModel.probability(bad), bad) == .flagged)
let split = AccuracyModel.featureValues(kind: .mcq, rules: [], votes: [AccuracyVote(risk: 1, answer: "A"), AccuracyVote(risk: 3, answer: "A")],
                                        evidenceCount: 0, sourceMatch: 0.5, keyLetter: "A")
check("a split vote is Check this", AccuracyModel.grade(AccuracyModel.probability(split), split) == .check)
let none = AccuracyModel.featureValues(kind: .card, rules: [], votes: [], evidenceCount: 0, sourceMatch: nil, keyLetter: nil)
check("rules alone never verify", AccuracyModel.grade(AccuracyModel.probability(none), none) == .unchecked)
let severe = [AccuracyRules.Hit(rule: "dose-range", severity: "severe", detail: "")]
let ruled = AccuracyModel.featureValues(kind: .card, rules: severe, votes: [], evidenceCount: 0, sourceMatch: nil, keyLetter: nil)
check("a severe rule with no model is Flagged", AccuracyModel.grade(AccuracyModel.probability(ruled), ruled) == .flagged)
let passRuled = AccuracyModel.featureValues(kind: .card, rules: severe, votes: [AccuracyVote(risk: 1, evidence: "supports"), AccuracyVote(risk: 1, evidence: "supports")],
                                            evidenceCount: 5, sourceMatch: 1, keyLetter: nil)
check("a severe rule is never Verified", AccuracyModel.grade(AccuracyModel.probability(passRuled), passRuled) != .verified)

// one model's word is never enough, and the oath check (server/tests/accuracy.test.mjs, case for case)
let lone = AccuracyModel.featureValues(kind: .card, rules: [], votes: [AccuracyVote(risk: 1, evidence: "supports")],
                                       evidenceCount: 3, sourceMatch: 0.9, keyLetter: nil)
check("a single vote, however sure, is Check this, never Verified", AccuracyModel.grade(0.99, lone) == .check)
let unbacked = AccuracyModel.featureValues(kind: .card, rules: [], votes: [AccuracyVote(model: "gemini-3.5-flash-lite", risk: 1, evidence: "none"), AccuracyVote(model: "@cf/openai/gpt-oss-120b", risk: 1, evidence: "none")],
                                           evidenceCount: 0, sourceMatch: 0.2, keyLetter: nil)
check("an oath item with two votes but no support stays Check this",
      AccuracyModel.grade(0.99, unbacked) == .verified && AccuracyModel.grade(0.99, unbacked, oath: true) == .check)
let literature = AccuracyModel.featureValues(kind: .card, rules: [], votes: [AccuracyVote(model: "gemini-3.5-flash-lite", risk: 1, evidence: "supports"), AccuracyVote(model: "@cf/openai/gpt-oss-120b", risk: 1, evidence: "none")],
                                             evidenceCount: 2, sourceMatch: 0.2, keyLetter: nil)
let lecture = AccuracyModel.featureValues(kind: .card, rules: [], votes: [AccuracyVote(model: "gemini-3.5-flash-lite", risk: 1, evidence: "none"), AccuracyVote(model: "@cf/openai/gpt-oss-120b", risk: 1, evidence: "none")],
                                          evidenceCount: 0, sourceMatch: AccuracyModel.oathSourceMatch, keyLetter: nil)
check("with the literature or its own lecture behind it, an oath item can be Verified",
      AccuracyModel.grade(0.99, literature, oath: true) == .verified && AccuracyModel.grade(0.99, lecture, oath: true) == .verified)
// server/tests/oath-vectors.mjs, text for text
let doseVectors: [(String, Bool)] = [
    ("Give amoxicillin 500 mg PO three times a day", true),
    ("Start IV ceftriaxone 2 g once daily", true),
    ("Paracetamol 15 mg/kg every 6 hours", true),
    ("Enoxaparin 1 mg/kg twice daily", true),
    ("Adrenaline IM 0.5 mg", true),
    ("Insulin 10 units at night nocte", true),
    ("Give 1 g stat", true),
    ("Potassium 6.8 mmol/L, glucose 250 mg/dL", false),
    ("A 45-year-old man weighing 80 kg presents", false),
    ("Haemoglobin 9 g/dL with low MCV", false),
    ("What is the most likely diagnosis?", false),
    ("The mechanism of aspirin", false),
]
for (text, dose) in doseVectors {
    check("dose \(dose ? "found" : "not found"): \(text)", AccuracyModel.hasDose(text) == dose)
}
check("a diagnosis, a treatment or a dose makes an oath item; a mechanism does not",
      AccuracyModel.isOath("What is the most likely diagnosis?") && AccuracyModel.isOath("What is the next best step in management?")
      && AccuracyModel.isOath("Give amoxicillin 500 mg PO three times a day") && !AccuracyModel.isOath("Which enzyme is deficient in PKU?"))
check("key disagreement is a share", AccuracyModel.featureValues(kind: .mcq, rules: [], votes: [AccuracyVote(risk: 1, answer: "C"), AccuracyVote(risk: 1, answer: "A")],
                                                                 evidenceCount: 0, sourceMatch: nil, keyLetter: "A")["key_disagree"] == 0.5)
check("the bundled weights decode and are valid", AccuracyModel.bundled.version == "prior-1" && AccuracyModel.bundled.isValid
      && AccuracyModel.bundled.features == AccuracyModel.features)
// the same numbers as the server's predict() for the passing case: logit 3 + 0.3*(2/3) + 0.8 + 0.1*0.6 + 0.8*0.7
let voterTerm: Double = 0.3 * (2.0 / 3.0)
let evidenceTerm: Double = 0.8 + 0.1 * 0.6
let sourceTerm: Double = 0.8 * 0.7
let logit: Double = 3 + voterTerm + evidenceTerm + sourceTerm
check("inference is the logistic of the weighted sum", abs(p1 - 1 / (1 + exp(-logit))) < 1e-12, "\(p1)")
var trained = AccuracyModel.bundled
trained.thresholds = .init(verified: 0.999, flagged: 0.4)
check("new weights re-score without a new check", AccuracyModel.grade(p1, pass, weights: trained) == .check)
trained.thresholds = .init(verified: 0.3, flagged: 0.5)
check("weights with crossed cut-offs are invalid", !trained.isValid)

// MARK: the cache key

let hashA = q.contentHash
var edited = q; edited.explanation += " "
var renamed = q; renamed.id = "other"
check("the hash is stable and 32 hex", hashA.count == 32 && hashA == q.contentHash && hashA.allSatisfy { $0.isHexDigit })
check("it is of the content, not the id", renamed.contentHash == hashA)
var rekeyed = q; rekeyed.key = 1
check("any edit changes it", rekeyed.contentHash != hashA && AccuracyItem(id: "q", kind: .mcq, stem: q.stem, options: q.options, key: 0, explanation: q.explanation, source: "lecture").contentHash != hashA)
check("FNV-1a of the empty string is its offset basis", AccuracyItem.fnv("", seed: 0xcbf29ce484222325) == "cbf29ce484222325"
      && AccuracyItem.fnv("a", seed: 0xcbf29ce484222325) == "af63dc4c8601ec8c")
check("the checker text matches the server's", q.checkedText.hasSuffix("Keyed answer: A. Aspirin\nExplanation: Aspirin reduces mortality in acute coronary syndrome."))

// MARK: items in every kind of set

let mq = MCQQuestion(stem: q.stem, options: q.options, correctIndex: 0, explanation: q.explanation)
var mcqSet = StudySet(name: "ACS", kind: .mcq)
mcqSet.questions = [mq]
check("a question becomes an item", AccuracyItem.items(in: mcqSet).first?.kind == .mcq && AccuracyItem.items(in: mcqSet).first?.id == mq.id.uuidString)
check("with its lecture excerpt", AccuracyItem.items(in: mcqSet, source: { _ in String(repeating: "x", count: 5000) }).first?.source.count == AccuracyItem.sourceLimit)
var cardSet = StudySet(name: "Cards", kind: .anki)
cardSet.cards = [AnkiCard(type: .qa, front: "Antidote to warfarin?", bullets: ["Vitamin K", "PCC"], why: "Reverses it."),
                 AnkiCard(type: .occlusion)]
check("cards (not a wordless occlusion)", AccuracyItem.items(in: cardSet).count == 1 && AccuracyItem.items(in: cardSet)[0].text.contains("A: Vitamin K; PCC"))
var caseSet = StudySet(name: "Cases", kind: .qa)
caseSet.qaCards = [QACard(type: .case, stem: "A 30-year-old with fever", answer: ["Malaria"])]
var osceSet = StudySet(name: "OSCE", kind: .osce)
osceSet.osceChecklists = [OsceChecklist(title: "BLS", steps: ["Check response", "Call for help"])]
check("cases and stations", AccuracyItem.items(in: caseSet).first?.kind == .case && AccuracyItem.items(in: osceSet).first?.text == "BLS\n- Check response\n- Call for help")
var book = StudySet(name: "Book", kind: .book)
book.bookMarkdown = "# Heart\nThe heart has four chambers.\n# Lungs\nThe right lung has three lobes."
check("a textbook's pages", AccuracyItem.items(in: book).count == 2 && AccuracyItem.items(in: book)[1].kind == .page)
var talk = StudySet(name: "Lecture", kind: .narrate)
talk.narrateSegments = [NarrateSegment(text: "Welcome everyone. Give aspirin 300 mg at once. Thanks for coming. Amoxicillin is first line for otitis media.")]
let facts = AccuracyItem.items(in: talk)
check("a narration's key facts, not its chatter", facts.count == 1 && facts[0].text.contains("aspirin 300 mg") && facts[0].text.contains("first line") && !facts[0].text.contains("Welcome"))
check("a note is its own kind", AccuracyItem.note(id: UUID(), title: "T", body: "B").kind == .note)

// MARK: the ledger

var ledger = AccuracyLedger()
let item0 = AccuracyItem.items(in: mcqSet)[0]
check("an unchecked item with no rule hits is Not checked yet", ledger.assess(item0).grade == .unchecked)
ledger.add(votes: [AccuracyVote(model: "a", risk: 1, answer: "A", evidence: "supports", blind: true), AccuracyVote(model: "b", risk: 1, answer: "A", evidence: "supports", blind: true)],
           evidence: [AccuracyEvidence(id: "S1", source: "MedlinePlus", title: "t", url: "https://medlineplus.gov")], sourceMatch: 0.8, for: item0.contentHash)
check("blind solves make it Verified", ledger.assess(item0).grade == .verified && ledger.isChecked(item0.contentHash, question: true))
var anchoredLedger = AccuracyLedger()
anchoredLedger.add(votes: [AccuracyVote(model: "a", risk: 1, answer: "A", evidence: "supports"), AccuracyVote(model: "b", risk: 1, answer: "A", evidence: "supports")], sourceMatch: 0.8, for: item0.contentHash)
check("a question checked before blind solving is asked about again", !anchoredLedger.isChecked(item0.contentHash, question: true)
      && anchoredLedger.isChecked(item0.contentHash) && anchoredLedger.assess(item0).grade == .check)
ledger.add(votes: [AccuracyVote(model: "a", risk: 4, answer: "B", evidence: "contradicts", issues: ["Wrong"])], for: item0.contentHash)
check("a model's new vote replaces its old one", ledger.records[item0.contentHash]?.votes.count == 2 && ledger.assess(item0).grade != .verified)
check("and its concern is a reason", ledger.assess(item0).reasons.contains("a: Wrong"))
var reported = AccuracyLedger()
reported.add(votes: [AccuracyVote(model: "a", risk: 1, answer: "A", evidence: "supports", blind: true), AccuracyVote(model: "b", risk: 1, answer: "A", evidence: "supports", blind: true)], sourceMatch: 0.8, for: item0.contentHash)
reported.markReported(item0.contentHash)
check("a reported item is never shown as Verified again", reported.assess(item0).grade == .check)
// the claim gate (server/claims.js): the server's reply, as it sends it
func gateReply(_ claims: String) -> AccuracyCheckReply? {
    let json: String = """
    {"items":[{"id":"q","hash":"x","p":0.97,"verdict":"check","modelVersion":"v","features":{"source_match":0.8,"no_source":0},
      "rules":[],"votes":[{"model":"a","risk":1,"answer":"A","evidence":"supports","cites":[],"issues":[],"fix":null,"blind":true},
                          {"model":"b","risk":1,"answer":"A","evidence":"supports","cites":[],"issues":[],"fix":null,"blind":true}],
      "evidence":[{"id":"S1","source":"MedlinePlus","title":"t","url":"https://medlineplus.gov"}],"fix":null\(claims)}]}
    """
    return try? JSONDecoder().decode(AccuracyCheckReply.self, from: Data(json.utf8))
}
let hash0: String = item0.contentHash
let gateTime = Date(timeIntervalSince1970: 3_000_000)
var gated = AccuracyLedger()
gated.record(gateReply(""), for: [hash0], at: gateTime)
check("a reply the gate found nothing in: Verified on the votes, as before", gated.assess(item0).grade == .verified && gated.records[hash0]?.claimHolds == nil)
gated.record(gateReply(#","claims":{"hard":[{"code":"frequency","claim":"every 4 hours","source":"every 6 hours"}],"soft":[]}"#), for: [hash0], at: gateTime)
check("an item that contradicts its own lecture is never Verified, whatever the votes", gated.assess(item0).grade == .check
      && gated.records[hash0]?.claimHolds == ["frequency"] && gated.isChecked(hash0))
check("and the finding is a reason, in words", gated.assess(item0).reasons.contains("Gives a different dosing frequency from its own lecture."))
gated.record(gateReply(""), for: [hash0], at: gateTime)
check("a later reply's findings replace the earlier ones", gated.assess(item0).grade == .verified)
gated.add(votes: [AccuracyVote(model: "c", risk: 1, answer: "A", evidence: "supports")], holds: ["negation"], for: hash0)
gated.add(votes: [AccuracyVote(model: "d", risk: 1, answer: "A", evidence: "supports")], for: hash0)
check("a vote from elsewhere, with no gate, leaves the findings as they were", gated.records[hash0]?.claimHolds == ["negation"] && gated.assess(item0).grade == .check)
var broken = AccuracyLedger()
broken.record(gateReply(#","claims":{"hard":[{"code":"gate_failed","claim":"","source":""}],"soft":[]}"#), for: [hash0], at: gateTime)
check("a gate that failed holds the item at Check this, with its votes kept", broken.assess(item0).grade == .check && broken.records[hash0]?.votes.count == 2)
check("and it is asked about again later, not at once", !broken.isChecked(hash0) && !broken.mayRetry(hash0, now: gateTime.addingTimeInterval(60))
      && broken.mayRetry(hash0, now: gateTime.addingTimeInterval(7 * 3600)))
broken.record(gateReply(""), for: [hash0], at: gateTime.addingTimeInterval(7 * 3600))
check("asked again and the gate works: graded on the votes", broken.isChecked(hash0, question: true) && broken.assess(item0).grade == .verified)
var unread = AccuracyLedger()
unread.record(gateReply(#","claims":{"hard":[{"claim":"x"}],"soft":[],"partial":true}"#), for: [hash0], at: gateTime)
check("a finding without a code still holds the item", unread.assess(item0).grade == .check)
var unanswered = AccuracyLedger()
unanswered.record(AccuracyCheckReply(items: [], limit: "day", message: nil), for: [hash0], at: gateTime)
unanswered.record(nil, for: ["other"], at: gateTime)
check("no vote: failed, unless the day's checks ran out", unanswered.failed[hash0] == nil && unanswered.failed["other"] == gateTime && unanswered.records.isEmpty)
let older = try? JSONDecoder().decode(AccuracyRecord.self, from: Data(#"{"hash":"h","votes":[],"evidence":[],"checkedAt":0,"reported":false}"#.utf8))
check("a record saved before the gate still loads, with no findings", older != nil && older?.claimHolds == nil)
let summary = reported.summary(of: [item0, AccuracyItem(id: "z", kind: .card, text: "Give paracetamol 10 g now")])
check("a set's summary", summary.check == 1 && summary.flagged == 1 && summary.grade == .flagged && summary.line == "1 to check \u{00B7} 1 flagged")
check("nothing checked: no summary line", AccuracySummary().line == nil)
var failing = AccuracyLedger()
let t0 = Date(timeIntervalSince1970: 1_000_000)
failing.failed["h"] = t0
check("a failed check waits before it is tried again", !failing.mayRetry("h", now: t0.addingTimeInterval(60)) && failing.mayRetry("h", now: t0.addingTimeInterval(7 * 3600)))
failing.records["old"] = AccuracyRecord(hash: "old")
failing.prune(keeping: ["h"])
check("records of edited or deleted items are pruned", failing.records.isEmpty && failing.failed["h"] != nil)

// MARK: the schedule

let now = Date(timeIntervalSince1970: 2_000_000)
func set(_ name: String, updated: TimeInterval, n: Int) -> StudySet {
    var s = StudySet(name: name, kind: .anki)
    s.updatedAt = now.addingTimeInterval(-updated)
    s.cards = (0..<n).map { AnkiCard(type: .qa, front: "\(name) question \($0)?", bullets: ["answer \($0)"]) }
    return s
}
let justMade = set("new", updated: 60, n: 5)
let oldStudied = set("studied", updated: 30 * 86400, n: 3)
let oldIdle = set("idle", updated: 20 * 86400, n: 3)
let thisWeek = set("week", updated: 2 * 86400, n: 2)
let plan = AccuracySchedule.plan(sets: [oldIdle, oldStudied, thisWeek, justMade], items: { AccuracyItem.items(in: $0) },
                                 ledger: AccuracyLedger(), studied: [oldStudied.id: 40, oldIdle.id: 1], now: now, limit: 100)
check("just-made content first, in the foreground", plan.first?.setID == justMade.id && plan.first?.priority == "foreground" && plan[1].setID == justMade.id)
check("in batches of four", plan[0].items.count == 4 && plan[1].items.count == 1)
check("then this week's, then most-studied, then the rest, in the background",
      plan.dropFirst(2).map(\.setID) == [thisWeek.id, oldStudied.id, oldIdle.id] && plan.dropFirst(2).allSatisfy { $0.priority == "background" })
var partly = AccuracyLedger()
for item in AccuracyItem.items(in: justMade).prefix(3) { partly.add(votes: [AccuracyVote(model: "a", risk: 1)], for: item.contentHash) }
partly.failed[AccuracyItem.items(in: justMade)[3].contentHash] = now
let replan = AccuracySchedule.plan(sets: [justMade], items: { AccuracyItem.items(in: $0) }, ledger: partly, now: now)
check("checked items are never sent again, failed ones wait", replan.count == 1 && replan[0].items.count == 1)
let capped = AccuracySchedule.plan(sets: [oldIdle, oldStudied, thisWeek, justMade], items: { AccuracyItem.items(in: $0) },
                                   ledger: AccuracyLedger(), now: now, limit: 6)
check("the day's limit is kept", capped.reduce(0) { $0 + $1.items.count } == 6)
var twin = set("twin", updated: 100 * 86400, n: 1)
twin.cards = justMade.cards.prefix(1).map { var c = $0; c.id = UUID(); return c }
let deduped = AccuracySchedule.plan(sets: [justMade, twin], items: { AccuracyItem.items(in: $0) }, ledger: AccuracyLedger(), now: now)
check("the same content in two sets is checked once", deduped.reduce(0) { $0 + $1.items.count } == 5)

// MARK: one-tap corrections

let keyFix = AccuracySuggestion(field: "key", value: "B")
if let fixed = AccuracyFix.apply(keyFix, toItem: mq.id.uuidString, in: mcqSet) {
    check("a key correction moves the key", fixed.questions[0].correctIndex == 1)
    check("and the edit means a new check", AccuracyItem.items(in: fixed)[0].contentHash != item0.contentHash)
} else { check("a key correction applies", false) }
check("a key outside the options is not offered", !AccuracyFix.canApply(AccuracySuggestion(field: "key", value: "Q"), to: item0)
      && AccuracyFix.apply(AccuracySuggestion(field: "key", value: "Z"), toItem: mq.id.uuidString, in: mcqSet) == nil)
check("an explanation correction", AccuracyFix.apply(AccuracySuggestion(field: "explanation", value: "Better."), toItem: mq.id.uuidString, in: mcqSet)?.questions[0].explanation == "Better.")
let cardID = cardSet.cards[0].id.uuidString
check("a card's answer, line by line", AccuracyFix.apply(AccuracySuggestion(field: "answer", value: "Vitamin K\n- Four-factor PCC"), toItem: cardID, in: cardSet)?.cards[0].bullets == ["Vitamin K", "Four-factor PCC"])
check("a station's steps", AccuracyFix.apply(AccuracySuggestion(field: "text", value: "Check danger\nCheck response\nCall for help"), toItem: osceSet.osceChecklists[0].id.uuidString, in: osceSet)?.osceChecklists[0].steps.count == 3)
check("a fix for an unknown item does nothing", AccuracyFix.apply(keyFix, toItem: "nope", in: mcqSet) == nil)

// MARK: the shared rule cases (server/tests/accuracy.test.mjs runs the same file)
var ruleRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
while !FileManager.default.fileExists(atPath: ruleRoot.appendingPathComponent("server/tests/rule-vectors.json").path), ruleRoot.path != "/" {
    ruleRoot.deleteLastPathComponent()
}
struct RuleQuestion: Decodable { var stem: String; var options: [String]; var key: Int; var explanation: String }
struct RuleCase: Decodable { var text: String?; var mcq: RuleQuestion?; var has: [String]?; var not: [String]? }
let ruleCases: [RuleCase] = (try? JSONDecoder().decode([RuleCase].self,
    from: Data(contentsOf: ruleRoot.appendingPathComponent("server/tests/rule-vectors.json")))) ?? []
check("the shared rule cases are found", ruleCases.count >= 20, "\(ruleCases.count)")
for c in ruleCases {
    let item: AccuracyItem = c.mcq.map {
        AccuracyItem(id: "x", kind: .mcq, stem: $0.stem, options: $0.options, key: $0.key, explanation: $0.explanation)
    } ?? card(c.text ?? "")
    let said: String = c.mcq?.stem ?? c.text ?? ""
    let found: [String] = ids(item)
    for h in c.has ?? [] { check("\"\(said)\" gives \(h)", found.contains(h), found.joined(separator: ", ")) }
    for n in c.not ?? [] { check("\"\(said)\" gives no \(n)", !found.contains { $0.hasPrefix(n + ":") }, found.joined(separator: ", ")) }
}

print(failures.isEmpty ? "\nALL ACCURACY TESTS PASS" : "\n\(failures.count) ACCURACY TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
