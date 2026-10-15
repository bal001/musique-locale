// Moteur de lecture à deux sources, derrière une interface unique :
// - "local"   : élément <video> qui lit vos fichiers via /api/audio/:id (musique, ou clips téléchargés
//               affichés par <VideoYoutube />) ;
// - "youtube" : lecteur intégré de YouTube (IFrame Player API), dans le lecteur développé ou en mini-lecteur.
import { urlAudio } from '../api';
import type { Titre } from '../types';

export interface Ecouteurs {
  lecture: () => void;
  pause: () => void;
  temps: (t: number, duree: number) => void;
  duree: (d: number) => void;
  fin: () => void;
  chargement: (actif: boolean) => void;
  erreur: (message: string) => void;
}

let ec: Ecouteurs | null = null;
export const brancher = (e: Ecouteurs) => (ec = e);

type Source = 'local' | 'youtube';
let actif: Source = 'local';
let jeton = 0; // invalide les chargements dépassés (clics rapides sur "suivant")
let volume = 1;
let muet = false;

// --- Source locale -------------------------------------------------------------

// Un <video> lit aussi bien l'audio que les clips ; <VideoYoutube /> l'insère une fois pour toutes dans la page.
const audio = document.createElement('video');
audio.preload = 'auto';
audio.playsInline = true;
export const elementLocal = audio;
const siLocal = (fn: () => void) => () => actif === 'local' && fn();
audio.addEventListener('play', siLocal(() => ec?.lecture()));
audio.addEventListener('pause', siLocal(() => ec?.pause()));
audio.addEventListener('waiting', siLocal(() => ec?.chargement(true)));
audio.addEventListener('playing', siLocal(() => ec?.chargement(false)));
audio.addEventListener('loadedmetadata', siLocal(() => ec?.duree(audio.duration)));
audio.addEventListener('timeupdate', siLocal(() => ec?.temps(audio.currentTime, audio.duration)));
audio.addEventListener('ended', siLocal(() => ec?.fin()));
audio.addEventListener('error', siLocal(() => audio.src && ec?.erreur('Impossible de lire ce fichier')));

// --- Source YouTube (IFrame Player API) ---------------------------------------

/* eslint-disable @typescript-eslint/no-explicit-any */
declare global {
  interface Window {
    YT?: any;
    onYouTubeIframeAPIReady?: () => void;
  }
}

let apiPrete: Promise<void> | null = null;
let lecteurYt: any = null;
let lecteurPret: Promise<any> | null = null;
let videoChargee: string | null = null;
let etatYt = -1;
let sondage: number | undefined;

export function chargerApi() {
  apiPrete ??= new Promise<void>((ok, echec) => {
    if (window.YT?.Player) return ok();
    window.onYouTubeIframeAPIReady = () => ok();
    const s = document.createElement('script');
    s.src = 'https://www.youtube.com/iframe_api';
    s.onerror = () => {
      apiPrete = null;
      echec(new Error('Impossible de charger le lecteur YouTube (connexion ?)'));
    };
    document.head.appendChild(s);
  });
  return apiPrete;
}

function obtenirLecteur(): Promise<any> {
  lecteurPret ??= chargerApi().then(
    () =>
      new Promise((ok) => {
        // Le conteneur #yt-hote est rendu par <VideoYoutube /> ; on y crée un nœud que React ne gère pas.
        const hote = document.getElementById('yt-hote');
        const cible = document.createElement('div');
        hote?.appendChild(cible);
        lecteurYt = new window.YT.Player(cible, {
          width: '100%',
          height: '100%',
          playerVars: { playsinline: 1, rel: 0, origin: location.origin },
          events: {
            onReady: () => {
              lecteurYt.getIframe?.()?.setAttribute('title', 'Lecteur vidéo YouTube');
              lecteurYt.setVolume(Math.round(volume * 100));
              if (muet) lecteurYt.mute();
              ok(lecteurYt);
            },
            onStateChange: (e: { data: number }) => changementEtat(e.data),
            onError: (e: { data: number }) => {
              if (actif !== 'youtube') return;
              const raison = e.data === 101 || e.data === 150 ? "Le propriétaire de cette vidéo n'autorise pas sa lecture hors de YouTube" : 'Vidéo YouTube indisponible';
              ec?.erreur(raison);
            },
          },
        });
      }),
  );
  return lecteurPret;
}

function changementEtat(etat: number) {
  etatYt = etat;
  if (actif !== 'youtube') return;
  clearInterval(sondage);
  if (etat === 1) {
    ec?.chargement(false);
    ec?.lecture();
    const d = lecteurYt.getDuration();
    if (d) ec?.duree(d);
    // Le lecteur YouTube n'émet pas d'évènement de progression : on l'interroge.
    sondage = window.setInterval(() => ec?.temps(lecteurYt.getCurrentTime(), lecteurYt.getDuration()), 250);
  } else if (etat === 2 || etat === 5 || etat === -1) {
    ec?.pause();
  } else if (etat === 3) {
    ec?.chargement(true);
  } else if (etat === 0) {
    ec?.pause();
    ec?.fin();
  }
}

// --- Interface commune ---------------------------------------------------------

export const moteur = {
  source: () => actif,

  async charger(t: Titre, depart: number, lancer: boolean) {
    const moi = ++jeton;
    if (t.source === 'youtube' && t.idVideo) {
      audio.pause();
      actif = 'youtube';
      ec?.chargement(true);
      let p;
      try {
        p = await obtenirLecteur();
      } catch (err) {
        ec?.chargement(false);
        ec?.erreur((err as Error).message);
        return;
      }
      if (moi !== jeton) return;
      videoChargee = t.idVideo;
      const params = { videoId: t.idVideo, startSeconds: Math.floor(depart) };
      if (lancer) p.loadVideoById(params);
      else {
        p.cueVideoById(params);
        ec?.chargement(false);
      }
      return;
    }
    if (actif === 'youtube') {
      clearInterval(sondage);
      lecteurYt?.stopVideo?.();
      videoChargee = null;
    }
    actif = 'local';
    const src = urlAudio(t.id);
    if (!audio.src.endsWith(src)) audio.src = src;
    if (depart) audio.currentTime = depart;
    if (lancer) audio.play().catch(() => ec?.pause());
  },

  estCharge: () => (actif === 'youtube' ? videoChargee !== null : Boolean(audio.src)),

  lire() {
    if (actif === 'youtube') lecteurYt?.playVideo?.();
    else audio.play().catch(() => ec?.pause());
  },

  pause() {
    if (actif === 'youtube') lecteurYt?.pauseVideo?.();
    else audio.pause();
  },

  enPause: () => (actif === 'youtube' ? etatYt !== 1 && etatYt !== 3 : audio.paused),

  temps: (): number => (actif === 'youtube' ? lecteurYt?.getCurrentTime?.() ?? 0 : audio.currentTime),

  duree: (): number => (actif === 'youtube' ? lecteurYt?.getDuration?.() ?? 0 : audio.duration || 0),

  chercher(s: number) {
    if (actif === 'youtube') lecteurYt?.seekTo?.(s, true);
    else audio.currentTime = s;
    ec?.temps(s, moteur.duree());
  },

  regler(v: number, m: boolean) {
    volume = v;
    muet = m;
    audio.volume = v;
    audio.muted = m;
    if (lecteurYt?.setVolume) {
      lecteurYt.setVolume(Math.round(v * 100));
      if (m) lecteurYt.mute();
      else lecteurYt.unMute();
    }
  },
};
