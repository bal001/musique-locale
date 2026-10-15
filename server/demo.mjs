// Génère une petite bibliothèque de démonstration 100 % synthétisée (aucun contenu protégé) :
// fichiers WAV avec tags RIFF INFO, pochettes SVG et paroles synchronisées .lrc.
// Lancé automatiquement si le dossier musique/ est vide, ou à la main : npm run demo
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DOSSIER_MUSIQUE_DEFAUT } from './chemins.mjs';

const TAUX = 22050;
const DOSSIER_DEMO = path.join(DOSSIER_MUSIQUE_DEFAUT, 'Démo');

// --- Catalogue fictif ---------------------------------------------------------

const CATALOGUE = [
  {
    artiste: 'Néon Boulevard', album: 'Minuit Électrique', annee: 2025, genre: 'Synthwave', style: 'synthwave',
    couleurs: ['#2b0a3d', '#ff2e88', '#ffb347'],
    titres: [
      { titre: 'Autoroute 80', bpm: 104, racine: 45, duree: 38 },
      { titre: 'Néons sous la pluie', bpm: 96, racine: 50, duree: 42, paroles: 'neons' },
      { titre: 'Cassette rose', bpm: 110, racine: 47, duree: 34 },
      { titre: 'Minuit électrique', bpm: 100, racine: 43, duree: 40 },
      { titre: "Retour à l'aube", bpm: 92, racine: 48, duree: 36 },
    ],
  },
  {
    artiste: 'Les Ondes Calmes', album: 'Café du matin', annee: 2024, genre: 'Lo-fi', style: 'lofi',
    couleurs: ['#3b2a20', '#d9a066', '#f4e4c1'],
    titres: [
      { titre: 'Croissant tiède', bpm: 82, racine: 53, duree: 36 },
      { titre: 'Pluie sur Montmartre', bpm: 76, racine: 55, duree: 40, paroles: 'montmartre' },
      { titre: 'Page 47', bpm: 85, racine: 50, duree: 32 },
      { titre: 'Sieste', bpm: 72, racine: 52, duree: 34 },
    ],
  },
  {
    artiste: 'Aurore Boréale', album: 'Lumières du Nord', annee: 2026, genre: 'Ambient', style: 'ambient',
    couleurs: ['#04142b', '#1fd1a5', '#7b5cff'],
    titres: [
      { titre: 'Toundra', bpm: 60, racine: 48, duree: 40 },
      { titre: 'Aurore', bpm: 60, racine: 52, duree: 38 },
      { titre: 'Silence blanc', bpm: 56, racine: 45, duree: 36 },
      { titre: 'Polaris', bpm: 64, racine: 50, duree: 34 },
    ],
  },
  {
    artiste: 'Pixelle', album: 'Huit bits', annee: 2026, genre: 'Chiptune', style: 'chiptune',
    couleurs: ['#0d1b2a', '#3ddc97', '#ffd23f'],
    titres: [
      { titre: 'Huit bits', bpm: 140, racine: 57, duree: 30 },
      { titre: 'Game Over', artiste: 'Pixelle feat. Néon Boulevard', bpm: 132, racine: 55, duree: 30 },
    ],
  },
  {
    artiste: 'Les Ondes Calmes', artisteTitre: 'Les Ondes Calmes avec Aurore Boréale', album: 'Brume', annee: 2026, genre: 'Lo-fi', style: 'brume',
    couleurs: ['#1e2a38', '#8fb3c9', '#e8eef2'],
    titres: [{ titre: 'Brume', bpm: 70, racine: 50, duree: 38 }],
  },
];

