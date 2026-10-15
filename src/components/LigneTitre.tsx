// Ligne de titre (listes d'album, playlist, recherche, bibliothèque).
import { Link } from 'react-router-dom';
import { estYoutube } from '../api';
import { artistePrincipal } from '../pages/ArtistesYoutube';
import { useBibliotheque } from '../store/bibliotheque';
import { useLecteur } from '../store/lecteur';
import type { ElementMenu } from '../store/interface';
import type { Titre } from '../types';
import { menuTitre, ouvrirMenuDepuis } from '../utils/actions';
import { duree, joindre, lectures } from '../utils/format';
import { BoutonIcone, Pochette } from './Elements';
import { Egaliseur, Icone } from './Icone';

interface Props {
  titre: Titre;
  onLire: () => void;
  numero?: number;              // affiche le n° de piste au lieu de la pochette (pages album)
  details?: 'album' | 'complet' | 'lectures';
  menuExtra?: ElementMenu[];
}

export function LigneTitre({ titre: t, onLire, numero, details = 'complet', menuExtra }: Props) {
  const courant = useLecteur((s) => s.file[s.index] === t.id);
  const enLecture = useLecteur((s) => s.enLecture);
  const note = useBibliotheque((s) => s.utilisateur.jaime[t.id]);
  const nb = useBibliotheque((s) => s.utilisateur.lectures[t.id] || 0);
  const noter = useBibliotheque((s) => s.noterJaime);
  const basculer = useLecteur((s) => s.basculerLecture);
  const menu = (e: React.MouseEvent) => ouvrirMenuDepuis(e, menuTitre(t.id, menuExtra));

  return (
    <div className={`ligne-titre${courant ? ' courante' : ''}`} onDoubleClick={onLire} onContextMenu={menu}>
      <div className="ligne-gauche">
        {numero != null ? (
          <span className="ligne-numero">{courant ? <Egaliseur actif={enLecture} /> : numero}</span>
        ) : (
          <div className="ligne-vignette">
            <Pochette id={t.pochette} nom={t.titre} />
            {courant && <span className="ligne-vignette-anim"><Egaliseur actif={enLecture} /></span>}
          </div>
        )}
        <button type="button" className="ligne-lecture" aria-label={courant && enLecture ? 'Pause' : `Lire ${t.titre}`} onClick={() => (courant ? basculer() : onLire())}>
          <Icone nom={courant && enLecture ? 'pause' : 'lecture'} taille={24} />
        </button>
      </div>
      <div className="ligne-textes">
        <div className="ligne-titre-texte" title={t.titre}>{t.titre}</div>
        <div className="ligne-sous-texte">
          {details === 'lectures' ? (
            lectures(nb)
          ) : details === 'album' ? (
            t.artistes.length > 1 || t.artiste !== t.artisteAlbum ? <LiensArtistes titre={t} /> : lectures(nb)
          ) : (
            <>
              {estYoutube(t) && <><span className="badge-youtube">YouTube</span>{' '}</>}
              {t.video && <><span className="badge-youtube">Clip</span>{' '}</>}
              {t.origineYoutube && <Icone nom="telecharge" taille={14} className="marque-telecharge" />}
              <LiensArtistes titre={t} />
              <span className="separateur"> • </span>
              {estYoutube(t) ? <span>{t.album}</span> : <Link to={`/album/${t.idAlbum}`}>{t.album}</Link>}
            </>
          )}
        </div>
      </div>
      <div className="ligne-actions">
        <BoutonIcone icone={note === -1 ? 'jaimePasPlein' : 'jaimePas'} libelle="Je n'aime pas" taille={20} onClick={() => noter(t.id, note === -1 ? 0 : -1)} />
        <BoutonIcone icone={note === 1 ? 'jaimePlein' : 'jaime'} libelle="J'aime" taille={20} onClick={() => noter(t.id, note === 1 ? 0 : 1)} />
        <BoutonIcone icone="plus" libelle="Plus d'actions" taille={20} onClick={menu} />
      </div>
      {note === 1 && <Icone nom="jaimePlein" taille={16} className="ligne-indicateur-jaime" />}
      <span className="ligne-duree">{t.duree ? duree(t.duree) : '–:––'}</span>
    </div>
  );
}

export function LiensArtistes({ titre }: { titre: Titre }) {
  // Titres YouTube : lien vers la page artiste regroupée.
  if (!titre.idsArtistes.length) {
    return <Link to={`/youtube/artiste/${encodeURIComponent(artistePrincipal(titre))}`} onClick={(e) => e.stopPropagation()}>{titre.artiste}</Link>;
  }
  return (
    <>
      {titre.artistes.map((nom, i) => (
        <span key={titre.idsArtistes[i]}>
          {i > 0 && (i === titre.artistes.length - 1 ? ' et ' : ', ')}
          <Link to={`/artiste/${titre.idsArtistes[i]}`} onClick={(e) => e.stopPropagation()}>{nom}</Link>
        </span>
      ))}
    </>
  );
}

// Ligne compacte (recherche) : "Titre • Artiste • 3:17"
export function sousTitreRecherche(t: Titre) {
  return joindre('Titre', t.artiste, duree(t.duree));
}
