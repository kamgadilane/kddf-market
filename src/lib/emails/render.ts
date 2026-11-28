// Moteur de modèles d'emails : remplace {{variable}} (échappée en HTML) et {{{variable}}} (HTML déjà sûr, fourni par le code).
// Fonctions PURES, sans accès serveur : faciles à tester. Les modèles sont les fichiers src/lib/emails/*.html.
import { appName, appUrl } from "@/lib/env";
import { EMAIL_TEMPLATES } from "./templates.generated";

export type TemplateName = "confirmation_inscription" | "recu_paiement" | "notification_vendeur" | "notification_affilie" | "litige";

/** Texte de garantie, identique partout sur le site (voir lib/translations.ts : guarantee.full). */
export const GUARANTEE_TEXT =
  "Garantie KDDF Market : Si le produit n'est pas conforme, retour sous 48h, remboursement sous 7 jours. Valable UNIQUEMENT si le paiement est fait sur KDDF Market.";

export function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

/** Renvoie le HTML final. Une variable absente est remplacée par du vide (jamais de « {{x}} » visible dans un email). */
export function renderTemplate(name: TemplateName, vars: Record<string, string>): string {
  const source = EMAIL_TEMPLATES[name];
  if (source === undefined) throw new Error(`Modèle d'email introuvable : ${name}`);
  const all: Record<string, string> = {
    app_name: appName(),
    app_url: appUrl(),
    app_host: appUrl().replace(/^https?:\/\//, ""),
    guarantee: GUARANTEE_TEXT,
    ...vars,
  };
  return source
    .replace(/\{\{\{\s*([a-z_]+)\s*\}\}\}/g, (_m, k: string) => all[k] ?? "")
    .replace(/\{\{\s*([a-z_]+)\s*\}\}/g, (_m, k: string) => escapeHtml(all[k] ?? ""));
}