const PAROLES = {
  neons: [
    [4, '♪'], [8, 'Les néons coulent sur le bitume'], [12, 'La ville respire dans la brume'],
    [16, 'On roule sans savoir où aller'], [20, 'La radio joue notre été'], [24, 'Sous la pluie, sous la pluie'],
    [28, 'Tout s\'allume, tout s\'enfuit'], [32, 'Sous la pluie, sous la pluie'], [36, 'Les néons nous tiennent compagnie'], [40, '♪'],
  ],
  montmartre: [
    [3, '♪'], [6, 'Les marches mouillées de Montmartre'], [10, 'Un café qui refroidit'], [14, 'Je regarde les gouttes se battre'],
    [18, 'Sur la vitre de l\'après-midi'], [22, 'Et la pluie fait des ronds dans les flaques'], [26, 'Comme un disque qui tourne au ralenti'],
    [30, 'Rien ne presse, rien ne craque'], [34, 'Paris s\'endort, et moi aussi'], [38, '♪'],
  ],
};

// --- Synthèse -----------------------------------------------------------------

const freq = (midi) => 440 * 2 ** ((midi - 69) / 12);

function aleatoire(graine) {
  let s = graine >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 2 ** 32);
}

const MINEUR = [0, 2, 3, 5, 7, 8, 10];
const MAJEUR = [0, 2, 4, 5, 7, 9, 11];

const PROGRESSIONS = {
  synthwave: { gamme: MINEUR, degres: [0, 5, 2, 6] },
  lofi: { gamme: MAJEUR, degres: [1, 4, 0, 5] },
  ambient: { gamme: MAJEUR, degres: [0, 3, 5, 3] },
  chiptune: { gamme: MAJEUR, degres: [0, 4, 5, 3] },
  brume: { gamme: MINEUR, degres: [0, 3, 5, 4] },
};

// Accord de 4 sons (avec septième) sur un degré de la gamme.
function accord(racine, gamme, degre) {
  return [0, 2, 4, 6].map((i) => {
    const d = degre + i;
    return racine + gamme[d % 7] + 12 * Math.floor(d / 7);
  });
}

