import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { SHARE_CHANNELS } from "@/lib/share";
import { isUuid } from "@/lib/validate";
import { rateLimitIp } from "@/lib/rateLimit";

export const runtime = "nodejs";

// Enregistre un partage (sert à repérer les produits "endormis" : 0 partage depuis 3 jours).
export async function POST(req: Request): Promise<NextResponse> {
  // Anti-abus : 60 partages comptés par IP et par heure
  if (!(await rateLimitIp(req, "share", 60, 3600))) return NextResponse.json({ ok: true });
  const body: unknown = await req.json().catch(() => null);
  const b = body !== null && typeof body === "object" ? (body as Record<string, unknown>) : {};
  if (!isUuid(b.productId) || typeof b.channel !== "string" || !SHARE_CHANNELS.includes(b.channel)) {
    return NextResponse.json({ ok: false }, { status: 400 });
  }
  await createAdminClient().from("product_shares").insert({ product_id: b.productId, channel: b.channel });
  return NextResponse.json({ ok: true });
}
