// Réglages : dossiers de musique, lecture automatique, actualisation, statistiques, historique, téléchargements.
import { useEffect, useState } from 'react';
import { api } from '../api';
import { useLecteur } from '../store/lecteur';
import { useBibliotheque } from '../store/bibliotheque';
import { useInterface, notifier } from '../store/interface';
import { BoutonIcone } from '../components/Elements';
import { Icone } from '../components/Icone';
import { dureeLongue } from '../utils/format';
import { oublierToutesRecherches } from '../utils/recherche';

export function PageReglages() {
  const { utilisateur, listeTitres, listeAlbums, listeArtistes, sauverReglages, rescanner, viderHistorique } = useBibliotheque();
  const ouvrirDialogue = useInterface((s) => s.ouvrirDialogue);
  const [nouveau, setNouveau] = useState('');
  const [occupe, setOccupe] = useState(false);
  const { dossiers, lectureAuto } = utilisateur.reglages;
  const total = listeTitres.reduce((s, t) => s + t.duree, 0);

  const enregistrerDossiers = async (liste: string[]) => {
    setOccupe(true);
    try {
      const manquants = await sauverReglages({ dossiers: liste });
      notifier(manquants.length ? `Dossier introuvable : ${manquants.join(', ')}` : 'Dossiers mis à jour');
    } finally {
      setOccupe(false);
    }
  };

  return (
    <div className="page page-reglages">
      <h1 className="titre-geant">Réglages</h1>

      <section className="reglage-bloc">
        <h2>Dossiers de musique</h2>
        <p className="reglage-aide">
          L'application lit les fichiers MP3, M4A, AAC, FLAC, OGG, Opus, WAV et WebM de ces dossiers (et de leurs sous-dossiers).
          Les tags (titre, artiste, album, pochette) sont lus automatiquement. Pour les paroles synchronisées, placez un fichier
          <code>.lrc</code> du même nom à côté du fichier audio.
        </p>
        <ul className="liste-dossiers">
          {dossiers.map((d) => (
            <li key={d}>
              <Icone nom="dossier" />
              <code>{d}</code>
              <BoutonIcone icone="supprimer" libelle="Retirer ce dossier" onClick={() => enregistrerDossiers(dossiers.filter((x) => x !== d))} desactive={occupe} />
            </li>
          ))}
        </ul>
        <form
          className="ajout-dossier"
          onSubmit={(e) => {
            e.preventDefault();
            if (nouveau.trim()) enregistrerDossiers([...dossiers, nouveau.trim()]).then(() => setNouveau(''));
          }}
        >
          <input value={nouveau} onChange={(e) => setNouveau(e.target.value)} placeholder="Chemin du dossier, ex. ~/Music" aria-label="Nouveau dossier" />
          <button type="submit" className="bouton-principal" disabled={!nouveau.trim() || occupe}>Ajouter</button>
        </form>
        <div className="rangee-boutons">
          <button type="button" className="bouton-secondaire" disabled={occupe} onClick={async () => { setOccupe(true); await rescanner().finally(() => setOccupe(false)); }}>
            <Icone nom="actualiser" taille={20} /> {occupe ? 'Analyse…' : 'Actualiser la bibliothèque'}
          </button>
        </div>
      </section>

      <SectionYoutube />

      <section className="reglage-bloc">
        <h2>Lecture</h2>
        <label className="reglage-ligne">
          <span>
            <b>Lecture automatique</b>
            <small>À la fin de la file d'attente, continuer avec des titres similaires.</small>
          </span>
          <input type="checkbox" className="interrupteur" role="switch" checked={lectureAuto} onChange={(e) => sauverReglages({ lectureAuto: e.target.checked })} />
        </label>
        <button type="button" className="reglage-ligne bouton-ligne" onClick={() => ouvrirDialogue({ type: 'raccourcis' })}>
          <span>
            <b>Raccourcis clavier</b>
            <small>Les mêmes que YouTube Music. Appuyez sur ? n'importe où.</small>
          </span>
          <Icone nom="clavier" />
        </button>
      </section>

      <section className="reglage-bloc">
        <h2>Votre bibliothèque</h2>
        <div className="stats">
          <div><b>{listeTitres.length}</b><span>titres</span></div>
          <div><b>{listeAlbums.length}</b><span>albums</span></div>
          <div><b>{listeArtistes.length}</b><span>artistes</span></div>
          <div><b>{utilisateur.playlists.length}</b><span>playlists</span></div>
        </div>
        <p className="reglage-aide">Durée totale : {dureeLongue(total)}. Vos J'aime, playlists et historique sont enregistrés dans <code>donnees/etat.json</code>.</p>
      </section>

      <SectionIphone />

      <section className="reglage-bloc">
        <h2>Historique</h2>
        <div className="rangee-boutons">
          <button type="button" className="bouton-secondaire" onClick={() => ouvrirDialogue({ type: 'confirmer', message: 'Effacer toutes vos recherches récentes ?', libelle: 'Effacer', action: () => { oublierToutesRecherches(); notifier('Historique des recherches effacé'); } })}>
            Effacer l'historique des recherches
          </button>
          <button type="button" className="bouton-secondaire" onClick={() => ouvrirDialogue({ type: 'confirmer', message: "Effacer tout l'historique d'écoute ? Les compteurs de lecture sont conservés.", libelle: 'Effacer', action: viderHistorique })}>
            Effacer l'historique d'écoute
          </button>
        </div>
      </section>

      <section className="reglage-bloc">
        <h2>Téléchargements</h2>
        <p className="reglage-aide">
          Les titres téléchargés (audio ou clip) sont rangés dans <code>musique/Téléchargements</code>, avec leur pochette et leurs paroles, et se lisent sans connexion.
          Pour votre écoute personnelle uniquement.
        </p>
      </section>
    </div>
  );
}

