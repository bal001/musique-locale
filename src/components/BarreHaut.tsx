// Barre du haut : menu, logo, champ de recherche avec suggestions, boutons à droite.
import { useEffect, useMemo, useRef, useState } from 'react';
import { Link, useLocation, useNavigate, useSearchParams } from 'react-router-dom';
import { useBibliotheque } from '../store/bibliotheque';
import { useInterface } from '../store/interface';
import { useLecteur } from '../store/lecteur';
import { memoriserRecherche, oublierRecherche, oublierToutesRecherches, rechercher, recherchesRecentes, suggestionsTexte } from '../utils/recherche';
import { joindre } from '../utils/format';
import { api } from '../api';
import { BoutonIcone, Pochette } from './Elements';
import { Icone } from './Icone';

export function BarreHaut() {
  const basculerGuide = useInterface((s) => s.basculerGuide);
  return (
    <header className="barre-haut">
      <div className="barre-haut-gauche">
        <BoutonIcone icone="menu" libelle="Guide" onClick={basculerGuide} />
        <Link to="/" className="logo" aria-label="Accueil YouTube Musique Locale">
          <img src="/icone.svg" alt="" width={30} height={30} />
          <span>Musique<b>locale</b></span>
        </Link>
      </div>
      <ChampRecherche />
      <div className="barre-haut-droite">
        <Link to="/historique" className="bouton-icone" title="Historique" aria-label="Historique"><Icone nom="historique" /></Link>
        <BoutonIcone icone="clavier" libelle="Raccourcis clavier (?)" onClick={() => useInterface.getState().ouvrirDialogue({ type: 'raccourcis' })} />
        <Link to="/reglages" className="bouton-icone" title="Réglages" aria-label="Réglages"><Icone nom="reglages" /></Link>
        <div className="avatar" title="Profil local">L</div>
      </div>
    </header>
  );
}

