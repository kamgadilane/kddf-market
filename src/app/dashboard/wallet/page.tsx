import AutoRefresh from "@/components/AutoRefresh";
import StatCard from "@/components/StatCard";
import WithdrawForm from "@/components/WithdrawForm";
import { getTarifs } from "@/lib/tarifs";
import WalletFraudGuard from "@/components/WalletFraudGuard";
import { getSessionUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { asRow, asRows } from "@/lib/db";
import { formatFcfa } from "@/lib/money";
import { WITHDRAWAL_METHOD_LABELS } from "@/lib/labels";
import type { Wallet, Withdrawal } from "@/lib/types";

export const dynamic = "force-dynamic";
export const metadata = { title: "Mes gains" };

const STATUS: Record<Withdrawal["status"], string> = { pending: "En attente de validation", paid: "Payé", failed: "Refusé (solde rendu)" };

export default async function WalletPage() {
  const user = await getSessionUser();
  if (!user) return null;
  const supabase = createClient();
  await supabase.rpc("release_my_funds");

  const [{ data: w }, { data: wd }, { data: prof }] = await Promise.all([
    supabase.from("wallets").select("user_id, balance_pending, balance_available, total_earned, total_withdrawn, commission_due").eq("user_id", user.id).maybeSingle(),
    supabase.from("withdrawals").select("id, user_id, amount, method, phone_number, status, note, created_at, processed_at, commission_deducted, fee, express").eq("user_id", user.id).order("created_at", { ascending: false }).limit(30),
    supabase.from("profiles").select("commission_exempt").eq("id", user.id).maybeSingle(),
  ]);
  const tarifs = await getTarifs();
  const exempt = asRow<{ commission_exempt: boolean }>(prof)?.commission_exempt ?? false;
  const wallet = asRow<Wallet>(w);
  const withdrawals = asRows<Withdrawal>(wd);

  return (
    <div className="space-y-6">
      <AutoRefresh seconds={30} />
      <h1 className="font-display text-3xl font-bold text-white">Mes gains</h1>
      <section className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Solde en attente" value={formatFcfa(wallet?.balance_pending ?? 0)} tone="volt" hint="digital : disponible 24 h après l'achat · physique : après confirmation de réception par l'acheteur (ou 7 jours après la livraison sans litige), et jamais avant 7 jours après le paiement" />
        <StatCard label="Solde disponible" value={formatFcfa(wallet?.balance_available ?? 0)} tone="jade" />
        <StatCard label="Total gagné" value={formatFcfa(wallet?.total_earned ?? 0)} />
        <StatCard label="Total retiré" value={formatFcfa(wallet?.total_withdrawn ?? 0)} />
      </section>
      {(wallet?.commission_due ?? 0) > 0 && (
        <p role="status" className="rounded-xl bg-amber-500/10 px-4 py-3 text-sm text-amber-200">
          Commission à régler : {formatFcfa(wallet?.commission_due ?? 0)} (commission KDDF sur les ventes encaissées en cash). Elle sera déduite automatiquement de votre prochain retrait.
        </p>
      )}
      <WalletFraudGuard available={wallet?.balance_available ?? 0}><WithdrawForm available={wallet?.balance_available ?? 0} commissionDue={wallet?.commission_due ?? 0} exempt={exempt} feePercent={tarifs.withdrawalFeePercent} feeMin={tarifs.withdrawalFeeMin} expressPercent={tarifs.expressFeePercent} /></WalletFraudGuard>
      <section className="glass p-5">
        <p className="label">Mes demandes de retrait</p>
        {withdrawals.length === 0 ? (
          <p className="text-sm text-zinc-500">Aucune demande.</p>
        ) : (
          <ul className="divide-y divide-white/5 text-sm">
            {withdrawals.map((x) => (
              <li key={x.id} className="flex flex-wrap justify-between gap-2 py-2.5 text-zinc-200">
                <span>{x.express && <span className="mr-1.5 rounded-full bg-amber-500/15 px-2 py-0.5 text-xs font-semibold text-amber-300">⚡ Express</span>}{formatFcfa(x.amount)}{x.commission_deducted > 0 || x.fee > 0 ? ` (${x.commission_deducted > 0 ? `commission cash ${formatFcfa(x.commission_deducted)}` : ""}${x.commission_deducted > 0 && x.fee > 0 ? ", " : ""}${x.fee > 0 ? `frais ${formatFcfa(x.fee)}` : ""} → vous recevez ${formatFcfa(x.amount - x.commission_deducted - x.fee)})` : ""} · {WITHDRAWAL_METHOD_LABELS[x.method]} · {x.phone_number}</span>
                <span className="text-xs text-zinc-400">{STATUS[x.status]} · {new Date(x.created_at).toLocaleDateString("fr-FR")}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