function genererTitre(style, { bpm, racine, duree }, graine) {
  const n = Math.floor(duree * TAUX);
  const sortie = new Float32Array(n);
  const rnd = aleatoire(graine);
  const temps = 60 / bpm;
  const mesure = temps * 4;
  const { gamme, degres } = PROGRESSIONS[style];
  const fondu = (t) => Math.min(1, t / 3, (duree - t) / 4);

  const ajouter = (debut, longueur, gen) => {
    const i0 = Math.floor(debut * TAUX);
    const i1 = Math.min(n, i0 + Math.floor(longueur * TAUX));
    for (let i = Math.max(0, i0); i < i1; i++) sortie[i] += gen((i - i0) / TAUX);
  };

  const scie = (ph) => 2 * (ph % 1) - 1;
  const carre = (ph, rapport = 0.5) => ((ph % 1) < rapport ? 1 : -1);
  const triangle = (ph) => 1 - 4 * Math.abs((ph % 1) - 0.5);

  const nbMesures = Math.ceil(duree / mesure);
  let filtre = 0;

  for (let m = 0; m < nbMesures; m++) {
    const debut = m * mesure;
    const notes = accord(racine, gamme, degres[m % degres.length]);
    const intro = m < 2;

    // Nappe (pad)
    const volPad = style === 'ambient' || style === 'brume' ? 0.07 : style === 'chiptune' ? 0.025 : 0.045;
    for (const note of notes) {
      const f = freq(note + 12);
      ajouter(debut, mesure + 0.6, (t) => {
        const env = Math.min(1, t / (style === 'ambient' ? 1.6 : 0.4)) * Math.max(0, 1 - Math.max(0, t - mesure) / 0.6);
        let v;
        if (style === 'chiptune') v = carre(f * t, 0.25);
        else if (style === 'synthwave') v = 0.5 * scie(f * t) + 0.5 * scie(f * 1.004 * t);
        else v = Math.sin(2 * Math.PI * f * t) + 0.3 * Math.sin(2 * Math.PI * f * 2.001 * t) + 0.15 * Math.sin(2 * Math.PI * f * 0.5 * t);
        const tremolo = style === 'ambient' ? 0.75 + 0.25 * Math.sin(2 * Math.PI * 0.25 * t) : 1;
        return v * env * volPad * tremolo;
      });
    }

    // Basse
    if (!(style === 'ambient' && m % 2)) {
      const fb = freq(notes[0] - 12);
      const pas = style === 'synthwave' ? temps / 2 : style === 'chiptune' ? temps / 2 : temps * 2;
      for (let b = 0; b < mesure / pas; b++) {
        ajouter(debut + b * pas, pas * 0.95, (t) => {
          const env = Math.exp(-t * (style === 'ambient' ? 0.6 : 3));
          const v = style === 'chiptune' ? triangle(fb * t) : style === 'synthwave' ? 0.6 * scie(fb * t) + 0.4 * Math.sin(2 * Math.PI * fb * t) : Math.sin(2 * Math.PI * fb * t);
          return v * env * 0.16;
        });
      }
    }

    // Mélodie / arpège
    if (!intro) {
      const pas = style === 'ambient' ? temps : style === 'lofi' || style === 'brume' ? temps / 2 : temps / 4;
      for (let k = 0; k < mesure / pas; k++) {
        if (style !== 'chiptune' && style !== 'synthwave' && rnd() < 0.35) continue;
        const note = notes[Math.floor(rnd() * notes.length)] + (style === 'ambient' ? 24 : 12) + (rnd() < 0.2 ? 12 : 0);
        const f = freq(note);
        const swing = style === 'lofi' && k % 2 ? pas * 0.16 : 0;
        ajouter(debut + k * pas + swing, pas * (style === 'ambient' ? 3 : 1.4), (t) => {
          const env = Math.exp(-t * (style === 'ambient' ? 1.2 : style === 'lofi' ? 5 : 9));
          let v;
          if (style === 'chiptune') v = carre(f * t, 0.5);
          else if (style === 'synthwave') v = scie(f * t) * 0.6 + carre(f * 0.5 * t) * 0.2;
          else v = Math.sin(2 * Math.PI * f * t) * (1 + 0.4 * Math.sin(2 * Math.PI * f * 3 * t));
          return v * env * (style === 'chiptune' ? 0.05 : 0.09);
        });
      }
    }

    // Batterie
    if (style !== 'ambient' && !(intro && style !== 'chiptune')) {
      for (let b = 0; b < 4; b++) {
        const tb = debut + b * temps;
        if (b % 2 === 0 || style === 'synthwave') {
          ajouter(tb, 0.35, (t) => Math.sin(2 * Math.PI * (45 + 90 * Math.exp(-t * 30)) * t) * Math.exp(-t * 9) * 0.5);
        }
        if (b % 2 === 1) {
          ajouter(tb, 0.25, (t) => ((rnd() * 2 - 1) * 0.7 + Math.sin(2 * Math.PI * 190 * t) * 0.3) * Math.exp(-t * (style === 'lofi' ? 14 : 20)) * 0.22);
        }
        for (let h = 0; h < 2; h++) {
          const swing = style === 'lofi' && h ? temps * 0.08 : 0;
          ajouter(tb + h * (temps / 2) + swing, 0.06, (t) => (rnd() * 2 - 1) * Math.exp(-t * 70) * 0.06);
        }
      }
    }
  }

  // Grésillement vinyle pour le lo-fi
  if (style === 'lofi' || style === 'brume') {
    for (let i = 0; i < n; i++) if (rnd() < 0.0004) sortie[i] += (rnd() * 2 - 1) * 0.25;
  }

  // Écho (delay avec réinjection) puis filtre doux, fondu et saturation douce.
  const retard = Math.floor(temps * 0.75 * TAUX);
  const reinjection = style === 'ambient' || style === 'brume' ? 0.55 : 0.3;
  for (let i = retard; i < n; i++) sortie[i] += sortie[i - retard] * reinjection;
  const coef = style === 'lofi' || style === 'brume' ? 0.35 : 0.6;
  let max = 0;
  for (let i = 0; i < n; i++) {
    filtre += coef * (sortie[i] - filtre);
    sortie[i] = Math.tanh(filtre * 1.4) * fondu(i / TAUX);
    max = Math.max(max, Math.abs(sortie[i]));
  }
  for (let i = 0; i < n; i++) sortie[i] = (sortie[i] / (max || 1)) * 0.85;
  return sortie;
}

