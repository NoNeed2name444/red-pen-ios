import Foundation

/// One thing an exam expects the student to know - "Asthma", "Brachial
/// plexus" - with the words that give it away when it turns up in the
/// student's own material.
///
/// Keywords are lowercase and singular. British spellings are enough: the
/// coverage engine folds "haemorrhage" and "hemorrhage", "tumour" and
/// "tumor" into the same word before it compares them.
struct SyllabusSubtopic: Identifiable, Hashable {
    let name: String
    let keywords: [String]
    var id: String { name }
}

/// A heading in an exam's blueprint - an area of clinical practice, an organ
/// system, a specialty - and the subtopics under it.
struct SyllabusArea: Identifiable, Hashable {
    let name: String
    let subtopics: [SyllabusSubtopic]
    var id: String { name }
}

/// What each exam covers, as a list of areas and subtopics to check the
/// library against.
///
/// These lists are CONDENSED from the public blueprints - the GMC's MLA
/// content map (PLAB), the USMLE content outline, the MRCP(UK) Part 1
/// blueprint and the MRCS Part A syllabus - and are approximate: the headings
/// follow the blueprints, the subtopics are a fair sample of what sits under
/// each rather than the full list, and the keywords are ours. They say where
/// the gaps probably are, not what the exam will ask.
///
/// Foundation only, so the coverage engine can be tested without the app.
enum Syllabus {

    /// The areas for one exam. General revision gets the broad organ-system
    /// map, which suits any medical exam.
    static func areas(for track: ExamTrack) -> [SyllabusArea] {
        switch track {
        case .plab: return plab
        case .usmle, .general: return usmle
        case .mrcp: return mrcp
        case .mrcs: return mrcs
        }
    }

    /// Which blueprint a track's list is condensed from, for the screen.
    static func blueprint(for track: ExamTrack) -> String {
        switch track {
        case .plab: return "the GMC's MLA content map"
        case .usmle: return "the USMLE content outline"
        case .general: return "the USMLE content outline's organ systems"
        case .mrcp: return "the MRCP(UK) Part 1 blueprint"
        case .mrcs: return "the MRCS Part A syllabus"
        }
    }

    /// A subtopic from a name and its keywords, comma-separated.
    private static func t(_ name: String, _ keywords: String) -> SyllabusSubtopic {
        SyllabusSubtopic(name: name,
                         keywords: keywords.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                            .filter { !$0.isEmpty })
    }

    private static func area(_ name: String, _ subtopics: [SyllabusSubtopic]) -> SyllabusArea {
        SyllabusArea(name: name, subtopics: subtopics)
    }

    // MARK: - Clinical blocks shared by more than one exam

    static let cardiology: [SyllabusSubtopic] = [
        t("Ischaemic heart disease", "angina, myocardial infarction, acute coronary syndrome, stemi, nstemi, troponin, coronary artery, coronary"),
        t("Heart failure", "heart failure, ejection fraction, bnp, cardiomyopathy, pulmonary oedema, cardiac failure"),
        t("Arrhythmias", "arrhythmia, atrial fibrillation, atrial flutter, tachycardia, bradycardia, heart block, long qt, wolff parkinson white, svt, ventricular fibrillation"),
        t("Hypertension", "hypertension, blood pressure, antihypertensive, amlodipine, ramipril, ace inhibitor"),
        t("Valve disease", "aortic stenosis, aortic regurgitation, mitral stenosis, mitral regurgitation, murmur, valve replacement, heart valve"),
        t("Endocarditis and pericardial disease", "endocarditis, pericarditis, pericardial effusion, tamponade, myocarditis, duke criteria"),
        t("Vascular disease", "aortic dissection, aortic aneurysm, peripheral arterial disease, claudication, limb ischaemia, varicose vein"),
        t("Congenital heart disease", "ventricular septal defect, atrial septal defect, tetralogy of fallot, patent ductus arteriosus, coarctation, congenital heart"),
        t("Lipids and cardiovascular prevention", "cholesterol, statin, hyperlipidaemia, lipid, qrisk, cardiovascular risk"),
    ]

    static let respiratory: [SyllabusSubtopic] = [
        t("Asthma", "asthma, wheeze, inhaler, salbutamol, peak flow, bronchodilator"),
        t("COPD", "copd, chronic obstructive, emphysema, chronic bronchitis, spirometry"),
        t("Pneumonia", "pneumonia, curb 65, chest infection, lower respiratory tract infection, consolidation, legionella, mycoplasma"),
        t("Pulmonary embolism", "pulmonary embolism, wells score, d dimer, ctpa, thromboembolism"),
        t("Lung cancer", "lung cancer, bronchial carcinoma, small cell, non small cell, mesothelioma, pancoast"),
        t("Interstitial lung disease", "interstitial lung disease, pulmonary fibrosis, sarcoidosis, asbestosis, pneumoconiosis, extrinsic allergic alveolitis"),
        t("Pleural disease", "pleural effusion, pneumothorax, empyema, chest drain, pleural"),
        t("Tuberculosis", "tuberculosis, mycobacterium, rifampicin, isoniazid, latent tb"),
        t("Bronchiectasis and cystic fibrosis", "bronchiectasis, cystic fibrosis, cftr"),
        t("Respiratory failure and sleep", "respiratory failure, type 2 respiratory failure, non invasive ventilation, obstructive sleep apnoea, sleep apnoea, oxygen therapy"),
    ]

