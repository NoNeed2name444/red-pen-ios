#!/usr/bin/env python3
"""atlas_refs.py: reference images for every structure in the anatomy atlas, free to use commercially, to check the
models against at every change. The images are looked at, never shipped or traced.

  atlas_refs.py index <anatomy.json> <out.json>
      For each structure (its left and right as one, where both lead to the same article), finds its Wikidata item
      (by its UBERON id, else by a search of English Wikipedia for its name), then the pictures its articles show in
      seven Wikipedias (English, German, French, Spanish, Italian, Japanese, Russian), the item's own image, and the
      files in its Commons category that name it. Keeps the files whose licence allows commercial use (public domain
      and CC0, CC BY, and CC BY-SA, which is marked share-alike), with each one's author and licence; drops
      non-human anatomy, the wikis' icons and pictures shown on too many articles to be about any one; and writes
      them per structure, the pictures most of the Wikipedias show first.
  atlas_refs.py pages <index.json> <out dir>
      The same index as one Markdown page per body system, with every image linked, to browse on a phone.
  atlas_refs.py sheet <index.json> <regex> <out.png> [images per structure]
      Fetches the images of the structures whose name, label or node matches, and lays them out on one sheet with each
      image's structure, file, licence and author under it.

The lookups go through the Wikidata Query Service, whose MediaWiki API service runs the wikis' searches, picture lists
and licence reads on its side, many to a query (the wikis' own APIs rate-limit shared addresses too hard to make
thousands of calls). Calls go one at a time and wait after a refusal; every answer is kept in a cache
(ATLAS_REFS_CACHE, by default ~/.cache/atlas_refs), so a run that stops picks up where it was.
"""
import gzip
import hashlib
import http.client
import html
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "StethoscoreAtlasRefs/0.2 (anatomy reference index; python-urllib)"
CACHE = os.environ.get("ATLAS_REFS_CACHE") or os.path.expanduser("~/.cache/atlas_refs")
CTX = ssl.create_default_context(cafile=os.environ.get("SSL_CERT_FILE") or None)
GAP = 1.0                # seconds between calls
LAST = [0.0]
LANGS = ("en", "de", "fr", "es", "it", "ja", "ru")
META = "License|LicenseShortName|Copyrighted|Artist|ImageDescription"
OUT = {"title": "mwapi:title", "lic": '"imageinfo/ii/extmetadata/LicenseShortName/@value"',
       "code": '"imageinfo/ii/extmetadata/License/@value"', "cr": '"imageinfo/ii/extmetadata/Copyrighted/@value"',
       "by": '"imageinfo/ii/extmetadata/Artist/@value"', "desc": '"imageinfo/ii/extmetadata/ImageDescription/@value"',
       "w": '"imageinfo/ii/@width"', "h": '"imageinfo/ii/@height"', "mime": '"imageinfo/ii/@mime"'}
ANIMAL = re.compile(r"\b(dogs?|canine|canis|cats?|feline|felis|horses?|equine|equus|bovine|cows?|cattle|sheep|ovine|pigs?|"
                    r"porcine|swine|rats?|mouse|mice|murine|rabbits?|birds?|avian|chickens?|fish|frogs?|frosch\w*|"
                    r"reptiles?|lizards?|snakes?|turtles?|dinosaurs?|fossils?|mammoth|chimp\w*|gorillas?|monkeys?|"
                    r"macaques?|whales?|dolphins?|bears?|deer|elephants?|kangaroos?|goats?|camels?|ape|apes|primates?|"
                    r"vertebrates?|animals?|zebrafish|drosophila|bats?|crocod\w*|alligators?|sharks?|lemurs?|"
                    r"marsupial\w*|eutherian|zoolog\w*|glyptodon\w*|holotype|paratype)(?![a-z])"
                    r"|saurus|insect|neanderthal", re.I)
# pictures in an anatomy article that are not of anatomy: works of art and objects shown in museums of them
NOT_ANATOMY = re.compile(r"museum of art|\bMET DP|krater|figurine|archaeolog|tournament|deutsches museum|glenside museum|"
                         r"painting|sculpture|statue|amphora|mosaic|fresco", re.I)
