// Playlists officielles de YouTube Music lues sans clé API (voir catalogue-youtube.ts et utils/playlistsYoutube.ts).
import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { CLASSEMENTS, GENRES, HUMEURS, type PlaylistYoutube } from '../catalogue-youtube';
import { ACCUEIL } from '../accueil-youtube';
import { api } from '../api';
import { useBibliotheque } from '../store/bibliotheque';
import { useLecteur } from '../store/lecteur';
import { annoncer } from '../store/interface';
import type { Titre } from '../types';
import { Carte, Etagere, EtatVide } from '../components/Elements';
import { Icone } from '../components/Icone';
import { LigneTitre } from '../components/LigneTitre';
import { couleurDeTexte } from '../utils/couleur';
import { titresDePlaylist } from '../utils/playlistsYoutube';

const TOUTES = new Map<string, string>([
  ...CLASSEMENTS,
  ...Object.values(HUMEURS).flat(),
  ...Object.values(GENRES).flat(),
  ...ACCUEIL.flatMap((e) => (e.type === 'playlists' ? e.elements.map((x) => [x.id, x.nom] as PlaylistYoutube) : [])),
]);
const POCHETTES = new Map(ACCUEIL.flatMap((e) => (e.type === 'playlists' ? e.elements.filter((x) => x.pochette).map((x) => [x.id, x.pochette!] as const) : [])));
export const nomPlaylist = (id: string) => TOUTES.get(id) ?? 'Playlist YouTube Music';

// Couverture générée : dégradé + nom, dans l'esprit Higgsfield.
export function CouverturePlaylist({ nom }: { nom: string }) {
  return (
    <div className="couverture-playlist" style={{ '--couleur': couleurDeTexte(nom) } as React.CSSProperties} aria-hidden="true">
      <span>{nom}</span>
    </div>
  );
}

function useTitresPlaylist(id: string, max: number) {
  const [etat, setEtat] = useState<{ phase: 'chargement' | 'ok' | 'erreur'; titres: Titre[] }>({ phase: 'chargement', titres: [] });
  useEffect(() => {
    let actif = true;
    setEtat({ phase: 'chargement', titres: [] });
    titresDePlaylist(id, max)
      .then((titres) => actif && setEtat({ phase: titres.length ? 'ok' : 'erreur', titres }))
      .catch(() => actif && setEtat({ phase: 'erreur', titres: [] }));
    return () => {
      actif = false;
    };
  }, [id, max]);
  return etat;
}

export function CartePlaylistYoutube({ playlist: [id, nom], sousTitre = 'Playlist • YouTube Music', pochette }: { playlist: PlaylistYoutube; sousTitre?: string; pochette?: string | null }) {
  const lire = useLecteur((s) => s.lire);
  const lancer = async () => {
    annoncer(`Chargement de ${nom}`);
    const titres = await titresDePlaylist(id, 50);
    if (titres.length) lire(titres.map((t) => t.id), 0, { libelle: nom, lien: `/youtube/playlist/${id}` });
    else annoncer('Playlist indisponible');
  };
  const image = pochette ?? POCHETTES.get(id);
  return (
    <Carte
      lien={`/youtube/playlist/${id}`}
      titre={nom}
      sousTitre={sousTitre}
      pochette={image}
      visuel={image ? undefined : <CouverturePlaylist nom={nom} />}
      onLire={lancer}
    />
  );
}

// Étagère de cartes de playlists.
export function EtagerePlaylists({ titre, surtitre, playlists }: { titre: string; surtitre?: string; playlists: PlaylistYoutube[] }) {
  return (
    <Etagere titre={titre} surtitre={surtitre}>
      {playlists.map((p) => <CartePlaylistYoutube key={p[0]} playlist={p} />)}
    </Etagere>
  );
}

// Grille de titres tirée d'une playlist (ex. "Sélection rapide" = Top 100 France).
export function GrilleTitresPlaylist({ titre, surtitre, id, max = 12 }: { titre: string; surtitre?: string; id: string; max?: number }) {
  const etat = useTitresPlaylist(id, max);
  const lire = useLecteur((s) => s.lire);
  const ids = etat.titres.map((t) => t.id);
  const source = { libelle: titre, lien: `/youtube/playlist/${id}` };
  return (
    <section className="etagere">
      <header className="etagere-entete">
        <div>
          {surtitre && <div className="etagere-surtitre">{surtitre}</div>}
          <h2 className="etagere-titre">{titre}</h2>
        </div>
        {ids.length > 0 && (
          <div className="etagere-actions">
            <button type="button" className="bouton-secondaire" onClick={() => lire(ids, 0, source)}>Tout lire</button>
          </div>
        )}
      </header>
      {etat.phase === 'chargement' && <div className="squelette-liste">{Array.from({ length: 8 }, (_, i) => <div key={i} />)}</div>}
      {etat.phase === 'erreur' && <div className="yt-message erreur"><Icone nom="info" taille={20} /> Impossible de charger cette playlist pour le moment.</div>}
      {etat.phase === 'ok' && (
        <div className="grille-titres">
          {etat.titres.map((t, i) => <LigneTitre key={t.id} titre={t} onLire={() => lire(ids, i, source)} />)}
        </div>
      )}
    </section>
  );
}

