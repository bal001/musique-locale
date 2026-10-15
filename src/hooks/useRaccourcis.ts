// Raccourcis clavier identiques à ceux de YouTube Music (relevés avec REA, cf. analyse-rea/raccourcis-clavier.txt).
import { useEffect } from 'react';
import { useBibliotheque } from '../store/bibliotheque';
import { annoncer, useInterface } from '../store/interface';
import { duree } from '../utils/format';
import { titreCourant, useLecteur } from '../store/lecteur';
import { aller } from '../utils/actions';

export function useRaccourcis() {
  useEffect(() => {
    let prefixeG = 0; // horodatage de la dernière touche "g" (navigation gh / ge / gl / g,)

    const touche = (e: KeyboardEvent) => {
      const cible = e.target as HTMLElement;
      if (cible.closest('input, textarea, select, [contenteditable="true"]') || e.metaKey || e.altKey) return;
      if (useInterface.getState().dialogue && e.key !== '?') return;

      const l = useLecteur.getState();
      const k = e.key;
      const bas = k.toLowerCase();
      const fait = () => e.preventDefault();

      if (Date.now() - prefixeG < 1200) {
        prefixeG = 0;
        const routes: Record<string, string> = { h: '/', e: '/explorer', l: '/bibliotheque', ',': '/reglages' };
        if (routes[bas]) return fait(), aller(routes[bas]);
      }

      // Combinaisons avec Ctrl+Maj (±1 s)
      if (e.ctrlKey && e.shiftKey && (k === 'ArrowRight' || k === 'ArrowLeft')) return fait(), l.avancer(k === 'ArrowRight' ? 1 : -1);
      if (e.ctrlKey) return;

      if (e.shiftKey) {
        switch (bas) {
          case 'n': return fait(), l.suivant();
          case 'p': return fait(), l.precedent();
          case 'l': return fait(), l.avancer(1);
          case 'h': return fait(), l.avancer(-1);
        }
        if (k === 'ArrowRight') return fait(), l.avancer(10);
        if (k === 'ArrowLeft') return fait(), l.avancer(-10);
      }

      switch (k) {
        case ' ':
        case ';':
          return fait(), l.basculerLecture();
        case 'j': return fait(), l.suivant();
        case 'k': return fait(), l.precedent();
        case 'l': return fait(), l.avancer(10);
        case 'h': return fait(), l.avancer(-10);
        case 's': return fait(), l.basculerAleatoire();
        case 'r': return fait(), l.basculerRepetition();
        case '=': return fait(), l.regler(l.volume + 0.05);
        case '-': return fait(), l.regler(l.volume - 0.05);
        case 'm': return fait(), l.basculerMuet();
        case 'q':
        case 'Escape':
          if (k === 'Escape' && (useInterface.getState().menu || !l.pageOuverte)) return;
          return fait(), l.ouvrirPage();
        case 'f':
          fait();
          return document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen().catch(() => {});
        case '+':
        case '_': {
          const t = titreCourant();
          if (t) useBibliotheque.getState().noterJaime(t.id, k === '+' ? 1 : 0);
          return fait();
        }
        case '/':
          fait();
          return window.dispatchEvent(new Event('yml:recherche'));
        case '?':
          fait();
          return useInterface.getState().dialogue?.type === 'raccourcis'
            ? useInterface.getState().fermerDialogue()
            : useInterface.getState().ouvrirDialogue({ type: 'raccourcis' });
        case 'g':
          prefixeG = Date.now();
          return;
        case 'i': {
          // Ajout pour VoiceOver : annonce le titre en cours et la position.
          fait();
          const t = titreCourant();
          if (!t) return annoncer('Rien en lecture');
          return annoncer(`${l.enLecture ? 'En lecture' : 'En pause'} : ${t.titre}, de ${t.artiste}. ${duree(l.temps)} sur ${duree(l.duree || t.duree)}.`);
        }
      }
    };

    window.addEventListener('keydown', touche);
    return () => window.removeEventListener('keydown', touche);
  }, []);
}

