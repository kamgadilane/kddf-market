import { LIFECYCLE_STEPS, lifecycleIndex } from "@/lib/labels";
import type { OrderStatus } from "@/lib/types";

/** Frise « En attente → Payé → Livré → Terminé » (le statut ne peut jamais sauter une étape : trigger SQL orders_status_guard). */
export default function OrderLifecycle({ status, paymentStatus }: { status: OrderStatus; paymentStatus: string }) {
  if (status === "cancelled") return <p className="text-xs text-red-300">Commande annulée</p>;
  const current = lifecycleIndex(status, paymentStatus);
  return (
    <ol className="flex items-center gap-1 text-[11px]" aria-label="Avancement de la commande">
      {LIFECYCLE_STEPS.map((label, i) => (
        <li key={label} className="flex items-center gap-1">
          <span className={`rounded-full px-2 py-0.5 font-medium ${i < current ? "bg-jade/20 text-jade-soft" : i === current ? "bg-volt/20 text-volt-soft" : "bg-white/5 text-zinc-500"}`} aria-current={i === current ? "step" : undefined}>
            {i < current ? "✓ " : ""}{label}
          </span>
          {i < LIFECYCLE_STEPS.length - 1 && <span className="text-zinc-600" aria-hidden="true">→</span>}
        </li>
      ))}
    </ol>
  );
}
