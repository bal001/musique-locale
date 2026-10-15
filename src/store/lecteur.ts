// Store du lecteur : pilote le moteur (fichiers locaux ou lecteur YouTube officiel, voir moteur.ts).
// Reproduit le comportement observé sur YouTube Music : file d'attente "À suivre",
// aléatoire, répétition (aucune / tout / un), lecture automatique de titres similaires,
// reprise de la lecture au rechargement et intégration aux touches multimédia du Mac.
import { create } from 'zustand';
import { api, urlPochette } from '../api';
import type { Repetition, SourceLecture, Titre } from '../types';
import { useBibliotheque } from './bibliotheque';
import { annoncer, notifier } from './interface';
import { titresSimilaires } from '../utils/similaires';
import { moteur, brancher } from './moteur';
import { titreJoue } from './telechargements';

export type OngletLecteur = 'suivre' | 'paroles' | 'similaires';
export type ModeAffichage = 'titre' | 'video' | 'paroles';

interface EtatLecteur {
  file: string[];               // ordre de lecture actuel
  fileOriginale: string[] | null; // ordre avant activation de l'aléatoire
  index: number;
  source: SourceLecture | null;
  ajoutsAuto: number;           // nb de titres ajoutés par la lecture automatique (en fin de file)
  enLecture: boolean;
  chargement: boolean;
  aleatoire: boolean;
  repetition: Repetition;
  volume: number;               // 0..1
  muet: boolean;
  temps: number;
  idLu: string | null; // titre réellement chargé (la version téléchargée d'un titre YouTube, par exemple)
  duree: number;
  pageOuverte: boolean;
  onglet: OngletLecteur;
  modeVideo: ModeAffichage; // sélecteur « Titre / Vidéo / Paroles » du lecteur développé
  choisirModeVideo: (m: ModeAffichage) => void;

  lire: (ids: string[], index?: number, source?: SourceLecture | null, options?: { melanger?: boolean }) => void;
  lireEnsuite: (ids: string[]) => void;
  ajouterALaFile: (ids: string[]) => void;
  retirerDeLaFile: (index: number) => void;
  deplacerDansLaFile: (de: number, vers: number) => void;
  allerA: (index: number) => void;
  rechargerCourant: () => void;
  basculerLecture: () => void;
  suivant: (auto?: boolean) => void;
  precedent: () => void;
  chercher: (secondes: number) => void;
  avancer: (delta: number) => void;
  basculerAleatoire: () => void;
  basculerRepetition: () => void;
  regler: (volume: number) => void;
  basculerMuet: () => void;
  ouvrirPage: (ouverte?: boolean, onglet?: OngletLecteur) => void;
  choisirOnglet: (o: OngletLecteur) => void;
}

const CLE_STOCKAGE = 'yml-lecteur';
const melanger = <T,>(liste: T[]) => {
  const l = [...liste];
  for (let i = l.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [l[i], l[j]] = [l[j], l[i]];
  }
  return l;
};

function lireSauvegarde(): Partial<EtatLecteur> {
  try {
    return JSON.parse(localStorage.getItem(CLE_STOCKAGE) || '{}');
  } catch {
    return {};
  }
}

const sauvegarde = lireSauvegarde();

