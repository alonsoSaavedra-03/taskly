/**
 * Verificación de compilación de producción y runtime de Vercel (`npm run verify:vercel`).
 * - Ejecuta el build de producción (`scripts/build-vercel.js`) hacia `public/`.
 * - Ejecuta la función Serverless `api/config.js` en aislamiento y valida cabeceras y payload
 *   (sin imprimir claves ni tokens).
 * - Levanta un servidor efímero que aplica estrictamente las reglas de `vercel.json`
 *   (`outputDirectory: "public"` + `api/config.js`), independiente de `web_simulator/server.js`.
 * - Inicializa el cliente oficial `@supabase/supabase-js` usando únicamente la respuesta de `/api/config`
 *   y verifica conexión real contra Supabase.
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const { runBuild } = require('./build-vercel');

const ROOT_DIR = path.resolve(__dirname, '..');
const ENV_PATH = path.join(ROOT_DIR, '.env');
const VERCEL_JSON_PATH = path.join(ROOT_DIR, 'vercel.json');
const API_CONFIG_HANDLER = require(path.join(ROOT_DIR, 'api', 'config.js'));

function loadDotEnv(filePath) {
  if (!fs.existsSync(filePath)) return;
  const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const eqIdx = line.indexOf('=');
    if (eqIdx === -1) continue;
    const key = line.slice(0, eqIdx).trim();
    let val = line.slice(eqIdx + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    if (!process.env[key]) {
      process.env[key] = val;
    }
  }
}

async function verifyVercelProduction() {
  loadDotEnv(ENV_PATH);
  runBuild();

  console.log('\n================================================================');
  console.log(' VERIFICACIÓN DE CONFIGURACIÓN Y RUNTIME DE PRODUCCIÓN VERCEL');
  console.log('================================================================');

  const checks = [];
  function record(name, ok, detail = '') {
    checks.push({ name, ok });
    console.log(` [${ok ? 'APROBADA' : 'FALLIDA'}] ${name}${detail ? ' — ' + detail : ''}`);
  }

  // 1. Validar estructura de vercel.json
  const vercelCfg = JSON.parse(fs.readFileSync(VERCEL_JSON_PATH, 'utf8'));
  record(
    'Configuración vercel.json (version 2, buildCommand y outputDirectory="public")',
    vercelCfg.version === 2 &&
      vercelCfg.buildCommand === 'npm run build' &&
      vercelCfg.outputDirectory === 'public' &&
      Array.isArray(vercelCfg.rewrites) &&
      Array.isArray(vercelCfg.headers)
  );

  // 2. Invocar directamente la Serverless Function api/config.js (mock req/res de Vercel)
  let capturedStatus = null;
  let capturedBody = null;
  const capturedHeaders = {};
  const mockReq = { method: 'GET', headers: {} };
  const mockRes = {
    setHeader(k, v) {
      capturedHeaders[k.toLowerCase()] = v;
    },
    status(code) {
      capturedStatus = code;
      return this;
    },
    json(payload) {
      capturedBody = payload;
      return this;
    },
    end() {
      return this;
    }
  };

  API_CONFIG_HANDLER(mockReq, mockRes);

  const hasValidPublicConfig =
    capturedStatus === 200 &&
    capturedBody &&
    capturedBody.configured === true &&
    typeof capturedBody.supabaseUrl === 'string' &&
    capturedBody.supabaseUrl.startsWith('https://') &&
    typeof capturedBody.supabasePublishableKey === 'string' &&
    capturedBody.supabasePublishableKey.length > 15;

  record(
    'Serverless Function api/config.js devuelve HTTP 200 y configured=true',
    hasValidPublicConfig,
    `Cache-Control=${capturedHeaders['cache-control'] || 'none'}`
  );

  const rawJsonKeys = Object.keys(capturedBody || {});
  const leaksTestVars = rawJsonKeys.some((k) => k.toLowerCase().includes('test_user') || k.toLowerCase().includes('password') || k.toLowerCase().includes('service_role'));
  record(
    'Aislamiento de variables en api/config.js (no expone TEST_USER_* ni secretos)',
    !leaksTestVars,
    `Campos públicos expuestos: ${rawJsonKeys.join(', ')}`
  );

  // 3. Levantar emulador efímero que sirve exclusivamente public/ + api/config.js según vercel.json
  const publicDir = path.join(ROOT_DIR, 'public');
  const server = http.createServer((req, res) => {
    const urlPath = (req.url || '/').split('?')[0];
    if (urlPath === '/api/config' || urlPath === '/api/config.js') {
      res.status = function (c) {
        this.statusCode = c;
        return this;
      };
      res.json = function (obj) {
        this.setHeader('Content-Type', 'application/json; charset=utf-8');
        this.end(JSON.stringify(obj));
        return this;
      };
      return API_CONFIG_HANDLER(req, res);
    }

    let targetFile = path.join(publicDir, urlPath === '/' ? 'index.html' : urlPath.replace(/^\/+/, ''));
    if (!fs.existsSync(targetFile) || fs.statSync(targetFile).isDirectory()) {
      targetFile = path.join(publicDir, 'index.html');
    }

    const ext = path.extname(targetFile).toLowerCase();
    const mime =
      ext === '.html'
        ? 'text/html; charset=utf-8'
        : ext === '.js'
          ? 'application/javascript; charset=utf-8'
          : 'application/octet-stream';
    res.writeHead(200, {
      'Content-Type': mime,
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'SAMEORIGIN'
    });
    res.end(fs.readFileSync(targetFile));
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const [resRoot, resConfig, resLucide, resSupaBundle, resSupaCfg] = await Promise.all([
      fetch(`${baseUrl}/`),
      fetch(`${baseUrl}/api/config`),
      fetch(`${baseUrl}/assets/lucide.min.js`),
      fetch(`${baseUrl}/assets/supabase.min.js`),
      fetch(`${baseUrl}/assets/supabase-config.js`)
    ]);

    const htmlText = await resRoot.text();
    const apiConfigJson = await resConfig.json();

    record(
      'Ruta raíz "/" servida desde public/index.html con diseño íntegro',
      resRoot.status === 200 && htmlText.includes('Taskly') && htmlText.includes('/assets/supabase.min.js'),
      `HTTP ${resRoot.status} (${htmlText.length} bytes)`
    );

    record(
      'Rutas de activos "/assets/*" servidas desde public/assets/*',
      resLucide.status === 200 && resSupaBundle.status === 200 && resSupaCfg.status === 200,
      'lucide.min.js, supabase.min.js y supabase-config.js HTTP 200'
    );

    // 4. Conectar a Supabase real usando exclusivamente el JSON devuelto por /api/config
    const bundleCode = await resSupaBundle.text();
    const supabaseModule = new Function(bundleCode + '; return supabase;')();
    const prodClient = supabaseModule.createClient(
      apiConfigJson.supabaseUrl,
      apiConfigJson.supabasePublishableKey,
      { auth: { persistSession: false, autoRefreshToken: false } }
    );

    const { error: rlsAnonErr } = await prodClient.from('tasks').select('id').limit(1);
    record(
      'Conexión real a Supabase desde cliente inicializado vía /api/config de producción',
      Boolean(rlsAnonErr && /permission denied/i.test(rlsAnonErr.message)),
      'Endpoint responde y aplica protección RLS/privilegios correctamente'
    );
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }

  const failed = checks.filter((c) => !c.ok);
  console.log('\n================================================================');
  console.log(` RESUMEN VERCEL PROD: ${checks.length - failed.length}/${checks.length} APROBADAS`);
  console.log('================================================================');
  if (failed.length > 0) {
    process.exitCode = 1;
  }
}

verifyVercelProduction().catch((err) => {
  console.error('[ERROR EN VERIFICACIÓN VERCEL]:', err.message);
  process.exitCode = 1;
});