// --- Écriture WAV + tags RIFF INFO -------------------------------------------

function chunkInfo(tags) {
  const morceaux = Object.entries(tags).map(([cle, valeur]) => {
    // Les tags RIFF INFO sont lus en Latin-1 par les lecteurs.
    let donnees = Buffer.from(`${valeur}\0`, 'latin1');
    if (donnees.length % 2) donnees = Buffer.concat([donnees, Buffer.alloc(1)]);
    const entete = Buffer.alloc(8);
    entete.write(cle, 0, 'ascii');
    entete.writeUInt32LE(Buffer.byteLength(`${valeur}\0`, 'latin1'), 4);
    return Buffer.concat([entete, donnees]);
  });
  const corps = Buffer.concat([Buffer.from('INFO'), ...morceaux]);
  const entete = Buffer.alloc(8);
  entete.write('LIST', 0, 'ascii');
  entete.writeUInt32LE(corps.length, 4);
  return Buffer.concat([entete, corps]);
}

function ecrireWav(fichier, echantillons, tags) {
  const donnees = Buffer.alloc(echantillons.length * 2);
  for (let i = 0; i < echantillons.length; i++) donnees.writeInt16LE(Math.round(Math.max(-1, Math.min(1, echantillons[i])) * 32767), i * 2);
  const fmt = Buffer.alloc(24);
  fmt.write('fmt ', 0, 'ascii');
  fmt.writeUInt32LE(16, 4);
  fmt.writeUInt16LE(1, 8); // PCM
  fmt.writeUInt16LE(1, 10); // mono
  fmt.writeUInt32LE(TAUX, 12);
  fmt.writeUInt32LE(TAUX * 2, 16);
  fmt.writeUInt16LE(2, 20);
  fmt.writeUInt16LE(16, 22);
  const info = chunkInfo(tags);
  const enteteData = Buffer.alloc(8);
  enteteData.write('data', 0, 'ascii');
  enteteData.writeUInt32LE(donnees.length, 4);
  const riff = Buffer.alloc(12);
  riff.write('RIFF', 0, 'ascii');
  riff.writeUInt32LE(4 + fmt.length + info.length + enteteData.length + donnees.length, 4);
  riff.write('WAVE', 8, 'ascii');
  fs.writeFileSync(fichier, Buffer.concat([riff, fmt, info, enteteData, donnees]));
}

// --- Pochettes SVG ------------------------------------------------------------

const echapper = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');

