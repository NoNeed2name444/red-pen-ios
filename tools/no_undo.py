#!/usr/bin/env python3
# The gate before a change lands on the one version (docs/one-version.md):
# does the change undo work that landed after it started?
#
#   python3 tools/no_undo.py --base B --onto T --change C [--allow SHA ...] [--scope GLOB ...]
#
# B is the commit the change started from, T the one version's tip now and C
# the change's tip, which must already contain T. The work that landed after
# the change started is every commit in B..T, and the diff from T to C must not
# undo any of it:
#   U1  C removes or alters a line of T that a commit in B..T wrote (git blame
#       on T); a line C keeps elsewhere in the file, or re-indented, is not lost
#   U2  C brings back a line that a commit in B..T removed from the same file,
#       renames followed; blank lines, lines of only brackets, punctuation or
#       whitespace, and lines under 4 characters are ignored, and so is a line
#       a commit or C only moved within the file
#   U3  C deletes or renames away a file that a commit in B..T added or
#       changed, or a binary differs between T and C although a commit in
#       B..T changed it
#   U4  only with --scope: a path that differs between T and C matches none
#       of the globs (fnmatch, so * also crosses /; a directory takes in
#       everything under it; one argument may list several, comma-separated)
# --allow SHA exempts that commit's work: a rewrite the owner approved.
#
# Exit 0 prints "no-undo: OK (<n> files checked)". Exit 1 prints one line per
# finding, file:line (line 0: the whole file), the commit whose work is undone
# and its subject; or "take in the latest tip first" when C does not contain T.
# Exit 2: bad input (an unknown commit, or B not an ancestor of T).
# Standard library and git only.
import argparse
import fnmatch
import os
import re
import subprocess
import sys
import unicodedata
from collections import Counter, defaultdict

# The user's git config must not change what is read: no colour, prefixes,
# relative paths, external diff or text conversion, quoting or signatures.
GIT = ["git", "--no-pager", "--no-optional-locks",
       "-c", "core.quotePath=false", "-c", "color.ui=never", "-c", "log.showSignature=false",
       "-c", "diff.noprefix=false", "-c", "diff.mnemonicPrefix=false", "-c", "log.follow=false"]
DIFF = ["-U0", "-M", "--no-color", "--no-ext-diff", "--no-textconv", "--no-relative",
        "--src-prefix=a/", "--dst-prefix=b/"]
ENV = dict(os.environ, GIT_LITERAL_PATHSPECS="1", GIT_PAGER="cat")
for _k in ("GIT_DIFF_OPTS", "GIT_EXTERNAL_DIFF"):
    ENV.pop(_k, None)
ROOT = None

HUNK = re.compile(r"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@")
BLAME = re.compile(r"^([0-9a-f]{40,64}) \d+ (\d+)(?: \d+)?$")
ESCAPES = {"a": 7, "b": 8, "t": 9, "n": 10, "v": 11, "f": 12, "r": 13, '"': 34, "\\": 92}


class Stop(Exception):
    """Bad input, or git could not answer: exit 2."""


