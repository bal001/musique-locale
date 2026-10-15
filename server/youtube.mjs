// Catalogue YouTube : recherche de n'importe quel artiste ou titre SANS clé (yt-dlp, comme CutLocal), tendances,
// suggestions pendant la frappe ; l'API YouTube Data v3 reste utilisée si une clé a été ajoutée.
// La lecture se fait côté client avec le lecteur YouTube intégré. Rien n'est téléchargé.
import fs from 'node:fs';
import { execFile } from 'node:child_process';
import path from 'node:path';
import { DOSSIER_DONNEES } from './chemins.mjs';

const API = 'https://www.googleapis.com/youtube/v3';
const FICHIER_CONNUS = path.join(DOSSIER_DONNEES, 'youtube-titres.json');
const CATEGORIE_MUSIQUE = '10';
const DUREE_CACHE_MS = 30 * 24 * 3600 * 1000; // conservation max. autorisée des données de l'API : 30 jours

let connus = null; // { idTitre: titre }

function chargerConnus() {
  if (connus) return connus;
  try {
    connus = JSON.parse(fs.readFileSync(FICHIER_CONNUS, 'utf8'));
    const limite = Date.now() - DUREE_CACHE_MS;
    for (const [id, t] of Object.entries(connus)) if ((t.vuLe || 0) < limite) delete connus[id];
  } catch {
    connus = {};
  }
  return connus;
}

function memoriser(titres) {
  const c = chargerConnus();
  for (const t of titres) c[t.id] = { ...c[t.id], ...t, vuLe: Date.now() };
  const tmp = `${FICHIER_CONNUS}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(c));
  fs.renameSync(tmp, FICHIER_CONNUS);
  return titres;
}

export const titresConnus = () => chargerConnus();

// "PT3M17S" → 197
function dureeIso(iso = '') {
  const m = iso.match(/P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!m) return 0;
  const [, j, h, mi, s] = m.map((x) => Number(x) || 0);
  return j * 86400 + h * 3600 + mi * 60 + s;
}

const decoder = (s = '') =>
  s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>');

// Les chaînes "Artiste - Topic" de YouTube Music deviennent "Artiste".
const nettoyerChaine = (nom = '') => nom.replace(/\s*-\s*Topic$/i, '').replace(/VEVO$/i, '').trim();

// "Artiste - Titre (Clip officiel)" → { artiste, titre } quand c'est possible.
function separerTitre(titreVideo, chaine) {
  const propre = decoder(titreVideo)
    .replace(/\s*[([](?:official|clip|video|audio|lyrics?|paroles|visualizer|music video|hd|4k)[^)\]]*[)\]]/gi, '')
    .trim();
  const m = propre.match(/^(.+?)\s+[-–—]\s+(.+)$/);
  if (m) return { artiste: m[1].trim(), titre: m[2].trim() };
  return { artiste: chaine, titre: propre };
}

function versTitre(video) {
  const sn = video.snippet ?? {};
  const chaine = nettoyerChaine(sn.channelTitle);
  const { artiste, titre } = separerTitre(sn.title ?? '', chaine);
  const vignettes = sn.thumbnails ?? {};
  const miniature = (vignettes.maxres || vignettes.high || vignettes.medium || vignettes.default)?.url ?? null;
  const idVideo = typeof video.id === 'string' ? video.id : video.id?.videoId;
  return {
    id: `yt:${idVideo}`,
    source: 'youtube',
    idVideo,
    titre,
    artiste,
    artistes: [artiste],
    idsArtistes: [],
    album: chaine || 'YouTube',
    idAlbum: '',
    artisteAlbum: chaine,
    annee: sn.publishedAt ? Number(sn.publishedAt.slice(0, 4)) : null,
    genre: null,
    piste: null,
    disque: null,
    duree: dureeIso(video.contentDetails?.duration),
    pochette: miniature,
    paroles: null,
    ajouteLe: Date.now(),
  };
}

async function appel(route, params, cle) {
  const url = new URL(`${API}/${route}`);
  for (const [k, v] of Object.entries({ ...params, key: cle })) url.searchParams.set(k, String(v));
  const res = await fetch(url);
  const corps = await res.json().catch(() => ({}));
  if (!res.ok) {
    const raison = corps.error?.errors?.[0]?.reason || corps.error?.status || res.status;
    const message = {
      quotaExceeded: 'Quota quotidien de l\'API YouTube épuisé (il se recharge chaque jour).',
      keyInvalid: 'Clé API YouTube invalide.',
      API_KEY_INVALID: 'Clé API YouTube invalide.',
      accessNotConfigured: 'L\'API « YouTube Data API v3 » n\'est pas activée sur ce projet Google Cloud.',
    }[raison];
    const err = new Error(message || `Erreur de l'API YouTube (${raison})`);
    err.statut = res.status;
    throw err;
  }
  return corps;
}

