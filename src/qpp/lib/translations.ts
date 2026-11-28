/** Textes de l'interface. Français aujourd'hui ; ajouter `en` plus tard sans toucher aux pages. */
export type Lang = "fr" | "en";
export const DEFAULT_LANG: Lang = "fr";

const fr = {
  "nav.wholesale": "Grossistes",
  "nav.cart": "Panier",
  "country.soon": "Bientôt disponible",
  "country.popupTitle": "KDDF Market arrive bientôt en {country} !",
  "country.popupText": "Laisse ton WhatsApp pour être parmi les 100 premiers vendeurs.",
  "country.send": "Rejoindre la liste",
  "country.thanks": "Merci ! Tu es n°{n} sur la liste.",
  "guarantee.full": "Garantie KDDF Market : Si le produit n'est pas conforme, retour sous 48h, remboursement sous 7 jours. Valable UNIQUEMENT si le paiement est fait sur KDDF Market.",
  "wholesale.title": "Grossistes",
  "wholesale.quote": "Demander un devis grossiste",
  "wholesale.verified": "Grossiste Vérifié",
  "cart.title": "Mon panier",
  "cart.empty": "Ton panier est vide.",
} as const;

export type TranslationKey = keyof typeof fr;

// Structure prête pour l'anglais : copier les clés de `fr` et traduire les valeurs.
const dictionaries: Record<Lang, Partial<Record<TranslationKey, string>>> = { fr, en: {} };

export function t(key: TranslationKey, vars?: Record<string, string | number>, lang: Lang = DEFAULT_LANG): string {
  const raw = dictionaries[lang][key] ?? fr[key];
  return vars ? raw.replace(/\{(\w+)\}/g, (_, k: string) => String(vars[k] ?? "")) : raw;
}