    static let gastro: [SyllabusSubtopic] = [
        t("Upper GI and peptic disease", "dyspepsia, peptic ulcer, helicobacter, reflux, gord, gerd, barrett, oesophagitis, proton pump inhibitor"),
        t("Inflammatory bowel disease", "crohn, ulcerative colitis, inflammatory bowel disease, ibd"),
        t("Liver disease", "cirrhosis, hepatitis, liver failure, ascites, varices, jaundice, alcoholic liver disease, fatty liver, nafld, hepatic encephalopathy"),
        t("Pancreas and biliary tree", "pancreatitis, gallstone, cholecystitis, cholangitis, biliary colic, obstructive jaundice"),
        t("GI cancers", "colorectal cancer, bowel cancer, oesophageal cancer, gastric cancer, pancreatic cancer, hepatocellular carcinoma, colonic polyp"),
        t("Coeliac disease and malabsorption", "coeliac, malabsorption, gluten, irritable bowel syndrome, ibs"),
        t("GI infection and diarrhoea", "diarrhoea, gastroenteritis, clostridium difficile, c difficile, food poisoning"),
        t("GI bleeding", "haematemesis, melaena, gi bleed, gastrointestinal bleeding, rockall, glasgow blatchford, rectal bleeding"),
    ]

    static let endocrine: [SyllabusSubtopic] = [
        t("Diabetes mellitus", "diabetes, insulin, metformin, hba1c, hyperglycaemia, diabetic ketoacidosis, dka, hypoglycaemia, sglt2"),
        t("Thyroid disease", "thyroid, hyperthyroidism, hypothyroidism, graves, hashimoto, levothyroxine, tsh, goitre, thyrotoxicosis"),
        t("Adrenal disease", "cushing, addison, adrenal, cortisol, phaeochromocytoma, conn syndrome, hyperaldosteronism"),
        t("Pituitary disease", "pituitary, prolactinoma, acromegaly, diabetes insipidus, hypopituitarism, prolactin, siadh"),
        t("Calcium and bone metabolism", "hypercalcaemia, hypocalcaemia, parathyroid, hyperparathyroidism, osteoporosis, vitamin d, osteomalacia, paget"),
        t("Obesity and metabolic syndrome", "obesity, metabolic syndrome, bmi, bariatric"),
        t("Reproductive endocrinology", "polycystic ovary, pcos, hypogonadism, klinefelter, turner syndrome, gynaecomastia"),
    ]

    static let renal: [SyllabusSubtopic] = [
        t("Acute kidney injury", "acute kidney injury, aki, oliguria, acute renal failure, nephrotoxic"),
        t("Chronic kidney disease", "chronic kidney disease, ckd, egfr, dialysis, renal transplant, haemodialysis"),
        t("Glomerular disease", "glomerulonephritis, nephrotic syndrome, nephritic syndrome, iga nephropathy, proteinuria, haematuria"),
        t("Electrolytes and acid-base", "hyperkalaemia, hypokalaemia, hyponatraemia, hypernatraemia, metabolic acidosis, metabolic alkalosis, anion gap"),
        t("Urinary tract infection", "urinary tract infection, uti, pyelonephritis, cystitis"),
        t("Urological cancer", "prostate cancer, bladder cancer, renal cell carcinoma, testicular cancer, psa"),
        t("Stones and obstruction", "renal colic, kidney stone, nephrolithiasis, hydronephrosis, urinary retention, benign prostatic hyperplasia, bph"),
        t("Scrotal and penile problems", "testicular torsion, epididymitis, epididymo orchitis, hydrocele, varicocele, erectile dysfunction"),
    ]

    static let neurology: [SyllabusSubtopic] = [
        t("Stroke and TIA", "stroke, transient ischaemic attack, tia, thrombolysis, thrombectomy, cerebral infarction, intracerebral haemorrhage"),
        t("Headache", "headache, migraine, cluster headache, subarachnoid haemorrhage, idiopathic intracranial hypertension, tension type headache"),
        t("Epilepsy and seizures", "epilepsy, seizure, status epilepticus, antiepileptic, sodium valproate, levetiracetam, lamotrigine"),
        t("Movement disorders", "parkinson, tremor, huntington, levodopa, dystonia, chorea"),
        t("Multiple sclerosis and demyelination", "multiple sclerosis, demyelination, demyelinating, optic neuritis, guillain barre"),
        t("Neuromuscular disease", "myasthenia gravis, motor neurone disease, peripheral neuropathy, muscular dystrophy, amyotrophic lateral sclerosis, neuropathy"),
        t("Dementia and delirium", "dementia, alzheimer, delirium, cognitive impairment, lewy body, frontotemporal"),
        t("CNS infection and tumours", "meningitis, encephalitis, brain tumour, glioma, glioblastoma, meningioma, brain abscess"),
        t("Spinal cord and nerve roots", "spinal cord compression, cauda equina, radiculopathy, myelopathy, syringomyelia"),
    ]

    static let rheumatology: [SyllabusSubtopic] = [
        t("Inflammatory arthritis", "rheumatoid arthritis, psoriatic arthritis, ankylosing spondylitis, reactive arthritis, spondyloarthritis, methotrexate"),
        t("Crystal arthritis", "gout, pseudogout, urate, allopurinol, chondrocalcinosis, colchicine"),
        t("Osteoarthritis", "osteoarthritis, joint replacement, hip replacement, knee replacement"),
        t("Connective tissue disease", "systemic lupus erythematosus, lupus, sle, scleroderma, systemic sclerosis, sjogren, dermatomyositis, polymyositis, antiphospholipid"),
        t("Vasculitis and polymyalgia", "vasculitis, giant cell arteritis, temporal arteritis, polymyalgia rheumatica, granulomatosis with polyangiitis, anca"),
        t("Back and neck pain", "back pain, sciatica, disc prolapse, mechanical back pain, neck pain"),
        t("Bone and joint infection", "septic arthritis, osteomyelitis, discitis"),
        t("Fractures and injuries", "fracture, dislocation, neck of femur, colles, scaphoid, compartment syndrome, sprain"),
    ]

