// Serveur local : API JSON + diffusion des fichiers audio et des pochettes.
// Joue le rôle des points d'accès youtubei/v1/* de YouTube Music, mais pour vos propres fichiers.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import express from 'express';
import QRCode from 'qrcode';
import { PORT, DOSSIER_DIST, DOSSIER_MUSIQUE_DEFAUT } from './chemins.mjs';
import { scanner, cheminPochette, analyserParoles } from './scanner.mjs';
import { chargerEtat, lireEtat, modifier, noterJaime, ajouterHistorique, basculerDansListe, nouvelId } from './stockage.mjs';
import { parolesEnLigne } from './paroles.mjs';
import { DOSSIER_TELECHARGEMENTS, listeTaches, supprimer as supprimerTelechargement, surFin, telecharger } from './telechargements.mjs';
import { rechercher as rechercherYoutube, tendances as tendancesYoutube, suggestions as suggestionsYoutube, infosLien, infosVideos, titresConnus, noterDuree } from './youtube.mjs';

const app = express();
app.use(express.json({ limit: '1mb' }));

// Accessible depuis l'iPhone sur le même Wi-Fi, mais jamais depuis Internet : réseau local uniquement.
const RESEAU_LOCAL = /^(::1|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|fe80:|fd|fc)/i;
app.use((req, res, next) => (RESEAU_LOCAL.test((req.socket.remoteAddress || '').replace(/^::ffff:/, '')) ? next() : res.sendStatus(403)));

let bibliotheque = null;
let scanEnCours = null;

async function rescanner() {
  if (scanEnCours) return scanEnCours;
  scanEnCours = (async () => {
    const debut = Date.now();
    const dossiers = lireEtat().reglages.dossiers.map(developperChemin);
    // Les téléchargements font toujours partie de la bibliothèque.
    if (!dossiers.some((d) => (DOSSIER_TELECHARGEMENTS + path.sep).startsWith(d + path.sep))) dossiers.push(DOSSIER_TELECHARGEMENTS);
    bibliotheque = await scanner(dossiers, { surProgression: (n) => console.log(`  … ${n} fichiers lus`) });
    console.log(`Bibliothèque : ${bibliotheque.titres.length} titres, ${bibliotheque.albums.length} albums, ${bibliotheque.artistes.length} artistes (${Date.now() - debut} ms)`);
    return bibliotheque;
  })().finally(() => (scanEnCours = null));
  return scanEnCours;
}

const developperChemin = (p) => path.resolve(p.replace(/^~(?=$|\/)/, os.homedir()));

function publique(b) {
  const { _chemins, _paroles, ...reste } = b;
  return reste;
}

// --- Bibliothèque -----------------------------------------------------------

app.get('/api/bibliotheque', async (_req, res) => {
  if (!bibliotheque) await rescanner();
  res.json(publique(bibliotheque));
});

app.post('/api/rescanner', async (_req, res) => {
  await rescanner();
  res.json(publique(bibliotheque));
});

app.get('/api/audio/:id', (req, res) => {
  const chemin = bibliotheque?._chemins.get(req.params.id);
  if (!chemin || !fs.existsSync(chemin)) return res.sendStatus(404);
  // sendFile gère les requêtes Range : la barre de progression peut sauter n'importe où.
  res.sendFile(chemin, { acceptRanges: true, maxAge: '1h', dotfiles: 'allow' });
});

app.get('/api/pochette/:id', (req, res) => {
  const chemin = cheminPochette(req.params.id);
  if (!chemin || !fs.existsSync(chemin)) return res.sendStatus(404);
  res.sendFile(chemin, { maxAge: '7d', immutable: true, dotfiles: 'allow' });
});