export const useLecteur = create<EtatLecteur>((set, get) => {
  // Charge le titre courant dans le moteur.
  const charger = (lancer: boolean, depart = 0) => {
    const { file, index } = get();
    const t = titreJoue(useBibliotheque.getState().titres[file[index]]);
    if (!t) return;
    dejaCompte = false;
    set({ temps: depart, duree: t.duree || 0, idLu: t.id });
    moteur.charger(t, depart, lancer);
    majMediaSession();
  };

  return {
    file: sauvegarde.file ?? [],
    fileOriginale: sauvegarde.fileOriginale ?? null,
    index: sauvegarde.index ?? 0,
    source: sauvegarde.source ?? null,
    ajoutsAuto: 0,
    enLecture: false,
    chargement: false,
    aleatoire: sauvegarde.aleatoire ?? false,
    repetition: sauvegarde.repetition ?? 'aucune',
    volume: sauvegarde.volume ?? 1,
    muet: sauvegarde.muet ?? false,
    temps: sauvegarde.temps ?? 0,
    idLu: null,
    duree: 0,
    pageOuverte: false,
    onglet: 'suivre',
    modeVideo: sauvegarde.modeVideo ?? 'video',
    choisirModeVideo(modeVideo) {
      set({ modeVideo });
      annoncer({ titre: 'Mode titre : pochette en grand', video: 'Mode vidéo : clip en grand', paroles: 'Mode paroles : paroles en grand' }[modeVideo]);
    },

    lire(ids, index = 0, source = null, options = {}) {
      if (!ids.length) return;
      let file = [...ids];
      let i = index;
      const aleatoire = options.melanger ?? get().aleatoire;
      let fileOriginale: string[] | null = null;
      if (aleatoire) {
        fileOriginale = file;
        const premier = options.melanger ? file[Math.floor(Math.random() * file.length)] : file[index];
        file = [premier, ...melanger(file.filter((_, k) => k !== file.indexOf(premier)))];
        i = 0;
      }
      set({ file, index: i, fileOriginale, aleatoire, source, ajoutsAuto: 0 });
      charger(true);
    },

    lireEnsuite(ids) {
      const { file, index } = get();
      if (!file.length) return get().lire(ids);
      const nouvelle = [...file.slice(0, index + 1), ...ids, ...file.slice(index + 1)];
      set({ file: nouvelle });
      notifier(ids.length > 1 ? `${ids.length} titres seront lus ensuite` : 'Ce titre sera lu ensuite');
    },

    ajouterALaFile(ids) {
      const { file, ajoutsAuto } = get();
      if (!file.length) return get().lire(ids);
      // Inséré avant les suggestions de la lecture automatique.
      const coupe = file.length - ajoutsAuto;
      set({ file: [...file.slice(0, coupe), ...ids, ...file.slice(coupe)] });
      notifier(ids.length > 1 ? `${ids.length} titres ajoutés à la file d'attente` : "Ajouté à la file d'attente");
    },

    retirerDeLaFile(i) {
      const { file, index, ajoutsAuto } = get();
      if (i === index) return;
      set({
        file: file.filter((_, k) => k !== i),
        index: i < index ? index - 1 : index,
        ajoutsAuto: i >= file.length - ajoutsAuto ? ajoutsAuto - 1 : ajoutsAuto,
      });
    },

    deplacerDansLaFile(de, vers) {
      const { file, index } = get();
      if (de === vers) return;
      const f = [...file];
      const [x] = f.splice(de, 1);
      f.splice(vers, 0, x);
      let i = index;
      if (de === index) i = vers;
      else if (de < index && vers >= index) i--;
      else if (de > index && vers <= index) i++;
      set({ file: f, index: i });
    },

    allerA(i) {
      set({ index: i });
      charger(true);
    },

    // Recharge le titre courant au même endroit (par ex. son téléchargement vient d'être supprimé).
    rechargerCourant() {
      const enCours = !moteur.enPause();
      const depart = moteur.temps();
      moteur.pause();
      charger(enCours, depart);
    },

    basculerLecture() {
      if (!get().file.length) {
        const { listeTitres } = useBibliotheque.getState();
        if (listeTitres.length) get().lire(listeTitres.map((t) => t.id), 0, { libelle: 'Tous les titres' }, { melanger: true });
        return;
      }
      if (!moteur.estCharge()) charger(true, get().temps);
      else if (moteur.enPause()) moteur.lire();
      else moteur.pause();
    },

    suivant(auto = false) {
      const { file, index, repetition, ajoutsAuto } = get();
      if (auto && repetition === 'un') {
        moteur.chercher(0);
        moteur.lire();
        return;
      }
      if (index < file.length - 1) {
        set({ index: index + 1 });
        return charger(true);
      }
      if (repetition === 'tout') {
        set({ index: 0 });
        return charger(true);
      }
      // Lecture automatique : on prolonge la file avec des titres similaires.
      if (useBibliotheque.getState().utilisateur.reglages.lectureAuto) {
        const suggestions = titresSimilaires(file[index], file, 10).map((t) => t.id);
        if (suggestions.length) {
          set({ file: [...file, ...suggestions], index: index + 1, ajoutsAuto: ajoutsAuto + suggestions.length });
          return charger(true);
        }
      }
      moteur.pause();
      moteur.chercher(0);
    },

    precedent() {
      const { index } = get();
      // Comme YouTube Music : au-delà de 3 s, on revient au début du titre.
      if (moteur.temps() > 3 || index === 0) {
        moteur.chercher(0);
        return;
      }
      set({ index: index - 1 });
      charger(true);
    },

    chercher(s) {
      const d = moteur.duree() || get().duree;
      const cible = Math.max(0, Math.min(d || 0, s));
      moteur.chercher(cible);
      set({ temps: cible });
    },

    avancer(delta) {
      get().chercher(moteur.temps() + delta);
    },

    basculerAleatoire() {
      const { aleatoire, file, index, fileOriginale } = get();
      const courant = file[index];
      if (!aleatoire) {
        const reste = melanger(file.filter((_, k) => k !== index));
        set({ aleatoire: true, fileOriginale: file, file: courant ? [courant, ...reste] : reste, index: 0 });
        notifier('Lecture aléatoire activée');
      } else {
        const origine = fileOriginale && fileOriginale.length === file.length ? fileOriginale : file;
        set({ aleatoire: false, fileOriginale: null, file: origine, index: Math.max(0, origine.indexOf(courant)) });
        notifier('Lecture aléatoire désactivée');
      }
    },

    basculerRepetition() {
      const ordre: Repetition[] = ['aucune', 'tout', 'un'];
      const repetition = ordre[(ordre.indexOf(get().repetition) + 1) % 3];
      set({ repetition });
      notifier({ aucune: 'Répétition désactivée', tout: 'Répéter tous les titres', un: 'Répéter le titre' }[repetition]);
    },

    regler(volume) {
      const v = Math.max(0, Math.min(1, volume));
      const muet = v === 0 ? get().muet : false;
      set({ volume: v, muet });
      moteur.regler(v, muet);
    },

    basculerMuet() {
      const muet = !get().muet;
      set({ muet });
      moteur.regler(get().volume, muet);
    },

    ouvrirPage(ouverte, onglet) {
      set((s) => ({ pageOuverte: ouverte ?? !s.pageOuverte, onglet: onglet ?? s.onglet }));
    },

    choisirOnglet(onglet) {
      set({ onglet, pageOuverte: true });
    },
  };
});