    static let haematology: [SyllabusSubtopic] = [
        t("Anaemia", "anaemia, iron deficiency, b12 deficiency, folate deficiency, pernicious anaemia, haemolytic, haemolysis"),
        t("Haemoglobinopathies", "sickle cell, thalassaemia, haemoglobinopathy"),
        t("Leukaemia", "leukaemia, acute myeloid, acute lymphoblastic, chronic lymphocytic, chronic myeloid"),
        t("Lymphoma and myeloma", "lymphoma, hodgkin, non hodgkin, myeloma, paraprotein, bence jones"),
        t("Myeloproliferative and marrow disorders", "myeloproliferative, polycythaemia, essential thrombocythaemia, myelofibrosis, myelodysplastic, aplastic anaemia"),
        t("Bleeding disorders", "haemophilia, von willebrand, thrombocytopenia, itp, disseminated intravascular coagulation, dic, bleeding disorder"),
        t("Thrombosis and anticoagulation", "deep vein thrombosis, dvt, anticoagulant, anticoagulation, warfarin, heparin, apixaban, rivaroxaban, thrombophilia"),
        t("Transfusion", "transfusion, blood product, transfusion reaction, fresh frozen plasma, cryoprecipitate"),
        t("Neutropenia and the spleen", "neutropenia, neutropenic, splenomegaly, splenectomy, hyposplenism"),
    ]

    static let infection: [SyllabusSubtopic] = [
        t("Sepsis", "sepsis, septic shock, qsofa, sepsis six, blood culture, bacteraemia"),
        t("HIV", "hiv, antiretroviral, aids, cd4, pneumocystis"),
        t("Tropical and travel infection", "malaria, typhoid, dengue, schistosomiasis, returning traveller, travel"),
        t("Antimicrobial prescribing", "antibiotic, antimicrobial, penicillin, amoxicillin, co amoxiclav, vancomycin, gentamicin, antimicrobial resistance, mrsa, stewardship"),
        t("Viral infections", "influenza, covid, herpes simplex, varicella, shingles, epstein barr, glandular fever, cytomegalovirus, measles, mumps"),
        t("Healthcare-associated infection", "hospital acquired, healthcare associated, infection control, hand hygiene, isolation, clostridioides"),
        t("Fungal and parasitic infection", "candida, aspergillus, fungal, parasite, helminth, giardia, worm"),
        t("Vaccination", "vaccine, vaccination, immunisation"),
    ]

    static let childHealth: [SyllabusSubtopic] = [
        t("Neonates", "neonate, neonatal, newborn, neonatal jaundice, prematurity, preterm, apgar, respiratory distress syndrome"),
        t("Growth and development", "developmental milestone, milestone, growth chart, failure to thrive, faltering growth, puberty, developmental delay"),
        t("Childhood infections and fever", "bronchiolitis, croup, febrile convulsion, kawasaki, scarlet fever, hand foot and mouth, feverish child"),
        t("Safeguarding", "safeguarding, non accidental injury, child abuse, child protection, neglect"),
        t("Paediatric surgery", "intussusception, pyloric stenosis, hirschsprung, undescended testis, malrotation, intestinal atresia"),
        t("Congenital and neurodevelopmental conditions", "down syndrome, cerebral palsy, cleft lip, congenital, autism, adhd"),
        t("Feeding and nutrition", "breastfeeding, infant feeding, cows milk protein allergy, rickets, weaning"),
        t("Childhood chronic illness", "childhood asthma, type 1 diabetes, epilepsy in children, juvenile idiopathic arthritis, nephrotic syndrome in children"),
    ]

    static let obstetrics: [SyllabusSubtopic] = [
        t("Antenatal care", "antenatal, booking visit, pregnancy, gestation, folic acid, antenatal screening"),
        t("Early pregnancy problems", "ectopic pregnancy, miscarriage, hyperemesis gravidarum, molar pregnancy"),
        t("Complications of pregnancy", "pre eclampsia, eclampsia, gestational diabetes, placenta praevia, placental abruption, obstetric cholestasis"),
        t("Labour and delivery", "labour, caesarean, induction of labour, shoulder dystocia, cardiotocography, ctg, instrumental delivery"),
        t("Postnatal care", "postnatal, postpartum, puerperal, postpartum haemorrhage, postnatal depression"),
    ]

    static let gynaecology: [SyllabusSubtopic] = [
        t("Menstrual disorders", "menorrhagia, heavy menstrual bleeding, amenorrhoea, dysmenorrhoea, endometriosis, fibroid"),
        t("Gynaecological cancer", "cervical cancer, ovarian cancer, endometrial cancer, cervical screening, smear test, ca 125"),
        t("Contraception and fertility", "contraception, contraceptive, infertility, ivf, intrauterine device, combined pill"),
        t("Menopause and pelvic floor", "menopause, hormone replacement therapy, hrt, uterovaginal prolapse, prolapse, urinary incontinence"),
        t("Breast disease", "breast cancer, breast lump, mammogram, fibroadenoma, brca, mastitis"),
    ]

    static let mentalHealth: [SyllabusSubtopic] = [
        t("Depression and anxiety", "depression, anxiety, generalised anxiety disorder, panic disorder, ssri, antidepressant, sertraline"),
        t("Psychosis and schizophrenia", "psychosis, schizophrenia, antipsychotic, hallucination, delusion, clozapine"),
        t("Bipolar disorder", "bipolar, mania, hypomania, lithium"),
        t("Self-harm and suicide", "self harm, suicide, suicidal, overdose, risk assessment"),
        t("Substance misuse", "alcohol dependence, alcohol withdrawal, delirium tremens, opioid dependence, substance misuse, wernicke, drug misuse"),
        t("Eating disorders", "anorexia nervosa, bulimia, eating disorder, refeeding"),
        t("Personality, OCD and trauma", "personality disorder, obsessive compulsive, ocd, ptsd, post traumatic stress"),
        t("Mental health law and capacity", "mental health act, mental capacity, capacity, sectioning, deprivation of liberty"),
    ]

