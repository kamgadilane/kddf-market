import type { PaymentProvider } from "@/lib/payments";

// Frais de service PAYÉS PAR L'ACHETEUR selon le moyen de paiement (ils couvrent les frais de la passerelle).
// Réglables à tout moment dans Admin > Commissions. Le calcul réel est fait par la base (apply_service_fee) :
// cette copie sert uniquement à AFFICHER le montant avant le paiement. Elle doit rester identique à la fonction SQL.
export interface FeeRule {
  percent: number; // 0 à 15
  fixed: number; // FCFA, 0 à 5000
}

export type FeeRules = Record<PaymentProvider, FeeRule>;

/** Valeurs de départ (estimations d'après les frais des passerelles) : utilisées seulement si la base n'est pas encore à jour. */
export const DEFAULT_FEE_RULES: FeeRules = {
  fapshi: { percent: 0, fixed: 0 },
  flutterwave: { percent: 3, fixed: 0 },
  crypto: { percent: 1, fixed: 0 },
  paypal: { percent: 5, fixed: 300 },
};

/** Frais de service d'une commande (entiers FCFA, arrondi au FCFA supérieur comme la base). */
export function computeServiceFee(base: number, rule: FeeRule | undefined): number {
  if (!rule || (rule.percent <= 0 && rule.fixed <= 0)) return 0;
  // Calcul en centièmes pour éviter les erreurs de virgule flottante (5 % de 10 000 = 500 exactement)
  const hundredths = Math.round(rule.percent * 100);
  return Math.ceil((base * hundredths) / 10000) + Math.round(rule.fixed);
}

/** « 5 % + 300 FCFA », « 3 % », « aucun frais » */
export function feeRuleText(rule: FeeRule | undefined): string {
  if (!rule || (rule.percent <= 0 && rule.fixed <= 0)) return "aucun frais";
  const parts: string[] = [];
  if (rule.percent > 0) parts.push(`${String(rule.percent).replace(".", ",")} %`);
  if (rule.fixed > 0) parts.push(`${rule.fixed} FCFA`);
  return parts.join(" + ");
}