// L'app sur l'iPhone : même Wi-Fi que le Mac, Safari, puis « Sur l'écran d'accueil ».
function SectionIphone() {
  const [infos, setInfos] = useState<{ adresse: string | null; qr: string | null } | null>(null);
  useEffect(() => {
    api.iphone().then(setInfos).catch(() => setInfos({ adresse: null, qr: null }));
  }, []);
  return (
    <section className="reglage-bloc" id="iphone">
      <h2>Sur votre iPhone</h2>
      {!infos ? null : !infos.adresse ? (
        <p className="reglage-aide">Le Mac n'est connecté à aucun réseau Wi-Fi.</p>
      ) : (
        <div className="iphone">
          <div className="iphone-qr" dangerouslySetInnerHTML={{ __html: infos.qr ?? '' }} />
          <ol className="reglage-aide">
            <li>iPhone sur le <b>même Wi-Fi</b> que ce Mac.</li>
            <li>Scannez le code avec l'appareil photo, ou ouvrez <code>{infos.adresse}</code> dans <b>Safari</b>.</li>
            <li>Touchez <b>Partager</b> puis <b>Sur l'écran d'accueil</b> : l'app apparaît avec son icône, en plein écran.</li>
            <li>Le Mac doit être allumé avec l'app ouverte : c'est lui qui fournit la musique, les recherches et les téléchargements.</li>
          </ol>
        </div>
      )}
    </section>
  );
}

// YouTube : la recherche marche sans clé ; lecture d'un lien collé.
function SectionYoutube() {
  const integrer = useBibliotheque((s) => s.integrerYoutube);
  const lire = useLecteur((s) => s.lire);
  const [lien, setLien] = useState('');

  const lireLien = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const t = await api.youtubeLien(lien);
      integrer([t]);
      lire([t.id], 0, { libelle: t.titre });
      setLien('');
    } catch (err) {
      notifier((err as Error).message);
    }
  };

  return (
    <section className="reglage-bloc" id="youtube">
      <h2>YouTube</h2>
      <p className="reglage-aide">
        Cherche n'importe quel artiste, titre ou album de YouTube depuis la barre de recherche, <b>sans clé ni compte</b>.
        L'écoute passe par le lecteur YouTube intégré. Tu peux aussi coller un lien YouTube ou YouTube Music.
      </p>
      <div className="yt-statut ok">
        <Icone nom="coche" taille={20} />
        Recherche YouTube active.
      </div>
      <form className="ajout-dossier" onSubmit={lireLien}>
        <input value={lien} onChange={(e) => setLien(e.target.value)} placeholder="https://music.youtube.com/watch?v=…" aria-label="Lien YouTube" />
        <button type="submit" className="bouton-secondaire" disabled={!lien.trim()}>
          <Icone nom="lecture" taille={20} /> Lire le lien
        </button>
      </form>
    </section>
  );
}
