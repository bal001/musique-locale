// Page artiste : grand en-tête, Aléatoire / Mix / S'abonner, titres, albums, singles, apparitions.
import { useMemo } from 'react';
import { useParams } from 'react-router-dom';
import { urlPochette } from '../api';
import { useBibliotheque } from '../store/bibliotheque';
import { useLecteur } from '../store/lecteur';
import { Etagere, EtatVide } from '../components/Elements';
import { Icone } from '../components/Icone';
import { LigneTitre } from '../components/LigneTitre';
import { mixArtiste } from '../utils/similaires';
import { joindre, nbTitres } from '../utils/format';
import { CarteAlbum, CarteArtiste } from './communs';

export function PageArtiste() {
  const { id = '' } = useParams();
  const { artistes, albums, titres, listeAlbums, listeArtistes, utilisateur, basculerArtiste } = useBibliotheque();
  const lire = useLecteur((s) => s.lire);
  const a = artistes[id];

  const populaires = useMemo(() => {
    if (!a) return [];
    return [...a.titres].sort((x, y) => (utilisateur.lectures[y] || 0) - (utilisateur.lectures[x] || 0)).slice(0, 5).map((t) => titres[t]).filter(Boolean);
  }, [a, utilisateur.lectures, titres]);

  if (!a) return <EtatVide icone="artiste" titre="Artiste introuvable" />;
  const siens = a.albums.map((x) => albums[x]).filter(Boolean);
  const longs = siens.filter((x) => x.type === 'Album');
  const singles = siens.filter((x) => x.type === 'Single');
  const apparitions = listeAlbums.filter((x) => x.idArtiste !== id && x.titres.some((t) => titres[t]?.idsArtistes.includes(id)));
  const similaires = listeArtistes.filter((x) => x.id !== id && x.genres.some((g) => a.genres.includes(g)));
  const suivi = utilisateur.artistesSuivis.includes(id);
  const source = { libelle: a.nom, lien: `/artiste/${id}` };

  return (
    <div className="page page-artiste">
      <header className="artiste-heros" style={{ '--image': a.pochette ? `url(${urlPochette(a.pochette)})` : 'none' } as React.CSSProperties}>
        <div className="artiste-heros-contenu">
          <div className="sur-titre">{joindre('Artiste', a.genres.join(', '), nbTitres(a.titres.length))}</div>
          <h1 className="titre-geant">{a.nom}</h1>
          <div className="rangee-boutons">
            <button type="button" className="bouton-principal" onClick={() => lire(a.titres, 0, source, { melanger: true })}>
              <Icone nom="aleatoire" taille={20} /> Aléatoire
            </button>
            <button type="button" className="bouton-secondaire" onClick={() => lire(mixArtiste(id), 0, { libelle: `Mix – ${a.nom}`, lien: source.lien })}>
              <Icone nom="mix" taille={20} /> Mix
            </button>
            <button type="button" className={`bouton-secondaire${suivi ? ' actif' : ''}`} onClick={() => basculerArtiste(id)}>
              {suivi ? <><Icone nom="coche" taille={20} /> Abonné</> : "S'abonner"}
            </button>
          </div>
        </div>
      </header>

      {populaires.length > 0 && (
        <section className="etagere">
          <h2 className="etagere-titre">Titres</h2>
          <div className="liste-titres">
            {populaires.map((t, i) => <LigneTitre key={t.id} titre={t} details="lectures" onLire={() => lire(populaires.map((x) => x.id), i, source)} />)}
          </div>
        </section>
      )}
      <Etagere titre="Albums" vide={!longs.length}>{longs.map((x) => <CarteAlbum key={x.id} album={x} sousTitre={joindre(x.type, x.annee)} />)}</Etagere>
      <Etagere titre="Singles" vide={!singles.length}>{singles.map((x) => <CarteAlbum key={x.id} album={x} sousTitre={joindre(x.type, x.annee)} />)}</Etagere>
      <Etagere titre="Apparaît sur" vide={!apparitions.length}>{apparitions.map((x) => <CarteAlbum key={x.id} album={x} />)}</Etagere>
      <Etagere titre="Les fans aiment aussi" vide={!similaires.length}>{similaires.map((x) => <CarteArtiste key={x.id} artiste={x} />)}</Etagere>
    </div>
  );
}
