#!/usr/bin/env python3
"""scratch_ci.py: the helper for .github/workflows/scratch-build.yml.

That workflow runs one "job directory" of scripts (a run.sh and what it needs)
on a GitHub Linux runner, against a commit plus an optional uncommitted patch,
and returns the small results on the branch shots/scratch-<name>.

  pack      build the request (base64 of a gzip tar: patch.diff + job/) to dispatch
  unpack    the safe unpack of a request (used by the run job)
  check-patch   refuse a patch that touches anything outside the allow-list
  check-result  the filter the publish job puts between an artifact and a push
  fetch     bring a finished build's files back from its branch
  selftest  every rule above, with good and bad inputs

Standard library only. Nothing here runs a shell on a string from outside.
The request and the results are public (the repository is).
"""
import argparse, base64, binascii, gzip, io, json, os, re, shutil, subprocess, sys, tarfile, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

# What a patch may touch, and what a request, a patch file and a result may hold.
PATCH_DIRS = ("tools/scratch_body/",)
PATCH_FILES = ("tools/anatomy_teeth.py",)
SAFE_PATH = re.compile(r"^[A-Za-z0-9._+/-]+$")          # a path in a request or a patch
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,39}$")      # a build's name
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
RESULT_NAME = re.compile(r"^[A-Za-z0-9._-]+$")
RESULT_EXT = {".jpg", ".jpeg", ".png", ".json", ".txt", ".tsv", ".csv", ".log", ".md"}
SKIP_DIRS = {"__pycache__", ".git"}
SKIP_EXT = {".pyc", ".pkl", ".npz", ".npy", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp",
            ".tif", ".tiff", ".ico", ".pdf", ".zip", ".gz", ".bin", ".so", ".o"}

MAX_PACK_FILE = 400 * 1024        # one packed file
MAX_B64 = 60000                   # the dispatch input limit is 65535
MAX_B64_IN = 70000                # what unpack will read at all
MAX_REQ_FILES = 400
MAX_REQ_BYTES = 5 * 1024 * 1024
MAX_RES_FILE = 2 * 1024 * 1024
MAX_RES_FILES = 300
MAX_RES_BYTES = 40 * 1024 * 1024


class CiError(Exception):
    pass


def git(args, cwd=None, input=None, check=True, env=None):
    """Run git with a list of arguments (never a shell); return bytes of stdout."""
    e = dict(os.environ, **(env or {}))
    r = subprocess.run(["git"] + args, cwd=cwd, input=input, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, env=e)
    if check and r.returncode != 0:
        raise CiError("git %s failed: %s" % (" ".join(args[:3]), r.stderr.decode(errors="replace").strip()))
    return r.stdout if check else r


def repo_root():
    return git(["rev-parse", "--show-toplevel"], cwd=HERE).decode().strip()


def allowed_patch_path(p):
    if not SAFE_PATH.match(p) or p.startswith("/") or any(c in ("", ".", "..") for c in p.split("/")):
        return False
    return p in PATCH_FILES or any(p.startswith(d) and len(p) > len(d) for d in PATCH_DIRS)


# ----------------------------------------------------------------- pack

def is_text(path):
    with open(path, "rb") as f:
        data = f.read(MAX_PACK_FILE + 1)
    if b"\0" in data:
        return False
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return True


def collect(root, rel_prefix, skipped):
    """Packable files under root (symlinks followed), as {rel path with rel_prefix: abs path}."""
    out, seen = {}, set()
    for dirpath, dirs, files in os.walk(root, followlinks=True):
        real = os.path.realpath(dirpath)
        if real in seen:
            dirs[:] = []
            continue
        seen.add(real)
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for fn in sorted(files):
            full = os.path.join(dirpath, fn)
            rel = rel_prefix + os.path.relpath(full, root).replace(os.sep, "/")
            if fn.endswith(".pyc") or os.path.splitext(fn)[1].lower() in SKIP_EXT:
                skipped.append((rel, "binary or cache type"))
            elif not SAFE_PATH.match(rel):
                skipped.append((rel, "name has odd characters"))
            elif not os.path.isfile(full):
                skipped.append((rel, "not a file"))
            elif os.path.getsize(full) > MAX_PACK_FILE:
                skipped.append((rel, "over 400 KB"))
            elif not is_text(full):
                skipped.append((rel, "not text"))
            else:
                out[rel] = full
    return out


