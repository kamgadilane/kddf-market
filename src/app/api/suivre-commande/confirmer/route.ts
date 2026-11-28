import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { dbErrorMessage } from "@/lib/labels";
import { NOT_FOUND_MESSAGE, readGuestKey, trackGuestOrder } from "@/lib/guestTrack";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Le client sans compte confirme qu'il a reçu sa commande (Numéro + Code). */
export async function POST(req: Request) {
  const body: unknown = await req.json().catch(() => null);
  const b = (body ?? {}) as { phone?: unknown; code?: unknown };
  const k = await readGuestKey(req, b.phone, b.code);
  if (!k.ok) return NextResponse.json({ error: k.error }, { status: k.status });
  const { error } = await createAdminClient().rpc("guest_confirm_delivery", { p_phone: k.key.phone, p_code: k.key.code });
  if (error) {
    if (error.message.includes("commande_introuvable")) return NextResponse.json({ error: NOT_FOUND_MESSAGE }, { status: 404 });
    return NextResponse.json({ error: dbErrorMessage(error.message) }, { status: 400 });
  }
  const order = await trackGuestOrder(k.key);
  return NextResponse.json({ ok: true, order }, { headers: { "Cache-Control": "no-store" } });
}