export const titreCourant = (): Titre | undefined => {
  const { file, index } = useLecteur.getState();
  return useBibliotheque.getState().titres[file[index]];
};

// --- Évènements du moteur ------------------------------------------------------

let dejaCompte = false;
moteur.regler(useLecteur.getState().volume, useLecteur.getState().muet);

brancher({
  lecture: () => useLecteur.setState({ enLecture: true }),
  pause: () => useLecteur.setState({ enLecture: false }),
  chargement: (chargement) => useLecteur.setState({ chargement }),
  duree: (d) => {
    if (!d || !Number.isFinite(d)) return;
    useLecteur.setState({ duree: d });
    // Les vidéos ajoutées par lien (sans clé API) n'ont pas encore de durée connue.
    const t = titreCourant();
    if (t?.source === 'youtube' && !t.duree) {
      useBibliotheque.getState().integrerYoutube([{ ...t, duree: Math.round(d) }]);
      api.youtubeDuree(t.id, d).catch(() => {});
    }
  },
  fin: () => useLecteur.getState().suivant(true),
  erreur: (message) => {
    notifier(`${message}, passage au suivant`);
    setTimeout(() => useLecteur.getState().suivant(true), 1200);
  },
  temps: (temps, duree) => {
    useLecteur.setState({ temps });
    // Une lecture compte dans l'historique après 10 s (ou la moitié d'un titre très court).
    if (!dejaCompte && temps >= Math.min(10, (duree || 20) / 2)) {
      dejaCompte = true;
      const t = titreCourant();
      if (t) useBibliotheque.getState().enregistrerLecture(t.id);
    }
    if ('mediaSession' in navigator && duree && Number.isFinite(duree)) {
      try {
        navigator.mediaSession.setPositionState({ duration: duree, position: Math.min(temps, duree), playbackRate: 1 });
      } catch {}
    }
  },
});

