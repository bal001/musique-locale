// Application Mac "YouTube Musique Locale" (Electron).
// Démarre le serveur local dans l'app puis ouvre l'interface dans une fenêtre native.
// Le .app installé (npm run app) ne contient qu'un lanceur qui charge CE fichier :
// toute modification du projet est prise en compte après "npm run build", sans réinstaller l'app.
import { app, BrowserWindow, dialog, screen, shell } from 'electron';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const RACINE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const NOM = 'YouTube Musique Locale';

app.setName(NOM);

let fenetre = null;
let quitter = false;

async function demarrerServeur() {
  if (!fs.existsSync(path.join(RACINE, 'dist', 'index.html'))) {
    throw new Error(`L'interface n'est pas construite.\nDans le dossier ${RACINE}, lancez : npm run build`);
  }
  const { pret } = await import(pathToFileURL(path.join(RACINE, 'server', 'index.mjs')).href);
  return pret;
}

function creerFenetre(url) {
  // La fenêtre doit toujours tenir entièrement dans l'écran (sinon le menu de gauche disparaît hors écran).
  const zone = screen.getPrimaryDisplay().workArea;
  const largeur = Math.min(1440, zone.width);
  const hauteur = Math.min(900, zone.height);
  fenetre = new BrowserWindow({
    width: largeur,
    height: hauteur,
    x: zone.x + Math.round((zone.width - largeur) / 2),
    y: zone.y + Math.round((zone.height - hauteur) / 2),
    minWidth: Math.min(900, zone.width),
    minHeight: Math.min(600, zone.height),
    title: NOM,
    backgroundColor: '#030304',
    titleBarStyle: 'hiddenInset', // feux tricolores intégrés à la barre du haut, comme une app Mac native
    trafficLightPosition: { x: 18, y: 24 },
    show: false,
    webPreferences: { contextIsolation: true, sandbox: true },
  });

  // Signale à l'interface qu'elle tourne dans l'app (zone de glissement, place pour les feux tricolores).
  fenetre.webContents.on('dom-ready', () => {
    fenetre.webContents.executeJavaScript("document.documentElement.classList.add('app-mac')").catch(() => {});
  });

  // Liens externes (YouTube Music, console Google…) → navigateur par défaut.
  fenetre.webContents.setWindowOpenHandler(({ url: cible }) => {
    if (/^https?:/.test(cible)) shell.openExternal(cible);
    return { action: 'deny' };
  });
  fenetre.webContents.on('will-navigate', (e, cible) => {
    if (!cible.startsWith(url)) {
      e.preventDefault();
      shell.openExternal(cible);
    }
  });

  // Fermer la fenêtre la cache seulement : la musique continue (comme l'app Musique). Cmd+Q quitte.
  fenetre.on('close', (e) => {
    if (!quitter) {
      e.preventDefault();
      fenetre.hide();
    }
  });

  // Au démarrage : au premier plan, sur le bureau courant, pour que l'utilisateur (et VoiceOver) y arrive directement.
  fenetre.once('ready-to-show', () => {
    fenetre.show();
    fenetre.focus();
    app.focus({ steal: true });
  });
  fenetre.loadURL(url);
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    fenetre?.show();
    fenetre?.focus();
  });
  app.on('activate', () => {
    fenetre?.show();
    fenetre?.focus();
  });
  app.on('before-quit', () => {
    quitter = true;
  });
  app.on('window-all-closed', () => app.quit());

  app.whenReady().then(async () => {
    try {
      const { url } = await demarrerServeur();
      creerFenetre(url);
    } catch (err) {
      dialog.showErrorBox(NOM, `Impossible de démarrer : ${err.message}`);
      app.quit();
    }
  });
}
