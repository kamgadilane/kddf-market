import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { rateLimit } from "@/lib/rateLimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** GET /api/account/export : télécharge un fichier JSON avec les données personnelles de la personne connectée (profil, produits, achats, ventes, retraits). */
export async function GET(): Promise<NextResponse> {
  const supabase = createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return NextResponse.json({ error: "Connectez-vous pour télécharger vos données." }, { status: 401 });
  if (!(await rateLimit(`account-export:${auth.user.id}`, 5, 3600))) return NextResponse.json({ error: "Trop de téléchargements. Réessayez dans une heure." }, { status: 429 });
  const { data, error } = await supabase.rpc("export_my_data");
  if (error) return NextResponse.json({ error: "Export impossible pour le moment. Réessayez dans un instant." }, { status: 500 });
  const payload = { email: auth.user.email ?? null, ...(data as Record<string, unknown>) };
  return new NextResponse(JSON.stringify(payload, null, 2), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Disposition": 'attachment; filename="mes-donnees-kddf-market.json"',
      "Cache-Control": "no-store",
    },
  });
}
