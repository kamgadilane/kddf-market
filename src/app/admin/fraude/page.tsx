import FlashError from "@/components/FlashError";
import AutoRefresh from "@/components/AutoRefresh";
import StatCard from "@/components/StatCard";
import { createClient } from "@/lib/supabase/server";
import { asRow, asRows } from "@/lib/db";
import { formatFcfa } from "@/lib/money";
import { resolveFraud, setFraudActive, unblockUser } from "./actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Admin · Anti-fraude", robots: { index: false } };

interface Overview {
  active: boolean;
  hold_days: number;
  blocked_today: number;
  pending: number;
  saved_total: number;
  under_review: number;
}
interface Alert {
  id: string;
  created_at: string;
  affiliate_id: string | null;
  affiliate_name: string;
  seller_name: string;
  reason: string;
  risk_score: number;
  amount: number;
  action: "blocked" | "flagged" | "allowed";
  status: "open" | "validated" | "blocked" | "closed";
  affiliate_review: boolean;
}

const STATUS_LABEL: Record<Alert["status"], string> = {
  open: "À valider",
  validated: "Validée",
  blocked: "Bloquée par l'admin",
  closed: "Bloquée automatiquement",
};

function scoreTone(score: number): string {
  return score >= 70 ? "bg-red-500/15 text-red-300" : score >= 40 ? "bg-amber-500/15 text-amber-200" : "bg-white/5 text-zinc-300";
}

export default async function AdminFraud({ searchParams }: { searchParams: { erreur?: string } }) {
  const supabase = createClient();
  const [{ data: o }, { data: a }] = await Promise.all([supabase.rpc("admin_fraud_overview"), supabase.rpc("admin_fraud_alerts", { p_limit: 150 })]);
  const ov = asRow<Overview>(o);
  const alerts = asRows<Alert>(a);
  const reviewed = alerts.filter((x) => x.affiliate_review && x.affiliate_id);
  const seen = new Set<string>();
  const toUnblock = reviewed.filter((x) => (x.affiliate_id && !seen.has(x.affiliate_id) ? (seen.add(x.affiliate_id), true) : false));

  return (
    <div className="space-y-6">
      <FlashError code={searchParams.erreur} />
      <AutoRefresh seconds={30} />
      <h1 className="font-display text-3xl font-bold text-white">Anti-fraude</h1>

      <section className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <StatCard label="Ventes bloquées aujourd'hui" value={String(ov?.blocked_today ?? 0)} tone="volt" />
        <StatCard label="Ventes en attente de validation" value={String(ov?.pending ?? 0)} tone="jade" />
        <StatCard label="Argent économisé grâce à l'anti-fraude" value={formatFcfa(Number(ov?.saved_total ?? 0))} hint="commissions annulées" />
      </section>

      <section className="glass flex flex-wrap items-center justify-between gap-3 p-4 text-sm">
        <p className="text-zinc-300">
          Protection : <strong className={ov?.active ? "text-jade-soft" : "text-amber-300"}>{ov?.active ? "ACTIVE" : "DÉSACTIVÉE"}</strong>
          {" · "}délai de sécurité {ov?.hold_days ?? 7} jours · comptes en vérification : {ov?.under_review ?? 0}
        </p>
        <form action={setFraudActive} className="flex gap-2">
          <input type="hidden" name="active" value={ov?.active ? "off" : "on"} />
          <button className="btn-ghost !px-3 !py-2">{ov?.active ? "Désactiver" : "Activer"}</button>
        </form>
      </section>

      {toUnblock.length > 0 && (
        <section className="glass p-5">
          <p className="label">Comptes « en cours de vérification » (retraits suspendus)</p>
          <ul className="divide-y divide-white/5 text-sm">
            {toUnblock.map((x) => (
              <li key={x.affiliate_id} className="flex flex-wrap items-center justify-between gap-2 py-2.5 text-zinc-200">
                <span>{x.affiliate_name}</span>
                <form action={unblockUser}>
                  <input type="hidden" name="id" value={x.affiliate_id ?? ""} />
                  <button className="btn-jade !px-3 !py-2">Débloquer les retraits</button>
                </form>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section className="glass p-5">
        <p className="label">Alertes ({alerts.length})</p>
        {alerts.length === 0 ? (
          <p className="text-sm text-zinc-500">Aucune alerte. Tout est calme.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[820px] text-left text-sm">
              <thead className="text-xs uppercase text-zinc-500">
                <tr>
                  <th className="py-2 pr-3">Date</th>
                  <th className="pr-3">Affilié</th>
                  <th className="pr-3">Vendeur</th>
                  <th className="pr-3">Raison</th>
                  <th className="pr-3">Score</th>
                  <th className="pr-3">Montant</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/5 align-top text-zinc-200">
                {alerts.map((x) => (
                  <tr key={x.id}>
                    <td className="whitespace-nowrap py-3 pr-3 text-xs text-zinc-400">{new Date(x.created_at).toLocaleString("fr-FR")}</td>
                    <td className="pr-3">{x.affiliate_name}</td>
                    <td className="pr-3">{x.seller_name}</td>
                    <td className="max-w-xs pr-3 text-zinc-300">{x.reason}</td>
                    <td className="pr-3"><span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${scoreTone(x.risk_score)}`}>{x.risk_score}/100</span></td>
                    <td className="whitespace-nowrap pr-3">{formatFcfa(Number(x.amount))}</td>
                    <td>
                      {x.status === "open" ? (
                        <div className="flex flex-wrap gap-1.5">
                          {(["validate", "block", "ban"] as const).map((d) => (
                            <form key={d} action={resolveFraud}>
                              <input type="hidden" name="id" value={x.id} />
                              <input type="hidden" name="decision" value={d} />
                              <button className={d === "validate" ? "btn-jade !px-2.5 !py-1.5 text-xs" : "btn-ghost !px-2.5 !py-1.5 text-xs text-red-300"}>
                                {d === "validate" ? "Valider la vente" : d === "block" ? "Bloquer la vente" : "Bannir l'utilisateur"}
                              </button>
                            </form>
                          ))}
                        </div>
                      ) : (
                        <span className="text-xs text-zinc-500">{STATUS_LABEL[x.status]}</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
