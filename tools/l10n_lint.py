# What still stands between the app and a full Arabic (right-to-left) build.
#
#   python3 tools/l10n_lint.py [ios/RedPen] [--out l10n-report.md] [--strict]
#
# Reads every Swift file and writes a report of:
#
#   Not localisable (the words cannot be translated as written)
#     concat-text     a String glued together with + inside Text(...), or
#                     Text + Text: the order of the parts is English's
#     format-english  String(format:) with English words in the format
#     plural          a hard-coded English plural: == 1 ? "" : "s", \(plural)
#     fixed-date      a date written with a fixed pattern or a fixed locale
#     not-in-catalog  a literal on screen (Text, Label, Button, Toggle,
#                     navigationTitle, accessibilityLabel...) with no catalog
#                     key yet: the Xcode build could translate it, the
#                     Playgrounds build cannot until it goes through L10n
#   Physical left and right (they do not turn round in Arabic)
#     symbol          "chevron.right", "arrow.left"...: use .forward/.backward
#     left-right      .left / .right (alignment, padding, edges)
#                     where .leading / .trailing is meant
#     offset-x        .offset(x: n): an offset is never mirrored (right over
#                     a picture, whose content does not turn round; wrong
#                     for a layout)
#     arrow-key       .leftArrow / .rightArrow: next and back swap sides
#     ring            a .trim(...) arc with no .fillsFromLeading(): rings
#                     should run from the leading side
#     wording         a comment that places something on the left or right:
#                     check that the layout it describes still mirrors
#   Wired but broken (a bug today)
#     missing-key     Text(l10n:), L10n.string(...) with no such catalog key
#
# A line whose comment says "l10n: ok" has been looked at and is meant as it
# is (mirrored by hand, or a picture that must not turn round); it is skipped.
#
# It never fails the build unless --strict is given, and then only for
# missing-key: the rest is the to-do list for the string sweep.
import json, os, re, sys
from collections import defaultdict

ROOT = "ios/RedPen"
CATALOG = "Resources/Localizable.xcstrings"
SKIP_DIRS = {"Tests"}

STRING = re.compile(r'"(?:\\.|[^"\\])*"')
INTERP = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")
UI_CALLS = re.compile(
    r'(?:\bText|\bLabel|\bButton|\bToggle|\bSection|\bPicker|\bLabeledContent|\bTextField|'
    r'\.navigationTitle|\.accessibilityLabel|\.accessibilityHint|\.alert|\.confirmationDialog|'
    r'\bMenu|\bLink|\bStepper|\bDatePicker)\(\s*("(?:\\.|[^"\\])*")')
L10N_CALLS = re.compile(r'(?:Text\(l10n:\s*|L10n\.string\()\s*("(?:\\.|[^"\\])*")')
CATEGORIES = [
    ("missing-key", "Wired but broken: no such catalog key"),
    ("concat-text", "String concatenation into Text"),
    ("format-english", "String(format:) with English words"),
    ("plural", "Hard-coded English plurals"),
    ("fixed-date", "Dates in a fixed pattern or locale"),
    ("symbol", "Directional SF Symbols (use .forward / .backward)"),
    ("left-right", ".left / .right instead of .leading / .trailing"),
    ("offset-x", "Horizontal offsets (never mirrored; right for a picture, wrong for a layout)"),
    ("arrow-key", "Left / right arrow keys"),
    ("ring", "Rings and arcs not filling from the leading side"),
    ("wording", "Comments that place things left or right"),
    ("not-in-catalog", "On-screen literals not in the catalog yet"),
]


def split_comment(line):
    """(code, comment) of one line, ignoring // inside string literals."""
    in_string = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == "\\" and in_string:
            i += 2
            continue
        if c == '"':
            in_string = not in_string
        elif not in_string and line.startswith("//", i):
            return line[:i], line[i:]
        i += 1
    return line, ""


def swift_literal_to_key(literal):
    """The catalog key a Swift literal becomes: \\(x) as a pattern that
    matches %@ / %lld / %d / %f, escapes decoded."""
    body = literal[1:-1]
    parts = INTERP.split(body)
    decoded = [decode(p) for p in parts]
    pattern = r"%(?:\d+\$)?(?:@|l{0,2}[dfu]|\.\d+f)".join(re.escape(p) for p in decoded)
    return re.compile("^" + pattern + "$"), len(parts) > 1


def decode(text):
    text = re.sub(r"\\u\{([0-9a-fA-F]+)\}", lambda m: chr(int(m.group(1), 16)), text)
    return (text.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t")
            .replace("\\'", "'").replace("\\\\", "\\"))


def load_keys(root):
    path = os.path.join(root, CATALOG)
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as f:
        return set(json.load(f)["strings"].keys())


def in_catalog(literal, keys, exact_cache):
    pattern, interpolated = swift_literal_to_key(literal)
    if not interpolated:
        return decode(literal[1:-1]) in keys
    return any(pattern.match(k) for k in keys)