// --- Touches multimédia / Centre de contrôle macOS ----------------------------

let derniereAnnonce = '';
function majMediaSession() {
  const t = titreCourant();
  if (t && t.id !== derniereAnnonce) {
    derniereAnnonce = t.id;
    annoncer(`Lecture : ${t.titre}, de ${t.artiste}`);
  }
  if (!('mediaSession' in navigator)) return;
  if (!t) return;
  const pochette = urlPochette(t.pochette);
  navigator.mediaSession.metadata = new MediaMetadata({
    title: t.titre,
    artist: t.artiste,
    album: t.album,
    artwork: pochette ? [{ src: new URL(pochette, location.href).href, sizes: '512x512' }] : [],
  });
  document.title = `${t.titre} - ${t.artiste} · YouTube Musique Locale`;
}

if ('mediaSession' in navigator) {
  const l = () => useLecteur.getState();
  const actions: [MediaSessionAction, MediaSessionActionHandler][] = [
    ['play', () => l().basculerLecture()],
    ['pause', () => moteur.pause()],
    ['previoustrack', () => l().precedent()],
    ['nexttrack', () => l().suivant()],
    ['seekbackward', (d) => l().avancer(-(d.seekOffset || 10))],
    ['seekforward', (d) => l().avancer(d.seekOffset || 10)],
    ['seekto', (d) => d.seekTime != null && l().chercher(d.seekTime)],
  ];
  for (const [action, gestion] of actions) {
    try {
      navigator.mediaSession.setActionHandler(action, gestion);
    } catch {}
  }
}

// Sauvegarde de la session de lecture pour la reprendre au rechargement.
// Limitée à une écriture par seconde (le temps de lecture change ~4 fois par seconde).
let sauvegardePrevue = false;
useLecteur.subscribe(() => {
  if (sauvegardePrevue) return;
  sauvegardePrevue = true;
  window.setTimeout(() => {
    sauvegardePrevue = false;
    try {
      const { file, fileOriginale, index, source, aleatoire, repetition, volume, muet, temps, modeVideo } = useLecteur.getState();
      localStorage.setItem(CLE_STOCKAGE, JSON.stringify({ file, fileOriginale, index, source, aleatoire, repetition, volume, muet, temps, modeVideo }));
    } catch {}
  }, 1000);
});

// Au démarrage : on prépare le titre sauvegardé sans le lancer.
export function restaurerSession() {
  const { file, index, temps } = useLecteur.getState();
  const titres = useBibliotheque.getState().titres;
  const valides = file.filter((id) => titres[id]);
  if (!valides.length) return useLecteur.setState({ file: [], index: 0 });
  if (valides.length !== file.length) return useLecteur.setState({ file: valides, index: 0, temps: 0 });
  const t = titreJoue(titres[file[index]])!;
  useLecteur.setState({ duree: t.duree || 0, idLu: t.id });
  moteur.charger(t, temps, false);
  majMediaSession();
}
