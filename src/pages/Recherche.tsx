// Résultats de recherche : puces de filtre, carte "meilleur résultat", puis sections.
import { useMemo } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { ressembleLienYoutube, urlPochette } from '../api';
import { useBibliotheque } from '../store/bibliotheque';
import { useLecteur } from '../store/lecteur';
import { EtatVide, Pochette, Puces } from '../components/Elements';
import { Icone } from '../components/Icone';
import { LigneTitre } from '../components/LigneTitre';
import { rechercher, type ResultatRecherche } from '../utils/recherche';
import { useCouleurDominante } from '../utils/couleur';
import { joindre, nbTitres } from '../utils/format';
import { mixArtiste } from '../utils/similaires';
import { CarteAlbum, CarteArtiste } from './communs';
import { ResultatsYoutube } from './YouTube';
import { artistePrincipal } from './ArtistesYoutube';

type Filtre = 'artistes' | 'albums' | 'titres' | 'youtube';
const FILTRES: { valeur: Filtre; libelle: string }[] = [
  { valeur: 'youtube', libelle: 'YouTube' },
  { valeur: 'titres', libelle: 'Titres' },
  { valeur: 'albums', libelle: 'Albums' },
  { valeur: 'artistes', libelle: 'Artistes' },
];

export function PageRecherche() {
  const [params, setParams] = useSearchParams();
  const q = params.get('q') || '';
  const filtre = (params.get('type') as Filtre | null) ?? null;
  const { listeTitres, listeAlbums, listeArtistes, listeYoutube } = useBibliotheque();
  const lire = useLecteur((s) => s.lire);
  // Vos fichiers + tous les titres YouTube déjà indexés depuis les playlists officielles.
  const r = useMemo(
    () => rechercher(q, { titres: [...listeTitres, ...listeYoutube], albums: listeAlbums, artistes: listeArtistes }),
    [q, listeTitres, listeYoutube, listeAlbums, listeArtistes],
  );

  const choisir = (v: Filtre | null) => {
    const p = new URLSearchParams(params);
    if (v) p.set('type', v);
    else p.delete('type');
    setParams(p);
  };

  const idsTitres = r.titres.map((x) => x.titre.id);
  const source = { libelle: `Recherche « ${q} »`, lien: `/recherche?q=${encodeURIComponent(q)}` };

  const youtube = !filtre || filtre === 'youtube';
  // Meilleur résultat : ta musique locale si elle correspond, sinon le premier résultat de la recherche YouTube.
  const meilleurLocal = r.meilleur && !(r.meilleur.type === 'titre' && r.meilleur.titre.source === 'youtube') ? r.meilleur : null;
  return (
    <div className="page page-recherche">
      <Puces options={FILTRES} valeur={filtre} onChange={choisir} />

      {!filtre && meilleurLocal && <MeilleurResultat r={meilleurLocal} />}
      {youtube && (
        <ResultatsYoutube
          q={q}
          complet={filtre === 'youtube'}
          onToutAfficher={() => choisir('youtube')}
          meilleur={!filtre && !meilleurLocal ? (t) => <MeilleurResultat r={{ type: 'titre', score: 1, titre: t }} /> : undefined}
        />
      )}
      {filtre && filtre !== 'youtube' && !r.tous.length && !ressembleLienYoutube(q) && (
        <EtatVide
          icone="recherche"
          titre="Aucun résultat"
          texte={`« ${q} » ne figure ni dans vos fichiers ni dans les ${listeYoutube.length} titres YouTube indexés pour l'instant. L'index s'enrichit en arrière-plan : réessayez dans quelques minutes.`}
        />
      )}

      {(!filtre || filtre === 'titres') && r.titres.length > 0 && (
        <section className="etagere">
          <header className="etagere-entete">
            <h2 className="etagere-titre">Titres</h2>
            {!filtre && r.titres.length > 5 && <button type="button" className="bouton-secondaire" onClick={() => choisir('titres')}>Tout afficher</button>}
          </header>
          <div className="liste-titres">
            {r.titres.slice(0, filtre ? 200 : 5).map((x, i) => <LigneTitre key={x.titre.id} titre={x.titre} onLire={() => lire(idsTitres, i, source)} />)}
          </div>
        </section>
      )}
      {(!filtre || filtre === 'albums') && r.albums.length > 0 && (
        <section className="etagere">
          <header className="etagere-entete">
            <h2 className="etagere-titre">Albums</h2>
            {!filtre && r.albums.length > 6 && <button type="button" className="bouton-secondaire" onClick={() => choisir('albums')}>Tout afficher</button>}
          </header>
          <div className="grille-cartes">{r.albums.slice(0, filtre ? 200 : 6).map((x) => <CarteAlbum key={x.album.id} album={x.album} />)}</div>
        </section>
      )}
      {(!filtre || filtre === 'artistes') && r.artistes.length > 0 && (
        <section className="etagere">
          <h2 className="etagere-titre">Artistes</h2>
          <div className="grille-cartes">{r.artistes.slice(0, filtre ? 200 : 6).map((x) => <CarteArtiste key={x.artiste.id} artiste={x.artiste} />)}</div>
        </section>
      )}
    </div>
  );
}

