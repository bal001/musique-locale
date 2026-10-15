// "Similaires" et lecture automatique : sans les recommandations de Google, on rapproche
// les titres par artiste, genre, album et écoutes, avec un peu de hasard pour varier.
import { useBibliotheque } from '../store/bibliotheque';
import type { Titre } from '../types';

export function titresSimilaires(idReference: string | undefined, exclure: string[] = [], max = 20): Titre[] {
  const { titres, listeTitres, listeYoutube, utilisateur } = useBibliotheque.getState();
  const ref = idReference ? titres[idReference] : undefined;
  const candidats = ref?.source === 'youtube' ? [...listeYoutube, ...listeTitres] : listeTitres;
  const exclus = new Set(exclure.slice(-50));
  if (idReference) exclus.add(idReference);

  return candidats
    .filter((t) => !exclus.has(t.id) && utilisateur.jaime[t.id] !== -1)
    .map((t) => {
      let s = Math.random() * 2;
      if (ref) {
        if (t.idsArtistes.some((a) => ref.idsArtistes.includes(a)) || (t.source === 'youtube' && t.artiste === ref.artiste)) s += 4;
        if (t.source === ref.source) s += 2;
        if (t.genre && t.genre === ref.genre) s += 3;
        if (t.idAlbum === ref.idAlbum) s += 1;
        if (ref.annee && t.annee && Math.abs(ref.annee - t.annee) <= 3) s += 0.5;
      }
      if (utilisateur.jaime[t.id] === 1) s += 1.5;
      s += Math.min(2, (utilisateur.lectures[t.id] || 0) / 5);
      return { t, s };
    })
    .sort((a, b) => b.s - a.s)
    .slice(0, max)
    .map((x) => x.t);
}

// Mix d'un artiste : ses titres + des titres proches.
export function mixArtiste(idArtiste: string, max = 25): string[] {
  const { artistes } = useBibliotheque.getState();
  const a = artistes[idArtiste];
  if (!a) return [];
  const siens = [...a.titres].sort(() => Math.random() - 0.5).slice(0, 10);
  const proches = siens.length ? titresSimilaires(siens[0], siens, max - siens.length).map((t) => t.id) : [];
  return [...siens, ...proches].sort(() => Math.random() - 0.5);
}
