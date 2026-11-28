import { explain, explainPaymentError } from "@/lib/errors";
import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { initiatePay } from "@/lib/fapshi";
import { PRO_PLAN } from "@/lib/pro";
import { getTarifs } from "@/lib/tarifs";
import { appUrl } from "@/lib/env";
import { asRow } from "@/lib/db";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * POST /api/pro : le vendeur paie 30 jours d'abonnement Pro via Fapshi.
 * Le prix vient des réglages de l'admin (base de données, lus côté serveur), jamais du navigateur. L'abonnement n'est activé que quand Fapshi confirme le paiement
 * (webhook / page de retour / tâche planifiée), exactement comme pour un boost.
 */
export async function POST(): Promise<NextResponse> {
  const supabase = createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return NextResponse.json({ error: explain("Vous n'êtes pas connecté.", "Connectez-vous puis recommencez.") }, { status: 401 });

  const db = createAdminClient();
  const { proPrice } = await getTarifs();
  const { data: created, error } = await db.from("pro_subscriptions").insert({ user_id: auth.user.id, amount: proPrice }).select("id").single();
  const sub = asRow<{ id: string }>(created);
  if (error || !sub) return NextResponse.json({ error: explain("L'abonnement n'a pas pu être enregistré.", "Réessayez dans un instant. Aucun paiement n'a été effectué.") }, { status: 500 });

  try {
    const pay = await initiatePay({
      amount: proPrice,
      email: auth.user.email ?? "no-reply@kddf-market.app",
      redirectUrl: `${appUrl()}/dashboard/pro?abo=${sub.id}`,
      userId: auth.user.id,
      externalId: sub.id,
      message: `${PRO_PLAN.label} : ${PRO_PLAN.days} jours`,
    });
    const { error: saveError } = await db.from("pro_subscriptions").update({ fapshi_trans_id: pay.transId, fapshi_link: pay.link, fapshi_status: "CREATED" }).eq("id", sub.id);
    if (saveError) throw new Error(saveError.message);
    return NextResponse.json({ url: pay.link });
  } catch (e) {
    console.error("[pro] Fapshi indisponible", e instanceof Error ? e.message : e);
    await db.from("pro_subscriptions").update({ status: "failed", fapshi_status: "FAILED" }).eq("id", sub.id);
    return NextResponse.json({ error: explainPaymentError(e) }, { status: 502 });
  }
}