// Carte teintée par la pochette, avec Aléatoire / Mix et 3 titres à droite (comme sur YouTube Music).
function MeilleurResultat({ r }: { r: ResultatRecherche }) {
  const lire = useLecteur((s) => s.lire);
  const titres = useBibliotheque((s) => s.titres);

  let lien: string, pochette: string | null, nom: string, sous: string, ids: string[], rond = false;
  if (r.type === 'artiste') {
    ({ id: lien, pochette, nom } = { ...r.artiste, id: `/artiste/${r.artiste.id}` });
    sous = joindre('Artiste', nbTitres(r.artiste.titres.length));
    ids = r.artiste.titres;
    rond = true;
  } else if (r.type === 'album') {
    lien = `/album/${r.album.id}`;
    ({ pochette, titre: nom } = r.album);
    sous = joindre(r.album.type, r.album.artiste, r.album.annee);
    ids = r.album.titres;
  } else {
    lien = r.titre.idAlbum ? `/album/${r.titre.idAlbum}` : `/youtube/artiste/${encodeURIComponent(artistePrincipal(r.titre))}`;
    ({ pochette, titre: nom } = r.titre);
    sous = joindre('Titre', r.titre.artiste, r.titre.album);
    ids = [r.titre.id];
  }
  const teinte = useCouleurDominante(urlPochette(pochette));
  const apercu = ids.slice(0, 3).map((id) => titres[id]).filter(Boolean);
  const source = { libelle: nom, lien };

  return (
    <section className="meilleur-resultat" style={{ '--teinte': teinte } as React.CSSProperties}>
      <div className="mr-principal">
        <Link to={lien} className="mr-visuel"><Pochette id={pochette} nom={nom} rond={rond} /></Link>
        <div className="mr-textes">
          <div className="sur-titre">Meilleur résultat</div>
          <Link to={lien} className="mr-nom">{nom}</Link>
          <div className="mr-sous">{sous}</div>
          <div className="rangee-boutons">
            {r.type === 'titre' ? (
              <button type="button" className="bouton-principal" onClick={() => lire(ids, 0, { libelle: nom })}><Icone nom="lecture" taille={20} /> Lire</button>
            ) : (
              <button type="button" className="bouton-principal" onClick={() => lire(ids, 0, source, { melanger: true })}><Icone nom="aleatoire" taille={20} /> Aléatoire</button>
            )}
            {r.type === 'artiste' && (
              <button type="button" className="bouton-secondaire" onClick={() => lire(mixArtiste(r.artiste.id), 0, { libelle: `Mix – ${nom}`, lien })}><Icone nom="mix" taille={20} /> Mix</button>
            )}
          </div>
        </div>
      </div>
      {r.type !== 'titre' && apercu.length > 0 && (
        <div className="mr-titres">
          {apercu.map((t, i) => (
            <button key={t.id} type="button" className="mr-titre" onClick={() => lire(ids, i, source)}>
              <Pochette id={t.pochette} nom={t.titre} />
              <span>
                <b>{t.titre}</b>
                <small>{joindre('Titre', t.artiste)}</small>
              </span>
              <Icone nom="lecture" className="mr-titre-lecture" />
            </button>
          ))}
        </div>
      )}
    </section>
  );
}