def base_files(sha, wanted):
    """{path: (bytes, mode)} of the wanted paths as they are in commit sha (missing ones absent)."""
    roots = [d.rstrip("/") for d in PATCH_DIRS] + list(PATCH_FILES)
    raw = git(["archive", "--format=tar", sha, "--"] + roots, cwd=repo_root(), check=False)
    if raw.returncode != 0:
        raise CiError("git archive %s failed: %s" % (sha[:7], raw.stderr.decode(errors="replace").strip()))
    out = {}
    with tarfile.open(fileobj=io.BytesIO(raw.stdout), mode="r:") as t:
        for m in t:
            if m.isreg() and m.name in wanted:
                out[m.name] = (t.extractfile(m).read(), 0o755 if m.mode & 0o111 else 0o644)
    return out


def make_patch(sha, src, skipped):
    """The difference of tools/scratch_body/** and tools/anatomy_teeth.py in src from commit sha."""
    cand = collect(os.path.join(src, "tools", "scratch_body"), "tools/scratch_body/", skipped)
    teeth = os.path.join(src, "tools", "anatomy_teeth.py")
    if os.path.isfile(teeth):
        tmp = []
        cand.update(collect_one(teeth, "tools/anatomy_teeth.py", tmp))
        skipped.extend(tmp)
    cand = {p: f for p, f in cand.items() if allowed_patch_path(p)}
    base = base_files(sha, set(cand))
    with tempfile.TemporaryDirectory() as td:
        env = {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull}
        cfg = ["-c", "core.autocrlf=false", "-c", "core.safecrlf=false", "-c", "core.quotepath=off"]
        git(["init", "-q"], cwd=td, env=env)
        for p, (data, mode) in base.items():
            write_file(os.path.join(td, p), data, mode)
        git(cfg + ["add", "-A", "-f"], cwd=td, env=env)
        added = []
        for p, f in cand.items():
            with open(f, "rb") as fh:
                data = fh.read()
            if p in base and base[p][0] == data:
                continue
            write_file(os.path.join(td, p), data, base[p][1] if p in base else 0o644)
            if p not in base:
                added.append(p)
        if added:
            git(cfg + ["add", "-N", "-f", "--"] + added, cwd=td, env=env)
        patch = git(cfg + ["diff", "--no-color", "--no-ext-diff", "--no-textconv", "--no-renames",
                           "--src-prefix=a/", "--dst-prefix=b/"], cwd=td, env=env)
    return patch


def collect_one(path, rel, skipped):
    d, fn = os.path.split(path)
    got = {}
    tmp = []
    all_ = collect(d, rel[: -len(fn)], tmp)
    if rel in all_:
        got[rel] = all_[rel]
    else:
        skipped.extend(x for x in tmp if x[0] == rel)
    return got


def write_file(path, data, mode):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    os.chmod(path, mode)


def tar_request(patch, jobfiles):
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0, compresslevel=9) as gz:
        with tarfile.open(fileobj=gz, mode="w", format=tarfile.GNU_FORMAT) as t:
            def add(name, data):
                ti = tarfile.TarInfo(name)
                ti.size, ti.mode, ti.mtime = len(data), 0o644, 0
                t.addfile(ti, io.BytesIO(data))
            if patch:
                add("patch.diff", patch)
            for name in sorted(jobfiles):
                with open(jobfiles[name], "rb") as f:
                    add(name, f.read())
    return buf.getvalue()


def verify_patch_applies(sha, patch):
    """git apply --check of the patch against a fresh archive of the commit."""
    with tempfile.TemporaryDirectory() as td:
        raw = git(["archive", "--format=tar", sha, "--"] + [d.rstrip("/") for d in PATCH_DIRS] + list(PATCH_FILES),
                  cwd=repo_root())
        with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as t:
            t.extractall(td, filter="data")
        pf = os.path.join(td, "..", "_scratch_check.diff")
        pf = os.path.abspath(pf)
        with open(pf, "wb") as f:
            f.write(patch)
        try:
            r = git(["apply", "--check", "--whitespace=nowarn", pf], cwd=td, check=False)
            if r.returncode != 0:
                raise CiError("the patch does not apply cleanly to %s: %s"
                              % (sha[:7], r.stderr.decode(errors="replace").strip()))
        finally:
            os.unlink(pf)


