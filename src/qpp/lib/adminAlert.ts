import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { sendEmail } from "@/lib/mailer";
import { adminErrorAlertEmail } from "@/lib/emailTemplates";
import { adviceFor, URGENCY_LABEL } from "@/lib/errorAdvice";
import { legalInfo } from "@/lib/legal";

/** Adresse qui reçoit les alertes : ADMIN_ALERT_EMAIL, sinon SUPPORT_EMAIL, sinon l'email de l'éditeur du site. */
export function alertRecipient(): string {
  const pick = (v: string | undefined): string => (v ?? "").trim();
  return pick(process.env.ADMIN_ALERT_EMAIL) || pick(process.env.SUPPORT_EMAIL) || legalInfo().email;
}

/**
 * Prévient l'administrateur d'une erreur : une alerte dans la cloche (Admin) et un email avec la notice « que faire ».
 * Au plus UNE alerte toutes les 30 minutes (la base décide) : pas de déluge si un bug touche tout le monde.
 * Ne lève jamais d'exception.
 */
export async function alertAdminsOfError(a: { message: string; url: string | null; digest: string | null }): Promise<void> {
  try {
    const { data } = await createAdminClient().rpc("alert_admins_error", { p_message: a.message, p_url: a.url });
    if (data !== true) return;
    const advice = adviceFor(a.message);
    await sendEmail({
      to: alertRecipient(),
      kind: "admin_alert",
      retry: false,
      ...adminErrorAlertEmail({
        message: a.message,
        url: a.url,
        digest: a.digest,
        title: advice.title,
        cause: advice.cause,
        steps: advice.steps,
        urgencyLabel: URGENCY_LABEL[advice.urgency],
      }),
    });
  } catch {
    /* l'alerte ne doit jamais provoquer d'erreur */
  }
}
