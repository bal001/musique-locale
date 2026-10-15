// Menu contextuel "⋮", notifications et boîtes de dialogue.
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useBibliotheque } from '../store/bibliotheque';
import { useInterface } from '../store/interface';
import { Icone, type NomIcone } from './Icone';
import { Pochette, BoutonIcone } from './Elements';

export function Superpositions() {
  const annonce = useInterface((s) => s.annonce);
  return (
    <>
      <div className="lecteur-ecran" aria-live="polite" aria-atomic="true">{annonce}</div>
      <MenuContextuel />
      <Toasts />
      <Dialogues />
    </>
  );
}

function MenuContextuel() {
  const menu = useInterface((s) => s.menu);
  const fermer = useInterface((s) => s.fermerMenu);
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState({ x: 0, y: 0 });

  // Garde le menu dans la fenêtre.
  useLayoutEffect(() => {
    if (!menu || !ref.current) return;
    const r = ref.current.getBoundingClientRect();
    setPos({
      x: Math.min(menu.x, window.innerWidth - r.width - 8),
      y: menu.y + r.height > window.innerHeight - 8 ? Math.max(8, menu.y - r.height) : menu.y,
    });
  }, [menu]);

  // Accessibilité : le focus va sur le premier choix ; flèches pour naviguer ; le focus revient ensuite.
  useEffect(() => {
    if (!menu) return;
    const precedent = document.activeElement as HTMLElement | null;
    ref.current?.querySelector('button')?.focus();
    const naviguer = (e: KeyboardEvent) => {
      if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
      e.preventDefault();
      const boutons = [...(ref.current?.querySelectorAll('button') ?? [])];
      const i = boutons.indexOf(document.activeElement as HTMLButtonElement);
      boutons[(i + (e.key === 'ArrowDown' ? 1 : -1) + boutons.length) % boutons.length]?.focus();
    };
    window.addEventListener('keydown', naviguer);
    return () => {
      window.removeEventListener('keydown', naviguer);
      precedent?.focus?.();
    };
  }, [menu]);

  useEffect(() => {
    if (!menu) return;
    const touche = (e: KeyboardEvent) => e.key === 'Escape' && fermer();
    window.addEventListener('keydown', touche);
    window.addEventListener('resize', fermer);
    return () => {
      window.removeEventListener('keydown', touche);
      window.removeEventListener('resize', fermer);
    };
  }, [menu, fermer]);

  if (!menu) return null;
  return (
    <div className="voile-menu" onMouseDown={fermer} onContextMenu={(e) => { e.preventDefault(); fermer(); }}>
      <div className="menu" ref={ref} style={{ left: pos.x, top: pos.y }} role="menu" onMouseDown={(e) => e.stopPropagation()}>
        {menu.elements.map((el) => (
          <button
            key={el.libelle}
            type="button"
            role="menuitem"
            className={el.danger ? 'danger' : ''}
            onClick={() => {
              fermer();
              el.action();
            }}
          >
            {el.icone && <Icone nom={el.icone as NomIcone} taille={22} />}
            <span>{el.libelle}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

function Toasts() {
  const toasts = useInterface((s) => s.toasts);
  return (
    <div className="toasts" aria-live="polite">
      {toasts.map((t) => (
        <div key={t.id} className="toast">{t.texte}</div>
      ))}
    </div>
  );
}

function Dialogues() {
  const dialogue = useInterface((s) => s.dialogue);
  const fermer = useInterface((s) => s.fermerDialogue);
  useEffect(() => {
    if (!dialogue) return;
    const touche = (e: KeyboardEvent) => e.key === 'Escape' && fermer();
    window.addEventListener('keydown', touche);
    return () => window.removeEventListener('keydown', touche);
  }, [dialogue, fermer]);
  if (!dialogue) return null;
  return (
    <div className="voile-dialogue" onMouseDown={fermer}>
      <div
        className={`dialogue dialogue-${dialogue.type}`}
        role="dialog"
        aria-modal="true"
        aria-label={{ 'nouvelle-playlist': 'Nouvelle playlist', 'modifier-playlist': 'Modifier la playlist', 'ajouter-playlist': 'Enregistrer dans une playlist', raccourcis: 'Raccourcis clavier', confirmer: 'Confirmation' }[dialogue.type]}
        ref={(el) => {
          // Place le focus dans la boîte de dialogue à l'ouverture.
          if (el && !el.contains(document.activeElement)) el.querySelector<HTMLElement>('input, textarea, button')?.focus();
        }}
        onMouseDown={(e) => e.stopPropagation()}
      >
        {dialogue.type === 'nouvelle-playlist' && <FormulairePlaylist titres={dialogue.titres} />}
        {dialogue.type === 'modifier-playlist' && <FormulairePlaylist idPlaylist={dialogue.id} />}
        {dialogue.type === 'ajouter-playlist' && <AjouterAPlaylist titres={dialogue.titres} />}
        {dialogue.type === 'raccourcis' && <Raccourcis />}
        {dialogue.type === 'confirmer' && (
          <>
            <h2>Confirmation</h2>
            <p>{dialogue.message}</p>
            <div className="dialogue-actions">
              <button type="button" className="bouton-texte" onClick={fermer}>Annuler</button>
              <button type="button" className="bouton-principal danger" onClick={() => { fermer(); dialogue.action(); }}>{dialogue.libelle}</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function FormulairePlaylist({ titres, idPlaylist }: { titres?: string[]; idPlaylist?: string }) {
  const existante = useBibliotheque((s) => s.utilisateur.playlists.find((p) => p.id === idPlaylist));
  const { creerPlaylist, modifierPlaylist } = useBibliotheque.getState();
  const fermer = useInterface((s) => s.fermerDialogue);
  const [nom, setNom] = useState(existante?.nom ?? '');
  const [description, setDescription] = useState(existante?.description ?? '');

  const valider = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!nom.trim()) return;
    if (existante) await modifierPlaylist(existante.id, { nom, description });
    else await creerPlaylist(nom, description, titres);
    fermer();
  };

  return (
    <form onSubmit={valider}>
      <h2>{existante ? 'Modifier la playlist' : 'Nouvelle playlist'}</h2>
      {titres && titres.length > 0 && <p className="dialogue-note">{titres.length} titre{titres.length > 1 ? 's' : ''} seront ajoutés.</p>}
      <label className="champ">
        <span>Titre</span>
        <input autoFocus value={nom} maxLength={150} onChange={(e) => setNom(e.target.value)} />
      </label>
      <label className="champ">
        <span>Description</span>
        <textarea value={description} maxLength={5000} rows={3} onChange={(e) => setDescription(e.target.value)} />
      </label>
      <div className="dialogue-actions">
        <button type="button" className="bouton-texte" onClick={fermer}>Annuler</button>
        <button type="submit" className="bouton-principal" disabled={!nom.trim()}>{existante ? 'Enregistrer' : 'Créer'}</button>
      </div>
    </form>
  );
}

function AjouterAPlaylist({ titres }: { titres: string[] }) {
  const playlists = useBibliotheque((s) => s.utilisateur.playlists);
  const ajouter = useBibliotheque((s) => s.ajouterAPlaylist);
  const tous = useBibliotheque((s) => s.titres);
  const { fermerDialogue, ouvrirDialogue } = useInterface.getState();
  return (
    <>
      <header className="dialogue-entete">
        <h2>Enregistrer dans une playlist</h2>
        <BoutonIcone icone="fermer" libelle="Fermer" onClick={fermerDialogue} />
      </header>
      <div className="liste-playlists">
        {playlists.length === 0 && <p className="dialogue-note">Aucune playlist pour le moment.</p>}
        {playlists.map((p) => {
          const contient = titres.length === 1 && p.titres.includes(titres[0]);
          return (
            <button key={p.id} type="button" className="choix-playlist" onClick={() => { ajouter(p.id, titres); fermerDialogue(); }}>
              <Pochette id={tous[p.titres[0]]?.pochette} nom={p.nom} />
              <span>
                <b>{p.nom}</b>
                <small>{p.titres.length} titre{p.titres.length > 1 ? 's' : ''}{contient ? ' • déjà présent' : ''}</small>
              </span>
            </button>
          );
        })}
      </div>
      <div className="dialogue-actions">
        <button type="button" className="bouton-principal" onClick={() => ouvrirDialogue({ type: 'nouvelle-playlist', titres })}>
          <Icone nom="ajouter" taille={20} /> Nouvelle playlist
        </button>
      </div>
    </>
  );
}

// Liste relevée sur YouTube Music (dialogue "?") pendant l'analyse REA.
export const RACCOURCIS: { groupe: string; lignes: [string, string][] }[] = [
  {
    groupe: 'Lecture',
    lignes: [
      ['Lecture/Pause', 'Espace ou ;'],
      ['Titre suivant', 'J ou Maj+N'],
      ['Titre précédent', 'K ou Maj+P'],
      ['Avancer de 10 s', 'L ou Maj+→'],
      ['Revenir 10 s en arrière', 'H ou Maj+←'],
      ['Avancer de 1 s', 'Maj+L ou Ctrl+Maj+→'],
      ['Revenir 1 s en arrière', 'Maj+H ou Ctrl+Maj+←'],
      ['Lecture aléatoire', 'S'],
      ['Lecture en boucle', 'R'],
      ['Annoncer le titre en cours (VoiceOver)', 'I'],
    ],
  },
  {
    groupe: 'Général',
    lignes: [
      ['Augmenter le volume', '='],
      ['Baisser le volume', '-'],
      ['Couper / réactiver le son', 'M'],
      ['File d\'attente ↔ lecteur développé', 'Q ou Échap'],
      ['Plein écran', 'F'],
      ['J\'aime', '+'],
      ['Retirer le J\'aime', '_'],
    ],
  },
  {
    groupe: 'Navigation',
    lignes: [
      ['Accueil', 'G puis H'],
      ['Explorer', 'G puis E'],
      ['Bibliothèque', 'G puis L'],
      ['Réglages', 'G puis ,'],
      ['Rechercher', '/'],
      ['Afficher les raccourcis', '?'],
    ],
  },
];

function Raccourcis() {
  const fermer = useInterface((s) => s.fermerDialogue);
  return (
    <>
      <header className="dialogue-entete">
        <h2>Raccourcis clavier</h2>
        <BoutonIcone icone="fermer" libelle="Fermer" onClick={fermer} />
      </header>
      <div className="raccourcis">
        {RACCOURCIS.map((g) => (
          <section key={g.groupe}>
            <h3>{g.groupe}</h3>
            {g.lignes.map(([action, touches]) => (
              <div key={action} className="raccourci">
                <span>{action}</span>
                <span className="touches">{touches.split(' ou ').map((k, i) => <span key={k}>{i > 0 && <i> ou </i>}<kbd>{k}</kbd></span>)}</span>
              </div>
            ))}
          </section>
        ))}
      </div>
    </>
  );
}