// Détails (durée) de plusieurs vidéos en un seul appel (1 unité de quota).
async function details(ids, cle) {
  if (!ids.length) return [];
  const r = await appel('videos', { part: 'snippet,contentDetails', id: ids.join(','), maxResults: 50 }, cle);
  return r.items ?? [];
}

// Cache des requêtes (requête → { t, titres }) conservé sur disque : économise le quota entre deux lancements.
const FICHIER_CACHE = path.join(DOSSIER_DONNEES, 'youtube-requetes.json');
const cacheRequetes = new Map(Object.entries((() => {
  try {
    return JSON.parse(fs.readFileSync(FICHIER_CACHE, 'utf8'));
  } catch {
    return {};
  }
})()));
function mettreEnCache(k, titres) {
  cacheRequetes.set(k, { t: Date.now(), titres });
  try {
    fs.writeFileSync(FICHIER_CACHE, JSON.stringify(Object.fromEntries(cacheRequetes)));
  } catch {}
}
const DUREE_CACHE_REQUETE = 6 * 3600_000;

// --- Sans clé : yt-dlp (métadonnées de recherche uniquement) -----------------------------------------
const YTDLP = path.join(path.dirname(DOSSIER_DONNEES), 'outils', 'yt-dlp');

function ytdlp(args) {
  return new Promise((resolve, reject) => {
    execFile(YTDLP, ['--ignore-config', '--no-cache-dir', '--flat-playlist', '--dump-single-json', ...args],
      { timeout: 45_000, maxBuffer: 32 * 1024 * 1024 }, (err, stdout) => {
        if (err) return reject(Object.assign(new Error('YouTube ne répond pas pour le moment. Réessaie.'), { statut: 502 }));
        try {
          resolve(JSON.parse(stdout));
        } catch {
          reject(Object.assign(new Error('Réponse de YouTube illisible.'), { statut: 502 }));
        }
      });
  });
}

// Une entrée de résultat yt-dlp → un titre de l'app (même forme que l'API officielle).
function depuisYtdlp(e) {
  const t = versTitre({ id: e.id, snippet: { title: e.title ?? '', channelTitle: e.channel || e.uploader || '',
    thumbnails: { high: { url: `https://i.ytimg.com/vi/${e.id}/hqdefault.jpg` } } } });
  return { ...t, duree: Math.round(e.duration || 0) };
}

// Musique seulement : on écarte les émissions, directs et vidéos très longues (plus de 15 min).
const estMusique = (e) => /^[\w-]{11}$/.test(e?.id || '') && (!e.duration || (e.duration >= 30 && e.duration <= 900)) && !e.live_status?.includes('live');

// Deux recherches en même temps : YouTube Music (que des chansons, les plus pertinentes d'abord) et YouTube (artiste,
// durée, clips). Les chansons viennent en premier ; un artiste encore inconnu est demandé à oEmbed.
async function rechercherSansCle(q, nombre = 30) {
  const urlMusique = `https://music.youtube.com/search?q=${encodeURIComponent(q)}#songs`;
  const [musique, videos] = await Promise.allSettled([
    ytdlp(['--playlist-end', '25', urlMusique]),
    ytdlp([`ytsearch${nombre}:${q}`]),
  ]);
  if (musique.status === 'rejected' && videos.status === 'rejected') throw musique.reason;
  const clips = videos.status === 'fulfilled' ? (videos.value.entries ?? []).filter(estMusique) : [];
  const parId = new Map(clips.map((e) => [e.id, e]));
  const chansons = musique.status === 'fulfilled' ? (musique.value.entries ?? []).filter((e) => /^[\w-]{11}$/.test(e?.id || '')) : [];
  const resultats = [];
  const inconnues = [];
  for (const c of chansons) {
    const clip = parId.get(c.id);
    if (clip) resultats.push(depuisYtdlp({ ...clip, title: clip.title }));
    else inconnues.push(c);
  }
  // Artiste des chansons sans clip correspondant : oEmbed (« Ninho - Topic » → « Ninho »), 8 à la fois.
  const completes = new Map();
  const file = [...inconnues];
  await Promise.all(Array.from({ length: 8 }, async () => {
    while (file.length) {
      const c = file.shift();
      try {
        const res = await fetch(`https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(`https://www.youtube.com/watch?v=${c.id}`)}`, { signal: AbortSignal.timeout(5000) });
        if (!res.ok) continue;
        const o = await res.json();
        const artiste = nettoyerChaine(o.author_name || '');
        completes.set(c.id, depuisYtdlp({ id: c.id, title: artiste ? `${artiste} - ${c.title}` : c.title, channel: artiste }));
      } catch {}
    }
  }));
  for (const c of chansons) if (completes.has(c.id)) resultats.splice(chansons.indexOf(c), 0, completes.get(c.id));
  const vus = new Set(resultats.map((t) => t.idVideo));
  for (const e of clips) if (!vus.has(e.id)) resultats.push(depuisYtdlp(e));
  return memoriser(resultats.slice(0, 50));
}

// Suggestions de YouTube pendant la frappe (la liste sous sa barre de recherche) ; seuls les mots tapés sont envoyés.
export async function suggestions(q) {
  q = String(q || '').trim();
  if (!q || q.length > 100) return [];
  const url = `https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&hl=fr&gl=FR&q=${encodeURIComponent(q)}`;
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(4000) });
    const [, liste] = await res.json();
    return (liste ?? []).slice(0, 8);
  } catch {
    return [];
  }
}

