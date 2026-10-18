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

LIMITE = time.strftime("%Y-%m-%d", time.gmtime(time.time() - 122 * 86400))

def artistes_des_flux():
    """Artistes des nouveautés (méthode « Release Radar » de l'app) : artistes les plus écoutés d'Apple Music
    et toutes leurs sorties des 2 derniers mois."""
    noms = []
    for code in ["fr", "us", "gb"]:
        ids = []
        for t in ["albums", "songs"]:
            d = get(f"https://rss.marketingtools.apple.com/api/v2/{code}/music/most-played/100/{t}.json")
            for r in (d or {}).get("feed", {}).get("results", []):
                noms.append(r["artistName"])
                if r.get("artistId") and r["artistId"] not in ids: ids.append(r["artistId"])
        for i in range(0, len(ids), 40):
            d = get(f"https://itunes.apple.com/lookup?id={','.join(ids[i:i+40])}&entity=album&sort=recent&limit=8&country={code}")
            noms += [r["artistName"] for r in (d or {}).get("results", [])
                     if r.get("wrapperType") == "collection" and r.get("releaseDate", "") >= LIMITE]
    vus, res = set(), []
    for n in noms:
        p = principal(n)
        if p and cle(p) not in vus:
            vus.add(cle(p)); res.append(p)
    # Comme l'app : les artistes similaires (Deezer) des 100 premiers artistes de chaque pays.
    for p in list(res)[:300]:
        d = get("https://api.deezer.com/search/artist?q=" + urllib.parse.quote(p) + "&limit=10") or {}
        meme = [a for a in d.get("data", []) if cle(a.get("name", "")) == cle(p)]
        if not meme: continue
        a = max(meme, key=lambda a: a.get("nb_fan", 0))
        rel = get(f"https://api.deezer.com/artist/{a['id']}/related?limit=12") or {}
        for r in rel.get("data", []):
            if cle(r["name"]) not in vus:
                vus.add(cle(r["name"])); res.append(r["name"])
        time.sleep(0.15)
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
