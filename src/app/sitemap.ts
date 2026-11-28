import type { MetadataRoute } from "next";
import { appUrl } from "@/lib/env";
import { createAdminClient } from "@/lib/supabase/admin";
import { asRows } from "@/lib/db";

export const dynamic = "force-dynamic";

/** Plan du site pour Google : pages publiques, produits publiés et validés, boutiques. Jamais d'erreur : sans base, seules les pages fixes sont listées. */
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const base = appUrl();
  const now = new Date();
  const fixed = ["", "/grossistes", "/services", "/suivre-commande", "/support", "/international", "/conditions", "/confidentialite", "/remboursement", "/mentions-legales"].map((p) => ({
    url: `${base}${p}`,
    lastModified: now,
  }));
  try {
    const db = createAdminClient();
    const [{ data: products }, { data: shops }] = await Promise.all([
      db.from("products").select("id, updated_at").eq("is_published", true).eq("moderation_status", "approved").order("created_at", { ascending: false }).limit(2000),
      db.from("public_profiles").select("store_slug").not("store_slug", "is", null).limit(1000),
    ]);
    return [
      ...fixed,
      ...asRows<{ id: string; updated_at: string | null }>(products).map((p) => ({ url: `${base}/p/${p.id}`, lastModified: p.updated_at ? new Date(p.updated_at) : now })),
      ...asRows<{ store_slug: string }>(shops).map((s) => ({ url: `${base}/boutique/${s.store_slug}`, lastModified: now })),
    ];
  } catch {
    return fixed;
  }
}
