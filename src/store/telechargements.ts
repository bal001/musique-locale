// Téléchargements pour l'écoute hors ligne (voir server/telechargements.mjs).
// Un titre YouTube téléchargé est lu depuis le fichier (clip de préférence, sinon audio) :
// il marche sans connexion, comme dans YouTube Music.
import { create } from 'zustand';
import { api } from '../api';
import type { FormatTelechargement, Telechargement, Titre } from '../types';
import { useBibliotheque } from './bibliotheque';
import { useLecteur } from './lecteur';
import { notifier } from './interface';

interface EtatTelechargements {
  taches: Telechargement[];
  telecharger: (t: Titre, format: FormatTelechargement) => Promise<void>;
  supprimer: (t: Titre) => Promise<void>;
}

let sondage: number | undefined;

export const useTelechargements = create<EtatTelechargements>((set, get) => {
  // Suit les tâches tant qu'il y en a en cours.
  const suivre = () => {
    if (sondage) return;
    sondage = window.setInterval(async () => {
      const avant = get().taches;
      const taches = await api.telechargements().catch(() => avant);
      set({ taches });
      for (const t of taches) {
        const ancien = avant.find((a) => a.idVideo === t.idVideo && a.format === t.format);
        if (ancien?.etat === t.etat) continue;
        if (t.etat === 'fini') {
          await useBibliotheque.getState().actualiser();
          notifier(`Téléchargé : ${t.titre}${t.format === 'video' ? ' (clip)' : ''}`);
        } else if (t.etat === 'erreur') notifier(`Échec du téléchargement de « ${t.titre} » : ${t.erreur}`);
      }
      if (!taches.some((t) => t.etat === 'attente' || t.etat === 'encours')) {
        clearInterval(sondage);
        sondage = undefined;
      }
    }, 700);
  };

  return {
    taches: [],

    async telecharger(t, format) {
      if (!t.idVideo) return;
      const tache = await api.telecharger(t, format).catch((e: Error) => notifier(`Téléchargement impossible : ${e.message}`));
      if (!tache) return;
      set((s) => ({ taches: [...s.taches.filter((x) => !(x.idVideo === tache.idVideo && x.format === tache.format)), tache] }));
      notifier(`Téléchargement de « ${t.titre} »${format === 'video' ? ' (clip vidéo)' : ''}…`);
      suivre();
    },

    async supprimer(t) {
      const b = await api.supprimerTelechargement(t.id).catch((e: Error) => notifier(e.message));
      if (!b) return;
      set((s) => ({ taches: s.taches.filter((x) => !(x.idVideo === t.origineYoutube && (x.format === 'video') === Boolean(t.video))) }));
      await useBibliotheque.getState().actualiser(b);
      if (useLecteur.getState().idLu === t.id) useLecteur.getState().rechargerCourant(); // on repasse sur YouTube
      notifier(`Téléchargement supprimé : ${t.titre}`);
    },
  };
});

// Fichiers téléchargés d'une vidéo YouTube (clip d'abord).
export function versionsTelechargees(idVideo: string | undefined, liste = useBibliotheque.getState().listeTitres): Titre[] {
  if (!idVideo) return [];
  return liste.filter((t) => t.origineYoutube === idVideo).sort((a, b) => Number(Boolean(b.video)) - Number(Boolean(a.video)));
}

// Le titre réellement lu : la version téléchargée si elle existe.
export function titreJoue(t: Titre | undefined, liste?: Titre[]): Titre | undefined {
  if (t?.source !== 'youtube') return t;
  return versionsTelechargees(t.idVideo, liste)[0] ?? t;
}

// Pour l'affichage : ce que le moteur lit vraiment (un téléchargement fini en cours d'écoute
// ne change rien avant le titre suivant).
export function useTitreJoue(id: string | undefined) {
  const t = useBibliotheque((s) => (id ? s.titres[id] : undefined));
  const liste = useBibliotheque((s) => s.listeTitres);
  const idLu = useLecteur((s) => s.idLu);
  const lu = useBibliotheque((s) => (idLu ? s.titres[idLu] : undefined));
  if (lu && (lu.id === id || (t?.idVideo && lu.origineYoutube === t.idVideo))) return lu;
  return titreJoue(t, liste);
}
