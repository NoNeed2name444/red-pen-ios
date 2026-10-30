# The Sciences: what each source may give the app

The owner asked for the core sciences "ALL FROM FREE FOR COMMERCIAL USE
SOURCES". This ledger is how that is kept. It follows Chat-me brief §23f §3:

- **Admitted:** CC0, CC BY, public domain and U.S. government works, with
  the licence read from the source's own page or file, and each file or item
  checked on its own where a site mixes licences.
- **Refused:** CC BY-SA (whatever is made from it must carry ShareAlike),
  CC BY-ND (the app adapts what it uses), NC, custom or unclear terms, and
  anything whose upstream terms conflict with the licence it is offered
  under.
- **Everything else can only inform.** A source that is not admitted may be
  read to understand a subject, but nothing is copied from it: no text,
  figures, meshes or tables.
- **Facts are written fresh.** Equations, constants, pathways and the
  textbook ranges in Shared/Sciences are facts, written in the app's own
  words. Only identifiers point outward, to open databases, so a student can
  check them.

Every admitted source the app ships is credited in Settings, Sources
(`ContentSources` in Shared/ContentCredits.swift), with what was changed
where CC BY asks. The licences below were read on 29 Oct 2026.

## In the app now

| Source | What the app has from it | Licence | Where |
|---|---|---|---|
| HRA 3D Reference Organ Set for Male, v1.10 | The 3D atlas's male body: 33 parts, 865 structures | CC BY 4.0 (release metadata) | Resources/Anatomy, its SOURCES.md |
| HRA 3D Reference Organ Set for Female, v1.10 | The 3D atlas's female body: 35 parts, 900 structures | CC BY 4.0 (release metadata, checked 2026-10-29) | Resources/Anatomy, its SOURCES.md |
| HRA ASCT+B 3D crosswalk, v1.10 | The atlas's labels and UBERON ids | CC BY 4.0 | Resources/Anatomy |
| NIH 3D 3DPX-020591, Skull and Eyes - Visible Human Male (kbrowne, NLM 3D: Anatomy) | The skull in both bodies: 13 named bones, paired ones split left and right | CC BY 4.0 (stated on the entry) | Resources/Anatomy, via tools/anatomy_gaps.py |
| TotalSegmentator dataset v3.0.0 (Wasserthal et al.; Zenodo 22688904) | Three CT scans, s1803 (a man), s1764 (a woman) and s1880 (a man, for his forearm and hand): the ribs and costal cartilages, the male sternum, clavicles, scapulae, humeri, the radius, ulna, carpus, metacarpals and phalanges (cut from the CT itself, which the dataset does not segment), gluteus maximus, medius and minimus, iliopsoas, the deep back muscles, thyroid, adrenals, oesophagus and stomach, in both bodies | CC BY 4.0 (record metadata) | Resources/Anatomy, via tools/anatomy_gaps.py |
| Visible Human Project (NLM) | The bodies the organ sets were made from | U.S. government; credit "Courtesy of the U.S. National Library of Medicine" | credited with the HRA |
| UBERON | Identifiers on atlas structures | CC BY 3.0 (uberon.owl header) | anatomy.json |
| Cell Ontology | Identifiers on immune cells | CC BY 4.0 (cl.owl header) | Immunology.swift |
| Reactome | Pathway identifiers | Data CC0; illustrations CC BY 4.0 | Biochemistry.swift |
| NCBI Taxonomy | Organism identifiers | NCBI places no restrictions on its data | Microbiology.swift |

Build-time tools, not shipped: numpy (BSD) and fast-simplification (MIT)
in tools/anatomy_atlas.py; scipy and scikit-image (BSD) and nibabel (MIT)
in tools/anatomy_gaps.py; pyamg (MIT) speeds the random-walker split in
tools/anatomy_limbs.py.

## Admitted, not used yet

These passed, for the gaps the plan names (plan.md, S3a to S3c and S4).

### Bones and muscles

- **TotalSegmentator v3**, beyond what the atlas takes from it: the other
  scans (1,939 in all), for the foot bones it does not segment but its CT
  volumes show, and for a second look at each part.
- **NIH 3D "My Segmenter" skeleton**, 3DPX-016799 to 016838 (CC BY 4.0), one
  bone per file. Which CT it came from is not stated, so ask its makers
  before shipping.
- **Single bones from different donors**, each CC BY 4.0, so their sizes do
  not match:
  - Eric Bauer / Elon University on Wikimedia Commons and Sketchfab (only
    the CC BY models; seven of theirs are CC BY-NC-ND);
  - UNCG Imaging Lab: talus, cuboid, hamate, patella, ribs;
  - the Zenodo 5192130 CAD foot, 19 bones (Franciosa and Gerbino).
