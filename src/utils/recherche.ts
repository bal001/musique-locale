// Recherche locale, insensible aux accents et à la casse.
// Reproduit les deux sections renvoyées par youtubei/v1/music/get_search_suggestions
// (observé avec REA) : suggestions textuelles + résultats enrichis (artistes, albums, titres).
import type { Album, Artiste, Titre } from '../types';

export const normaliser = (s: string) =>
  s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();

// Score de pertinence : 0 = aucun rapport.
export function score(texte: string, requete: string) {
  const t = normaliser(texte);
  const q = normaliser(requete);
  if (!q) return 0;
  if (t === q) return 100;
  if (t.startsWith(q)) return 80;
  if (t.split(/[\s\-'(]+/).some((mot) => mot.startsWith(q))) return 60;
  if (t.includes(q)) return 40;
  // Tous les mots de la requête présents, dans n'importe quel ordre.
  const mots = q.split(' ');
  if (mots.length > 1 && mots.every((m) => t.includes(m))) return 30;
  return 0;
}

// Un bonus de type ne s'applique qu'aux éléments qui correspondent déjà.
const bonus = (s: number, b: number) => (s > 0 ? s + b : 0);

export type ResultatRecherche =
  | { type: 'artiste'; score: number; artiste: Artiste }
  | { type: 'album'; score: number; album: Album }
  | { type: 'titre'; score: number; titre: Titre };

export function rechercher(requete: string, d: { titres: Titre[]; albums: Album[]; artistes: Artiste[] }) {
  const artistes = d.artistes
    .map((a) => ({ type: 'artiste' as const, score: bonus(score(a.nom, requete), 5), artiste: a }))
    .filter((r) => r.score > 0);
  const albums = d.albums
    .map((a) => ({ type: 'album' as const, score: Math.max(bonus(score(a.titre, requete), 3), score(`${a.titre} ${a.artiste}`, requete), score(a.artiste, requete) * 0.6), album: a }))
    .filter((r) => r.score > 0);
  const titres = d.titres
    .map((t) => ({
      type: 'titre' as const,
      score: Math.max(score(t.titre, requete), score(`${t.titre} ${t.artiste}`, requete), score(t.artiste, requete) * 0.6, score(t.album, requete) * 0.5),
      titre: t,
    }))
    .filter((r) => r.score > 0);
  const tri = <T extends { score: number }>(l: T[]) => l.sort((a, b) => b.score - a.score);
  tri(artistes);
  tri(albums);
  tri(titres);
  const tous: ResultatRecherche[] = tri([...artistes, ...albums, ...titres]);
  return { meilleur: tous[0] ?? null, artistes, albums, titres, tous };
}

// Suggestions textuelles (complétions) à partir des noms connus.
export function suggestionsTexte(requete: string, d: { titres: Titre[]; albums: Album[]; artistes: Artiste[] }, max = 6) {
  const q = normaliser(requete);
  if (!q) return [];
  const vus = new Set<string>();
  const candidats: { texte: string; s: number }[] = [];
  const ajouter = (texte: string, bonus: number) => {
    const n = normaliser(texte);
    if (vus.has(n)) return;
    const s = score(texte, requete);
    if (s >= 60) {
      vus.add(n);
      candidats.push({ texte: texte.toLowerCase(), s: s + bonus });
    }
  };
  d.artistes.forEach((a) => ajouter(a.nom, 3));
  d.albums.forEach((a) => ajouter(a.titre, 1));
  d.titres.forEach((t) => {
    ajouter(t.titre, 2);
    ajouter(`${t.artistes[0]} ${t.titre}`, 0);
  });
  return candidats.sort((a, b) => b.s - a.s || a.texte.length - b.texte.length).slice(0, max).map((c) => c.texte);
}

// Historique des recherches (stocké dans le navigateur).
const CLE = 'yml-recherches';
export function recherchesRecentes(): string[] {
  try {
    return JSON.parse(localStorage.getItem(CLE) || '[]');
  } catch {
    return [];
  }
}
export function memoriserRecherche(q: string) {
  try {
    const l = [q, ...recherchesRecentes().filter((x) => normaliser(x) !== normaliser(q))].slice(0, 8);
    localStorage.setItem(CLE, JSON.stringify(l));
  } catch {}
}
export function oublierToutesRecherches() {
  try {
    localStorage.removeItem(CLE);
  } catch {}
}
export function oublierRecherche(q: string) {
  try {
    localStorage.setItem(CLE, JSON.stringify(recherchesRecentes().filter((x) => x !== q)));
  } catch {}
}
