// Informations de l'éditeur du site (pages légales + pied de page).
// Chaque valeur se règle dans Vercel > Settings > Environment Variables (puis « Redeploy ») : aucun code à modifier.
// Les valeurs ci-dessous ne servent que de secours si la variable n'existe pas encore.

export const LEGAL_UPDATED = "27 novembre 2026";

export interface LegalInfo {
  status: string;
  name: string;
  address: string;
  email: string;
  phone: string;
  director: string;
  host: string;
}

const pick = (value: string | undefined, fallback: string): string => (value && value.trim() !== "" ? value.trim() : fallback);

export function legalInfo(): LegalInfo {
  return {
    status: pick(process.env.NEXT_PUBLIC_SITE_OWNER_STATUS, "Particulier"),
    name: pick(process.env.NEXT_PUBLIC_SITE_OWNER_NAME, "KAMGA DJOMGANG DILANE FAREL"),
    address: pick(process.env.NEXT_PUBLIC_SITE_OWNER_ADDRESS, "Makepe Bm, Douala, Cameroun"),
    email: pick(process.env.NEXT_PUBLIC_SITE_OWNER_EMAIL, "kamgadjomgangd@gmail.com"),
    phone: pick(process.env.NEXT_PUBLIC_SITE_OWNER_PHONE, "+237689644382"),
    director: pick(process.env.NEXT_PUBLIC_SITE_PUBLICATION_DIRECTOR, "KAMGA DJOMGANG DILANE FAREL"),
    host: pick(process.env.NEXT_PUBLIC_SITE_HOST, "Vercel Inc., 440 N Barranca Ave #4133, Covina, CA 91723, États-Unis"),
  };
}

/** Liens des pages légales (pied de page, plan du site). */
export const LEGAL_LINKS: ReadonlyArray<{ href: string; label: string }> = [
  { href: "/conditions", label: "Conditions d'utilisation et de vente" },
  { href: "/confidentialite", label: "Confidentialité" },
  { href: "/remboursement", label: "Remboursement et litiges" },
  { href: "/mentions-legales", label: "Mentions légales" },
];