ICON = re.compile(r"(logo|icon|^commons|wikidata|wiktionary|wikibooks|wikisource|wikiversity|question.book|ambox|"
                  r"edit-clear|padlock|crystal.clear|nuvola|disambig|stub|flag.of|speaker|gnome-|folder.hexagonal|"
                  r"portal-puzzle|^p[ _]\w+\.svg$|red.pencil|oojs|placeholder|replace.this|loudspeaker|symbol.support)", re.I)
PLATE = re.compile(r"gray\d|gray's|vandyke|sobotta|bourgery|testut|spalteholz|toldt|cunningham|quain|henle|rauber|"
                   r"openstax|blausen|servier|dissect|cadaver|specimen", re.I)
SIDE = re.compile(r"\b(left|right)\b\s*", re.I)
STOP = {"of", "the", "and", "left", "right", "part", "region", "area", "structure", "segment", "muscle", "bone", "body",
        "compact", "fasciculus", "anterior", "posterior", "superior", "inferior", "lateral", "medial", "external",
        "internal", "deep", "superficial", "lobe", "branch", "with", "from", "for", "proper", "human", "anatomy"}


def get(url, data=None, path=None, check=None):
    """One call, cached (at `path` if given), at its turn; retried with growing waits on 429, server or network
    errors and answers that `check` finds cut short (none of which is cached)."""
    if path is None:
        key = hashlib.sha1((url + "\0" + (data or "")).encode()).hexdigest()
        path = os.path.join(CACHE, "api", key[:2], key)
    if os.path.exists(path):
        with open(path, "rb") as fh:
            return fh.read()
    wait = 2.0
    for _ in range(12):
        dt = time.time() - LAST[0]
        if dt < GAP:
            time.sleep(GAP - dt)
        LAST[0] = time.time()
        req = urllib.request.Request(url, data=data.encode() if data else None,
                                     headers={"User-Agent": UA, "Accept-Encoding": "gzip"})
        try:
            with urllib.request.urlopen(req, context=CTX, timeout=150) as r:
                body = r.read()
                if r.headers.get("Content-Encoding") == "gzip":
                    body = gzip.decompress(body)
            if check is None or check(body):
                break
            time.sleep(wait); wait = min(wait * 2, 120)
        except urllib.error.HTTPError as e:
            if e.code not in (429, 500, 502, 503, 504):
                raise
            ra = e.headers.get("Retry-After")
            time.sleep(max(float(ra) if ra and ra.isdigit() else 0.0, wait)); wait = min(wait * 2, 120)
        except (urllib.error.URLError, TimeoutError, ConnectionError, ssl.SSLError, http.client.HTTPException, EOFError):
            time.sleep(wait); wait = min(wait * 2, 120)
    else:
        raise RuntimeError(f"gave up on {url[:160]}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".part", "wb") as fh:
        fh.write(body)
    os.replace(path + ".part", path)
    return body


def whole(body):
    """Whether an answer is complete JSON (a connection can drop mid-answer without an error)."""
    try:
        json.loads(body)
        return True
    except ValueError:
        return False


def sparql(q):
    d = json.loads(get("https://query.wikidata.org/sparql?format=json", urllib.parse.urlencode({"query": q}), check=whole))
    return [{k: v["value"] for k, v in b.items()} for b in d["results"]["bindings"]]


def lit(s, lang=None):
    """A SPARQL string literal."""
    return json.dumps(s, ensure_ascii=False) + (f"@{lang}" if lang else "")


def chunks(xs, n=50):
    xs = list(xs)
    return [xs[i:i + n] for i in range(0, len(xs), n)]


def mwapi(endpoint, params, inputs, outs, batch=20, api="Generator", ordinal=False, pages=None):
    """Rows of a MediaWiki API call the query service makes on `endpoint` for each input (bound to ?in): params
    {name: value or "?in"}, outs {variable: apiOutput}; with ordinal, each row's place in its answer as ?ord; with
    `pages`, at most that many further pages of each answer (the service otherwise follows a search's pages until
    the query times out)."""
    rows = []
    for c in chunks(inputs, batch):
        ps = "; ".join(f"mwapi:{k} {v if v == '?in' else lit(v)}" for k, v in params.items())
        if pages is not None:
            ps = f"wikibase:limitContinuations {int(pages)}; " + ps
        os_ = " ".join(f"?{k} wikibase:apiOutput {v}." for k, v in outs.items()) + (" ?ord wikibase:apiOrdinal true." if ordinal else "")
        rows += sparql(f"""SELECT ?in {' '.join('?' + k for k in outs)}{' ?ord' if ordinal else ''} WHERE {{ VALUES ?in {{ {' '.join(lit(x) for x in c)} }}
            SERVICE wikibase:mwapi {{ bd:serviceParam wikibase:endpoint {lit(endpoint)}; wikibase:api {lit(api)}; {ps}.
            {os_} }} }}""")
    return rows


def plain(label):
    return re.sub(r"\s+", " ", SIDE.sub("", label)).strip()


def words(s):
    return {w[:5] for w in re.findall(r"[a-z]+", (s or "").lower()) if len(w) > 3 and w not in STOP}


def text(s, n):
    s = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s or ""))).strip()
    return s if len(s) <= n else s[:n - 1].rstrip() + "…"


