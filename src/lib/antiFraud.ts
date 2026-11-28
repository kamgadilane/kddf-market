import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";

/**
 * ANTI-FRAUDE AFFILIATION — point d'entrée serveur.
 *
 * Les règles vivent dans la base (fonction `fraud_assess`, voir supabase/schema.sql, section 25) : ainsi elles
 * s'appliquent à CHAQUE paiement (Fapshi, Flutterwave, crypto, cash) sans qu'aucune route ne puisse les oublier.
 * Cette fonction permet de poser la même question depuis le code serveur (route API, tâche, page admin).
 *
 * Règle d'or : si quoi que ce soit plante, on répond { allowed: true } — mieux vaut laisser passer un fraudeur
 * que bloquer de vrais clients. Montants : entiers FCFA uniquement.
 */

export type CommissionAction = "normal" | "zero" | "hold";

export interface FraudOrderData {
  buyer_id?: string | null;
  buyer_email?: string | null;
  buyer_phone?: string | null;
  seller_id: string;
  affiliate_id?: string | null;
  order_id?: string | null;
  /** Numéro Mobile Money utilisé pour payer, si la passerelle le fournit (Fapshi ne le donne pas aujourd'hui). */
  payer_phone?: string | null;
}

export interface FraudResult {
  /** false = règle 1 ou 2 : la commission affilié est refusée (la vente, elle, continue). */
  allowed: boolean;
  /** 0 à 100 */
  risk_score: number;
  /** Raison interne : à réserver à l'administrateur, JAMAIS à afficher à l'utilisateur. */
  reason: string;
  /** normal = commission payée à l'échéance · zero = commission annulée · hold = en attente de validation admin */
  commission: CommissionAction;
}

const SAFE: FraudResult = { allowed: true, risk_score: 0, reason: "", commission: "normal" };

function isUuid(v: unknown): v is string {
  return typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
}

function clampScore(n: unknown): number {
  const v = Math.round(Number(n));
  return Number.isFinite(v) ? Math.min(100, Math.max(0, v)) : 0;
}

/** Évalue les règles 1 à 4 pour une vente. Ne modifie rien. Ne lève jamais d'exception. */
export async function checkFraud(orderData: FraudOrderData): Promise<FraudResult> {
  try {
    if (!orderData || !isUuid(orderData.seller_id) || !isUuid(orderData.affiliate_id)) return SAFE; // pas d'affilié : rien à contrôler
    const { data, error } = await createAdminClient().rpc("fraud_assess", {
      p_buyer_id: isUuid(orderData.buyer_id) ? orderData.buyer_id : null,
      p_buyer_email: orderData.buyer_email ?? null,
      p_buyer_phone: orderData.buyer_phone ?? null,
      p_seller_id: orderData.seller_id,
      p_affiliate_id: orderData.affiliate_id,
      p_order_id: isUuid(orderData.order_id) ? orderData.order_id : null,
      p_payer_phone: orderData.payer_phone ?? null,
    });
    if (error || !data || typeof data !== "object") return SAFE;
    const r = data as { allowed?: unknown; risk_score?: unknown; reason?: unknown; commission?: unknown };
    const commission: CommissionAction = r.commission === "zero" || r.commission === "hold" ? r.commission : "normal";
    return {
      allowed: r.allowed !== false,
      risk_score: clampScore(r.risk_score),
      reason: typeof r.reason === "string" ? r.reason : "",
      commission,
    };
  } catch {
    return SAFE;
  }
}

/** Message affiché à un utilisateur dont la commission est annulée : volontairement vague (on n'explique jamais la règle). */
export const FRAUD_CANCELLED_MESSAGE = "Votre commission a été annulée pour activité suspecte. Contactez le support.";
/** Message affiché pendant la vérification. */
export const FRAUD_REVIEW_MESSAGE = "Commission en cours de vérification - 7 jours";

export { clientIpFrom } from "@/lib/clientIp";
