import { MAX_ORDER_QUANTITY } from "@/lib/order";
import { explain, explainPaymentError } from "@/lib/errors";
import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { initiatePay } from "@/lib/fapshi";
import { appUrl } from "@/lib/env";
import { initiateFlutterwave } from "@/lib/flutterwave";
import { createCryptoInvoice } from "@/lib/nowpayments";
import { createPaypalOrder } from "@/lib/paypal";
import { FxUnavailableError, fxMarginPercent, getFxRates } from "@/lib/fx";
import { DEFAULT_PAYPAL_CURRENCY, PAYPAL_CURRENCIES, isFxCurrency, minorToDecimal, quoteFromFcfa, type FxCurrency } from "@/lib/fxCore";
import { enabledProviders, isProvider, REF_PREFIX, type PaymentProvider } from "@/lib/payments";
import { asRow } from "@/lib/db";
import { dbErrorMessage } from "@/lib/labels";
import { cleanText, isEmail, isReferralCode, isUuid } from "@/lib/validate";
import { GUEST_DIGITAL_MESSAGE, technicalEmail } from "@/lib/guest";
import { clientIpFrom } from "@/lib/clientIp";
import { sendSellerNewOrderEmail } from "@/lib/email";
import { rateLimit, rateLimitIp, tooManyRequests } from "@/lib/rateLimit";
import { DELIVERY_LABELS } from "@/lib/labels";
import type { DeliveryMethod, PaymentMethod } from "@/lib/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const DELIVERY_METHODS: readonly string[] = ["pickup_douala", "delivery_douala", "shipping_cameroon"];

interface CheckoutInput {
  provider: PaymentProvider;
  productId: string;
  email: string;
  name: string;
  quantity: number;
  deliveryMethod: DeliveryMethod | null;
  address: string;
  phone: string;
  city: string;
  district: string;
  paymentMethod: PaymentMethod;
  /** Devise de paiement choisie (PayPal seulement ; les autres moyens encaissent en FCFA). */
  currency: FxCurrency;
  /** V4.0 : commande de GROS (prix par palier, paiement en ligne obligatoire, compte obligatoire) : tout est contrôlé par la base. */
  wholesale: boolean;
}

interface CreatedOrder {
  order_id: string;
  transaction_id: string;
  download_token: string;
  total: number;
  title: string;
  product_type: string;
  order_code?: string | null;
  blocked?: boolean;
}

function parseInput(raw: unknown): CheckoutInput | null {
  if (raw === null || typeof raw !== "object") return null;
  const b = raw as Record<string, unknown>;
  if (!isUuid(b.productId)) return null;
  // Email : OBLIGATOIRE seulement pour un produit digital (compte). Pour un produit physique il est facultatif.
  const email = cleanText(b.email, 254).toLowerCase();
  if (email !== "" && !isEmail(email)) return null;
  const quantity = typeof b.quantity === "number" ? b.quantity : 1;
  if (!Number.isInteger(quantity) || quantity < 1 || quantity > MAX_ORDER_QUANTITY) return null;
  const deliveryMethod =
    typeof b.deliveryMethod === "string" && DELIVERY_METHODS.includes(b.deliveryMethod)
      ? (b.deliveryMethod as DeliveryMethod)
      : null;
  return {
    productId: b.productId,
    email,
    name: cleanText(b.name, 100),
    quantity,
    deliveryMethod,
    address: cleanText(b.address, 300),
    phone: cleanText(b.phone, 20),
    city: cleanText(b.city, 80),
    district: cleanText(b.district, 80),
    paymentMethod: b.paymentMethod === "cod" ? "cod" : "online",
    provider: isProvider(b.provider) ? b.provider : "fapshi",
    currency: isFxCurrency(b.currency) && PAYPAL_CURRENCIES.includes(b.currency) ? b.currency : DEFAULT_PAYPAL_CURRENCY,
    wholesale: b.wholesale === true,
  };
}

