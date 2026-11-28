import AutoRefresh from "@/components/AutoRefresh";
import { createAdminClient } from "@/lib/supabase/admin";
import { asRow, asRows } from "@/lib/db";
import { formatFcfa } from "@/lib/money";
import { AFTER_LAUNCH_CHOICES, calculateSplit, DEFAULT_AFTER_LAUNCH_PERCENT, effectivePlatformPercent, isLaunchActive, PLATFORM_MAX_PERCENT, type CommissionSettings } from "@/lib/calculateCommission";
import { commissionMessage } from "@/lib/commissionNotify";
import { getTarifs } from "@/lib/tarifs";
import { getFreeProductLimit } from "@/lib/freePlan";
import { getServiceFeeRules } from "@/lib/serviceFeeServer";
import { PROVIDERS, PROVIDER_LABELS } from "@/lib/payments";
import { computeServiceFee } from "@/lib/serviceFee";
import { endLaunchNow, restartLaunch, setAfterLaunchPercent, setCommissionExempt, setRevenueSettings, setServiceFees, setFreeProductLimit } from "./actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Admin · Commissions", robots: { index: false } };

interface Settings extends CommissionSettings {
  updated_at: string;
}
interface History {
  id: string;
  changed_at: string;
  old_percent: number | string | null;
  new_percent: number | string | null;
  changed_by: string | null;
  notified_count: number;
  admin: { full_name: string | null } | null;
}

const DAY = 86400000;
const ERRORS: Record<string, string> = {
  plateforme: `Commission refusée : la plateforme ne peut pas dépasser ${PLATFORM_MAX_PERCENT} % (et doit être un nombre).\nChoisissez une valeur entre 0 et ${PLATFORM_MAX_PERCENT}.`,
  acces: "Accès refusé : seul le compte administrateur peut changer les commissions.\nConnectez-vous avec le compte admin.",
  inconnu: "Aucun compte ne correspond à cet e-mail.\nVérifiez l'adresse : le compte doit déjà être inscrit sur le site.",
  tarifs: "Tarifs refusés. Valeurs acceptées : commission Pro de 0 à 10 %, prix Pro entier de 500 à 200 000 FCFA, frais de retrait de 0 à 10 %, minimum entier de 0 à 5 000 FCFA, supplément express de 0 à 10 %.\nCorrigez puis réessayez.",
  frais: "Frais de service refusés. Valeurs acceptées : pourcentage de 0 à 15 %, montant fixe entier de 0 à 5 000 FCFA.\nCorrigez puis réessayez.",
  limite: "Limite refusée : entrez un nombre entier de 0 à 1 000 (0 = illimité).",
  autre: "Le changement n'a pas pu être enregistré (tables de commissions absentes ?).\nExécutez supabase/schema.sql dans le SQL Editor de Supabase, puis réessayez.",
};

const fmt = (p: number | string | null): string => (p === null ? "-" : `${Number(p).toString().replace(".", ",")} %`);

