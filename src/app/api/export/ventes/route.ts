import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { rateLimit } from "@/lib/rateLimit";
import { asRows } from "@/lib/db";
import { csvResponse, dayStamp, toCsv } from "@/lib/csv";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface Row {
  paid_at: string | null;
  order_code: string | null;
  total_amount: number;
  service_fee: number;
  platform_fee: number | null;
  affiliate_fee: number | null;
  seller_amount: number | null;
  status: string;
  product: { title: string } | null;
}

/** GET /api/export/ventes : les ventes du vendeur connecté (RLS : uniquement les siennes), au format CSV pour Excel. */
export async function GET(): Promise<Response> {
  const supabase = createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return NextResponse.json({ error: "Connectez-vous pour exporter vos ventes." }, { status: 401 });
  if (!(await rateLimit(`export-ventes:${auth.user.id}`, 20, 3600))) return NextResponse.json({ error: "Trop d'exports. Réessayez dans une heure." }, { status: 429 });
  const { data, error } = await supabase
    .from("transactions")
    .select("paid_at, order_code, total_amount, service_fee, platform_fee, affiliate_fee, seller_amount, status, product:products!product_id(title)")
    .eq("seller_id", auth.user.id)
    .eq("status", "paid")
    .order("paid_at", { ascending: false })
    .limit(5000);
  if (error) return NextResponse.json({ error: "Export impossible pour le moment." }, { status: 500 });
  const rows = asRows<Row>(data).map((r) => [
    r.paid_at ? new Date(r.paid_at).toISOString().slice(0, 16).replace("T", " ") : "",
    r.order_code ?? "",
    r.product?.title ?? "",
    r.total_amount - (r.service_fee ?? 0), // ce que le vendeur a vendu : sans les frais de service de l'acheteur
    r.platform_fee ?? 0,
    r.affiliate_fee ?? 0,
    r.seller_amount ?? 0,
  ]);
  return csvResponse(`mes-ventes-${dayStamp()}.csv`, toCsv(["Date (UTC)", "Code commande", "Produit", "Vente FCFA", "Commission KDDF FCFA", "Part affilié FCFA", "Votre part FCFA"], rows));
}
