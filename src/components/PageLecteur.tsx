// Lecteur développé (route "watch" de YouTube Music) : pochette, clip ou paroles en grand à gauche,
// panneau à onglets À SUIVRE / PAROLES / SIMILAIRES à droite.
import { useEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, estYoutube, lienYoutube, urlPochette } from '../api';
import { useBibliotheque } from '../store/bibliotheque';
import { useInterface } from '../store/interface';
import { useLecteur, type ModeAffichage, type OngletLecteur } from '../store/lecteur';
import { useTelechargements, useTitreJoue, versionsTelechargees } from '../store/telechargements';
import type { Paroles, Titre } from '../types';
import { menuTelechargement, menuTitre, ouvrirMenuDepuis } from '../utils/actions';
import { useCouleurDominante } from '../utils/couleur';
import { duree } from '../utils/format';
import { titresSimilaires } from '../utils/similaires';
import { BoutonIcone, Pochette } from './Elements';
import { Egaliseur, Icone } from './Icone';

// Fait défiler uniquement le panneau du lecteur (jamais la page entière).
function defilerDans(el: HTMLElement | null, mode: 'proche' | 'centre') {
  const conteneur = el?.closest<HTMLElement>('.pl-contenu');
  if (!el || !conteneur) return;
  const haut = el.offsetTop - conteneur.offsetTop;
  if (mode === 'centre') {
    conteneur.scrollTo({ top: haut - conteneur.clientHeight / 2 + el.offsetHeight / 2, behavior: 'smooth' });
  } else if (haut < conteneur.scrollTop || haut + el.offsetHeight > conteneur.scrollTop + conteneur.clientHeight) {
    conteneur.scrollTo({ top: haut - 8 });
  }
}

const ONGLETS: { id: OngletLecteur; libelle: string }[] = [
  { id: 'suivre', libelle: 'À suivre' },
  { id: 'paroles', libelle: 'Paroles' },
  { id: 'similaires', libelle: 'Similaires' },
];

const MODES: { id: ModeAffichage; libelle: string }[] = [
  { id: 'titre', libelle: 'Titre' },
  { id: 'video', libelle: 'Vidéo' },
  { id: 'paroles', libelle: 'Paroles' },
];

export function PageLecteur() {
  const ouverte = useLecteur((s) => s.pageOuverte);
  const onglet = useLecteur((s) => s.onglet);
  const choisir = useLecteur((s) => s.choisirOnglet);
  const idCourant = useLecteur((s) => s.file[s.index]);
  const t = useTitreJoue(idCourant); // version téléchargée si elle existe
  const couleur = useCouleurDominante(urlPochette(t?.pochette));
  const modeChoisi = useLecteur((s) => s.modeVideo);
  const choisirModeVideo = useLecteur((s) => s.choisirModeVideo);

  if (!t) return null;
  const avecVideo = estYoutube(t) || Boolean(t.video);
  const modes = avecVideo ? MODES : MODES.filter((m) => m.id !== 'video');
  const mode = modeChoisi === 'video' && !avecVideo ? 'titre' : modeChoisi;
  // Emplacement occupé par la vidéo (voir VideoYoutube.tsx) ; en petit hors du mode vidéo.
  const petiteVideo = avecVideo && <div id="zone-video" className="pl-video petite" />;
  return (
    <section className={`page-lecteur${ouverte ? ' ouverte' : ''}`} aria-hidden={!ouverte} style={{ '--teinte': couleur } as React.CSSProperties}>
      <div className="pl-visuel">
        <div className="selecteur-mode" role="radiogroup" aria-label="Affichage">
          {modes.map((m) => (
            <button key={m.id} type="button" role="radio" aria-checked={mode === m.id} className={mode === m.id ? 'actif' : ''} onClick={() => choisirModeVideo(m.id)}>
              {m.libelle}
            </button>
          ))}
        </div>
        {mode === 'video' ? (
          <div id="zone-video" className="pl-video" />
        ) : mode === 'paroles' ? (
          <div className="pl-mode-paroles">
            <div className="pl-contenu pl-paroles-grandes"><PanneauParoles t={t} /></div>
            {petiteVideo}
          </div>
        ) : (
          <div className="pl-mode-titre">
            <div className="pl-pochette"><Pochette id={t.pochette} nom={t.titre} /></div>
            {petiteVideo}
          </div>
        )}
        <div className="pl-legende">
          <h1>{t.titre}</h1>
          {estYoutube(t) ? (
            <p>
              {t.artiste} • <a href={lienYoutube(t)} target="_blank" rel="noreferrer">Voir sur YouTube Music</a>
            </p>
          ) : (
            <p>
              {t.artistes.map((n, i) => (
                <span key={n}>{i > 0 && ', '}<Link to={`/artiste/${t.idsArtistes[i]}`} onClick={() => useLecteur.getState().ouvrirPage(false)}>{n}</Link></span>
              ))}
              {' • '}
              <Link to={`/album/${t.idAlbum}`} onClick={() => useLecteur.getState().ouvrirPage(false)}>{t.album}</Link>
            </p>
          )}
          <BoutonTelecharger id={idCourant} />
        </div>
      </div>
      <div className="pl-panneau">
        <div className="pl-onglets" role="tablist">
          {ONGLETS.map((o) => (
            <button key={o.id} type="button" role="tab" aria-selected={onglet === o.id} className={onglet === o.id ? 'actif' : ''} onClick={() => choisir(o.id)}>
              {o.libelle}
            </button>
          ))}
        </div>
        <div className="pl-contenu">
          {onglet === 'suivre' && <FileAttente />}
          {onglet === 'paroles' && <PanneauParoles t={t} />}
          {onglet === 'similaires' && <PanneauSimilaires id={t.id} />}
        </div>
      </div>
    </section>
  );
}

