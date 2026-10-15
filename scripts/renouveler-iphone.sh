#!/bin/zsh
# Usage : renouveler-iphone.sh <UDID de l'iPhone>
# Chaque nuit (launchd) : récupère les corrections publiées sur GitHub, refabrique l'app iPhone
# et la réinstalle sur l'iPhone par le Wi-Fi. Renouvelle aussi la signature gratuite de 7 jours.
# Journal : ~/Library/Logs/MusiqueLocale-renouvellement.log
set -u
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# Copie du projet hors de Documents : macOS refuse aux tâches de nuit l'accès à Documents.
RACINE="$HOME/Developer/musique-locale"
IPHONE="${1:?identifiant de l'iPhone (UDID) attendu}"
cd "$RACINE/ios/MusiqueLocale" || exit 1
echo "=== $(date '+%d/%m/%Y %H:%M') ==="

# 1. Corrections publiées sur GitHub (sans toucher aux changements locaux en cours).
git -C "$RACINE" pull --ff-only --quiet 2>&1 || echo "(pas de mise à jour récupérée)"

# 2. Fabrication signée avec l'identifiant Apple gratuit.
"$HOME/.local/xcodegen/bin/xcodegen" generate --quiet || exit 1
if ! xcodebuild -project MusiqueLocale.xcodeproj -scheme MusiqueLocale -destination "id=$IPHONE" \
     -derivedDataPath build -allowProvisioningUpdates build > /tmp/musiquelocale-fabrication.log 2>&1; then
  grep -E "error:" /tmp/musiquelocale-fabrication.log | tail -5
  echo "Fabrication impossible."
  exit 1
fi
echo "App fabriquée."

# 3. Installation par le Wi-Fi (jusqu'à 6 essais si l'iPhone n'est pas encore joignable).
for essai in 1 2 3 4 5 6; do
  if xcrun devicectl device install app --device "$IPHONE" build/Build/Products/Debug-iphoneos/MusiqueLocale.app >/dev/null 2>&1; then
    echo "App réinstallée (essai $essai)."
    exit 0
  fi
  sleep 300
done
echo "iPhone injoignable cette nuit."
exit 1
