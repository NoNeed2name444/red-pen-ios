#!/usr/bin/env python3
"""Whether each Swift suite lists the files that define the Ward names its files use.

A suite's files are listed by hand (tools/swift_suites.txt), and macOS CI builds
the mac-only suites (tools/swift_suites_mac_only.txt) with SwiftUI present, so
code that Linux fences out comes in there: Brand.swift's `.wardInk` stopped the
macOS job (run 39735376216) while Linux and preflight stayed green. This reads
each suite's files as the machine that builds them does (a mac-only suite as
macOS: SwiftUI and AppKit, no UIKit; the rest as Linux), keeps the code their
#if's let in, and fails, naming the suite, the file and the name, when a file
uses a Ward name (a Ward* type, Color.ward*, a .ward* member or modifier) that
none of the suite's files define, or a mac-only suite's file imports a module
macOS lacks (UIKit is iOS's alone).

    tools/swift_suite_closure.py                   every suite
    tools/swift_suite_closure.py --affected <ref>  the suites tools/swift_suites.py --affected picks
    tools/swift_suite_closure.py --only a,b        some

Static: no compiler, no network, the standard library only. Exit 0 prints
"closure: OK (...)"; exit 1 prints one line per finding; exit 2, a bad ref.
"""
import argparse, os, re, subprocess, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
VARS = {"S": "ios/RedPen/Shared", "M": "ios/RedPen/Models", "F": "ios/RedPen/Features"}

# What each build can import. macOS: every Apple module but iOS's own, and none
# of Linux's Foundation stand-ins. Linux (swift:6.4-noble): the toolchain's own.
NOT_ON_MACOS = {"UIKit", "ActivityKit", "ARKit", "CarPlay", "MessageUI", "WatchConnectivity",
                "FoundationNetworking", "FoundationXML", "Glibc", "Musl"}
ON_LINUX = {"Foundation", "FoundationNetworking", "FoundationXML", "FoundationEssentials", "Dispatch",
            "Glibc", "Musl", "Observation", "Synchronization", "RegexBuilder", "XCTest", "Testing"}
OS = {"macos": "macOS", "linux": "Linux"}
ARCH = {"macos": "arm64", "linux": "x86_64"}  # macos-latest, ubuntu-latest


def has(build, module):
    return module not in NOT_ON_MACOS if build == "macos" else module in ON_LINUX


def suites(root=ROOT):
    """{name: files, the test first}, read as tools/swift_suites.py reads them."""
    text = open(os.path.join(root, "tools/swift_suites.txt")).read().replace("\\\n", " ")
    out = {}
    for line in text.split("\n"):
        line = line.strip()
        if not line.startswith("suite ") or line.startswith("suite ()"):
            continue
        name, test, *srcs = line.split()[1:]
        out[name] = ["ios/RedPen/Tests/" + test] + [re.sub(r"\$(\w)", lambda m: VARS[m.group(1)], s) for s in srcs]
    return out


def mac_only(root=ROOT):
    path = os.path.join(root, "tools/swift_suites_mac_only.txt")
    if not os.path.exists(path):
        return set()
    return {l.split("#")[0].strip() for l in open(path) if l.split("#")[0].strip()}


# Comments and string literals: blanked, so a name in a doc comment or a
# message is not a use. Lines and columns are kept.
SPECIAL = re.compile(r'//|/\*|#*"')
QUOTE = re.compile(r'(#*)("""|")')
COMMENT_EDGE = re.compile(r"/\*|\*/")


def string_end(src, i):
    """Just past the string literal at src[i]. An interpolation is skipped
    whole, with any strings inside it."""
    m = QUOTE.match(src, i)
    hashes, quote = m.group(1), m.group(2)
    close, escape, j = quote + hashes, "\\" + hashes, m.end()
    while j < len(src):
        if src.startswith(close, j):
            return j + len(close)
        if src.startswith(escape, j):
            j += len(escape)
            if src.startswith("(", j):
                depth, j = 1, j + 1
                while j < len(src) and depth:
                    if QUOTE.match(src, j):
                        j = string_end(src, j)
                        continue
                    depth += {"(": 1, ")": -1}.get(src[j], 0)
                    j += 1
            else:
                j += 1
            continue
        if quote == '"' and src[j] == "\n":
            return j
        j += 1
    return j


def comment_end(src, i):
    depth = 0
    for m in COMMENT_EDGE.finditer(src, i):
        depth += 1 if m.group(0) == "/*" else -1
        if depth == 0:
            return m.end()
    return len(src)


def strip(src):
    out, i = [], 0
    while True:
        m = SPECIAL.search(src, i)
        if m is None:
            out.append(src[i:])
            return "".join(out)
        out.append(src[i:m.start()])
        if m.group(0) == "//":
            end = src.find("\n", m.start())
            end = len(src) if end < 0 else end
        elif m.group(0) == "/*":
            end = comment_end(src, m.start())
        else:
            end = string_end(src, m.start())
        out.append(re.sub(r"[^\n]", " ", src[m.start():end]))
        i = end


DIRECTIVE = re.compile(r"\s*#(if|elseif|else|endif)\b(.*)")


