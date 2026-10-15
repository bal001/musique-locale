// Explorer + sous-pages Nouveautés, Classement, Humeurs et genres, page d'un genre.
import { useMemo } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useBibliotheque } from '../store/bibliotheque';
import { useLecteur } from '../store/lecteur';
import { Etagere, EtatVide } from '../components/Elements';
import { Icone, type NomIcone } from '../components/Icone';
import { LigneTitre } from '../components/LigneTitre';
import { CarteAlbum, CarteArtiste } from './communs';
import { couleurDeTexte } from '../utils/couleur';
import { TendancesYoutube } from './YouTube';
import { CLASSEMENTS } from '../catalogue-youtube';
import { EtagerePlaylists, TuilesCategories } from './PlaylistsYoutube';
import { EtagereArtistesYoutube } from './ArtistesYoutube';

function useGenres() {
  const titres = useBibliotheque((s) => s.listeTitres);
  return useMemo(() => {
    const n = new Map<string, number>();
    titres.forEach((t) => t.genre && n.set(t.genre, (n.get(t.genre) || 0) + 1));
    return [...n.entries()].sort((a, b) => b[1] - a[1]).map(([nom, nb]) => ({ nom, nb }));
  }, [titres]);
}

function useClassement(max = 50) {
  const titres = useBibliotheque((s) => s.listeTitres);
  const lectures = useBibliotheque((s) => s.utilisateur.lectures);
  return useMemo(() => titres.filter((t) => lectures[t.id]).sort((a, b) => lectures[b.id] - lectures[a.id]).slice(0, max), [titres, lectures, max]);
}

const BOUTONS: { lien: string; libelle: string; icone: NomIcone }[] = [
  { lien: '/nouveautes', libelle: 'Nouveautés', icone: 'nouveautes' },
  { lien: '/classement', libelle: 'Classement', icone: 'tendance' },
  { lien: '/genres', libelle: 'Humeurs et genres', icone: 'humeur' },
];

