import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { getMyProfile } from "@/lib/auth";
import { asRows } from "@/lib/db";
import { csvResponse, dayStamp, toCsv } from "@/lib/csv";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface Sale {
  paid_at: string | null;
  order_code: string | null;
  fapshi_medium: string | null;
  service_gateway: string | null;
  total_amount: number;
  service_fee: number;
  platform_fee: number | null;
  platform_fee_percent: number | null;
  affiliate_fee: number | null;
  seller_amount: number | null;
  fapshi_revenue: number | null;
  product: { title: string } | null;
}
interface Withdrawal {
  created_at: string;
  processed_at: string | null;
  amount: number;
  fee: number | null;
  method: string;
  status: string;
  express: boolean | null;
  user: { full_name: string | null; store_name: string | null } | null;
}

/** GET /api/admin/export?type=ventes|retraits : comptabilité en CSV, réservée à l'administrateur (les autres reçoivent 404). */
export async function GET(req: Request): Promise<Response> {
  const { data: auth } = await createClient().auth.getUser();
  if (!auth.user || (await getMyProfile(auth.user.id))?.role !== "admin") return new NextResponse(null, { status: 404 });
  const type = new URL(req.url).searchParams.get("type");
  const db = createAdminClient();

  if (type === "retraits") {
    const { data, error } = await db
      .from("withdrawals")
      .select("created_at, processed_at, amount, fee, method, status, express, user:profiles!user_id(full_name, store_name)")
      .order("created_at", { ascending: false })
      .limit(10000);
    if (error) return NextResponse.json({ error: "Export impossible." }, { status: 500 });
    const rows = asRows<Withdrawal>(data).map((r) => [
      r.created_at.slice(0, 16).replace("T", " "),
      r.processed_at ? r.processed_at.slice(0, 16).replace("T", " ") : "",
      r.user?.store_name ?? r.user?.full_name ?? "",
      r.amount,
      r.fee ?? 0,
      r.method,
      r.status,
      r.express === true,
    ]);
    return csvResponse(`retraits-${dayStamp()}.csv`, toCsv(["Demandé le (UTC)", "Traité le (UTC)", "Vendeur", "Montant FCFA", "Frais FCFA", "Moyen", "Statut", "Express"], rows));
  }

  const { data, error } = await db
    .from("transactions")
    .select("paid_at, order_code, fapshi_medium, service_gateway, total_amount, service_fee, platform_fee, platform_fee_percent, affiliate_fee, seller_amount, fapshi_revenue, product:products!product_id(title)")
    .eq("status", "paid")
    .order("paid_at", { ascending: false })
    .limit(10000);
  if (error) return NextResponse.json({ error: "Export impossible." }, { status: 500 });
  const rows = asRows<Sale>(data).map((r) => [
    r.paid_at ? r.paid_at.slice(0, 16).replace("T", " ") : "",
    r.order_code ?? "",
    r.product?.title ?? "",
    r.service_gateway ?? "",
    r.fapshi_medium ?? "",
    r.total_amount,
    r.service_fee ?? 0,
    r.platform_fee ?? 0,
    r.platform_fee_percent ?? 0,
    r.affiliate_fee ?? 0,
    r.seller_amount ?? 0,
    r.fapshi_revenue ?? "",
  ]);
  return csvResponse(`ventes-${dayStamp()}.csv`, toCsv(["Payé le (UTC)", "Code commande", "Produit", "Passerelle", "Moyen", "Total payé FCFA", "Frais de service FCFA", "Commission FCFA", "Taux %", "Part affilié FCFA", "Part vendeur FCFA", "Reçu après frais passerelle FCFA"], rows));
}
