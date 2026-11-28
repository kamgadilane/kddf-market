import { createClient } from "@/lib/supabase/server";
import { asRow } from "@/lib/db";
import { effectivePlatformPercent, isLaunchActive, type CommissionSettings } from "@/lib/calculateCommission";

const DAY = 86400000;

/** Bloc « Commission actuelle KDDF » du tableau de bord vendeur : 0 % pendant le lancement, puis le taux choisi par l'admin. */
export default async function CommissionBanner() {
  const { data } = await createClient()
    .from("commission_settings")
    .select("platform_fee_percent, after_launch_percent, launch_start_date, launch_end_date, is_launch_mode")
    .eq("id", 1)
    .maybeSingle();
  const s = asRow<CommissionSettings>(data);
  if (!s) return null; // tables pas encore installées : on n'affiche rien plutôt qu'une erreur

  const pct = effectivePlatformPercent(s);
  const label = Number.isInteger(pct) ? String(pct) : pct.toFixed(2).replace(".", ",");
  const after = Number(s.after_launch_percent);
  const afterLabel = Number.isInteger(after) ? String(after) : after.toFixed(2).replace(".", ",");
  const end = new Date(`${s.launch_end_date}T23:59:59Z`).getTime();
  const start = new Date(`${s.launch_start_date}T00:00:00Z`).getTime();
  const totalDays = Math.max(1, Math.round((end - start) / DAY));
  const daysLeft = Math.max(0, Math.ceil((end - Date.now()) / DAY));

  if (isLaunchActive(s)) {
    const ratio = Math.min(100, Math.round((daysLeft / totalDays) * 100));
    return (
      <section className="glass space-y-3 p-4 text-sm">
        <p className="text-zinc-200">
          <span className="font-semibold text-white">Commission actuelle KDDF : 0 %</span>{" "}
          {daysLeft > 0 ? `(Offre de lancement - il te reste ${daysLeft} jour${daysLeft > 1 ? "s" : ""} à 0 %)` : "(Offre de lancement - dernier jour à 0 %)"}
        </p>
        <div>
          <div className="mb-1 flex justify-between text-xs text-zinc-400"><span>Jours restants à 0 %</span><span>{daysLeft} / {totalDays}</span></div>
          <div className="h-2 overflow-hidden rounded-full bg-white/10" role="progressbar" aria-valuemin={0} aria-valuemax={totalDays} aria-valuenow={daysLeft}>
            <div className="h-full rounded-full bg-jade transition-all" style={{ width: `${ratio}%` }} />
          </div>
        </div>
        <p className="text-xs text-zinc-500">Ensuite : {afterLabel} % automatiquement. Les affiliés reçoivent le pourcentage que tu choisis pour chaque produit (de 1 % à 50 %).</p>
      </section>
    );
  }

  return (
    <section className="glass p-4 text-sm text-zinc-300">
      <p><span className="font-semibold text-white">Commission actuelle KDDF : {label} %</span> sur chaque vente. Les affiliés reçoivent le pourcentage que tu choisis pour chaque produit (de 1 % à 50 %).</p>
    </section>
  );
}
