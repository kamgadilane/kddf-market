// Abonnement « Pro » des créateurs : 30 jours payés d'avance (pas de renouvellement automatique : le Mobile Money ne le permet pas).
// Le PRIX et le TAUX de commission Pro sont réglables dans Admin > Commissions (table commission_settings) : voir lib/tarifs.ts.
// Le prix est toujours lu côté serveur, jamais depuis le navigateur.

export const PRO_PLAN = {
  days: 30,
  boostDiscountPercent: 20, // -20 % sur les boosts
  label: "Abonnement Pro",
} as const;

/** Avantages affichés sur la page Pro (le taux vient de la base). */
export function proPerks(proPercent: number, normalPercent: number, freeProductLimit = 0): readonly string[] {
  const fmt = (p: number): string => `${String(p).replace(".", ",")} %`;
  return [
    `Commission réduite à ${fmt(proPercent)} au lieu de ${fmt(normalPercent)}, sur toutes vos ventes`,
    "Badge « Pro » visible sur votre boutique et vos produits",
    `${PRO_PLAN.boostDiscountPercent} % de réduction sur tous les boosts`,
    ...(freeProductLimit > 0 ? [`Publication de produits sans limite (le plan gratuit est limité à ${freeProductLimit} produits publiés)`] : []),
  ];
}

/** Prix d'un boost pour un vendeur : -20 % s'il est Pro (arrondi à l'entier inférieur). */
export function boostPriceFor(price: number, isPro: boolean): number {
  return isPro ? Math.floor((price * (100 - PRO_PLAN.boostDiscountPercent)) / 100) : price;
}
