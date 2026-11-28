import "server-only";
import { sendEmail } from "@/lib/mailer";
import { supportAlertEmail } from "@/lib/emailTemplates";

export const SUPPORT_CATEGORIES: Record<string, string> = {
  paiement: "Paiement",
  commande: "Commande / livraison",
  compte: "Compte / connexion",
  bug: "Bug / erreur sur le site",
  autre: "Autre",
};

/** Prévient le propriétaire d'un nouveau message de support. Sans SUPPORT_EMAIL ou sans clé Resend : rien n'est envoyé (jamais bloquant). */
export async function notifySupport(m: { name: string; email: string; category: string; message: string; pageUrl: string | null; imageCount: number }): Promise<void> {
  const to = process.env.SUPPORT_EMAIL;
  if (!to) return;
  await sendEmail({
    to,
    kind: "support",
    replyTo: m.email,
    ...supportAlertEmail({
      name: m.name,
      email: m.email,
      categoryLabel: SUPPORT_CATEGORIES[m.category] ?? "Autre",
      message: m.message,
      pageUrl: m.pageUrl,
      imageCount: m.imageCount,
    }),
  });
}