def pack(sha, src, job, out):
    if not SHA_RE.match(sha):
        raise CiError("--sha must be 40 hex characters (use: git rev-parse <ref>)")
    git(["cat-file", "-e", sha + "^{commit}"], cwd=repo_root())
    if not os.path.isdir(os.path.join(src, "tools", "scratch_body")):
        raise CiError("--src has no tools/scratch_body")
    if not os.path.isfile(os.path.join(job, "run.sh")):
        raise CiError("--job has no run.sh")
    skipped = []
    patch = make_patch(sha, src, skipped)
    if patch:
        check_patch_bytes(patch)
        verify_patch_applies(sha, patch)
    jskipped = []
    jobfiles = collect(job, "job/", jskipped)
    if "job/run.sh" not in jobfiles:
        raise CiError("job/run.sh is not packable (text, under 400 KB)")
    if len(jobfiles) > MAX_REQ_FILES or sum(os.path.getsize(f) for f in jobfiles.values()) > MAX_REQ_BYTES:
        raise CiError("the job directory is over 400 files or 5 MB")
    blob = tar_request(patch, jobfiles)
    text = base64.b64encode(blob).decode()
    err = sys.stderr.write
    err("patch: %d bytes%s\n" % (len(patch), "" if patch else " (no difference: no patch.diff)"))
    err("job files: %d; tar.gz: %d bytes; base64: %d characters (limit %d)\n" % (len(jobfiles), len(blob), len(text), MAX_B64))
    for rel, why in skipped + jskipped:
        err("skipped %s (%s)\n" % (rel, why))
    if len(text) > MAX_B64:
        raise CiError("the request is %d characters of base64, over %d: trim the job or the patch" % (len(text), MAX_B64))
    if out:
        with open(out, "w") as f:
            f.write(text)
    else:
        sys.stdout.write(text)


# ----------------------------------------------------------------- unpack

def unpack_text(text, dest):
    text = "".join(text.split())
    if not text or len(text) > MAX_B64_IN:
        raise CiError("request is empty or over %d characters" % MAX_B64_IN)
    try:
        blob = base64.b64decode(text, validate=True)
    except (binascii.Error, ValueError):
        raise CiError("request is not base64")
    try:
        t = tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz")
    except (tarfile.TarError, OSError, EOFError) as e:
        raise CiError("request is not a gzip tar: %s" % e)
    with t:
        members, names, total = [], set(), 0
        try:
            for m in t:
                n = m.name
                if not SAFE_PATH.match(n) or n.startswith("/") or any(c in ("", ".", "..") for c in n.split("/")):
                    raise CiError("bad path in request: %r" % n)
                if not (n == "patch.diff" or n.startswith("job/")):
                    raise CiError("path outside patch.diff and job/: %r" % n)
                if m.isdir():
                    continue
                if not m.isreg():
                    raise CiError("not a regular file (link or device): %r" % n)
                if n in names:
                    raise CiError("duplicate path: %r" % n)
                names.add(n)
                total += m.size
                if len(names) > MAX_REQ_FILES or total > MAX_REQ_BYTES:
                    raise CiError("request holds over 400 files or 5 MB")
                members.append(m)
        except (tarfile.TarError, OSError, EOFError) as e:
            raise CiError("request tar is damaged: %s" % e)
        if "job/run.sh" not in names:
            raise CiError("request has no job/run.sh")
        os.makedirs(dest, exist_ok=True)
        for m in members:
            t.extract(m, dest, filter="data")
    return sorted(names)


def unpack(src, dest):
    text = sys.stdin.read() if src == "-" else open(src).read()
    names = unpack_text(text, dest)
    print("unpacked %d files into %s%s" % (len(names), dest, " (with patch.diff)" if "patch.diff" in names else ""))


# ----------------------------------------------------------------- check-patch

HUNK = re.compile(r"^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@")