    static let dermatology: [SyllabusSubtopic] = [
        t("Eczema and dermatitis", "eczema, dermatitis, emollient, atopic"),
        t("Psoriasis", "psoriasis, plaque psoriasis, guttate"),
        t("Skin cancer", "melanoma, basal cell carcinoma, squamous cell carcinoma, actinic keratosis, naevus, mole"),
        t("Skin infections and infestations", "cellulitis, impetigo, tinea, scabies, erysipelas, molluscum"),
        t("Acne and rosacea", "acne, rosacea, isotretinoin"),
        t("Urticaria and drug eruptions", "urticaria, angioedema, stevens johnson, toxic epidermal necrolysis, drug eruption"),
        t("Blistering disease", "pemphigus, pemphigoid, dermatitis herpetiformis, blister"),
        t("Skin signs of systemic disease", "erythema nodosum, pyoderma gangrenosum, acanthosis nigricans, vitiligo, erythema multiforme"),
    ]

    static let ent: [SyllabusSubtopic] = [
        t("Ear disease and hearing", "otitis media, otitis externa, hearing loss, tinnitus, cholesteatoma, glue ear"),
        t("Vertigo and balance", "vertigo, bppv, benign paroxysmal positional vertigo, meniere, vestibular neuritis, labyrinthitis"),
        t("Nose and sinuses", "epistaxis, sinusitis, rhinitis, nasal polyp"),
        t("Throat and airway", "tonsillitis, pharyngitis, quinsy, peritonsillar abscess, stridor, epiglottitis"),
        t("Head and neck cancer and neck lumps", "head and neck cancer, laryngeal cancer, neck lump, hoarseness, oral cancer, parotid, salivary gland"),
    ]

    static let ophthalmology: [SyllabusSubtopic] = [
        t("Red eye", "red eye, conjunctivitis, uveitis, iritis, keratitis, scleritis, episcleritis"),
        t("Glaucoma", "glaucoma, intraocular pressure, angle closure"),
        t("Sudden visual loss", "visual loss, retinal detachment, central retinal artery occlusion, retinal vein occlusion, vitreous haemorrhage, amaurosis fugax"),
        t("Retinopathy and macular disease", "diabetic retinopathy, retinopathy, macular degeneration, macular oedema"),
        t("Cataract", "cataract"),
        t("Neuro-ophthalmology", "papilloedema, optic neuritis, visual field defect, hemianopia, diplopia, horner, third nerve palsy"),
        t("Eye injury", "eye injury, corneal abrasion, foreign body in the eye, chemical eye injury, hyphaema"),
    ]

    static let oncology: [SyllabusSubtopic] = [
        t("Suspected cancer and referral", "two week wait, urgent suspected cancer, cancer referral, red flag, unexplained weight loss"),
        t("Oncological emergencies", "neutropenic sepsis, metastatic spinal cord compression, superior vena cava obstruction, tumour lysis, hypercalcaemia of malignancy"),
        t("Chemotherapy, radiotherapy and immunotherapy", "chemotherapy, radiotherapy, immunotherapy, cytotoxic, targeted therapy, checkpoint inhibitor"),
        t("Cancer screening", "cancer screening, bowel screening, breast screening, cervical screening"),
        t("Tumour biology and staging", "tumour marker, oncogene, tumour suppressor, metastasis, staging, tnm, carcinogenesis"),
        t("Breast cancer", "breast cancer, tamoxifen, aromatase inhibitor, her2, brca"),
    ]

    static let palliative: [SyllabusSubtopic] = [
        t("Symptom control", "palliative, symptom control, breathlessness, nausea and vomiting, terminal agitation"),
        t("Pain and opioids", "analgesic ladder, morphine, opioid, breakthrough pain, syringe driver, oxycodone"),
        t("Care in the last days of life", "end of life, last days of life, dying, anticipatory medicine, terminal care"),
        t("Advance care planning", "advance care planning, dnacpr, dnar, advance decision, lasting power of attorney"),
        t("Breaking bad news and bereavement", "breaking bad news, bereavement, grief"),
        t("After death", "death certificate, coroner, verification of death, cremation"),
    ]

    static let perioperative: [SyllabusSubtopic] = [
        t("Preoperative assessment", "preoperative, pre operative assessment, asa grade, fasting, fitness for surgery"),
        t("Anaesthesia", "anaesthesia, anaesthetic, general anaesthesia, local anaesthetic, regional anaesthesia, intubation, airway management, malignant hyperthermia"),
        t("Postoperative complications", "postoperative, post operative complication, wound infection, anastomotic leak, atelectasis, ileus, wound dehiscence"),
        t("Fluids and electrolytes", "iv fluid, intravenous fluid, maintenance fluid, fluid resuscitation, crystalloid, fluid balance"),
        t("VTE prophylaxis", "vte prophylaxis, thromboprophylaxis, low molecular weight heparin, compression stocking, venous thromboembolism"),
        t("Perioperative drugs", "perioperative, bridging anticoagulation, steroid cover, stopping anticoagulant"),
        t("Postoperative pain", "patient controlled analgesia, epidural, postoperative pain, nerve block"),
        t("Nutrition in surgery", "enteral nutrition, parenteral nutrition, tpn, nasogastric feeding, malnutrition"),
    ]

    static let olderAdults: [SyllabusSubtopic] = [
        t("Falls", "falls, faller, postural hypotension, gait, fall prevention"),
        t("Frailty and geriatric assessment", "frailty, frail, comprehensive geriatric assessment, older adult, elderly, geriatric"),
        t("Delirium and dementia", "delirium, dementia, acute confusion, cognitive impairment"),
        t("Polypharmacy", "polypharmacy, deprescribing, stopp start, anticholinergic burden"),
        t("Continence and pressure care", "incontinence, pressure ulcer, pressure sore"),
        t("Osteoporosis and fragility fracture", "osteoporosis, fragility fracture, bisphosphonate, dexa"),
        t("Discharge and social care", "discharge planning, care home, social care, occupational therapy, rehabilitation"),
    ]

