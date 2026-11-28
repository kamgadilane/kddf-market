// Client PayPal (API Orders v2).
//   POST /v1/oauth2/token                            -> jeton d'accès (mis en mémoire jusqu'à son expiration)
//   POST /v2/checkout/orders                         -> crée la commande, renvoie le lien de validation pour l'acheteur
//   GET  /v2/checkout/orders/{id}                    -> statut réel (on ne croit jamais le webhook ni l'URL de retour)
//   POST /v2/checkout/orders/{id}/capture            -> encaisse une commande approuvée (PayPal-Request-Id : jamais deux captures)
//   POST /v1/notification/verify-webhook-signature   -> vérifie la signature d'un webhook
// Le montant en devise étrangère est VERROUILLÉ à la création (colonnes pay_amount / pay_currency de transactions) :
// à l'arrivée, montant, devise et référence doivent être identiques, sinon la vente passe « à vérifier » sans crédit.
import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { asRow } from "@/lib/db";
import type { FapshiTransaction } from "@/lib/fapshi";
import { isFxCurrency } from "@/lib/fxCore";
import type { FxCurrency } from "@/lib/fxCore";
import { approvalLink, buildCreateOrderBody, interpretOrder, isPaypalOrderId } from "@/lib/paypalCore";

export class PayPalError extends Error {
  readonly status: number;
  constructor(message: string, status: number) {
    super(message);
    this.name = "PayPalError";
    this.status = status;
  }
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

export function paypalConfigured(): boolean {
  return Boolean(process.env.PAYPAL_CLIENT_ID && process.env.PAYPAL_CLIENT_SECRET);
}

function base(): string {
  return process.env.PAYPAL_ENV === "live" ? "https://api-m.paypal.com" : "https://api-m.sandbox.paypal.com";
}

let tokenCache: { token: string; expiresAt: number } | null = null;

async function accessToken(): Promise<string> {
  if (tokenCache && Date.now() < tokenCache.expiresAt - 60_000) return tokenCache.token;
  const id = process.env.PAYPAL_CLIENT_ID;
  const secret = process.env.PAYPAL_CLIENT_SECRET;
  if (!id || !secret) throw new Error("PAYPAL_CLIENT_ID / PAYPAL_CLIENT_SECRET manquants dans les variables d'environnement");
  const res = await fetch(`${base()}/v1/oauth2/token`, {
    method: "POST",
    headers: { Authorization: `Basic ${Buffer.from(`${id}:${secret}`).toString("base64")}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=client_credentials",
    cache: "no-store",
    signal: AbortSignal.timeout(15000),
  });
  const json: unknown = await res.json().catch(() => null);
  if (!res.ok || !isRecord(json) || typeof json.access_token !== "string") throw new PayPalError("Identifiants PayPal refusés (vérifiez PAYPAL_CLIENT_ID, PAYPAL_CLIENT_SECRET et PAYPAL_ENV).", res.status);
  const ttl = typeof json.expires_in === "number" ? json.expires_in : 300;
  tokenCache = { token: json.access_token, expiresAt: Date.now() + ttl * 1000 };
  return json.access_token;
}

async function call(path: string, init: { method: "GET" | "POST"; body?: unknown; requestId?: string }): Promise<{ status: number; json: unknown }> {
  const headers: Record<string, string> = { Authorization: `Bearer ${await accessToken()}`, "Content-Type": "application/json", Accept: "application/json" };
  if (init.requestId) headers["PayPal-Request-Id"] = init.requestId;
  const res = await fetch(`${base()}${path}`, {
    method: init.method,
    headers,
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
    cache: "no-store",
    signal: AbortSignal.timeout(20000),
  });
  const json: unknown = await res.json().catch(() => null);
  return { status: res.status, json };
}

function messageOf(json: unknown, status: number): string {
  if (isRecord(json)) {
    if (typeof json.message === "string") return json.message;
    if (typeof json.error_description === "string") return json.error_description;
  }
  return `Erreur HTTP ${status}`;
}

/** Crée la commande PayPal et renvoie le lien de validation. */
export async function createPaypalOrder(a: {
  transactionId: string;
  title: string;
  currency: FxCurrency;
  minor: number;
  returnUrl: string;
  cancelUrl: string;
}): Promise<{ orderId: string; link: string }> {
  const { status, json } = await call("/v2/checkout/orders", { method: "POST", body: buildCreateOrderBody(a), requestId: `kddf-order-${a.transactionId}` });
  const orderId = isRecord(json) ? json.id : null;
  const link = approvalLink(json);
  if (status < 200 || status >= 300 || !isPaypalOrderId(orderId) || !link) throw new PayPalError(messageOf(json, status), status);
  return { orderId, link };
}

interface ExpectedRow {
  id: string;
  total_amount: number;
  pay_currency: string | null;
  pay_amount: number | string | null;
}

/**
 * Statut réel d'un paiement PayPal, au format commun avec Fapshi (ref = id de commande PayPal, sans le préfixe « pp: »).
 * Si le client a validé mais que l'argent n'est pas encore capturé, on le capture ici (idempotent).
 */
export async function getPaypalStatus(orderId: string): Promise<FapshiTransaction> {
  const ref = `pp:${orderId}`;
  const pending: FapshiTransaction = { transId: ref, status: "PENDING", amount: 0, revenue: null, medium: "paypal", externalId: orderId };
  if (!isPaypalOrderId(orderId)) return pending;

  const { data } = await createAdminClient().from("transactions").select("id, total_amount, pay_currency, pay_amount").eq("fapshi_trans_id", ref).maybeSingle();
  const row = asRow<ExpectedRow>(data);
  if (!row || !isFxCurrency(row.pay_currency) || row.pay_amount === null) return pending;
  const minor = Math.round(Number(row.pay_amount) * 100);
  const expected = { transactionId: row.id, currency: row.pay_currency, minor };

  let res = await call(`/v2/checkout/orders/${orderId}`, { method: "GET" });
  if (res.status === 404) return pending;
  if (res.status < 200 || res.status >= 300) throw new PayPalError(messageOf(res.json, res.status), res.status);
  let verdict = interpretOrder(res.json, expected);

  if (verdict.kind === "approved") {
    res = await call(`/v2/checkout/orders/${orderId}/capture`, { method: "POST", body: {}, requestId: `kddf-capture-${row.id}` });
    if (res.status < 200 || res.status >= 300) {
      // 422 ORDER_ALREADY_CAPTURED : la capture a déjà eu lieu (autre appel simultané) -> on relit la commande
      const again = await call(`/v2/checkout/orders/${orderId}`, { method: "GET" });
      if (again.status < 200 || again.status >= 300) throw new PayPalError(messageOf(res.json, res.status), res.status);
      res = again;
    }
    verdict = interpretOrder(res.json, expected);
  }

  switch (verdict.kind) {
    case "paid":
      return { ...pending, status: "SUCCESSFUL", amount: row.total_amount, medium: "paypal" };
    case "mismatch":
      console.error("[paypal] paiement reçu mais différent de l'attendu :", orderId, verdict.reason);
      return { ...pending, status: "SUCCESSFUL", amount: -1, medium: "paypal" }; // montant volontairement faux -> « à vérifier », aucun crédit
    case "failed":
      return { ...pending, status: "FAILED" };
    default:
      return pending;
  }
}

/** Vérifie la signature d'un webhook PayPal (en-têtes PAYPAL-*). Faux si PAYPAL_WEBHOOK_ID est absent ou si la vérification échoue. */
export async function verifyPaypalWebhook(headers: { get(name: string): string | null }, event: unknown): Promise<boolean> {
  const webhookId = process.env.PAYPAL_WEBHOOK_ID;
  if (!webhookId || !isRecord(event)) return false;
  const get = (n: string): string => headers.get(n) ?? "";
  const body = {
    auth_algo: get("paypal-auth-algo"),
    cert_url: get("paypal-cert-url"),
    transmission_id: get("paypal-transmission-id"),
    transmission_sig: get("paypal-transmission-sig"),
    transmission_time: get("paypal-transmission-time"),
    webhook_id: webhookId,
    webhook_event: event,
  };
  if (!body.transmission_id || !body.transmission_sig || !/^https:\/\/api(-m)?\.(sandbox\.)?paypal\.com\//i.test(body.cert_url)) return false;
  const { status, json } = await call("/v1/notification/verify-webhook-signature", { method: "POST", body });
  return status >= 200 && status < 300 && isRecord(json) && json.verification_status === "SUCCESS";
}
