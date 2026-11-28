// Moyens de paiement en ligne du site. Fapshi est toujours disponible (comportement historique) ;
// Flutterwave (cartes + Mobile Money élargi) et la crypto ne s'affichent QUE si leurs clés sont présentes sur Vercel.
import type { CountryCode } from "@/lib/currency";

export type PaymentProvider = "fapshi" | "flutterwave" | "crypto" | "paypal";

export const PROVIDERS: readonly PaymentProvider[] = ["fapshi", "flutterwave", "crypto", "paypal"];

export const PROVIDER_LABELS: Record<PaymentProvider, { title: string; detail: string }> = {
  fapshi: { title: "Mobile Money Cameroun", detail: "MTN MoMo ou Orange Money (via Fapshi)" },
  flutterwave: { title: "Carte bancaire & Mobile Money Afrique", detail: "Visa, Mastercard, Wave, Moov, M-Pesa, Orange, MTN… (via Flutterwave)" },
  crypto: { title: "Cryptomonnaie", detail: "USDT, Bitcoin, Ethereum… (via NOWPayments)" },
  paypal: { title: "PayPal", detail: "Compte PayPal ou carte, en euros, dollars, livres ou dollars canadiens (taux du jour)" },
};

export function isProvider(v: unknown): v is PaymentProvider {
  return typeof v === "string" && (PROVIDERS as readonly string[]).includes(v);
}

export function enabledProviders(): PaymentProvider[] {
  const list: PaymentProvider[] = ["fapshi"];
  if (process.env.FLW_SECRET_KEY) list.push("flutterwave");
  if (process.env.NOWPAYMENTS_API_KEY && process.env.NOWPAYMENTS_IPN_SECRET) list.push("crypto");
  if (process.env.PAYPAL_CLIENT_ID && process.env.PAYPAL_CLIENT_SECRET) list.push("paypal");
  return list;
}

/** Préfixes stockés dans transactions.fapshi_trans_id (la colonne garde son nom historique). */
export const REF_PREFIX = { flutterwave: "flw:", crypto: "np:", paypal: "pp:" } as const;

/* ---------------------------------------------------------------------
 * Moyens de paiement PAR PAYS (module international). Seul le Cameroun est actif aujourd'hui.
 * Les autres pays ouvriront quand leur passerelle sera branchée : on ajoutera alors leurs moyens ici.
 * ------------------------------------------------------------------- */
export interface PaymentMethod {
  id: string;
  label: string;
  provider: PaymentProvider;
}

export const PAYMENT_METHODS: Record<CountryCode, readonly PaymentMethod[]> = {
  CM: [
    { id: "mtn_momo", label: "MTN Mobile Money", provider: "fapshi" },
    { id: "orange_money", label: "Orange Money", provider: "fapshi" },
    { id: "card", label: "Carte bancaire", provider: "flutterwave" },
    { id: "crypto", label: "Crypto (USDT, BTC)", provider: "crypto" },
    { id: "paypal", label: "PayPal", provider: "paypal" },
  ],
  GA: [],
  CG: [],
  TD: [],
  CI: [],
  SN: [],
  BJ: [],
  TG: [],
  BF: [],
  ML: [],
  NE: [],
  CF: [],
};
