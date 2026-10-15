// État utilisateur persistant (J'aime, playlists, historique, réglages) dans donnees/etat.json.
// Équivalent local de ce que YouTube Music garde côté compte Google.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { DOSSIER_DONNEES, DOSSIER_MUSIQUE_DEFAUT } from './chemins.mjs';

const FICHIER_ETAT = path.join(DOSSIER_DONNEES, 'etat.json');
const HISTORIQUE_MAX = 500;

function etatParDefaut() {
  return {
    version: 1,
    jaime: {},              // { idTitre: 1 (J'aime) | -1 (Je n'aime pas) }
    playlists: [],          // [{ id, nom, description, titres: [idTitre], creeLe, modifieLe }]
    albumsEnregistres: [],  // [idAlbum]
    artistesSuivis: [],     // [idArtiste]
    historique: [],         // [{ id: idTitre, t: timestamp }], le plus récent en premier
    lectures: {},           // { idTitre: nombre de lectures }
    reglages: {
      dossiers: [DOSSIER_MUSIQUE_DEFAUT],
      lectureAuto: true,
    },
  };
}

let etat = null;

export function chargerEtat() {
  fs.mkdirSync(DOSSIER_DONNEES, { recursive: true });
  try {
    const lu = JSON.parse(fs.readFileSync(FICHIER_ETAT, 'utf8'));
    const defaut = etatParDefaut();
    etat = { ...defaut, ...lu, reglages: { ...defaut.reglages, ...lu.reglages } };
  } catch {
    etat = etatParDefaut();
    sauver();
  }
  return etat;
}

export function lireEtat() {
  return etat ?? chargerEtat();
}

// Écriture atomique : on écrit un fichier temporaire puis on le renomme.
function sauver() {
  const tmp = `${FICHIER_ETAT}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(etat, null, 2));
  fs.renameSync(tmp, FICHIER_ETAT);
}

export function modifier(fn) {
  const resultat = fn(lireEtat());
  sauver();
  return resultat;
}

export const nouvelId = () => crypto.randomBytes(6).toString('hex');

export function noterJaime(idTitre, valeur) {
  return modifier((e) => {
    if (valeur === 1 || valeur === -1) e.jaime[idTitre] = valeur;
    else delete e.jaime[idTitre];
    return e.jaime;
  });
}

export function ajouterHistorique(idTitre) {
  return modifier((e) => {
    e.historique = [{ id: idTitre, t: Date.now() }, ...e.historique.filter((h) => h.id !== idTitre)].slice(0, HISTORIQUE_MAX);
    e.lectures[idTitre] = (e.lectures[idTitre] || 0) + 1;
    return { historique: e.historique, lectures: e.lectures };
  });
}

export function basculerDansListe(cle, id) {
  return modifier((e) => {
    const liste = e[cle];
    e[cle] = liste.includes(id) ? liste.filter((x) => x !== id) : [id, ...liste];
    return e[cle];
  });
}