def check_patch_bytes(data):
    """Raise CiError unless every path the patch names is allowed and no link or binary is in it."""
    text = data.decode("utf-8", errors="strict")
    old = new = 0                           # lines still owed by the current hunk
    saw = False

    def need(p, what):
        if p == "/dev/null":
            return
        if not allowed_patch_path(p):
            raise CiError("patch touches a path outside the allow-list (%s): %r" % (what, p))

    for line in text.split("\n"):
        if old > 0 or new > 0:
            c = line[:1]
            if c == " ":
                old -= 1; new -= 1
            elif c == "-":
                old -= 1
            elif c == "+":
                new -= 1
            elif c == "\\" or line == "":
                pass
            continue
        m = HUNK.match(line)
        if m:
            old = int(m.group(1) if m.group(1) is not None else 1)
            new = int(m.group(2) if m.group(2) is not None else 1)
            continue
        if line.startswith("diff --git "):
            saw = True
            mm = re.match(r"^diff --git a/(\S+) b/(\S+)$", line)
            if not mm:
                raise CiError("unreadable diff header: %r" % line[:80])
            need(mm.group(1), "diff"); need(mm.group(2), "diff")
        elif line.startswith("--- "):
            p = line[4:].split("\t")[0]
            if p != "/dev/null":
                if not p.startswith("a/"):
                    raise CiError("unexpected --- line: %r" % line[:80])
                need(p[2:], "---")
        elif line.startswith("+++ "):
            p = line[4:].split("\t")[0]
            if p != "/dev/null":
                if not p.startswith("b/"):
                    raise CiError("unexpected +++ line: %r" % line[:80])
                need(p[2:], "+++")
        elif re.match(r"^(rename|copy) (from|to) ", line):
            need(line.split(" ", 2)[2], "rename/copy")
        elif re.match(r"^(old|new|deleted file|new file) mode ", line) or line.startswith("new file mode") \
                or line.startswith("deleted file mode"):
            if line.rstrip().endswith(("120000", "160000")):
                raise CiError("patch makes or changes a symlink or submodule")
        elif line.startswith("GIT binary patch") or line.startswith("Binary files "):
            raise CiError("patch holds a binary file")
    if not saw and text.strip():
        raise CiError("patch has no diff header")
    return True


def check_patch(path):
    with open(path, "rb") as f:
        check_patch_bytes(f.read())
    print("patch ok: every path is under tools/scratch_body/ or is tools/anatomy_teeth.py")


# ----------------------------------------------------------------- check-result

def check_result(src, dest):
    """Copy the allowed files of src into dest; list the rest in dest/DROPPED.txt. Print exit_code=N."""
    dropped, kept = [], []
    cand = []

    def entries(d):
        with os.scandir(d) as it:
            return sorted(it, key=lambda e: e.name)

    def name_ok(n):
        return bool(RESULT_NAME.match(n)) and not n.startswith(".")

    for e in entries(src):
        if e.is_symlink() or e.is_file(follow_symlinks=False):
            cand.append((e.name, e.name, e))
        elif e.is_dir(follow_symlinks=False):
            if not name_ok(e.name):
                dropped.append((e.name + "/", "directory name not allowed"))
                continue
            for f in entries(e.path):
                rel = e.name + "/" + f.name
                if f.is_symlink() or f.is_file(follow_symlinks=False):
                    cand.append((rel, f.name, f))
                else:
                    dropped.append((rel + ("/" if f.is_dir(follow_symlinks=False) else ""),
                                    "deeper than one directory level" if f.is_dir(follow_symlinks=False) else "not a regular file"))
        else:
            dropped.append((e.name, "not a regular file"))
    total = 0
    for rel, name, e in cand:
        if e.is_symlink() or not e.is_file(follow_symlinks=False):
            dropped.append((rel, "link or not a regular file")); continue
        ext = os.path.splitext(name)[1].lower()
        size = e.stat(follow_symlinks=False).st_size
        if rel == "exit_code":
            continue                        # the run job's own note; meta.json carries the code
        if rel == "DROPPED.txt":
            dropped.append((rel, "reserved name"))
        elif not name_ok(name):
            dropped.append((rel, "name not allowed"))
        elif ext not in RESULT_EXT:
            dropped.append((rel, "extension not allowed"))
        elif size > MAX_RES_FILE:
            dropped.append((rel, "over 2 MB"))
        elif len(kept) >= MAX_RES_FILES:
            dropped.append((rel, "over 300 files"))
        elif total + size > MAX_RES_BYTES:
            dropped.append((rel, "over 40 MB in all"))
        else:
            kept.append((rel, e.path)); total += size
    os.makedirs(dest, exist_ok=True)
    for rel, path in kept:
        out = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        shutil.copyfile(path, out, follow_symlinks=False)
    if dropped:
        with open(os.path.join(dest, "DROPPED.txt"), "w") as f:
            f.write("Dropped from the result (not pushed):\n")
            for rel, why in dropped:
                f.write("%s\t%s\n" % (rel, why))
    code = 255
    try:
        with open(os.path.join(src, "meta.json")) as f:
            v = json.load(f).get("exit_code")
        if isinstance(v, int) and not isinstance(v, bool) and 0 <= v <= 255:
            code = v
    except (OSError, ValueError, AttributeError):
        sys.stderr.write("warning: meta.json missing or unreadable; exit code taken as 255\n")
    sys.stderr.write("kept %d files (%d bytes), dropped %d\n" % (len(kept), total, len(dropped)))
    for rel, why in dropped:
        sys.stderr.write("dropped %s (%s)\n" % (rel, why))
    print("exit_code=%d" % code)


