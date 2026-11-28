import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { clientIpFrom } from "@/lib/clientIp";
import { rateLimit } from "@/lib/rateLimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * POST /api/antifraud/ip : enregistre l'IP du compte connecté (lue dans les en-têtes Vercel, jamais fournie par le navigateur).
 * Sert à repérer plusieurs comptes sur une même IP (règle anti-fraude affiliation). Ne bloque jamais l'utilisateur.
 */
export async function POST(req: Request): Promise<NextResponse> {
  try {
    const { data } = await createClient().auth.getUser();
    if (!data.user) return NextResponse.json({ ok: false }, { status: 401 });
    const ip = clientIpFrom(req.headers);
    if (!ip) return NextResponse.json({ ok: true, recorded: false });
    if (!(await rateLimit(`ipbeacon:${data.user.id}`, 20, 3600))) return NextResponse.json({ ok: true, recorded: false });
    await createAdminClient().rpc("fraud_record_ip_for", { p_user: data.user.id, p_ip: ip });
    return NextResponse.json({ ok: true, recorded: true });
  } catch (e) {
    console.error("[antifraude] IP non enregistrée :", e instanceof Error ? e.message : e);
    return NextResponse.json({ ok: true, recorded: false });
  }
}
