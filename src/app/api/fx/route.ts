import { NextResponse } from "next/server";
import { FxUnavailableError, fxMarginPercent, getFxRates } from "@/lib/fx";
import { rateLimitIp, tooManyRequests } from "@/lib/rateLimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Taux de change publics (FCFA, EUR, USD, GBP, CAD) pour l'affichage du total avant le paiement. Aucune donnée privée. */
export async function GET(req: Request): Promise<NextResponse> {
  if (!(await rateLimitIp(req, "fx", 60, 600))) return tooManyRequests();
  try {
    const rates = await getFxRates();
    return NextResponse.json(
      { rates, marginPercent: fxMarginPercent() },
      { headers: { "Cache-Control": "public, s-maxage=300, stale-while-revalidate=600" } },
    );
  } catch (e) {
    if (e instanceof FxUnavailableError) return NextResponse.json({ error: "Taux de change momentanément indisponibles. Les paiements en FCFA restent possibles." }, { status: 503 });
    console.error("[api/fx]", e instanceof Error ? e.message : e);
    return NextResponse.json({ error: "Erreur serveur." }, { status: 500 });
  }
}
