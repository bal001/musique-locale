// Guide de gauche : Accueil / Explorer / Bibliothèque + playlists, réductible avec ☰.
import { NavLink, useLocation } from 'react-router-dom';
import { useBibliotheque } from '../store/bibliotheque';
import { useInterface } from '../store/interface';
import { useLecteur } from '../store/lecteur';
import { Icone, type NomIcone } from './Icone';

const ENTREES: { chemin: string; libelle: string; icone: NomIcone; iconeActive: NomIcone }[] = [
  { chemin: '/', libelle: 'Accueil', icone: 'accueilContour', iconeActive: 'accueil' },
  { chemin: '/explorer', libelle: 'Explorer', icone: 'explorerContour', iconeActive: 'explorer' },
  { chemin: '/bibliotheque', libelle: 'Bibliothèque', icone: 'bibliothequeContour', iconeActive: 'bibliotheque' },
];

export function BarreLaterale() {
  const reduit = useInterface((s) => s.guideReduit);
  const playlists = useBibliotheque((s) => s.utilisateur.playlists);
  const nbJaime = useBibliotheque((s) => Object.values(s.utilisateur.jaime).filter((v) => v === 1).length);
  const ouvrirDialogue = useInterface((s) => s.ouvrirDialogue);
  const lieu = useLocation();
  const source = useLecteur((s) => s.source);
  const enLecture = useLecteur((s) => s.enLecture);

  return (
    <nav className={`guide${reduit ? ' reduit' : ''}`} aria-label="Navigation principale">
      {ENTREES.map((e) => {
        const actif = e.chemin === '/' ? lieu.pathname === '/' : lieu.pathname.startsWith(e.chemin);
        return (
          <NavLink key={e.chemin} to={e.chemin} className={`guide-entree${actif ? ' active' : ''}`}>
            <Icone nom={actif ? e.iconeActive : e.icone} />
            <span>{e.libelle}</span>
          </NavLink>
        );
      })}
      {!reduit && (
        <>
          <hr />
          <button type="button" className="guide-nouvelle" onClick={() => ouvrirDialogue({ type: 'nouvelle-playlist' })}>
            <Icone nom="ajouter" /> Nouvelle playlist
          </button>
          <div className="guide-playlists">
            <NavLink to="/playlist/jaime" className="guide-playlist">
              <span className="guide-playlist-nom">Titres J'aime</span>
              <span className="guide-playlist-info">
                {source?.lien === '/playlist/jaime' && enLecture ? <Icone nom="volume" taille={16} /> : `Playlist automatique • ${nbJaime}`}
              </span>
            </NavLink>
            {playlists.map((p) => (
              <NavLink key={p.id} to={`/playlist/${p.id}`} className="guide-playlist">
                <span className="guide-playlist-nom">{p.nom}</span>
                <span className="guide-playlist-info">
                  {source?.lien === `/playlist/${p.id}` && enLecture ? <Icone nom="volume" taille={16} /> : `Vous • ${p.titres.length} titre${p.titres.length > 1 ? 's' : ''}`}
                </span>
              </NavLink>
            ))}
          </div>
        </>
      )}
    </nav>
  );
}

// Sur iPhone : les mêmes entrées, en onglets en bas de l'écran (comme l'app YouTube Music).
export function NavigationMobile() {
  const lieu = useLocation();
  return (
    <nav className="nav-mobile" aria-label="Navigation">
      {ENTREES.map((e) => {
        const actif = e.chemin === '/' ? lieu.pathname === '/' : lieu.pathname.startsWith(e.chemin);
        return (
          <NavLink key={e.chemin} to={e.chemin} className={actif ? 'active' : ''}>
            <Icone nom={actif ? e.iconeActive : e.icone} />
            <span>{e.libelle}</span>
          </NavLink>
        );
      })}
    </nav>
  );
}