def tier(m):
    """pd (public domain, CC0), by (CC BY, attribution), by-sa (share-alike), or None (not free to use commercially)."""
    code, short = (m.get("code") or "").lower(), (m.get("lic") or "").lower()
    s = f"{code} {short}"
    if re.search(r"\bnc\b|-nc\b|-nc-|non.?commercial|-nd\b|\bnd\b|no.?deriv|fair.use|non.?free", s):
        return None
    if code in ("pd", "cc0") or code.startswith("pd-") or "public domain" in short or short.startswith("cc0") \
            or m.get("cr") == "False":
        return "pd"
    if "by-sa" in s or "by sa" in s:
        return "by-sa"
    if code.startswith("cc-by") or short.startswith("cc by") or "attribution" in (code, short):
        return "by"
    return None


def file_row(r):
    """A picture as the index keeps it, from a row of the API's image info; None if it is not usable."""
    name = r["title"].split(":", 1)[1] if ":" in r["title"] else r["title"]
    t = tier(r)
    w, h = int(float(r.get("w") or 0)), int(float(r.get("h") or 0))
    desc = text(r.get("desc"), 110)
    if not t or not (r.get("mime") or "").startswith("image/") or "djvu" in (r.get("mime") or "") or min(w, h) < 150 \
            or ICON.search(name) or ANIMAL.search(name + " " + desc) or NOT_ANATOMY.search(name + " " + desc):
        return None
    return {"f": name, "t": t, "lic": text(r.get("lic"), 30) or None, "by": text(r.get("by"), 70) or None, "w": w, "h": h,
            **({"desc": desc} if desc else {})}


def entries(manifest):
    """The atlas's structures by label: their nodes, UBERON ids, tissue, system and part."""
    out = {}
    for b in manifest["bodies"]:
        for p in b["parts"]:
            for s in p["structures"]:
                e = out.setdefault(s["label"], {"label": s["label"], "nodes": [], "uberon": set(), "tissue": s["tissue"],
                                                "system": p["system"], "part": p["id"]})
                e["nodes"].append(f"{b['id']}/{s['node']}")
                if s.get("uberon"):
                    e["uberon"].add(s["uberon"])
    return out


def by_uberon(ids):
    """UBERON id -> its Wikidata item: the one with an English article, else the most linked."""
    best = {}
    for c in chunks(ids, 150):
        rows = sparql(f"""SELECT ?ub ?item ?art ?n WHERE {{ VALUES ?ub {{ {' '.join(lit(u.split(':')[1]) for u in c)} }}
            ?item wdt:P1554 ?ub ; wikibase:sitelinks ?n .
            OPTIONAL {{ ?art schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> }} }}""")
        for r in rows:
            u = "UBERON:" + r["ub"]; score = (bool(r.get("art")), int(r["n"]))
            if u not in best or score > best[u][0]:
                best[u] = (score, r["item"].rsplit("/", 1)[1])
    return {u: q for u, (_, q) in best.items()}


