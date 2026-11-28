import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { rateLimitIp } from "@/lib/rateLimit";
import { cleanText } from "@/lib/validate";
import { alertAdminsOfError } from "@/lib/adminAlert";
import { adviceFor } from "@/lib/errorAdvice";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * POST /api/errors : journal des erreurs d'affichage (page qui plante chez un visiteur).
 * Limité à 20 envois par adresse IP et par 10 minutes ; textes tronqués ; jamais de données personnelles (ni cookies, ni formulaires).
 * Alerte l'administrateur (cloche + email avec notice « que faire », 1 par 30 minutes) pour les erreurs qui comptent.
 * Répond toujours 204 : le navigateur n'a rien à faire du résultat.
 */
export async function POST(req: Request): Promise<NextResponse> {
  if (!(await rateLimitIp(req, "errors", 20, 600))) return new NextResponse(null, { status: 204 });
  const body: unknown = await req.json().catch(() => null);
  if (body === null || typeof body !== "object") return new NextResponse(null, { status: 204 });
  const b = body as Record<string, unknown>;
  const message = cleanText(b.message, 500);
  if (message === "") return new NextResponse(null, { status: 204 });
  const url = cleanText(b.url, 300);
  const digest = cleanText(b.digest, 80);
  try {
    const { data } = await createClient().auth.getUser();
    await createAdminClient().rpc("log_app_error", {
      p_source: "client",
      p_message: message,
      p_url: url.startsWith("/") ? url : null,
      p_digest: digest || null,
      p_user: data.user?.id ?? null,
    });
    // Erreurs sans gravité (fichier périmé après une mise à jour, session expirée...) : journal seulement, pas d'alerte
    if (adviceFor(message).urgency > 0) {
      await alertAdminsOfError({ message, url: url.startsWith("/") ? url : null, digest: digest || null });
    }
  } catch {
    /* le journal ne doit jamais provoquer d'erreur */
  }
  return new NextResponse(null, { status: 204 });
}
