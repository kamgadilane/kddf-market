import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { rateLimit } from "@/lib/rateLimit";
import { sendWelcomeIfNeeded } from "@/lib/welcome";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** POST /api/welcome : envoie l'email de bienvenue du compte connecté (une seule fois par compte). Ne bloque jamais l'utilisateur. */
export async function POST(): Promise<NextResponse> {
  try {
    const { data } = await createClient().auth.getUser();
    if (!data.user) return NextResponse.json({ ok: false }, { status: 401 });
    if (!(await rateLimit(`welcome:${data.user.id}`, 10, 3600))) return NextResponse.json({ ok: true, result: "throttled" });
    return NextResponse.json({ ok: true, result: await sendWelcomeIfNeeded() });
  } catch (e) {
    console.error("[bienvenue] erreur :", e instanceof Error ? e.message : e);
    return NextResponse.json({ ok: true, result: "failed" });
  }
}
