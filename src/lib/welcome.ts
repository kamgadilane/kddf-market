import "server-only";
import { createClient } from "@/lib/supabase/server";
import { sendEmail } from "@/lib/mailer";
import { welcomeEmail } from "@/lib/emailTemplates";

/**
 * Email de bienvenue (modèle confirmation_inscription.html) : envoyé UNE seule fois par compte.
 * La base « réserve » l'envoi (claim_welcome_email) : même avec deux onglets ouverts en même temps, un seul email part.
 * Si l'envoi échoue, la réservation est rendue et l'envoi sera retenté à la prochaine connexion.
 * Le lien de confirmation lui-même (clic obligatoire) est l'email Supabase : voir supabase/email-templates/.
 */
export async function sendWelcomeIfNeeded(): Promise<"sent" | "already" | "skipped" | "failed"> {
  try {
    const supabase = createClient();
    const { data: auth } = await supabase.auth.getUser();
    const user = auth.user;
    if (!user || !user.email) return "skipped";
    const { data: claimed, error } = await supabase.rpc("claim_welcome_email");
    if (error) {
      console.error("[bienvenue] réservation impossible :", error.message);
      return "failed";
    }
    if (claimed !== true) return "already";
    const meta = user.user_metadata as { full_name?: unknown } | undefined;
    const name = typeof meta?.full_name === "string" ? meta.full_name : null;
    const result = await sendEmail({ to: user.email, kind: "welcome", ...welcomeEmail({ name }) });
    if (result === "sent" || result === "queued") return "sent";
    await supabase.rpc("release_welcome_email"); // pas envoyé (clé absente ou échec) : on réessaiera plus tard
    return result === "skipped" ? "skipped" : "failed";
  } catch (e) {
    console.error("[bienvenue] ignoré :", e instanceof Error ? e.message : e);
    return "failed";
  }
}
