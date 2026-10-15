// Bibliothèque (onglets Playlists / Titres / Albums / Artistes / Téléchargements) et Historique.
import { useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useBibliotheque } from '../store/bibliotheque';
import { useInterface } from '../store/interface';
import { useLecteur } from '../store/lecteur';
import { useTelechargements } from '../store/telechargements';
import { EtatVide, Puces } from '../components/Elements';
import { Icone } from '../components/Icone';
import { LigneTitre } from '../components/LigneTitre';
import { dateRelative } from '../utils/format';
import { CarteAlbum, CarteArtiste, CartePlaylist, useTitresJaime } from './communs';

type Onglet = 'playlists' | 'titres' | 'albums' | 'artistes' | 'telechargements';
const ONGLETS: { valeur: Onglet; libelle: string }[] = [
  { valeur: 'playlists', libelle: 'Playlists' },
  { valeur: 'titres', libelle: 'Titres' },
  { valeur: 'albums', libelle: 'Albums' },
  { valeur: 'artistes', libelle: 'Artistes' },
  { valeur: 'telechargements', libelle: 'Téléchargements' },
];

type Tri = 'recents' | 'az' | 'za' | 'ecoutes';

export function PageBibliotheque() {
  const { onglet: o } = useParams();
  const onglet: Onglet = (ONGLETS.find((x) => x.valeur === o)?.valeur) ?? 'playlists';
  const naviguer = useNavigate();
  const [tri, setTri] = useState<Tri>('recents');
  const [filtre, setFiltre] = useState<'tout' | 'enregistres'>('tout');
  const { listeTitres, listeAlbums, listeArtistes, utilisateur } = useBibliotheque();
  const jaime = useTitresJaime();
  const lire = useLecteur((s) => s.lire);
  const ouvrirDialogue = useInterface((s) => s.ouvrirDialogue);

  const trier = <T extends { ajouteLe?: number; id: string }>(liste: T[], nom: (x: T) => string) => {
    const l = [...liste];
    if (tri === 'az') l.sort((a, b) => nom(a).localeCompare(nom(b)));
    if (tri === 'za') l.sort((a, b) => nom(b).localeCompare(nom(a)));
    if (tri === 'recents') l.sort((a, b) => (b.ajouteLe || 0) - (a.ajouteLe || 0));
    if (tri === 'ecoutes') l.sort((a, b) => (utilisateur.lectures[b.id] || 0) - (utilisateur.lectures[a.id] || 0));
    return l;
  };

  const titres = useMemo(() => trier(listeTitres, (t) => t.titre), [listeTitres, tri, utilisateur.lectures]); // eslint-disable-line
  const telecharges = useMemo(() => titres.filter((t) => t.origineYoutube), [titres]);
  const albums = useMemo(() => {
    const base = filtre === 'enregistres' ? listeAlbums.filter((a) => utilisateur.albumsEnregistres.includes(a.id)) : listeAlbums;
    return trier(base, (a) => a.titre);
  }, [listeAlbums, tri, filtre, utilisateur.albumsEnregistres]); // eslint-disable-line
  const artistes = useMemo(() => {
    const base = filtre === 'enregistres' ? listeArtistes.filter((a) => utilisateur.artistesSuivis.includes(a.id)) : listeArtistes;
    return tri === 'za' ? [...base].reverse() : base;
  }, [listeArtistes, tri, filtre, utilisateur.artistesSuivis]);

  return (
    <div className="page">
      <h1 className="titre-geant">Bibliothèque</h1>
      <div className="biblio-barre">
        <Puces options={ONGLETS} valeur={onglet} onChange={(v) => naviguer(`/bibliotheque/${v ?? 'playlists'}`)} />
        <div className="biblio-options">
          {(onglet === 'albums' || onglet === 'artistes') && (
            <select value={filtre} onChange={(e) => setFiltre(e.target.value as typeof filtre)} aria-label="Filtre">
              <option value="tout">Tout</option>
              <option value="enregistres">{onglet === 'albums' ? 'Enregistrés' : 'Abonnements'}</option>
            </select>
          )}
          {onglet !== 'playlists' && onglet !== 'telechargements' && (
            <select value={tri} onChange={(e) => setTri(e.target.value as Tri)} aria-label="Trier">
              <option value="recents">Ajouts récents</option>
              <option value="az">A à Z</option>
              <option value="za">Z à A</option>
              {onglet === 'titres' && <option value="ecoutes">Les plus écoutés</option>}
            </select>
          )}
        </div>
      </div>

      {onglet === 'playlists' && (
        <div className="grille-cartes">
          <button type="button" className="carte carte-nouvelle" onClick={() => ouvrirDialogue({ type: 'nouvelle-playlist' })}>
            <div className="carte-visuel"><div className="pochette pochette-vide nouvelle"><Icone nom="ajouter" taille={48} /></div></div>
            <span className="carte-titre">Nouvelle playlist</span>
          </button>
          <CartePlaylist playlist={{ id: 'jaime', nom: "Titres J'aime", titres: jaime, sousTitre: `Playlist automatique • ${jaime.length} titres` }} />
          {utilisateur.playlists.map((p) => <CartePlaylist key={p.id} playlist={p} />)}
        </div>
      )}
      {onglet === 'titres' && (
        <>
          <div className="rangee-boutons">
            <button type="button" className="bouton-principal" onClick={() => lire(titres.map((t) => t.id), 0, { libelle: 'Tous les titres', lien: '/bibliotheque/titres' }, { melanger: true })}>
              <Icone nom="aleatoire" taille={20} /> Lecture aléatoire
            </button>
          </div>
          <div className="liste-titres">
            {titres.map((t, i) => <LigneTitre key={t.id} titre={t} onLire={() => lire(titres.map((x) => x.id), i, { libelle: 'Tous les titres', lien: '/bibliotheque/titres' })} />)}
          </div>
        </>
      )}
      {onglet === 'telechargements' && (
        <>
          <TelechargementsEnCours />
          {telecharges.length ? (
            <>
              <div className="rangee-boutons">
                <button type="button" className="bouton-principal" onClick={() => lire(telecharges.map((t) => t.id), 0, { libelle: 'Téléchargements', lien: '/bibliotheque/telechargements' }, { melanger: true })}>
                  <Icone nom="aleatoire" taille={20} /> Lecture aléatoire
                </button>
              </div>
              <div className="liste-titres">
                {telecharges.map((t, i) => <LigneTitre key={t.id} titre={t} onLire={() => lire(telecharges.map((x) => x.id), i, { libelle: 'Téléchargements', lien: '/bibliotheque/telechargements' })} />)}
              </div>
            </>
          ) : (
            <EtatVide icone="telecharger" titre="Aucun téléchargement" texte="Dans le menu ⋮ d'un titre YouTube ou dans le lecteur, choisissez « Télécharger » pour l'écouter sans connexion." />
          )}
        </>
      )}
      {onglet === 'albums' && (albums.length ? <div className="grille-cartes">{albums.map((a) => <CarteAlbum key={a.id} album={a} />)}</div> : <EtatVide icone="album" titre="Aucun album enregistré" />)}
      {onglet === 'artistes' && (artistes.length ? <div className="grille-cartes">{artistes.map((a) => <CarteArtiste key={a.id} artiste={a} />)}</div> : <EtatVide icone="artiste" titre="Aucun abonnement" />)}
    </div>
  );
}