# ----------------------------------------------------------------- fetch

def fetch(name, to):
    if not NAME_RE.match(name):
        raise CiError("name must match %s" % NAME_RE.pattern)
    root = repo_root()
    br = "shots/scratch-" + name
    git(["fetch", "-q", "origin", br], cwd=root)
    raw = git(["archive", "--format=tar", "FETCH_HEAD"], cwd=root)
    os.makedirs(to, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as t:
        t.extractall(to, filter="data")
    code = secs = "?"
    try:
        with open(os.path.join(to, "meta.json")) as f:
            m = json.load(f)
        code, secs = m.get("exit_code", "?"), m.get("seconds", "?")
    except (OSError, ValueError):
        pass
    print("fetched %s into %s: exit_code=%s seconds=%s" % (br, to, code, secs))


# ----------------------------------------------------------------- selftest

def selftest():
    results = []

    def case(label, fn):
        try:
            fn()
            results.append((label, True, ""))
        except Exception as e:                      # a failed assertion or an unexpected error
            results.append((label, False, "%s: %s" % (type(e).__name__, e)))

    def expect(ok, why):
        if not ok:
            raise AssertionError(why)

    def rejects(fn, *a):
        try:
            fn(*a)
        except CiError:
            return
        raise AssertionError("was accepted")

    root = repo_root()
    sha = git(["rev-parse", "HEAD"], cwd=root).decode().strip()
    tmp = tempfile.mkdtemp(prefix="scratch_ci_test_")
    st = {}
    try:
        # a tiny fake tree: one real file of HEAD edited, one new file, some that must be skipped
        src, job = os.path.join(tmp, "src"), os.path.join(tmp, "job")
        os.makedirs(os.path.join(src, "tools", "scratch_body", "__pycache__"))
        os.makedirs(job)
        teeth_head = git(["show", "%s:tools/anatomy_teeth.py" % sha], cwd=root)
        write_file(os.path.join(src, "tools", "anatomy_teeth.py"), teeth_head + b"\n# selftest edit\n", 0o644)
        write_file(os.path.join(src, "tools", "scratch_body", "new_trial.py"), b"X = 1\nprint(X)", 0o644)  # no final newline
        write_file(os.path.join(src, "tools", "scratch_body", "__pycache__", "a.pyc"), b"\0\0", 0o644)
        write_file(os.path.join(src, "tools", "scratch_body", "big.json"), b"[" + b"1," * 300000 + b"1]", 0o644)
        write_file(os.path.join(src, "tools", "scratch_body", "pic.png"), b"\x89PNG", 0o644)
        write_file(os.path.join(job, "run.sh"), b"echo hi > \"$OUT/a.txt\"\n", 0o755)
        write_file(os.path.join(job, "data.json"), b"{}", 0o644)
        reqf = os.path.join(tmp, "req.b64")

        def c_pack():
            old = sys.stderr; sys.stderr = io.StringIO()
            try:
                pack(sha, src, job, reqf)
                log = sys.stderr.getvalue()
            finally:
                sys.stderr = old
            assert os.path.getsize(reqf) <= MAX_B64
            assert "big.json (over 400 KB)" in log and "pic.png" in log and "a.pyc" not in log.split("skipped")[0]
            assert "__pycache__" not in log
        case("pack: builds a request, skips pyc, image and 400 KB+ files", c_pack)

        def c_unpack():
            dest = os.path.join(tmp, "req")
            unpack_text(open(reqf).read(), dest)
            assert os.path.isfile(os.path.join(dest, "job", "run.sh"))
            assert os.path.isfile(os.path.join(dest, "job", "data.json"))
            assert os.path.isfile(os.path.join(dest, "patch.diff"))
            st["patch"] = os.path.join(dest, "patch.diff")
        case("unpack: files land where they belong", c_unpack)

        case("check-patch: the packed patch is inside the allow-list", lambda: check_patch(st["patch"]))

        def c_apply():
            work = os.path.join(tmp, "head")
            raw = git(["archive", "--format=tar", sha, "--", "tools/scratch_body", "tools/anatomy_teeth.py"], cwd=root)
            with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as t:
                t.extractall(work, filter="data")
            git(["apply", "--whitespace=nowarn", st["patch"]], cwd=work)
            assert open(os.path.join(work, "tools", "anatomy_teeth.py"), "rb").read() == teeth_head + b"\n# selftest edit\n"
            assert open(os.path.join(work, "tools", "scratch_body", "new_trial.py"), "rb").read() == b"X = 1\nprint(X)"
            assert not os.path.exists(os.path.join(work, "tools", "scratch_body", "pic.png"))
        case("apply: the patch makes the archive of HEAD equal the tree", c_apply)

        def bad_patch(fn):
            p = open(st["patch"], "rb").read().decode()
            rejects(check_patch_bytes, fn(p).encode())
        case("check-patch: rejects a path outside the allow-list",
             lambda: bad_patch(lambda p: p.replace("tools/anatomy_teeth.py", "tools/preflight.sh")))
        case("check-patch: rejects a .. path",
             lambda: bad_patch(lambda p: p.replace("b/tools/scratch_body/new_trial.py", "b/tools/scratch_body/../../x")))
        case("check-patch: rejects a symlink",
             lambda: rejects(check_patch_bytes, b"diff --git a/tools/scratch_body/l b/tools/scratch_body/l\nnew file mode 120000\n"))
        case("check-patch: rejects a workflow path",
             lambda: rejects(check_patch_bytes, b"diff --git a/.github/workflows/x.yml b/.github/workflows/x.yml\n"))

        def mk_tar(entries):
            buf = io.BytesIO()
            with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0) as gz, tarfile.open(fileobj=gz, mode="w") as t:
                for name, kind, data in entries:
                    ti = tarfile.TarInfo(name)
                    if kind == "sym":
                        ti.type, ti.linkname = tarfile.SYMTYPE, "/etc/passwd"
                    elif kind == "dev":
                        ti.type = tarfile.CHRTYPE
                    else:
                        ti.size = len(data)
                    t.addfile(ti, io.BytesIO(data) if kind == "file" else None)
            return base64.b64encode(buf.getvalue()).decode()
        ok_run = ("job/run.sh", "file", b"true\n")
        for label, ents in [
            ("an absolute path", [ok_run, ("/etc/x", "file", b"x")]),
            ("a .. path", [ok_run, ("job/../x", "file", b"x")]),
            ("a symlink", [ok_run, ("job/l", "sym", b"")]),
            ("a device", [ok_run, ("job/d", "dev", b"")]),
            ("a path outside job/", [ok_run, ("other.txt", "file", b"x")]),
            ("401 files", [ok_run] + [("job/f%d" % i, "file", b"") for i in range(400)]),
            ("6 MB unpacked", [ok_run, ("job/big", "file", b"\0" * (6 * 1024 * 1024))]),
            ("no run.sh", [("job/x", "file", b"x")]),
        ]:
            case("unpack: rejects " + label,
                 lambda ents=ents: rejects(unpack_text, mk_tar(ents), os.path.join(tmp, "bad_" + str(abs(hash(str(ents)))))))

        # check-result
        res = os.path.join(tmp, "result")
        os.makedirs(os.path.join(res, "sub", "deep"))
        for n, d in [("meta.json", json.dumps({"exit_code": 3}).encode()), ("ok.txt", b"1"), ("pic.png", b"\x89PNG"),
                     ("sub/inner.json", b"{}"), ("evil.sh", b"rm -rf /"), ("big.txt", b"x" * (3 * 1024 * 1024)),
                     ("bad name.txt", b"x"), ("sub/deep/n.txt", b"x"), (".hidden.txt", b"x"), ("noext", b"x")]:
            write_file(os.path.join(res, n), d, 0o644)
        os.symlink("/etc/passwd", os.path.join(res, "link.txt"))
        clean = os.path.join(tmp, "clean")

        def c_res():
            old = sys.stdout; sys.stdout = io.StringIO(); olde = sys.stderr; sys.stderr = io.StringIO()
            try:
                check_result(res, clean)
                out = sys.stdout.getvalue()
            finally:
                sys.stdout, sys.stderr = old, olde
            assert out.strip() == "exit_code=3", out
        case("check-result: runs and reports the exit code", c_res)

        def got(p):
            return os.path.exists(os.path.join(clean, p))
        for p in ["meta.json", "ok.txt", "pic.png", "sub/inner.json"]:
            case("check-result: keeps " + p, lambda p=p: expect(got(p), "missing"))
        for p, why in [("link.txt", "a symlink"), ("evil.sh", "a .sh"), ("big.txt", "a 3 MB file"),
                       ("sub/deep/n.txt", "a nested directory"), ("bad name.txt", "a bad name"),
                       (".hidden.txt", "a dot name"), ("noext", "no extension")]:
            case("check-result: drops " + why, lambda p=p: expect(not got(p), "was kept"))

        def c_dropped():
            d = open(os.path.join(clean, "DROPPED.txt")).read()
            for p in ["link.txt", "evil.sh", "big.txt", "sub/deep/", "bad name.txt"]:
                assert p in d, p
        case("check-result: DROPPED.txt lists what was dropped", c_dropped)

        def c_count():
            r2, c2 = os.path.join(tmp, "r2"), os.path.join(tmp, "c2")
            os.makedirs(r2)
            for i in range(305):
                write_file(os.path.join(r2, "f%03d.txt" % i), b"x", 0o644)
            o = sys.stdout; sys.stdout = io.StringIO(); e = sys.stderr; sys.stderr = io.StringIO()
            try:
                check_result(r2, c2)
            finally:
                sys.stdout, sys.stderr = o, e
            n = len([x for x in os.listdir(c2) if x != "DROPPED.txt"])
            assert n == 300, n
        case("check-result: at most 300 files", c_count)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    bad = 0
    for label, ok, why in results:
        print("%s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  [" + why + "]"))
        bad += not ok
    print("%d cases, %d failed" % (len(results), bad))
    return 1 if bad else 0


# ----------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("pack", help="build the request for the Scratch build workflow")
    p.add_argument("--sha", required=True); p.add_argument("--src", required=True)
    p.add_argument("--job", required=True); p.add_argument("--out")
    p = sub.add_parser("unpack"); p.add_argument("request"); p.add_argument("dest")
    p = sub.add_parser("check-patch"); p.add_argument("patch")
    p = sub.add_parser("check-result"); p.add_argument("dir"); p.add_argument("dest")
    p = sub.add_parser("fetch"); p.add_argument("name"); p.add_argument("--to", required=True)
    sub.add_parser("selftest")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "pack":
            pack(a.sha, os.path.abspath(a.src), os.path.abspath(a.job), a.out)
        elif a.cmd == "unpack":
            unpack(a.request, a.dest)
        elif a.cmd == "check-patch":
            check_patch(a.patch)
        elif a.cmd == "check-result":
            check_result(a.dir, a.dest)
        elif a.cmd == "fetch":
            fetch(a.name, a.to)
        else:
            return selftest()
    except CiError as e:
        sys.stderr.write("error: %s\n" % e)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
