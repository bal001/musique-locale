"""Source SideStore / AltStore (format v2) : la liste que SideStore lit pour installer et mettre à jour l'app."""
import json, os, sys
from datetime import datetime, timezone

depot, version, build, ipa = sys.argv[1:5]
proprietaire = depot.split("/")[0]
base = f"https://github.com/{depot}"
print(json.dumps({
    "name": "Musique Locale",
    "identifier": f"io.github.{proprietaire.lower()}.musiquelocale",
    "sourceURL": f"{base}/releases/latest/download/source.json",
    "iconURL": f"https://raw.githubusercontent.com/{depot}/main/public/icone-512.png",
    "tintColor": "D1FE17",
    "apps": [{
        "name": "Musique Locale",
        "bundleIdentifier": "local.alec.musiquelocale",
        "developerName": proprietaire,
        "subtitle": "Toute la musique, comme YouTube Music",
        "localizedDescription": "Recherche, radio, recommandations, paroles, clips et téléchargements hors ligne.",
        "iconURL": f"https://raw.githubusercontent.com/{depot}/main/public/icone-512.png",
        "tintColor": "D1FE17",
        "category": "entertainment",
        "versions": [{
            "version": version,
            "buildVersion": build,
            "date": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "size": os.path.getsize(ipa),
            "downloadURL": f"{base}/releases/download/v{version}/MusiqueLocale.ipa",
            "minOSVersion": "26.0",
        }],
        "appPermissions": {"entitlements": [], "privacy": {}},
    }],
    "news": [],
}, ensure_ascii=False, indent=2))
