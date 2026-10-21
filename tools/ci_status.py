#!/usr/bin/env python3
"""CI in a few lines: one per workflow run for a branch or commit, and for a
failure only its first error lines - so nobody (person or agent) reads a
thousand-line log to find one mistake.

    tools/ci_status.py personal            the newest commit's runs on a branch
    tools/ci_status.py 25b4ed4             a commit's runs on any branch
    tools/ci_status.py personal --wait     wait until every run finishes
Exit status: 0 all green, 1 something failed, 2 still running (without --wait).
"""
import json, re, subprocess, sys, time, urllib.request

REPO = "NoNeed2name444/red-pen-ios"
API = f"https://api.github.com/repos/{REPO}"

def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"}), timeout=30) as r:
        return json.load(r)

def sha_of(ref):
    if re.fullmatch(r"[0-9a-f]{7,40}", ref):
        out = subprocess.run(["git", "rev-parse", ref], capture_output=True, text=True).stdout.strip()
        return out or ref
    return get(f"{API}/branches/{ref}")["commit"]["sha"]

def errors(job_id):
    """The first error lines of a failed job, via gh (the log needs a token)."""
    out = subprocess.run(["gh", "api", f"repos/{REPO}/actions/jobs/{job_id}/logs"], capture_output=True, text=True).stdout
    keep = [re.sub(r"^\S+Z ", "", l) for l in out.splitlines()
            if re.search(r"error:|^.{0,40}(FAIL|NO BUILD) |Test Case .* failed|##\[error\]", l)]
    seen, lines = set(), []
    for l in keep:
        l = re.sub(r"/Users/runner/work/[^ ]*?/ios/", "ios/", l).strip()
        if l not in seen: seen.add(l); lines.append(l[:220])
    return lines[:6]

def main():
    if len(sys.argv) < 2: print(__doc__); return 2
    ref, wait = sys.argv[1], "--wait" in sys.argv
    sha = sha_of(ref)
    while True:
        runs = get(f"{API}/actions/runs?head_sha={sha}&per_page=50")["workflow_runs"]
        if ref != sha and not re.fullmatch(r"[0-9a-f]{7,40}", ref):
            runs = [r for r in runs if r["head_branch"] == ref] or runs
        pending = [r for r in runs if r["status"] != "completed"]
        if not wait or (runs and not pending): break
        time.sleep(60)
    if not runs:
        print(f"{sha[:7]}: no runs yet"); return 2
    bad = 0
    for r in sorted(runs, key=lambda r: r["name"]):
        state = r["conclusion"] or r["status"]
        print(f"{state:12} {r['name']:22} {r['head_branch']:28} {r['id']}")
        if r["conclusion"] in ("failure", "timed_out"):
            bad += 1
            for j in get(r["jobs_url"])["jobs"]:
                if j["conclusion"] in ("failure", "timed_out"):
                    for l in errors(j["id"]): print(f"    {j['name']}: {l}")
    return 1 if bad else (2 if any(r["status"] != "completed" for r in runs) else 0)

sys.exit(main())
