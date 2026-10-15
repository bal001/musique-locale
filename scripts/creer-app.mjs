// Crée l'application Mac "YouTube Musique Locale.app" dans ~/Applications : npm run app
// 1. construit l'interface (vite build)
// 2. génère l'icône .icns à partir de public/icone.svg
// 3. emballe un lanceur Electron minimal qui charge electron/principal.mjs depuis ce dossier
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { packager } from '@electron/packager';

const RACINE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const NOM = 'YouTube Musique Locale';
const TRAVAIL = path.join(RACINE, 'build-app');
const DESTINATION = path.join(os.homedir(), 'Applications');
const require = createRequire(import.meta.url);

const etape = (texte) => console.log(`\n▶ ${texte}`);
const executer = (cmd, args, options = {}) => execFileSync(cmd, args, { stdio: 'inherit', ...options });

fs.rmSync(TRAVAIL, { recursive: true, force: true });
fs.mkdirSync(TRAVAIL, { recursive: true });

etape("Construction de l'interface");
executer(process.execPath, [path.join(RACINE, 'node_modules/vite/bin/vite.js'), 'build'], { cwd: RACINE });

etape("Création de l'icône");
const iconset = path.join(TRAVAIL, 'icone.iconset');
fs.mkdirSync(iconset);
// Quick Look sait rendre un SVG en PNG sans dépendance supplémentaire.
executer('qlmanage', ['-t', '-s', '1024', '-o', TRAVAIL, path.join(RACINE, 'public/icone.svg')], { stdio: 'ignore' });
const png = path.join(TRAVAIL, 'icone.svg.png');
for (const taille of [16, 32, 128, 256, 512]) {
  for (const echelle of [1, 2]) {
    const px = taille * echelle;
    const nom = `icon_${taille}x${taille}${echelle === 2 ? '@2x' : ''}.png`;
    executer('sips', ['-z', String(px), String(px), png, '--out', path.join(iconset, nom)], { stdio: 'ignore' });
  }
}
const icns = path.join(TRAVAIL, 'icone.icns');
executer('iconutil', ['-c', 'icns', iconset, '-o', icns]);

etape('Préparation du lanceur');
const coquille = path.join(TRAVAIL, 'coquille');
fs.mkdirSync(coquille);
fs.writeFileSync(
  path.join(coquille, 'package.json'),
  JSON.stringify({ name: 'youtube-musique-locale', productName: NOM, version: '1.0.0', main: 'lanceur.cjs' }, null, 2),
);
fs.writeFileSync(
  path.join(coquille, 'lanceur.cjs'),
  `// Généré par scripts/creer-app.mjs : charge l'application depuis le dossier du projet.
const { pathToFileURL } = require('node:url');
const RACINE = ${JSON.stringify(RACINE)};
import(pathToFileURL(RACINE + '/electron/principal.mjs').href).catch((err) => {
  const { app, dialog } = require('electron');
  app.whenReady().then(() => {
    dialog.showErrorBox(${JSON.stringify(NOM)}, 'Projet introuvable dans ' + RACINE + '\\n\\n' + err.message);
    app.quit();
  });
});
`,
);

etape("Emballage de l'application");
const [chemin] = await packager({
  dir: coquille,
  name: NOM,
  executableName: NOM,
  appBundleId: 'local.youtube-musique-locale',
  appCategoryType: 'public.app-category.music',
  platform: 'darwin',
  arch: process.arch,
  electronVersion: require('electron/package.json').version,
  icon: icns,
  out: path.join(TRAVAIL, 'sortie'),
  overwrite: true,
  asar: false,
  prune: false,
  quiet: true,
});
const app = path.join(chemin, `${NOM}.app`);

// Signature ad hoc : obligatoire pour lancer une app sur Mac Apple Silicon.
executer('codesign', ['--force', '--deep', '--sign', '-', app], { stdio: 'ignore' });

etape(`Installation dans ${DESTINATION}`);
fs.mkdirSync(DESTINATION, { recursive: true });
const cible = path.join(DESTINATION, `${NOM}.app`);
fs.rmSync(cible, { recursive: true, force: true });
executer('ditto', [app, cible]);
fs.rmSync(TRAVAIL, { recursive: true, force: true });

console.log(`\n✓ Application prête : ${cible}\n  Ouvrez-la depuis le Finder, le Launchpad ou Spotlight (« ${NOM} »).\n`);
