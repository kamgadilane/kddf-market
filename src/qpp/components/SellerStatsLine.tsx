import { createClient } from "@/lib/supabase/server";
import { asRow } from "@/lib/db";

/** « 128 ventes · 96 % de satisfaction » (statistiques publiques de la boutique). */
export default async function SellerStatsLine({ sellerId }: { sellerId: string }) {
  const s = asRow<{ sales_count: number | string; satisfaction_percent: number | null }>(
    (await createClient().from("seller_public_stats").select("sales_count, satisfaction_percent").eq("seller_id", sellerId).maybeSingle()).data
  );
  if (!s) return null;
  const sales = Number(s.sales_count) || 0;
  return (
    <p className="text-sm text-zinc-400">
      {sales} vente{sales > 1 ? "s" : ""}
      {s.satisfaction_percent !== null && <> · {s.satisfaction_percent} % de satisfaction</>}
    </p>
  );
}
