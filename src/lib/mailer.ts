import "server-only";
import { resendConfigured, sendOnce, sendWithRetry } from "@/lib/resend";
import { createAdminClient } from "@/lib/supabase/admin";
import { asRows } from "@/lib/db";
import { isEmail } from "@/lib/validate";
import { isTechnicalEmail } from "@/lib/guest";
import type { EmailMessage } from "@/lib/emailTemplates";

/**
 * Expéditeur d'emails UNIQUE du site (Resend).
 *  - sans RESEND_API_KEY : rien n'est envoyé (résultat "skipped"), pratique en développement ;
 *  - si Resend échoue : UN réessai immédiat (lib/resend.ts), puis, si `retry` est vrai, l'email est mis en file (table email_outbox)
 *    et renvoyé automatiquement par la tâche planifiée (processOutbox), 6 essais maximum ;
 *  - l'erreur est toujours écrite dans les logs du serveur et dans email_outbox.last_error ;
 *  - ne lève JAMAIS d'exception : un email raté ne doit jamais bloquer une vente ni une livraison.
 */
export type MailResult = "sent" | "queued" | "skipped" | "failed";

export interface OutgoingEmail extends EmailMessage {
  to: string;
  /** Famille d'email (purchase, seller_order, support...) : sert au diagnostic dans la file. */
  kind: string;
  replyTo?: string;
  /** Mettre en file d'attente en cas d'échec (défaut : oui). */
  retry?: boolean;
}

export async function sendEmail(m: OutgoingEmail): Promise<MailResult> {
  if (!resendConfigured()) return "skipped";
  // Client sans compte : l'adresse « invite-…@example.com » est purement technique, on n'écrit jamais dessus.
  if (isTechnicalEmail(m.to)) return "skipped";
  if (!isEmail(m.to)) {
    console.error("[email] destinataire invalide, email ignoré :", m.kind);
    return "failed";
  }
  const err = await sendWithRetry({ to: m.to, subject: m.subject, html: m.html, text: m.text, replyTo: m.replyTo }, m.kind);
  if (err === null) return "sent";
  console.error(`[email] échec définitif d'envoi (${m.kind}) :`, err);
  if (m.retry === false) return "failed";
  try {
    const { error } = await createAdminClient().from("email_outbox").insert({
      kind: m.kind,
      to_email: m.to,
      subject: m.subject,
      html: m.html,
      text_body: m.text,
      reply_to: m.replyTo ?? null,
      attempts: 2, // 1er essai + réessai immédiat déjà faits
      last_error: err.slice(0, 300),
      next_attempt_at: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
    });
    if (error) {
      console.error("[email] mise en file impossible :", error.message);
      return "failed";
    }
    return "queued";
  } catch (e) {
    console.error("[email] mise en file impossible :", e instanceof Error ? e.message : e);
    return "failed";
  }
}

interface OutboxRow {
  id: string;
  to_email: string;
  subject: string;
  html: string;
  text_body: string | null;
  reply_to: string | null;
}

/** Renvoie les emails en attente (appelée par la tâche planifiée). */
export async function processOutbox(limit = 20): Promise<{ sent: number; failed: number }> {
  const out = { sent: 0, failed: 0 };
  try {
    const db = createAdminClient();
    const { data, error } = await db.rpc("outbox_claim", { p_limit: limit });
    if (error) {
      console.error("[email] file d'attente illisible :", error.message);
      return out;
    }
    for (const row of asRows<OutboxRow>(data)) {
      const err = await sendOnce({ to: row.to_email, subject: row.subject, html: row.html, text: row.text_body, replyTo: row.reply_to });
      await db.rpc("outbox_report", { p_id: row.id, p_ok: err === null, p_error: err });
      if (err === null) out.sent += 1;
      else out.failed += 1;
    }
  } catch (e) {
    console.error("[email] traitement de la file impossible :", e instanceof Error ? e.message : e);
  }
  return out;
}