def search(labels):
    """Label without its side -> the first English Wikipedia article a search for it finds that shares a word with it."""
    rows = mwapi("en.wikipedia.org", {"srsearch": "?in", "srlimit": "5"}, sorted({plain(l) for l in labels}),
                 {"title": "mwapi:title"}, batch=25, api="Search", ordinal=True, pages=0)
    hits = {}
    for r in sorted(rows, key=lambda r: int(r.get("ord", 99))):
        if int(r.get("ord", 99)) < 5 and r["in"] not in hits and words(r["title"]) & words(r["in"]):
            hits[r["in"]] = r["title"]
    return hits


def items_of(titles):
    """English article -> its Wikidata item (not a disambiguation page)."""
    out = {}
    for c in chunks(titles, 150):
        for r in sparql(f"""SELECT ?t ?item WHERE {{ VALUES ?t {{ {' '.join(lit(t, 'en') for t in c)} }}
                ?a schema:name ?t ; schema:isPartOf <https://en.wikipedia.org/> ; schema:about ?item .
                FILTER NOT EXISTS {{ ?item wdt:P31 wd:Q4167410 }} }}"""):
            out[r["t"]] = r["item"].rsplit("/", 1)[1]
    return out


def about(qids):
    """Item -> its image, Commons category and its articles in LANGS {lang: title}."""
    out = {q: {"image": None, "category": None, "articles": {}} for q in qids}
    wikis = ", ".join(f"<https://{l}.wikipedia.org/>" for l in LANGS)
    for c in chunks(qids, 120):
        for r in sparql(f"""SELECT ?item ?img ?cat ?wiki ?t WHERE {{ VALUES ?item {{ {' '.join('wd:' + q for q in c)} }}
                OPTIONAL {{ ?item wdt:P18 ?img }} OPTIONAL {{ ?item wdt:P373 ?cat }}
                OPTIONAL {{ ?a schema:about ?item ; schema:isPartOf ?wiki ; schema:name ?t . FILTER(?wiki IN ({wikis})) }} }}"""):
            o = out[r["item"].rsplit("/", 1)[1]]
            if r.get("img") and not o["image"]:
                o["image"] = urllib.parse.unquote(r["img"].rsplit("/", 1)[1])
            if r.get("cat") and not o["category"]:
                o["category"] = r["cat"]
            if r.get("wiki"):
                o["articles"][r["wiki"].split("//")[1].split(".")[0]] = r["t"]
    return out


def article_pictures(lang, titles):
    """Article title -> the usable pictures it shows, on that language's Wikipedia."""
    out = {}
    params = {"generator": "images", "titles": "?in", "gimlimit": "max", "prop": "imageinfo", "iiprop": "size|mime|extmetadata",
              "iiextmetadatafilter": META, "iiextmetadatalanguage": "en"}
    for r in mwapi(f"{lang}.wikipedia.org", params, titles, OUT, batch=15, pages=2):
        p = file_row(r)
        if p:
            out.setdefault(r["in"], {})[p["f"]] = p
    return out


def category_pictures(cats):
    """Commons category -> the usable pictures directly in it (the first 60)."""
    out = {}
    params = {"generator": "categorymembers", "gcmtitle": "?in", "gcmtype": "file", "gcmlimit": "60", "prop": "imageinfo",
              "iiprop": "size|mime|extmetadata", "iiextmetadatafilter": META, "iiextmetadatalanguage": "en"}
    for r in mwapi("commons.wikimedia.org", params, ["Category:" + c for c in cats], OUT, batch=10, pages=0):
        p = file_row(r)
        if p:
            out.setdefault(r["in"].split(":", 1)[1], {})[p["f"]] = p
    return out


