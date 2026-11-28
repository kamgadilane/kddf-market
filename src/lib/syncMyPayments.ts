import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { syncFapshiTransaction } from "@/lib/fulfillment";
import { asRows } from "@/lib/db";

/**
 * Rattrapage à la demande pour UN acheteur connecté : ses paiements en ligne encore « en attente » (moins de 26 h)
 * sont revérifiés chez le fournisseur. Utile quand le webhook n'est pas arrivé et que l'acheteur ouvre « Mes achats »
 * au lieu de revenir sur la page de retour. Chaque transaction est limitée à une vérification toutes les 20 secondes.
 * Ne lève jamais d'exception ; renvoie le nombre de paiements validés.
 */
export async function syncMyPendingPayments(userId: string): Promise<number> {
  try {
    const db = createAdminClient();
    const since = new Date(Date.now() - 26 * 3600 * 1000).toISOString();
    const { data: orders } = await db
      .from("orders")
      .select("id")
      .eq("buyer_id", userId)
      .eq("payment_method", "online")
      .in("payment_status", ["pending", "failed"])
      .gte("created_at", since)
      .order("created_at", { ascending: false })
      .limit(5);
    const ids = asRows<{ id: string }>(orders).map((o) => o.id);
    if (ids.length === 0) return 0;

    const { data: txs } = await db.from("transactions").select("fapshi_trans_id").in("order_id", ids).not("fapshi_trans_id", "is", null);
    let paid = 0;
    for (const t of asRows<{ fapshi_trans_id: string }>(txs)) {
      const r = await syncFapshiTransaction(t.fapshi_trans_id, { source: "verification", minAgeSeconds: 20 });
      if (r === "paid") paid += 1;
    }
    return paid;
  } catch (e) {
    console.error("[mes achats] rattrapage impossible :", e instanceof Error ? e.message : e);
    return 0;
  }
}
