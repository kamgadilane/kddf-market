// Calcul des commissions (système FLEXIBLE, ACTIVÉ PAR DÉFAUT, géré par l'admin dans /admin/commissions).
// Règle : 0 % pendant les 30 jours de lancement, puis 8 % par défaut (au choix de l'admin, jusqu'à 10 %). L'ancien calcul 5/8/10 % n'existe plus.
// Tous les montants sont des ENTIERS en FCFA : jamais de float pour l'argent, toujours arrondi à l'entier INFÉRIEUR.
// Ce fichier ne s'exécute que côté serveur (aperçus de l'admin, validations des actions). Le calcul RÉEL des ventes
// est fait dans la base (fonction compute_split_for) : il applique exactement les mêmes règles.

export const PLATFORM_MAX_PERCENT = 10; // la plateforme ne dépasse jamais 10 %
export const AFFILIATE_MIN_PERCENT = 1;
export const AFFILIATE_MAX_PERCENT = 50; // l'affilié ne gagne jamais plus de 50 %
export const SELLER_MIN_PERCENT = 40; // le vendeur garde toujours au moins 40 %
export const DEFAULT_AFFILIATE_PERCENT_NEW = 20;
export const LAUNCH_DAYS = 30; // durée de l'offre de lancement à 0 %
export const DEFAULT_AFTER_LAUNCH_PERCENT = 8; // taux appliqué automatiquement après le lancement
export const AFTER_LAUNCH_CHOICES = [5, 8, 10] as const; // boutons rapides de /admin/commissions

/** Réglages lus dans la table commission_settings (une seule ligne). */
export interface CommissionSettings {
  platform_fee_percent: number | string;
  after_launch_percent: number | string;
  launch_start_date: string;
  launch_end_date: string;
  is_launch_mode: boolean;
}

/** Date du jour au format AAAA-MM-JJ (UTC, comme current_date côté base). */
export function todayIso(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10);
}

/** Le lancement à 0 % est-il en cours ? (identique à la fonction SQL effective_platform_percent) */
export function isLaunchActive(s: CommissionSettings, today: string = todayIso()): boolean {
  return s.is_launch_mode && today <= s.launch_end_date;
}

/** Commission de la plateforme appliquée AUJOURD'HUI (0 pendant le lancement, puis le taux « après lancement »). Aperçu : le calcul réel est dans la base. */
export function effectivePlatformPercent(s: CommissionSettings, today: string = todayIso()): number {
  const clamp = (v: number): number => Math.min(PLATFORM_MAX_PERCENT, Math.max(0, Number.isFinite(v) ? v : 0));
  if (isLaunchActive(s, today)) return 0;
  return clamp(Number(s.is_launch_mode ? s.after_launch_percent : s.platform_fee_percent));
}

export type CommissionErrorCode = "montant_invalide" | "plateforme_max" | "affilie_max" | "affilie_min" | "vendeur_minimum";

export class CommissionError extends Error {
  readonly code: CommissionErrorCode;
  constructor(code: CommissionErrorCode, message: string) {
    super(message);
    this.name = "CommissionError";
    this.code = code;
  }
}

export interface CommissionSplit {
  platformFee: number;
  affiliateFee: number;
  sellerAmount: number;
}

/** Pourcentage -> centièmes de pour cent entiers (3 -> 300 ; 2,5 -> 250), pour ne jamais multiplier par un nombre à virgule. */
function toBasisPoints(percent: number): number {
  return Math.round(percent * 100);
}

/** Vérifie la commission d'affilié choisie par un vendeur (entier de 1 à 50). Au-delà de 50 : refus, jamais d'arrondi silencieux. */
export function validateAffiliatePercent(value: number): { ok: true; value: number } | { ok: false; code: "affilie_max" | "affilie_min"; message: string } {
  if (!Number.isInteger(value) || value < AFFILIATE_MIN_PERCENT) {
    return { ok: false, code: "affilie_min", message: `La commission d'affilié doit être un nombre entier d'au moins ${AFFILIATE_MIN_PERCENT} %.` };
  }
  if (value > AFFILIATE_MAX_PERCENT) {
    return { ok: false, code: "affilie_max", message: `La commission d'affilié ne peut pas dépasser ${AFFILIATE_MAX_PERCENT} % (elle a été limitée à ${AFFILIATE_MAX_PERCENT} %).` };
  }
  return { ok: true, value };
}

/**
 * Répartition d'une vente.
 *   platform_fee  = total x plateforme %
 *   affiliate_fee = total x affilié %   (0 s'il n'y a pas d'affilié)
 *   seller_amount = total - platform_fee - affiliate_fee
 * Lève CommissionError si une règle de sécurité est violée (plateforme > 10 %, affilié > 50 %, vendeur < 40 %).
 */
export function calculateSplit(totalAmount: number, affiliatePercent: number, platformFeePercent: number, hasAffiliate: boolean = affiliatePercent > 0): CommissionSplit {
  if (!Number.isSafeInteger(totalAmount) || totalAmount < 0) throw new CommissionError("montant_invalide", "Le montant doit être un entier positif en FCFA.");
  if (!Number.isFinite(platformFeePercent) || platformFeePercent < 0 || platformFeePercent > PLATFORM_MAX_PERCENT) {
    throw new CommissionError("plateforme_max", `La commission de la plateforme doit être comprise entre 0 % et ${PLATFORM_MAX_PERCENT} %.`);
  }
  if (hasAffiliate) {
    const v = validateAffiliatePercent(affiliatePercent);
    if (!v.ok) throw new CommissionError(v.code, v.message);
  }

  const platformFee = Math.floor((totalAmount * toBasisPoints(platformFeePercent)) / 10000);
  const affiliateFee = hasAffiliate ? Math.floor((totalAmount * toBasisPoints(affiliatePercent)) / 10000) : 0;
  const sellerAmount = totalAmount - platformFee - affiliateFee;

  // Filet de sécurité : le vendeur garde au moins 40 % (impossible avec les plafonds 10 % + 50 %, mais vérifié quand même)
  if (sellerAmount * 100 < totalAmount * SELLER_MIN_PERCENT) {
    throw new CommissionError("vendeur_minimum", `Le vendeur doit toujours gagner au minimum ${SELLER_MIN_PERCENT} % : vente bloquée.`);
  }
  return { platformFee, affiliateFee, sellerAmount };
}
