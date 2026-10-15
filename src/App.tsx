// Squelette de l'application : barre du haut, guide, contenu, lecteur développé, barre de lecture.
import { useEffect, useRef } from 'react';
import { Route, Routes, useLocation, useNavigate } from 'react-router-dom';
import { BarreHaut } from './components/BarreHaut';
import { BarreLaterale, NavigationMobile } from './components/BarreLaterale';
import { BarreLecture } from './components/BarreLecture';
import { PageLecteur } from './components/PageLecteur';
import { Superpositions } from './components/Superpositions';
import { VideoYoutube } from './components/VideoYoutube';
import { useRaccourcis } from './hooks/useRaccourcis';
import { useBibliotheque } from './store/bibliotheque';
import { annoncer, useInterface } from './store/interface';
import { restaurerSession, useLecteur } from './store/lecteur';
import { definirNavigation } from './utils/actions';
import { Accueil } from './pages/Accueil';
import { Classement, Explorer, Genre, Genres, Nouveautes } from './pages/Explorer';
import { PageBibliotheque, PageHistorique } from './pages/Bibliotheque';
import { PageAlbum, PagePlaylist } from './pages/Collection';
import { PageArtiste } from './pages/Artiste';
import { PageRecherche } from './pages/Recherche';
import { PageReglages } from './pages/Reglages';
import { PageCategorieYoutube, PagePlaylistYoutube } from './pages/PlaylistsYoutube';
import { PageArtisteYoutube } from './pages/ArtistesYoutube';
import { CLASSEMENTS, GENRES, HUMEURS } from './catalogue-youtube';
import { titresDePlaylist } from './utils/playlistsYoutube';
import { EtatVide } from './components/Elements';

export function App() {
  const charge = useBibliotheque((s) => s.charge);
  const charger = useBibliotheque((s) => s.charger);
  const guideReduit = useInterface((s) => s.guideReduit);
  const lecteurActif = useLecteur((s) => s.file.length > 0);
  const pageOuverte = useLecteur((s) => s.pageOuverte);
  const naviguer = useNavigate();
  const lieu = useLocation();
  const contenu = useRef<HTMLElement>(null);

  useRaccourcis();
  useEffect(() => {
    definirNavigation(naviguer);
  }, [naviguer]);
  useEffect(() => {
    charger().then(async () => {
      restaurerSession();
      // Précharge les classements officiels : nouveautés et artistes du moment disponibles tout de suite.
      for (const [id] of CLASSEMENTS) await titresDePlaylist(id, 50).catch(() => []);
      // Puis, lentement (une playlist toutes les 4 s), toutes les playlists officielles du catalogue :
      // la recherche sans clé couvre ainsi plusieurs milliers de titres. Résultats mis en cache.
      const toutes = [...new Set([...Object.values(GENRES).flat(), ...Object.values(HUMEURS).flat()].map(([id]) => id))];
      for (const id of toutes) {
        await titresDePlaylist(id, 30).catch(() => []);
        await new Promise((r) => setTimeout(r, 4000));
      }
    });
  }, [charger]);

  // Retour en haut à chaque changement de page, et fermeture du lecteur développé.
  useEffect(() => {
    contenu.current?.scrollTo(0, 0);
    useLecteur.getState().ouvrirPage(false);
    // VoiceOver : annonce le titre de la nouvelle page une fois rendue.
    const minuterie = window.setTimeout(() => {
      const h1 = document.querySelector('.contenu h1')?.textContent;
      if (h1) annoncer(`Page ${h1}`);
    }, 400);
    return () => clearTimeout(minuterie);
  }, [lieu.pathname, lieu.search]);

  return (
    <div className={`app${guideReduit ? ' guide-reduit' : ''}${lecteurActif ? ' avec-lecteur' : ''}${pageOuverte ? ' lecteur-ouvert' : ''}`}>
      <BarreHaut />
      <BarreLaterale />
      <main className="contenu" ref={contenu}>
        {!charge ? (
          <div className="chargement-page"><span className="anneau" /></div>
        ) : (
          <Routes>
            <Route path="/" element={<Accueil />} />
            <Route path="/explorer" element={<Explorer />} />
            <Route path="/nouveautes" element={<Nouveautes />} />
            <Route path="/classement" element={<Classement />} />
            <Route path="/genres" element={<Genres />} />
            <Route path="/genre/:nom" element={<Genre />} />
            <Route path="/bibliotheque" element={<PageBibliotheque />} />
            <Route path="/bibliotheque/:onglet" element={<PageBibliotheque />} />
            <Route path="/historique" element={<PageHistorique />} />
            <Route path="/album/:id" element={<PageAlbum />} />
            <Route path="/playlist/:id" element={<PagePlaylist />} />
            <Route path="/artiste/:id" element={<PageArtiste />} />
            <Route path="/recherche" element={<PageRecherche />} />
            <Route path="/reglages" element={<PageReglages />} />
            <Route path="/youtube/playlist/:id" element={<PagePlaylistYoutube />} />
            <Route path="/youtube/categorie/:nom" element={<PageCategorieYoutube />} />
            <Route path="/youtube/artiste/:nom" element={<PageArtisteYoutube />} />
            <Route path="*" element={<EtatVide icone="info" titre="Page introuvable" />} />
          </Routes>
        )}
      </main>
      <PageLecteur />
      <VideoYoutube />
      <BarreLecture />
      <NavigationMobile />
      <Superpositions />
    </div>
  );
}
