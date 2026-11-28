// Retrait express (option) : supplément réglé par l'admin, voir lib/tarifs.ts.
// Frais de retrait : un pourcentage du montant (avec un minimum), prélevés sur le paiement envoyé (pas sur le solde).
// Le pourcentage et le minimum sont réglés par l'admin (Admin > Commissions) et lus dans la base : voir lib/tarifs.ts.
// Aperçu côté navigateur seulement : le calcul réel est dans la base (fonction request_withdrawal) et reste la référence.

/** Frais pour un retrait demandé de `amount` FCFA, dont `commissionDue` FCFA de commission cash déjà déduits. Compte exempté : 0. */
export function withdrawalFee(amount: number, feePercent: number, feeMin: number, commissionDue = 0, exempt = false, expressPercent = 0): number {
  if (exempt) return 0;
  const base = Math.max(0, amount - Math.max(0, commissionDue));
  // Calcul en centièmes de pour cent, en entiers, comme la base : pas d'erreur d'arrondi sur les décimaux
  const normal = Math.min(base, Math.max(feeMin, Math.ceil((base * Math.round(feePercent * 100)) / 10000)));
  // Retrait express : supplément en plus des frais normaux (jamais plus que le montant restant)
  const express = expressPercent > 0 ? Math.min(base - normal, Math.ceil((base * Math.round(expressPercent * 100)) / 10000)) : 0;
  return normal + express;
}