// Paroles : fichier local (.lrc ou tag) d'abord, sinon en ligne (LRCLIB, puis YouTube Music).
app.get('/api/paroles/:id', async (req, res) => {
  const vide = { synchronisees: false, lignes: [], source: null };
  const locale = bibliotheque?._paroles.get(req.params.id);
  try {
    if (locale) return res.json({ ...analyserParoles(locale), source: 'fichier local' });
    const { titre, artiste, duree, idVideo } = req.query;
    if (!titre || !artiste) return res.json(vide);
    const enLigne = await parolesEnLigne({ titre: String(titre), artiste: String(artiste), duree: Number(duree) || 0, idVideo: /^[\w-]{11}$/.test(idVideo || '') ? String(idVideo) : null });
    res.json(enLigne ? { ...analyserParoles({ texte: enLigne.texte }), source: enLigne.source } : vide);
  } catch {
    res.json(vide);
  }
});

// --- Téléchargements (écoute hors ligne) --------------------------------------

surFin(() => rescanner());
app.get('/api/telechargements', (_req, res) => res.json(listeTaches()));
app.post('/api/telechargements', (req, res) => {
  try {
    res.json(telecharger(req.body ?? {}));
  } catch (err) {
    res.status(err.statut || 500).json({ erreur: err.message });
  }
});
app.delete('/api/telechargements/:id', async (req, res) => {
  try {
    supprimerTelechargement(bibliotheque?._chemins.get(req.params.id));
    await rescanner();
    res.json(publique(bibliotheque));
  } catch (err) {
    res.status(err.statut || 500).json({ erreur: err.message });
  }
});

// --- État utilisateur -------------------------------------------------------

// La clé API YouTube ne quitte jamais le serveur : l'interface sait seulement si elle existe.
const cleYoutube = () => lireEtat().reglages.cleYoutube || process.env.YOUTUBE_API_KEY || '';
const reglagesPublics = (r) => {
  const { cleYoutube: _cle, ...reste } = r;
  return { ...reste, youtubeConfigure: true }; // la recherche YouTube marche toujours, avec ou sans clé
};

app.get('/api/etat', (_req, res) => {
  const e = lireEtat();
  res.json({ ...e, reglages: reglagesPublics(e.reglages) });
});

app.put('/api/jaime/:id', (req, res) => res.json(noterJaime(req.params.id, req.body?.valeur)));

app.post('/api/historique/:id', (req, res) => res.json(ajouterHistorique(req.params.id)));

app.delete('/api/historique', (_req, res) =>
  res.json(modifier((e) => ((e.historique = []), { historique: [], lectures: e.lectures }))),
);

// Retire un titre de l'historique (toutes ses écoutes), comme « Supprimer de l'historique » de YouTube Music.
app.delete('/api/historique/:id', (req, res) =>
  res.json(modifier((e) => ((e.historique = e.historique.filter((h) => h.id !== req.params.id)), { historique: e.historique, lectures: e.lectures }))),
);

app.put('/api/albums-enregistres/:id', (req, res) => res.json(basculerDansListe('albumsEnregistres', req.params.id)));
app.put('/api/artistes-suivis/:id', (req, res) => res.json(basculerDansListe('artistesSuivis', req.params.id)));

app.post('/api/playlists', (req, res) => {
  const { nom, description = '', titres = [] } = req.body ?? {};
  if (!nom?.trim()) return res.status(400).json({ erreur: 'Nom requis' });
  const p = { id: nouvelId(), nom: nom.trim(), description, titres, creeLe: Date.now(), modifieLe: Date.now() };
  modifier((e) => e.playlists.unshift(p));
  res.json(p);
});

app.patch('/api/playlists/:id', (req, res) => {
  const resultat = modifier((e) => {
    const p = e.playlists.find((x) => x.id === req.params.id);
    if (!p) return null;
    const { nom, description, titres, ajouter, retirerIndex } = req.body ?? {};
    if (typeof nom === 'string' && nom.trim()) p.nom = nom.trim();
    if (typeof description === 'string') p.description = description;
    if (Array.isArray(titres)) p.titres = titres;
    if (Array.isArray(ajouter)) p.titres.push(...ajouter);
    if (Number.isInteger(retirerIndex)) p.titres.splice(retirerIndex, 1);
    p.modifieLe = Date.now();
    return p;
  });
  resultat ? res.json(resultat) : res.sendStatus(404);
});

app.delete('/api/playlists/:id', (req, res) => {
  modifier((e) => (e.playlists = e.playlists.filter((p) => p.id !== req.params.id)));
  res.json({ ok: true });
});