- **NIH 3D 3DPX-012628 and 012629**, the Visible Human arm muscles (CC BY
  4.0). Each is one merged mesh, so they can only be unnamed context.

### Nerves

- **Sketchfab audreybyrd**, "Bony Pelvis with Neurovascular Supply from MRI"
  (CC BY 4.0, OSU Biomedical Imaging Laboratory). The lumbosacral plexus
  only.
- **Visible Human cryosections and CT** (U.S. government). A clean base for
  tracing nerves here.

Everything else in nerves is drawn for the app.

### Images

- **CDC PHIL**, images marked Public Domain only. Credit CDC and the
  photographer, and name the site as the free source; never the CDC logo.
- **Wikimedia Commons**, per file. In a sample of 100 histology files, 46
  were public domain, 12 CC BY, 2 CC0 and 40 CC BY-SA (refused).
- **PMC Open Access figures**, from CC0 or CC BY articles only. Leave out
  any figure whose caption says it was reprinted with permission.

### Data and identifiers

- **WikiPathways:** CC0.
- **Rhea:** CC BY 4.0.
- **ChEBI:** CC BY 4.0.
- **UniProt:** CC BY 4.0.
- **RCSB PDB:** data CC0; the Molecule of the Month art is CC BY 4.0, but
  its article text is © RCSB and refused.
- **Gene Ontology:** CC BY 4.0.
- **Disease Ontology:** CC0.
- **MONDO:** CC BY 4.0.
- **Orphanet:** Orphadata Science only, CC BY 4.0. Other orpha.net content
  needs written consent.
- **NCBI Gene, ClinVar and PubChem:** NCBI's data policy, with care.
  Depositors may hold rights, so only NCBI-computed fields are admitted.

## Refused, and why

| Source | Terms | Why |
|---|---|---|
| BodyParts3D / Anatomography, Z-Anatomy | CC BY-SA 2.1 JP to 4.0 | ShareAlike. Also refused: whatever is made from them, among them SPARC dataset 307 (nerves and muscles placed on BodyParts3D) and Sketchfab models "based on Z-Anatomy" that are relabelled CC BY |
| OpenStax Anatomy & Physiology 2e | CC BY-NC-SA 4.0 | Non-commercial and ShareAlike (§23f §3) |
| FMA | No licence in the file; a 2006 draft licence; listed as custom | Unclear. UBERON's FMA cross-references are used instead |
| HPO | No changes allowed; site content for personal, non-commercial use | Custom terms |
| OpenSkeleton (Zenodo 23592083) | CC BY 4.0 on Zenodo, but the upstream NMDID agreement allows "only research or education" | The terms conflict. Escalated to the owner |
| Open Anatomy (SPL) atlases | 3D Slicer licence, section B | Custom terms that must travel with copies |
| MorphoSource human media | No CC0 or CC BY items; the rest unknown, NC, ND or SA | Nothing admissible |
| NIH 3D 3DPX-017249 (hand bones) | GNU GPLv3 | Not CC0 or CC BY |
| SimTK carpal bone database (Brown University) | A custom "MIT Use Agreement" on the project page; carpals and metacarpal bases only, no phalanges | Custom terms; and it would not give a whole hand |
| NIH 3D 3DPX-017321 (female pelvis with muscles) | CC BY 4.0, built from two Thingiverse models | Upstream licences unknown |
| Open Anatomy os coxae and scapula on Commons | GPLv3 | Not CC0 or CC BY |
| WHO publications, StatPearls, MedlinePlus licensed content | NC-SA, ND, or licensed to NLM | §23f §3 |

## Not verified

These are refused until each one is read:

- SPARC datasets 444 to 446 (their readme would not load).
- The Sketchfab brachial plexus models of unknown origin, and Sketchfab's
  own download terms.
- The CT behind the My Segmenter skeleton.
- The upstream permissions for BoneDat.
- ClinVar's own data-use page, and where NCBI Gene's summaries come from.

## Waiting on the owner

- **OpenSkeleton.** It is the most complete skeleton found, but it is under
  NMDID's terms. Ship it only with written leave for an app.
- **CC BY-SA meshes.** BodyParts3D and Z-Anatomy have every muscle and
  nerve. §23f refuses them because ShareAlike would reach the files made
  from them. The atlas stays without them unless the owner decides
  otherwise.
