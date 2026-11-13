import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

const BACKEND_ORIGIN = process.env.VITE_API_ORIGIN ?? 'http://127.0.0.1:8001';
const FRONTEND_HOST = 'localhost';
const FRONTEND_PORT = 5173;
const API_PREFIX = '/api';

// Local development runs two processes:
//   backend  -> uvicorn app.main:app --port 8001
//   frontend -> npm run dev (this config, port 5173)
// Requests to /api/* are proxied to the backend with the /api prefix stripped,
// which is how the deployed image serves the same endpoints.
export default defineConfig(({ command }) => ({
  plugins: [react()],
  define: {
    // Development calls the API through the proxy prefix.
    // Production builds share the API origin, so the prefix is empty; the
    // deployment images can override it with --build-arg VITE_API_PREFIX=...
    'import.meta.env.VITE_API_PREFIX': JSON.stringify(
      process.env.VITE_API_PREFIX ?? (command === 'serve' ? API_PREFIX : ''),
    ),
  },
  server: {
    host: FRONTEND_HOST,
    port: FRONTEND_PORT,
    strictPort: true,
    proxy: {
      [API_PREFIX]: {
        target: BACKEND_ORIGIN,
        changeOrigin: true,
        // The backend keeps its API paths unprefixed, so the dev prefix is
        // stripped - except for GET /api itself, which is a real route on the
        // backend (the JSON service index) and would otherwise be rewritten to
        // "/", where the backend serves the built SPA when one exists.
        rewrite: (path) =>
          path === API_PREFIX ? path : path.replace(/^\/api/, ''),
      },
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    sourcemap: false,
  },
}));
