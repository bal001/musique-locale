# Musique Locale (YouTube Musique Locale) — dossier de passation

Deux apps personnelles, pour le propriétaire et sa famille (pas de vente) :
1. **App Mac** (Electron) : sa musique locale **et** tout YouTube, à la façon de YouTube Music.
2. **App iPhone** (SwiftUI, `ios/`) : **la même expérience que l'app YouTube Music sur téléphone**, sans aucun
   serveur du propriétaire (le Mac peut être éteint). C'est le projet principal aujourd'hui.

Code, commentaires, interface et messages de commit en **français**. Détails propres à la machine du propriétaire
(iPhone, équipe Apple, emplacements, état en cours) : `CLAUDE.local.md` (non publié).

## Comment travailler avec le propriétaire

- Il veut que l'app iPhone soit **identique à YouTube Music** (ergonomie, écrans, comportements) et
  « que rien ne soit laissé au hasard ». Pour comparer, il accepte qu'on regarde son app YouTube Music officielle.
- **Tout vérifier soi-même avant d'annoncer** (tests `ios/Verification`, compilation, installation, capture
  d'écran). Être proactif : trouver les défauts avant lui.
- Il a donné son accord général (« fais tout, je donne mon accord ») ; seuls ses mots de passe, comptes et achats
  restent à lui. **Pas de leçons de morale** sur les conditions de YouTube : il connaît les risques (dire une
  limite une seule fois, en une phrase). Refusés et à ne pas proposer : vendre l'app, déguiser le dépôt pour
  échapper aux robots de détection.
- **Captures de son iPhone : une seule à la fois, quand il dit qu'il est dans l'app.** Jamais de captures en
  boucle (une capture en boucle a déjà enregistré ses messages privés).
- **Il ne veut aucune tâche de nuit, ni sur son Mac ni sur GitHub** (renouvellement launchd et vérification planifiée retirés à sa demande).
- Il dicte à l'oral : messages courts ; répondre simplement, étapes numérotées quand il doit toucher son iPhone.

## App iPhone (`ios/MusiqueLocale`)

**Lancer / tester**
```bash
cd ios/MusiqueLocale && xcodegen generate     # XcodeGen : le .xcodeproj n'est pas versionné
xcodebuild -project MusiqueLocale.xcodeproj -scheme MusiqueLocale -destination 'id=<UDID>' \
  -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> build/Build/Products/Debug-iphoneos/MusiqueLocale.app
xcrun devicectl device capture screenshot --device <UDID> --destination ecran.png   # voir son écran
cd ../Verification && swift run -c release    # 23 contrôles avec les vraies réponses de YouTube
```
iOS 26 minimum (iPhone du propriétaire en iOS 26.7). Swift 5, SwiftUI, Observation.

**Données (sans clé ni compte)**
- `Services/InnerTube.swift` : API interne de YouTube Music (client WEB_REMIX, hl fr / gl FR). La version du client
  est **lue chaque jour sur music.youtube.com** (cookie `SOCS=CAI` pour éviter la page de consentement) et relue
  dès qu'une requête est refusée (400/403). Pages : accueil `FEmusic_home` (+ puces d'humeur), explorer,
  `FEmusic_moods_and_genres`, artistes `UC…`, albums `MPREb…`, playlists `VL…`, recherche (puces = filtres),
  suggestions, `radio` (endpoint `next` avec `RDAMVM<id>`), `similaires` (`MPTR…`), paroles (`MPLY…`),
  classements par pays (`FEmusic_charts` + `formData.selectedValues`).
- `Services/AnalyseYTM.swift` : réponses → `PageYTM` / `Rangee` / `Carte` / `Titre`. Sans compte, l'accueil n'a
  que ~3 rangées : on complète avec Explorer et les recommandations personnelles.
- `Services/Nouveautes.swift` : nouveautés par pays = classements publics **Apple Music** (date de sortie réelle,
  6 dernières semaines, sans précommandes), retrouvées sur YouTube Music au toucher. Le flux Apple renvoie souvent
  502/504 : 4 essais + dernière liste valide gardée 3 jours.
