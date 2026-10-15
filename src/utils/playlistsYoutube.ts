// Lecture du contenu d'une playlist publique YouTube SANS clé API :
// un lecteur officiel (IFrame Player API) temporaire, hors écran et qui ne joue jamais,
// charge la playlist et renvoie la liste de ses vidéos (getPlaylist), puis est détruit.
// Les titres sont ensuite demandés au serveur (oEmbed, sans clé).
import { api } from '../api';
import { useBibliotheque } from '../store/bibliotheque';
import { chargerApi } from '../store/moteur';
import type { Titre } from '../types';

/* eslint-disable @typescript-eslint/no-explicit-any */
let fileAttente: Promise<unknown> = Promise.resolve();

const DUREE_CACHE = 12 * 3600_000;

// Un lecteur neuf par playlist : réutilisé, le lecteur officiel renvoie la liste précédente.
async function lireAvecLecteurNeuf(idPlaylist: string): Promise<string[]> {
  await chargerApi();
  const hote = document.createElement('div');
  hote.setAttribute('aria-hidden', 'true');
  hote.style.cssText = 'position:fixed;left:-10000px;top:0;width:320px;height:180px;pointer-events:none';
  const cible = document.createElement('div');
  hote.appendChild(cible);
  document.body.appendChild(hote);
  let p: any = null;
  try {
    return await new Promise<string[]>((ok) => {
      const lire = () => {
        const l = p?.getPlaylist?.();
        if (Array.isArray(l) && l.length) fin(l);
      };
      const fin = (liste: string[]) => {
        clearTimeout(minuterie);
        clearInterval(sondage);
        ok(liste);
      };
      const minuterie = window.setTimeout(() => fin([]), 12_000);
      const sondage = window.setInterval(lire, 400);
      p = new window.YT.Player(cible, {
        width: 320,
        height: 180,
        playerVars: { autoplay: 0, listType: 'playlist', list: idPlaylist, origin: location.origin },
        events: { onStateChange: (e: { data: number }) => e.data === 5 && lire() },
      });
    });
  } finally {
    try {
      p?.destroy?.();
    } catch {}
    hote.remove();
  }
}

function lireCache(id: string): string[] | null {
  try {
    const c = JSON.parse(localStorage.getItem(`yml-pl2:${id}`) || 'null');
    return c && Date.now() - c.t < DUREE_CACHE ? c.ids : null;
  } catch {
    return null;
  }
}

// Identifiants des vidéos d'une playlist (les demandes passent une par une).
export function videosDePlaylist(idPlaylist: string): Promise<string[]> {
  const enCache = lireCache(idPlaylist);
  if (enCache) return Promise.resolve(enCache);
  const tache = fileAttente.then(async () => {
    const ids = await lireAvecLecteurNeuf(idPlaylist);
    try {
      if (ids.length) localStorage.setItem(`yml-pl2:${idPlaylist}`, JSON.stringify({ t: Date.now(), ids }));
    } catch {}
    return ids;
  });
  fileAttente = tache.catch(() => {});
  return tache;
}

// Titres (avec nom, artiste, miniature) des premières vidéos d'une playlist.
export async function titresDePlaylist(idPlaylist: string, max = 25): Promise<Titre[]> {
  const ids = (await videosDePlaylist(idPlaylist)).slice(0, max);
  if (!ids.length) return [];
  const { titres, integrerYoutube } = useBibliotheque.getState();
  const manquants = ids.filter((id) => !titres[`yt:${id}`]);
  if (manquants.length) integrerYoutube(await api.youtubeInfos(manquants));
  const a = useBibliotheque.getState().titres;
  return ids.map((id) => a[`yt:${id}`]).filter(Boolean);
}