def holds(cond, build):
    """Whether an #if condition holds in `build`; ValueError when it cannot be read."""
    def call(m):
        fn, arg = m.group(1), m.group(2).split(",")[0].strip()
        if fn == "canImport":
            return str(has(build, arg.split(".")[0]))
        if fn == "os":
            return str(arg == OS[build])
        if fn == "arch":
            return str(arg == ARCH[build])
        if fn == "targetEnvironment":
            return "False"
        raise ValueError(cond)
    expr = re.sub(r"\b(\w+)\s*\(([^()]*)\)", call, cond)
    # a bare name is a -D flag, and tools/swift_suites.py passes none
    expr = re.sub(r"\b(?!True\b|False\b)[A-Za-z_]\w*", lambda m: str(m.group(0) == "true"), expr)
    expr = expr.replace("&&", " and ").replace("||", " or ").replace("!", " not ")
    if not expr.strip() or not re.fullmatch(r"(?:\s|\(|\)|True|False|and|or|not)*", expr):
        raise ValueError(cond)
    return bool(eval(expr, {"__builtins__": {}}))


_ACTIVE = {}


def active(path, build):
    """The file's lines as `build` compiles them: comments, strings and the code
    its #if's leave out are blank. OSError, or ValueError naming the line."""
    if (path, build) not in _ACTIVE:
        lines, stack = [], []  # per open #if: [this branch is compiled, a branch was taken]
        for no, line in enumerate(strip(open(path, encoding="utf-8").read()).split("\n"), 1):
            m = DIRECTIVE.match(line)
            if m is None:
                lines.append(line if all(s[0] for s in stack) else "")
                continue
            kw, cond = m.group(1), m.group(2).strip()
            try:
                if kw == "if":
                    take = all(s[0] for s in stack) and holds(cond, build)
                    stack.append([take, take])
                elif kw == "elseif":
                    take = all(s[0] for s in stack[:-1]) and not stack[-1][1] and holds(cond, build)
                    stack[-1] = [take, stack[-1][1] or take]
                elif kw == "else":
                    stack[-1] = [all(s[0] for s in stack[:-1]) and not stack[-1][1], True]
                else:
                    stack.pop()
            except (ValueError, IndexError):
                raise ValueError(f"line {no}: cannot read #{kw} {cond}")
            lines.append("")
        _ACTIVE[(path, build)] = lines
    return _ACTIVE[(path, build)]


USE = re.compile(r"\b(Ward[A-Z]\w*)|\.\s*(ward(?:[A-Z]\w*)?)\b")
DEFINE = re.compile(r"\b(?:enum|struct|class|protocol|typealias|actor|associatedtype)\s+(Ward[A-Z]\w*)"
                    r"|\b(?:var|let|func)\s+(ward(?:[A-Z]\w*)?)\b")
# an enum's cases, every name of `case a, b(Int), c = 1` (on a line of its
# own or after `{` or `;`); a switch's pattern (`case .ward:`, `case let x:`)
# is not one
CASES = re.compile(r"(?:^|[{;])\s*(?:indirect\s+)?case\s+(?!\.|let\b|var\b)([^;{}]*)")
IMPORT = re.compile(r"\s*(?:@\w+(?:\([^)]*\))?\s+)*import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(\w+)")


def case_names(line):
    names = []
    for m in CASES.finditer(line):
        body, before = m.group(1), None
        while body != before:
            before, body = body, re.sub(r"\([^()]*\)", "", body)
        if ":" not in body:
            names += re.findall(r"(?:^|,)\s*(\w+)", body)
    return names


def check(names, every, macs, root=ROOT):
    """[(suite, file, line, what, build)] for the suites `names`."""
    out = []
    for name in names:
        build = "macos" if name in macs else "linux"
        defined, uses = set(), []
        for f in dict.fromkeys(every[name]):
            try:
                lines = active(os.path.join(root, f), build)
            except (OSError, ValueError) as e:
                out.append((name, f, 0, f"cannot be read: {e}", build))
                continue
            for no, line in enumerate(lines, 1):
                defined.update(t or m for t, m in DEFINE.findall(line))
                defined.update(case_names(line))
                uses += [(f, no, t or "." + m) for t, m in USE.findall(line)]
                imp = IMPORT.match(line)
                if imp and build == "macos" and not has(build, imp.group(1)):
                    out.append((name, f, no, f"imports {imp.group(1)}, which macOS does not have", build))
        seen = set()
        for f, no, n in uses:
            if n.lstrip(".") not in defined and (f, n) not in seen:
                seen.add((f, n))
                out.append((name, f, no, f"uses {n}, which none of the suite's files define", build))
    return out


def main():
    ap = argparse.ArgumentParser(description="Each Swift suite lists the files defining the Ward names it uses.")
    ap.add_argument("--only", default="")
    ap.add_argument("--affected", default="", help="a git ref: the suites tools/swift_suites.py --affected picks")
    a = ap.parse_args()
    every, macs = suites(), mac_only()
    names = list(every)
    if a.only:
        names = [n for n in names if n in set(a.only.split(","))]
    if a.affected:
        if subprocess.run(["git", "rev-parse", "--verify", "-q", a.affected + "^{commit}"], cwd=ROOT,
                          capture_output=True).returncode:
            print(f"closure: unknown ref {a.affected}")
            return 2
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tools/swift_suites.py"), "--affected", a.affected,
                            "--list-chosen"], cwd=ROOT, capture_output=True, text=True)
        if r.returncode:
            print(r.stdout + r.stderr)
            return 2
        names = [n for n in names if n in set(r.stdout.split())]
    found = check(names, every, macs)
    for suite, f, no, what, build in found:
        print(f"FAIL {suite}: {f}:{no} {what} ({OS[build]} build)")
    if found:
        print(f"closure: {len(found)} finding(s) in {len({x[0] for x in found})} suite(s)")
        return 1
    n_mac = sum(n in macs for n in names)
    print(f"closure: OK ({len(names)} suites: {n_mac} read as macOS builds them, {len(names) - n_mac} as Linux)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
