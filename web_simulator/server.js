const http = require('http');
const fs = require('fs');
const path = require('path');

// Carga variables de entorno desde .env si existe
function loadEnvFile(filePath) {
  try {
    if (fs.existsSync(filePath)) {
      const content = fs.readFileSync(filePath, 'utf8');
      content.split(/\r?\n/).forEach(line => {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) return;
        const eqIdx = trimmed.indexOf('=');
        if (eqIdx > 0) {
          const key = trimmed.slice(0, eqIdx).trim();
          const val = trimmed.slice(eqIdx + 1).trim().replace(/^['"]|['"]$/g, '');
          if (val) process.env[key] = val;
        }
      });
    }
  } catch (_) {}
}

loadEnvFile(path.join(__dirname, '.env'));
loadEnvFile(path.join(__dirname, '..', '.env'));

const PORT = process.env.PORT || 3403;

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon'
};

/**
 * Servidor estático ligero para desarrollo local.
 * Toda la autenticación (registro, login, recuperación, sesiones) y la persistencia de datos
 * se realizan directamente contra Supabase Auth, PostgreSQL (RLS) y Supabase Realtime.
 * No almacena ni gestiona contraseñas de usuarios.
 */
const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'SAMEORIGIN');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  // Endpoint público de configuración (idéntico a /api/config.js en Vercel)
  if (url.pathname === '/api/config' && req.method === 'GET') {
    // Recargar .env en desarrollo por si el usuario acaba de editarlo
    loadEnvFile(path.join(__dirname, '.env'));
    loadEnvFile(path.join(__dirname, '..', '.env'));

    const supabaseUrl =
      process.env.SUPABASE_URL ||
      process.env.NEXT_PUBLIC_SUPABASE_URL ||
      '';
    const supabasePublishableKey =
      process.env.SUPABASE_PUBLISHABLE_KEY ||
      process.env.SUPABASE_ANON_KEY ||
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
      '';
    const oauthGoogleConfigured = process.env.GOOGLE_OAUTH_ENABLED === 'true';
    const configured = Boolean(
      supabaseUrl &&
      supabasePublishableKey &&
      !supabaseUrl.includes('tu-proyecto-id')
    );

    res.writeHead(200, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store, max-age=0'
    });
    return res.end(JSON.stringify({
      supabaseUrl,
      supabasePublishableKey,
      oauthGoogleConfigured,
      configured,
      version: '1.0.0'
    }));
  }

  // Servir archivos estáticos locales (/assets/lucide.min.js, /assets/supabase.min.js, etc.)
  if (url.pathname.startsWith('/assets/')) {
    const safeRel = path.normalize(url.pathname).replace(/^(\.\.(\/|\\|$))+/, '');
    const assetPath = path.join(__dirname, safeRel);
    if (fs.existsSync(assetPath) && fs.statSync(assetPath).isFile()) {
      const ext = path.extname(assetPath).toLowerCase();
      res.writeHead(200, {
        'Content-Type': MIME_TYPES[ext] || 'application/octet-stream',
        'Cache-Control': 'public, max-age=3600'
      });
      return res.end(fs.readFileSync(assetPath));
    }
    res.writeHead(404);
    return res.end('Asset not found');
  }

  // SPA fallback: sirve index.html para cualquier ruta de navegación
  if (req.method === 'GET' && !url.pathname.startsWith('/api/')) {
    const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(html);
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, () => {
  console.log(`Taskly 1.0 (Supabase Auth + PostgreSQL + Realtime) en http://localhost:${PORT}`);
});