export default async function AdminCommissions({ searchParams }: { searchParams: { ok?: string; n?: string; err?: string } }) {
  const db = createAdminClient();
  // 3 requêtes de données au total : réglages, historique (avec le nom de l'admin en jointure), vendeurs avec WhatsApp (jointure produits)
  const [{ data: sData }, { data: hData }, { data: wData }, { data: eData }] = await Promise.all([
    db.from("commission_settings").select("platform_fee_percent, after_launch_percent, launch_start_date, launch_end_date, is_launch_mode, updated_at").eq("id", 1).maybeSingle(),
    db.from("commission_history").select("id, changed_at, old_percent, new_percent, changed_by, notified_count, admin:profiles!changed_by(full_name)").order("changed_at", { ascending: false }).limit(50),
    db.from("profiles").select("id, full_name, whatsapp, products!seller_id!inner(id)").not("whatsapp", "is", null).limit(100),
    db.from("profiles").select("id, full_name, store_name").eq("commission_exempt", true).limit(50),
  ]);
  const tarifs = await getTarifs();
  const feeRules = await getServiceFeeRules();
  const freeLimit = await getFreeProductLimit();
  const exempts = asRows<{ id: string; full_name: string | null; store_name: string | null }>(eData);
  const s = asRow<Settings>(sData);
  const history = asRows<History>(hData);

  if (!s) {
    return (
      <div className="space-y-4">
        <h1 className="font-display text-3xl font-bold text-white">Commissions</h1>
        <p className="whitespace-pre-line rounded-xl bg-red-500/10 px-4 py-3 text-sm text-red-200">{ERRORS.autre}</p>
      </div>
    );
  }

  // Noms des admins qui ont modifié (déjà joints à l'historique)
  const names: Record<string, string> = {};
  for (const h of history) if (h.changed_by) names[h.changed_by] = h.admin?.full_name ?? "Admin";

  const pct = effectivePlatformPercent(s);
  const after = Number(s.after_launch_percent);
  const launching = isLaunchActive(s);
  const end = new Date(`${s.launch_end_date}T23:59:59Z`).getTime();
  const daysLeft = Math.ceil((end - Date.now()) / DAY);
  const launchAlert = launching && daysLeft <= 7;

  // Exemples calculés côté serveur avec la même règle que la base
  const examples = [
    { label: "Sans affilié", aff: 0, has: false },
    { label: "Affilié 20 %", aff: 20, has: true },
    { label: "Affilié 50 %", aff: 50, has: true },
  ].map((e) => ({ ...e, r: calculateSplit(10000, e.aff, pct, e.has) }));

  // WhatsApp : liens prêts à envoyer (aucune API WhatsApp automatique n'est utilisée)
  const wa = asRows<{ id: string; full_name: string | null; whatsapp: string | null }>(wData).filter((p) => p.whatsapp);
  const message = commissionMessage(pct);

  const statusText = launching ? "Actuellement : 0 % (Mode Lancement)" : `Actuellement : ${fmt(pct)} (Mode Normal)`;

  return (
    <div className="space-y-6">
      <AutoRefresh seconds={60} />
      <h1 className="font-display text-3xl font-bold text-white">Commissions</h1>

      {searchParams.ok === "commission" && (
        <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">
          Commission enregistrée : elle s&apos;applique à toutes les nouvelles ventes, tout de suite.
          {searchParams.n !== undefined && (Number(searchParams.n) >= 0 ? ` ${searchParams.n} vendeur(s) prévenu(s) par email.` : " Aucun email envoyé : la clé Resend n'est pas configurée (utilisez les liens WhatsApp en bas de page).")}
        </p>
      )}
      {searchParams.ok === "launch" && <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">Nouvelle période de lancement : 0 % pendant 30 jours.</p>}
      {searchParams.ok === "exempt" && <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">Compte exempté : 0 % de commission et aucun frais de retrait, tout de suite.</p>}
      {searchParams.ok === "nonexempt" && <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">Exemption retirée : ce compte repasse au taux normal.</p>}
      {searchParams.ok === "tarifs" && <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">Tarifs enregistrés : ils s&apos;appliquent tout de suite aux nouvelles opérations (les ventes et retraits déjà faits ne changent pas).</p>}
      {searchParams.ok === "frais" && <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">Frais de service enregistrés : ils s&apos;appliquent tout de suite aux nouveaux paiements.</p>}
      {searchParams.ok === "limite" && <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">Limite du plan gratuit enregistrée.</p>}
      {searchParams.err && ERRORS[searchParams.err] && <p role="alert" className="whitespace-pre-line rounded-xl bg-red-500/10 px-4 py-3 text-sm text-red-200">{ERRORS[searchParams.err]}</p>}

      <section className="glass space-y-3 p-5">
        <p className="label !mb-0">Commission de la plateforme</p>
        <p className="font-display text-2xl font-bold text-white">{statusText}</p>
        {launching && <p className="text-sm text-zinc-400">Offre de lancement du {s.launch_start_date} au {s.launch_end_date} ({Math.max(0, daysLeft)} jour(s) restant(s)). Ensuite : {fmt(after)} automatiquement.</p>}
        {launchAlert && (
          <p role="alert" className="rounded-xl bg-amber-500/10 px-4 py-3 text-sm text-amber-200">
            {daysLeft > 0 ? `L'offre de lancement se termine dans ${daysLeft} jour(s).` : "Dernier jour de l'offre de lancement."} Ensuite la commission passe automatiquement à {fmt(after)} (modifiable ci-dessous).
          </p>
        )}
      </section>

      <section className="glass space-y-3 p-5">
        <p className="label !mb-0">Offre de lancement (0 % pendant 30 jours)</p>
        <p className="text-sm text-zinc-400">Les commissions flexibles sont actives par défaut : 0 % pendant le lancement, puis {fmt(after)} automatiquement, sans que tu aies rien à faire.</p>
        <div className="flex flex-wrap gap-3">
          <form action={restartLaunch}><button className={launching ? "btn-ghost" : "btn-primary"}>Relancer 30 jours à 0 %</button></form>
          <form action={endLaunchNow} className="flex gap-3">
            <input type="hidden" name="after" value={String(after > 0 ? after : DEFAULT_AFTER_LAUNCH_PERCENT)} />
            <input type="hidden" name="notify" value="yes" />
            <button className="btn-ghost" disabled={!launching}>Terminer le lancement maintenant ({fmt(after > 0 ? after : DEFAULT_AFTER_LAUNCH_PERCENT)})</button>
          </form>
        </div>
      </section>

      <section className="glass space-y-4 p-5">
        <p className="label !mb-0">Taux appliqué après le lancement (immédiat, sans redéployer)</p>
        <form action={setAfterLaunchPercent} className="space-y-4">
          <div className="flex flex-wrap items-end gap-3">
            {AFTER_LAUNCH_CHOICES.map((v) => (
              <button key={v} name="percent" value={v} className={after === v ? "btn-primary !px-5" : "btn-ghost !px-5"}>{v} %</button>
            ))}
            <div>
              <label className="label" htmlFor="cm-custom">Personnalisé (0 à {PLATFORM_MAX_PERCENT} %)</label>
              <input id="cm-custom" name="custom" inputMode="decimal" placeholder="ex : 2,5" className="input !w-32 !py-2" />
            </div>
            <button name="percent" value="custom" className="btn-ghost">Appliquer</button>
          </div>

          <fieldset className="space-y-2 rounded-xl bg-amber-500/10 p-4 text-sm text-amber-100">
            <legend className="px-1 text-xs font-semibold uppercase tracking-wide text-amber-200">Prévenir les vendeurs ?</legend>
            <p>
              Si tu passes de {fmt(pct)} à un taux plus élevé, les vendeurs existants seront notifiés par Email (et WhatsApp : liens prêts à envoyer ci-dessous).
              Veux-tu envoyer la notification ?
            </p>
            <div className="flex gap-6">
              <label className="flex items-center gap-2"><input type="radio" name="notify" value="yes" defaultChecked className="accent-indigo-500" /> Oui</label>
              <label className="flex items-center gap-2"><input type="radio" name="notify" value="no" className="accent-indigo-500" /> Non</label>
            </div>
          </fieldset>
        </form>
      </section>

      <section className="glass space-y-3 p-5">
        <p className="label !mb-0">Exemples sur 10 000 FCFA avec la commission actuelle ({fmt(pct)})</p>
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="text-xs text-zinc-500"><tr><th className="py-2 pr-4">Cas</th><th className="pr-4">Plateforme</th><th className="pr-4">Affilié</th><th>Vendeur</th></tr></thead>
            <tbody className="text-zinc-200">
              {examples.map((e) => (
                <tr key={e.label} className="border-t border-white/5"><td className="py-2 pr-4">{e.label}</td><td className="pr-4">{formatFcfa(e.r.platformFee)}</td><td className="pr-4">{formatFcfa(e.r.affiliateFee)}</td><td className="font-semibold text-jade-soft">{formatFcfa(e.r.sellerAmount)}</td></tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="text-xs text-zinc-500">Limites imposées : plateforme 10 % maximum, affilié 50 % maximum, le vendeur garde toujours au moins 40 %. Montants arrondis à l&apos;entier inférieur.</p>
      </section>

      <section className="glass space-y-3 p-5">
        <p className="label !mb-0">Historique des changements</p>
        {history.length === 0 ? (
          <p className="text-sm text-zinc-500">Aucun changement pour l&apos;instant.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-xs text-zinc-500"><tr><th className="py-2 pr-4">Date</th><th className="pr-4">Ancien %</th><th className="pr-4">Nouveau %</th><th className="pr-4">Qui</th><th>Prévenus</th></tr></thead>
              <tbody className="text-zinc-200">
                {history.map((h) => (
                  <tr key={h.id} className="border-t border-white/5">
                    <td className="py-2 pr-4 whitespace-nowrap">{new Date(h.changed_at).toLocaleString("fr-FR", { dateStyle: "medium", timeStyle: "short" })}</td>
                    <td className="pr-4">{fmt(h.old_percent)}</td>
                    <td className="pr-4 font-semibold text-white">{fmt(h.new_percent)}</td>
                    <td className="pr-4">{h.changed_by ? names[h.changed_by] ?? "Admin" : "-"}</td>
                    <td>{h.notified_count > 0 ? h.notified_count : "-"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="glass space-y-4 p-5">
        <p className="label !mb-0">Tarifs Pro et frais de retrait (modifiables à tout moment)</p>
        <p className="text-sm text-zinc-400">
          Rappel : Fapshi prend 3 % sur chaque encaissement, payés par la plateforme. Votre marge sur une vente = commission − 3 %.
          Commission normale {fmt(tarifs.afterLaunchPercent)} → marge {fmt(Math.max(0, tarifs.afterLaunchPercent - 3))} ; commission Pro {fmt(tarifs.proPercent)} → marge {fmt(Math.max(0, tarifs.proPercent - 3))}.
          Ne descendez pas sous 3 % : en dessous, chaque vente vous coûte de l&apos;argent.
        </p>
        <form action={setRevenueSettings} className="grid gap-4 sm:grid-cols-2">
          <div>
            <label className="label" htmlFor="tf-pro-pct">Commission des vendeurs Pro (%)</label>
            <input id="tf-pro-pct" name="pro_percent" inputMode="decimal" required defaultValue={String(tarifs.proPercent).replace(".", ",")} className="input" />
          </div>
          <div>
            <label className="label" htmlFor="tf-pro-price">Prix de l&apos;abonnement Pro (FCFA / 30 jours)</label>
            <input id="tf-pro-price" name="pro_price" inputMode="numeric" required defaultValue={tarifs.proPrice} className="input" />
          </div>
          <div>
            <label className="label" htmlFor="tf-fee-pct">Frais de retrait (%)</label>
            <input id="tf-fee-pct" name="fee_percent" inputMode="decimal" required defaultValue={String(tarifs.withdrawalFeePercent).replace(".", ",")} className="input" />
          </div>
          <div>
            <label className="label" htmlFor="tf-fee-min">Frais de retrait minimum (FCFA)</label>
            <input id="tf-fee-min" name="fee_min" inputMode="numeric" required defaultValue={tarifs.withdrawalFeeMin} className="input" />
          </div>
          <div className="sm:col-span-2">
            <label className="label" htmlFor="tf-express">Supplément du retrait express (%) : 0 pour désactiver l&apos;option</label>
            <input id="tf-express" name="express_percent" inputMode="decimal" required defaultValue={String(tarifs.expressFeePercent).replace(".", ",")} className="input sm:!w-1/2" />
          </div>
          <div className="sm:col-span-2"><button className="btn-primary">Enregistrer les tarifs</button></div>
        </form>
        <p className="text-xs text-zinc-500">Le taux de commission normal se règle plus haut (« Taux appliqué après le lancement »). Les tarifs affichés aux vendeurs (page Pro, formulaire de retrait) se mettent à jour tout de suite.</p>
      </section>

      <section className="glass space-y-4 p-5">
        <p className="label !mb-0">Frais de service payés par l&apos;acheteur (selon le moyen de paiement)</p>
        <p className="text-sm text-zinc-400">
          Ces frais sont AJOUTÉS au total que l&apos;acheteur paie et restent à la plateforme : le vendeur n&apos;est pas touché. Ils servent à couvrir les frais des passerelles
          (PayPal ≈ 2,9 à 3,5 % + frais fixes + change, cartes ≈ 1,5 à 3 %, crypto : frais du réseau). Mobile Money Fapshi : 0 car la plateforme absorbe déjà ses 3 %.
          Les acheteurs voient le détail avant de payer.
        </p>
        <form action={setServiceFees} className="space-y-3">
          {PROVIDERS.map((g) => (
            <div key={g} className="grid items-end gap-3 sm:grid-cols-[1fr_8rem_8rem_9rem]">
              <p className="text-sm text-white">{PROVIDER_LABELS[g].title}</p>
              <div>
                <label className="label" htmlFor={`sf-${g}-pct`}>Pourcentage (%)</label>
                <input id={`sf-${g}-pct`} name={`${g}_percent`} inputMode="decimal" required defaultValue={String(feeRules[g].percent).replace(".", ",")} className="input" />
              </div>
              <div>
                <label className="label" htmlFor={`sf-${g}-fix`}>Fixe (FCFA)</label>
                <input id={`sf-${g}-fix`} name={`${g}_fixed`} inputMode="numeric" required defaultValue={feeRules[g].fixed} className="input" />
              </div>
              <p className="pb-3 text-xs text-zinc-500">Sur 10 000 FCFA : {formatFcfa(computeServiceFee(10000, feeRules[g]))}</p>
            </div>
          ))}
          <button className="btn-primary">Enregistrer les frais de service</button>
        </form>
      </section>

      <section className="glass space-y-3 p-5">
        <p className="label !mb-0">Plan gratuit : nombre de produits publiés</p>
        <p className="text-sm text-zinc-400">Un vendeur gratuit peut publier jusqu&apos;à ce nombre de produits (les brouillons ne comptent pas). Les vendeurs Pro, les comptes exemptés et l&apos;admin n&apos;ont pas de limite. Mettez 0 pour supprimer la limite. Les produits déjà publiés ne sont jamais retirés.</p>
        <form action={setFreeProductLimit} className="flex flex-wrap items-end gap-3">
          <div>
            <label className="label" htmlFor="fl-limit">Limite actuelle ({freeLimit === 0 ? "illimité" : `${freeLimit} produits`})</label>
            <input id="fl-limit" name="limit" inputMode="numeric" required defaultValue={freeLimit} className="input !w-40" />
          </div>
          <button className="btn-primary">Enregistrer</button>
        </form>
      </section>

      <section className="glass space-y-3 p-5">
        <p className="label !mb-0">Comptes exemptés (0 % de commission, aucun frais de retrait)</p>
        <p className="text-sm text-zinc-400">Pour votre propre compte vendeur (guides KDDFBusiness) ou un partenaire. Les vendeurs Pro paient {fmt(tarifs.proPercent)} et les autres le taux normal.</p>
        <form action={setCommissionExempt} className="flex flex-wrap gap-2">
          <input type="hidden" name="exempt" value="yes" />
          <input name="email" type="email" required placeholder="E-mail du compte à exempter" aria-label="E-mail du compte à exempter" className="input !w-72 !py-2" />
          <button className="btn-primary !px-4 !py-2">Exempter</button>
        </form>
        {exempts.length === 0 ? (
          <p className="text-sm text-zinc-500">Aucun compte exempté pour le moment.</p>
        ) : (
          <ul className="divide-y divide-white/5 text-sm">
            {exempts.map((x) => (
              <li key={x.id} className="flex flex-wrap items-center justify-between gap-2 py-2.5 text-zinc-200">
                <span>{x.store_name ?? x.full_name ?? "Compte"} <span className="text-xs text-zinc-500">({x.id.slice(0, 8)})</span></span>
                <form action={setCommissionExempt}>
                  <input type="hidden" name="id" value={x.id} />
                  <input type="hidden" name="exempt" value="no" />
                  <button className="btn-ghost !px-3 !py-1.5 text-xs text-red-300">Retirer l&apos;exemption</button>
                </form>
              </li>
            ))}
          </ul>
        )}
      </section>

      <details className="glass p-5">
        <summary className="cursor-pointer text-sm font-semibold text-white">Prévenir les vendeurs par WhatsApp ({wa.length} avec numéro)</summary>
        <p className="mt-3 whitespace-pre-line text-xs text-zinc-400">Message prérempli : « {message} »{"\n"}Cliquez sur un nom : WhatsApp s&apos;ouvre avec le message prêt à envoyer.</p>
        <ul className="mt-3 grid gap-2 sm:grid-cols-2">
          {wa.map((p) => (
            <li key={p.id}>
              <a className="btn-ghost block !py-2 text-center text-sm" target="_blank" rel="noopener noreferrer" href={`https://wa.me/${(p.whatsapp ?? "").replace(/[^0-9]/g, "")}?text=${encodeURIComponent(`Bonjour ${p.full_name ?? ""}, ${message}`)}`}>
                💬 {p.full_name ?? "Vendeur"}
              </a>
            </li>
          ))}
        </ul>
      </details>
    </div>
  );
}