def english_words(fmt):
    stripped = re.sub(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:l{0,2}|h{0,2})[a-zA-Z@]", " ", fmt)
    # words, not hexadecimal ("5EA50000-...")
    return any(not re.fullmatch(r"[A-Fa-f]+", w) for w in re.findall(r"[A-Za-z]{2,}", stripped))


def scan_file(path, rel, keys, found):
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    for n, raw in enumerate(lines, 1):
        code, comment = split_comment(raw)
        if "l10n: ok" in comment:
            # looked at and meant: already mirrored by hand, or a picture
            # that must not turn round
            continue
        where = (rel, n, raw.strip()[:160])
        blank = STRING.sub('""', code)
        # --- not localisable
        for m in L10N_CALLS.finditer(code):
            if keys and not in_catalog(m.group(1), keys, None):
                found["missing-key"].append(where)
        if re.search(r'\bText\([^()]*\+', blank) or re.search(r'\bText\([^()]*\)\s*\+\s*Text\(', blank):
            found["concat-text"].append(where)
        for m in re.finditer(r'String\(format:\s*("(?:\\.|[^"\\])*")', code):
            if english_words(m.group(1)[1:-1]):
                found["format-english"].append(where)
        if re.search(r'==\s*1\s*\?\s*""\s*:\s*"s"|\\\(plural\)|let plural\b|"s"\s*:\s*""', code):
            found["plural"].append(where)
        if re.search(r'dateFormat\s*=|Locale\(identifier:\s*"en', code):
            found["fixed-date"].append(where)
        if keys:
            for m in UI_CALLS.finditer(code):
                literal = m.group(1)
                text = decode(literal[1:-1])
                if not re.search(r"[A-Za-z]{2,}", INTERP.sub("", text)):
                    continue
                if not in_catalog(literal, keys, None):
                    found["not-in-catalog"].append(where)
        # --- physical left and right
        for m in re.finditer(r'"((?:chevron|arrow|arrowshape|arrowtriangle|chevron\.compact)[\w.]*)"', code):
            name = m.group(1)
            parts = name.split(".")
            if ("left" in parts) != ("right" in parts):
                found["symbol"].append(where)
        if re.search(r'(alignment:|padding\(|edges?:|textAlignment\s*=|Edge\.Set\(|Edge\.|\.frame\([^)]*alignment:)'
                     r'\s*\[?\s*\.(left|right)\b', blank):
            found["left-right"].append(where)
        m = re.search(r'\.offset\(\s*x:\s*([^,)]+)', blank)
        if m and m.group(1).strip() not in ("0", "0.0"):
            found["offset-x"].append(where)
        if re.search(r'\.(leftArrow|rightArrow)\b', blank):
            found["arrow-key"].append(where)
        if ".trim(from:" in blank:
            window = "\n".join(lines[n - 1:n + 6])
            if "fillsFromLeading" not in window and "flipsForRightToLeft" not in window:
                found["ring"].append(where)
        if comment and re.search(r'\b(to|on|at) the (left|right)\b|\b(left|right)[- ](hand|thumb|edge|side)\b',
                                 comment, re.I):
            found["wording"].append(where)


def scan(root):
    keys = load_keys(root)
    found = defaultdict(list)
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for name in sorted(filenames):
            if name.endswith(".swift"):
                path = os.path.join(dirpath, name)
                scan_file(path, os.path.relpath(path, root), keys, found)
    return found, keys


def report(found, keys, root):
    out = ["# Localisation and right-to-left report", "",
           f"Scanned `{root}`; the catalog has {len(keys)} keys.", "",
           "| What | Count | Files |", "|---|---:|---:|"]
    for cat, title in CATEGORIES:
        hits = found.get(cat, [])
        files = len({h[0] for h in hits})
        out.append(f"| {title} (`{cat}`) | {len(hits)} | {files} |")
    for cat, title in CATEGORIES:
        hits = found.get(cat, [])
        if not hits:
            continue
        out += ["", f"## {title} (`{cat}`)", ""]
        per_file = defaultdict(list)
        for rel, n, text in hits:
            per_file[rel].append((n, text))
        for rel in sorted(per_file, key=lambda r: (-len(per_file[r]), r)):
            out.append(f"- `{rel}` ({len(per_file[rel])})")
            for n, text in per_file[rel]:
                shown = text.replace("`", "'")
                out.append(f"  - {n}: `{shown}`")
    return "\n".join(out) + "\n"


def main(argv):
    root = ROOT
    out_path = "l10n-report.md"
    strict = False
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--out":
            out_path = args.pop(0)
        elif a == "--strict":
            strict = True
        else:
            root = a
    found, keys = scan(root)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(report(found, keys, root))
    for cat, title in CATEGORIES:
        print(f"{len(found.get(cat, [])):5d}  {title}")
    print(f"report: {out_path}")
    broken = found.get("missing-key", [])
    for rel, n, text in broken:
        print(f"missing catalog key: {rel}:{n}: {text}")
    return 1 if strict and broken else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
