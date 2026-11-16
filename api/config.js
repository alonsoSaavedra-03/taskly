// Vercel Serverless Function: expone únicamente la configuración pública de Supabase
// NUNCA expone service_role ni secretos administrativos.
module.exports = function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Cache-Control', 'no-store, max-age=0');

  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

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

  return res.status(200).json({
    supabaseUrl,
    supabasePublishableKey,
    oauthGoogleConfigured,
    configured: Boolean(supabaseUrl && supabasePublishableKey && !supabaseUrl.includes('tu-proyecto-id')),
    version: '1.0.0'
  });
};