    static let pharmacology: [SyllabusSubtopic] = [
        t("Safe prescribing", "prescribing, prescription, drug chart, bnf, medication error"),
        t("Adverse drug reactions", "adverse drug reaction, side effect, yellow card, drug allergy"),
        t("Drug interactions", "drug interaction, cytochrome p450, enzyme inducer, enzyme inhibitor"),
        t("Pharmacokinetics", "pharmacokinetic, half life, clearance, volume of distribution, bioavailability, first pass"),
        t("Pharmacodynamics", "pharmacodynamic, receptor, agonist, antagonist, dose response, therapeutic index"),
        t("Prescribing in special groups", "prescribing in pregnancy, renal impairment, hepatic impairment, breastfeeding, elderly prescribing, teratogen"),
        t("High-risk drugs", "warfarin, insulin, digoxin, lithium, methotrexate, gentamicin, amiodarone, opioid"),
        t("Therapeutic drug monitoring and toxicity", "therapeutic drug monitoring, drug level, toxicity, overdose, antidote, poisoning"),
    ]

    static let immunology: [SyllabusSubtopic] = [
        t("Allergy and anaphylaxis", "anaphylaxis, allergy, allergic, adrenaline auto injector, food allergy, ige"),
        t("Hypersensitivity", "hypersensitivity, hypersensitivity reaction, type iv hypersensitivity, immune complex"),
        t("Immunodeficiency", "immunodeficiency, hypogammaglobulinaemia, complement deficiency, recurrent infection, severe combined immunodeficiency"),
        t("Autoimmunity", "autoimmune, autoantibody, antinuclear antibody, anca, autoimmunity"),
        t("Transplant immunology", "transplant, graft rejection, rejection, graft versus host, immunosuppression, tacrolimus, ciclosporin"),
        t("The immune system", "antibody, immunoglobulin, t cell, b cell, cytokine, complement, innate immunity, adaptive immunity, mhc"),
    ]

    static let genetics: [SyllabusSubtopic] = [
        t("Patterns of inheritance", "autosomal dominant, autosomal recessive, x linked, inheritance, pedigree, mitochondrial inheritance"),
        t("Chromosomal disorders", "down syndrome, trisomy, turner syndrome, klinefelter, chromosomal, karyotype"),
        t("Genetic testing and counselling", "genetic testing, genetic counselling, genomic, genome sequencing, carrier testing"),
        t("Cancer genetics", "brca, lynch syndrome, familial adenomatous polyposis, hereditary cancer"),
        t("Pharmacogenomics", "pharmacogenomic, pharmacogenetic, tpmt, hla b"),
        t("Single-gene disorders", "cystic fibrosis, huntington, sickle cell, haemophilia, marfan, duchenne, fragile x"),
    ]

    static let sexualHealth: [SyllabusSubtopic] = [
        t("Sexually transmitted infections", "chlamydia, gonorrhoea, syphilis, sexually transmitted, genital herpes, genital wart, trichomonas"),
        t("HIV prevention", "hiv, prep, pre exposure prophylaxis, post exposure prophylaxis"),
        t("Contraception", "contraception, emergency contraception, contraceptive"),
        t("Vaginal discharge", "vaginal discharge, bacterial vaginosis, thrush, vulvovaginal candidiasis"),
        t("Pelvic inflammatory disease", "pelvic inflammatory disease, pid"),
        t("Sexual history and partner notification", "sexual history, partner notification, contact tracing, gillick, fraser"),
    ]

    static let epidemiology: [SyllabusSubtopic] = [
        t("Study design", "cohort study, case control, randomised controlled trial, cross sectional, systematic review, meta analysis"),
        t("Diagnostic test performance", "sensitivity, specificity, positive predictive value, negative predictive value, likelihood ratio"),
        t("Measures of risk", "relative risk, odds ratio, absolute risk, number needed to treat, nnt, attributable risk"),
        t("Statistical tests and inference", "p value, confidence interval, t test, chi squared, standard deviation, statistical significance, type 1 error"),
        t("Bias and confounding", "bias, confounding, selection bias, lead time bias, blinding"),
        t("Incidence, prevalence and screening", "incidence, prevalence, screening programme, wilson and jungner, epidemiology"),
    ]

    static let ethics: [SyllabusSubtopic] = [
        t("Consent", "consent, informed consent"),
        t("Confidentiality", "confidentiality, disclosure, data protection"),
        t("Capacity and decision making", "capacity, best interest, mental capacity act, advance directive, surrogate"),
        t("End-of-life ethics", "withdrawing treatment, euthanasia, assisted dying, dnacpr"),
        t("Patient safety and quality improvement", "patient safety, clinical governance, audit, quality improvement, significant event, never event, root cause analysis, medical error"),
        t("Professionalism and communication", "good medical practice, gmc, duty of candour, whistleblowing, professionalism, breaking bad news, interpreter"),
    ]

    // MARK: - PLAB (UK MLA content map)

