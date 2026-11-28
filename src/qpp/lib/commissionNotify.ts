import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { appName } from "@/lib/env";
import { asRows } from "@/lib/db";
import { sendEmail } from "@/lib/mailer";
import { resendConfigured } from "@/lib/resend";
import { commissionChangeEmail } from "@/lib/emailTemplates";

export function commissionMessage(newPercent: number): string {
  return `La commission de ${appName()} passe à ${String(newPercent).replace(".", ",")} % sur chaque vente, à partir d'aujourd'hui. Les ventes déjà faites ne changent pas. Merci pour votre confiance !`;
}

/** Vendeurs (ayant au moins un produit) à prévenir. */
export async function listSellerIds(limit = 300): Promise<string[]> {
  const { data } = await createAdminClient().from("products").select("seller_id").limit(5000);
  return Array.from(new Set(asRows<{ seller_id: string }>(data).map((r) => r.seller_id))).slice(0, limit);
}

/**
 * Prévient les vendeurs par email (Resend). Retourne le nombre d'emails envoyés ou mis en file, ou -1 si Resend n'est pas configuré.
 * Ne bloque jamais le changement de commission : toute erreur est ignorée.
 */
export async function notifySellersByEmail(newPercent: number): Promise<number> {
  if (!resendConfigured()) return -1;
  const db = createAdminClient();
  const mail = commissionChangeEmail(commissionMessage(newPercent));
  const ids = await listSellerIds();
  let sent = 0;
  for (let i = 0; i < ids.length; i += 10) {
    const chunk = ids.slice(i, i + 10);
    const results = await Promise.all(
      chunk.map(async (id) => {
        try {
          const { data } = await db.auth.admin.getUserById(id);
          const to = data.user?.email;
          if (!to) return 0;
          const r = await sendEmail({ to, kind: "commission_change", ...mail });
          return r === "sent" || r === "queued" ? 1 : 0;
        } catch {
          return 0;
        }
      })
    );
    sent += results.reduce<number>((a, b) => a + b, 0);
  }
  return sent;
}
