import AdminAffiliateCount from "@/components/AdminAffiliateCount";
import AutoRefresh from "@/components/AutoRefresh";
import StatCard from "@/components/StatCard";
import { createClient } from "@/lib/supabase/server";
import { asRow, asRows } from "@/lib/db";
import { formatFcfa } from "@/lib/money";
import { splitLine } from "@/lib/format";
import { TRANSACTION_STATUS_LABELS } from "@/lib/labels";
import type { Transaction } from "@/lib/types";
import { refundTransaction } from "./actions";
import Link from "next/link";

export const dynamic = "force-dynamic";
export const metadata = { title: "Administration", robots: { index: false } };

interface FeeRow { platform_fee_percent: number | null; sales: number; volume: number; platform_fees: number; affiliate_fees: number; seller_amounts: number; fapshi_received: number; service_fees?: number }
type Tx = Pick<Transaction, "id" | "order_id" | "total_amount" | "service_fee" | "platform_fee" | "affiliate_fee" | "seller_amount" | "affiliate_id" | "status" | "review_reason" | "released_at" | "fapshi_trans_id" | "paid_at" | "created_at">;
interface Stats { total_sellers: number; total_users: number; total_orders: number; commissions_today: number; commissions_month: number; commissions_due: number; products_pending: number; withdrawals_pending: number }

interface Overview { stats: Stats | null; fees: FeeRow[] | null; affiliates: number | string | null; boost_revenue: number | string | null; pro_revenue: number | string | null; pro_active: number | string | null; withdrawal_fees: number | string | null; service_fees?: number | string | null }

export default async function AdminPage() {
  // 2 requêtes de données : le tableau de bord (fonction SQL admin_overview) + les dernières transactions
  const supabase = createClient();
  const [{ data: overviewData }, { data: txData }] = await Promise.all([
    supabase.rpc("admin_overview"),
    supabase.from("transactions").select("id, order_id, total_amount, service_fee, platform_fee, affiliate_fee, seller_amount, affiliate_id, status, review_reason, released_at, fapshi_trans_id, paid_at, created_at").order("created_at", { ascending: false }).limit(60),
  ]);
  const overview = asRow<Overview>(overviewData);
  const boostRevenue = Number(overview?.boost_revenue ?? 0);
  const proRevenue = Number(overview?.pro_revenue ?? 0);
  const proActive = Number(overview?.pro_active ?? 0);
  const withdrawalFees = Number(overview?.withdrawal_fees ?? 0);
  const serviceFees = Number(overview?.service_fees ?? 0);
  const fees = overview?.fees ?? [];
  const txs = asRows<Tx>(txData);
  const stats = overview?.stats ?? null;

  const totalFees = fees.reduce((n, f) => n + Number(f.platform_fees), 0);
  const volume = fees.reduce((n, f) => n + Number(f.volume), 0);

  return (
    <div className="space-y-8">
      <AutoRefresh seconds={30} />
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="font-display text-3xl font-bold text-white">Administration</h1>
        <div className="flex flex-wrap gap-2">
          <a href="/api/admin/export?type=ventes" download className="btn-ghost !px-4 !py-2 text-sm">Exporter les ventes (Excel)</a>
          <a href="/api/admin/export?type=retraits" download className="btn-ghost !px-4 !py-2 text-sm">Exporter les retraits (Excel)</a>
        </div>
      </div>

      <section className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Nombre de vendeurs" value={String(stats?.total_sellers ?? 0)} />
        <AdminAffiliateCount value={Number(overview?.affiliates ?? 0)} />
        <StatCard label="Nombre de commandes" value={String(stats?.total_orders ?? 0)} />
        <StatCard label="Commissions aujourd'hui" value={formatFcfa(stats?.commissions_today ?? 0)} tone="jade" />
        <StatCard label="Commissions ce mois-ci" value={formatFcfa(stats?.commissions_month ?? 0)} tone="jade" />
      </section>

      <section className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Link href="/admin/products"><StatCard label="Produits à valider" value={String(stats?.products_pending ?? 0)} tone="volt" /></Link>
        <Link href="/admin/withdrawals"><StatCard label="Retraits en attente" value={String(stats?.withdrawals_pending ?? 0)} tone="volt" /></Link>
        <StatCard label="Commissions cash à encaisser" value={formatFcfa(stats?.commissions_due ?? 0)} hint="commission KDDF des ventes à la livraison, déduite des retraits" />
        <StatCard label="Utilisateurs inscrits" value={String(stats?.total_users ?? 0)} />
      </section>

      <section className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Volume total" value={formatFcfa(volume)} />
        <StatCard label="Frais plateforme" value={formatFcfa(totalFees)} tone="jade" />
        <StatCard label="Revenus des boosts" value={formatFcfa(boostRevenue)} tone="jade" />
        <StatCard label="Abonnements Pro" value={formatFcfa(proRevenue)} tone="jade" hint={`${proActive} vendeur(s) Pro actif(s)`} />
        <StatCard label="Frais de retrait" value={formatFcfa(withdrawalFees)} tone="jade" />
        <StatCard label="Frais de service acheteurs" value={formatFcfa(serviceFees)} tone="jade" hint="payés par les acheteurs : ils couvrent les frais PayPal, cartes et crypto" />
        <StatCard label="Revenus du site (hors commissions)" value={formatFcfa(boostRevenue + proRevenue + withdrawalFees)} tone="volt" hint="boosts + abonnements Pro + frais de retrait" />
      </section>

      <section className="glass p-5">
        <p className="label">Frais de plateforme par taux appliqué</p>
        <ul className="divide-y divide-white/5 text-sm">
          {fees.length === 0 && <li className="py-2 text-zinc-500">Aucune vente pour l&apos;instant.</li>}
          {fees.map((f) => (
            <li key={String(f.platform_fee_percent)} className="flex flex-wrap justify-between gap-2 py-2.5">
              <span className="text-zinc-300">{f.platform_fee_percent ?? 0} % · {Number(f.sales)} vente(s)</span>
              <span className="font-semibold text-jade-soft">{formatFcfa(Number(f.platform_fees))}</span>
            </li>
          ))}
        </ul>
      </section>

      <section className="glass p-5">
        <p className="label">Toutes les transactions</p>
        <ul className="divide-y divide-white/5 text-sm">
          {txs.map((t) => (
            <li key={t.id} className="flex flex-wrap justify-between gap-2 py-2.5">
              <span className="text-zinc-200">
                {t.status === "paid" ? splitLine(t) : `${formatFcfa(t.total_amount)} — ${TRANSACTION_STATUS_LABELS[t.status]}`}
              </span>
              <span className="flex items-center gap-3 text-xs text-zinc-500">
                {new Date(t.created_at).toLocaleString("fr-FR")}
                {t.status === "paid" && t.released_at === null && (
                  <form action={refundTransaction}>
                    <input type="hidden" name="id" value={t.id} />
                    <button className="text-red-300 underline">Rembourser</button>
                  </form>
                )}
              </span>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
