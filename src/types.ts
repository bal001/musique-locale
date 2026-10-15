// Modèle de données partagé avec le serveur (voir server/scanner.mjs et server/stockage.mjs).

export interface Titre {
  id: string;             // fichier local : hash du chemin ; YouTube : "yt:<idVideo>"
  source?: 'local' | 'youtube';
  idVideo?: string;
  titre: string;
  artiste: string;        // texte affiché, ex. "Pixelle feat. Néon Boulevard"
  artistes: string[];     // noms séparés
  idsArtistes: string[];
  album: string;
  idAlbum: string;
  artisteAlbum: string;
  annee: number | null;
  genre: string | null;
  piste: number | null;
  disque: number | null;
  duree: number;          // secondes
  pochette: string | null; // id de pochette locale, ou URL complète (miniature YouTube)
  paroles: 'lrc' | 'tag' | null;
  ajouteLe: number;
  video?: boolean;          // clip téléchargé (.mp4) : lu avec l'image
  origineYoutube?: string;  // téléchargé depuis cette vidéo YouTube
}

export interface Album {
  id: string;
  titre: string;
  artiste: string;
  idArtiste: string;
  annee: number | null;
  genre: string | null;
  pochette: string | null;
  titres: string[];
  type: 'Album' | 'Single';
  duree: number;
  ajouteLe: number;
}

export interface Artiste {
  id: string;
  nom: string;
  albums: string[];
  titres: string[];
  pochette: string | null;
  genres: string[];
}

export interface Bibliotheque {
  genereLe: number;
  titres: Titre[];
  albums: Album[];
  artistes: Artiste[];
}

export interface Playlist {
  id: string;
  nom: string;
  description: string;
  titres: string[];
  creeLe: number;
  modifieLe: number;
}

export interface EtatUtilisateur {
  jaime: Record<string, 1 | -1>;
  playlists: Playlist[];
  albumsEnregistres: string[];
  artistesSuivis: string[];
  historique: { id: string; t: number }[];
  lectures: Record<string, number>;
  reglages: { dossiers: string[]; lectureAuto: boolean; youtubeConfigure?: boolean };
}

export interface Paroles {
  synchronisees: boolean;
  lignes: { t: number | null; texte: string }[];
  source?: string | null; // « fichier local », « LRCLIB », « Source : LyricFind »…
}

export type FormatTelechargement = 'audio' | 'video';

export interface Telechargement {
  idVideo: string;
  format: FormatTelechargement;
  titre: string;
  artiste: string;
  etat: 'attente' | 'encours' | 'fini' | 'erreur';
  progression: number;
  erreur: string | null;
}

export type Repetition = 'aucune' | 'tout' | 'un';

// D'où vient la lecture en cours ("Lecture à partir de …" dans la file d'attente).
export interface SourceLecture {
  libelle: string;
  lien?: string;
}
