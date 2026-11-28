import ProButton from "@/components/ProButton";
import ProBadge from "@/components/ProBadge";
import { getSessionUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { syncProPayment } from "@/lib/fulfillment";
import { asRow, asRows } from "@/lib/db";
import { formatFcfa } from "@/lib/money";
import { proPerks, PRO_PLAN } from "@/lib/pro";
import { getTarifs } from "@/lib/tarifs";
import { getFreeProductLimit } from "@/lib/freePlan";
import { isUuid } from "@/lib/validate";

export const dynamic = "force-dynamic";
export const metadata = { title: "Abonnement Pro" };

interface Sub { id: string; status: string; amount: number; starts_at: string | null; ends_at: string | null; created_at: string }

const STATUS: Record<string, string> = { pending: "En attente de paiement", paid: "Payé", failed: "Échec", expired: "Expiré", review: "À vérifier par KDDF" };
const day = (d: string): string => new Date(d).toLocaleDateString("fr-FR");

export default async function ProPage({ searchParams }: { searchParams: { abo?: string } }) {
  const user = await getSessionUser();
  if (!user) return null;

  // Retour du paiement Fapshi : on vérifie tout de suite (sans attendre le webhook)
  let message = "";
  if (isUuid(searchParams.abo)) {
    const admin = createAdminClient();
    const { data: r } = await admin.from("pro_subscriptions").select("fapshi_trans_id, status, user_id").eq("id", searchParams.abo).maybeSingle();
    const row = asRow<{ fapshi_trans_id: string | null; status: string; user_id: string }>(r);
    if (row && row.user_id === user.id && row.fapshi_trans_id) {
      if (row.status === "pending") await syncProPayment(row.fapshi_trans_id, { source: "verification", minAgeSeconds: 10 });
      const { data: after } = await admin.from("pro_subscriptions").select("status").eq("id", searchParams.abo).maybeSingle();
      const status = asRow<{ status: string }>(after)?.status;
      message =
        status === "paid" ? "✅ Abonnement Pro activé ! Votre commission réduite s'applique dès maintenant."
        : status === "pending" ? "Paiement en cours de confirmation… rafraîchissez la page dans un instant."
        : status === "review" ? "Paiement reçu mais le montant doit être vérifié par KDDF. Contactez le support si l'abonnement n'apparaît pas."
        : "Le paiement n'a pas abouti. Vous n'avez pas été débité.";
    }
  }

  const tarifs = await getTarifs();
  const perks = proPerks(tarifs.proPercent, tarifs.afterLaunchPercent, await getFreeProductLimit());
  const supabase = createClient();
  const { data: act } = await supabase.from("active_pro").select("ends_at").eq("user_id", user.id).order("ends_at", { ascending: false }).limit(1).maybeSingle();
  const activeUntil = asRow<{ ends_at: string }>(act)?.ends_at ?? null;
  const { data: hist } = await supabase.from("pro_subscriptions").select("id, status, amount, starts_at, ends_at, created_at").eq("user_id", user.id).order("created_at", { ascending: false }).limit(10);
  const history = asRows<Sub>(hist);

  return (
    <div className="space-y-6">
      <h1 className="flex flex-wrap items-center gap-3 font-display text-3xl font-bold text-white">Abonnement Pro {activeUntil && <ProBadge />}</h1>
      {message && <p role="status" className="rounded-xl bg-white/5 px-4 py-3 text-sm text-zinc-200">{message}</p>}

      <section className="glass space-y-4 p-5">
        <p className="font-display text-2xl font-bold text-white">{formatFcfa(tarifs.proPrice)} <span className="text-base font-normal text-zinc-400">pour {PRO_PLAN.days} jours</span></p>
        <ul className="space-y-2 text-sm text-zinc-200">
          {perks.map((perk) => <li key={perk} className="flex gap-2"><span aria-hidden="true" className="text-jade-soft">✓</span><span>{perk}</span></li>)}
        </ul>
        {activeUntil ? (
          <p className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">Votre abonnement Pro est actif jusqu&apos;au {day(activeUntil)}. Vous pouvez le prolonger : les 30 jours s&apos;ajoutent à la fin de la période en cours.</p>
        ) : (
          <p className="text-sm text-zinc-400">Vous n&apos;êtes pas encore Pro : la commission normale s&apos;applique à vos ventes.</p>
        )}
        <ProButton label={activeUntil ? `Prolonger de ${PRO_PLAN.days} jours · ${formatFcfa(tarifs.proPrice)}` : `Devenir Pro · ${formatFcfa(tarifs.proPrice)}`} />
        <p className="text-xs text-zinc-500">Paiement Mobile Money (MTN / Orange) via Fapshi. Pas de renouvellement automatique : à la fin des 30 jours, vous revenez simplement au tarif normal. La commission réduite ne s&apos;applique qu&apos;aux ventes payées pendant que l&apos;abonnement est actif ; elle ne change jamais les ventes passées.</p>
      </section>

      <section className="glass p-5">
        <p className="label">Mes paiements</p>
        {history.length === 0 ? (
          <p className="text-sm text-zinc-500">Aucun abonnement pour le moment.</p>
        ) : (
          <ul className="divide-y divide-white/5 text-sm">
            {history.map((h) => (
              <li key={h.id} className="flex flex-wrap justify-between gap-2 py-2.5 text-zinc-200">
                <span>{formatFcfa(h.amount)} · {STATUS[h.status] ?? h.status}</span>
                <span className="text-xs text-zinc-400">{h.starts_at && h.ends_at ? `du ${day(h.starts_at)} au ${day(h.ends_at)}` : day(h.created_at)}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