export async function rechercher(q, cle) {
  const k = `r:${q.toLowerCase().trim()}`;
  const enCache = cacheRequetes.get(k);
  if (enCache && Date.now() - enCache.t < DUREE_CACHE_REQUETE) return enCache.titres;
  if (!cle) {
    const titres = await rechercherSansCle(q);
    mettreEnCache(k, titres);
    return titres;
  }
  // search.list coûte 100 unités ; quota gratuit : 10 000 unités par jour.
  const r = await appel('search', { part: 'id', type: 'video', videoCategoryId: CATEGORIE_MUSIQUE, maxResults: 25, q, regionCode: 'FR', relevanceLanguage: 'fr' }, cle);
  const ids = (r.items ?? []).map((i) => i.id?.videoId).filter(Boolean);
  const titres = memoriser((await details(ids, cle)).map(versTitre));
  mettreEnCache(k, titres);
  return titres;
}

export async function tendances(cle, region = 'FR') {
  const k = `t:${region}`;
  const enCache = cacheRequetes.get(k);
  if (enCache && Date.now() - enCache.t < DUREE_CACHE_REQUETE) return enCache.titres;
  if (!cle) {
    // Sans clé : les clips musicaux qui cartonnent en ce moment en France.
    const titres = await rechercherSansCle(`hits du moment ${new Date().getFullYear()} clip officiel`, 40);
    mettreEnCache(k, titres);
    return titres;
  }
  const r = await appel('videos', { part: 'snippet,contentDetails', chart: 'mostPopular', videoCategoryId: CATEGORIE_MUSIQUE, regionCode: region, maxResults: 30 }, cle);
  const titres = memoriser((r.items ?? []).map(versTitre));
  mettreEnCache(k, titres);
  return titres;
}

// Extrait l'identifiant d'une URL youtube.com / music.youtube.com / youtu.be.
export function idDepuisLien(texte) {
  try {
    const u = new URL(texte.trim());
    if (/(^|\.)youtu\.be$/.test(u.hostname)) return u.pathname.slice(1).split('/')[0] || null;
    if (/(^|\.)youtube\.com$/.test(u.hostname)) {
      if (u.searchParams.get('v')) return u.searchParams.get('v');
      const m = u.pathname.match(/^\/(?:shorts|embed|live)\/([\w-]{6,})/);
      return m?.[1] ?? null;
    }
  } catch {}
  return /^[\w-]{11}$/.test(texte.trim()) ? texte.trim() : null;
}

// Infos d'un lien : API si une clé existe (avec durée), sinon oEmbed (sans clé).
export async function infosLien(texte, cle) {
  const idVideo = idDepuisLien(texte);
  if (!idVideo) throw Object.assign(new Error('Lien YouTube non reconnu'), { statut: 400 });
  const connu = chargerConnus()[`yt:${idVideo}`];
  if (connu?.duree) return connu;
  if (cle) {
    const [video] = await details([idVideo], cle);
    if (video) return memoriser([versTitre(video)])[0];
  }
  const res = await fetch(`https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(`https://www.youtube.com/watch?v=${idVideo}`)}`);
  if (!res.ok) throw Object.assign(new Error('Vidéo introuvable, privée ou non intégrable'), { statut: 404 });
  const o = await res.json();
  const t = versTitre({ id: idVideo, snippet: { title: o.title, channelTitle: o.author_name, thumbnails: { high: { url: o.thumbnail_url } } } });
  return memoriser([t])[0];
}

// Met à jour une durée découverte par le lecteur (vidéos ajoutées sans clé API).
export function noterDuree(id, duree) {
  const c = chargerConnus();
  if (c[id] && !c[id].duree && duree > 0) memoriser([{ ...c[id], duree: Math.round(duree) }]);
}

// Infos de plusieurs vidéos (titres des playlists officielles) via oEmbed, sans clé.
// Requêtes lentes et limitées (4 en parallèle), résultats gardés en cache 30 jours.
export async function infosVideos(ids, cle) {
  const uniques = [...new Set(ids.filter((id) => /^[\w-]{11}$/.test(id)))].slice(0, 60);
  const resultats = new Map();
  const file = [...uniques];
  const travailleur = async () => {
    while (file.length) {
      const id = file.shift();
      try {
        resultats.set(id, await infosLien(id, cle));
      } catch {
        // vidéo privée, supprimée ou non intégrable : ignorée
      }
    }
  };
  await Promise.all(Array.from({ length: 4 }, travailleur));
  return uniques.map((id) => resultats.get(id)).filter(Boolean);
}
