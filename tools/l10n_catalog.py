# The String Catalog (ios/RedPen/Resources/Localizable.xcstrings), read
# without Xcode.
#
#   python3 tools/l10n_catalog.py check ios/RedPen/Resources/Localizable.xcstrings
#       every key has a finished translation in every language the catalog
#       has, its format specifiers match the key's, and each plural has the
#       categories its language needs (Arabic: zero, one, two, few, many, other)
#   python3 tools/l10n_catalog.py lproj <catalog> <out dir>
#       writes <lang>.lproj/Localizable.strings and .stringsdict
#
# Why the second: Xcode compiles a .xcstrings on its own, but a Swift
# Playgrounds package cannot be counted on to, so make_swiftpm.py gives the
# package the plain .strings/.stringsdict an older toolchain has always
# understood, made from the same catalog (see L10n.swift).
import json, os, re, sys
from xml.sax.saxutils import escape

TABLE = "Localizable"
# The plural categories each language uses (CLDR). A language missing here
# is only asked for "other".
PLURALS = {
    "en": {"one", "other"},
    "ar": {"zero", "one", "two", "few", "many", "other"},
}
SPEC = re.compile(r"%(?:(\d+)\$)?(#@\w+@|l{0,2}[dixuoXfeEgGcs@])")


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def languages(catalog):
    found = {catalog.get("sourceLanguage", "en")}
    for entry in catalog["strings"].values():
        found.update(entry.get("localizations", {}).keys())
    return sorted(found)


def specs(text):
    """The kinds of the format specifiers in `text`, in argument order."""
    out = {}
    position = 0
    for m in SPEC.finditer(text.replace("%%", "")):
        if m.group(2).startswith("#@"):
            continue
        position += 1
        index = int(m.group(1)) if m.group(1) else position
        kind = m.group(2)
        out[index] = "@" if kind == "@" else ("d" if kind[-1] in "dixu" else kind[-1])
    return out


def units(localization):
    """Every finished text in one language's entry: (label, value, state)."""
    out = []
    if "stringUnit" in localization:
        u = localization["stringUnit"]
        out.append(("", u.get("value", ""), u.get("state", "")))
    for form, v in localization.get("variations", {}).get("plural", {}).items():
        u = v.get("stringUnit", {})
        out.append((form, u.get("value", ""), u.get("state", "")))
    return out


def check(catalog):
    """Problems with the catalog, as sentences; empty when it is sound."""
    problems = []
    source = catalog.get("sourceLanguage", "en")
    wanted = [l for l in languages(catalog) if l != source]
    for key, entry in sorted(catalog["strings"].items()):
        locs = entry.get("localizations", {})
        key_specs = specs(key)
        for lang in wanted:
            loc = locs.get(lang)
            if loc is None:
                problems.append(f"{lang}: no translation for {key!r}")
                continue
            plural = loc.get("variations", {}).get("plural")
            if plural is not None:
                need = PLURALS.get(lang, {"other"})
                missing = sorted(need - set(plural))
                if missing:
                    problems.append(f"{lang}: {key!r} lacks plural forms {missing}")
            for sub_name, sub in loc.get("substitutions", {}).items():
                forms = sub.get("variations", {}).get("plural", {})
                missing = sorted(PLURALS.get(lang, {"other"}) - set(forms))
                if missing:
                    problems.append(f"{lang}: {key!r} substitution {sub_name} lacks {missing}")
            for form, value, state in units(loc):
                where = f"{key!r}" + (f" [{form}]" if form else "")
                if state != "translated":
                    problems.append(f"{lang}: {where} is {state or 'unfinished'}")
                if not value.strip():
                    problems.append(f"{lang}: {where} is empty")
                if "substitutions" in loc:
                    continue
                got = specs(value)
                # a plural form may leave its number out ("one second"), but
                # never add or change one
                extra = {i: k for i, k in got.items() if key_specs.get(i) != k}
                if extra:
                    problems.append(f"{lang}: {where} has format {extra}, the key has {key_specs}")
                if not form and got != key_specs:
                    problems.append(f"{lang}: {where} formats {got}, the key {key_specs}")
    return problems


