// Actions partagées des menus "⋮" (titre, album, artiste, playlist), comme dans YouTube Music.
import type { NavigateFunction } from 'react-router-dom';
import { estYoutube, lienYoutube } from '../api';
import { useBibliotheque } from '../store/bibliotheque';
import { useInterface, type ElementMenu } from '../store/interface';
import { useLecteur } from '../store/lecteur';
import { useTelechargements, versionsTelechargees } from '../store/telechargements';
import { mixArtiste } from './similaires';

let naviguer: NavigateFunction = () => {};
export const definirNavigation = (n: NavigateFunction) => (naviguer = n);
export const aller = (chemin: string) => {
  useLecteur.getState().ouvrirPage(false);
  naviguer(chemin);
};

const lecteur = () => useLecteur.getState();
const biblio = () => useBibliotheque.getState();
const ui = () => useInterface.getState();

export function ouvrirMenuDepuis(e: React.MouseEvent, elements: ElementMenu[]) {
  e.preventDefault();
  e.stopPropagation();
  const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
  const viaClicDroit = e.type === 'contextmenu';
  ui().ouvrirMenu(viaClicDroit ? e.clientX : r.right, viaClicDroit ? e.clientY : r.bottom, elements);
}

export function menuTitre(id: string, extra: ElementMenu[] = []): ElementMenu[] {
  const t = biblio().titres[id];
  if (!t) return extra;
  const aime = biblio().utilisateur.jaime[id] === 1;
  if (estYoutube(t)) {
    return [
      { libelle: 'Lire ensuite', icone: 'lireEnsuite', action: () => lecteur().lireEnsuite([id]) },
      { libelle: "Ajouter à la file d'attente", icone: 'file', action: () => lecteur().ajouterALaFile([id]) },
      { libelle: aime ? 'Retirer des titres J\'aime' : 'Ajouter aux titres J\'aime', icone: aime ? 'jaimePlein' : 'jaime', action: () => biblio().noterJaime(id, aime ? 0 : 1) },
      { libelle: 'Enregistrer dans une playlist', icone: 'ajouterPlaylist', action: () => ui().ouvrirDialogue({ type: 'ajouter-playlist', titres: [id] }) },
      { libelle: 'Rechercher cet artiste', icone: 'recherche', action: () => aller(`/recherche?q=${encodeURIComponent(t.artiste)}`) },
      ...menuTelechargement(id),
      { libelle: 'Ouvrir dans YouTube Music', icone: 'note', action: () => window.open(lienYoutube(t), '_blank', 'noopener') },
      ...extra,
    ];
  }
  const elements: ElementMenu[] = [
    { libelle: 'Lire ensuite', icone: 'lireEnsuite', action: () => lecteur().lireEnsuite([id]) },
    { libelle: "Ajouter à la file d'attente", icone: 'file', action: () => lecteur().ajouterALaFile([id]) },
    { libelle: 'Lancer le mix', icone: 'mix', action: () => lecteur().lire([id, ...mixArtiste(t.idsArtistes[0]).filter((x) => x !== id)], 0, { libelle: `Mix – ${t.titre}` }) },
    { libelle: aime ? 'Retirer des titres J\'aime' : 'Ajouter aux titres J\'aime', icone: aime ? 'jaimePlein' : 'jaime', action: () => biblio().noterJaime(id, aime ? 0 : 1) },
    { libelle: 'Enregistrer dans une playlist', icone: 'ajouterPlaylist', action: () => ui().ouvrirDialogue({ type: 'ajouter-playlist', titres: [id] }) },
    { libelle: "Accéder à l'album", icone: 'album', action: () => aller(`/album/${t.idAlbum}`) },
    ...t.idsArtistes.map((a, i) => ({ libelle: `Accéder à l'artiste${t.idsArtistes.length > 1 ? ` (${t.artistes[i]})` : ''}`, icone: 'artiste', action: () => aller(`/artiste/${a}`) })),
  ];
  if (t.origineYoutube) elements.push(...menuTelechargement(id));
  return [...elements, ...extra];
}

