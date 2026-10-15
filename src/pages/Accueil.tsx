// Accueil, identique à celui de YouTube Music (relevé sur music.youtube.com, voir accueil-youtube.ts) :
// puces d'humeur en haut, puis Hits incontournables, 100% hits, Playlists de la communauté,
// Nouveaux sons, Sélection rapide et Nouveautés. Votre musique locale vient en dessous.
import { useMemo, useState } from 'react';
import { useBibliotheque } from '../store/bibliotheque';
import { useInterface } from '../store/interface';
import { useLecteur } from '../store/lecteur';
import { Carte, EtatVide, Etagere, Puces } from '../components/Elements';
import { menuTitre, ouvrirMenuDepuis } from '../utils/actions';
import { CarteAlbum, CarteArtiste } from './communs';
import { HUMEURS } from '../catalogue-youtube';
import { ACCUEIL } from '../accueil-youtube';
import { CartePlaylistYoutube, EtagerePlaylists, GrilleTitresPlaylist, GrilleTitresVideos } from './PlaylistsYoutube';

export function Accueil() {
  const { listeAlbums, listeArtistes, titres, utilisateur, erreur } = useBibliotheque();
  const lire = useLecteur((s) => s.lire);
  const [humeur, setHumeur] = useState<string | null>(null);

  // "Réécouter" : derniers titres écoutés (YouTube ou fichiers), comme sur YouTube Music une fois connecté.
  const reecouter = useMemo(() => utilisateur.historique.map((h) => titres[h.id]).filter(Boolean).slice(0, 20), [utilisateur.historique, titres]);
  const recents = useMemo(() => [...listeAlbums].sort((a, b) => b.ajouteLe - a.ajouteLe).slice(0, 20), [listeAlbums]);

  if (erreur) return <EtatVide icone="info" titre="Serveur introuvable" texte={erreur} />;
  const idsReecouter = reecouter.map((t) => t.id);
  const choix = humeur ? HUMEURS[humeur] : null;

  return (
    <div className="page page-accueil">
      {/* Pas de grand titre visible (comme YouTube Music) ; VoiceOver annonce quand même la page. */}
      <h1 className="lecteur-ecran">Accueil</h1>
      <Puces options={Object.keys(HUMEURS).map((h) => ({ valeur: h, libelle: h }))} valeur={humeur} onChange={setHumeur} />

      {choix && humeur ? (
        <>
          <GrilleTitresPlaylist key={humeur} titre={humeur} surtitre="Humeur" id={choix[0][0]} />
          <EtagerePlaylists titre={`Playlists ${humeur.toLowerCase()}`} playlists={choix} />
        </>
      ) : (
        <>
          <Etagere
            surtitre="Votre historique"
            titre="Réécouter"
            vide={!reecouter.length}
            action={
              <button type="button" className="bouton-secondaire" onClick={() => useInterface.getState().ouvrirDialogue({ type: 'confirmer', message: "Effacer tout l'historique d'écoute ? La rangée « Réécouter » sera vidée.", libelle: 'Effacer', action: () => useBibliotheque.getState().viderHistorique() })}>
                Effacer l'historique
              </button>
            }
          >
            {reecouter.map((t, i) => (
              <Carte
                key={t.id}
                lien={t.idAlbum ? `/album/${t.idAlbum}` : `/recherche?q=${encodeURIComponent(t.artiste)}`}
                pochette={t.pochette}
                titre={t.titre}
                sousTitre={t.artiste}
                onLire={() => lire(idsReecouter, i, { libelle: 'Réécouter' })}
                onMenu={(e) => ouvrirMenuDepuis(e, menuTitre(t.id, [{ libelle: "Retirer de l'historique", icone: 'retirer', action: () => useBibliotheque.getState().retirerDeLHistorique(t.id) }]))}
              />
            ))}
          </Etagere>

          {ACCUEIL.map((e) =>
            e.type === 'titres' ? (
              <GrilleTitresVideos key={e.titre} titre={e.titre} surtitre={e.surtitre} idsVideos={e.idsVideos} />
            ) : (
              <Etagere key={e.titre} surtitre={e.surtitre} titre={e.titre}>
                {e.elements.map((x) => <CartePlaylistYoutube key={x.id} playlist={[x.id, x.nom]} sousTitre={x.sousTitre} pochette={x.pochette} />)}
              </Etagere>
            ),
          )}

          <Etagere surtitre="Vos fichiers" titre="Votre musique" vide={!recents.length}>
            {recents.map((a) => <CarteAlbum key={a.id} album={a} />)}
          </Etagere>
          <Etagere titre="Vos artistes" vide={!listeArtistes.length}>
            {listeArtistes.map((a) => <CarteArtiste key={a.id} artiste={a} />)}
          </Etagere>
        </>
      )}
    </div>
  );
}
