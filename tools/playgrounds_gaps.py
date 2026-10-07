#!/usr/bin/env python3
"""Names an assembled Playgrounds package still uses that only dropped files
declared, so a missing stand-in shows here instead of in the Mac build.

  playgrounds_gaps.py <ios/RedPen> <assembled .swiftpm folder>

A type is "gone" when the full app declares it at the top level and nothing in
the package (its own files or the stand-ins, at any depth) does. Code under
`#if ... !SWIFT_PACKAGE` is skipped, since the package never compiles it.
Exit 1, with each name and the files using it, when any gone type is used.
"""
import os, re, sys

MOD = r'(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:nonisolated|public|internal|private|fileprivate|final|indirect|open|package)\s+)*'
TOP = re.compile(r'^' + MOD + r'(?:struct|class|enum|actor|protocol|typealias)\s+([A-Za-z_]\w*)', re.M)
ANY = re.compile(r'^\s*' + MOD + r'(?:struct|class|enum|actor|protocol|typealias)\s+([A-Za-z_]\w*)', re.M)
TYPE = re.compile(r'\b[A-Z]\w*\b')


def swift_files(root):
    for folder, _, names in os.walk(root):
        if "/Tests" in folder or folder.endswith("/Tests"):
            continue
        for n in names:
            if n.endswith(".swift"):
                yield os.path.join(folder, n)


def compiled(text):
    """The text a Swift package build reads: blocks under `#if ... !SWIFT_PACKAGE`
    (up to their #else or #endif) are dropped, comments and strings blanked."""
    out, stack = [], []
    for line in text.split("\n"):
        s = line.strip()
        if s.startswith("#if"):
            stack.append("!SWIFT_PACKAGE" in s)
            continue
        if s.startswith("#elseif") or s.startswith("#else"):
            if stack:
                stack[-1] = False
            continue
        if s.startswith("#endif"):
            if stack:
                stack.pop()
            continue
        if not any(stack):
            out.append(line)
    t = "\n".join(out)
    t = re.sub(r'/\*.*?\*/', '', t, flags=re.S)
    t = re.sub(r'//[^\n]*', '', t)
    t = re.sub(r'"""(?:.|\n)*?"""', '""', t)
    return re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', t)


def main():
    full, pkg = sys.argv[1], sys.argv[2]
    app = set()
    for p in swift_files(full):
        app |= set(TOP.findall(open(p, errors="replace").read()))
    texts = {p: compiled(open(p, errors="replace").read()) for p in swift_files(pkg)}
    have = set()
    for t in texts.values():
        have |= set(ANY.findall(t))
    gone = app - have
    users = {}
    for p, t in texts.items():
        for n in set(TYPE.findall(t)) & gone:
            users.setdefault(n, []).append(os.path.relpath(p, pkg))
    for n in sorted(users):
        print(f"  {n} (dropped) used by {', '.join(sorted(users[n])[:3])}")
    return 1 if users else 0


sys.exit(main())
