// Client de l'API locale (server/index.mjs).
import type { Bibliotheque, EtatUtilisateur, FormatTelechargement, Paroles, Playlist, Telechargement, Titre } from './types';

async function requete<T>(methode: string, url: string, corps?: unknown): Promise<T> {
  const res = await fetch(`/api${url}`, {
    method: methode,
    headers: corps === undefined ? undefined : { 'Content-Type': 'application/json' },
    body: corps === undefined ? undefined : JSON.stringify(corps),
  });
  if (!res.ok) {
    const corps = await res.json().catch(() => null);
    throw new Error(corps?.erreur || `${methode} ${url} → ${res.status}`);
  }
  return res.json() as Promise<T>;
}

export const api = {
  bibliotheque: () => requete<Bibliotheque>('GET', '/bibliotheque'),
  rescanner: () => requete<Bibliotheque>('POST', '/rescanner'),
  etat: () => requete<EtatUtilisateur>('GET', '/etat'),
  // Le serveur cherche aussi en ligne quand le titre n'a pas de paroles locales.
  paroles: (t: Titre) =>
    requete<Paroles>('GET', `/paroles/${encodeURIComponent(t.id)}?${new URLSearchParams({ titre: t.titre, artiste: t.artiste, duree: String(Math.round(t.duree || 0)), idVideo: t.idVideo || t.origineYoutube || '' })}`),
  telechargements: () => requete<Telechargement[]>('GET', '/telechargements'),
  telecharger: (t: Titre, format: FormatTelechargement) =>
    requete<Telechargement>('POST', '/telechargements', { idVideo: t.idVideo, titre: t.titre, artiste: t.artiste, duree: t.duree, format }),
  supprimerTelechargement: (id: string) => requete<Bibliotheque>('DELETE', `/telechargements/${id}`),
  noterJaime: (id: string, valeur: 1 | -1 | 0) => requete<EtatUtilisateur['jaime']>('PUT', `/jaime/${id}`, { valeur }),
  ajouterHistorique: (id: string) => requete<Pick<EtatUtilisateur, 'historique' | 'lectures'>>('POST', `/historique/${id}`),
  retirerDeLHistorique: (id: string) => requete<Pick<EtatUtilisateur, 'historique' | 'lectures'>>('DELETE', `/historique/${encodeURIComponent(id)}`),
  viderHistorique: () => requete<Pick<EtatUtilisateur, 'historique' | 'lectures'>>('DELETE', '/historique'),
  basculerAlbum: (id: string) => requete<string[]>('PUT', `/albums-enregistres/${id}`),
  basculerArtiste: (id: string) => requete<string[]>('PUT', `/artistes-suivis/${id}`),
  creerPlaylist: (nom: string, description: string, titres: string[]) => requete<Playlist>('POST', '/playlists', { nom, description, titres }),
  modifierPlaylist: (id: string, changements: Partial<Pick<Playlist, 'nom' | 'description' | 'titres'>> & { ajouter?: string[]; retirerIndex?: number }) =>
    requete<Playlist>('PATCH', `/playlists/${id}`, changements),
  supprimerPlaylist: (id: string) => requete<{ ok: true }>('DELETE', `/playlists/${id}`),
  youtubeRecherche: (q: string) => requete<Titre[]>('GET', `/youtube/recherche?q=${encodeURIComponent(q)}`),
  youtubeTendances: () => requete<Titre[]>('GET', '/youtube/tendances'),
  youtubeSuggestions: (q: string) => requete<string[]>('GET', `/youtube/suggestions?q=${encodeURIComponent(q)}`),
  youtubeLien: (lien: string) => requete<Titre>('GET', `/youtube/lien?url=${encodeURIComponent(lien)}`),
  youtubeInfos: (ids: string[]) => requete<Titre[]>('POST', '/youtube/infos', { ids }),
  youtubeConnus: () => requete<Record<string, Titre>>('GET', '/youtube/connus'),
  youtubeDuree: (id: string, duree: number) => requete<{ ok: true }>('POST', `/youtube/duree/${encodeURIComponent(id)}`, { duree }),
  iphone: () => requete<{ adresse: string | null; qr: string | null }>('GET', '/iphone'),
  sauverReglages: (reglages: Partial<EtatUtilisateur['reglages']> & { cleYoutube?: string }) =>
    requete<{ reglages: EtatUtilisateur['reglages']; manquants: string[] }>('PUT', '/reglages', reglages),
};

export const urlAudio = (id: string) => `/api/audio/${id}`;
export const urlPochette = (id: string | null | undefined) => (!id ? null : /^https?:/.test(id) ? id : `/api/pochette/${id}`);

export const estYoutube = (t: Pick<Titre, 'source'> | undefined) => t?.source === 'youtube';
export const lienYoutube = (t: Pick<Titre, 'idVideo'>) => `https://music.youtube.com/watch?v=${t.idVideo}`;
// Reconnaît un lien youtube.com / music.youtube.com / youtu.be.
export const ressembleLienYoutube = (texte: string) => /^(https?:\/\/)?([\w-]+\.)?(youtube\.com|youtu\.be)\//i.test(texte.trim());
