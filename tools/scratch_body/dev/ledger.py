"""ledger.py [--book <text of Gray 1918, one page a form feed>]: write ../LEDGER.md, the list of every named detail of the
skull with what the from-scratch model has of it.

The owner, 13 November: "trace every single bone irregularities in the image to the 3d models" and "check for details of
bones in free for commercial use sources that u didn't incorporate in the bones". This is the list that work is ticked
off against. The names are those Gray's Anatomy (20th edition, 1918, public domain) uses in its account of the skull
(pages 129 to 198). The page beside each name is found by searching the book's own text for it, never written from
memory; a name the search does not find keeps the page it was given before, or none.

A row: (bone, name, what to search the book for, state, where it is made or what is lacking).
state  built    a shape of its own, read from a plate, looked at in a picture
       plain    there, but only as part of a larger traced form, with no detail of its own
       missing  not there
"""
import os, re, sys, json

HERE = os.path.dirname(os.path.abspath(__file__))
PAGES = (129, 198)

ROWS = [
    # ---------------- frontal ----------------
    ("Frontal", "frontal eminence", r"frontal eminence", "plain", "the braincase's traced outline (skull2.braincase)"),
    ("Frontal", "superciliary arch", r"superciliary arch", "plain", "the face's relief through traced points (skull2.face); no arch of its own"),
    ("Frontal", "glabella", r"glabella", "plain", "a point of the traced profile (landmarks.py)"),
    ("Frontal", "supraorbital margin", r"supraorbital margin", "built", "skull2.orbit_margin: the orbit's rim as traced"),
    ("Frontal", "supraorbital notch or foramen", r"supraorbital notch", "built", "a shallow notch cut in the orbit's upper rim, 5 mm wide (skull2.build)"),
    ("Frontal", "zygomatic process", r"zygomatic process", "built", "its hind edge is the temporal crest traced on Fig. 188 (temporal.FRONTAL_CREST), the fossa hollowed behind it (temporal.fossa_front); the suture below it is in the split (bones.py)"),
    ("Frontal", "temporal line", r"temporal line", "built", "temporal.lines_relief: the crest on the frontal bone, traced on Fig. 188"),
    ("Frontal", "nasal part and nasal spine", r"nasal (part|spine)", "missing", "the nasal bones meet the frontal bone on a plain wall"),
    ("Frontal", "orbital plate (roof of the orbit)", r"orbital (plates|part)", "plain", "the orbit's funnel (skull2.build)"),
    ("Frontal", "fossa for the lacrimal gland", r"lacrimal fossa", "missing", ""),
    ("Frontal", "trochlear fovea", r"fovea trochlearis|trochlear fovea", "missing", ""),
    ("Frontal", "frontal sinus", r"frontal (air )?sinus", "missing", "the bone is solid"),
    ("Frontal", "inside: frontal crest, foramen cecum, sagittal sulcus", r"frontal crest", "missing", "the cranial cavity is one smooth hollow"),
    # ---------------- parietal ----------------
    ("Parietal", "parietal eminence", r"parietal eminence", "plain", "the braincase's traced outline"),
    ("Parietal", "superior and inferior temporal lines", r"temporal lines", "built", "temporal.lines_relief: two low lines over the parietal, traced on Fig. 188; they still read as a very regular arc"),
    ("Parietal", "parietal foramen", r"parietal foramen", "missing", ""),
    ("Parietal", "inside: grooves for the middle meningeal vessels, sagittal sulcus", r"middle meningeal", "missing", "the cranial cavity is one smooth hollow"),
    # ---------------- occipital ----------------
    ("Occipital", "external occipital protuberance", r"external occipital protuberance", "built", "occiput.py"),
    ("Occipital", "highest nuchal line", r"highest nuchal line", "missing", ""),
    ("Occipital", "superior nuchal line", r"superior nuchal line", "built", "occiput.py: the traced strip, a broad low swell"),
    ("Occipital", "median nuchal line (external occipital crest)", r"median nuchal line", "built", "occiput.py"),
    ("Occipital", "inferior nuchal line and the muscles' areas", r"inferior nuchal line", "built", "occiput.py: the four areas the plate rings, sunk, with the lips between them"),
    ("Occipital", "foramen magnum", r"foramen magnum", "built", "foramina.py: the plate's own outline"),
    ("Occipital", "condyles", r"condyles", "built", "foramina.condyles: the facet's traced kidney, the sloping inner side"),
    ("Occipital", "condyloid fossa and canal", r"condyloid (fossa|canal)", "built", "foramina.py: the hollow behind the condyle, the canal's mouth"),
    ("Occipital", "hypoglossal canal", r"hypoglossal canal", "built", "foramina.py"),
    ("Occipital", "jugular process and jugular notch", r"jugular process", "plain", "the base's relief (base.py); the jugular foramen is built"),
    ("Occipital", "pharyngeal tubercle", r"pharyngeal tubercle", "built", "foramina.py: pressed in with the base's small relief"),
    ("Occipital", "basilar part", r"basilar part", "built", "base.py: heights from the sagittal section (Fig. 194)"),
    ("Occipital", "inside: cruciate eminence, internal protuberance, grooves for the sinuses, the four fossae", r"cruciate eminence", "missing", "the cranial cavity is one smooth hollow"),
    # ---------------- temporal ----------------
    ("Temporal", "squama", r"squama", "plain", "the braincase's wall; its suture is cut"),
    ("Temporal", "zygomatic process and its roots", r"zygomatic process", "built", "skull2.cheek, temporal.py; the root over the joint is still a lump"),
    ("Temporal", "supramastoid crest", r"supramastoid crest", "built", "temporal.relief"),
    ("Temporal", "suprameatal triangle and spine", r"suprameatal", "built", "temporal.relief"),
    ("Temporal", "articular tubercle", r"articular tubercle", "built", "base.py: the slope from the socket's roof to the tubercle's crest"),
    ("Temporal", "mandibular fossa", r"mandibular fossa", "built", "base.py, base.socket_cut"),
    ("Temporal", "postglenoid process", r"postglenoid", "built", "temporal.ear_hole: the small process between the ear hole and the socket"),
    ("Temporal", "petrotympanic fissure", r"petrotympanic fissure", "missing", ""),
    ("Temporal", "external acoustic meatus", r"external acoustic meatus", "built", "temporal.ear_hole; its rim is too even"),
    ("Temporal", "tympanic part", r"tympanic part", "built", "temporal.py: the thick rough lip round the ear hole"),
    ("Temporal", "mastoid process", r"mastoid process", "built", "skull2.build, on its traced outline"),
    ("Temporal", "mastoid notch (digastric) and occipital groove", r"mastoid notch", "built", "skull2.build"),
    ("Temporal", "mastoid foramen", r"mastoid foramen", "missing", "finer than the grid: as a pit it came out as a crater"),
    ("Temporal", "styloid process and its sheath (vaginal process)", r"styloid process", "built", "temporal.py"),
    ("Temporal", "stylomastoid foramen", r"stylomastoid foramen", "built", "foramina.py"),
    ("Temporal", "carotid canal", r"carotid canal", "built", "foramina.py"),
    ("Temporal", "jugular fossa", r"jugular fossa", "built", "foramina.py: the hollow and the opening"),
    ("Temporal", "inferior tympanic and mastoid canaliculi, cochlear aqueduct", r"canaliculus", "built", "foramina.py: three small mouths where the plate places them"),
    ("Temporal", "petrous part, under surface", r"petrous portion|petrous part", "built", "base.py"),
    ("Temporal", "inside: internal acoustic meatus, arcuate eminence, tegmen, sigmoid sulcus", r"internal acoustic meatus", "missing", "the cranial cavity is one smooth hollow"),
    # ---------------- sphenoid ----------------
    ("Sphenoid", "body: sella turcica, dorsum sellae, clinoid processes", r"sella turcica", "missing", "the cranial cavity is one smooth hollow"),
    ("Sphenoid", "sphenoidal sinuses", r"sphenoidal (air )?sinus", "missing", "the body is solid"),
    ("Sphenoid", "rostrum", r"rostrum", "missing", "the vomer's wings are there; the beak they clasp is not"),
    ("Sphenoid", "small wings", r"small wings", "plain", "the orbit's roof behind; not shaped"),
    ("Sphenoid", "optic foramen", r"optic foramen", "plain", "a round tube (skull2.build)"),
    ("Sphenoid", "superior orbital fissure", r"superior orbital fissure", "plain", "a slit (skull2.build), not its true shape"),
    ("Sphenoid", "great wings: temporal and orbital surfaces", r"great wings", "plain", "the wall behind the orbit; marked off in the split"),
    ("Sphenoid", "infratemporal crest", r"infratemporal crest", "plain", "base.py: the crest the wing turns up at"),
    ("Sphenoid", "foramen rotundum", r"foramen rotundum", "missing", ""),
    ("Sphenoid", "foramen ovale", r"foramen ovale", "built", "foramina.py: the plate's leaf"),
    ("Sphenoid", "foramen spinosum and the spine", r"foramen spinosum", "built", "foramina.py, base.py"),
    ("Sphenoid", "lateral pterygoid plate", r"lateral pterygoid plate", "built", "pterygoid.py; thicker than the real one (the grid's limit)"),
    ("Sphenoid", "medial pterygoid plate and hamulus", r"pterygoid hamulus", "built", "pterygoid.py"),
    ("Sphenoid", "pterygoid fossa and scaphoid fossa", r"scaphoid fossa", "built", "pterygoid.py"),
    ("Sphenoid", "pterygoid canal", r"pterygoid canal", "missing", ""),
    ("Sphenoid", "vaginal process", r"vaginal process", "missing", ""),
    # ---------------- ethmoid ----------------
    ("Ethmoid", "cribriform plate and crista galli", r"crista galli", "missing", "the roof of the nose is solid; the cranial cavity smooth"),
    ("Ethmoid", "perpendicular plate", r"perpendicular plate", "built", "nose.septum"),
    ("Ethmoid", "labyrinth and its cells", r"labyrinth", "plain", "a solid block between the orbits"),
    ("Ethmoid", "lamina papyracea", r"lamina papyracea", "plain", "the orbit's inner wall; marked off in the split"),
    ("Ethmoid", "superior nasal concha", r"superior nasal concha", "missing", ""),
    ("Ethmoid", "middle nasal concha", r"middle nasal concha", "built", "nose.conchae"),
    ("Ethmoid", "uncinate process and bulla", r"uncinate process", "missing", ""),
    ("Ethmoid", "anterior and posterior ethmoidal foramina", r"ethmoidal (foramen|foramina|canal)", "missing", ""),
    # ---------------- nasal, lacrimal ----------------
    ("Nasal", "the bone and its borders", r"nasal bones", "built", "the face's relief; marked off in the split (bones.py)"),
    ("Lacrimal", "the bone", r"lacrimal bone", "plain", "a plate of the orbit's inner wall; marked off in the split"),
    ("Lacrimal", "posterior lacrimal crest, lacrimal sulcus, hamulus", r"posterior lacrimal crest", "missing", ""),
    # ---------------- maxilla ----------------
    ("Maxilla", "infraorbital foramen", r"infraorbital foramen", "built", "an oblique oval under an overhanging upper lip, its floor running out below (skull2.build)"),
    ("Maxilla", "infraorbital groove and canal", r"infraorbital groove", "built", "a gutter on the orbit's floor sinking into a curved canal to the foramen (skull2.build)"),
    ("Maxilla", "canine fossa", r"canine fossa", "built", "skull2 (face relief)"),
    ("Maxilla", "canine eminence and the swellings over the roots", r"canine eminence", "built", "skull2: the tooth-bearing process"),
    ("Maxilla", "incisive fossa (above the incisors)", r"incisive fossa", "plain", ""),
    ("Maxilla", "anterior nasal spine", r"anterior nasal spine", "built", "skull2.build: a three-cornered blade"),
    ("Maxilla", "nasal notch (the opening's rim)", r"nasal notch", "built", "skull2.aperture_rim, traced"),
    ("Maxilla", "frontal process", r"frontal process", "built", "skull2 (face relief)"),
    ("Maxilla", "anterior lacrimal crest and lacrimal groove", r"anterior lacrimal crest", "missing", "no canal for the tear duct"),
    ("Maxilla", "zygomatic process", r"zygomatic process", "built", "skull2 (face relief); its suture is in the split"),
    ("Maxilla", "maxillary tuberosity", r"maxillary tuberosity", "built", "skull2.build"),
    ("Maxilla", "alveolar canals on the back of the jaw", r"alveolar canals", "missing", ""),
    ("Maxilla", "alveolar process and the sockets", r"alveolar process", "built", "teeth.py: every tooth's own socket"),
    ("Maxilla", "palatine process", r"palatine process", "built", "palate.py"),
    ("Maxilla", "incisive foramen and canals", r"incisive (foramen|canals?)", "built", "palate.py"),
    ("Maxilla", "maxillary sinus", r"maxillary sinus", "missing", "the bone is solid"),
    # ---------------- zygomatic ----------------
    ("Zygomatic", "malar surface", r"malar surface", "built", "skull2.cheek"),
    ("Zygomatic", "zygomaticofacial foramen", r"zygomaticofacial foramen", "built", "the end of a fine canal from the orbital surface, opening obliquely on the cheek (skull2.build)"),
    ("Zygomatic", "frontosphenoidal process", r"frontosphenoidal process", "built", "skull2.cheek: a plate 5 to 6 mm thick, its hind border traced on Fig. 188 (ZYG_SIDE), hollowed behind along the orbit's outer wall"),
    ("Zygomatic", "temporal process and the arch", r"temporal process", "built", "skull2.cheek, at the usual breadth of 133 mm"),
    ("Zygomatic", "orbital surface and its foramina", r"zygomatico-?orbital", "built", "the orifices of the two canals (skull2.build)"),
    ("Zygomatic", "zygomaticotemporal foramen", r"zygomaticotemporal foramen", "built", "the second canal, through to the temporal fossa (skull2.build)"),
    # ---------------- palatine ----------------
    ("Palatine", "horizontal part", r"horizontal part", "built", "palate.py"),
    ("Palatine", "posterior nasal spine", r"posterior nasal spine", "built", "palate.py"),
    ("Palatine", "palatine crest", r"palatine crest|curved ridge", "built", "palate.py"),
    ("Palatine", "greater palatine foramen and groove", r"greater palatine foramen", "built", "palate.py"),
    ("Palatine", "lesser palatine foramina", r"lesser palatine foramina", "built", "palate.py"),
    ("Palatine", "pyramidal process", r"pyramidal process", "built", "pterygoid.py"),
    ("Palatine", "vertical part", r"vertical part", "plain", "the hind part of the nose's side wall; marked off in the split"),
    ("Palatine", "orbital and sphenoidal processes, sphenopalatine foramen", r"sphenopalatine foramen", "missing", ""),
    # ---------------- inferior concha, vomer ----------------
    ("Inferior nasal concha", "the scroll", r"inferior nasal concha", "built", "nose.conchae"),
    ("Inferior nasal concha", "lacrimal, ethmoidal and maxillary processes", r"maxillary process", "missing", ""),
    ("Vomer", "the plate and its free hind border", r"vomer", "built", "nose.septum"),
    ("Vomer", "alae", r"\bal(a|ae)\b", "built", "nose.septum: a leaf seen from below"),
    ("Vomer", "nasopalatine groove", r"nasopalatine", "missing", ""),
    # ---------------- mandible ----------------
    ("Mandible", "symphysis and mental protuberance", r"mental protuberance", "built", "mandible4.py"),
    ("Mandible", "mental tubercle", r"mental tubercle", "built", "mandible4.py"),
    ("Mandible", "incisive fossa", r"incisive fossa", "built", "mandible4.py"),
    ("Mandible", "mental foramen", r"mental foramen", "built", "opens backward and upward under a front and lower lip (mandible4.py)"),
    ("Mandible", "oblique line", r"oblique line", "built", "mandible4.py"),
    ("Mandible", "mental spines", r"mental spines", "built", "mandible4.py"),
    ("Mandible", "digastric fossa", r"digastric", "built", "mandible4.py"),
    ("Mandible", "mylohyoid line", r"mylohyoid line", "built", "mandible4.py"),
    ("Mandible", "hollows for the sublingual and submaxillary glands", r"submaxillary gland", "built", "mandible4.py"),
    ("Mandible", "alveolar border and the sockets", r"alveolar border", "built", "teeth.py"),
    ("Mandible", "ramus: ridges for the masseter and the medial pterygoid", r"masseter", "built", "mandible4.py"),
    ("Mandible", "mandibular foramen and lingula", r"lingula", "built", "mandible4.py"),
    ("Mandible", "mylohyoid groove", r"mylohyoid groove", "built", "mandible4.py"),
    ("Mandible", "coronoid process and mandibular notch", r"coronoid process", "built", "mandible4.py"),
    ("Mandible", "condyloid process: head, neck, the hollow for the lateral pterygoid", r"condyloid process", "built", "mandible4.py"),
    ("Mandible", "angle", r"angle of the mandible", "built", "mandible4.py: a round turn, about 118 degrees"),
    ("Mandible", "mandibular canal", r"mandibular canal", "missing", "inside the bone"),
    # ---------------- the skull as a whole ----------------
    ("Whole skull", "sutures of the vault: coronal, sagittal, lambdoidal, squamosal", r"lambdoidal suture", "built", "skull2.sutures, traced on Fig. 188 and checked over the plate (dev/plate_lines.py); toothed as Gray describes them, meeting at bregma and lambda"),
    ("Whole skull", "sutures round the great wing and the mastoid", r"sphenoparietal", "built", "skull2.sutures"),
    ("Whole skull", "sutures of the face", r"zygomaticomaxillary suture|frontonasal suture", "plain", "walls in the split (bones.py); not cut into the one-piece skull"),
    ("Whole skull", "sutures of the palate", r"palatine suture", "built", "palate.py"),
    ("Whole skull", "orbit: margin and four walls", r"orbital margin|margin of the orbit", "built", "skull2.build"),
    ("Whole skull", "inferior orbital fissure", r"inferior orbital fissure", "plain", "a slit, not its true shape"),
    ("Whole skull", "nasolacrimal canal", r"nasolacrimal canal", "missing", ""),
    ("Whole skull", "temporal fossa", r"temporal fossa", "built", "bounded by the temporal lines and the frontal crest (temporal.lines_relief), hollowed behind the cheek bone and the crest (temporal.fossa_front)"),
    ("Whole skull", "infratemporal fossa", r"infratemporal fossa", "built", "base.py, pterygoid.py"),
    ("Whole skull", "pterygomaxillary fissure and pterygopalatine fossa", r"pterygomaxillary fissure", "built", "pterygoid.py"),
    ("Whole skull", "choanae", r"choanae", "built", "left between the plates, the vomer, the body and the palate"),
    ("Whole skull", "foramen lacerum", r"foramen lacerum", "built", "foramina.py"),
    ("Whole skull", "jugular foramen", r"jugular foramen", "built", "foramina.py"),
    ("Whole skull", "inside of the skull: the three fossae and their markings", r"anterior fossa", "missing", "the cranial cavity is one smooth hollow"),
    ("Whole skull", "diploe and the bone's inner structure", r"diploe", "missing", ""),
]


