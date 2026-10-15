// Scanne les dossiers de musique, lit les tags (titre, artiste, album, pochette, paroles)
// et construit la bibliothèque : titres, albums, artistes.
// Un cache (donnees/cache-index.json) évite de relire les fichiers inchangés.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { parseFile } from 'music-metadata';
import { DOSSIER_DONNEES, DOSSIER_POCHETTES } from './chemins.mjs';

const EXTENSIONS_VIDEO = new Set(['.mp4', '.m4v', '.mov']); // clips téléchargés : lus avec l'image
const EXTENSIONS_AUDIO = new Set(['.mp3', '.m4a', '.aac', '.flac', '.ogg', '.oga', '.opus', '.wav', '.webm', ...EXTENSIONS_VIDEO]);
const NOMS_POCHETTE = /^(cover|folder|front|album|artwork|pochette)\.(jpe?g|png|webp|svg)$/i;
const FICHIER_CACHE = path.join(DOSSIER_DONNEES, 'cache-index.json');
const VERSION_CACHE = 3;

const hash = (texte, n = 12) => crypto.createHash('sha1').update(texte).digest('hex').slice(0, n);
const MIME_EXT = { 'image/jpeg': 'jpg', 'image/jpg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif' };

function* parcourir(dossier) {
  let entrees;
  try {
    entrees = fs.readdirSync(dossier, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entrees) {
    if (e.name.startsWith('.')) continue;
    const complet = path.join(dossier, e.name);
    if (e.isDirectory()) yield* parcourir(complet);
    else if (e.isFile() && EXTENSIONS_AUDIO.has(path.extname(e.name).toLowerCase())) yield complet;
  }
}

function lireCache() {
  try {
    const c = JSON.parse(fs.readFileSync(FICHIER_CACHE, 'utf8'));
    return c.version === VERSION_CACHE ? c.fichiers : {};
  } catch {
    return {};
  }
}

// Pochette intégrée au fichier → copiée une seule fois dans donnees/pochettes (dédupliquée par contenu).
function enregistrerPochetteIntegree(image) {
  const ext = MIME_EXT[image.format?.toLowerCase()] || 'jpg';
  const nom = `${hash(image.data, 16)}.${ext}`;
  const cible = path.join(DOSSIER_POCHETTES, nom);
  if (!fs.existsSync(cible)) fs.writeFileSync(cible, image.data);
  return nom;
}

// Pochette à côté du fichier (cover.jpg, folder.png…) → référencée par un id stable.
const pochettesDossier = new Map(); // idPochette -> chemin absolu
function pochetteDuDossier(dossier) {
  let fichiers = [];
  try {
    fichiers = fs.readdirSync(dossier);
  } catch {}
  const trouve = fichiers.find((f) => NOMS_POCHETTE.test(f));
  if (!trouve) return null;
  const complet = path.join(dossier, trouve);
  const id = `d-${hash(complet, 16)}${path.extname(trouve).toLowerCase()}`;
  pochettesDossier.set(id, complet);
  return id;
}

// Image portant le même nom que le fichier (« Titre.jpg »), sinon pochette du dossier.
function pochetteVoisine(chemin) {
  const base = chemin.replace(/\.[^.]+$/, '');
  const image = ['.jpg', '.jpeg', '.png', '.webp'].map((e) => base + e).find((f) => fs.existsSync(f));
  if (!image) return pochetteDuDossier(path.dirname(chemin));
  const id = `d-${hash(image, 16)}${path.extname(image).toLowerCase()}`;
  pochettesDossier.set(id, image);
  return id;
}

export function cheminPochette(id) {
  if (id.startsWith('d-')) return pochettesDossier.get(id) ?? null;
  if (!/^[a-f0-9]{16}\.[a-z]+$/.test(id)) return null;
  return path.join(DOSSIER_POCHETTES, id);
}

// "Angèle feat. Justice", "A & B", "A, B" → ["Angèle", "Justice"]
function separerArtistes(texte) {
  return texte
    .split(/\s*(?:,|&|;|\/| feat\.? | ft\.? | featuring | avec | x )\s*/i)
    .map((s) => s.trim())
    .filter(Boolean);
}

function texteParoles(lyrics) {
  if (!lyrics?.length) return null;
  const l = lyrics[0];
  if (typeof l === 'string') return l;
  if (l.syncText?.length) return l.syncText.map((s) => `[${formatLrc(s.timestamp)}]${s.text}`).join('\n');
  return l.text || null;
}

const formatLrc = (ms) => {
  const m = Math.floor(ms / 60000);
  const s = ((ms % 60000) / 1000).toFixed(2).padStart(5, '0');
  return `${String(m).padStart(2, '0')}:${s}`;
};

async function lireFichier(chemin, racine) {
  const st = fs.statSync(chemin);
  const meta = await parseFile(chemin, { duration: true, skipCovers: false });
  const c = meta.common;
  const nomFichier = path.basename(chemin, path.extname(chemin));
  const dossierParent = path.dirname(chemin);

  // Sans tags, on devine "Artiste - Titre" depuis le nom de fichier.
  let titre = c.title?.trim();
  let artiste = c.artist?.trim();
  if (!titre) {
    const m = nomFichier.match(/^(?:\d+[\s.-]+)?(.+?)\s+-\s+(.+)$/);
    if (m && !artiste) [artiste, titre] = [m[1], m[2]];
    else titre = nomFichier.replace(/^\d+[\s.-]+/, '');
  }
  artiste ||= c.albumartist?.trim() || 'Artiste inconnu';

  let album = c.album?.trim();
  if (!album) album = dossierParent !== racine ? path.basename(dossierParent) : titre;

  let pochette = null;
  if (c.picture?.length) pochette = enregistrerPochetteIntegree(c.picture[0]);
  else pochette = pochetteVoisine(chemin);

  const lrc = path.join(dossierParent, `${nomFichier}.lrc`);
  return {
    chemin,
    taille: st.size,
    mtime: st.mtimeMs,
    ajouteLe: Math.round(st.birthtimeMs || st.mtimeMs),
    titre,
    artiste,
    artistes: c.artists?.length ? c.artists.flatMap(separerArtistes) : separerArtistes(artiste),
    album,
    artisteAlbum: c.albumartist?.trim() || separerArtistes(artiste)[0] || artiste,
    annee: c.year || null,
    genre: c.genre?.[0]?.trim() || null,
    piste: c.track?.no || null,
    disque: c.disk?.no || null,
    duree: meta.format.duration || 0,
    pochette,
    video: EXTENSIONS_VIDEO.has(path.extname(chemin).toLowerCase()) || undefined,
    // « Artiste - Titre [idVideo].m4a » : téléchargé depuis YouTube.
    origineYoutube: nomFichier.match(/\[([\w-]{11})\]$/)?.[1],
    paroles: fs.existsSync(lrc) ? 'lrc' : texteParoles(c.lyrics) ? 'tag' : null,
    parolesTexte: fs.existsSync(lrc) ? null : texteParoles(c.lyrics),
  };
}

const typeAlbum = (n) => (n <= 3 ? 'Single' : 'Album');

export async function scanner(dossiers, { surProgression } = {}) {
  fs.mkdirSync(DOSSIER_POCHETTES, { recursive: true });
  const cache = lireCache();
  const nouveauCache = {};
  const titres = [];
  let lus = 0;

  for (const racine of dossiers) {
    for (const chemin of parcourir(racine)) {
      let info;
      try {
        const st = fs.statSync(chemin);
        const enCache = cache[chemin];
        if (enCache && enCache.mtime === st.mtimeMs && enCache.taille === st.size) {
          info = enCache;
          // Les pochettes de dossier vivent en mémoire : on les ré-enregistre.
          if (info.pochette?.startsWith('d-')) info.pochette = pochetteVoisine(chemin);
        } else {
          info = await lireFichier(chemin, racine);
        }
      } catch (err) {
        console.warn(`Fichier ignoré (${err.message}) : ${chemin}`);
        continue;
      }
      nouveauCache[chemin] = info;
      titres.push({ id: hash(chemin), ...info });
      if (++lus % 50 === 0) surProgression?.(lus);
    }
  }

  fs.writeFileSync(FICHIER_CACHE, JSON.stringify({ version: VERSION_CACHE, fichiers: nouveauCache }));
  return construireBibliotheque(titres);
}

function construireBibliotheque(titres) {
  const albums = new Map();
  const artistes = new Map();
  const idArtiste = (nom) => hash(`artiste:${nom.toLowerCase()}`);

  const artiste = (nom) => {
    const id = idArtiste(nom);
    if (!artistes.has(id)) artistes.set(id, { id, nom, albums: [], titres: [], pochette: null, genres: new Set() });
    return artistes.get(id);
  };

  for (const t of titres) {
    const idAlbum = hash(`album:${t.artisteAlbum.toLowerCase()}|${t.album.toLowerCase()}`);
    if (!albums.has(idAlbum)) {
      albums.set(idAlbum, {
        id: idAlbum,
        titre: t.album,
        artiste: t.artisteAlbum,
        idArtiste: idArtiste(t.artisteAlbum),
        annee: t.annee,
        genre: t.genre,
        pochette: t.pochette,
        titres: [],
        ajouteLe: t.ajouteLe,
      });
    }
    const a = albums.get(idAlbum);
    a.titres.push(t);
    a.annee ||= t.annee;
    a.genre ||= t.genre;
    a.pochette ||= t.pochette;
    a.ajouteLe = Math.max(a.ajouteLe, t.ajouteLe);
    t.idAlbum = idAlbum;
    t.artistes = [...new Set(t.artistes)];
    t.idsArtistes = t.artistes.map(idArtiste);
  }

  for (const a of albums.values()) {
    a.titres.sort((x, y) => (x.disque || 1) - (y.disque || 1) || (x.piste || 999) - (y.piste || 999) || x.titre.localeCompare(y.titre));
    a.type = typeAlbum(a.titres.length);
    a.duree = a.titres.reduce((s, t) => s + t.duree, 0);
    const principal = artiste(a.artiste);
    principal.albums.push(a.id);
    principal.pochette ||= a.pochette;
    if (a.genre) principal.genres.add(a.genre);
    for (const t of a.titres) {
      for (const nom of t.artistes) {
        const ar = artiste(nom);
        ar.titres.push(t.id);
        ar.pochette ||= t.pochette;
        if (t.genre) ar.genres.add(t.genre);
      }
      if (!t.artistes.some((n) => idArtiste(n) === principal.id)) principal.titres.push(t.id);
    }
    a.titres = a.titres.map((t) => t.id);
  }

  const sortieTitres = titres.map(({ chemin, taille, mtime, parolesTexte, ...reste }) => reste);
  return {
    genereLe: Date.now(),
    titres: sortieTitres,
    albums: [...albums.values()],
    artistes: [...artistes.values()].map((a) => ({ ...a, genres: [...a.genres] })),
    // Données internes, jamais envoyées au client.
    _chemins: new Map(titres.map((t) => [t.id, t.chemin])),
    _paroles: new Map(titres.filter((t) => t.paroles).map((t) => [t.id, t.paroles === 'lrc' ? { lrc: t.chemin.replace(/\.[^.]+$/, '.lrc') } : { texte: t.parolesTexte }])),
  };
}

// Paroles synchronisées (LRC) ou simples.
export function analyserParoles(source) {
  const texte = source.lrc ? fs.readFileSync(source.lrc, 'utf8') : source.texte || '';
  const lignes = [];
  let synchronisees = false;
  for (const brute of texte.split(/\r?\n/)) {
    const horodatages = [...brute.matchAll(/\[(\d{1,2}):(\d{2}(?:[.:]\d{1,3})?)\]/g)];
    const contenu = brute.replace(/\[[^\]]*\]/g, '').trim();
    if (horodatages.length) {
      synchronisees = true;
      for (const h of horodatages) lignes.push({ t: Number(h[1]) * 60 + Number(h[2].replace(':', '.')), texte: contenu });
    } else if (!/^\[[a-z]+:/i.test(brute) && (contenu || lignes.length)) {
      lignes.push({ t: null, texte: contenu });
    }
  }
  if (!synchronisees) return { synchronisees, lignes };
  return { synchronisees, lignes: lignes.filter((l) => l.t !== null).sort((a, b) => a.t - b.t) };
}
