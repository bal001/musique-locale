// Barre de lecture en bas de l'écran, disposition observée sur YouTube Music (2026) :
// infos du titre à gauche, commandes au centre, temps / J'aime / volume / menu à droite,
// barre de progression rouge sur le bord supérieur.
import { useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { useBibliotheque } from '../store/bibliotheque';
import { useLecteur } from '../store/lecteur';
import { menuTitre, ouvrirMenuDepuis } from '../utils/actions';
import { duree } from '../utils/format';
import { BoutonIcone, Pochette } from './Elements';
import { Icone } from './Icone';
import { LiensArtistes } from './LigneTitre';

export function BarreLecture() {
  const idCourant = useLecteur((s) => s.file[s.index]);
  const t = useBibliotheque((s) => s.titres[idCourant]);
  const l = useLecteur();
  const note = useBibliotheque((s) => (t ? s.utilisateur.jaime[t.id] : undefined));
  const noter = useBibliotheque((s) => s.noterJaime);

  if (!t) return null;

  // Un clic sur une zone vide de la barre ouvre/ferme le lecteur développé.
  const clicBarre = (e: React.MouseEvent) => {
    if ((e.target as HTMLElement).closest('button, a, input, .progression')) return;
    l.ouvrirPage();
  };

  return (
    <footer className="barre-lecture" onClick={clicBarre} aria-label="Lecteur">
      <Progression />
      <div className="bl-gauche">
        <div className="bl-vignette">
          <Pochette id={t.pochette} nom={t.titre} />
        </div>
        <div className="bl-textes">
          <div className="bl-titre" title={t.titre}>{t.titre}</div>
          <div className="bl-sous-titre">
            <LiensArtistes titre={t} />
            <span className="separateur"> • </span>
            {t.idAlbum ? <Link to={`/album/${t.idAlbum}`}>{t.album}</Link> : <span>{t.album}</span>}
            {t.annee && <span> • {t.annee}</span>}
          </div>
        </div>
      </div>

      <div className="bl-centre">
        <BoutonIcone icone="aleatoire" libelle="Lecture aléatoire (s)" actif={l.aleatoire} onClick={l.basculerAleatoire} />
        <BoutonIcone icone="precedent" libelle="Précédent (k)" taille={32} onClick={l.precedent} />
        <button type="button" className={`bl-lecture${l.chargement ? ' chargement' : ''}`} aria-label={l.enLecture ? 'Pause (espace)' : 'Lecture (espace)'} title={l.enLecture ? 'Pause' : 'Lecture'} onClick={l.basculerLecture}>
          <Icone nom={l.enLecture ? 'pause' : 'lecture'} taille={32} />
        </button>
        <BoutonIcone icone="suivant" libelle="Suivant (j)" taille={32} onClick={() => l.suivant()} />
        <BoutonIcone
          icone={l.repetition === 'un' ? 'repeterUn' : 'repeter'}
          libelle={{ aucune: 'Répéter (r)', tout: 'Répéter tout', un: 'Répéter le titre' }[l.repetition]}
          actif={l.repetition !== 'aucune'}
          onClick={l.basculerRepetition}
        />
      </div>

      <div className="bl-droite">
        <span className="bl-temps">{duree(l.temps)} / {duree(l.duree || t.duree)}</span>
        <div className="pilule-jaime">
          <button type="button" aria-label="J'aime (+)" title="J'aime" className={note === 1 ? 'actif' : ''} onClick={() => noter(t.id, note === 1 ? 0 : 1)}>
            <Icone nom={note === 1 ? 'jaimePlein' : 'jaime'} taille={20} />
          </button>
          <span className="pilule-separateur" />
          <button type="button" aria-label="Je n'aime pas" title="Je n'aime pas" className={note === -1 ? 'actif' : ''} onClick={() => noter(t.id, note === -1 ? 0 : -1)}>
            <Icone nom={note === -1 ? 'jaimePasPlein' : 'jaimePas'} taille={20} />
          </button>
        </div>
        <Volume />
        <BoutonIcone icone="plus" libelle="Plus d'actions" onClick={(e) => ouvrirMenuDepuis(e, menuTitre(t.id))} />
        <BoutonIcone icone={l.pageOuverte ? 'bas' : 'haut'} libelle={l.pageOuverte ? 'Réduire le lecteur (q)' : 'Ouvrir le lecteur (q)'} onClick={() => l.ouvrirPage()} />
      </div>
    </footer>
  );
}

function Progression() {
  const temps = useLecteur((s) => s.temps);
  const dureeTotale = useLecteur((s) => s.duree);
  const chercher = useLecteur((s) => s.chercher);
  const ref = useRef<HTMLDivElement>(null);
  const [survol, setSurvol] = useState<{ x: number; t: number } | null>(null);
  const [glisse, setGlisse] = useState<number | null>(null);

  const tempsA = (clientX: number) => {
    const r = ref.current!.getBoundingClientRect();
    return Math.max(0, Math.min(1, (clientX - r.left) / r.width)) * (dureeTotale || 0);
  };

  const debut = (e: React.PointerEvent) => {
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    setGlisse(tempsA(e.clientX));
  };
  const deplacer = (e: React.PointerEvent) => {
    const t = tempsA(e.clientX);
    setSurvol({ x: e.clientX - ref.current!.getBoundingClientRect().left, t });
    if (glisse != null) setGlisse(t);
  };
  const fin = (e: React.PointerEvent) => {
    if (glisse != null) chercher(tempsA(e.clientX));
    setGlisse(null);
  };

  const affiche = glisse ?? temps;
  const pct = dureeTotale ? (affiche / dureeTotale) * 100 : 0;
  return (
    <div
      ref={ref}
      className={`progression${glisse != null ? ' glisse' : ''}`}
      role="slider"
      aria-label="Progression"
      aria-valuemin={0}
      aria-valuemax={Math.round(dureeTotale)}
      aria-valuenow={Math.round(affiche)}
      aria-valuetext={`${duree(affiche)} sur ${duree(dureeTotale)}`}
      tabIndex={0}
      onKeyDown={(e) => {
        const pas = ({ ArrowRight: 5, ArrowUp: 5, ArrowLeft: -5, ArrowDown: -5, PageUp: 30, PageDown: -30 } as Record<string, number>)[e.key];
        if (pas) {
          e.preventDefault();
          e.stopPropagation();
          chercher(temps + pas);
        } else if (e.key === 'Home' || e.key === 'End') {
          e.preventDefault();
          chercher(e.key === 'Home' ? 0 : dureeTotale - 1);
        }
      }}
      onPointerDown={debut}
      onPointerMove={deplacer}
      onPointerUp={fin}
      onPointerLeave={() => setSurvol(null)}
    >
      <div className="progression-piste">
        {survol && <div className="progression-survol" style={{ width: survol.x }} />}
        <div className="progression-lue" style={{ width: `${pct}%` }} />
        <div className="progression-bouton" style={{ left: `${pct}%` }} />
      </div>
      {survol && <div className="progression-info" style={{ left: survol.x }}>{duree(survol.t)}</div>}
    </div>
  );
}

function Volume() {
  const volume = useLecteur((s) => s.volume);
  const muet = useLecteur((s) => s.muet);
  const regler = useLecteur((s) => s.regler);
  const basculerMuet = useLecteur((s) => s.basculerMuet);
  const v = muet ? 0 : volume;
  return (
    <div className="volume">
      <input
        type="range"
        min={0}
        max={100}
        value={Math.round(v * 100)}
        aria-label="Volume"
        aria-valuetext={`${Math.round(v * 100)} %`}
        style={{ '--v': `${v * 100}%` } as React.CSSProperties}
        onChange={(e) => regler(Number(e.target.value) / 100)}
      />
      <BoutonIcone icone={v === 0 ? 'muet' : v < 0.5 ? 'volumeBas' : 'volume'} libelle={muet ? 'Réactiver le son (m)' : 'Couper le son (m)'} onClick={basculerMuet} />
    </div>
  );
}
