import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { asRow } from "@/lib/db";
import { sendEmail } from "@/lib/mailer";
import { affiliateCommissionEmail, sellerSaleEmail } from "@/lib/emailTemplates";

/**
 * Notifications après chaque vente payée (module 12) :
 *  - vendeur  : « Nouvelle vente ! [Produit] - [Prix] »
 *  - affilié  : « Tu as gagné [Montant] FCFA de commission »
 * Canal : email (Resend, avec réessai automatique). Un message WhatsApp AUTOMATIQUE demande l'API WhatsApp Business
 * (compte Meta payant) : non branchée. Une erreur ici ne bloque JAMAIS la vente ni la livraison.
 */

interface TxRow {
  seller_id: string;
  affiliate_id: string | null;
  affiliate_fee: number | null;
  seller_amount: number | null;
  total_amount: number;
  service_fee: number | null;
  product_id: string;
}

export async function notifyAfterSale(orderId: string): Promise<void> {
  try {
    const db = createAdminClient();
    const tx = asRow<TxRow>((await db.from("transactions").select("seller_id, affiliate_id, affiliate_fee, seller_amount, total_amount, service_fee, product_id").eq("order_id", orderId).maybeSingle()).data);
    if (!tx) return;
    const product = asRow<{ title: string }>((await db.from("products").select("title").eq("id", tx.product_id).maybeSingle()).data);
    const title = product?.title ?? "Produit";

    const seller = await db.auth.admin.getUserById(tx.seller_id);
    if (seller.data.user?.email) {
      await sendEmail({
        to: seller.data.user.email,
        kind: "seller_sale",
        ...sellerSaleEmail({ productTitle: title, totalFcfa: tx.total_amount - (tx.service_fee ?? 0), sellerShareFcfa: tx.seller_amount ?? 0 }),
      });
    }

    const fee = tx.affiliate_fee ?? 0;
    if (tx.affiliate_id && fee > 0) {
      const aff = await db.auth.admin.getUserById(tx.affiliate_id);
      if (aff.data.user?.email) {
        await sendEmail({
          to: aff.data.user.email,
          kind: "affiliate_commission",
          ...affiliateCommissionEmail({ productTitle: title, feeFcfa: fee }),
        });
      }
    }
  } catch (e) {
    console.error("[notif] ignoré :", e instanceof Error ? e.message : e);
  }
}