def file_pictures(names):
    """Commons file -> its picture (for the items' own images)."""
    out = {}
    params = {"generator": "allimages", "gaifrom": "?in", "gaito": "?in", "gailimit": "1", "prop": "imageinfo",
              "iiprop": "size|mime|extmetadata", "iiextmetadatafilter": META, "iiextmetadatalanguage": "en"}
    for r in mwapi("commons.wikimedia.org", params, [n.replace(" ", "_") for n in names], OUT, batch=25, pages=0):
        p = file_row(r)
        if p:
            out[p["f"]] = p
    return out


def index(manifest_path, out_path):
    say = lambda *a: print(*a, flush=True)
    E = entries(json.load(open(manifest_path)))
    say(f"{len(E)} labels")
    U = by_uberon(sorted({u for e in E.values() for u in e["uberon"]}))
    say(f"{len(U)} UBERON ids on Wikidata")
    for e in E.values():
        e["item"] = next((U[u] for u in sorted(e["uberon"]) if u in U), None); e["how"] = "uberon" if e["item"] else None
    # an item with no English article, and a label with no item: found by a search of English Wikipedia
    A = about(sorted({e["item"] for e in E.values() if e["item"]}))
    lost = [e for e in E.values() if not e["item"] or "en" not in A[e["item"]]["articles"]]
    say(f"searching English Wikipedia for {len(lost)}")
    S = search([e["label"] for e in lost])
    I = items_of(sorted(set(S.values())))
    for e in lost:
        t = S.get(plain(e["label"]))
        if t and t in I and (not e["item"]):
            e["item"], e["how"] = I[t], "search"
        elif t and t in I:
            e["also"] = I[t]          # the UBERON item has no English article: the search's too
    A.update(about(sorted({q for e in E.values() for q in (e["item"], e.get("also")) if q and q not in A})))
    say(f"{sum(1 for e in E.values() if e['item'])} of {len(E)} labels have an item")
    # the pictures: every language's article, the item's image, its Commons category
    P = {}
    for lang in LANGS:
        titles = sorted({a["articles"][lang] for a in A.values() if lang in a["articles"]})
        P[lang] = article_pictures(lang, titles)
        say(f"  {lang}: {len(titles)} articles, {sum(len(v) for v in P[lang].values())} usable pictures on them")
    cats = sorted({a["category"] for a in A.values() if a["category"]}
                  | {a["articles"]["en"] for a in A.values() if not a["category"] and "en" in a["articles"]})
    C = category_pictures(cats)
    say(f"  Commons: {len(cats)} categories, {sum(len(v) for v in C.values())} usable pictures in them")
    F = file_pictures(sorted({a["image"] for a in A.values() if a["image"]}))
    # one entry per structure, left and right together where they share an item
    groups = {}
    for e in sorted(E.values(), key=lambda e: e["label"]):
        g = groups.setdefault((plain(e["label"]), e["item"]), {
            "name": plain(e["label"]), "labels": [], "nodes": [], "uberon": set(), "tissue": e["tissue"],
            "system": e["system"], "part": e["part"], "item": e["item"], "how": e["how"], "also": e.get("also")})
        g["labels"].append(e["label"]); g["nodes"] += e["nodes"]; g["uberon"] |= e["uberon"]
    # a picture on the articles of too many structures is about none of them (a map of the brain's lobes aside)
    used = {}
    for g in groups.values():
        for q in {g["item"], g["also"]} - {None}:
            for lang in LANGS:
                for f in P[lang].get(A[q]["articles"].get(lang), {}):
                    used.setdefault(f, set()).add(g["name"])
    for g in groups.values():
        votes, pics = {}, {}
        qs = [q for q in (g["item"], g["also"]) if q]
        for q in qs:
            a = A[q]
            for lang in LANGS:
                for f, p in P[lang].get(a["articles"].get(lang), {}).items():
                    if len(used.get(f, ())) <= 40:
                        votes.setdefault(f, set()).add(lang); pics[f] = p
            if a["image"] in F:
                votes.setdefault(a["image"], set()).add("wikidata"); pics[a["image"]] = F[a["image"]]
        name_words = words(g["name"]) | {w for q in qs for w in words(A[q]["articles"].get("en"))}
        for q in qs:
            a = A[q]; cat = a["category"] or a["articles"].get("en")
            for f, p in C.get(cat, {}).items():
                if f not in pics and words(f + " " + (p.get("desc") or "")) & name_words:
                    votes.setdefault(f, set()).add("commons"); pics[f] = p
        rank = sorted(pics, key=lambda f: (-len(votes[f] - {"commons"}), not PLATE.search(f),
                                           {"pd": 0, "by": 1, "by-sa": 2}[pics[f]["t"]], f))
        g["images"] = [{**pics[f], "src": "+".join(sorted(votes[f]))} for f in rank[:36]]
        a = A.get(g["item"]) or {"articles": {}, "category": None}
        g["article"] = a["articles"].get("en") or (A[g["also"]]["articles"].get("en") if g["also"] else None)
        g["category"] = a["category"]
        g["uberon"] = sorted(g["uberon"])
    out = sorted(groups.values(), key=lambda g: (g["system"], g["part"], g["name"]))
    with open(out_path, "w") as fh:
        fh.write('{"about": "Reference images for the anatomy atlas, free to use commercially: looked at, never shipped '
                 'or traced. t: pd (public domain, CC0), by (CC BY), by-sa (CC BY-SA: share-alike). src: the Wikipedias '
                 'whose article on the structure shows it (en, de, fr, es, it, ja, ru), wikidata (its Wikidata image), '
                 'commons (its Commons category). Each file is at https://commons.wikimedia.org/wiki/File:<f>. Made by '
                 'tools/atlas_refs.py.",\n "structures": [\n')
        fh.write(",\n".join(json.dumps({k: v for k, v in g.items() if v not in (None, [], set())}, ensure_ascii=False,
                                       separators=(",", ":")) for g in out))
        fh.write("\n]}\n")
    n = [len(g["images"]) for g in out]
    say(f"wrote {len(out)} structures, {sum(n)} images; none for {sum(1 for x in n if x == 0)}, "
        f"under 5 for {sum(1 for x in n if x < 5)}, median {sorted(n)[len(n) // 2]}")


