// Bibliothèque (titres/albums/artistes scannés) + état utilisateur (J'aime, playlists, historique).
import { create } from 'zustand';
import { api } from '../api';
import type { Album, Artiste, Bibliotheque, EtatUtilisateur, Playlist, Titre } from '../types';
import { notifier } from './interface';

interface EtatBibliotheque {
  charge: boolean;
  erreur: string | null;
  titres: Record<string, Titre>;
  albums: Record<string, Album>;
  artistes: Record<string, Artiste>;
  listeTitres: Titre[];
  listeAlbums: Album[];
  listeArtistes: Artiste[];
  listeYoutube: Titre[];        // titres YouTube déjà rencontrés (recherche, tendances, liens)
  utilisateur: EtatUtilisateur;

  integrerYoutube: (titres: Titre[]) => void;
  charger: () => Promise<void>;
  rescanner: () => Promise<void>;
  actualiser: (b?: Bibliotheque) => Promise<void>;
  noterJaime: (id: string, valeur: 1 | -1 | 0) => Promise<void>;
  enregistrerLecture: (id: string) => Promise<void>;
  viderHistorique: () => Promise<void>;
  retirerDeLHistorique: (id: string) => Promise<void>;
  basculerAlbum: (id: string) => Promise<void>;
  basculerArtiste: (id: string) => Promise<void>;
  creerPlaylist: (nom: string, description?: string, titres?: string[]) => Promise<Playlist>;
  ajouterAPlaylist: (idPlaylist: string, ids: string[]) => Promise<void>;
  modifierPlaylist: (id: string, changements: Partial<Pick<Playlist, 'nom' | 'description' | 'titres'>>) => Promise<void>;
  retirerDePlaylist: (idPlaylist: string, index: number) => Promise<void>;
  supprimerPlaylist: (id: string) => Promise<void>;
  sauverReglages: (r: Partial<EtatUtilisateur['reglages']> & { cleYoutube?: string }) => Promise<string[]>;
}

const utilisateurVide: EtatUtilisateur = {
  jaime: {},
  playlists: [],
  albumsEnregistres: [],
  artistesSuivis: [],
  historique: [],
  lectures: {},
  reglages: { dossiers: [], lectureAuto: true },
};

const indexer = (b: Bibliotheque) => ({
  titres: Object.fromEntries(b.titres.map((t) => [t.id, t])),
  albums: Object.fromEntries(b.albums.map((a) => [a.id, a])),
  artistes: Object.fromEntries(b.artistes.map((a) => [a.id, a])),
  listeTitres: b.titres,
  listeAlbums: b.albums,
  listeArtistes: [...b.artistes].sort((a, z) => a.nom.localeCompare(z.nom)),
});

