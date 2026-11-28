import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { asRow } from "@/lib/db";
import { sendEmail } from "@/lib/mailer";
import { disputeEmail } from "@/lib/emailTemplates";

/**
 * Emails de litige (modèle litige.html) : ouverture (vendeur + acheteur) et décision de l'admin (vendeur + acheteur).
 * Ne bloque JAMAIS l'action en cours : toute erreur est seulement écrite dans les logs.
 */
interface OrderRow {
  id: string;
  buyer_id: string | null;
  buyer_email: string | null;
  seller_id: string;
  product_id: string;
  dispute_reason: string | null;
}

async function emailOf(userId: string | null): Promise<{ email: string | null; name: string | null }> {
  if (!userId) return { email: null, name: null };
  const { data } = await createAdminClient().auth.admin.getUserById(userId);
  const meta = data.user?.user_metadata as { full_name?: unknown } | undefined;
  return { email: data.user?.email ?? null, name: typeof meta?.full_name === "string" ? meta.full_name : null };
}

async function loadOrder(orderId: string): Promise<{ o: OrderRow; title: string } | null> {
  const db = createAdminClient();
  const o = asRow<OrderRow>((await db.from("orders").select("id, buyer_id, buyer_email, seller_id, product_id, dispute_reason").eq("id", orderId).maybeSingle()).data);
  if (!o) return null;
  const p = asRow<{ title: string }>((await db.from("products").select("title").eq("id", o.product_id).maybeSingle()).data);
  return { o, title: p?.title ?? "Produit" };
}

/** L'acheteur vient d'ouvrir un litige : le vendeur et l'acheteur reçoivent un email. */
export async function notifyDisputeOpened(orderId: string): Promise<void> {
  try {
    const loaded = await loadOrder(orderId);
    if (!loaded) return;
    const { o, title } = loaded;
    const seller = await emailOf(o.seller_id);
    const buyer = await emailOf(o.buyer_id);
    const buyerTo = buyer.email ?? o.buyer_email;
    if (seller.email) {
      await sendEmail({
        to: seller.email,
        kind: "dispute_seller",
        ...disputeEmail({
          recipientName: seller.name,
          headline: "Un litige a été ouvert sur votre vente",
          productTitle: title,
          orderId,
          message: `Motif de l'acheteur : ${o.dispute_reason ?? "non précisé"}\n\nLes fonds de cette vente restent bloqués jusqu'à la décision de l'équipe. Envoyez la photo du colis avant envoi.`,
        }),
      });
    }
    if (buyerTo) {
      await sendEmail({
        to: buyerTo,
        kind: "dispute_buyer",
        ...disputeEmail({
          recipientName: buyer.name,
          headline: "Votre litige est bien enregistré",
          productTitle: title,
          orderId,
          message: "Nous avons prévenu le vendeur. Ajoutez une photo du produit reçu pour accélérer la décision.",
        }),
      });
    }
  } catch (e) {
    console.error("[litige] email d'ouverture ignoré :", e instanceof Error ? e.message : e);
  }
}

/** L'admin a tranché : refund = acheteur remboursé ; reject = litige refusé, le vendeur est payé. */
export async function notifyDisputeDecision(disputeId: string, decision: "refund" | "reject"): Promise<void> {
  try {
    const db = createAdminClient();
    const d = asRow<{ order_id: string }>((await db.from("disputes").select("order_id").eq("id", disputeId).maybeSingle()).data);
    if (!d) return;
    const loaded = await loadOrder(d.order_id);
    if (!loaded) return;
    const { o, title } = loaded;
    const refunded = decision === "refund";
    const seller = await emailOf(o.seller_id);
    const buyer = await emailOf(o.buyer_id);
    const buyerTo = buyer.email ?? o.buyer_email;
    if (buyerTo) {
      await sendEmail({
        to: buyerTo,
        kind: "dispute_decision_buyer",
        ...disputeEmail({
          recipientName: buyer.name,
          headline: refunded ? "Litige accepté : vous êtes remboursé" : "Litige refusé",
          productTitle: title,
          orderId: d.order_id,
          message: refunded ? "Après examen, le remboursement est accordé (sous 7 jours)." : "Après examen, le produit a été jugé conforme : la vente est maintenue.",
        }),
      });
    }
    if (seller.email) {
      await sendEmail({
        to: seller.email,
        kind: "dispute_decision_seller",
        ...disputeEmail({
          recipientName: seller.name,
          headline: refunded ? "Litige tranché : vente remboursée" : "Litige refusé : vous êtes payé",
          productTitle: title,
          orderId: d.order_id,
          message: refunded ? "Cette vente a été remboursée à l'acheteur ; les montants en attente correspondants sont retirés." : "Le litige est rejeté : les fonds suivent leur calendrier normal de libération.",
        }),
      });
    }
  } catch (e) {
    console.error("[litige] email de décision ignoré :", e instanceof Error ? e.message : e);
  }
}
