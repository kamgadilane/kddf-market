import "server-only";
import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { clientIpFrom } from "@/lib/clientIp";

/**
 * Limitation de débit (anti-abus), compteur atomique dans la base (fonction SQL rate_limit_hit).
 * true = autorisé. Si la base ne répond pas, on laisse passer (jamais bloquer de vrais clients par erreur technique).
 */
export async function rateLimit(key: string, limit: number, windowSeconds: number): Promise<boolean> {
  try {
    const { data, error } = await createAdminClient().rpc("rate_limit_hit", {
      p_key: key,
      p_limit: limit,
      p_window_seconds: windowSeconds,
    });
    if (error) return true;
    return data !== false;
  } catch {
    return true;
  }
}

/** Même chose, avec une clé propre à l'adresse IP du visiteur. Sans IP lisible : autorisé. */
export async function rateLimitIp(req: Request, name: string, limit: number, windowSeconds: number): Promise<boolean> {
  const ip = clientIpFrom(req.headers);
  if (!ip) return true;
  return rateLimit(`${name}:${ip}`, limit, windowSeconds);
}

/** Réponse standard « trop de demandes ». */
export function tooManyRequests(message = "Trop de demandes en peu de temps. Patientez une minute puis réessayez."): NextResponse {
  return NextResponse.json({ error: message }, { status: 429, headers: { "Retry-After": "60" } });
}