    static let plab: [SyllabusArea] = [
        area("Acute and emergency", [
            t("Cardiac arrest and resuscitation", "cardiac arrest, resuscitation, cpr, advanced life support, defibrillation"),
            t("Shock", "shock, hypovolaemic, septic shock, cardiogenic shock, fluid resuscitation"),
            t("Anaphylaxis", "anaphylaxis, adrenaline, angioedema"),
            t("Poisoning and overdose", "poisoning, overdose, paracetamol overdose, toxicology, naloxone, activated charcoal"),
            t("Acute chest pain and breathlessness", "acute chest pain, chest pain, breathlessness, acute dyspnoea"),
            t("Reduced consciousness and collapse", "reduced consciousness, glasgow coma scale, gcs, coma, collapse, syncope"),
            t("The deteriorating patient", "news2, early warning score, abcde, deteriorating patient, sepsis"),
            t("Major trauma and head injury", "major trauma, head injury, atls, burns, primary survey"),
        ]),
        area("Cancer", oncology),
        area("Cardiovascular", cardiology),
        area("Child health", childHealth),
        area("Clinical haematology", haematology),
        area("Clinical imaging", [
            t("Chest X-ray", "chest x ray, cxr, chest radiograph"),
            t("CT and MRI", "ct scan, computed tomography, mri, magnetic resonance"),
            t("Ultrasound and echocardiography", "ultrasound, echocardiogram, echocardiography, fast scan, doppler"),
            t("Radiation safety and contrast", "ionising radiation, radiation dose, contrast, contrast nephropathy, irmer"),
            t("Choosing the right imaging", "imaging, radiology, investigation of choice, radiograph"),
            t("Nuclear medicine", "pet scan, nuclear medicine, bone scan, v q scan"),
        ]),
        area("Dermatology", dermatology),
        area("Ear, nose and throat", ent),
        area("Endocrine and metabolic", endocrine),
        area("Gastrointestinal including liver", gastro),
        area("General practice and primary care", [
            t("Chronic disease management", "chronic disease, long term condition, annual review, multimorbidity, qof"),
            t("Health promotion", "health promotion, smoking cessation, lifestyle advice, brief intervention, physical activity"),
            t("Common presentations", "sore throat, cough, tiredness, fatigue, rash, dizziness"),
            t("Prescribing in primary care", "repeat prescription, medication review, polypharmacy"),
            t("Referral and safety netting", "referral, safety netting, two week wait"),
            t("Consultation skills", "consultation, ideas concerns expectations, shared decision making"),
        ]),
        area("Infection", infection),
        area("Mental health", mentalHealth),
        area("Musculoskeletal", rheumatology),
        area("Neurosciences", neurology),
        area("Obstetrics and gynaecology", obstetrics + gynaecology),
        area("Ophthalmology", ophthalmology),
        area("Palliative and end of life care", palliative),
        area("Perioperative medicine and anaesthesia", perioperative),
        area("Renal and urology", renal),
        area("Respiratory", respiratory),
        area("Sexual health", sexualHealth),
        area("Surgery", [
            t("Acute abdomen", "acute abdomen, appendicitis, bowel obstruction, perforation, peritonitis, diverticulitis, volvulus"),
            t("Hernia", "hernia, inguinal hernia, femoral hernia, umbilical hernia"),
            t("Vascular surgery", "abdominal aortic aneurysm, aaa, acute limb ischaemia, carotid endarterectomy, varicose vein, leg ulcer"),
            t("Anorectal conditions", "haemorrhoid, anal fissure, fistula in ano, perianal abscess, pilonidal"),
            t("Breast surgery", "breast lump, breast abscess, fibroadenoma, mastectomy"),
            t("Trauma and orthopaedics", "fracture, trauma, dislocation, neck of femur, compartment syndrome"),
            t("Surgical consent and safety", "consent, who checklist, surgical safety, marking"),
        ]),
        area("Clinical biochemistry", [
            t("Liver function tests", "liver function test, alt, alkaline phosphatase, bilirubin, albumin, lft"),
            t("Renal function and electrolytes", "urea, creatinine, electrolyte, potassium, sodium"),
            t("Blood gases and acid-base", "arterial blood gas, acidosis, alkalosis, anion gap, bicarbonate, lactate"),
            t("Cardiac and other markers", "troponin, bnp, creatine kinase, amylase, lipase, crp"),
            t("Glucose and lipids", "glucose, hba1c, cholesterol, triglyceride, lipid profile"),
            t("Calcium, phosphate and bone", "calcium, phosphate, magnesium, pth, parathyroid hormone"),
            t("Therapeutic drug levels", "therapeutic drug monitoring, drug level, digoxin level, lithium level, gentamicin level"),
        ]),
        area("Clinical pharmacology and therapeutics", pharmacology),
        area("Medicine of older adults", olderAdults),
        area("Allergy and immunology", immunology),
        area("Genetics and genomics", genetics),
        area("Laboratory haematology", [
            t("Full blood count", "full blood count, haemoglobin, mcv, white cell count, platelet count"),
            t("Blood film", "blood film, target cell, schistocyte, spherocyte, reticulocyte"),
            t("Coagulation tests", "prothrombin time, inr, aptt, fibrinogen, d dimer"),
            t("Haematinics", "ferritin, transferrin, b12, folate, iron studies"),
            t("Blood groups and cross-matching", "blood group, cross match, abo, rhesus, coombs"),
        ]),
        area("Social and population health", [
            t("Epidemiology", "incidence, prevalence, epidemiology, relative risk, odds ratio, cohort study, case control"),
            t("Screening", "screening, wilson and jungner, sensitivity, specificity, positive predictive value"),
            t("Health inequalities", "health inequality, inequalities, deprivation, social determinant"),
            t("Public health and prevention", "public health, notifiable disease, outbreak, primary prevention, secondary prevention"),
            t("Evidence-based medicine", "evidence based, randomised controlled trial, systematic review, meta analysis, confidence interval, number needed to treat"),
        ]),
        area("Professional knowledge and ethics", ethics),
    ]

    // MARK: - USMLE Step 1 / Step 2 CK (systems)