def book_pages(path):
    """{row index: first page of PAGES on which the row's search finds something}."""
    text = open(path, encoding="utf-8", errors="replace").read().split("\f")
    norm = lambda t: re.sub(r"\s+", " ", re.sub(r"-\s*\n\s*", "", t.lower()))
    pages = {p: norm(text[p - 1]) for p in range(PAGES[0], PAGES[1] + 1) if p - 1 < len(text)}
    assert "base of skull" in pages[179] and "side view of the skull" in pages[182], "the text's pages are not the book's"
    # each bone's own account first, then the whole range
    own = {"Frontal": (135, 138), "Parietal": (133, 135), "Occipital": (129, 133), "Temporal": (138, 147), "Sphenoid": (147, 153),
           "Ethmoid": (153, 156), "Nasal": (156, 157), "Maxilla": (157, 163), "Lacrimal": (163, 164), "Zygomatic": (164, 166),
           "Palatine": (166, 169), "Inferior nasal concha": (169, 170), "Vomer": (170, 172), "Mandible": (172, 178), "Whole skull": (178, 198)}
    out = {}
    for i, (bone, name, rx, state, where) in enumerate(ROWS):
        a, b = own[bone]
        for p in list(range(a, b + 1)) + list(range(PAGES[0], PAGES[1] + 1)):
            if p in pages and re.search(rx, pages[p]):
                out[i] = p; break
    return out


