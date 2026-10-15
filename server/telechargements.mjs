// Téléchargements pour l'écoute hors ligne (comme dans YouTube Music), un à la fois :
// yt-dlp récupère l'audio (.m4a) ou le clip (.mp4), ffmpeg écrit les tags (titre, artiste, pochette),
// et les paroles sont enregistrées à côté (.lrc). Le fichier rejoint ensuite la bibliothèque locale.
// Nom des fichiers : « Artiste - Titre [idVideo].m4a » → le scanner reconnaît leur origine YouTube.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { DOSSIER_MUSIQUE_DEFAUT, RACINE } from './chemins.mjs';
import { parolesEnLigne } from './paroles.mjs';

export const DOSSIER_TELECHARGEMENTS = path.join(DOSSIER_MUSIQUE_DEFAUT, 'Téléchargements');
const YTDLP = path.join(RACINE, 'outils', 'yt-dlp');
const FFMPEG = path.join(RACINE, 'outils', 'ffmpeg');

const FORMATS = {
  audio: { ext: 'm4a', args: ['-f', 'bestaudio[ext=m4a]/bestaudio', '-x', '--audio-format', 'm4a'] },
  // H.264 jusqu'en 1080p : lu partout, sans réencodage.
  video: { ext: 'mp4', args: ['-f', 'bv*[ext=mp4][vcodec^=avc1][height<=1080]+ba[ext=m4a]/b[ext=mp4]/bv*+ba', '--merge-output-format', 'mp4'] },
};

const taches = new Map(); // `${idVideo}:${format}` -> tâche
let file = Promise.resolve();
let quandFini = () => {};
export const surFin = (fn) => (quandFini = fn);

export const listeTaches = () => [...taches.values()];

