import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { asRow } from "@/lib/db";
import { effectivePlatformPercent, type CommissionSettings } from "@/lib/calculateCommission";

// Tarifs de la plateforme : TOUS réglables à tout moment dans Admin > Commissions (aucun redéploiement).
// Ces valeurs par défaut ne servent que si la base n'est pas encore à jour (SQL « mise-a-jour-finale.sql » pas encore exécuté).
// Le calcul réel des ventes et des retraits est fait dans la base ; ici on ne fait que LIRE pour l'affichage.
export interface Tarifs {
  normalPercent: number; // commission normale appliquée aujourd'hui (0 pendant le lancement)
  afterLaunchPercent: number; // commission normale après le lancement
  proPercent: number; // commission des vendeurs Pro
  proPrice: number; // prix de l'abonnement Pro (FCFA / 30 jours)
  withdrawalFeePercent: number;
  withdrawalFeeMin: number;
  expressFeePercent: number; // supplément du retrait express
}

export const DEFAULT_TARIFS: Tarifs = {
  normalPercent: 8,
  afterLaunchPercent: 8,
  proPercent: 5,
  proPrice: 3000,
  withdrawalFeePercent: 1.5,
  withdrawalFeeMin: 200,
  expressFeePercent: 2,
};

interface Row extends CommissionSettings {
  pro_percent?: number | string | null;
  pro_price?: number | string | null;
  withdrawal_fee_percent?: number | string | null;
  withdrawal_fee_min?: number | string | null;
  express_fee_percent?: number | string | null;
}

const num = (v: unknown, fallback: number): number => {
  const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN;
  return Number.isFinite(n) ? n : fallback;
};

/** Lit les tarifs en vigueur (service_role : les colonnes de tarifs ne sont pas lisibles par le navigateur). Jamais d'erreur : valeurs par défaut en secours. */
export async function getTarifs(): Promise<Tarifs> {
  try {
    const { data, error } = await createAdminClient()
      .from("commission_settings")
      .select("platform_fee_percent, after_launch_percent, launch_start_date, launch_end_date, is_launch_mode, pro_percent, pro_price, withdrawal_fee_percent, withdrawal_fee_min, express_fee_percent")
      .eq("id", 1)
      .maybeSingle();
    const r = asRow<Row>(data);
    if (error || !r) return DEFAULT_TARIFS;
    return {
      normalPercent: effectivePlatformPercent(r),
      afterLaunchPercent: num(r.after_launch_percent, DEFAULT_TARIFS.afterLaunchPercent),
      proPercent: num(r.pro_percent, DEFAULT_TARIFS.proPercent),
      proPrice: Math.round(num(r.pro_price, DEFAULT_TARIFS.proPrice)),
      withdrawalFeePercent: num(r.withdrawal_fee_percent, DEFAULT_TARIFS.withdrawalFeePercent),
      withdrawalFeeMin: Math.round(num(r.withdrawal_fee_min, DEFAULT_TARIFS.withdrawalFeeMin)),
      expressFeePercent: num(r.express_fee_percent, DEFAULT_TARIFS.expressFeePercent),
    };
  } catch {
    return DEFAULT_TARIFS;
  }
}

/** 1.5 -> « 1,5 % » */
export function percentText(p: number): string {
  return `${String(p).replace(".", ",")} %`;
}