export const useBibliotheque = create<EtatBibliotheque>((set, get) => {
  const majPlaylist = (p: Playlist) =>
    set((s) => ({ utilisateur: { ...s.utilisateur, playlists: s.utilisateur.playlists.map((x) => (x.id === p.id ? p : x)) } }));

  return {
    charge: false,
    erreur: null,
    titres: {},
    albums: {},
    artistes: {},
    listeTitres: [],
    listeAlbums: [],
    listeArtistes: [],
    listeYoutube: [],
    utilisateur: utilisateurVide,

    integrerYoutube(liste) {
      if (!liste.length) return;
      set((s) => {
        const titres = { ...s.titres };
        const yt = new Map(s.listeYoutube.map((t) => [t.id, t]));
        for (const t of liste) {
          titres[t.id] = { ...titres[t.id], ...t };
          yt.set(t.id, titres[t.id]);
        }
        return { titres, listeYoutube: [...yt.values()] };
      });
    },

    async charger() {
      try {
        const [b, u, yt] = await Promise.all([api.bibliotheque(), api.etat(), api.youtubeConnus().catch(() => ({}))]);
        set({ ...indexer(b), utilisateur: u, charge: true, erreur: null });
        get().integrerYoutube(Object.values(yt));
      } catch (e) {
        set({ erreur: `Impossible de joindre le serveur local (${(e as Error).message}). Lancez « npm run dev ».`, charge: true });
      }
    },

    // Recharge la bibliothèque déjà scannée par le serveur (après un téléchargement, par exemple).
    async actualiser(b) {
      set(indexer(b ?? (await api.bibliotheque())));
      get().integrerYoutube(get().listeYoutube);
    },

    async rescanner() {
      const b = await api.rescanner();
      set(indexer(b));
      get().integrerYoutube(get().listeYoutube);
      notifier(`Bibliothèque actualisée : ${b.titres.length} titres`);
    },

    async noterJaime(id, valeur) {
      // Mise à jour optimiste, comme le bouton "J'aime" de YouTube Music.
      set((s) => {
        const jaime = { ...s.utilisateur.jaime };
        if (valeur) jaime[id] = valeur;
        else delete jaime[id];
        return { utilisateur: { ...s.utilisateur, jaime } };
      });
      const jaime = await api.noterJaime(id, valeur);
      set((s) => ({ utilisateur: { ...s.utilisateur, jaime } }));
      if (valeur === 1) notifier('Ajouté à « Titres J\'aime »');
      else if (valeur === -1) notifier('Merci pour votre avis');
    },

    async enregistrerLecture(id) {
      const r = await api.ajouterHistorique(id);
      set((s) => ({ utilisateur: { ...s.utilisateur, ...r } }));
    },

    async retirerDeLHistorique(id) {
      const r = await api.retirerDeLHistorique(id);
      set((s) => ({ utilisateur: { ...s.utilisateur, ...r } }));
      notifier("Retiré de l'historique");
    },

    async viderHistorique() {
      const r = await api.viderHistorique();
      set((s) => ({ utilisateur: { ...s.utilisateur, ...r } }));
      notifier('Historique effacé');
    },

    async basculerAlbum(id) {
      const albumsEnregistres = await api.basculerAlbum(id);
      set((s) => ({ utilisateur: { ...s.utilisateur, albumsEnregistres } }));
      notifier(albumsEnregistres.includes(id) ? 'Album ajouté à la bibliothèque' : 'Album retiré de la bibliothèque');
    },

    async basculerArtiste(id) {
      const artistesSuivis = await api.basculerArtiste(id);
      set((s) => ({ utilisateur: { ...s.utilisateur, artistesSuivis } }));
      notifier(artistesSuivis.includes(id) ? 'Abonné à l\'artiste' : 'Désabonné de l\'artiste');
    },

    async creerPlaylist(nom, description = '', titres = []) {
      const p = await api.creerPlaylist(nom, description, titres);
      set((s) => ({ utilisateur: { ...s.utilisateur, playlists: [p, ...s.utilisateur.playlists] } }));
      notifier(`Playlist « ${p.nom} » créée`);
      return p;
    },

    async ajouterAPlaylist(idPlaylist, ids) {
      const p = await api.modifierPlaylist(idPlaylist, { ajouter: ids });
      majPlaylist(p);
      notifier(`Enregistré dans « ${p.nom} »`);
    },

    async modifierPlaylist(id, changements) {
      majPlaylist(await api.modifierPlaylist(id, changements));
    },

    async retirerDePlaylist(idPlaylist, index) {
      majPlaylist(await api.modifierPlaylist(idPlaylist, { retirerIndex: index }));
      notifier('Retiré de la playlist');
    },

    async supprimerPlaylist(id) {
      const nom = get().utilisateur.playlists.find((p) => p.id === id)?.nom;
      await api.supprimerPlaylist(id);
      set((s) => ({ utilisateur: { ...s.utilisateur, playlists: s.utilisateur.playlists.filter((p) => p.id !== id) } }));
      notifier(`Playlist « ${nom} » supprimée`);
    },

    async sauverReglages(r) {
      const { reglages, manquants } = await api.sauverReglages(r);
      set((s) => ({ utilisateur: { ...s.utilisateur, reglages } }));
      if (r.dossiers) {
        const b = await api.bibliotheque();
        set(indexer(b));
        get().integrerYoutube(get().listeYoutube);
      }
      return manquants;
    },
  };
});

// Sélecteurs pratiques
export const titresDe = (ids: string[]) => {
  const { titres } = useBibliotheque.getState();
  return ids.map((id) => titres[id]).filter(Boolean);
};
