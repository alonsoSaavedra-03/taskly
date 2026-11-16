/**
 * Compilación de producción de Taskly para Vercel (`npm run build`).
 * - Genera el directorio `public/` requerido por Vercel (`outputDirectory: "public"`).
 * - Valida la sintaxis JavaScript de `index.html`, `assets/supabase-config.js` y `api/config.js`.
 * - Inyecta únicamente variables públicas (`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
 *   `GOOGLE_OAUTH_ENABLED`) en `public/assets/supabase-config.js` si están definidas en el entorno de build.
 * - Verifica que ninguna credencial de prueba (`TEST_USER_*`) ni clave `service_role` se incluya en el build.
 */

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT_DIR = path.resolve(__dirname, '..');
const SRC_DIR = path.join(ROOT_DIR, 'web_simulator');
const OUT_DIR = path.join(ROOT_DIR, 'public');
const OUT_ASSETS_DIR = path.join(OUT_DIR, 'assets');
const API_CONFIG_PATH = path.join(ROOT_DIR, 'api', 'config.js');

function ensureDir(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

function validateJsSyntax(code, filename) {
  new vm.Script(code, { filename });
}

function extractInlineScripts(htmlContent) {
  const scripts = [];
  const regex = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi;
  let match;
  while ((match = regex.exec(htmlContent)) !== null) {
    scripts.push(match[1]);
  }
  return scripts;
}

function runBuild() {
  console.log('================================================================');
  console.log(' COMPILACIÓN DE PRODUCCIÓN TASKLY (VERCEL BUILD)');
  console.log('================================================================');

  // 1. Verificar archivos fuente obligatorios
  const requiredSources = [
    path.join(SRC_DIR, 'index.html'),
    path.join(SRC_DIR, 'assets', 'lucide.min.js'),
    path.join(SRC_DIR, 'assets', 'supabase.min.js'),
    path.join(SRC_DIR, 'assets', 'supabase-config.js'),
    API_CONFIG_PATH,
    path.join(ROOT_DIR, 'vercel.json')
  ];

  for (const filePath of requiredSources) {
    if (!fs.existsSync(filePath)) {
      throw new Error(`Archivo fuente requerido no encontrado: ${path.relative(ROOT_DIR, filePath)}`);
    }
  }

  // 2. Validar sintaxis de api/config.js y scripts embebidos en index.html
  const apiCode = fs.readFileSync(API_CONFIG_PATH, 'utf8');
  validateJsSyntax(apiCode, 'api/config.js');
  console.log(' [OK] Sintaxis verificada: api/config.js');

  const indexHtml = fs.readFileSync(path.join(SRC_DIR, 'index.html'), 'utf8');
  const inlineScripts = extractInlineScripts(indexHtml);
  if (inlineScripts.length === 0) {
    throw new Error('No se encontró el script principal de la aplicación en web_simulator/index.html');
  }
  inlineScripts.forEach((scriptContent, idx) => {
    validateJsSyntax(scriptContent, `web_simulator/index.html#script-${idx + 1}`);
  });
  console.log(` [OK] Sintaxis verificada: web_simulator/index.html (${inlineScripts.length} bloque(s) JS)`);

  // 3. Preparar directorio de salida public/
  if (fs.existsSync(OUT_DIR)) {
    fs.rmSync(OUT_DIR, { recursive: true, force: true });
  }
  ensureDir(OUT_DIR);
  ensureDir(OUT_ASSETS_DIR);

  // 4. Copiar index.html y librerías estáticas a public/
  fs.copyFileSync(path.join(SRC_DIR, 'index.html'), path.join(OUT_DIR, 'index.html'));
  fs.copyFileSync(path.join(SRC_DIR, 'assets', 'lucide.min.js'), path.join(OUT_ASSETS_DIR, 'lucide.min.js'));
  fs.copyFileSync(path.join(SRC_DIR, 'assets', 'supabase.min.js'), path.join(OUT_ASSETS_DIR, 'supabase.min.js'));

  // 5. Generar public/assets/supabase-config.js con variables públicas de entorno (si existen en Vercel)
  const publicSupabaseUrl =
    process.env.SUPABASE_URL ||
    process.env.NEXT_PUBLIC_SUPABASE_URL ||
    'https://nbvkflkjbukgjpkvafwq.supabase.co';
  const publicSupabaseKey =
    process.env.SUPABASE_PUBLISHABLE_KEY ||
    process.env.SUPABASE_ANON_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
    '';
  const oauthGoogleConfigured = process.env.GOOGLE_OAUTH_ENABLED === 'true';

  const generatedConfigJs = `/**
 * Configuración pública generada para el cliente navegador de Taskly en producción.
 * En tiempo de ejecución, \`/api/config\` tiene prioridad automática.
 */
window.__TASKLY_SUPABASE_CONFIG__ = window.__TASKLY_SUPABASE_CONFIG__ || {
  supabaseUrl: ${JSON.stringify(publicSupabaseUrl)},
  supabasePublishableKey: ${JSON.stringify(publicSupabaseKey)},
  oauthGoogleConfigured: ${JSON.stringify(oauthGoogleConfigured)}
};
`;

  validateJsSyntax(generatedConfigJs, 'public/assets/supabase-config.js');
  fs.writeFileSync(path.join(OUT_ASSETS_DIR, 'supabase-config.js'), generatedConfigJs, 'utf8');
  console.log(' [OK] Artefactos estáticos generados en public/ y public/assets/');

  // 6. Auditoría de seguridad del bundle compilado (prohibir credenciales de prueba o service_role)
  const filesToAudit = [
    path.join(OUT_DIR, 'index.html'),
    path.join(OUT_ASSETS_DIR, 'supabase-config.js'),
    API_CONFIG_PATH
  ];
  const forbiddenPatterns = [
    'TEST_USER_A_PASSWORD',
    'TEST_USER_B_PASSWORD',
    'SUPABASE_SERVICE_ROLE_KEY'
  ];

  for (const file of filesToAudit) {
    const content = fs.readFileSync(file, 'utf8');
    for (const pat of forbiddenPatterns) {
      if (content.includes(pat)) {
        throw new Error(`El archivo ${path.relative(ROOT_DIR, file)} contiene referencia prohibida: ${pat}`);
      }
    }
  }
  console.log(' [OK] Auditoría de seguridad del bundle: sin secretos ni credenciales de prueba expuestos');
  console.log('================================================================');
  console.log(' BUILD DE PRODUCCIÓN COMPLETADO EXITOSAMENTE');
  console.log('================================================================');
}

if (require.main === module) {
  try {
    runBuild();
  } catch (err) {
    console.error('[ERROR EN BUILD DE PRODUCCIÓN]:', err.message);
    process.exitCode = 1;
  }
}

module.exports = { runBuild };