function pochette({ album, artiste, style, couleurs: [fond, accent, clair] }) {
  let motif = '';
  if (style === 'synthwave') {
    motif = `<circle cx="300" cy="300" r="150" fill="url(#soleil)"/>` +
      Array.from({ length: 6 }, (_, i) => `<rect x="140" y="${318 + i * 22}" width="320" height="${4 + i * 2}" fill="${fond}"/>`).join('') +
      Array.from({ length: 9 }, (_, i) => `<line x1="${300 + (i - 4) * 30}" y1="450" x2="${300 + (i - 4) * 160}" y2="600" stroke="${accent}" stroke-width="2" opacity=".7"/>`).join('') +
      Array.from({ length: 5 }, (_, i) => `<line x1="0" y1="${460 + i * i * 9}" x2="600" y2="${460 + i * i * 9}" stroke="${accent}" stroke-width="2" opacity=".7"/>`).join('');
  } else if (style === 'lofi' || style === 'brume') {
    motif = `<circle cx="300" cy="290" r="170" fill="${accent}" opacity=".25"/><circle cx="300" cy="290" r="120" fill="${fond}" stroke="${clair}" stroke-width="6"/>` +
      `<circle cx="300" cy="290" r="40" fill="${accent}"/><circle cx="300" cy="290" r="8" fill="${fond}"/>` +
      Array.from({ length: 4 }, (_, i) => `<circle cx="300" cy="290" r="${60 + i * 14}" fill="none" stroke="${clair}" stroke-opacity=".18"/>`).join('');
  } else if (style === 'ambient') {
    motif = Array.from({ length: 5 }, (_, i) => `<path d="M0 ${330 + i * 30} C 150 ${230 + i * 40}, 300 ${400 - i * 20}, 600 ${280 + i * 35}" stroke="${i % 2 ? accent : clair}" stroke-width="${18 - i * 3}" fill="none" opacity="${0.75 - i * 0.12}"/>`).join('') +
      Array.from({ length: 40 }, (_, i) => `<circle cx="${(i * 137) % 600}" cy="${(i * 71) % 260}" r="${1 + (i % 3)}" fill="#fff" opacity=".8"/>`).join('');
  } else {
    motif = Array.from({ length: 12 * 12 }, (_, i) => {
      const x = i % 12, y = Math.floor(i / 12);
      const plein = (x * 7 + y * 3 + x * y) % 5 === 0;
      return plein ? `<rect x="${60 + x * 40}" y="${40 + y * 40}" width="36" height="36" fill="${(x + y) % 2 ? accent : clair}"/>` : '';
    }).join('');
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600" viewBox="0 0 600 600">
<defs>
<linearGradient id="fond" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${fond}"/><stop offset="1" stop-color="#000"/></linearGradient>
<linearGradient id="soleil" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${clair}"/><stop offset="1" stop-color="${accent}"/></linearGradient>
</defs>
<rect width="600" height="600" fill="url(#fond)"/>
${motif}
<rect y="500" width="600" height="100" fill="#000" opacity=".35"/>
<text x="30" y="545" font-family="Helvetica, Arial, sans-serif" font-size="36" font-weight="700" fill="#fff">${echapper(album)}</text>
<text x="30" y="580" font-family="Helvetica, Arial, sans-serif" font-size="22" fill="#fff" opacity=".8">${echapper(artiste)}</text>
</svg>`;
}

// --- Génération ---------------------------------------------------------------

const fichierLrc = (lignes) =>
  lignes.map(([s, texte]) => `[${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}.00]${texte}`).join('\n') + '\n';

function contientAudio(dossier) {
  try {
    for (const e of fs.readdirSync(dossier, { withFileTypes: true })) {
      if (e.isDirectory() && contientAudio(path.join(dossier, e.name))) return true;
      if (e.isFile() && /\.(mp3|m4a|aac|flac|ogg|oga|opus|wav|webm)$/i.test(e.name)) return true;
    }
  } catch {}
  return false;
}

export async function genererDemo({ forcer = false } = {}) {
  if (!forcer && contientAudio(DOSSIER_MUSIQUE_DEFAUT)) return false;
  console.log('Génération de la musique de démonstration…');
  let graine = 7;
  for (const album of CATALOGUE) {
    const dossier = path.join(DOSSIER_DEMO, `${album.artiste} - ${album.album}`);
    fs.mkdirSync(dossier, { recursive: true });
    fs.writeFileSync(path.join(dossier, 'cover.svg'), pochette(album));
    album.titres.forEach((t, i) => {
      const base = `${String(i + 1).padStart(2, '0')} ${t.titre.replace(/[/:]/g, '-')}`;
      const audio = genererTitre(album.style, t, graine++ * 7919);
      ecrireWav(path.join(dossier, `${base}.wav`), audio, {
        INAM: t.titre,
        IART: t.artiste || album.artisteTitre || album.artiste,
        IPRD: album.album,
        IGNR: album.genre,
        ICRD: String(album.annee),
        ITRK: String(i + 1),
      });
      if (t.paroles) fs.writeFileSync(path.join(dossier, `${base}.lrc`), fichierLrc(PAROLES[t.paroles]));
      process.stdout.write('.');
    });
  }
  console.log(`\nDémo prête dans ${DOSSIER_DEMO}`);
  return true;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await genererDemo({ forcer: process.argv.includes('--force') });
}
