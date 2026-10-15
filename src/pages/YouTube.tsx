// Sections alimentées par l'API officielle de YouTube : résultats de recherche, tendances musique.
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, ressembleLienYoutube } from '../api';
import { useBibliotheque } from '../store/bibliotheque';
import { useLecteur } from '../store/lecteur';
import type { Titre } from '../types';
import { Icone } from '../components/Icone';
import { LigneTitre } from '../components/LigneTitre';
import { Carte, Etagere } from '../components/Elements';
import { menuTitre, ouvrirMenuDepuis } from '../utils/actions';

type Etat = { phase: 'attente' | 'chargement' | 'ok' | 'erreur'; titres: Titre[]; message?: string };

function useRequeteYoutube(cle: string, charger: (() => Promise<Titre[]>) | null) {
  const integrer = useBibliotheque((s) => s.integrerYoutube);
  const [etat, setEtat] = useState<Etat>({ phase: 'attente', titres: [] });
  useEffect(() => {
    if (!charger) {
      setEtat({ phase: 'attente', titres: [] });
      return;
    }
    let actif = true;
    setEtat({ phase: 'chargement', titres: [] });
    charger()
      .then((titres) => {
        if (!actif) return;
        integrer(titres);
        setEtat({ phase: 'ok', titres });
      })
      .catch((e: Error) => actif && setEtat({ phase: 'erreur', titres: [], message: e.message }));
    return () => {
      actif = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cle]);
  return etat;
}

function ListeYoutube({ etat, source, max }: { etat: Etat; source: { libelle: string; lien?: string }; max?: number }) {
  const lire = useLecteur((s) => s.lire);
  if (etat.phase === 'chargement') return <div className="yt-message"><span className="anneau petit" /> Recherche sur YouTube…</div>;
  if (etat.phase === 'erreur') return <div className="yt-message erreur"><Icone nom="info" taille={20} /> {etat.message}</div>;
  if (etat.phase === 'ok' && !etat.titres.length) return <div className="yt-message">Aucun résultat sur YouTube.</div>;
  const ids = etat.titres.map((t) => t.id);
  return (
    <div className="liste-titres">
      {etat.titres.slice(0, max).map((t, i) => <LigneTitre key={t.id} titre={t} onLire={() => lire(ids, i, source)} />)}
    </div>
  );
}

export function InviteCleYoutube({ texte }: { texte: string }) {
  return (
    <div className="yt-invite">
      <Icone nom="info" />
      <span>{texte}</span>
      <Link className="bouton-secondaire" to="/reglages#youtube">Configurer</Link>
    </div>
  );
}

// Résultats YouTube pour la page de recherche (ou lecture d'un lien collé).
export function ResultatsYoutube({ q, complet, onToutAfficher, meilleur }: { q: string; complet: boolean; onToutAfficher: () => void; meilleur?: (t: Titre) => React.ReactNode }) {
  const configure = useBibliotheque((s) => Boolean(s.utilisateur.reglages.youtubeConfigure));
  const lien = ressembleLienYoutube(q);
  const etat = useRequeteYoutube(
    `${q}|${configure}`,
    lien ? () => api.youtubeLien(q).then((t) => [t]) : configure && q.trim() ? () => api.youtubeRecherche(q) : null,
  );
  const source = { libelle: `YouTube « ${q} »`, lien: `/recherche?q=${encodeURIComponent(q)}&type=youtube` };

  return (
    <>
    {meilleur && !lien && etat.titres[0] && meilleur(etat.titres[0])}
    <section className="etagere">
      <header className="etagere-entete">
        <div>
          <div className="etagere-surtitre">Catalogue YouTube</div>
          <h2 className="etagere-titre">{lien ? 'Lien YouTube' : 'Sur YouTube'}</h2>
        </div>
        {!complet && etat.titres.length > 5 && <button type="button" className="bouton-secondaire" onClick={onToutAfficher}>Tout afficher</button>}
      </header>
      <ListeYoutube etat={etat} source={source} max={complet ? undefined : 5} />
    </section>
    </>
  );
}

// Étagère "Tendances musique" (vidéos musicales les plus populaires en France).
export function TendancesYoutube({ max = 12 }: { max?: number }) {
  const configure = useBibliotheque((s) => Boolean(s.utilisateur.reglages.youtubeConfigure));
  const lire = useLecteur((s) => s.lire);
  const etat = useRequeteYoutube(String(configure), configure ? api.youtubeTendances : null);
  if (!configure) return null;
  const ids = etat.titres.map((t) => t.id);
  const source = { libelle: 'Tendances musique YouTube', lien: '/explorer' };
  return (
    <section className="etagere">
      <header className="etagere-entete">
        <div>
          <div className="etagere-surtitre">Les clips les plus regardés en France</div>
          <h2 className="etagere-titre">Tendances YouTube</h2>
        </div>
        {ids.length > 0 && (
          <div className="etagere-actions">
            <button type="button" className="bouton-secondaire" onClick={() => lire(ids, 0, source)}>Tout lire</button>
          </div>
        )}
      </header>
      {etat.phase === 'ok' ? (
        <div className="grille-titres">
          {etat.titres.slice(0, max).map((t, i) => <LigneTitre key={t.id} titre={t} onLire={() => lire(ids, i, source)} />)}
        </div>
      ) : (
        <ListeYoutube etat={etat} source={source} />
      )}
    </section>
  );
}

// Étagère de l'accueil alimentée par une recherche YouTube (cartes carrées ou grille de titres).
export function EtagereYoutube({ surtitre, titre, requete, forme = 'cartes' }: { surtitre?: string; titre: string; requete: string; forme?: 'cartes' | 'liste' }) {
  const lire = useLecteur((s) => s.lire);
  const etat = useRequeteYoutube(requete, requete === ':tendances' ? api.youtubeTendances : () => api.youtubeRecherche(requete));
  const ids = etat.titres.map((t) => t.id);
  const source = { libelle: titre };
  if (etat.phase === 'erreur') {
    return (
      <section className="etagere">
        <h2 className="etagere-titre">{titre}</h2>
        <div className="yt-message erreur"><Icone nom="info" taille={20} /> {etat.message}</div>
      </section>
    );
  }
  if (etat.phase !== 'ok') {
    return (
      <section className="etagere">
        {surtitre && <div className="etagere-surtitre">{surtitre}</div>}
        <h2 className="etagere-titre">{titre}</h2>
        <div className={forme === 'cartes' ? 'squelette-cartes' : 'squelette-liste'}>
          {Array.from({ length: forme === 'cartes' ? 6 : 8 }, (_, i) => <div key={i} />)}
        </div>
      </section>
    );
  }
  if (forme === 'liste') {
    return (
      <section className="etagere">
        <header className="etagere-entete">
          <div>
            {surtitre && <div className="etagere-surtitre">{surtitre}</div>}
            <h2 className="etagere-titre">{titre}</h2>
          </div>
          <div className="etagere-actions">
            <button type="button" className="bouton-secondaire" onClick={() => lire(ids, 0, source)}>Tout lire</button>
          </div>
        </header>
        <div className="grille-titres">
          {etat.titres.slice(0, 12).map((t, i) => <LigneTitre key={t.id} titre={t} onLire={() => lire(ids, i, source)} />)}
        </div>
      </section>
    );
  }
  return (
    <Etagere surtitre={surtitre} titre={titre}>
      {etat.titres.map((t, i) => (
        <Carte
          key={t.id}
          lien={`/recherche?q=${encodeURIComponent(t.artiste)}`}
          pochette={t.pochette}
          titre={t.titre}
          sousTitre={t.artiste}
          onLire={() => lire(ids, i, source)}
          onMenu={(e) => ouvrirMenuDepuis(e, menuTitre(t.id))}
        />
      ))}
    </Etagere>
  );
}

// Carte d'accueil tant qu'aucune clé API n'est configurée.
export function ConfigurationYoutube() {
  const sauverReglages = useBibliotheque((s) => s.sauverReglages);
  const [cle, setCle] = useState('');
  const [occupe, setOccupe] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  const valider = async (e: React.FormEvent) => {
    e.preventDefault();
    setOccupe(true);
    setErreur(null);
    try {
      await sauverReglages({ cleYoutube: cle.trim() });
      await api.youtubeTendances(); // vérifie tout de suite que la clé fonctionne
    } catch (err) {
      setErreur((err as Error).message);
    } finally {
      setOccupe(false);
    }
  };

  return (
    <section className="config-youtube">
      <div className="sur-titre">Dernière étape</div>
      <h2>Connectez le catalogue YouTube</h2>
      <p>
        Pour remplir l'accueil avec les vrais titres de YouTube (tendances, hits, humeurs, recherche), l'app a besoin d'une
        clé gratuite de l'API YouTube. Aucun compte YouTube ni abonnement n'est nécessaire pour écouter.
      </p>
      <ol>
        <li>Ouvrez <a href="https://console.cloud.google.com/apis/library/youtube.googleapis.com" target="_blank" rel="noreferrer">la page de l'API YouTube Data v3</a> (connexion Google), créez un projet si demandé, puis cliquez sur <b>Activer</b>.</li>
        <li>Allez dans <a href="https://console.cloud.google.com/apis/credentials" target="_blank" rel="noreferrer">Identifiants</a> → <b>Créer des identifiants</b> → <b>Clé API</b>.</li>
        <li>Copiez la clé et collez-la ici :</li>
      </ol>
      <form className="ajout-dossier" onSubmit={valider}>
        <input type="password" autoComplete="off" value={cle} onChange={(e) => setCle(e.target.value)} placeholder="Clé API YouTube (commence par AIza…)" aria-label="Clé API YouTube" />
        <button type="submit" className="bouton-principal" disabled={!cle.trim() || occupe}>{occupe ? 'Vérification…' : 'Connecter'}</button>
      </form>
      {erreur && <div className="yt-message erreur"><Icone nom="info" taille={20} /> {erreur}</div>}
      <p className="config-note">En attendant, vous pouvez coller un lien YouTube ou YouTube Music dans la barre de recherche.</p>
    </section>
  );
}