def strings_escape(text):
    return (text.replace("\\", "\\\\").replace('"', '\\"')
            .replace("\n", "\\n").replace("\t", "\\t"))


def plural_dict(forms, value_type, arg=None, spec=None):
    """One stringsdict variable: its type and a text per category."""
    rows = ["<key>NSStringFormatSpecTypeKey</key><string>NSStringPluralRuleType</string>",
            f"<key>NSStringFormatValueTypeKey</key><string>{value_type}</string>"]
    for form in ("zero", "one", "two", "few", "many", "other"):
        if form in forms:
            text = forms[form]["stringUnit"]["value"]
            if arg is not None:
                text = text.replace("%arg", f"%{arg}${spec}")
            rows.append(f"<key>{form}</key><string>{escape(text)}</string>")
    return "<dict>" + "".join(rows) + "</dict>"


def first_spec(key):
    m = re.search(r"%(?:\d+\$)?(l{0,2}[dixu@])", key)
    return m.group(1) if m else "lld"


def tables(catalog):
    """{lang: (strings lines, stringsdict entries)} for every language."""
    source = catalog.get("sourceLanguage", "en")
    out = {lang: ([], []) for lang in languages(catalog)}
    for key, entry in sorted(catalog["strings"].items()):
        for lang, (lines, plurals) in out.items():
            loc = entry.get("localizations", {}).get(lang)
            if loc is None:
                if lang == source:
                    # the key is its own English
                    lines.append(f'"{strings_escape(key)}" = "{strings_escape(key)}";')
                continue
            plural = loc.get("variations", {}).get("plural")
            subs = loc.get("substitutions")
            if plural is not None:
                body = plural_dict(plural, first_spec(key))
                plurals.append(f"<key>{escape(key)}</key><dict>"
                               "<key>NSStringLocalizedFormatKey</key><string>%#@value@</string>"
                               f"<key>value</key>{body}</dict>")
            elif subs:
                head = loc["stringUnit"]["value"]
                parts = [f"<key>NSStringLocalizedFormatKey</key><string>{escape(head)}</string>"]
                for name, sub in sorted(subs.items()):
                    spec = sub.get("formatSpecifier", "lld")
                    forms = sub["variations"]["plural"]
                    parts.append(f"<key>{escape(name)}</key>"
                                 + plural_dict(forms, spec, sub.get("argNum", 1), spec))
                plurals.append(f"<key>{escape(key)}</key><dict>{''.join(parts)}</dict>")
            else:
                value = loc["stringUnit"]["value"]
                lines.append(f'"{strings_escape(key)}" = "{strings_escape(value)}";')
    return out


def write_lproj(catalog, out_dir):
    """Writes <lang>.lproj/Localizable.strings (and .stringsdict)."""
    written = []
    for lang, (lines, plurals) in tables(catalog).items():
        folder = os.path.join(out_dir, f"{lang}.lproj")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, f"{TABLE}.strings"), "w", encoding="utf-8") as f:
            f.write("/* Made from Localizable.xcstrings by tools/l10n_catalog.py */\n")
            f.write("\n".join(lines) + "\n")
        written.append(lang)
        if plurals:
            with open(os.path.join(folder, f"{TABLE}.stringsdict"), "w", encoding="utf-8") as f:
                f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
                        '<plist version="1.0"><dict>\n' + "\n".join(plurals) + "\n</dict></plist>\n")
    return written


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("check", "lproj"):
        print(__doc__ or "usage: l10n_catalog.py check|lproj <catalog> [out]")
        sys.exit(2)
    catalog = load(sys.argv[2])
    if sys.argv[1] == "check":
        problems = check(catalog)
        for p in problems:
            print("catalog:", p)
        count = len(catalog["strings"])
        print(f"{count} keys, languages {languages(catalog)}, {len(problems)} problem(s)")
        sys.exit(1 if problems else 0)
    print("lproj:", write_lproj(catalog, sys.argv[3]))