function ChampRecherche() {
  const naviguer = useNavigate();
  const [params] = useSearchParams();
  const lieu = useLocation();
  const [texte, setTexte] = useState('');
  const [ouvert, setOuvert] = useState(false);
  const [selection, setSelection] = useState(-1);
  const [recentes, setRecentes] = useState(recherchesRecentes);
  const champ = useRef<HTMLInputElement>(null);
  // Recherche dans vos fichiers ET dans tous les titres YouTube déjà indexés (sans clé).
  const listeTitres = useBibliotheque((s) => s.listeTitres);
  const listeYoutube = useBibliotheque((s) => s.listeYoutube);
  const titres = useMemo(() => [...listeTitres, ...listeYoutube], [listeTitres, listeYoutube]);
  const albums = useBibliotheque((s) => s.listeAlbums);
  const artistes = useBibliotheque((s) => s.listeArtistes);
  const lire = useLecteur((s) => s.lire);

  // Le champ reflète la requête de la page de résultats.
  useEffect(() => {
    setTexte(lieu.pathname === '/recherche' ? params.get('q') || '' : '');
  }, [lieu.pathname, params]);

  // Raccourci "/" pour aller dans la recherche.
  useEffect(() => {
    const focus = () => champ.current?.focus();
    window.addEventListener('yml:recherche', focus);
    return () => window.removeEventListener('yml:recherche', focus);
  }, []);

  const donnees = useMemo(() => ({ titres, albums, artistes }), [titres, albums, artistes]);
  // Suggestions de YouTube pendant la frappe (comme sous sa barre de recherche), après une courte pause.
  const [suggestionsYt, setSuggestionsYt] = useState<string[]>([]);
  useEffect(() => {
    const q = texte.trim();
    if (!q) return setSuggestionsYt([]);
    let annule = false;
    const minuterie = setTimeout(() => {
      api.youtubeSuggestions(q).then((s) => !annule && setSuggestionsYt(s)).catch(() => {});
    }, 180);
    return () => {
      annule = true;
      clearTimeout(minuterie);
    };
  }, [texte]);
  const textes = useMemo(() => {
    if (!texte.trim()) return recentes.slice(0, 6);
    const locales = suggestionsTexte(texte, donnees).slice(0, 3);
    const vus = new Set(locales.map((s) => s.toLowerCase()));
    return [...locales, ...suggestionsYt.filter((s) => !vus.has(s.toLowerCase()))].slice(0, 8);
  }, [texte, donnees, recentes, suggestionsYt]);
  const riches = useMemo(() => (texte.trim() ? rechercher(texte, donnees).tous.slice(0, 4) : []), [texte, donnees]);

  const valider = (q: string) => {
    const r = q.trim();
    if (!r) return;

    memoriserRecherche(r);
    setRecentes(recherchesRecentes());
    setOuvert(false);
    champ.current?.blur();
    naviguer(`/recherche?q=${encodeURIComponent(r)}`);
  };

  const total = textes.length + riches.length;
  const clavier = (e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setSelection((s) => (s + 1) % Math.max(1, total));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setSelection((s) => (s <= 0 ? total - 1 : s - 1));
    } else if (e.key === 'Enter') {
      if (selection >= 0 && selection < textes.length) valider(textes[selection]);
      else if (selection >= textes.length) ouvrirRiche(selection - textes.length);
      else valider(texte);
    } else if (e.key === 'Escape') {
      setOuvert(false);
      champ.current?.blur();
    }
  };

  const ouvrirRiche = (i: number) => {
    const r = riches[i];
    if (!r) return;
    setOuvert(false);
    champ.current?.blur();
    if (r.type === 'artiste') naviguer(`/artiste/${r.artiste.id}`);
    else if (r.type === 'album') naviguer(`/album/${r.album.id}`);
    else lire([r.titre.id], 0, { libelle: r.titre.titre });
  };

  return (
    <div className={`recherche${ouvert ? ' ouverte' : ''}`} onBlur={(e) => !e.currentTarget.contains(e.relatedTarget) && setOuvert(false)}>
      <div className="recherche-champ">
        <Icone nom="recherche" />
        <input
          ref={champ}
          value={texte}
          placeholder="Rechercher des titres, albums ou artistes"
          aria-label="Rechercher"
          role="combobox"
          aria-autocomplete="list"
          aria-expanded={ouvert && total > 0}
          aria-controls="suggestions-recherche"
          aria-activedescendant={selection >= 0 ? `suggestion-${selection}` : undefined}
          onFocus={() => {
            setRecentes(recherchesRecentes()); // peut avoir été effacé dans les Réglages
            setOuvert(true);
          }}
          onChange={(e) => {
            setTexte(e.target.value);
            setSelection(-1);
            setOuvert(true);
          }}
          onKeyDown={clavier}
        />
        {texte && <BoutonIcone icone="fermer" libelle="Effacer" taille={20} onClick={() => { setTexte(''); champ.current?.focus(); }} />}
      </div>
      {ouvert && total > 0 && (
        <div className="recherche-suggestions" role="listbox" id="suggestions-recherche" aria-label="Suggestions">
          {!texte.trim() && (
            <div className="suggestion-entete">
              <span>Recherches récentes</span>
              <button type="button" onMouseDown={(e) => e.preventDefault()} onClick={() => { oublierToutesRecherches(); setRecentes([]); }}>
                Tout effacer
              </button>
            </div>
          )}
          {textes.map((s, i) => (
            <div key={s} id={`suggestion-${i}`} className={`suggestion${selection === i ? ' selectionnee' : ''}`} role="option" aria-selected={selection === i}>
              <button type="button" className="suggestion-texte" onMouseDown={(e) => e.preventDefault()} onClick={() => valider(s)}>
                <Icone nom={texte.trim() ? 'recherche' : 'historique'} taille={20} />
                <span>{surligner(s, texte)}</span>
              </button>
              {!texte.trim() && (
                <BoutonIcone icone="fermer" libelle="Supprimer" taille={18} onClick={() => { oublierRecherche(s); setRecentes(recherchesRecentes()); }} />
              )}
            </div>
          ))}
          {riches.length > 0 && <div className="suggestion-separateur" />}
          {riches.map((r, i) => {
            const k = textes.length + i;
            const [pochette, nom, sous, rond] =
              r.type === 'artiste' ? [r.artiste.pochette, r.artiste.nom, 'Artiste', true]
              : r.type === 'album' ? [r.album.pochette, r.album.titre, joindre(r.album.type, r.album.artiste, r.album.annee), false]
              : [r.titre.pochette, r.titre.titre, joindre('Titre', r.titre.artiste), false];
            return (
              <button key={`${r.type}${nom}${i}`} id={`suggestion-${k}`} role="option" aria-selected={selection === k} aria-label={`${nom}, ${sous}`} type="button" className={`suggestion suggestion-riche${selection === k ? ' selectionnee' : ''}`} onMouseDown={(e) => e.preventDefault()} onClick={() => ouvrirRiche(i)}>
                <Pochette id={pochette} nom={nom} rond={rond} />
                <span className="suggestion-textes">
                  <span>{surligner(nom, texte)}</span>
                  <small>{sous}</small>
                </span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

// Met en gras la partie qui complète la saisie (comme YouTube Music).
function surligner(texte: string, saisie: string) {
  const n = saisie.trim().length;
  if (!n || !texte.toLowerCase().startsWith(saisie.trim().toLowerCase())) return <b>{texte}</b>;
  return (
    <>
      {texte.slice(0, n)}
      <b>{texte.slice(n)}</b>
    </>
  );
}