/**
 * POST /api/checkout
 * 0) V3.1 : un produit PHYSIQUE s'achète SANS compte (nom + téléphone + ville + quartier) ; un produit DIGITAL exige un compte
 * 1) la base crée la commande + la transaction (prix, stock et livraison relus côté serveur, jamais depuis le navigateur)
 * 2) Fapshi crée le lien de paiement
 * 3) on renvoie ce lien : l'acheteur y paie en Mobile Money, puis revient sur /download/[token]
 */
export async function POST(req: Request): Promise<NextResponse> {
  // Anti-abus : 15 tentatives par IP et par 10 minutes (une commande en attente réserve du stock)
  if (!(await rateLimitIp(req, "checkout", 15, 600))) return tooManyRequests("Trop de tentatives de commande. Patientez quelques minutes puis réessayez.");
  const input = parseInput(await req.json().catch(() => null));
  if (!input) return NextResponse.json({ error: explain("Une information du formulaire est manquante ou mal remplie (nom, téléphone, ville, quartier, email ou quantité).", "Relisez chaque champ, corrigez-le et validez à nouveau.") }, { status: 400 });

  // Limite par email (compte) ou par numéro de téléphone (achat sans compte)
  const who = input.email || `tel:${input.phone.replace(/\D/g, "").slice(-9)}`;
  if (!(await rateLimit(`checkout-mail:${who}`, 10, 600))) return tooManyRequests("Trop de tentatives avec ces coordonnées. Patientez quelques minutes puis réessayez.");

  const { data: auth } = await createClient().auth.getUser();
  const user = auth.user;

  // Code d'affilié mémorisé 30 jours par le middleware (cookie aff_ref)
  const refCookie = cookies().get("aff_ref")?.value;
  const refCode = isReferralCode(refCookie) ? refCookie : null;

  const db = createAdminClient();
  // Gros : la base calcule le prix de gros d'après la quantité (jamais envoyé par le navigateur) et refuse le cash et les invités
  const { data, error } = await db.rpc(input.wholesale ? "create_wholesale_order" : "create_checkout_order", {
    p_product_id: input.productId,
    p_buyer_id: user?.id ?? null,
    p_email: input.email,
    p_name: input.name || null,
    p_quantity: input.quantity,
    p_delivery_method: input.deliveryMethod,
    p_address: input.address || null,
    p_phone: input.phone || null,
    p_ref_code: refCode,
    p_payment_method: input.paymentMethod,
    p_city: input.city || null,
    p_district: input.district || null,
    p_ip: clientIpFrom(req.headers),
  });
  if (error) {
    // Produit digital sans compte : on demande de créer un compte (la vente ne se fait pas)
    if (error.message.includes("compte_requis_digital")) return NextResponse.json({ error: GUEST_DIGITAL_MESSAGE, needAccount: true }, { status: 401 });
    if (error.message.includes("compte_requis_gros")) return NextResponse.json({ error: dbErrorMessage(error.message), needAccount: true }, { status: 401 });
    return NextResponse.json({ error: dbErrorMessage(error.message) }, { status: 400 });
  }

  const order = asRow<CreatedOrder>(data);
  // Anti-fraude téléphone : plus de 5 commandes en 1 h avec le même numéro => bloqué (déjà tracé dans fraud_logs par la base)
  if (order?.blocked === true) return NextResponse.json({ error: dbErrorMessage("trop_de_commandes_numero") }, { status: 429 });
  if (!order) return NextResponse.json({ error: explain("La commande n'a pas pu être enregistrée par le serveur.", "Réessayez dans un instant. Aucun paiement n'a été effectué.") }, { status: 500 });

  // Les passerelles de paiement exigent une adresse email : sans email (achat physique sans compte) on utilise l'adresse technique
  const payEmail = input.email || technicalEmail(input.phone);

  // Paiement à la livraison (produits physiques seulement, contrôlé par la base) : rien à payer en ligne.
  if (input.paymentMethod === "cod") {
    await notifySellerOfCashOrder(db, input, order.order_id);
    return NextResponse.json({ url: `${appUrl()}/download/${order.download_token}`, orderCode: order.order_code ?? null });
  }

  // Autres moyens de paiement : uniquement s'ils sont activés (clés présentes sur Vercel)
  if (input.provider !== "fapshi" && !enabledProviders().includes(input.provider)) {
    await db.from("transactions").update({ status: "failed", fapshi_status: "FAILED" }).eq("id", order.transaction_id);
    await db.from("orders").update({ payment_status: "failed" }).eq("id", order.order_id);
    return NextResponse.json({ error: explain("Ce moyen de paiement n'est pas encore activé sur le site.", "Choisissez un autre moyen de paiement. Aucun argent n'a été débité.") }, { status: 400 });
  }

  // Frais de service payés par l'acheteur (selon le moyen de paiement, réglés dans l'admin) : calculés et enregistrés PAR LA BASE,
  // puis ce total (prix + livraison + frais) est celui envoyé à la passerelle et contrôlé à la confirmation du paiement.
  const feeRes = await db.rpc("apply_service_fee", { p_tx: order.transaction_id, p_gateway: input.provider });
  if (feeRes.error) {
    console.error("[checkout] frais de service non appliqués", feeRes.error.message);
    await db.from("transactions").update({ status: "failed", fapshi_status: "FAILED" }).eq("id", order.transaction_id);
    await db.from("orders").update({ payment_status: "failed" }).eq("id", order.order_id);
    return NextResponse.json({ error: explain("Le calcul du total à payer a échoué.", "Réessayez dans un instant. Aucun argent n'a été débité.") }, { status: 500 });
  }
  const feeInfo = asRow<{ total?: number | string }>(feeRes.data);
  const payTotal = Number(feeInfo?.total);
  if (!Number.isInteger(payTotal) || payTotal < order.total) {
    await db.from("transactions").update({ status: "failed", fapshi_status: "FAILED" }).eq("id", order.transaction_id);
    await db.from("orders").update({ payment_status: "failed" }).eq("id", order.order_id);
    return NextResponse.json({ error: explain("Le calcul du total à payer a échoué.", "Réessayez dans un instant. Aucun argent n'a été débité.") }, { status: 500 });
  }

  if (input.provider === "paypal") {
    try {
      // Taux du jour, VERROUILLÉ ici : le montant en devise est calculé par le serveur (jamais envoyé par le navigateur)
      const rates = await getFxRates();
      const margin = fxMarginPercent();
      const quote = quoteFromFcfa(payTotal, input.currency, rates, margin);
      const pay = await createPaypalOrder({
        transactionId: order.transaction_id,
        title: order.title,
        currency: quote.currency,
        minor: quote.minor,
        returnUrl: `${appUrl()}/download/${order.download_token}`,
        cancelUrl: `${appUrl()}/p/${input.productId}`,
      });
      const { error: saveError } = await db
        .from("transactions")
        .update({
          fapshi_trans_id: `${REF_PREFIX.paypal}${pay.orderId}`,
          fapshi_link: pay.link,
          fapshi_status: "CREATED",
          pay_currency: quote.currency,
          pay_amount: minorToDecimal(quote.minor, quote.currency),
          fx_rate: quote.rate,
          fx_source: `${rates.source}${rates.cached ? " (copie)" : ""} @ ${rates.asOf}`,
          fx_locked_at: new Date().toISOString(),
        })
        .eq("id", order.transaction_id);
      if (saveError) throw new Error(saveError.message);
      return NextResponse.json({ url: pay.link, orderCode: order.order_code ?? null });
    } catch (e) {
      console.error("[checkout] PayPal indisponible", e instanceof Error ? e.message : e);
      await db.from("transactions").update({ status: "failed", fapshi_status: "FAILED" }).eq("id", order.transaction_id);
      await db.from("orders").update({ payment_status: "failed" }).eq("id", order.order_id);
      if (e instanceof FxUnavailableError) {
        return NextResponse.json({ error: explain("Les taux de change sont momentanément indisponibles, le paiement en devise étrangère est suspendu.", "Payez en Mobile Money (FCFA) ou réessayez dans quelques minutes. Aucun argent n'a été débité.") }, { status: 503 });
      }
      return NextResponse.json({ error: explainPaymentError(e) }, { status: 502 });
    }
  }

  if (input.provider === "flutterwave" || input.provider === "crypto") {
    try {
      const back = `${appUrl()}/download/${order.download_token}`;
      let ref: string;
      let link: string;
      if (input.provider === "flutterwave") {
        const txRef = order.order_id;
        const pay = await initiateFlutterwave({ txRef, amountFcfa: payTotal, email: payEmail, name: input.name, redirectUrl: back, title: order.title });
        ref = `${REF_PREFIX.flutterwave}${txRef}`;
        link = pay.link;
      } else {
        const inv = await createCryptoInvoice({
          orderId: order.order_id,
          amountFcfa: payTotal,
          title: order.title,
          successUrl: back,
          cancelUrl: `${appUrl()}/p/${input.productId}`,
          ipnUrl: `${appUrl()}/api/webhook/crypto`,
        });
        ref = `${REF_PREFIX.crypto}${inv.invoiceId}`;
        link = inv.link;
      }
      const { error: saveError } = await db
        .from("transactions")
        .update({ fapshi_trans_id: ref, fapshi_link: link, fapshi_status: "CREATED" })
        .eq("id", order.transaction_id);
      if (saveError) throw new Error(saveError.message);
      return NextResponse.json({ url: link });
    } catch (e) {
      console.error("[checkout] fournisseur indisponible", input.provider, e instanceof Error ? e.message : e);
      await db.from("transactions").update({ status: "failed", fapshi_status: "FAILED" }).eq("id", order.transaction_id);
      await db.from("orders").update({ payment_status: "failed" }).eq("id", order.order_id);
      return NextResponse.json({ error: explainPaymentError(e) }, { status: 502 });
    }
  }

  try {
    const pay = await initiatePay({
      amount: payTotal,
      email: payEmail,
      redirectUrl: `${appUrl()}/download/${order.download_token}`,
      userId: user?.id ?? order.order_id,
      externalId: order.order_id,
      message: order.title,
    });
    const { error: saveError } = await db
      .from("transactions")
      .update({ fapshi_trans_id: pay.transId, fapshi_link: pay.link, fapshi_status: "CREATED" })
      .eq("id", order.transaction_id);
    if (saveError) throw new Error(saveError.message);
    return NextResponse.json({ url: pay.link, orderCode: order.order_code ?? null });
  } catch (e) {
    console.error("[checkout] Fapshi indisponible", e instanceof Error ? e.message : e);
    await db.from("transactions").update({ status: "failed", fapshi_status: "FAILED" }).eq("id", order.transaction_id);
    await db.from("orders").update({ payment_status: "failed" }).eq("id", order.order_id);
    return NextResponse.json({ error: explainPaymentError(e) }, { status: 502 });
  }
}

