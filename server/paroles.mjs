// Paroles en ligne, sans compte ni clé :
// 1. LRCLIB (base libre) → paroles synchronisées quand elles existent ;
// 2. sinon, l'onglet « Paroles » de YouTube Music (les mêmes paroles que dans l'app officielle).
// Les réponses sont gardées dans donnees/paroles-en-ligne.json (y compris « aucune parole »).
import fs from 'node:fs';
import path from 'node:path';
import { DOSSIER_DONNEES } from './chemins.mjs';

const FICHIER_CACHE = path.join(DOSSIER_DONNEES, 'paroles-en-ligne.json');
const AGENT = 'YouTubeMusiqueLocale/1.0 (application personnelle)';
const CLIENT_YTM = { clientName: 'WEB_REMIX', clientVersion: '1.20241001.01.00', hl: 'fr', gl: 'FR' };

let cache = null;
const lireCache = () => (cache ??= (() => {
  try {
    return JSON.parse(fs.readFileSync(FICHIER_CACHE, 'utf8'));
  } catch {
    return {};
  }
})());
function ecrireCache(cle, valeur) {
  lireCache()[cle] = valeur;
  fs.mkdirSync(DOSSIER_DONNEES, { recursive: true });
  fs.writeFileSync(FICHIER_CACHE, JSON.stringify(cache));
}

async function json(url, options = {}) {
  const res = await fetch(url, { ...options, signal: AbortSignal.timeout(6000), headers: { 'User-Agent': AGENT, ...options.headers } });
  if (!res.ok) throw new Error(`${res.status}`);
  return res.json();
}

// « Jefe (Clip officiel) [4K] » → « Jefe »
export const nettoyerTitre = (t) =>
  t
    .replace(/\s*[([][^)\]]*(clip|video|vidéo|audio|lyrics?|paroles|official|officiel|visuali[sz]er|4k|hd|remaster)[^)\]]*[)\]]/gi, '')
    .replace(/\s*[|｜].*$/, '')
    .trim();

async function depuisLrclib({ titre, artiste, duree }) {
  const q = new URLSearchParams({ track_name: nettoyerTitre(titre), artist_name: artiste.split(/,| & | feat/i)[0].trim() });
  const resultats = await json(`https://lrclib.net/api/search?${q}`);
  const proches = resultats.filter((r) => !duree || !r.duration || Math.abs(r.duration - duree) <= 4);
  const r = proches.find((x) => x.syncedLyrics) || proches.find((x) => x.plainLyrics);
  if (!r) return null;
  return { texte: r.syncedLyrics || r.plainLyrics, source: 'LRCLIB' };
}

async function depuisYoutubeMusic(idVideo) {
  const appel = (point, corps) =>
    json(`https://music.youtube.com/youtubei/v1/${point}?prettyPrint=false`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Origin: 'https://music.youtube.com' },
      body: JSON.stringify({ context: { client: CLIENT_YTM }, ...corps }),
    });
  const suite = JSON.stringify(await appel('next', { videoId: idVideo }));
  const idParoles = suite.match(/"browseId":"(MPLY[^"]+)"/)?.[1];
  if (!idParoles) return null;
  const page = JSON.stringify(await appel('browse', { browseId: idParoles }));
  const bloc = page.match(/"musicDescriptionShelfRenderer":\{"description":\{"runs":\[\{"text":("(?:[^"\\]|\\.)*")/);
  if (!bloc) return null;
  const fournisseur = page.match(/"footer":\{"runs":\[\{"text":("(?:[^"\\]|\\.)*")/);
  return { texte: JSON.parse(bloc[1]), source: fournisseur ? JSON.parse(fournisseur[1]) : 'YouTube Music' };
}

// Renvoie { texte, source } ou null. `idVideo` permet d'interroger YouTube Music.
export async function parolesEnLigne({ titre, artiste, duree, idVideo }) {
  const cle = idVideo ? `yt:${idVideo}` : `${artiste}|${titre}`.toLowerCase();
  const c = lireCache();
  if (cle in c) return c[cle];
  let trouve = null;
  let echec = false;
  for (const essai of [() => depuisLrclib({ titre, artiste, duree }), () => idVideo && depuisYoutubeMusic(idVideo)]) {
    try {
      trouve = await essai();
    } catch {
      echec = true; // réseau ou limite de requêtes : on ne mémorise pas un « rien trouvé »
    }
    if (trouve?.texte?.trim()) break;
    trouve = null;
  }
  if (trouve || !echec) ecrireCache(cle, trouve);
  return trouve;
}
