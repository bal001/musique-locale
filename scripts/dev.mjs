// Lance le serveur API (avec rechargement auto) et Vite ensemble : npm run dev
import { spawn } from 'node:child_process';

const processus = [
  spawn(process.execPath, ['--watch-path=server', 'server/index.mjs'], { stdio: 'inherit' }),
  spawn(process.execPath, ['node_modules/vite/bin/vite.js', '--open'], { stdio: 'inherit' }),
];
const arreter = () => processus.forEach((p) => p.kill());
process.on('SIGINT', arreter);
process.on('SIGTERM', arreter);
processus.forEach((p) => p.on('exit', (code) => { arreter(); process.exit(code ?? 0); }));
