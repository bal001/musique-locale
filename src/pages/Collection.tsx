// Pages Album et Playlist : colonne pochette + actions à gauche, liste des titres à droite
// (mise en page observée sur la page album de YouTube Music).
import type { ReactNode } from 'react';
import { Link, useParams } from 'react-router-dom';
import { urlPochette } from '../api';
import { useBibliotheque } from '../store/bibliotheque';
import { useInterface } from '../store/interface';
import { useLecteur } from '../store/lecteur';
import { BoutonIcone, Etagere, EtatVide, Pochette } from '../components/Elements';
import { Icone } from '../components/Icone';
import { LigneTitre } from '../components/LigneTitre';
import { menuAlbum, menuPlaylist, ouvrirMenuDepuis } from '../utils/actions';
import { useCouleurDominante } from '../utils/couleur';
import { dureeLongue, joindre, nbTitres } from '../utils/format';
import { CarteAlbum, useTitresJaime } from './communs';

interface EnTeteProps {
  pochette: string | null | undefined;
  nom: string;
  ligneHaut?: ReactNode;
  meta: string;
  details: string;
  description?: string;
  ids: string[];
  source: { libelle: string; lien: string };
  boutonGauche?: ReactNode;
  onMenu: (e: React.MouseEvent) => void;
}

function EnTeteCollection({ pochette, nom, ligneHaut, meta, details, description, ids, source, boutonGauche, onMenu }: EnTeteProps) {
  const lire = useLecteur((s) => s.lire);
  const basculer = useLecteur((s) => s.basculerLecture);
  const enCours = useLecteur((s) => s.source?.lien === source.lien && s.file.length > 0);
  const enLecture = useLecteur((s) => s.enLecture);
  return (
    <aside className="collection-entete">
      {ligneHaut && <div className="collection-ligne-haut">{ligneHaut}</div>}
      <div className="collection-pochette"><Pochette id={pochette} nom={nom} /></div>
      <h1 className="collection-nom">{nom}</h1>
      <div className="collection-meta">{meta}</div>
      <div className="collection-details">{details}</div>
      {description && <p className="collection-description">{description}</p>}
      <div className="collection-actions">
        {boutonGauche}
        <button
          type="button"
          className="gros-bouton-lecture"
          aria-label={enCours && enLecture ? 'Pause' : 'Lecture'}
          disabled={!ids.length}
          onClick={() => (enCours ? basculer() : lire(ids, 0, source, { melanger: false }))}
        >
          <Icone nom={enCours && enLecture ? 'pause' : 'lecture'} taille={36} />
        </button>
        <BoutonIcone icone="plus" libelle="Plus d'actions" className="rond" onClick={onMenu} />
      </div>
    </aside>
  );
}

export function PageAlbum() {
  const { id = '' } = useParams();
  const a = useBibliotheque((s) => s.albums[id]);
  const titres = useBibliotheque((s) => s.titres);
  const artistes = useBibliotheque((s) => s.artistes);
  const listeAlbums = useBibliotheque((s) => s.listeAlbums);
  const enregistre = useBibliotheque((s) => s.utilisateur.albumsEnregistres.includes(id));
  const basculerAlbum = useBibliotheque((s) => s.basculerAlbum);
  const lire = useLecteur((s) => s.lire);
  const teinte = useCouleurDominante(urlPochette(a?.pochette));

  if (!a) return <EtatVide icone="album" titre="Album introuvable" />;
  const artiste = artistes[a.idArtiste];
  const autres = listeAlbums.filter((x) => x.idArtiste === a.idArtiste && x.id !== a.id);
  const source = { libelle: a.titre, lien: `/album/${a.id}` };
  const liste = a.titres.map((t) => titres[t]).filter(Boolean);

  return (
    <div className="page page-collection" style={{ '--teinte': teinte } as React.CSSProperties}>
      <div className="collection">
        <EnTeteCollection
          pochette={a.pochette}
          nom={a.titre}
          ligneHaut={artiste && (
            <Link to={`/artiste/${artiste.id}`} className="collection-artiste">
              <Pochette id={artiste.pochette} nom={artiste.nom} rond /> {artiste.nom}
            </Link>
          )}
          meta={joindre(a.type, a.genre, a.annee)}
          details={joindre(nbTitres(a.titres.length), dureeLongue(a.duree))}
          ids={a.titres}
          source={source}
          boutonGauche={<BoutonIcone icone={enregistre ? 'enregistre' : 'enregistrer'} libelle={enregistre ? 'Retirer de la bibliothèque' : 'Enregistrer dans la bibliothèque'} className="rond" actif={enregistre} onClick={() => basculerAlbum(a.id)} />}
          onMenu={(e) => ouvrirMenuDepuis(e, menuAlbum(a.id))}
        />
        <div className="collection-titres">
          {liste.map((t, i) => (
            <LigneTitre key={t.id} titre={t} numero={t.piste ?? i + 1} details="album" onLire={() => lire(a.titres, i, source, { melanger: false })} />
          ))}
          <Etagere titre={`Autres sorties de ${a.artiste}`} vide={!autres.length}>
            {autres.map((x) => <CarteAlbum key={x.id} album={x} sousTitre={joindre(x.type, x.annee)} />)}
          </Etagere>
        </div>
      </div>
    </div>
  );
}

