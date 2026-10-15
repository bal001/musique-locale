// Cartes prêtes à l'emploi pour albums, artistes, playlists et mixes.
import { useBibliotheque } from '../store/bibliotheque';
import { useLecteur } from '../store/lecteur';
import type { Album, Artiste, Playlist } from '../types';
import { menuAlbum, menuArtiste, menuPlaylist, ouvrirMenuDepuis } from '../utils/actions';
import { joindre, nbTitres } from '../utils/format';
import { mixArtiste } from '../utils/similaires';
import { Carte } from '../components/Elements';

export function CarteAlbum({ album: a, sousTitre }: { album: Album; sousTitre?: string }) {
  const lire = useLecteur((s) => s.lire);
  const enLecture = useLecteur((s) => s.enLecture && s.source?.lien === `/album/${a.id}`);
  return (
    <Carte
      lien={`/album/${a.id}`}
      pochette={a.pochette}
      titre={a.titre}
      sousTitre={sousTitre ?? joindre(a.type, a.artiste, a.annee)}
      enLecture={enLecture}
      onLire={() => lire(a.titres, 0, { libelle: a.titre, lien: `/album/${a.id}` }, { melanger: false })}
      onMenu={(e) => ouvrirMenuDepuis(e, menuAlbum(a.id))}
    />
  );
}

export function CarteArtiste({ artiste: a }: { artiste: Artiste }) {
  const lire = useLecteur((s) => s.lire);
  return (
    <Carte
      rond
      lien={`/artiste/${a.id}`}
      pochette={a.pochette}
      titre={a.nom}
      sousTitre={joindre('Artiste', nbTitres(a.titres.length))}
      onLire={() => lire(mixArtiste(a.id), 0, { libelle: `Mix – ${a.nom}`, lien: `/artiste/${a.id}` })}
      onMenu={(e) => ouvrirMenuDepuis(e, menuArtiste(a.id))}
    />
  );
}

export function CartePlaylist({ playlist: p }: { playlist: Pick<Playlist, 'id' | 'nom' | 'titres'> & { sousTitre?: string } }) {
  const lire = useLecteur((s) => s.lire);
  const titres = useBibliotheque((s) => s.titres);
  const lien = `/playlist/${p.id}`;
  return (
    <Carte
      lien={lien}
      pochette={titres[p.titres[0]]?.pochette}
      titre={p.nom}
      sousTitre={p.sousTitre ?? joindre('Playlist', nbTitres(p.titres.length))}
      onLire={p.titres.length ? () => lire(p.titres, 0, { libelle: p.nom, lien }) : undefined}
      onMenu={(e) => ouvrirMenuDepuis(e, menuPlaylist(p.id, p.titres))}
    />
  );
}

// Titres J'aime (playlist automatique)
export function useTitresJaime() {
  const jaime = useBibliotheque((s) => s.utilisateur.jaime);
  const titres = useBibliotheque((s) => s.titres);
  return Object.keys(jaime).filter((id) => jaime[id] === 1 && titres[id]);
}
