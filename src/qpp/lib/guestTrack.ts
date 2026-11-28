import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { rateLimit, rateLimitIp } from "@/lib/rateLimit";
import { normalizeOrderCode } from "@/lib/guest";
import { asRow } from "@/lib/db";
import { cleanText } from "@/lib/validate";

/** Numéro + code saisis par le client, vérifiés (format) et limités en débit (anti-devinette de codes). */
export interface GuestKey {
  phone: string;
  code: string;
}

export type GuestKeyResult = { ok: true; key: GuestKey } | { ok: false; status: number; error: string };

export const NOT_FOUND_MESSAGE = "Commande introuvable. Vérifiez le numéro utilisé pour commander et le code (ex. KDDF-8421).";

/**
 * Vérifie le format du numéro et du code, puis applique la limitation de débit :
 *  - par adresse IP : 20 essais / 10 min ;
 *  - par numéro : 10 essais / 10 min (empêche de deviner les 10 000 codes pour un numéro donné).
 */
export async function readGuestKey(req: Request, rawPhone: unknown, rawCode: unknown): Promise<GuestKeyResult> {
  const phone = cleanText(rawPhone, 25);
  const digits = phone.replace(/\D/g, "");
  const code = typeof rawCode === "string" ? normalizeOrderCode(rawCode) : null;
  if (digits.length < 8 || digits.length > 15 || !code) {
    return { ok: false, status: 400, error: "Saisissez le numéro utilisé pour commander et le code de commande (ex. KDDF-8421)." };
  }
  if (!(await rateLimitIp(req, "suivre-ip", 20, 600)) || !(await rateLimit(`suivre-tel:${digits.slice(-9)}`, 10, 600))) {
    return { ok: false, status: 429, error: "Trop d'essais. Patientez quelques minutes puis réessayez." };
  }
  return { ok: true, key: { phone, code } };
}

/** Id interne de la commande (jamais renvoyé au navigateur). */
export async function findGuestOrderId(key: GuestKey): Promise<string | null> {
  const { data, error } = await createAdminClient().rpc("guest_find_order", { p_phone: key.phone, p_code: key.code });
  if (error) return null;
  return typeof data === "string" ? data : null;
}

/** Suivi d'une commande (réponse sans order_id). null = introuvable. */
export async function trackGuestOrder(key: GuestKey): Promise<Record<string, unknown> | null> {
  const { data, error } = await createAdminClient().rpc("guest_track_order", { p_phone: key.phone, p_code: key.code });
  if (error) return null;
  const row = asRow<Record<string, unknown>>(data);
  if (!row || row.found !== true) return null;
  const { order_id: _orderId, found: _found, ...safe } = row;
  void _orderId;
  void _found;
  return safe;
}
