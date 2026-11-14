"""structure_doc.py: write STRUCTURE.md from structure.TABLE: every bone, part by part, and the kind of bone in each."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import structure
here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORD = {"compact": "compact", "cancellous": "cancellous (spongy)", "air": "air cells or a sinus", "marrow canal": "a marrow (medullary) canal"}
out = ["# What each bone is made of, part by part", "",
       "The owner's order of 14 November: \"make bones compact - cancellous - spongy in each place each one should be and in each",
       "part of each bone. some bones also combine multiple types.\"", "",
       "Written by `dev/structure_doc.py` from the table in `structure.py`. The page is that of Gray's Anatomy, 20th edition, 1918",
       "(public domain). Words in quotation marks are Gray's; a line without them is the rule the model follows, in our words.",
       "\"Built\" says whether the from-scratch model has it yet.", "",
       "| Bone | Part | Made of | Gray | His words, or the rule | Built |", "| --- | --- | --- | --- | --- | --- |"]
n = {"yes": 0, "no": 0}
for bone, part, kinds, page, words, built in structure.TABLE:
    said = words[1:] if words.startswith("~") else "\"%s\"" % words
    out.append("| %s | %s | %s | p. %d | %s | %s |" % (bone, part, ", ".join(WORD[k] for k in kinds), page, said, built))
    if built != "rule":
        n["yes" if built.startswith(("yes", "as")) else "no"] += 1
out += ["", "%d parts built, %d not yet (the bones below the head are not built at all)." % (n["yes"], n["no"]), ""]
open(os.path.join(here, "STRUCTURE.md"), "w").write("\n".join(out))
print("STRUCTURE.md: %d rows; %d built, %d not yet" % (len(structure.TABLE), n["yes"], n["no"]))
