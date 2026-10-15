// Artistes YouTube : regroupés à partir de tous les titres rencontrés dans les playlists officielles.
import { useMemo } from 'react';
import { useParams } from 'react-router-dom';
import { useBibliotheque } from '../store/bibliotheque';
import { useLecteur } from '../store/lecteur';
import type { Titre } from '../types';
import { Carte, Etagere, EtatVide } from '../components/Elements';
import { Icone } from '../components/Icone';
import { LigneTitre } from '../components/LigneTitre';
import { normaliser } from '../utils/recherche';

// "GIMS & La Mano 1.9" → "GIMS" ; "Keblack & Franglish" → "Keblack"
export const artistePrincipal = (t: Pick<Titre, 'artiste'>) =>
  t.artiste.split(/\s*(?:,|&|\bfeat\.?|\bft\.?|\bx\b|\(|\bavec\b)\s*/i)[0].trim() || t.artiste;

export const lienArtisteYoutube = (nom: string) => `/youtube/artiste/${encodeURIComponent(nom)}`;

export function useArtistesYoutube() {
  const liste = useBibliotheque((s) => s.listeYoutube);
  return useMemo(() => {
    const groupes = new Map<string, { nom: string; titres: Titre[] }>();
    for (const t of liste) {
      const nom = artistePrincipal(t);
      const cle = normaliser(nom);
      if (!cle) continue;
      if (!groupes.has(cle)) groupes.set(cle, { nom, titres: [] });
      groupes.get(cle)!.titres.push(t);
    }
    return [...groupes.values()].sort((a, b) => b.titres.length - a.titres.length || a.nom.localeCompare(b.nom));
  }, [liste]);
}

export function CarteArtisteYoutube({ nom, titres }: { nom: string; titres: Titre[] }) {
  const lire = useLecteur((s) => s.lire);
  return (
    <Carte
      rond
      lien={lienArtisteYoutube(nom)}
      pochette={titres[0]?.pochette}
      titre={nom}
      sousTitre={`Artiste • ${titres.length} titre${titres.length > 1 ? 's' : ''}`}
      onLire={() => lire(titres.map((t) => t.id), 0, { libelle: nom, lien: lienArtisteYoutube(nom) })}
    />
  );
}

export function EtagereArtistesYoutube({ titre = 'Artistes du moment', max = 30 }: { titre?: string; max?: number }) {
  const artistes = useArtistesYoutube();
  return (
    <Etagere titre={titre} surtitre="Trouvés dans les playlists YouTube Music" vide={!artistes.length}>
      {artistes.slice(0, max).map((a) => <CarteArtisteYoutube key={a.nom} {...a} />)}
    </Etagere>
  );
}

export function PageArtisteYoutube() {
  const { nom = '' } = useParams();
  const artistes = useArtistesYoutube();
  const lire = useLecteur((s) => s.lire);
  const a = artistes.find((x) => normaliser(x.nom) === normaliser(nom));
  if (!a) return <EtatVide icone="artiste" titre={nom} texte="Aucun titre de cet artiste n'a encore été trouvé dans les playlists ouvertes." />;
  const ids = a.titres.map((t) => t.id);
  const source = { libelle: a.nom, lien: lienArtisteYoutube(a.nom) };
  return (
    <div className="page page-artiste">
      <header className="artiste-heros" style={{ '--image': a.titres[0]?.pochette ? `url(${a.titres[0].pochette})` : 'none' } as React.CSSProperties}>
        <div className="artiste-heros-contenu">
          <div className="sur-titre">Artiste • {a.titres.length} titre{a.titres.length > 1 ? 's' : ''}</div>
          <h1 className="titre-geant">{a.nom}</h1>
          <div className="rangee-boutons">
            <button type="button" className="bouton-principal" onClick={() => lire(ids, 0, source, { melanger: true })}>
              <Icone nom="aleatoire" taille={20} /> Aléatoire
            </button>
            <button type="button" className="bouton-secondaire" onClick={() => lire(ids, 0, source, { melanger: false })}>
              <Icone nom="lecture" taille={20} /> Tout lire
            </button>
          </div>
        </div>
      </header>
      <section className="etagere">
        <h2 className="etagere-titre">Titres</h2>
        <div className="liste-titres">
          {a.titres.map((t, i) => <LigneTitre key={t.id} titre={t} onLire={() => lire(ids, i, source, { melanger: false })} />)}
        </div>
      </section>
    </div>
  );
}