// « Télécharger » (comme dans YouTube Music) : audio seul ou clip vidéo, pour l'écoute hors ligne.
export function BoutonTelecharger({ id }: { id: string }) {
  const t = useBibliotheque((s) => s.titres[id]);
  const liste = useBibliotheque((s) => s.listeTitres);
  const taches = useTelechargements((s) => s.taches);
  const idVideo = t?.idVideo ?? t?.origineYoutube;
  if (!t || !idVideo) return null;
  const versions = versionsTelechargees(idVideo, liste);
  const enCours = taches.find((x) => x.idVideo === idVideo && (x.etat === 'attente' || x.etat === 'encours'));
  if (enCours) {
    return (
      <span className="bouton-telecharger en-cours" role="status">
        <span className="anneau-progression" style={{ '--p': `${enCours.progression}%` } as React.CSSProperties} />
        {enCours.etat === 'attente' ? 'En attente…' : `Téléchargement… ${enCours.progression} %`}
      </span>
    );
  }
  return (
    <button type="button" className={`bouton-telecharger${versions.length ? ' fait' : ''}`} onClick={(e) => ouvrirMenuDepuis(e, menuTelechargement(id))}>
      <Icone nom={versions.length ? 'telecharge' : 'telecharger'} taille={20} />
      {versions.length ? (versions.some((v) => v.video) ? 'Clip téléchargé' : 'Téléchargé') : 'Télécharger'}
    </button>
  );
}

function FileAttente() {
  const { file, index, source, ajoutsAuto, allerA, retirerDeLaFile, deplacerDansLaFile, enLecture } = useLecteur();
  const titres = useBibliotheque((s) => s.titres);
  const lectureAuto = useBibliotheque((s) => s.utilisateur.reglages.lectureAuto);
  const sauverReglages = useBibliotheque((s) => s.sauverReglages);
  const ouvrirDialogue = useInterface((s) => s.ouvrirDialogue);
  const [glisse, setGlisse] = useState<number | null>(null);
  const [cible, setCible] = useState<number | null>(null);
  const courantRef = useRef<HTMLDivElement>(null);

  // Accolades obligatoires : dans Chrome récent, scrollIntoView() renvoie une promesse,
  // que React prendrait pour une fonction de nettoyage.
  useEffect(() => {
    defilerDans(courantRef.current, 'proche');
  }, [index]);

  const debutAuto = file.length - ajoutsAuto;
  const ligne = (id: string, i: number) => {
    const t = titres[id];
    if (!t) return null;
    const courant = i === index;
    return (
      <div
        key={`${id}-${i}`}
        ref={courant ? courantRef : undefined}
        className={`fa-ligne${courant ? ' courante' : ''}${cible === i && glisse !== null ? ' cible' : ''}`}
        draggable={!courant}
        onDragStart={() => setGlisse(i)}
        onDragOver={(e) => { e.preventDefault(); setCible(i); }}
        onDrop={() => { if (glisse !== null) deplacerDansLaFile(glisse, i); setGlisse(null); setCible(null); }}
        onDragEnd={() => { setGlisse(null); setCible(null); }}
        onClick={() => !courant && allerA(i)}
        onContextMenu={(e) => ouvrirMenuDepuis(e, menuTitre(id, courant ? [] : [{ libelle: "Retirer de la file d'attente", icone: 'retirer', action: () => retirerDeLaFile(i) }]))}
      >
        <div className="fa-vignette">
          <Pochette id={t.pochette} nom={t.titre} />
          {courant ? <span className="fa-anim"><Egaliseur actif={enLecture} /></span> : <span className="fa-survol"><Icone nom="lecture" /></span>}
        </div>
        <div className="fa-textes">
          <div className="fa-titre">{t.titre}</div>
          <div className="fa-artiste">{t.artiste}</div>
        </div>
        <span className="fa-duree">{t.duree ? duree(t.duree) : '–:––'}</span>
        {!courant && <Icone nom="poignee" taille={20} className="fa-poignee" />}
      </div>
    );
  };

  return (
    <div className="file-attente">
      <div className="fa-entete">
        <div>
          <div className="fa-surtitre">Lecture à partir de</div>
          <div className="fa-source">{source?.lien ? <Link to={source.lien} onClick={() => useLecteur.getState().ouvrirPage(false)}>{source.libelle}</Link> : source?.libelle || "File d'attente"}</div>
        </div>
        <button type="button" className="bouton-secondaire" onClick={() => ouvrirDialogue({ type: 'nouvelle-playlist', titres: file })}>
          <Icone nom="ajouterPlaylist" taille={20} /> Enregistrer
        </button>
      </div>
      <label className="fa-auto">
        <span>
          <b>Lecture automatique</b>
          <small>Ajoute des titres similaires à la fin de la file d'attente</small>
        </span>
        <input type="checkbox" className="interrupteur" role="switch" checked={lectureAuto} onChange={(e) => sauverReglages({ lectureAuto: e.target.checked })} />
      </label>
      <div className="fa-liste">
        {file.slice(0, debutAuto).map((id, i) => ligne(id, i))}
        {ajoutsAuto > 0 && <div className="fa-separateur">Ajoutés par la lecture automatique</div>}
        {file.slice(debutAuto).map((id, k) => ligne(id, debutAuto + k))}
        {lectureAuto && ajoutsAuto === 0 && <div className="fa-separateur">Lecture automatique activée</div>}
      </div>
    </div>
  );
}

