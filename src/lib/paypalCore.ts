// PayPal : logique PURE (sans réseau ni base), donc testable seule. Le client réseau est dans paypal.ts.
import { decimalToMinor, minorToDecimal, type FxCurrency } from "@/lib/fxCore";

export interface ExpectedPayment {
  /** Id de notre transaction (transmis à PayPal dans custom_id et relu à l'arrivée). */
  transactionId: string;
  currency: FxCurrency;
  /** Montant verrouillé à la commande, en centimes. */
  minor: number;
}

export type OrderVerdict =
  | { kind: "paid" }
  | { kind: "approved" } // le client a validé chez PayPal mais l'argent n'est pas encore capturé : il faut capturer
  | { kind: "pending" }
  | { kind: "failed" }
  | { kind: "mismatch"; reason: string }; // payé mais montant, devise ou référence différents : jamais crédité automatiquement

function isRecord(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

export function buildCreateOrderBody(a: {
  transactionId: string;
  title: string;
  currency: FxCurrency;
  minor: number;
  returnUrl: string;
  cancelUrl: string;
}): Record<string, unknown> {
  return {
    intent: "CAPTURE",
    purchase_units: [
      {
        custom_id: a.transactionId,
        description: a.title.slice(0, 120),
        amount: { currency_code: a.currency, value: minorToDecimal(a.minor, a.currency) },
      },
    ],
    payment_source: {
      paypal: {
        experience_context: {
          brand_name: "KDDF Market",
          locale: "fr-FR",
          shipping_preference: "NO_SHIPPING",
          user_action: "PAY_NOW",
          return_url: a.returnUrl,
          cancel_url: a.cancelUrl,
        },
      },
    },
  };
}

/** Lien où envoyer l'acheteur pour valider son paiement chez PayPal. */
export function approvalLink(json: unknown): string | null {
  if (!isRecord(json) || !Array.isArray(json.links)) return null;
  for (const rel of ["payer-action", "approve"]) {
    for (const l of json.links) {
      if (isRecord(l) && l.rel === rel && typeof l.href === "string" && /^https:\/\/[a-z0-9.-]*paypal\.com\//i.test(l.href)) return l.href;
    }
  }
  return null;
}

/** Lit une commande PayPal (ou la réponse d'une capture) et dit où en est le paiement, en contrôlant montant, devise et référence. */
export function interpretOrder(json: unknown, expected: ExpectedPayment): OrderVerdict {
  if (!isRecord(json) || typeof json.status !== "string") return { kind: "pending" };
  switch (json.status) {
    case "COMPLETED":
      break;
    case "APPROVED":
      return { kind: "approved" };
    case "VOIDED":
      return { kind: "failed" };
    default:
      return { kind: "pending" }; // CREATED, SAVED, PAYER_ACTION_REQUIRED...
  }
  const units = Array.isArray(json.purchase_units) ? json.purchase_units : [];
  const unit = units.length > 0 && isRecord(units[0]) ? units[0] : null;
  const payments = unit && isRecord(unit.payments) ? unit.payments : null;
  const captures = payments && Array.isArray(payments.captures) ? payments.captures : [];
  const cap = captures.length > 0 && isRecord(captures[0]) ? captures[0] : null;
  if (!cap || typeof cap.status !== "string") return { kind: "pending" };
  if (cap.status === "PENDING") return { kind: "pending" };
  if (cap.status !== "COMPLETED") return { kind: "failed" }; // DECLINED, FAILED, REFUNDED, PARTIALLY_REFUNDED...
  const amount = isRecord(cap.amount) ? cap.amount : null;
  const currency = amount && typeof amount.currency_code === "string" ? amount.currency_code : "";
  const value = amount && typeof amount.value === "string" ? amount.value : "";
  const paidMinor = decimalToMinor(value, expected.currency);
  const customId = typeof cap.custom_id === "string" ? cap.custom_id : unit && typeof unit.custom_id === "string" ? unit.custom_id : "";
  if (currency !== expected.currency) return { kind: "mismatch", reason: `devise reçue ${currency || "?"}, attendue ${expected.currency}` };
  if (paidMinor === null || paidMinor !== expected.minor) return { kind: "mismatch", reason: `montant reçu ${value || "?"} ${currency}, attendu ${minorToDecimal(expected.minor, expected.currency)}` };
  if (customId !== expected.transactionId) return { kind: "mismatch", reason: "référence de transaction différente" };
  return { kind: "paid" };
}

/** Id de commande PayPal contenu dans un événement de webhook (paiement capturé ou commande approuvée). */
export function orderIdFromEvent(event: unknown): string | null {
  if (!isRecord(event) || typeof event.event_type !== "string" || !isRecord(event.resource)) return null;
  const r = event.resource;
  if (event.event_type === "CHECKOUT.ORDER.APPROVED") return typeof r.id === "string" ? r.id : null;
  if (event.event_type === "PAYMENT.CAPTURE.COMPLETED") {
    const sup = isRecord(r.supplementary_data) ? r.supplementary_data : null;
    const rel = sup && isRecord(sup.related_ids) ? sup.related_ids : null;
    return rel && typeof rel.order_id === "string" ? rel.order_id : null;
  }
  return null;
}

/** Un id de commande PayPal est une courte chaîne de lettres/chiffres : on refuse tout le reste avant de l'utiliser dans une URL. */
export function isPaypalOrderId(v: unknown): v is string {
  return typeof v === "string" && /^[A-Z0-9]{8,40}$/.test(v);
}
