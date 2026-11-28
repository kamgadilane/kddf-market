// Devises et conversion (calcul pur, utilisable côté serveur ET navigateur : aucune clé, aucun accès réseau ici).
// Le FCFA (XAF) est arrimé à l'euro par un taux FIXE officiel : 1 EUR = 655,957 FCFA. Les autres devises passent par l'euro.
// Les montants en FCFA restent des ENTIERS ; les montants en devise étrangère sont comptés en « centimes » entiers (minor units).

export const XAF_PER_EUR = 655.957;

export type FxCurrency = "XAF" | "EUR" | "USD" | "GBP" | "CAD";

export interface FxCurrencyInfo {
  code: FxCurrency;
  label: string;
  symbol: string;
  /** Décimales affichées (FCFA : 0 ; autres : 2). */
  decimals: 0 | 2;
  /** Accepté par PayPal (le FCFA ne l'est pas : PayPal exige une devise étrangère). */
  paypal: boolean;
}

export const FX_CURRENCIES: readonly FxCurrencyInfo[] = [
  { code: "XAF", label: "Franc CFA", symbol: "FCFA", decimals: 0, paypal: false },
  { code: "EUR", label: "Euro", symbol: "€", decimals: 2, paypal: true },
  { code: "USD", label: "Dollar américain", symbol: "$", decimals: 2, paypal: true },
  { code: "GBP", label: "Livre sterling", symbol: "£", decimals: 2, paypal: true },
  { code: "CAD", label: "Dollar canadien", symbol: "CA$", decimals: 2, paypal: true },
];

export const PAYPAL_CURRENCIES: readonly FxCurrency[] = FX_CURRENCIES.filter((c) => c.paypal).map((c) => c.code);

/** Devise utilisée par PayPal quand l'acheteur n'en choisit pas une acceptée par PayPal. */
export const DEFAULT_PAYPAL_CURRENCY: FxCurrency = "USD";

/**
 * Bornes de bon sens (valeur d'une devise en euros... exprimée en « unités de devise pour 1 EUR »).
 * Un taux hors de ces bornes est rejeté : il vient d'une panne ou d'une donnée empoisonnée, jamais d'un vrai marché.
 */
export const SANE_PER_EUR: Record<Exclude<FxCurrency, "XAF" | "EUR">, readonly [number, number]> = {
  USD: [0.6, 2.0],
  GBP: [0.5, 1.5],
  CAD: [0.9, 2.5],
};

export function isFxCurrency(v: unknown): v is FxCurrency {
  return typeof v === "string" && FX_CURRENCIES.some((c) => c.code === v);
}

export function currencyInfo(code: FxCurrency): FxCurrencyInfo {
  return FX_CURRENCIES.find((c) => c.code === code) ?? FX_CURRENCIES[0];
}

export interface FxRates {
  /** Unités de chaque devise pour 1 EUR (XAF = 655,957 et EUR = 1, toujours). */
  perEur: Record<FxCurrency, number>;
  /** Date/heure de la dernière mise à jour du taux chez la source (ISO). */
  asOf: string;
  source: string;
  /** Vrai si les taux viennent de la dernière copie en base (la source en ligne ne répond pas). */
  cached: boolean;
}

/** Valeur de 1 FCFA dans la devise demandée. */
export function ratePerFcfa(currency: FxCurrency, rates: FxRates): number {
  if (currency === "XAF") return 1;
  return rates.perEur[currency] / XAF_PER_EUR;
}

export interface FxQuote {
  currency: FxCurrency;
  /** Montant à payer en « centimes » entiers (FCFA : le montant lui-même). Arrondi vers le HAUT : le vendeur n'est jamais lésé. */
  minor: number;
  /** Valeur de 1 FCFA dans cette devise, marge comprise. */
  rate: number;
  marginPercent: number;
}

/** Convertit un montant ENTIER en FCFA vers une devise, avec une marge facultative (0 à 10 %). */
export function quoteFromFcfa(fcfa: number, currency: FxCurrency, rates: FxRates, marginPercent = 0): FxQuote {
  if (!Number.isInteger(fcfa) || fcfa < 0) throw new Error("Montant FCFA invalide");
  const margin = Number.isFinite(marginPercent) ? Math.min(10, Math.max(0, marginPercent)) : 0;
  if (currency === "XAF") return { currency, minor: fcfa, rate: 1, marginPercent: 0 };
  const rate = ratePerFcfa(currency, rates) * (1 + margin / 100);
  const minor = Math.ceil(fcfa * rate * 100 - 1e-6);
  return { currency, minor: Math.max(minor, 1), rate, marginPercent: margin };
}

/** « 1234 » (centimes) -> « 12.34 » (format attendu par PayPal). FCFA : entier. */
export function minorToDecimal(minor: number, currency: FxCurrency): string {
  if (currencyInfo(currency).decimals === 0) return String(minor);
  const sign = minor < 0 ? "-" : "";
  const abs = Math.abs(minor);
  return `${sign}${Math.floor(abs / 100)}.${String(abs % 100).padStart(2, "0")}`;
}

/** « 12.34 » -> 1234 centimes ; null si ce n'est pas un montant valide à 2 décimales au plus. */
export function decimalToMinor(value: string, currency: FxCurrency): number | null {
  const dec = currencyInfo(currency).decimals;
  const re = dec === 0 ? /^\d{1,12}$/ : /^\d{1,10}(\.\d{1,2})?$/;
  if (!re.test(value)) return null;
  if (dec === 0) return Number(value);
  const [whole, frac = ""] = value.split(".");
  return Number(whole) * 100 + Number(frac.padEnd(2, "0"));
}

/** Affichage lisible : « 15,23 $ », « 12,50 € », « 10 000 FCFA ». */
export function formatMoney(minor: number, currency: FxCurrency): string {
  const info = currencyInfo(currency);
  if (info.decimals === 0) return `${new Intl.NumberFormat("fr-FR").format(minor)} ${info.symbol}`;
  const n = new Intl.NumberFormat("fr-FR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(minor / 100);
  return `${n} ${info.symbol}`;
}

/** Texte du taux : « 1 USD = 604 FCFA » (arrondi pour la lecture seulement). */
export function describeRate(currency: FxCurrency, rates: FxRates, marginPercent = 0): string {
  if (currency === "XAF") return "Paiement en FCFA : pas de conversion";
  const fcfaPerUnit = 1 / (ratePerFcfa(currency, rates) * (1 + Math.min(10, Math.max(0, marginPercent)) / 100));
  const symbol = currencyInfo(currency).code;
  return `1 ${symbol} = ${new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 1 }).format(fcfaPerUnit)} FCFA`;
}

/** Valide un objet de taux reçu d'une source : tous les taux nécessaires, finis et dans les bornes de bon sens. */
export function sanitizePerEur(raw: Record<string, unknown>): Record<FxCurrency, number> | null {
  const out: Record<FxCurrency, number> = { XAF: XAF_PER_EUR, EUR: 1, USD: 0, GBP: 0, CAD: 0 };
  for (const code of ["USD", "GBP", "CAD"] as const) {
    const v = raw[code];
    const n = typeof v === "number" ? v : typeof v === "string" ? Number(v) : NaN;
    const [lo, hi] = SANE_PER_EUR[code];
    if (!Number.isFinite(n) || n < lo || n > hi) return null;
    out[code] = n;
  }
  return out;
}