function PanneauParoles({ t }: { t: Titre }) {
  const [paroles, setParoles] = useState<Paroles | null>(null);
  const temps = useLecteur((s) => s.temps);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let annule = false;
    setParoles(null);
    api.paroles(t).then((p) => !annule && setParoles(p)).catch(() => !annule && setParoles({ synchronisees: false, lignes: [] }));
    return () => {
      annule = true;
    };
  }, [t.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const active = useMemo(() => {
    if (!paroles?.synchronisees) return -1;
    let k = -1;
    paroles.lignes.forEach((l, i) => l.t !== null && l.t <= temps + 0.2 && (k = i));
    return k;
  }, [paroles, temps]);

  useEffect(() => {
    defilerDans(ref.current?.querySelector<HTMLElement>('.active') ?? null, 'centre');
  }, [active]);

  if (!paroles) return <div className="pl-message">Recherche des paroles…</div>;
  if (!paroles.lignes.length) return <div className="pl-message">Aucune parole trouvée pour ce titre.</div>;
  const source = paroles.source?.replace(/^Source\s*:\s*/i, '');
  return (
    <div className={`paroles${paroles.synchronisees ? ' synchronisees' : ''}`} ref={ref}>
      {paroles.lignes.map((l, i) => (
        <p
          key={i}
          className={i === active ? 'active' : i < active ? 'passee' : ''}
          onClick={() => l.t !== null && useLecteur.getState().chercher(l.t)}
        >
          {l.texte || ' '}
        </p>
      ))}
      {source && <div className="paroles-source">Source : {source}{paroles.synchronisees ? ' (synchronisé)' : ''}</div>}
    </div>
  );
}

function PanneauSimilaires({ id }: { id: string }) {
  const lire = useLecteur((s) => s.lire);
  const liste = useMemo(() => titresSimilaires(id, [], 20), [id]);
  if (!liste.length) return <div className="pl-message">Ajoutez plus de musique pour obtenir des suggestions.</div>;
  return (
    <div className="fa-liste">
      {liste.map((t, i) => (
        <div key={t.id} className="fa-ligne" onClick={() => lire(liste.map((x) => x.id), i, { libelle: 'Titres similaires' })} onContextMenu={(e) => ouvrirMenuDepuis(e, menuTitre(t.id))}>
          <div className="fa-vignette">
            <Pochette id={t.pochette} nom={t.titre} />
            <span className="fa-survol"><Icone nom="lecture" /></span>
          </div>
          <div className="fa-textes">
            <div className="fa-titre">{t.titre}</div>
            <div className="fa-artiste">{t.artiste}</div>
          </div>
          <BoutonIcone icone="plus" libelle="Plus d'actions" taille={20} onClick={(e) => ouvrirMenuDepuis(e, menuTitre(t.id))} />
        </div>
      ))}
    </div>
  );
}