    static let usmle: [SyllabusArea] = [
        area("General principles", [
            t("Biochemistry and molecular biology", "dna, rna, enzyme, glycolysis, krebs cycle, gluconeogenesis, metabolism, lysosomal storage, glycogen storage"),
            t("Genetics", "mutation, chromosome, inheritance, autosomal dominant, autosomal recessive, x linked, gene"),
            t("Cell biology and histology", "cell cycle, organelle, collagen, cytoskeleton, histology, epithelium"),
            t("Microbiology principles", "bacteria, gram positive, gram negative, virus, virulence factor, exotoxin, endotoxin"),
            t("Pathology: cell injury and inflammation", "necrosis, apoptosis, inflammation, cell injury, amyloid, wound healing"),
            t("Neoplasia", "neoplasia, oncogene, tumour suppressor, carcinogen, metastasis"),
            t("Pharmacology principles", "pharmacokinetic, pharmacodynamic, half life, agonist, antagonist, autonomic drug"),
            t("Nutrition and vitamins", "vitamin, malnutrition, kwashiorkor, marasmus, scurvy, beriberi"),
        ]),
        area("Immune system", immunology),
        area("Blood and lymphoreticular system", haematology),
        area("Behavioral health", mentalHealth + [
            t("Sleep disorders", "insomnia, narcolepsy, sleep disorder, sleep"),
            t("Neurodevelopmental disorders", "adhd, autism, tourette, intellectual disability"),
        ]),
        area("Nervous system and special senses", neurology + [
            t("Neuroanatomy and neurophysiology", "brainstem, cranial nerve, neurotransmitter, cerebellum, basal ganglia, internal capsule"),
            t("Eye", "glaucoma, cataract, retinopathy, uveitis, visual field, macular degeneration"),
            t("Ear", "hearing loss, vertigo, otitis media, tinnitus, meniere"),
        ]),
        area("Skin and subcutaneous tissue", dermatology),
        area("Musculoskeletal system", rheumatology + [
            t("Musculoskeletal anatomy", "brachial plexus, rotator cuff, muscle, carpal tunnel, lumbosacral plexus"),
        ]),
        area("Cardiovascular system", cardiology + [
            t("Cardiac physiology", "cardiac output, preload, afterload, cardiac action potential, cardiac cycle, pressure volume loop"),
        ]),
        area("Respiratory system", respiratory + [
            t("Respiratory physiology", "ventilation perfusion, compliance, oxygen dissociation curve, dead space, lung volume, surfactant"),
        ]),
        area("Gastrointestinal system", gastro + [
            t("GI physiology", "gastrin, secretin, cholecystokinin, bile acid, gastric acid secretion"),
        ]),
        area("Renal and urinary system", renal + [
            t("Renal physiology", "nephron, glomerular filtration, renin angiotensin, diuretic, loop of henle, collecting duct"),
        ]),
        area("Pregnancy, childbirth and the puerperium", obstetrics),
        area("Female reproductive system and breast", gynaecology),
        area("Male reproductive system", [
            t("Prostate", "benign prostatic hyperplasia, bph, prostate cancer, prostatitis, psa"),
            t("Testis and scrotum", "testicular cancer, testicular torsion, varicocele, hydrocele, cryptorchidism"),
            t("Sexual function and hypogonadism", "erectile dysfunction, hypogonadism, testosterone, infertility"),
            t("Male reproductive anatomy and physiology", "spermatogenesis, sertoli, leydig, male reproductive"),
            t("Penile and urethral disease", "hypospadias, phimosis, peyronie, urethritis"),
        ]),
        area("Endocrine system", endocrine),
        area("Multisystem processes and disorders", [
            t("Temperature regulation", "hypothermia, heat stroke, fever, malignant hyperthermia"),
            t("Multisystem disease", "sarcoidosis, amyloidosis, sepsis, multi organ failure"),
            t("Fluid and electrolyte balance", "dehydration, fluid balance, hyponatraemia, hyperkalaemia"),
            t("Poisoning and environmental injury", "poisoning, carbon monoxide, overdose, envenomation, burns, drowning"),
            t("Nutrition", "malnutrition, obesity, vitamin deficiency, refeeding"),
        ]),
        area("Biostatistics and epidemiology", epidemiology + [
            t("Prevention and population health", "primary prevention, secondary prevention, tertiary prevention, vaccination, outbreak"),
        ]),
        area("Social sciences, ethics and communication", ethics + [
            t("Health care systems", "medicare, medicaid, health insurance, hospice"),
        ]),
    ]

    // MARK: - MRCP(UK) Part 1 (specialties)

    static let mrcp: [SyllabusArea] = [
        area("Cardiology", cardiology),
        area("Clinical pharmacology", pharmacology),
        area("Clinical sciences", [
            t("Cell and molecular biology", "cell cycle, dna, rna, apoptosis, signal transduction, pcr"),
            t("Biochemistry and metabolism", "enzyme, metabolism, lipid metabolism, porphyria, inborn error"),
            t("Genetics", "inheritance, autosomal dominant, autosomal recessive, x linked, chromosome, trinucleotide repeat"),
            t("Immunology", "antibody, t cell, b cell, complement, cytokine, hypersensitivity, immunodeficiency"),
            t("Statistics and epidemiology", "sensitivity, specificity, p value, confidence interval, relative risk, number needed to treat, study design"),
            t("Physiology", "physiology, cardiac output, renal physiology, respiratory physiology, action potential"),
            t("Anatomy", "anatomy, cranial nerve, brachial plexus, dermatome"),
        ]),
        area("Dermatology", dermatology),
        area("Endocrinology", endocrine),
        area("Gastroenterology", gastro),
        area("Geriatric medicine", olderAdults),
        area("Haematology", haematology),
        area("Infectious diseases", infection + [
            t("Sexually transmitted infections", "chlamydia, gonorrhoea, syphilis, sexually transmitted, genital herpes"),
        ]),
        area("Nephrology", renal),
        area("Neurology", neurology),
        area("Oncology", oncology + [
            t("Palliative care", "palliative, end of life, syringe driver, symptom control"),
        ]),
        area("Ophthalmology", ophthalmology),
        area("Psychiatry", mentalHealth),
        area("Respiratory medicine", respiratory),
        area("Rheumatology", rheumatology),
    ]

    // MARK: - MRCS Part A

