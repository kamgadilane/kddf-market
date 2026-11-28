// Tous les montants sont des ENTIERS en FCFA : jamais de nombre à virgule pour l'argent.

export const MIN_PRICE_FCFA = 100; // minimum accepté par Fapshi

/** 10000 -> "10 000 FCFA" */
export function formatFcfa(amount: number): string {
  const n = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 }).format(Math.trunc(amount));
  return `${n.replace(/[  ]/g, " ")} FCFA`;
}

// Le calcul de la répartition (plateforme / affilié / vendeur) est dans lib/calculateCommission.ts (calculateSplit) et, pour les ventes réelles, dans la base (compute_split_for).
