import { createClient } from "@/lib/supabase/server";
import { FRAUD_CANCELLED_MESSAGE } from "@/lib/antiFraud";

interface Notice {
  held: number;
  cancelled: boolean;
  review: boolean;
  days_left: number | null;
  hold_days: number;
}

/**
 * Entoure le formulaire de retrait.
 * - Utilisateur honnête : le formulaire s'affiche comme avant (rien de différent).
 * - Fonds encore dans le délai de protection et rien de retirable : bouton grisé « Disponible dans X jours ».
 * - Compte en cours de vérification : bouton grisé + message générique (jamais la règle).
 * Tout est calculé côté serveur.
 */
export default async function WalletFraudGuard({ available, children }: { available: number; children: React.ReactNode }) {
  let n: Notice | null = null;
  try {
    const supabase = createClient();
    const { data } = await supabase.rpc("my_fraud_notice");
    n = (data as Notice | null) ?? null;
  } catch {
    n = null; // en cas de souci : l'affichage normal, jamais un blocage
  }
  if (!n) return <>{children}</>;

  const waiting = n.days_left !== null && available < 1000;
  return (
    <>
      {n.cancelled && (
        <p role="status" className="rounded-xl bg-red-500/10 px-4 py-3 text-sm text-red-200">{FRAUD_CANCELLED_MESSAGE}</p>
      )}
      {n.held > 0 && (
        <p role="status" className="rounded-xl bg-amber-500/10 px-4 py-3 text-sm text-amber-200">
          Commission en cours de vérification - {n.hold_days} jours. Activité suspecte : ces gains ne sont pas encore retirables.
        </p>
      )}
      {n.review ? (
        <div className="glass p-5">
          <button type="button" disabled aria-disabled="true" className="btn-ghost w-full cursor-not-allowed opacity-50">Demander un retrait</button>
          <p className="mt-2 text-xs text-zinc-400">Compte en cours de vérification. Contactez le support.</p>
        </div>
      ) : waiting ? (
        <div className="glass p-5">
          <button type="button" disabled aria-disabled="true" className="btn-ghost w-full cursor-not-allowed opacity-50">Demander un retrait</button>
          <p className="mt-2 text-xs text-zinc-400">Disponible dans {n.days_left} jour{(n.days_left ?? 0) > 1 ? "s" : ""}</p>
        </div>
      ) : (
        children
      )}
    </>
  );
}
