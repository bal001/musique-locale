import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// En dev, Vite sert l'interface (port 5317) et redirige /api vers le serveur Node (port 4317).
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5317,
    strictPort: true,
    proxy: { '/api': 'http://127.0.0.1:4317' },
  },
});