export function PagePlaylistYoutube() {
  const { id = '' } = useParams();
  const nom = nomPlaylist(id);
  const etat = useTitresPlaylist(id, 50);
  const lire = useLecteur((s) => s.lire);
  const ids = etat.titres.map((t) => t.id);
  const source = { libelle: nom, lien: `/youtube/playlist/${id}` };
  return (
    <div className="page page-collection" style={{ '--teinte': couleurDeTexte(nom) } as React.CSSProperties}>
      <div className="collection">
        <aside className="collection-entete">
          <div className="collection-pochette">
            {POCHETTES.get(id) ? <img className="pochette" src={POCHETTES.get(id)} alt="" /> : <CouverturePlaylist nom={nom} />}
          </div>
          <h1 className="collection-nom">{nom}</h1>
          <div className="collection-meta">Playlist • YouTube Music</div>
          <div className="collection-details">{etat.phase === 'ok' ? `${ids.length} titres` : 'Chargement…'}</div>
          <div className="collection-actions">
            <button type="button" className="bouton-secondaire" disabled={!ids.length} onClick={() => lire(ids, 0, source, { melanger: true })}>
              <Icone nom="aleatoire" taille={20} /> Aléatoire
            </button>
            <button type="button" className="gros-bouton-lecture" aria-label={`Lire ${nom}`} disabled={!ids.length} onClick={() => lire(ids, 0, source, { melanger: false })}>
              <Icone nom="lecture" taille={36} />
            </button>
          </div>
        </aside>
        <div className="collection-titres">
          {etat.phase === 'chargement' && <div className="squelette-liste">{Array.from({ length: 10 }, (_, i) => <div key={i} />)}</div>}
          {etat.phase === 'erreur' && <EtatVide icone="info" titre="Playlist indisponible" texte="YouTube n'a pas renvoyé le contenu de cette playlist." />}
          {etat.titres.map((t, i) => <LigneTitre key={t.id} titre={t} onLire={() => lire(ids, i, source, { melanger: false })} />)}
        </div>
      </div>
    </div>
  );
}

// Page d'une humeur ou d'un genre : toutes ses playlists.
export function PageCategorieYoutube() {
  const { nom = '' } = useParams();
  const playlists = HUMEURS[nom] ?? GENRES[nom] ?? [];
  if (!playlists.length) return <EtatVide icone="humeur" titre="Catégorie introuvable" />;
  return (
    <div className="page">
      <div className="sur-titre">{HUMEURS[nom] ? 'Humeur' : 'Genre'}</div>
      <h1 className="titre-geant">{nom}</h1>
      <GrilleTitresPlaylist titre="À écouter maintenant" id={playlists[0][0]} />
      <div className="grille-cartes">{playlists.map((p) => <CartePlaylistYoutube key={p[0]} playlist={p} />)}</div>
    </div>
  );
}

export function TuilesCategories() {
  const noms = [...Object.keys(HUMEURS), ...Object.keys(GENRES)];
  return (
    <div className="tuiles-genres">
      {noms.map((n) => (
        <Link key={n} to={`/youtube/categorie/${encodeURIComponent(n)}`} className="tuile-genre" style={{ '--couleur': couleurDeTexte(n) } as React.CSSProperties}>
          <span>{n}</span>
        </Link>
      ))}
    </div>
  );
}

// Grille de titres à partir d'identifiants de vidéos ("Sélection rapide" de l'accueil YouTube Music).
export function GrilleTitresVideos({ titre, surtitre, idsVideos }: { titre: string; surtitre?: string; idsVideos: string[] }) {
  const lire = useLecteur((s) => s.lire);
  const integrer = useBibliotheque((s) => s.integrerYoutube);
  const [titres, setTitres] = useState<Titre[] | null>(null);
  useEffect(() => {
    let actif = true;
    api
      .youtubeInfos(idsVideos)
      .then((t) => {
        integrer(t);
        if (actif) setTitres(t);
      })
      .catch(() => actif && setTitres([]));
    return () => {
      actif = false;
    };
  }, [idsVideos, integrer]);
  const ids = (titres ?? []).map((t) => t.id);
  const source = { libelle: titre };
  return (
    <section className="etagere">
      <header className="etagere-entete">
        <div>
          {surtitre && <div className="etagere-surtitre">{surtitre}</div>}
          <h2 className="etagere-titre">{titre}</h2>
        </div>
        {ids.length > 0 && (
          <div className="etagere-actions">
            <button type="button" className="bouton-secondaire" onClick={() => lire(ids, 0, source)}>Tout lire</button>
          </div>
        )}
      </header>
      {!titres && <div className="squelette-liste">{Array.from({ length: 8 }, (_, i) => <div key={i} />)}</div>}
      {titres && (
        <div className="grille-titres">
          {titres.map((t, i) => <LigneTitre key={t.id} titre={t} onLire={() => lire(ids, i, source)} />)}
        </div>
      )}
    </section>
  );
}