    static let mrcs: [SyllabusArea] = [
        area("Applied surgical anatomy", [
            t("Thorax", "mediastinum, thoracic, intercostal, diaphragm, phrenic nerve, pleura, heart anatomy"),
            t("Abdomen", "peritoneum, inguinal canal, abdominal wall, coeliac trunk, superior mesenteric, portal vein, retroperitoneum"),
            t("Pelvis and perineum", "pelvis, perineum, pudendal, ureter, rectum, pelvic floor"),
            t("Upper limb", "brachial plexus, median nerve, ulnar nerve, radial nerve, axillary nerve, rotator cuff, carpal tunnel, cubital fossa"),
            t("Lower limb", "femoral triangle, sciatic nerve, common peroneal, common fibular, popliteal fossa, femoral nerve, tibial nerve"),
            t("Head and neck", "cranial nerve, parotid, carotid sheath, triangles of the neck, larynx, thyroid gland, recurrent laryngeal"),
            t("Neuroanatomy", "brainstem, spinal cord, circle of willis, cerebellum, internal capsule, dural venous sinus"),
            t("Spine and back", "vertebra, vertebral column, spinal nerve, intervertebral disc"),
        ]),
        area("Applied physiology", [
            t("Cardiovascular physiology", "cardiac output, preload, afterload, starling, blood pressure regulation, baroreceptor"),
            t("Respiratory physiology", "ventilation perfusion, compliance, oxygen dissociation curve, dead space, lung volume"),
            t("Renal physiology and fluids", "glomerular filtration, renin angiotensin, loop of henle, antidiuretic hormone, fluid compartment"),
            t("Gastrointestinal physiology", "gastrin, secretin, cholecystokinin, bile, gastric emptying"),
            t("Metabolic response to surgery", "stress response, metabolic response to injury, catabolism, cortisol response"),
            t("Acid-base", "acid base, acidosis, alkalosis, henderson hasselbalch, bicarbonate"),
            t("Haemostasis", "haemostasis, coagulation cascade, platelet, fibrinolysis, clotting factor"),
            t("Thermoregulation and endocrine physiology", "thermoregulation, hypothermia, thyroid hormone, adrenal, insulin"),
        ]),
        area("Applied pathology", [
            t("Inflammation and healing", "inflammation, wound healing, granulation tissue, scar, keloid, repair"),
            t("Cell injury and necrosis", "necrosis, apoptosis, cell injury, gangrene, infarction"),
            t("Neoplasia", "neoplasia, carcinogenesis, metastasis, tumour, dysplasia, metaplasia, benign, malignant"),
            t("Thrombosis, embolism and infarction", "thrombosis, embolism, virchow, fat embolism, infarct"),
            t("Atherosclerosis and vascular pathology", "atherosclerosis, atheroma, aneurysm, arteritis"),
            t("Surgical microbiology", "surgical site infection, mrsa, sterilisation, asepsis, antibiotic prophylaxis, necrotising fasciitis"),
            t("Immunology and transplant", "transplant, rejection, immunosuppression, hypersensitivity"),
        ]),
        area("Perioperative care", perioperative + [
            t("Blood transfusion in surgery", "blood transfusion, transfusion reaction, massive transfusion, cell salvage"),
        ]),
        area("Trauma", [
            t("ATLS and the primary survey", "atls, primary survey, abcde, trauma, secondary survey"),
            t("Head injury", "head injury, extradural haematoma, subdural haematoma, glasgow coma scale, raised intracranial pressure"),
            t("Chest trauma", "haemothorax, tension pneumothorax, flail chest, cardiac tamponade, chest trauma"),
            t("Abdominal and pelvic trauma", "splenic injury, liver laceration, fast scan, pelvic fracture, abdominal trauma"),
            t("Burns", "burn, burns, parkland formula, escharotomy"),
            t("Spinal injury", "spinal injury, cervical spine, spinal shock, neurogenic shock"),
            t("Musculoskeletal trauma", "fracture, compartment syndrome, open fracture, dislocation"),
            t("Haemorrhagic shock", "haemorrhagic shock, hypovolaemic shock, major haemorrhage, tranexamic acid"),
        ]),
        area("Surgical care of the paediatric patient", [
            t("Pyloric stenosis and intussusception", "pyloric stenosis, intussusception"),
            t("Congenital anomalies", "congenital diaphragmatic hernia, tracheo oesophageal fistula, hirschsprung, malrotation, gastroschisis, exomphalos"),
            t("Groin and scrotum in children", "undescended testis, inguinal hernia in children, hydrocele, testicular torsion"),
            t("Paediatric fluids and physiology", "paediatric fluid, child weight, paediatric physiology"),
            t("Consent and safeguarding in children", "gillick, parental consent, safeguarding, non accidental injury"),
        ]),
        area("Surgical oncology", [
            t("Principles of cancer surgery", "resection margin, lymphadenectomy, curative surgery, palliative surgery, multidisciplinary team"),
            t("Staging and grading", "staging, tnm, grading, sentinel node"),
            t("Screening", "screening, bowel screening, breast screening"),
            t("Adjuvant and neoadjuvant therapy", "adjuvant, neoadjuvant, chemotherapy, radiotherapy"),
            t("Common surgical cancers", "colorectal cancer, breast cancer, oesophageal cancer, gastric cancer, pancreatic cancer, melanoma"),
        ]),
        area("Critical care", [
            t("Sepsis and multi-organ failure", "sepsis, septic shock, multi organ failure, sofa"),
            t("Respiratory support", "mechanical ventilation, ards, acute respiratory distress, tracheostomy"),
            t("Cardiovascular support", "inotrope, vasopressor, noradrenaline, arterial line, central line"),
            t("Renal support", "renal replacement therapy, haemofiltration, acute kidney injury"),
            t("Monitoring", "central venous pressure, arterial blood gas, lactate, cardiac output monitoring"),
        ]),
        area("Surgical technique and technology", [
            t("Sutures and wound closure", "suture, wound closure, stapler, knot, skin closure"),
            t("Diathermy and energy devices", "diathermy, electrosurgery, harmonic scalpel"),
            t("Laparoscopic surgery", "laparoscopy, laparoscopic, pneumoperitoneum, minimally invasive"),
            t("Tourniquets, drains and dressings", "tourniquet, surgical drain, dressing"),
            t("Surgical safety", "who checklist, surgical safety, sterile field, swab count"),
        ]),
        area("Professional practice and ethics", ethics),
    ]
}
