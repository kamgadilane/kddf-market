import "server-only";
import { createClient } from "@supabase/supabase-js";

// Client à privilèges élevés (clé service_role) : UNIQUEMENT côté serveur (webhooks, API, tâches).
// L'import "server-only" fait échouer le build si un composant client tente de l'importer : la clé ne peut jamais partir dans le navigateur.
export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("Configuration Supabase incomplète : NEXT_PUBLIC_SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont obligatoires.");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}