export function Explorer() {
  const albums = useBibliotheque((s) => s.listeAlbums);
  const recents = useMemo(() => [...albums].sort((a, b) => b.ajouteLe - a.ajouteLe).slice(0, 20), [albums]);
  const genres = useGenres();
  const top = useClassement(10);
  const lire = useLecteur((s) => s.lire);

  return (
    <div className="page">
      <h1 className="titre-geant">Explorer</h1>
      <div className="explorer-boutons">
        {BOUTONS.map((b) => (
          <Link key={b.lien} to={b.lien} className="explorer-bouton">
            <Icone nom={b.icone} />
            <span>{b.libelle}</span>
          </Link>
        ))}
      </div>

      <TendancesYoutube max={20} />
      <EtagerePlaylists titre="Classements" surtitre="YouTube Music · France" playlists={CLASSEMENTS} />
      <EtagereArtistesYoutube />
      <section className="etagere">
        <h2 className="etagere-titre">Humeurs et genres</h2>
        <TuilesCategories />
      </section>

      <Etagere titre="Nouveaux albums et singles" action={<Link className="bouton-secondaire" to="/nouveautes">Plus</Link>} vide={!recents.length}>
        {recents.map((a) => <CarteAlbum key={a.id} album={a} />)}
      </Etagere>

      {genres.length > 0 && (
        <section className="etagere">
          <header className="etagere-entete">
            <h2 className="etagere-titre">Humeurs et genres</h2>
            <div className="etagere-actions"><Link className="bouton-secondaire" to="/genres">Plus</Link></div>
          </header>
          <TuilesGenres genres={genres.slice(0, 12)} />
        </section>
      )}

      {top.length > 0 && (
        <section className="etagere">
          <header className="etagere-entete">
            <div>
              <div className="etagere-surtitre">D'après vos écoutes</div>
              <h2 className="etagere-titre">Les plus écoutés</h2>
            </div>
            <div className="etagere-actions"><Link className="bouton-secondaire" to="/classement">Plus</Link></div>
          </header>
          <div className="grille-titres">
            {top.map((t, i) => (
              <div key={t.id} className="rang">
                <span className="rang-numero">{i + 1}</span>
                <LigneTitre titre={t} details="complet" onLire={() => lire(top.map((x) => x.id), i, { libelle: 'Les plus écoutés', lien: '/classement' })} />
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}

function TuilesGenres({ genres }: { genres: { nom: string; nb: number }[] }) {
  return (
    <div className="tuiles-genres">
      {genres.map((g) => (
        <Link key={g.nom} to={`/genre/${encodeURIComponent(g.nom)}`} className="tuile-genre" style={{ '--couleur': couleurDeTexte(g.nom) } as React.CSSProperties}>
          <span>{g.nom}</span>
          <small>{g.nb}</small>
        </Link>
      ))}
    </div>
  );
}

export function Genres() {
  const genres = useGenres();
  return (
    <div className="page">
      <h1 className="titre-geant">Humeurs et genres</h1>
      {genres.length ? <TuilesGenres genres={genres} /> : <EtatVide icone="humeur" titre="Aucun genre" texte="Les genres proviennent des tags de vos fichiers audio." />}
    </div>
  );
}

export function Genre() {
  const { nom = '' } = useParams();
  const { listeTitres, listeAlbums, listeArtistes } = useBibliotheque();
  const lire = useLecteur((s) => s.lire);
  const titres = listeTitres.filter((t) => t.genre === nom);
  const albums = listeAlbums.filter((a) => a.genre === nom);
  const artistes = listeArtistes.filter((a) => a.genres.includes(nom));
  const ids = titres.map((t) => t.id);
  const source = { libelle: `Mix ${nom}`, lien: `/genre/${encodeURIComponent(nom)}` };
  return (
    <div className="page">
      <div className="sur-titre">Genre</div>
      <h1 className="titre-geant">{nom}</h1>
      <div className="rangee-boutons">
        <button type="button" className="bouton-principal" onClick={() => lire(ids, 0, source, { melanger: true })} disabled={!ids.length}>
          <Icone nom="aleatoire" taille={20} /> Lecture aléatoire
        </button>
      </div>
      <Etagere titre="Albums" vide={!albums.length}>{albums.map((a) => <CarteAlbum key={a.id} album={a} />)}</Etagere>
      <Etagere titre="Artistes" vide={!artistes.length}>{artistes.map((a) => <CarteArtiste key={a.id} artiste={a} />)}</Etagere>
      <section className="etagere">
        <h2 className="etagere-titre">Titres</h2>
        <div className="liste-titres">
          {titres.map((t, i) => <LigneTitre key={t.id} titre={t} onLire={() => lire(ids, i, source)} />)}
        </div>
      </section>
    </div>
  );
}

export function Nouveautes() {
  const albums = useBibliotheque((s) => s.listeAlbums);
  const tri = useMemo(() => [...albums].sort((a, b) => b.ajouteLe - a.ajouteLe), [albums]);
  return (
    <div className="page">
      <h1 className="titre-geant">Nouveautés</h1>
      <p className="sous-titre-page">Les derniers albums et singles ajoutés à votre bibliothèque.</p>
      <div className="grille-cartes">{tri.map((a) => <CarteAlbum key={a.id} album={a} />)}</div>
    </div>
  );
}

export function Classement() {
  const top = useClassement(100);
  const lire = useLecteur((s) => s.lire);
  const lectures = useBibliotheque((s) => s.utilisateur.lectures);
  const albums = useBibliotheque((s) => s.albums);
  const topAlbums = useMemo(() => {
    const n = new Map<string, number>();
    top.forEach((t) => n.set(t.idAlbum, (n.get(t.idAlbum) || 0) + lectures[t.id]));
    return [...n.entries()].sort((a, b) => b[1] - a[1]).map(([id]) => albums[id]).filter(Boolean);
  }, [top, lectures, albums]);

  if (!top.length) return <div className="page"><h1 className="titre-geant">Classement</h1><EtatVide icone="tendance" titre="Pas encore de classement" texte="Écoutez quelques titres : le classement se construit à partir de vos lectures." /></div>;
  return (
    <div className="page">
      <h1 className="titre-geant">Classement</h1>
      <Etagere titre="Albums les plus écoutés" vide={!topAlbums.length}>{topAlbums.map((a) => <CarteAlbum key={a.id} album={a} />)}</Etagere>
      <section className="etagere">
        <h2 className="etagere-titre">Top titres</h2>
        <div className="liste-titres">
          {top.map((t, i) => (
            <div key={t.id} className="rang">
              <span className="rang-numero">{i + 1}</span>
              <LigneTitre titre={t} details="lectures" onLire={() => lire(top.map((x) => x.id), i, { libelle: 'Top titres', lien: '/classement' })} />
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
