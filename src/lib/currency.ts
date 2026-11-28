/** Pays gérés par KDDF Market. Seul le Cameroun est ouvert ; les autres sont en liste d'attente. */
export type CountryCode = "CM" | "GA" | "CG" | "TD" | "CI" | "SN" | "BJ" | "TG" | "BF" | "ML" | "NE" | "CF";

export interface Country {
  code: CountryCode;
  name: string;
  flag: string;
  currency: "XAF" | "XOF";
  /** Libellé affiché après le montant */
  symbol: string;
  active: boolean;
}

export const COUNTRIES: readonly Country[] = [
  { code: "CM", name: "Cameroun", flag: "🇨🇲", currency: "XAF", symbol: "FCFA", active: true },
  { code: "GA", name: "Gabon", flag: "🇬🇦", currency: "XAF", symbol: "FCFA", active: false },
  { code: "CG", name: "Congo", flag: "🇨🇬", currency: "XAF", symbol: "FCFA", active: false },
  { code: "TD", name: "Tchad", flag: "🇹🇩", currency: "XAF", symbol: "FCFA", active: false },
  { code: "CI", name: "Côte d'Ivoire", flag: "🇨🇮", currency: "XOF", symbol: "FCFA", active: false },
  { code: "SN", name: "Sénégal", flag: "🇸🇳", currency: "XOF", symbol: "FCFA", active: false },
  { code: "BJ", name: "Bénin", flag: "🇧🇯", currency: "XOF", symbol: "FCFA", active: false },
  { code: "TG", name: "Togo", flag: "🇹🇬", currency: "XOF", symbol: "FCFA", active: false },
  { code: "BF", name: "Burkina Faso", flag: "🇧🇫", currency: "XOF", symbol: "FCFA", active: false },
  { code: "ML", name: "Mali", flag: "🇲🇱", currency: "XOF", symbol: "FCFA", active: false },
  { code: "NE", name: "Niger", flag: "🇳🇪", currency: "XOF", symbol: "FCFA", active: false },
  { code: "CF", name: "Centrafrique", flag: "🇨🇫", currency: "XAF", symbol: "FCFA", active: false },
];

export const DEFAULT_COUNTRY: CountryCode = "CM";

export function getCountry(code: string | null | undefined): Country {
  return COUNTRIES.find((c) => c.code === code) ?? COUNTRIES[0];
}

/** Montant entier en FCFA (XAF et XOF ont la même valeur). Jamais de décimales. Ex : 15000 -> "15 000 FCFA". */
export function formatPrice(amount: number, countryCode: string = DEFAULT_COUNTRY): string {
  const n = Number.isFinite(amount) ? Math.trunc(amount) : 0;
  const digits = String(Math.abs(n)).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return `${n < 0 ? "-" : ""}${digits} ${getCountry(countryCode).symbol}`;
}

/** Villes proposées dans les filtres. */
export const MAIN_CITIES: readonly string[] = ["Douala", "Yaoundé", "Bafoussam", "Garoua"];
