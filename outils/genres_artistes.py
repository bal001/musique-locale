#!/usr/bin/env python3
"""Fabrique ios/MusiqueLocale/Resources/genres-artistes.json : pays et styles (MusicBrainz) des artistes présents
dans les nouveautés Apple (fr, us, gb). L'app s'en sert au démarrage et complète elle-même les artistes nouveaux.
MusicBrainz demande au plus 1 requête par seconde. Usage : python3 outils/genres_artistes.py"""
import json, os, re, sys, time, unicodedata, urllib.parse, urllib.request

SORTIE = os.path.join(os.path.dirname(__file__), "..", "ios", "MusiqueLocale", "Resources", "genres-artistes.json")
AGENT = "MusiqueLocale/1.0 (https://github.com/bal001/musique-locale)"

def get(url):
    for essai in range(4):
        try:
            return json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": AGENT}), timeout=15))
        except Exception:
            time.sleep(2 + essai * 2)
    return None

def cle(nom):
    n = unicodedata.normalize("NFKD", nom.lower())
    return "".join(c for c in n if c.isalnum())

def principal(artistes):
    return re.split(r"\s*(?:,|&| feat\.? | ft\.? | x | X | et )\s*", artistes)[0].strip()

LIMITE = time.strftime("%Y-%m-%d", time.gmtime(time.time() - 42 * 86400))

def artistes_des_flux():
    """Artistes des sorties des 6 dernières semaines (les seules affichées dans Nouveautés)."""
    noms = []
    for code in ["fr", "us", "gb"]:
        for t in ["albums", "songs"]:
            d = get(f"https://rss.marketingtools.apple.com/api/v2/{code}/music/most-played/100/{t}.json")
            noms += [r["artistName"] for r in (d or {}).get("feed", {}).get("results", []) if r.get("releaseDate", "") >= LIMITE]
        for g in [18, 14, 7, 17, 15, 12, 21] + ([50000064] if code == "fr" else []):
            for t in ["topalbums", "topsongs"]:
                d = get(f"https://itunes.apple.com/{code}/rss/{t}/limit=100/genre={g}/json")
                noms += [e["im:artist"]["label"] for e in (d or {}).get("feed", {}).get("entry", []) if e.get("im:releaseDate", {}).get("label", "") >= LIMITE]
    vus, res = set(), []
    for n in noms:
        p = principal(n)
        if p and cle(p) not in vus:
            vus.add(cle(p)); res.append(p)
    return res

def fiche(nom):
    q = urllib.parse.quote(f'artist:"{nom}"')
    d = get(f"https://musicbrainz.org/ws/2/artist/?query={q}&limit=3&fmt=json") or {}
    for a in d.get("artists", []):
        if cle(a.get("name", "")) == cle(nom) or any(cle(x.get("name", "")) == cle(nom) for x in a.get("aliases", [])):
            tags = [t["name"] for t in sorted(a.get("tags", []), key=lambda t: -t.get("count", 0))][:8]
            return {"pays": a.get("country") or (a.get("area") or {}).get("iso-3166-1-codes", [None])[0], "styles": tags}
    return {"pays": None, "styles": []}

existant = json.load(open(SORTIE)) if os.path.exists(SORTIE) else {}
noms = artistes_des_flux()
print(len(noms), "artistes", file=sys.stderr)
for i, n in enumerate(noms):
    if cle(n) in existant: continue
    existant[cle(n)] = fiche(n)
    time.sleep(1.1)
    if i % 25 == 0:
        print(i, n, existant[cle(n)], file=sys.stderr)
        json.dump(existant, open(SORTIE, "w"), ensure_ascii=False, sort_keys=True)
json.dump(existant, open(SORTIE, "w"), ensure_ascii=False, sort_keys=True)
print("ok", len(existant), file=sys.stderr)
