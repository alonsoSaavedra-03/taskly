/**
 * Configuración pública de Supabase para el cliente navegador de Taskly.
 * En Vercel o servidor local, `/api/config` inyecta automáticamente `SUPABASE_URL`
 * y `SUPABASE_PUBLISHABLE_KEY` desde las variables de entorno (`.env`).
 */
window.__TASKLY_SUPABASE_CONFIG__ = window.__TASKLY_SUPABASE_CONFIG__ || {
  supabaseUrl: 'https://nbvkflkjbukgjpkvafwq.supabase.co',
  supabasePublishableKey: '',
  oauthGoogleConfigured: false
};
