# YouTube Musique Locale

App Mac personnelle (Electron) qui ressemble à YouTube Music : ta musique locale **et** tout YouTube.

## Ce que veut le propriétaire

- Chercher **n'importe quel artiste, titre ou album sur YouTube, sans clé API**, voir les résultats et les écouter
  dans l'app, comme la recherche YouTube de CutLocal.
- L'écoute passe par le lecteur YouTube intégré. Comme YouTube Music : choix Titre / Vidéo / Paroles,
  paroles en ligne (LRCLIB synchronisées, sinon YouTube Music), téléchargement audio ou clip pour le hors-ligne
  (`musique/Téléchargements`, lu à la place de YouTube quand il existe), historique des recherches effaçable.
- Code, commentaires et interface en français.

## Lancer

```bash
export PATH="$HOME/.local/node/bin:$PATH"
npm run build && node server/index.mjs   # http://localhost:4317
npm run app                               # (ré)installe ~/Applications/YouTube Musique Locale.app
```

## Architecture

- `server/` : Node + Express. `index.mjs` (routes `/api/*`), `youtube.mjs` (recherche YouTube),
  `scanner.mjs` (musique locale), `stockage.mjs` (état → `donnees/etat.json`), `paroles.mjs` (paroles en ligne),
  `telechargements.mjs` (yt-dlp + ffmpeg dans `outils/`, non versionnés).
- `src/` : React + TypeScript + Vite + zustand. `store/moteur.ts` (lecture locale et YouTube),
  `store/lecteur.ts` (file d'attente), `pages/`, `components/`.
- `electron/principal.mjs` : l'app Mac.

## App iPhone (`ios/`)

- `ios/MusiqueLocale` : app SwiftUI à l'image de YouTube Music, sans serveur (InnerTube sans clé, YouTubeKit,
  recommandations « radio » affinées par les goûts, nouveautés par pays via les classements Apple Music).
  Projet XcodeGen (`project.yml`) ; le `.xcodeproj` n'est pas versionné.
- `ios/Verification` : vérification complète avec les vraies réponses de YouTube (`swift run -c release`).
- `.github/workflows/app-iphone.yml` : fabrique l'app (non signée) à chaque changement et publie une version
  avec `source.json` pour SideStore (`https://github.com/bal001/musique-locale/releases/latest/download/source.json`).
- `.github/workflows/verification.yml` : vérification chaque nuit ; un échec envoie un e-mail.