def commons_url(f):
    return "https://commons.wikimedia.org/wiki/File:" + urllib.parse.quote(f.replace(" ", "_"))


def pages(index_path, out_dir):
    S = json.load(open(index_path))["structures"]
    os.makedirs(out_dir, exist_ok=True)
    by = {}
    for s in S:
        by.setdefault(s["system"], []).append(s)
    lic = {"pd": "public domain", "by": "CC BY", "by-sa": "CC BY-SA, share-alike"}
    for grp, ss in sorted(by.items()):
        slug = re.sub(r"[^a-z0-9]+", "-", grp.lower()).strip("-")
        lines = [f"# {grp[:1].upper() + grp[1:]} system: reference images", "",
                 "Free to use commercially; looked at, never shipped or traced. Made by tools/atlas_refs.py from "
                 "docs/sciences/anatomy-references.json. Each picture's source: the Wikipedias whose article on the "
                 "structure shows it, its Wikidata image, or its Commons category.", ""]
        for s in ss:
            lines.append(f"## {s['name']}")
            meta = []
            if s.get("article"):
                meta.append(f"[Wikipedia: {s['article']}](https://en.wikipedia.org/wiki/{urllib.parse.quote(s['article'].replace(' ', '_'))})")
            if s.get("category"):
                meta.append(f"[Commons: {s['category']}](https://commons.wikimedia.org/wiki/Category:{urllib.parse.quote(s['category'].replace(' ', '_'))})")
            lines.append(" · ".join(meta + [f"{len(s.get('images', []))} images"]) + "  ")
            lines.append("In the atlas: " + ", ".join(sorted(set(n.split("/", 1)[1] for n in s["nodes"]))[:6]))
            lines.append("")
            for i in s.get("images", []):
                who = f", {i['by']}" if i.get("by") else ""
                lines.append(f"- [{i['f']}]({commons_url(i['f'])}): {i.get('lic') or lic[i['t']]}{who} ({i['src']})")
            lines.append("")
        with open(os.path.join(out_dir, f"{slug}.md"), "w") as fh:
            fh.write("\n".join(lines))
    # the contents: each system's page, how many structures it has and how many of them have no picture
    rows = ["# Anatomy atlas: reference images", "",
            "Pictures of every structure in the 3D anatomy atlas, free to use commercially (public domain, CC0, CC BY, "
            "and CC BY-SA, marked share-alike), to check the models against at every change: looked at, never shipped "
            "or traced. One page per body system; the index itself is docs/sciences/anatomy-references.json. Made by "
            "tools/atlas_refs.py.", "",
            "| System | Structures | Pictures | Without a picture |", "|---|---|---|---|"]
    for grp, ss in sorted(by.items()):
        slug = re.sub(r"[^a-z0-9]+", "-", grp.lower()).strip("-")
        rows.append(f"| [{grp[:1].upper() + grp[1:]}]({slug}.md) | {len(ss)} | {sum(len(x.get('images', [])) for x in ss)} "
                    f"| {sum(1 for x in ss if not x.get('images'))} |")
    with open(os.path.join(out_dir, "README.md"), "w") as fh:
        fh.write("\n".join(rows) + "\n")
    print(f"{len(by)} pages in {out_dir}")