/** Prévient le vendeur par email d'une commande en cash (l'échec de l'email ne bloque jamais la commande). */
async function notifySellerOfCashOrder(db: ReturnType<typeof createAdminClient>, input: CheckoutInput, orderId: string): Promise<void> {
  try {
    const { data: o } = await db.from("orders").select("seller_id, product_id, quantity, delivery_method").eq("id", orderId).maybeSingle();
    const order = asRow<{ seller_id: string; product_id: string; quantity: number; delivery_method: DeliveryMethod | null }>(o);
    if (!order || !order.delivery_method) return;
    const { data: p } = await db.from("products").select("title").eq("id", order.product_id).maybeSingle();
    const { data: seller } = await db.auth.admin.getUserById(order.seller_id);
    const to = seller.user?.email;
    if (!to) return;
    await sendSellerNewOrderEmail({
      to,
      productTitle: asRow<{ title: string }>(p)?.title ?? "Produit",
      quantity: order.quantity,
      deliveryLabel: DELIVERY_LABELS[order.delivery_method],
      buyerName: input.name || null,
      buyerPhone: input.phone || null,
      address: [input.district, input.city].filter(Boolean).join(", ") || input.address || null,
      dashboardUrl: `${appUrl()}/dashboard/orders`,
      cash: true,
    });
  } catch (e) {
    console.error("[checkout] email vendeur (cash) non envoyé", e instanceof Error ? e.message : e);
  }
}
