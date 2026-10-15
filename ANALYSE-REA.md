# Analyse de YouTube Music avec REA

Outil : [REA — Reverse Engineer Anything](https://github.com/morluto/rea), CLI `rea-agents` 6.5.0.
Cible : l'application YouTube Music du Mac. C'est une **PWA installée par Brave**
(`~/Applications/Brave Browser Apps.localized/YouTube Music.app`, simple lanceur de 824 Ko qui ouvre
`https://music.youtube.com/?source=pwa`). Tout le code de l'app est donc celui du site web.

Méthode : Brave sans interface, avec un profil vierge (sans compte), piloté par le protocole Chrome DevTools.
Cookies refusés (« Tout refuser »). Les preuves brutes sont dans `analyse-rea/`.

## Commandes REA utilisées

| Commande | Ce qu'elle a apporté |
|---|---|
| `rea list-browser-targets` | repérage de la page (et de la page de consentement) |
| `rea inspect-web-page --include-accessibility-text --include-script-sources --include-storage-keys` | structure de l'accueil : 5 734 nœuds DOM, scripts (`music_polymer`, `player_es6/base.js`…) → `accueil-inspect.json` |
| `rea capture-web-screenshot` | captures de l'accueil, du lecteur, d'un album, de la recherche, d'Explorer et de la Bibliothèque → `captures/` |
| `rea observe-web-session` | parcours accueil → album → lecture (navigations internes, requêtes bloquées) → `session-navigation.json` |
| `rea inspect-web-page --include-json-body-shapes` | forme des réponses de `youtubei/v1/music/get_search_suggestions` pendant la saisie → `suggestions-recherche-inspect.json` |

Limite constatée : `inspect-web-page` s'arrête dès que l'URL change (`target_changed`, REA refuse de mélanger
deux pages). Les écrans ont donc été capturés après chaque navigation.

## Ce qui a été relevé, et comment c'est reproduit

| Observation sur YouTube Music | Reproduction locale |
|---|---|
| Disposition : barre du haut 64 px, guide 240 px (Accueil / Explorer / Bibliothèque), recherche ~480 px | `BarreHaut`, `BarreLaterale`, grille de `.app` |
| Accueil : puces d'humeur, étagères horizontales avec flèches ‹ › | `Accueil`, `Etagere` (puces = genres de vos fichiers) |
| Lecteur : onglets À SUIVRE / PAROLES / SIMILAIRES, « Lecture à partir de… », bouton Enregistrer, interrupteur Lecture automatique | `PageLecteur` |
| Barre de lecture : infos à gauche, aléatoire / précédent / lecture / suivant / répéter au centre, temps + J'aime / Je n'aime pas + volume + menu à droite, progression sur le bord haut | `BarreLecture` |
| Album : colonne pochette + actions à gauche, liste numérotée avec nombre de lectures, « Sorties pour vous » | `Collection.tsx` (« Autres sorties de… ») |
| Recherche : puces de filtre, carte « meilleur résultat » teintée avec Aléatoire / Mix et 3 titres | `Recherche.tsx` |
| Suggestions : l'API renvoie **2 sections** (`searchSuggestionsSectionRenderer`) : complétions textuelles, puis résultats enrichis (`musicResponsiveListItemRenderer`) | `utils/recherche.ts` + liste déroulante de `BarreHaut` |
| Explorer : Nouveautés / Charts / Humeurs et genres, tuiles de genre à bordure colorée | `Explorer.tsx` |
| Dialogue `?` : liste complète des raccourcis clavier | `useRaccourcis.ts` (identiques) → `raccourcis-clavier.txt` |
| L'interface est pilotée par le serveur (« renderers » JSON) | ici, API JSON simple et rendu côté client |

## Ce qui n'a volontairement pas été reproduit

- La lecture du catalogue YouTube : extraction ou déchiffrement des flux et signatures du lecteur `base.js`.
- Les publicités, les restrictions Premium, la connexion Google.
- Le logo, le nom de marque affiché et le style visuel de YouTube : l'habillage suit Higgsfield.