const nomPropre = (s) => s.replace(/[/\\:*?"<>|\u0000-\u001f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 120);

function executer(binaire, args, surLigne) {
  return new Promise((ok, echec) => {
    const p = spawn(binaire, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let erreurs = '';
    p.stdout.on('data', (d) => String(d).split(/\r?\n/).forEach((l) => l && surLigne?.(l)));
    p.stderr.on('data', (d) => {
      erreurs = (erreurs + d).slice(-2000);
      String(d).split(/\r?\n/).forEach((l) => l && surLigne?.(l)); // yt-dlp y écrit sa progression
    });
    p.on('error', echec);
    p.on('close', (code) => (code === 0 ? ok() : echec(new Error(erreurs.trim().split('\n').pop() || `${path.basename(binaire)} a échoué`))));
  });
}

// Fichiers déjà téléchargés pour cette vidéo (tous formats).
export function fichiersDe(idVideo) {
  try {
    return fs.readdirSync(DOSSIER_TELECHARGEMENTS).filter((f) => f.includes(`[${idVideo}].`)).map((f) => path.join(DOSSIER_TELECHARGEMENTS, f));
  } catch {
    return [];
  }
}

export function telecharger({ idVideo, titre, artiste, duree, format }) {
  if (!/^[\w-]{11}$/.test(idVideo || '') || !FORMATS[format]) throw Object.assign(new Error('Demande invalide'), { statut: 400 });
  const cle = `${idVideo}:${format}`;
  const existante = taches.get(cle);
  if (existante && existante.etat !== 'erreur') return existante;
  const tache = { idVideo, format, titre, artiste, etat: 'attente', progression: 0, erreur: null };
  taches.set(cle, tache);
  file = file.then(() => executerTache(tache, duree)).catch(() => {});
  return tache;
}

async function executerTache(tache, duree) {
  const { idVideo, format, titre, artiste } = tache;
  const { ext, args } = FORMATS[format];
  const base = nomPropre(`${artiste} - ${titre}`) + ` [${idVideo}]`;
  const cible = path.join(DOSSIER_TELECHARGEMENTS, `${base}.${ext}`);
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'yml-telechargement-'));
  tache.etat = 'encours';
  let partie = 0;
  let precedent = 0;
  try {
    fs.mkdirSync(DOSSIER_TELECHARGEMENTS, { recursive: true });
    // YouTube refuse parfois un flux (403) : on recommence, jusqu'à trois fois.
    const essayer = (n) => executer(
      YTDLP,
      [...args, '--ffmpeg-location', FFMPEG, '--no-playlist', '--write-thumbnail', '--convert-thumbnails', 'jpg',
        '--newline', '--progress-template', 'download:%(progress._percent_str)s', '-o', path.join(temp, 'media.%(ext)s'), '--',
        `https://www.youtube.com/watch?v=${idVideo}`],
      (ligne) => {
        // Un clip arrive en deux flux (image puis son) : chacun compte pour moitié.
        const p = parseFloat(ligne);
        if (Number.isNaN(p)) return;
        if (p < precedent) partie++;
        precedent = p;
        const parts = format === 'video' ? 2 : 1;
        tache.progression = Math.min(95, Math.round(((Math.min(partie, parts - 1) + p / 100) / parts) * 95));
      },
    ).catch((err) => {
      if (n >= 3 || !/403|Forbidden|timed out|reset/i.test(err.message)) throw err;
      partie = 0;
      precedent = 0;
      return new Promise((ok) => setTimeout(ok, 1500 * n)).then(() => essayer(n + 1));
    });
    await essayer(1);
    const media = fs.readdirSync(temp).find((f) => f.startsWith('media.') && !f.endsWith('.jpg'));
    if (!media) throw new Error('Fichier introuvable après le téléchargement');

    // Pochette carrée (comme YouTube Music), recadrée au centre de la miniature.
    const miniature = path.join(temp, 'media.jpg');
    const pochette = path.join(temp, 'pochette.jpg');
    const avecPochette = fs.existsSync(miniature) &&
      (await executer(FFMPEG, ['-v', 'error', '-y', '-i', miniature, '-vf', "crop='min(iw,ih)':'min(iw,ih)',scale=600:600", pochette]).then(() => true, () => false));

    // Tags + pochette intégrée (audio) ; aucun réencodage.
    const tags = ['-metadata', `title=${titre}`, '-metadata', `artist=${artiste}`, '-metadata', `album=${titre}`, '-metadata', `comment=youtube:${idVideo}`];
    const entrees = ['-i', path.join(temp, media), ...(avecPochette && format === 'audio' ? ['-i', pochette] : [])];
    const carte = avecPochette && format === 'audio' ? ['-map', '0:a', '-map', '1', '-disposition:v', 'attached_pic'] : ['-map', '0'];
    await executer(FFMPEG, ['-v', 'error', '-y', ...entrees, ...carte, '-c', 'copy', ...tags, '-movflags', '+faststart', path.join(temp, `final.${ext}`)]);
    fs.copyFileSync(path.join(temp, `final.${ext}`), cible);
    // Le clip garde sa pochette à côté (une piste image dans un .mp4 serait prise pour la vidéo).
    if (avecPochette && format === 'video') fs.copyFileSync(pochette, path.join(DOSSIER_TELECHARGEMENTS, `${base}.jpg`));

    // Paroles hors ligne.
    const lrc = path.join(DOSSIER_TELECHARGEMENTS, `${base}.lrc`);
    if (!fs.existsSync(lrc)) {
      const p = await parolesEnLigne({ titre, artiste, duree, idVideo }).catch(() => null);
      if (p?.texte) fs.writeFileSync(lrc, p.texte);
    }
    tache.progression = 100;
    tache.etat = 'fini';
    await quandFini(tache);
  } catch (err) {
    tache.etat = 'erreur';
    tache.erreur = /unavailable|private|removed/i.test(err.message) ? 'Vidéo indisponible' : err.message.replace(/^ERROR:\s*/, '').slice(0, 200);
    fs.rmSync(cible, { force: true });
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

// Supprime un téléchargement (et sa pochette / ses paroles si plus aucun format ne les utilise).
export function supprimer(chemin) {
  if (!chemin || path.dirname(chemin) !== DOSSIER_TELECHARGEMENTS) throw Object.assign(new Error('Ce titre n’est pas un téléchargement'), { statut: 400 });
  fs.rmSync(chemin, { force: true });
  const base = chemin.replace(/\.[^.]+$/, '');
  const restants = ['m4a', 'mp4'].some((e) => fs.existsSync(`${base}.${e}`));
  if (!restants) for (const e of ['jpg', 'lrc']) fs.rmSync(`${base}.${e}`, { force: true });
  for (const [cle, t] of taches) if (chemin.includes(`[${t.idVideo}]`) && chemin.endsWith(FORMATS[t.format].ext)) taches.delete(cle);
}