def fetch(f, width=500):
    """A file's thumbnail, cached."""
    key = hashlib.sha1(f.encode()).hexdigest()
    path = os.path.join(CACHE, "img", key[:2], key)
    get("https://commons.wikimedia.org/wiki/Special:FilePath/" + urllib.parse.quote(f.replace(" ", "_")) + f"?width={width}",
        path=path)
    return path


def sheet(index_path, pattern, out_png, per=8):
    from PIL import Image, ImageDraw, ImageFont
    rx = re.compile(pattern, re.I)
    S = json.load(open(index_path))["structures"]
    pick, have = [], set()
    for s in S:
        if rx.search(s["name"]) or any(rx.search(x) for x in s["labels"] + s["nodes"]):
            for i in s.get("images", [])[:per]:
                if i["f"] not in have:
                    have.add(i["f"]); pick.append((s["name"], i))
    if not pick:
        sys.exit(f"nothing matches {pattern}")
    W, H, CAP, cols = 380, 340, 64, 5
    rows = (len(pick) + cols - 1) // cols
    im = Image.new("RGB", (cols * W, rows * (H + CAP)), "white")
    dr = ImageDraw.Draw(im)
    try:
        fb = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 13)
        fr = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11)
    except OSError:
        fb = fr = ImageFont.load_default()
    for k, (name, i) in enumerate(pick):
        x, y = (k % cols) * W, (k // cols) * (H + CAP)
        try:
            p = Image.open(fetch(i["f"])); p.load()
            if p.mode in ("RGBA", "LA", "P"):
                p = p.convert("RGBA"); bg = Image.new("RGBA", p.size, "white"); bg.alpha_composite(p); p = bg
            p = p.convert("RGB"); p.thumbnail((W - 8, H - 8))
            im.paste(p, (x + (W - p.width) // 2, y + (H - p.height) // 2))
        except Exception as ex:      # a file that will not open is shown as such; the rest of the sheet is still made
            dr.text((x + 10, y + H // 2), f"(could not open: {type(ex).__name__})", fill="gray", font=fr)
        dr.text((x + 6, y + H + 2), text(name, 46), fill="black", font=fb)
        dr.text((x + 6, y + H + 20), text(i["f"], 58), fill=(60, 60, 60), font=fr)
        lic = i.get("lic") or i["t"]
        dr.text((x + 6, y + H + 36), text(f"{lic} · {i.get('by') or 'unknown author'}", 58),
                fill=(150, 30, 30) if i["t"] == "by-sa" else (30, 90, 30), font=fr)
    im.save(out_png)
    print(f"{out_png}: {len(pick)} images")


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "index":
        index(*args)
    elif cmd == "pages":
        pages(*args)
    elif cmd == "sheet":
        sheet(args[0], args[1], args[2], int(args[3]) if len(args) > 3 else 8)
    else:
        sys.exit(__doc__)
