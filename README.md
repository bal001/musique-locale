# YouTube Musique Locale

Un lecteur de musique **local** qui reproduit le fonctionnement de YouTube Music (accueil, explorer,
bibliothèque, lecteur avec file d'attente / paroles / similaires, recherche avec suggestions,
raccourcis clavier), habillé avec la direction artistique de **Higgsfield**, et qui lit **vos propres fichiers audio**.

Le comportement a été relevé sur la vraie application avec l'outil de rétro-ingénierie
[REA](https://github.com/morluto/rea) : voir [ANALYSE-REA.md](ANALYSE-REA.md).
Projet personnel, à usage local uniquement.

## Démarrer

```bash
export PATH="$HOME/.local/node/bin:$PATH"
npm start
```

Puis ouvrez **http://localhost:4317**. Au premier lancement, une petite bibliothèque de démonstration
(musique synthétisée, sans droits) est générée dans `musique/Démo`.

Pour développer avec rechargement à chaud : `npm run dev` (interface sur http://localhost:5317).

## Ajouter votre musique

- Déposez vos fichiers (MP3, M4A, AAC, FLAC, OGG, Opus, WAV, WebM) dans `musique/`,
  ou ajoutez un dossier (par ex. `~/Music`) dans **Réglages**.
- Titre, artiste, album, année, genre et pochette sont lus dans les tags. Une image `cover.jpg` ou `folder.png` dans le dossier sert aussi de pochette.
- Paroles synchronisées : un fichier `.lrc` portant le même nom que le fichier audio.

## Fonctionnalités

- Accueil : Réécouter, Sélection rapide, Ajouts récents, Mix par genre, Vos artistes, filtres par genre
- Explorer : Nouveautés, Classement (d'après vos écoutes), Humeurs et genres
- Bibliothèque : playlists, titres, albums, artistes (tri, filtres) ; Historique ; Titres J'aime
- Lecteur : file d'attente glisser-déposer, aléatoire, répétition (tout / un), lecture automatique,
  paroles synchronisées, titres similaires, reprise après rechargement
- Recherche insensible aux accents, suggestions en deux sections, carte « meilleur résultat »
- J'aime / Je n'aime pas, playlists (créer, modifier, supprimer, enregistrer la file d'attente)
- Touches multimédia du Mac et Centre de contrôle (Media Session)
- Tous les raccourcis de YouTube Music (appuyez sur `?`)
- Installable comme application (PWA), comme l'original

## Pour les IA

Voir [AGENTS.md](AGENTS.md) : architecture, API et conventions.
