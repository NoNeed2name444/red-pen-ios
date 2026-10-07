#!/usr/bin/env python3
"""Names an assembled Playgrounds package still uses that only dropped files
declared, so a missing stand-in shows here instead of in the Mac build.

  playgrounds_gaps.py <ios/RedPen> <assembled .swiftpm folder>

A type is "gone" when the full app declares it at the top level and nothing in
the package (its own files or the stand-ins, at any depth) does. A stand-in
type (declared under Shared/PlaygroundsStubs) is also short when a kept file
names `Type.member` and neither the stand-in nor an extension of it declares
that member. Code under `#if ... !SWIFT_PACKAGE` is skipped, since the
package never compiles it. Exit 1, naming each gap and the files using it.
"""
import os, re, sys

MOD = r'(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:nonisolated|public|internal|private|fileprivate|final|indirect|open|package)\s+)*'
TOP = re.compile(r'^' + MOD + r'(?:struct|class|enum|actor|protocol|typealias)\s+([A-Za-z_]\w*)', re.M)
ANY = re.compile(r'^\s*' + MOD + r'(?:struct|class|enum|actor|protocol|typealias)\s+([A-Za-z_]\w*)', re.M)
KIND = re.compile(r'^\s*' + MOD + r'(?:struct|class|enum|actor|protocol)\s+([A-Za-z_]\w*)', re.M)
TYPE = re.compile(r'\b[A-Z]\w*\b')
NAME = r'[A-Za-z_]\w*'
MEMBER = re.compile(r'\b(?:let|var|func|case)\s+((?:' + NAME + r'(?:\([^)]*\))?(?:\s*=\s*[^,\n]+)?\s*,\s*)*' + NAME + ')')
STUBS = os.path.join("Shared", "PlaygroundsStubs")


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


def body(text, start):
    """What sits between the first `{` after start and its matching `}`."""
    i = text.find("{", start)
    if i < 0:
        return ""
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
    return text[i + 1:]


def members(chunk):
    found = set()
    for m in MEMBER.finditer(chunk):
        for part in m.group(1).split(","):
            found.add(re.match(r'\s*(' + NAME + ')', part).group(1))
    return found


def short_members(texts, pkg):
    """`Stand-in.member` uses whose member no stand-in or extension declares."""
    stand_ins = set()
    for p, t in texts.items():
        if os.path.relpath(p, pkg).startswith(STUBS):
            stand_ins |= set(KIND.findall(t))
    gaps = {}
    for name in stand_ins:
        decl = re.compile(r'^\s*' + MOD + r'(?:struct|class|enum|actor|protocol|extension)\s+' + name + r'\b', re.M)
        have = set()
        for t in texts.values():
            for m in decl.finditer(t):
                have |= members(body(t, m.end()))
        use = re.compile(r'(?<![\w.])' + name + r'\.([a-z_]\w*)')
        for p, t in texts.items():
            for member in set(use.findall(t)) - have - {"self", "init", "allCases"}:
                gaps.setdefault(f"{name}.{member}", []).append(os.path.relpath(p, pkg))
    return gaps


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
    short = short_members(texts, pkg)
    for n in sorted(short):
        print(f"  {n} (not in the stand-in) used by {', '.join(sorted(short[n])[:3])}")
    return 1 if users or short else 0


sys.exit(main())
