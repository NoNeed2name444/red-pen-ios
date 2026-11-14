"""fetch_refs.py: look up and fetch public-domain reference plates (Gray's Anatomy, 1918) from Wikimedia Commons.
Usage: python3 -I fetch_refs.py <folder> <Commons file name> [...]     e.g. Gray188.png
Each plate is saved in the folder with a line in plates.tsv: file, description, licence, page.
Pictures are looked at for shape and proportion only; nothing is traced or imported."""
import json, re, sys, time, urllib.parse, urllib.request, os

UA = {"User-Agent": "stethoscore-anatomy-references/1.0 (reference lookup; contact via repository)"}


def get(url, tries=4):
    for k in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40) as r:
                return r.read()
        except Exception as e:  # the proxy or the site refused: wait and try again
            last = e
            time.sleep(2 * (k + 1))
    raise last


def main():
    folder, names = sys.argv[1], sys.argv[2:]
    os.makedirs(folder, exist_ok=True)
    for name in names:
        api = ("https://commons.wikimedia.org/w/api.php?action=query&format=json&prop=imageinfo"
               "&iiprop=url%7Cextmetadata&iiurlwidth=1000&titles=File:" + urllib.parse.quote(name))
        try:
            d = json.loads(get(api))
            page = next(iter(d["query"]["pages"].values()))
            ii = page["imageinfo"][0]
            m = ii.get("extmetadata", {})
            desc = re.sub(r"\s+", " ", re.sub("<[^>]+>", "", m.get("ImageDescription", {}).get("value", ""))).strip()
            lic = m.get("LicenseShortName", {}).get("value", "?")
            out = os.path.join(folder, name)
            if not os.path.exists(out):
                open(out, "wb").write(get(ii.get("thumburl") or ii["url"]))
            with open(os.path.join(folder, "plates.tsv"), "a") as f:
                f.write("\t".join([name, desc[:300], lic, ii.get("descriptionurl", "")]) + "\n")
            print(name, "|", desc[:120], "|", lic)
        except Exception as e:
            print(name, "FAILED", type(e).__name__, str(e)[:80])
        time.sleep(1.2)


main()
