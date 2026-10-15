// Couleur dominante d'une pochette, pour les dégradés d'arrière-plan
// (YouTube Music teinte l'en-tête des albums et la carte "meilleur résultat").
import { useEffect, useState } from 'react';

const cache = new Map<string, string>();

function extraire(url: string): Promise<string> {
  return new Promise((ok) => {
    const img = new Image();
    img.onload = () => {
      try {
        const c = document.createElement('canvas');
        c.width = c.height = 24;
        const ctx = c.getContext('2d', { willReadFrequently: true })!;
        ctx.drawImage(img, 0, 0, 24, 24);
        const d = ctx.getImageData(0, 0, 24, 24).data;
        let r = 0, g = 0, b = 0, poids = 0;
        for (let i = 0; i < d.length; i += 4) {
          const max = Math.max(d[i], d[i + 1], d[i + 2]);
          const min = Math.min(d[i], d[i + 1], d[i + 2]);
          const w = 1 + (max - min) / 32; // privilégie les pixels saturés
          r += d[i] * w; g += d[i + 1] * w; b += d[i + 2] * w; poids += w;
        }
        // Assombrie pour garder un texte blanc lisible.
        const f = 0.55 / poids;
        ok(`rgb(${Math.round(r * f)}, ${Math.round(g * f)}, ${Math.round(b * f)})`);
      } catch {
        ok('rgb(40, 40, 40)');
      }
    };
    img.onerror = () => ok('rgb(40, 40, 40)');
    img.src = url;
  });
}

export function useCouleurDominante(url: string | null) {
  const [couleur, setCouleur] = useState(() => (url && cache.get(url)) || 'rgb(40, 40, 40)');
  useEffect(() => {
    if (!url) return setCouleur('rgb(40, 40, 40)');
    const connue = cache.get(url);
    if (connue) return setCouleur(connue);
    let actif = true;
    extraire(url).then((c) => {
      cache.set(url, c);
      if (actif) setCouleur(c);
    });
    return () => {
      actif = false;
    };
  }, [url]);
  return couleur;
}

// Couleur stable dérivée d'un texte (pochettes manquantes, tuiles de genre).
export function couleurDeTexte(texte: string) {
  let h = 0;
  for (const c of texte) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return `hsl(${h % 360}, 55%, 45%)`;
}