def main():
    cache = os.path.join(HERE, "ledger_pages.json")
    pages = {int(k): v for k, v in json.load(open(cache)).items()} if os.path.exists(cache) else {}
    if "--book" in sys.argv:
        pages = book_pages(sys.argv[sys.argv.index("--book") + 1])
        json.dump({str(k): v for k, v in sorted(pages.items())}, open(cache, "w"), indent=0)
    n = {s: sum(r[3] == s for r in ROWS) for s in ("built", "plain", "missing")}
    L = ["# What the from-scratch skull has, detail by detail", "",
         "Written by `dev/ledger.py`; change the rows there, not here. The names are Gray's (Anatomy, 20th edition, 1918,",
         "public domain), and the page beside each is where a search of the book's text finds it.", "",
         "- **built**: a shape of its own, read from a plate and looked at in a picture",
         "- **plain**: there, but only as part of a larger traced form",
         "- **missing**: not there", "",
         "Of %d details: %d built, %d plain, %d missing." % (len(ROWS), n["built"], n["plain"], n["missing"]), ""]
    bone = None
    for i, (b, name, rx, state, where) in enumerate(ROWS):
        if b != bone:
            bone = b
            k = [r[3] for r in ROWS if r[0] == b]
            L += ["", "## %s (%d of %d built)" % (b, k.count("built"), len(k)), "", "| Detail | State | Where, or what is lacking | Gray, page |", "| --- | --- | --- | --- |"]
        L.append("| %s | %s | %s | %s |" % (name, state, where, pages.get(i, "")))
    open(os.path.join(os.path.dirname(HERE), "LEDGER.md"), "w").write("\n".join(L) + "\n")
    print("%d details: %d built, %d plain, %d missing; %d with a page found" % (len(ROWS), n["built"], n["plain"], n["missing"], len(pages)))
    for i, r in enumerate(ROWS):
        if i not in pages:
            print("  no page found for:", r[0], "/", r[1])


if __name__ == "__main__":
    main()