def git(*args, check=True):
    p = subprocess.run(GIT + list(args), cwd=ROOT, env=ENV, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and p.returncode != 0:
        err = p.stderr.decode("utf-8", "replace").strip().splitlines()
        raise Stop("git %s failed: %s" % (args[0], err[-1] if err else "exit %d" % p.returncode))
    return p.returncode, p.stdout.decode("utf-8", "surrogateescape")


def commit_of(name, flag):
    if not name or name.startswith("-"):
        raise Stop("%s needs a commit, got %r" % (flag, name))
    rc, out = git("rev-parse", "--verify", "--quiet", name + "^{commit}", check=False)
    if rc != 0:
        raise Stop("unknown commit for %s: %s" % (flag, name))
    return out.strip()


def is_ancestor(a, b):
    rc, _ = git("merge-base", "--is-ancestor", a, b, check=False)
    if rc not in (0, 1):
        raise Stop("git merge-base could not compare %s and %s" % (a[:12], b[:12]))
    return rc == 0


def trivial(s):
    """A stripped line too plain to say it came back: short, or only brackets and punctuation."""
    return len(s) < 4 or all(ch.isspace() or unicodedata.category(ch)[0] in "PS" for ch in s)


# MARK: reading git's patches

def unquote(s, i=0):
    """A C-quoted path starting at s[i] == '"': (path, index after the closing quote)."""
    out, i = bytearray(), i + 1
    while i < len(s):
        ch = s[i]
        if ch == '"':
            return out.decode("utf-8", "surrogateescape"), i + 1
        if ch == "\\" and i + 1 < len(s):
            nx = s[i + 1]
            if nx in ESCAPES:
                out.append(ESCAPES[nx])
                i += 2
                continue
            if nx in "01234567":
                out.append(int(s[i + 1:i + 4], 8) & 0xFF)
                i += 4
                continue
        out += ch.encode("utf-8", "surrogateescape")
        i += 1
    raise Stop("cannot read the quoted path %r" % s)


def header_path(v, prefix):
    """The path of a ---/+++ line, or None for /dev/null."""
    if v == "/dev/null":
        return None
    if v.startswith('"'):
        v = unquote(v)[0]
    elif v.endswith("\t"):  # git adds a tab after a name with a space in it
        v = v[:-1]
    return v[len(prefix):] if v.startswith(prefix) else v


def git_line_paths(rest):
    """The two names of 'diff --git a/X b/Y' (exact for X == Y; renames are read from their own lines)."""
    if rest.startswith('"'):
        a, i = unquote(rest)
        b = rest[i + 1:]
        b = unquote(b)[0] if b.startswith('"') else b
    elif rest.endswith('"') and ' "' in rest:
        j = rest.index(' "')
        a, b = rest[:j], unquote(rest, j + 1)[0]
    else:
        half = (len(rest) - 5) // 2
        if half > 0 and rest[2:2 + half] == rest[5 + half:] and rest[2 + half:5 + half] == " b/":
            a, b = rest[:2 + half], rest[3 + half:]
        else:
            j = rest.find(" b/")
            a, b = (rest[:j], rest[j + 1:]) if j > 0 else (rest, rest)
    return a[2:] if a.startswith("a/") else a, b[2:] if b.startswith("b/") else b


class Section:
    """One file of a patch: its old and new path (None when absent), what it removed and added."""
    __slots__ = ("old", "new", "binary", "gitlink", "parents", "removed", "added")

    def __init__(self, old, new, parents):
        self.old, self.new, self.parents = old, new, parents
        self.binary = self.gitlink = False
        self.removed, self.added = [], []  # (line number, text); line numbers only for a plain diff


def read_patch(text):
    """Commits of 'git log -p --cc --format=%x01%H %P' (or one unnamed commit for 'git diff')."""
    commits, sha, secs = [], None, None
    sec = state = None
    minus = plus = old_no = new_no = None
    flags = {}

    def close():
        if sec is None:
            return
        if flags.get("rename"):
            sec.old, sec.new = flags["rename_from"], flags["rename_to"]
        else:
            if "minus" in flags:
                sec.old = minus
            if "plus" in flags:
                sec.new = plus
            if flags.get("created"):
                sec.old = None
            if flags.get("deleted"):
                sec.new = None

    for line in text.split("\n"):
        if line.startswith("\x01"):
            close()
            sec = state = None
            parts = line[1:].split()
            sha, secs = parts[0], []
            commits.append((sha, parts[1:], secs))
            continue
        combined = line.startswith("diff --cc ") or line.startswith("diff --combined ")
        if line.startswith("diff --git ") or combined:
            close()
            if secs is None:
                secs = []
                commits.append((None, [], secs))
            if combined:
                rest = line.split(" ", 2)[2]
                path = unquote(rest)[0] if rest.startswith('"') else rest
                sec = Section(path, path, 2)
            else:
                a, b = git_line_paths(line[len("diff --git "):])
                sec = Section(a, b, 1)
            secs.append(sec)
            state, flags = "head", {}
            continue
        if sec is None:
            continue
        if line.startswith("@@"):
            state = "hunk"
            if sec.parents == 1:
                m = HUNK.match(line)
                if not m:
                    raise Stop("cannot read the hunk header %r" % line)
                old_no, new_no = int(m.group(1)), int(m.group(2))
            else:
                sec.parents = len(line) - len(line.lstrip("@")) - 1
            continue
        if state == "head":
            if line.startswith("rename from "):
                v = line[len("rename from "):]
                flags["rename"], flags["rename_from"] = True, unquote(v)[0] if v.startswith('"') else v
            elif line.startswith("rename to "):
                v = line[len("rename to "):]
                flags["rename_to"] = unquote(v)[0] if v.startswith('"') else v
            elif line.startswith("--- "):
                flags["minus"], minus = True, header_path(line[4:], "a/")
            elif line.startswith("+++ "):
                flags["plus"], plus = True, header_path(line[4:], "b/")
            elif line.startswith("new file mode"):
                flags["created"] = True
            elif line.startswith("deleted file mode"):
                flags["deleted"] = True
            elif line.startswith("Binary files "):
                sec.binary = True
            if line.startswith(("index ", "new file mode", "deleted file mode", "old mode", "new mode")) \
                    and "160000" in line.split()[-1].split(","):
                sec.gitlink = True  # a submodule: no lines to read
            continue
        if state == "hunk":
            if line.startswith("\\"):
                continue
            n = sec.parents
            mark, body = line[:n], line[n:]
            if len(mark) < n or not set(mark) <= {" ", "-", "+"}:
                state = None
            elif n == 1:
                if mark == "-":
                    sec.removed.append((old_no, body))
                    old_no += 1
                elif mark == "+":
                    sec.added.append((new_no, body))
                    new_no += 1
                else:
                    old_no += 1
                    new_no += 1
            elif set(mark) == {"-"}:  # in every parent and not in the merge: the merge's own removal
                sec.removed.append((None, body))
            elif set(mark) == {"+"}:
                sec.added.append((None, body))
    close()
    return commits


# MARK: the checks

class Groups:
    """Paths joined by renames: one file under all its names."""

    def __init__(self):
        self.up = {}
        self.paths = set()

    def find(self, p):
        root = p
        while self.up.get(root, root) != root:
            root = self.up[root]
        while self.up.get(p, p) != root:
            self.up[p], p = root, self.up[p]
        return root

    def join(self, a, b):
        self.paths.update((a, b))
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.up[ra] = rb


def in_scope(path, globs):
    return any(fnmatch.fnmatchcase(path, g) or fnmatch.fnmatchcase(path, g.rstrip("/") + "/*") for g in globs)


def blame(path, lines, onto, base):
    """Which commit wrote each of these lines of the tip; history before the base is not walked."""
    args = ["blame", "--porcelain", "--ignore-revs-file", ""]
    lines = sorted(set(lines))
    start = prev = lines[0]
    for n in lines[1:] + [None]:
        if n is not None and n == prev + 1:
            prev = n
            continue
        args += ["-L", "%d,%d" % (start, prev)]
        start = prev = n
    _, out = git(*args, onto, "^" + base, "--", path)
    who = {}
    for row in out.split("\n"):
        m = BLAME.match(row)
        if m:
            who[int(m.group(2))] = m.group(1)
    return who


def changed_by(path, onto, change):
    """The newest commit of the change that touched the path."""
    for extra in (["--no-merges"], []):
        _, out = git("log", "-1", "--format=%H", *extra, change, "^" + onto, "--", path)
        if out.strip():
            return out.strip()
    return change


def check(base, onto, change, allowed, scopes):
    """(findings, files checked); a finding is (rule, path, line, sha, what)."""
    _, out = git("diff", *DIFF, "--minimal", onto, change)
    tc = [s for _, _, secs in read_patch(out) for s in secs]
    n_files = len({s.old if s.old is not None else s.new for s in tc})
    findings = []
    if not tc:
        return findings, 0
    _, out = git("rev-list", onto, "^" + base)
    landed = set(out.split())
    groups = Groups()
    for s in tc:
        if s.old is not None and s.new is not None and s.old != s.new:
            groups.join(s.old, s.new)
    history = []
    if landed:
        # The renames in B..T first, so that the history read next follows each
        # file the change differs in under all its names, and only those files
        # (in a partial clone every other blob would be fetched for nothing).
        _, out = git("log", "--no-merges", "-M", "--diff-filter=R", "--name-status", "-z", "--format=%x01%H",
                     onto, "^" + base)
        tokens, i = [t.lstrip("\n") for t in out.split("\0")], 0
        while i < len(tokens):
            if re.fullmatch(r"R\d*", tokens[i]) and i + 2 < len(tokens):
                groups.join(tokens[i + 1], tokens[i + 2])
                i += 3
            else:
                i += 1
        roots = {groups.find(p) for s in tc for p in (s.old, s.new) if p is not None}
        names = sorted({p for s in tc for p in (s.old, s.new) if p is not None}
                       | {p for p in groups.paths if groups.find(p) in roots})
        limit = ["--"] + names if len(names) <= 2000 else []
        _, out = git("log", "-p", "--cc", *DIFF, "--full-history", "--topo-order", "--format=%x01%H %P",
                     onto, "^" + base, *limit)
        history = read_patch(out)
    for s in [s for _, _, secs in history for s in secs]:
        if s.old is not None and s.new is not None and s.old != s.new:
            groups.join(s.old, s.new)

    touched = defaultdict(list)   # file -> commits in B..T that added, changed, renamed or removed it
    removed = defaultdict(list)   # (file, stripped line) -> commits in B..T that removed it, newest first
    for sha, _, secs in history:
        for s in secs:
            for p in {s.old, s.new} - {None}:
                if sha not in touched[groups.find(p)]:
                    touched[groups.find(p)].append(sha)
            if s.binary or s.gitlink or not s.removed:
                continue
            root = groups.find(s.old if s.old is not None else s.new)
            gone = Counter(k for k in (t.strip() for _, t in s.removed) if not trivial(k))
            came = Counter(t.strip() for _, t in s.added)  # moved or re-indented in the same commit: not removed
            for k, count in gone.items():
                if count > came[k] and sha not in removed[(root, k)]:
                    removed[(root, k)].append(sha)
    removed_in = {root for root, _ in removed}

    def add(rule, path, line, sha, what):
        findings.append((rule, path, line, sha, what))

    for s in tc:
        if s.binary or s.gitlink:
            continue
        # U1: the lines of T that C removes or alters, and who wrote them; a line
        # that C still has elsewhere in the file, or re-indented, is not undone
        if s.old is not None and s.removed and touched.get(groups.find(s.old)):
            kept = Counter(t.strip() for _, t in s.added)
            lost = []
            for n, t in s.removed:
                if kept[t.strip()] > 0:
                    kept[t.strip()] -= 1
                else:
                    lost.append(n)
            who = blame(s.old, lost, onto, base) if lost else {}
            for n in lost:
                sha = who.get(n)
                if sha in landed and sha not in allowed:
                    add("U1", s.old, n, sha, "removes or alters a line written by")
        # U2: the lines C adds that a commit in B..T removed from this file
        if s.new is not None and s.added and groups.find(s.new) in removed_in:
            root = groups.find(s.new)
            moved = Counter(t.strip() for _, t in s.removed)
            for n, t in s.added:
                k = t.strip()
                if trivial(k):
                    continue
                if moved[k] > 0:
                    moved[k] -= 1
                    continue
                shas = [x for x in removed.get((root, k), ()) if x not in allowed]
                if shas:
                    add("U2", s.new, n, shas[0], "brings back a line removed by")

    # U3: files deleted or renamed away, binaries replaced
    created = {s.new for s in tc if s.old is None}
    for s in tc:
        if s.old is not None and s.new is None:
            if s.old in created:  # a type change: the lines are U1's
                continue
            path, what = s.old, "deletes a file changed by"
        elif s.old is not None and s.new is not None and s.old != s.new:
            path, what = s.old, "renames away (to %s) a file changed by" % s.new
        elif s.binary:
            path, what = s.old if s.old is not None else s.new, "replaces a binary changed by"
        else:
            continue
        for sha in touched.get(groups.find(path), ()):
            if sha not in allowed:
                add("U3", path, 0, sha, what)

    # U4: paths outside the task's scope
    if scopes:
        for s in tc:
            for p in dict.fromkeys(x for x in (s.old, s.new) if x is not None):
                if not in_scope(p, scopes):
                    add("U4", p, 0, changed_by(p, onto, change), "is outside --scope; changed by")
    return findings, n_files


def report(findings):
    """Finding lines, runs of neighbouring lines from the same commit joined into one."""
    rows = []
    for rule, path, line, sha, what in sorted(set(findings), key=lambda f: (f[0], f[1], f[2], f[3])):
        last = rows[-1] if rows else None
        if last and line > 0 and last[:2] == [rule, path] and last[4:6] == [sha, what] and line == last[3] + 1:
            last[3] = line
        else:
            rows.append([rule, path, line, line, sha, what])
    shas = sorted({r[4] for r in rows})
    _, out = git("log", "--no-walk=unsorted", "--format=%H%x00%s", *shas)
    subject = dict(row.split("\0", 1) for row in out.split("\n") if "\0" in row)
    for rule, path, start, end, sha, what in rows:
        where = "%d-%d" % (start, end) if end > start else "%d" % start
        print("%s:%s: %s %s %s %s" % (path, where, rule, what, sha[:12], subject.get(sha, "")))
    return rows


def main(argv=None):
    global ROOT
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="surrogateescape")
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(description="Fail when a change undoes work that landed on the one version after it started.")
    ap.add_argument("--base", required=True, help="the commit the change started from (B)")
    ap.add_argument("--onto", required=True, help="the one version's tip now (T)")
    ap.add_argument("--change", required=True, help="the change's tip (C), which must contain T")
    ap.add_argument("--allow", nargs="+", action="extend", default=[], metavar="SHA",
                    help="exempt this commit's work: a rewrite the owner approved")
    ap.add_argument("--scope", nargs="+", action="extend", default=[], metavar="GLOB",
                    help="every path that differs between T and C must match one of these")
    a = ap.parse_args(argv)
    try:
        rc, out = git("rev-parse", "--show-toplevel", check=False)
        if rc != 0:
            raise Stop("not inside a git work tree")
        ROOT = out.rstrip("\n")
        base = commit_of(a.base, "--base")
        onto = commit_of(a.onto, "--onto")
        change = commit_of(a.change, "--change")
        allowed = {commit_of(x, "--allow") for x in a.allow}
        scopes = [g.strip() for item in a.scope for g in item.split(",") if g.strip()]
        if not is_ancestor(base, onto):
            raise Stop("--base %s is not an ancestor of --onto %s" % (base[:12], onto[:12]))
        if not is_ancestor(onto, change):
            print("no-undo: the change %s does not contain the tip %s: take in the latest tip first "
                  "(git merge %s), then run this again" % (change[:12], onto[:12], a.onto))
            return 1
        findings, n_files = check(base, onto, change, allowed, scopes)
        if not findings:
            print("no-undo: OK (%d files checked)" % n_files)
            return 0
        rows = report(findings)
        rules = sorted({r[0] for r in rows})
        print("no-undo: FAILED, %d finding%s in %d of %d files checked (%s)" % (
            len(rows), "" if len(rows) == 1 else "s", len({r[1] for r in rows}), n_files, " ".join(rules)))
        if set(rules) - {"U4"}:
            print("no-undo: keep the work that landed after %s, or name a rewrite the owner approved with --allow SHA"
                  % base[:12])
        if "U4" in rules:
            print("no-undo: keep the change inside its --scope")
        return 1
    except Stop as e:
        print("no-undo: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