- `Services/ExtracteurFlux.swift` : **extraction rapide d'abord** (`ExtracteurDirect`, ~0,5 s) = endpoint `player`
  avec le client **VISIONOS** + identifiant de visiteur (`InnerTube.visiteur()`, gardé 1 jour) : liens directs sans
  signature (son m4a, HLS, vidéo seule). Testé le 15/10/2026 : les clients IOS, ANDROID, ANDROID_VR, TV, MWEB
  sont bloqués (PO token). **Secours : YouTubeKit 0.4.9** (~4 s ; extraction locale puis service distant de l'auteur).
  `PrechargeurFlux` prépare à l'avance les titres suivants, les 1ers résultats et l'accueil (cache 5 h). Son = m4a ; clip = **HLS** (aucun mp4 combiné n'existe plus) ;
  clip téléchargé = vidéo seule H.264 ≤ 1080p + son, assemblés sur le téléphone sans réencodage.
- `Services/ChargeurImages.swift` : remplace AsyncImage (qui abandonnait au défilement → images manquantes).
- Paroles : LRCLIB (synchronisées) puis YouTube Music.
- `Services/VeilleSorties.swift` : sorties **datées** (annuaire iTunes : search musicArtist puis lookup albums,
  précommandes comprises) → « Du nouveau chez vos artistes » (21 derniers jours) et « À venir » (4 mois), pour les
  artistes du profil + suivis + 25 artistes du moment du pays ; 12 h de mémoire par artiste ; doublons retirés.
- `Services/TelechargeurMorceaux.swift` : téléchargements **par plages de 2 Mo, 4 à la fois** (un GET complet est
  bridé à ~25 Ko/s par YouTube : 2 min 30 par titre ; par morceaux : 0,2 s) ; 3 titres au plus en même temps.
- Téléchargements stockés **dans l'iPhone** (Application Support de l'app), jamais sur un serveur ni le Mac.

**Comportements voulus (calqués sur YouTube Music, étudiés sur son téléphone)**
- Onglets **Accueil · Samples · Rechercher · Bibliothèque** ; logo à nous (citron #D1FE17 sur noir), pas celui de YouTube.
- Accueil : puces d'humeur, « Mixés pour vous » (Mix [artiste] dès la 1re écoute ; « Mon supermix » seulement
  quand le profil de goûts est suffisant), « Parce que vous avez écouté », rangées YouTube Music, nouveautés du pays
  (France / États-Unis / Royaume-Uni / International), « Dans le style de », « Favoris à redécouvrir ».
  **« Accès rapide » retiré** (doublon de « Sélection rapide »). **Pas de podcasts ni d'épisodes.**
- Recherche : toucher un titre lance **sa radio** (titres du même style), jamais la liste des résultats ;
  « Recherches récentes » = résultats ouverts + requêtes (↖, suppression, tout effacer) ; tuiles
  Nouveautés / Charts / Humeurs et genres.
- Recommandations (`Lecteur.prolongerSiBesoin`, `Historique.Gout`) : radio YouTube Music filtrée par les goûts —
  jamais un titre 👎 ou zappé (< 30 s), ni écouté récemment, ni autre version du même morceau (slowed, remix…),
  ni un artiste zappé bien plus qu'écouté ; graine = dernier titre écouté jusqu'au bout ou aimé. Profil par
  artiste (écoutes complètes, > 1 min, zaps, J'aime, demi-vie 14 jours), gardé sur le téléphone.
- Lecteur : bascule 🎧/▶ (titre/clip), AirPlay, ⋮, titre « › » vers l'artiste, bulles 👍|👎 · Enregistrer ·
  Télécharger · Partager, aléatoire, répéter, À SUIVRE · PAROLES · SIMILAIRES ; file réordonnable, « Lecture à
  partir de », interrupteur Lecture automatique, mise en veille. Mini-lecteur avec ⏮ ▶ ⏭.
- Menu ⋮ en feuille : Lire ensuite · Enregistrer dans une playlist · Partager, puis Démarrer le mix, file
  d'attente, Télécharger (son / clip), album, artiste, Supprimer la file, Mise en veille, Je n'aime pas.
- « Tout télécharger » : albums, playlists YouTube Music, playlists perso, Musique J'aime, Historique.
- Accueil rechargé tout seul au retour dans l'app après 30 min (pas de tâche de fond).
- Bibliothèque : puces Téléchargés · Playlists · Titres · Albums · Artistes, tri, grille/liste, « Musique J'aime »,
  playlists personnelles (« + Nouveau »), albums/playlists enregistrés, artistes suivis, historique.
- Samples : clips plein écran à la verticale, passage de 30 s, **3 clips préparés à l'avance** (démarrage instantané).
- Son : pause nette quand une autre app prend le son ou le micro (vocal Snapchat, appel), **reprise automatique**
  ensuite si la musique jouait ; pause au débranchement du casque. Reprise de la file au lancement.

**Erreurs déjà commises (à ne pas refaire)** : accueil reconstruit à chaque écoute (lancer un mix faisait sauter la page) ; recherche qui lisait la liste des résultats au lieu de la radio ;
images vides (AsyncImage) ; tuiles en NavigationLink dans une List (flèches parasites) ; NavigationLink dans les feuilles du lecteur (Similaires grisés) → toujours naviguer par `Navigateur.ouvrir` ; « Accès rapide » avec
un grand vide ; nouveautés « anciennes » (dernier album de l'année ≠ récent) ; version du client figée ;
tests dépendants de la France (le cloud GitHub est aux États-Unis).

## Distribution (sans le Mac du propriétaire)

- Dépôt **public** github.com/bal001/musique-locale (choisi pour les minutes de fabrication illimitées).
  `.github/workflows/app-iphone.yml` : à chaque changement de `ios/MusiqueLocale`, fabrique l'IPA **non signée**
  (macos-26) et publie une version + `source.json` (format AltStore v2, `.github/source.py`) :
  `https://github.com/bal001/musique-locale/releases/latest/download/source.json`.
- `.github/workflows/verification.yml` : 26 contrôles (la lecture rapide n'est qu'un avertissement sur GitHub : YouTube y traite les serveurs comme des robots ; ne pas chercher à contourner — refusé) à chaque changement du code et à la demande (pas de vérification de nuit : le propriétaire n'en veut pas) ; échec = e-mail.
- Installation prévue : **SideStore** sur les iPhone (le sien, celui de son petit frère), qui signe et renouvelle
  sur le téléphone et lit la source ci-dessus. Voir l'état en cours dans `CLAUDE.local.md`.
- Alternatives examinées : AltStore classique / Sideloadly (ordinateur), LiveContainer (dépend de SideStore),
  TrollStore (vieux iOS), AltStore PAL et TestFlight (compte Apple 99 €/an, refusé pour l'instant), services de
  certificats (payants, révocations : déconseillés).
- Projet SoundCloud : reporté (« plus tard, si je le décide »).

## App Mac (Electron)

```bash
export PATH="$HOME/.local/node/bin:$PATH"
npm run build && node server/index.mjs   # http://localhost:4317 (l'app Mac charge server/ de ce dossier)
npm run app                               # (ré)installe ~/Applications/YouTube Musique Locale.app
```
- `server/` (Express) : `youtube.mjs` (recherche sans clé via yt-dlp : YouTube Music + ytsearch + oEmbed),
  `scanner.mjs` (musique locale, clips .mp4, pochette « Titre.jpg »), `paroles.mjs`, `telechargements.mjs`
  (yt-dlp + ffmpeg de `outils/`, non versionnés), `stockage.mjs` (`donnees/etat.json`, non versionné).
- `src/` (React + TS + Vite + zustand) : `store/moteur.ts` (lecture locale par `<video>` + IFrame YouTube),
  `store/telechargements.ts` (version téléchargée lue à la place de YouTube).
- Fait : recherche sans clé, Titre/Vidéo/Paroles, téléchargements hors ligne, effacement des historiques
  (recherches et « Réécouter »), affichage mobile. Abandonné : version iPhone servie par le Mac en Wi-Fi/HTTPS
  (le propriétaire ne veut pas dépendre du Mac) — conservée sur la branche locale `essai-iphone-via-mac`.
- L'app Mac sert aussi une version web pour l'iPhone sur le Wi-Fi (`/api/iphone`, QR code dans Réglages,
  réseau local seulement) : précédente étape, gardée mais plus mise en avant.
- Les consignes de l'ancienne IA (« API officielles seulement ») ont été jetées à sa demande.