function TelechargementsEnCours() {
  const taches = useTelechargements((s) => s.taches).filter((t) => t.etat === 'attente' || t.etat === 'encours');
  if (!taches.length) return null;
  return (
    <div className="telechargements-en-cours">
      {taches.map((t) => (
        <div key={`${t.idVideo}${t.format}`} className="telechargement">
          <span className="telechargement-nom">{t.titre} <small>{t.artiste}{t.format === 'video' ? ' • clip vidéo' : ''}</small></span>
          <span className="telechargement-barre"><span style={{ width: `${t.progression}%` }} /></span>
          <span className="telechargement-pct">{t.etat === 'attente' ? 'En attente' : `${t.progression} %`}</span>
        </div>
      ))}
    </div>
  );
}

export function PageHistorique() {
  const historique = useBibliotheque((s) => s.utilisateur.historique);
  const titres = useBibliotheque((s) => s.titres);
  const vider = useBibliotheque((s) => s.viderHistorique);
  const ouvrirDialogue = useInterface((s) => s.ouvrirDialogue);
  const lire = useLecteur((s) => s.lire);

  const groupes = useMemo(() => {
    const g = new Map<string, string[]>();
    historique.filter((h) => titres[h.id]).forEach((h) => {
      const cle = dateRelative(h.t);
      g.set(cle, [...(g.get(cle) || []), h.id]);
    });
    return [...g.entries()];
  }, [historique, titres]);

  return (
    <div className="page">
      <div className="entete-ligne">
        <h1 className="titre-geant">Historique</h1>
        {historique.length > 0 && (
          <button type="button" className="bouton-secondaire" onClick={() => ouvrirDialogue({ type: 'confirmer', message: "Effacer tout l'historique d'écoute ? Les compteurs de lecture sont conservés.", libelle: 'Effacer', action: vider })}>
            Effacer l'historique
          </button>
        )}
      </div>
      {!groupes.length && <EtatVide icone="historique" titre="Aucun historique" texte="Les titres écoutés plus de 10 secondes apparaîtront ici." />}
      {groupes.map(([cle, ids]) => (
        <section key={cle} className="etagere">
          <h2 className="etagere-titre petit">{cle}</h2>
          <div className="liste-titres">
            {ids.map((id, i) => <LigneTitre key={id} titre={titres[id]} onLire={() => lire(ids, i, { libelle: 'Historique', lien: '/historique' })} />)}
          </div>
        </section>
      ))}
    </div>
  );
}
