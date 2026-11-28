import "server-only";
import { sendEmail, type MailResult } from "@/lib/mailer";
import { inactiveProductEmail, purchaseEmail, sellerNewOrderEmail } from "@/lib/emailTemplates";

// Fonctions d'envoi utilisées par le paiement, la tâche planifiée et le checkout.
// Les modèles sont dans lib/emailTemplates.ts ; l'envoi (avec file de réessai) dans lib/mailer.ts.

/** Email de confirmation envoyé à l'acheteur dès que le paiement est validé. */
export async function sendPurchaseEmail(a: {
  to: string;
  name: string | null;
  productTitle: string;
  portalUrl: string;
  licenseKey: string | null;
  isPhysical: boolean;
  totalFcfa: number;
}): Promise<MailResult> {
  const { to, ...rest } = a;
  return sendEmail({ to, kind: "purchase", ...purchaseEmail(rest) });
}

/** Email envoyé au vendeur quand une commande de produit physique est payée (ou passée en cash). */
export async function sendSellerNewOrderEmail(a: {
  to: string;
  productTitle: string;
  quantity: number;
  deliveryLabel: string;
  buyerName: string | null;
  buyerPhone: string | null;
  address: string | null;
  dashboardUrl: string;
  cash?: boolean;
}): Promise<MailResult> {
  const { to, ...rest } = a;
  return sendEmail({ to, kind: "seller_order", ...sellerNewOrderEmail(rest) });
}

/** Email de relance : un produit n'a ni vente, ni partage, ni visiteurs depuis 3 jours. */
export async function sendInactiveProductEmail(a: { to: string; productTitle: string; productUrl: string }): Promise<MailResult> {
  const { to, ...rest } = a;
  return sendEmail({ to, kind: "inactive_product", retry: false, ...inactiveProductEmail(rest) });
}
