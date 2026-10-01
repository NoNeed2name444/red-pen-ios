#!/usr/bin/env python3
"""Run the app's standalone Swift test suites - here, on Linux CI, or on macOS CI.

The suites are listed once, in tools/swift_suites.txt ("suite <name>
<Test.swift> <sources...>"); the workflow and this script both read it.

    tools/swift_suites.py                     every suite
    tools/swift_suites.py --only sync,dataio  some
    tools/swift_suites.py --affected origin/personal   only suites whose test or
                                              sources changed since that commit
    tools/swift_suites.py --platform linux    skip the suites marked mac-only
    tools/swift_suites.py --list              names, and where each can run

Output is one line per suite (PASS / FAIL / NO BUILD) and a last summary line;
full logs go to out/<suite>.log. Exit status is non-zero if anything failed.
Mac-only suites (they import Apple frameworks Linux lacks) are listed in
tools/swift_suites_mac_only.txt, which --classify rewrites from a local run.
"""
import argparse, os, re, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SUITES = os.path.join(ROOT, "tools/swift_suites.txt")
MAC_ONLY = os.path.join(ROOT, "tools/swift_suites_mac_only.txt")
VARS = {"S": "ios/RedPen/Shared", "M": "ios/RedPen/Models", "F": "ios/RedPen/Features"}

def suites():
    text = open(SUITES).read().replace("\\\n", " ")
    out = {}
    for line in text.split("\n"):
        line = line.strip()
        if not line.startswith("suite ") or line.startswith("suite ()"):
            continue
        parts = line.split()[1:]
        name, test, srcs = parts[0], parts[1], parts[2:]
        srcs = [re.sub(r"\$(\w)", lambda m: VARS[m.group(1)], s) for s in srcs]
        out[name] = (test, srcs)
    return out

def mac_only():
    if not os.path.exists(MAC_ONLY): return set()
    return {l.split("#")[0].strip() for l in open(MAC_ONLY) if l.split("#")[0].strip()}

def fixtures():
    """The sample Word handout the docx suite opens (as the workflow made it)."""
    if os.path.exists(os.path.join(ROOT, "sample.docx")) or not shutil.which("zip"): return
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, "word/media"))
    open(os.path.join(d, "word/document.xml"), "w").write('<?xml version="1.0"?><w:document xmlns:w="x"><w:body><w:p><w:r><w:t>Lupus &amp; the kidney</w:t></w:r></w:p><w:p><w:r><w:t>Class IV</w:t></w:r><w:r><w:t> nephritis</w:t></w:r></w:p><w:p/><w:p><w:r><w:t>Treat with</w:t></w:r><w:br/><w:r><w:t>steroids</w:t></w:r></w:p></w:body></w:document>')
    open(os.path.join(d, "word/media/image2.png"), "w").write("two")
    open(os.path.join(d, "word/media/image10.png"), "w").write("ten")
    subprocess.run(["zip", "-qr", os.path.join(ROOT, "sample.docx"), "."], cwd=d, check=False)

def run(name, test, srcs, swiftc, opt):
    b = os.path.join(ROOT, "build", name); os.makedirs(b, exist_ok=True)
    shutil.copy(os.path.join(ROOT, "ios/RedPen/Tests", test), os.path.join(b, "main.swift"))
    log = []
    c = subprocess.run([swiftc, opt, *srcs, os.path.join(b, "main.swift"), "-o", os.path.join(b, "run")],
                       cwd=ROOT, capture_output=True, text=True)
    log.append(c.stdout + c.stderr); log.append(f"compile rc={c.returncode}")
    if c.returncode != 0:
        status, detail = "NO BUILD", next((l for l in (c.stdout + c.stderr).splitlines() if "error:" in l), "")
    else:
        try:
            r = subprocess.run([os.path.join(b, "run")], cwd=ROOT, capture_output=True, text=True, timeout=600)
            out, rc = r.stdout + r.stderr, r.returncode
        except subprocess.TimeoutExpired as e:
            out, rc = (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or ""), 124
        log.append(out); log.append(f"run rc={rc}")
        fails = [l for l in out.splitlines() if l.startswith("FAIL")]
        status = "PASS" if rc == 0 else "FAIL"
        detail = fails[0] if fails else ("" if rc == 0 else f"exit {rc}")
    os.makedirs(os.path.join(ROOT, "out"), exist_ok=True)
    open(os.path.join(ROOT, "out", name + ".log"), "w").write("\n".join(log))
    return name, status, re.sub(r"^.*?/ios/", "ios/", detail)[:200]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--affected", default="", help="a git ref: suites whose files changed since it")
    ap.add_argument("--platform", choices=["linux", "mac", "any"], default="any",
                    help="linux: skip mac-only suites; mac: only mac-only suites")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--classify", action="store_true", help="rewrite the mac-only list from this run's NO BUILDs")
    ap.add_argument("-j", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--swiftc", default=shutil.which("swiftc") or "/opt/swift/usr/bin/swiftc")
    ap.add_argument("-O", dest="opt", default="-Onone", help="optimisation flag (CI uses -O)")
    a = ap.parse_args()
    all_s, macs = suites(), mac_only()
    if a.list:
        for n in all_s: print(f"{n:22} {'mac-only' if n in macs else 'linux+mac'}")
        return 0
    chosen = list(all_s)
    if a.only: chosen = [n for n in chosen if n in set(a.only.split(","))]
    if a.affected:
        changed = set(subprocess.run(["git", "diff", "--name-only", a.affected, "--"], cwd=ROOT,
                                     capture_output=True, text=True).stdout.split())
        changed |= set(subprocess.run(["git", "diff", "--name-only"], cwd=ROOT, capture_output=True, text=True).stdout.split())
        if any(c.startswith(".github/workflows/swift-tests") or c.startswith("tools/swift_suites") for c in changed):
            pass  # the list itself changed: everything
        else:
            chosen = [n for n in chosen if ("ios/RedPen/Tests/" + all_s[n][0]) in changed or set(all_s[n][1]) & changed]
    if a.platform == "linux": chosen = [n for n in chosen if n not in macs]
    if a.platform == "mac": chosen = [n for n in chosen if n in macs]
    if not chosen:
        print("no suites to run"); return 0
    fixtures()
    with ThreadPoolExecutor(max_workers=a.j) as ex:
        results = list(ex.map(lambda n: run(n, *all_s[n], a.swiftc, a.opt), chosen))
    bad = 0
    for n, st, d in sorted(results, key=lambda r: (r[1] == "PASS", r[0])):
        print(f"{st:8} {n:22} {d}")
        bad += st != "PASS"
    print(f"{len(results) - bad}/{len(results)} suites passed")
    if a.classify:
        nob = sorted(n for n, st, _ in results if st == "NO BUILD")
        open(MAC_ONLY, "w").write("# Suites that need Apple frameworks Linux lacks; they run on macOS CI.\n"
                                  "# Rewritten by tools/swift_suites.py --classify on Linux.\n" + "".join(n + "\n" for n in nob))
    return 1 if bad else 0

sys.exit(main())
