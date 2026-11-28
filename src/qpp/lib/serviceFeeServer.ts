import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { asRows } from "@/lib/db";
import { DEFAULT_FEE_RULES, type FeeRules } from "@/lib/serviceFee";
import { PROVIDERS, isProvider } from "@/lib/payments";

interface RuleRow {
  gateway: string;
  percent: number | string;
  fixed_amount: number | string;
}

/** Lit les frais de service en vigueur. Jamais d'erreur : valeurs de départ en secours (base pas encore mise à jour). */
export async function getServiceFeeRules(): Promise<FeeRules> {
  const rules: FeeRules = { ...DEFAULT_FEE_RULES };
  try {
    const { data, error } = await createAdminClient().from("service_fee_rules").select("gateway, percent, fixed_amount");
    if (error) return rules;
    for (const r of asRows<RuleRow>(data)) {
      if (!isProvider(r.gateway) || !PROVIDERS.includes(r.gateway)) continue;
      const percent = Number(r.percent);
      const fixed = Number(r.fixed_amount);
      if (Number.isFinite(percent) && Number.isFinite(fixed)) rules[r.gateway] = { percent, fixed: Math.round(fixed) };
    }
  } catch {
    /* secours */
  }
  return rules;
}
