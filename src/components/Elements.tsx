// Briques visuelles réutilisées partout : pochette, carte, étagère (carrousel), puces.
import { useRef, useState, useEffect, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { urlPochette } from '../api';
import { couleurDeTexte } from '../utils/couleur';
import { Icone, type NomIcone } from './Icone';

export function Pochette({ id, nom, rond, className = '' }: { id: string | null | undefined; nom: string; rond?: boolean; className?: string }) {
  const url = urlPochette(id);
  const [echec, setEchec] = useState(false);
  const classes = `pochette${rond ? ' ronde' : ''} ${className}`;
  if (!url || echec) {
    return (
      <div className={`${classes} pochette-vide`} style={{ background: couleurDeTexte(nom) }} aria-hidden="true">
        {rond ? <span>{nom.slice(0, 1).toUpperCase()}</span> : <Icone nom="note" taille={40} />}
      </div>
    );
  }
  return <img className={classes} src={url} alt="" loading="lazy" draggable={false} onError={() => setEchec(true)} />;
}

export function BoutonIcone({
  icone, libelle, onClick, actif, taille = 24, className = '', desactive,
}: {
  icone: NomIcone; libelle: string; onClick?: (e: React.MouseEvent) => void; actif?: boolean; taille?: number; className?: string; desactive?: boolean;
}) {
  return (
    <button type="button" className={`bouton-icone${actif ? ' actif' : ''} ${className}`} title={libelle} aria-label={libelle} onClick={onClick} disabled={desactive}>
      <Icone nom={icone} taille={taille} />
    </button>
  );
}

// Carte carrée d'une étagère (album, artiste, playlist), avec bouton lecture au survol.
export function Carte({
  lien, pochette, titre, sousTitre, rond, onLire, onMenu, enLecture, visuel,
}: {
  lien: string; pochette?: string | null; titre: string; sousTitre: ReactNode; rond?: boolean;
  onLire?: () => void; onMenu?: (e: React.MouseEvent) => void; enLecture?: boolean; visuel?: ReactNode;
}) {
  return (
    <div className={`carte${rond ? ' carte-ronde' : ''}`} onContextMenu={onMenu}>
      <div className="carte-visuel">
        <Link to={lien} tabIndex={-1} aria-hidden="true">
          {visuel ?? <Pochette id={pochette} nom={titre} rond={rond} />}
        </Link>
        {(onLire || onMenu) && (
          <div className="carte-survol">
            {onMenu && <BoutonIcone icone="plus" libelle="Plus d'actions" className="carte-menu" onClick={onMenu} />}
            {onLire && (
              <button type="button" className={`carte-lecture${enLecture ? ' visible' : ''}`} aria-label={`Lire ${titre}`} onClick={onLire}>
                <Icone nom="lecture" taille={28} />
              </button>
            )}
          </div>
        )}
      </div>
      <Link to={lien} className="carte-titre" title={titre}>{titre}</Link>
      <div className="carte-sous-titre">{sousTitre}</div>
    </div>
  );
}

// Étagère horizontale avec flèches ‹ › (comme "Hits incontournables").
export function Etagere({ surtitre, titre, action, children, vide }: { surtitre?: string; titre: ReactNode; action?: ReactNode; children: ReactNode; vide?: boolean }) {
  const ref = useRef<HTMLDivElement>(null);
  const [bords, setBords] = useState({ debut: true, fin: false });
  const maj = () => {
    const el = ref.current;
    if (el) setBords({ debut: el.scrollLeft <= 2, fin: el.scrollLeft + el.clientWidth >= el.scrollWidth - 2 });
  };
  useEffect(() => {
    maj();
    const el = ref.current;
    if (!el) return;
    const obs = new ResizeObserver(maj);
    obs.observe(el);
    return () => obs.disconnect();
  }, [children]);
  const defiler = (sens: number) => ref.current?.scrollBy({ left: sens * ref.current.clientWidth * 0.9, behavior: 'smooth' });
  if (vide) return null;
  return (
    <section className="etagere">
      <header className="etagere-entete">
        <div>
          {surtitre && <div className="etagere-surtitre">{surtitre}</div>}
          <h2 className="etagere-titre">{titre}</h2>
        </div>
        <div className="etagere-actions">
          {action}
          <BoutonIcone icone="gauche" libelle="Précédent" className="fleche" onClick={() => defiler(-1)} desactive={bords.debut} />
          <BoutonIcone icone="droite" libelle="Suivant" className="fleche" onClick={() => defiler(1)} desactive={bords.fin} />
        </div>
      </header>
      <div className="etagere-contenu" ref={ref} onScroll={maj}>
        {children}
      </div>
    </section>
  );
}

export function Puces<T extends string>({ options, valeur, onChange }: { options: { valeur: T; libelle: string }[]; valeur: T | null; onChange: (v: T | null) => void }) {
  return (
    <div className="puces" role="tablist">
      {options.map((o) => (
        <button key={o.valeur} type="button" role="tab" aria-selected={valeur === o.valeur} className={`puce${valeur === o.valeur ? ' active' : ''}`} onClick={() => onChange(valeur === o.valeur ? null : o.valeur)}>
          {o.libelle}
        </button>
      ))}
    </div>
  );
}

export function EtatVide({ icone, titre, texte, action }: { icone: NomIcone; titre: string; texte?: ReactNode; action?: ReactNode }) {
  return (
    <div className="etat-vide">
      <Icone nom={icone} taille={56} />
      <h2>{titre}</h2>
      {texte && <p>{texte}</p>}
      {action}
    </div>
  );
}
