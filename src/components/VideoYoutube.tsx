// Conteneur de la vidéo en cours : lecteur intégré de YouTube, ou clip téléchargé (élément <video> du moteur).
// - lecteur développé ouvert → la vidéo occupe l'emplacement #zone-video (à la place de la pochette) ;
// - sinon → mini-lecteur 16:9 en bas à droite, au-dessus de la barre de lecture.
// Un seul conteneur, positionné en CSS, pour ne jamais recréer l'iframe (ce qui couperait la lecture).
import { useEffect, useRef, useState } from 'react';
import { estYoutube } from '../api';
import { useLecteur } from '../store/lecteur';
import { elementLocal } from '../store/moteur';
import { useTitreJoue } from '../store/telechargements';
import { BoutonIcone } from './Elements';

export function VideoYoutube() {
  const id = useLecteur((s) => s.file[s.index]);
  const t = useTitreJoue(id);
  const youtube = estYoutube(t);
  const actif = youtube || Boolean(t?.video);
  const hoteLocal = useRef<HTMLDivElement>(null);

  // Inséré une seule fois : retirer un <video> de la page mettrait la lecture en pause.
  useEffect(() => {
    hoteLocal.current?.appendChild(elementLocal);
  }, []);
  const ouverte = useLecteur((s) => s.pageOuverte);
  const modeVideo = useLecteur((s) => s.modeVideo);
  const ouvrirPage = useLecteur((s) => s.ouvrirPage);
  const [zone, setZone] = useState<DOMRect | null>(null);

  // Suit la position de l'emplacement réservé dans le lecteur développé.
  useEffect(() => {
    if (!actif || !ouverte) {
      setZone(null);
      return;
    }
    let el: HTMLElement | null = null;
    let obs: ResizeObserver | null = null;
    const mesurer = () => el && setZone(el.getBoundingClientRect());
    // Attend la fin de l'animation d'ouverture avant de mesurer.
    const minuterie = window.setTimeout(() => {
      el = document.getElementById('zone-video');
      if (!el) return;
      mesurer();
      obs = new ResizeObserver(mesurer);
      obs.observe(el);
    }, 360);
    window.addEventListener('resize', mesurer);
    window.addEventListener('scroll', mesurer, true); // le lecteur développé défile sur petit écran
    return () => {
      clearTimeout(minuterie);
      obs?.disconnect();
      window.removeEventListener('resize', mesurer);
      window.removeEventListener('scroll', mesurer, true);
    };
  }, [actif, ouverte, modeVideo]);

  const mode = !actif ? 'inactive' : ouverte && zone ? 'developpee' : 'mini';
  const style = mode === 'developpee' && zone ? { left: zone.left, top: zone.top, width: zone.width, height: zone.height } : undefined;

  return (
    <div className={`video-yt ${mode}${youtube ? '' : ' locale'}`} style={style} aria-hidden={!actif}>
      <div id="yt-hote" className="video-yt-hote" />
      <div ref={hoteLocal} className="video-locale-hote" />
      {mode === 'mini' && <BoutonIcone icone="haut" libelle="Ouvrir le lecteur (q)" className="video-yt-agrandir" onClick={() => ouvrirPage(true)} />}
    </div>
  );
}
