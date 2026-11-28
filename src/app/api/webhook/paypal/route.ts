// Webhook PayPal : POST /api/webhook/paypal  (alias : /api/webhooks/paypal)
// Dashboard développeur PayPal > votre application > Webhooks : URL = cette adresse, événements :
//   CHECKOUT.ORDER.APPROVED et PAYMENT.CAPTURE.COMPLETED. Copiez l'« ID du webhook » dans PAYPAL_WEBHOOK_ID.
// La signature est vérifiée chez PayPal, puis le paiement est RELU chez PayPal : le corps du message n'est jamais cru sur parole.
// Répond toujours 200 (PayPal ne rejoue pas en boucle).
import { NextResponse } from "next/server";
import { verifyPaypalWebhook } from "@/lib/paypal";
import { isPaypalOrderId, orderIdFromEvent } from "@/lib/paypalCore";
import { syncFapshiTransaction } from "@/lib/fulfillment";
import { REF_PREFIX } from "@/lib/payments";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const OK = (): NextResponse => NextResponse.json({ received: true }, { status: 200 });
const MAX_BODY_BYTES = 128 * 1024;

export async function POST(req: Request): Promise<NextResponse> {
  try {
    const declared = Number(req.headers.get("content-length") ?? "0");
    if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) return OK();
    const event: unknown = await req.json().catch(() => null);
    if (event === null) return OK();
    if (!(await verifyPaypalWebhook(req.headers, event))) {
      console.warn("[paypal-webhook] signature invalide ou PAYPAL_WEBHOOK_ID absent : requête ignorée");
      return OK();
    }
    const orderId = orderIdFromEvent(event);
    if (!isPaypalOrderId(orderId)) return OK();
    const result = await syncFapshiTransaction(`${REF_PREFIX.paypal}${orderId}`, { source: "webhook", minAgeSeconds: 2 });
    console.log("[paypal-webhook]", orderId, "| résultat :", result);
  } catch (e) {
    console.error("[paypal-webhook] erreur interne :", e instanceof Error ? e.message : e);
  }
  return OK();
}
