import { NextResponse } from "next/server";
import { NOT_FOUND_MESSAGE, readGuestKey, trackGuestOrder } from "@/lib/guestTrack";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Suivi public d'une commande physique : Numéro + Code KDDF-XXXX, sans compte. */
export async function POST(req: Request) {
  const body: unknown = await req.json().catch(() => null);
  const b = (body ?? {}) as { phone?: unknown; code?: unknown };
  const k = await readGuestKey(req, b.phone, b.code);
  if (!k.ok) return NextResponse.json({ error: k.error }, { status: k.status });
  const order = await trackGuestOrder(k.key);
  if (!order) return NextResponse.json({ error: NOT_FOUND_MESSAGE }, { status: 404 });
  return NextResponse.json({ order }, { headers: { "Cache-Control": "no-store" } });
}
