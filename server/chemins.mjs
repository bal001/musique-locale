// Chemins partagés par le serveur.
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const RACINE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const DOSSIER_DONNEES = path.join(RACINE, 'donnees');
export const DOSSIER_POCHETTES = path.join(DOSSIER_DONNEES, 'pochettes');
export const DOSSIER_MUSIQUE_DEFAUT = path.join(RACINE, 'musique');
export const DOSSIER_DIST = path.join(RACINE, 'dist');

export const PORT = Number(process.env.PORT || 4317);
