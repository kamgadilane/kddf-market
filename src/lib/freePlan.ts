import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { asRow } from "@/lib/db";

/** Nombre de produits PUBLIÉS autorisés au plan gratuit (réglable dans Admin > Commissions ; 0 = illimité). Les vendeurs Pro, exemptés et l'admin n'ont pas de limite. */
export const DEFAULT_FREE_PRODUCT_LIMIT = 10;

export async function getFreeProductLimit(): Promise<number> {
  try {
    const { data, error } = await createAdminClient().from("commission_settings").select("free_product_limit").eq("id", 1).maybeSingle();
    const n = Number(asRow<{ free_product_limit: number | string | null }>(data)?.free_product_limit);
    return !error && Number.isInteger(n) && n >= 0 ? n : DEFAULT_FREE_PRODUCT_LIMIT;
  } catch {
    return DEFAULT_FREE_PRODUCT_LIMIT;
  }
}
