export function duree(secondes: number) {
  if (!Number.isFinite(secondes) || secondes < 0) secondes = 0;
  const h = Math.floor(secondes / 3600);
  const m = Math.floor((secondes % 3600) / 60);
  const s = Math.floor(secondes % 60);
  return h ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}` : `${m}:${String(s).padStart(2, '0')}`;
}

// "1 titre • 3 minutes et 9 secondes", comme l'en-tête d'album de YouTube Music.
export function dureeLongue(secondes: number) {
  const h = Math.floor(secondes / 3600);
  const m = Math.floor((secondes % 3600) / 60);
  const s = Math.round(secondes % 60);
  const pl = (n: number, mot: string) => `${n} ${mot}${n > 1 ? 's' : ''}`;
  if (h) return `${pl(h, 'heure')}${m ? ` et ${pl(m, 'minute')}` : ''}`;
  if (m) return `${pl(m, 'minute')}${s ? ` et ${pl(s, 'seconde')}` : ''}`;
  return pl(s, 'seconde');
}

export const nbTitres = (n: number) => `${n} titre${n > 1 ? 's' : ''}`;

export function lectures(n: number) {
  if (!n) return 'Jamais écouté';
  return `${new Intl.NumberFormat('fr-FR', { notation: 'compact' }).format(n)} lecture${n > 1 ? 's' : ''}`;
}

export function dateRelative(t: number) {
  const jours = Math.floor((Date.now() - t) / 86_400_000);
  if (jours <= 0) return "Aujourd'hui";
  if (jours === 1) return 'Hier';
  if (jours < 7) return 'Cette semaine';
  if (jours < 31) return 'Ce mois-ci';
  return new Intl.DateTimeFormat('fr-FR', { month: 'long', year: 'numeric' }).format(t);
}

export const joindre = (...parties: (string | number | null | undefined | false)[]) => parties.filter(Boolean).join(' • ');
