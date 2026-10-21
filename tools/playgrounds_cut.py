#!/usr/bin/env python3
"""Measure a Playgrounds "core" cut of ios/RedPen.

  cut.py --drop 'Features/Notes/Graph*.swift,Features/Lens,...' [--keep-file X.swift,...] [--surface]

Prints the lines kept, the kept lines per folder, and the boundary surface: every
top-level name declared only in dropped files that a kept file still references,
with the referencing files and the call-site lines, so a stand-in can be written.
"""
import argparse, fnmatch, os, re, sys, collections
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ios", "RedPen"))
MOD = r'(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:nonisolated|public|internal|private|fileprivate|final|indirect|open|package)\s+)*'
DECL = re.compile(r'^' + MOD + r'(struct|class|enum|actor|protocol|typealias|func|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)', re.M)
EXT = re.compile(r'^' + MOD + r'extension\s+([A-Za-z_][A-Za-z0-9_.]*)', re.M)
IDENT = re.compile(r'\b[A-Za-z_][A-Za-z0-9_]*\b')

def strip(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'"""(?:.|\n)*?"""', '""', text)
    text = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)
    return text

def files():
    out = []
    for folder, _, names in os.walk(ROOT):
        if "/Tests" in folder or folder.endswith("/Tests"): continue
        for n in names:
            if n.endswith(".swift"): out.append(os.path.relpath(os.path.join(folder, n), ROOT))
    return sorted(out)

def matches(rel, patterns):
    for p in patterns:
        if fnmatch.fnmatch(rel, p) or rel.startswith(p.rstrip("/") + "/") or rel == p: return True
    return False

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--drop", default="")
    ap.add_argument("--keep-file", default="", help="basenames inside dropped folders that stay")
    ap.add_argument("--surface", action="store_true")
    ap.add_argument("--names", action="store_true", help="compact: name, declaring file, kept files using it")
    ap.add_argument("--by-user", action="store_true", help="per kept file: the dropped names it uses")
    ap.add_argument("--reach", default="", help="comma list of seed files (outside the tree allowed): kept files no seed reaches by name")
    ap.add_argument("--folders", action="store_true")
    a = ap.parse_args()
    drop = [p for p in a.drop.split(",") if p]
    keepf = set(p for p in a.keep_file.split(",") if p)
    allf = files()
    text, lines, decls = {}, {}, collections.defaultdict(set)
    for rel in allf:
        t = open(os.path.join(ROOT, rel), errors="replace").read()
        text[rel] = strip(t); lines[rel] = t.count("\n") + 1
        for m in DECL.finditer(t): decls[m.group(2)].add(rel)
    dropped = set(r for r in allf if matches(r, drop) and os.path.basename(r) not in keepf)
    kept = [r for r in allf if r not in dropped]
    total = sum(lines[r] for r in kept)
    print(f"kept {len(kept)} files, {total} lines; dropped {len(dropped)} files, {sum(lines[r] for r in dropped)} lines")
    if a.folders:
        per = collections.Counter()
        for r in kept:
            parts = r.split("/"); k = "/".join(parts[:2]) if parts[0] in ("Features", "Shared") and len(parts) > 2 else (parts[0] if len(parts) > 1 else "(root)")
            per[k] += lines[r]
        for k, v in per.most_common(): print(f"  {v:6d} {k}")
    # names declared only in dropped files
    gone = {n for n, fs in decls.items() if fs and fs <= dropped and len(n) > 2}
    surface = collections.defaultdict(list)
    for r in kept:
        idents = set(IDENT.findall(text[r]))
        for n in idents & gone:
            surface[n].append(r)
    print(f"surface: {len(surface)} names declared only in dropped files but used by kept files")
    if a.names:
        byfile = collections.defaultdict(list)
        for n in surface: byfile[sorted(decls[n])[0]].append(n)
        for f in sorted(byfile, key=lambda k: -len(byfile[k])):
            items = ", ".join(f"{n}({len(surface[n])})" for n in sorted(byfile[f], key=lambda k: -len(surface[k])))
            print(f"  {f}: {items}")
    if a.reach:
        declared_in = collections.defaultdict(set)
        for r in kept:
            for n, fs in decls.items():
                if r in fs: declared_in[r].add(n)
        name_to_files = collections.defaultdict(set)
        for r in kept:
            for n in declared_in[r]: name_to_files[n].add(r)
        refs = {r: set(IDENT.findall(text[r])) for r in kept}
        reached = set(); frontier = []
        for seed in a.reach.split(","):
            if not seed: continue
            t = strip(open(seed, errors="replace").read()) if os.path.exists(seed) else text.get(seed, "")
            for n in set(IDENT.findall(t)):
                for r in name_to_files.get(n, ()): 
                    if r not in reached: reached.add(r); frontier.append(r)
        while frontier:
            r = frontier.pop()
            for n in refs[r]:
                for r2 in name_to_files.get(n, ()):
                    if r2 not in reached: reached.add(r2); frontier.append(r2)
        unreached = [r for r in kept if r not in reached and declared_in[r]]
        print(f"reach: {len(reached)} kept files reached from the seeds; {len(unreached)} kept files with declarations not reached ({sum(lines[r] for r in unreached)} lines):")
        for r in sorted(unreached, key=lambda k: -lines[k]): print(f"  {lines[r]:5d} {r}  [{', '.join(sorted(declared_in[r])[:4])}]")
    if a.by_user:
        users = collections.defaultdict(list)
        for n, fs in surface.items():
            for f in fs: users[f].append(n)
        for f in sorted(users, key=lambda k: -len(users[k])):
            print(f"  {f} ({lines[f]}): {', '.join(sorted(users[f]))}")
    if a.surface:
        for n in sorted(surface, key=lambda k: (-len(surface[k]), k)):
            where = sorted(decls[n])[0]
            print(f"\n- {n}  (declared in {where}) used by {len(surface[n])} kept files")
            shown = 0
            for r in surface[n]:
                for i, line in enumerate(open(os.path.join(ROOT, r), errors="replace").read().split("\n"), 1):
                    if re.search(r'\b' + re.escape(n) + r'\b', line) and not line.strip().startswith("//"):
                        print(f"    {r}:{i}: {line.strip()[:150]}"); shown += 1
                        if shown >= 6: break
                if shown >= 6: break
main()