app.put('/api/reglages', async (req, res) => {
  const { dossiers, lectureAuto, cleYoutube: nouvelleCle } = req.body ?? {};
  const avant = JSON.stringify(lireEtat().reglages.dossiers);
  const reglages = modifier((e) => {
    if (Array.isArray(dossiers)) e.reglages.dossiers = [...new Set(dossiers.map((d) => String(d).trim()).filter(Boolean))];
    if (typeof lectureAuto === 'boolean') e.reglages.lectureAuto = lectureAuto;
    if (typeof nouvelleCle === 'string') e.reglages.cleYoutube = nouvelleCle.trim();
    return e.reglages;
  });
  const manquants = reglages.dossiers.filter((d) => !fs.existsSync(developperChemin(d)));
  if (JSON.stringify(reglages.dossiers) !== avant) await rescanner();
  res.json({ reglages: reglagesPublics(reglages), manquants });
});

// --- YouTube (API officielle + lecteur intégré côté client) ----------------

const routeYoutube = (fn) => async (req, res) => {
  try {
    res.json(await fn(req));
  } catch (err) {
    res.status(err.statut && err.statut < 500 ? err.statut : 502).json({ erreur: err.message });
  }
};

app.get('/api/youtube/recherche', routeYoutube((req) => rechercherYoutube(String(req.query.q || ''), cleYoutube())));
app.get('/api/youtube/tendances', routeYoutube(() => tendancesYoutube(cleYoutube())));
app.get('/api/youtube/suggestions', routeYoutube((req) => suggestionsYoutube(req.query.q)));
app.get('/api/youtube/lien', routeYoutube((req) => infosLien(String(req.query.url || ''), cleYoutube())));
app.get('/api/youtube/connus', (_req, res) => res.json(titresConnus()));
app.post('/api/youtube/infos', routeYoutube((req) => infosVideos(Array.isArray(req.body?.ids) ? req.body.ids : [], cleYoutube())));
app.post('/api/youtube/duree/:id', (req, res) => {
  noterDuree(req.params.id, Number(req.body?.duree));
  res.json({ ok: true });
});

// --- iPhone : adresse du Mac sur le Wi-Fi + QR code à scanner -----------------

app.get('/api/iphone', async (_req, res) => {
  const ip = Object.values(os.networkInterfaces()).flat().find((i) => i?.family === 'IPv4' && !i.internal && /^(192\.168|10\.|172\.)/.test(i.address))?.address;
  if (!ip) return res.json({ adresse: null, qr: null });
  const adresse = `http://${ip}:${PORT}`;
  res.json({ adresse, qr: await QRCode.toString(adresse, { type: 'svg', margin: 1, color: { dark: '#030304', light: '#ffffff' } }) });
});

// --- Interface (build de production) ----------------------------------------

if (fs.existsSync(DOSSIER_DIST)) {
  app.use(express.static(DOSSIER_DIST));
  app.get(/^(?!\/api\/).*/, (_req, res) => res.sendFile(path.join(DOSSIER_DIST, 'index.html')));
}

// --- Démarrage --------------------------------------------------------------

chargerEtat();
fs.mkdirSync(DOSSIER_MUSIQUE_DEFAUT, { recursive: true });
await rescanner();

// "pret" est attendu par l'application Mac (electron/principal.mjs).
export const pret = new Promise((ok, echec) => {
  const serveur = app.listen(PORT, '0.0.0.0', () => {
    const ui = fs.existsSync(DOSSIER_DIST) ? `http://localhost:${PORT}` : '(interface servie par Vite en mode dev)';
    console.log(`\n▶ YouTube Musique Locale — API sur http://localhost:${PORT}/api  ·  interface : ${ui}\n`);
    ok({ url: `http://localhost:${PORT}`, existant: false });
  });
  serveur.on('error', (err) => {
    // Un serveur tourne déjà (par ex. "npm start") : on l'utilise.
    if (err.code === 'EADDRINUSE') ok({ url: `http://localhost:${PORT}`, existant: true });
    else echec(err);
  });
});