export function PagePlaylist() {
  const { id = '' } = useParams();
  const jaime = useTitresJaime();
  const p = useBibliotheque((s) => s.utilisateur.playlists.find((x) => x.id === id));
  const titres = useBibliotheque((s) => s.titres);
  const retirer = useBibliotheque((s) => s.retirerDePlaylist);
  const noter = useBibliotheque((s) => s.noterJaime);
  const ouvrirDialogue = useInterface((s) => s.ouvrirDialogue);
  const lire = useLecteur((s) => s.lire);

  const estJaime = id === 'jaime';
  // On garde l'index d'origine dans la playlist pour pouvoir retirer le bon élément.
  const entrees = estJaime ? jaime.map((t, k) => ({ t, k })) : (p?.titres ?? []).map((t, k) => ({ t, k })).filter((e) => titres[e.t]);
  const ids = entrees.map((e) => e.t);
  const premier = titres[ids[0]];
  const teinte = useCouleurDominante(urlPochette(premier?.pochette));
  if (!estJaime && !p) return <EtatVide icone="file" titre="Playlist introuvable" />;

  const nom = estJaime ? "Titres J'aime" : p!.nom;
  const source = { libelle: nom, lien: `/playlist/${id}` };
  const total = ids.reduce((s, t) => s + (titres[t]?.duree || 0), 0);

  return (
    <div className="page page-collection" style={{ '--teinte': teinte } as React.CSSProperties}>
      <div className="collection">
        <EnTeteCollection
          pochette={premier?.pochette}
          nom={nom}
          meta={estJaime ? 'Playlist automatique' : joindre('Playlist', 'Vous', new Date(p!.creeLe).getFullYear())}
          details={joindre(nbTitres(ids.length), dureeLongue(total))}
          description={estJaime ? 'Les titres que vous avez aimés apparaissent ici.' : p!.description}
          ids={ids}
          source={source}
          boutonGauche={!estJaime && <BoutonIcone icone="modifier" libelle="Modifier" className="rond" onClick={() => ouvrirDialogue({ type: 'modifier-playlist', id })} />}
          onMenu={(e) => ouvrirMenuDepuis(e, menuPlaylist(id, ids))}
        />
        <div className="collection-titres">
          {!ids.length && (
            <EtatVide
              icone={estJaime ? 'jaime' : 'ajouterPlaylist'}
              titre={estJaime ? 'Aucun titre aimé' : 'Cette playlist est vide'}
              texte={estJaime ? 'Appuyez sur 👍 (ou la touche +) pendant l\'écoute.' : 'Utilisez « Enregistrer dans une playlist » depuis le menu ⋮ d\'un titre.'}
            />
          )}
          {entrees.map(({ t, k }, i) => (
            <LigneTitre
              key={`${t}-${k}`}
              titre={titres[t]}
              details="complet"
              onLire={() => lire(ids, i, source, { melanger: false })}
              menuExtra={[
                estJaime
                  ? { libelle: "Retirer des titres J'aime", icone: 'retirer', action: () => noter(t, 0) }
                  : { libelle: 'Retirer de la playlist', icone: 'retirer', action: () => retirer(id, k) },
              ]}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