// Télécharger l'audio ou le clip d'un titre YouTube, ou supprimer ce qui a été téléchargé.
export function menuTelechargement(id: string): ElementMenu[] {
  const t = biblio().titres[id];
  const idVideo = t?.idVideo ?? t?.origineYoutube;
  if (!t || !idVideo) return [];
  const versions = versionsTelechargees(idVideo);
  const original = biblio().titres[`yt:${idVideo}`] ?? t;
  const dl = useTelechargements.getState();
  const elements: ElementMenu[] = [];
  if (original.idVideo && !versions.some((v) => !v.video)) elements.push({ libelle: 'Télécharger', icone: 'telecharger', action: () => dl.telecharger(original, 'audio') });
  if (original.idVideo && !versions.some((v) => v.video)) elements.push({ libelle: 'Télécharger le clip vidéo', icone: 'video', action: () => dl.telecharger(original, 'video') });
  for (const v of versions) elements.push({ libelle: v.video ? 'Supprimer le clip téléchargé' : 'Supprimer le téléchargement', icone: 'supprimer', action: () => dl.supprimer(v) });
  return elements;
}

export function menuAlbum(id: string): ElementMenu[] {
  const a = biblio().albums[id];
  if (!a) return [];
  const enregistre = biblio().utilisateur.albumsEnregistres.includes(id);
  return [
    { libelle: 'Lecture aléatoire', icone: 'aleatoire', action: () => lecteur().lire(a.titres, 0, { libelle: a.titre, lien: `/album/${id}` }, { melanger: true }) },
    { libelle: 'Lire ensuite', icone: 'lireEnsuite', action: () => lecteur().lireEnsuite(a.titres) },
    { libelle: "Ajouter à la file d'attente", icone: 'file', action: () => lecteur().ajouterALaFile(a.titres) },
    { libelle: enregistre ? 'Retirer de la bibliothèque' : 'Enregistrer dans la bibliothèque', icone: enregistre ? 'enregistre' : 'enregistrer', action: () => biblio().basculerAlbum(id) },
    { libelle: 'Enregistrer dans une playlist', icone: 'ajouterPlaylist', action: () => ui().ouvrirDialogue({ type: 'ajouter-playlist', titres: a.titres }) },
    { libelle: "Accéder à l'artiste", icone: 'artiste', action: () => aller(`/artiste/${a.idArtiste}`) },
  ];
}

export function menuArtiste(id: string): ElementMenu[] {
  const a = biblio().artistes[id];
  if (!a) return [];
  const suivi = biblio().utilisateur.artistesSuivis.includes(id);
  return [
    { libelle: 'Lecture aléatoire', icone: 'aleatoire', action: () => lecteur().lire(a.titres, 0, { libelle: a.nom, lien: `/artiste/${id}` }, { melanger: true }) },
    { libelle: 'Lancer le mix', icone: 'mix', action: () => lecteur().lire(mixArtiste(id), 0, { libelle: `Mix – ${a.nom}`, lien: `/artiste/${id}` }) },
    { libelle: suivi ? 'Se désabonner' : "S'abonner", icone: suivi ? 'coche' : 'ajouter', action: () => biblio().basculerArtiste(id) },
  ];
}

export function menuPlaylist(id: string, titres: string[]): ElementMenu[] {
  const modifiable = id !== 'jaime';
  return [
    { libelle: 'Lecture aléatoire', icone: 'aleatoire', action: () => lecteur().lire(titres, 0, null, { melanger: true }) },
    { libelle: 'Lire ensuite', icone: 'lireEnsuite', action: () => lecteur().lireEnsuite(titres) },
    { libelle: "Ajouter à la file d'attente", icone: 'file', action: () => lecteur().ajouterALaFile(titres) },
    ...(modifiable
      ? [
          { libelle: 'Modifier la playlist', icone: 'modifier', action: () => ui().ouvrirDialogue({ type: 'modifier-playlist', id }) },
          {
            libelle: 'Supprimer la playlist',
            icone: 'supprimer',
            danger: true,
            action: () =>
              ui().ouvrirDialogue({
                type: 'confirmer',
                message: 'Supprimer définitivement cette playlist ? Les fichiers audio ne sont pas touchés.',
                libelle: 'Supprimer',
                action: () => {
                  biblio().supprimerPlaylist(id);
                  aller('/bibliotheque/playlists');
                },
              }),
          },
        ]
      : []),
  ];
}
