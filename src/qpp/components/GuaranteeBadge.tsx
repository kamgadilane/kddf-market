import { t } from "@/lib/translations";

// Garantie KDDF Market : affichée sur la page produit, la page commande et la page grossistes.
export default function GuaranteeBadge() {
  return (
    <p className="rounded-xl border border-jade/30 bg-jade/10 px-4 py-3 text-xs text-jade-soft">
      🛡️ {t("guarantee.full")}
    </p>
  );
}
