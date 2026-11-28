import "server-only";
import { Resend } from "resend";
import { appName } from "@/lib/env";

/**
 * Client Resend UNIQUE du site. RESEND_API_KEY n'est lue que côté serveur (ce fichier est « server-only » :
 * l'importer depuis un composant client fait échouer le build, la clé ne peut donc jamais partir dans le navigateur).
 *
 *  - pas de clé  -> aucun envoi (résultat « RESEND_API_KEY absente ») ;
 *  - un envoi qui échoue est RÉESSAYÉ UNE FOIS (sendWithRetry), l'erreur est écrite dans les logs du serveur ;
 *  - si le 2e essai échoue aussi, lib/mailer.ts met l'email en file d'attente (table email_outbox) pour un envoi différé.
 *  - ces fonctions ne lèvent JAMAIS d'exception : un email raté ne bloque jamais une vente.
 */
export interface ResendMessage {
  to: string;
  subject: string;
  html: string;
  text?: string | null;
  replyTo?: string | null;
}

export function resendConfigured(): boolean {
  return Boolean(process.env.RESEND_API_KEY);
}

/** Expéditeur : EMAIL_FROM (domaine vérifié chez Resend), sinon une adresse d'exemple (à remplacer en production). */
export function emailFrom(): string {
  return process.env.EMAIL_FROM || `${appName()} <no-reply@example.com>`;
}

/** Un seul essai. Renvoie null si tout va bien, sinon le message d'erreur. */
export async function sendOnce(m: ResendMessage): Promise<string | null> {
  const key = process.env.RESEND_API_KEY;
  if (!key) return "RESEND_API_KEY absente";
  try {
    const { error } = await new Resend(key).emails.send({
      from: emailFrom(),
      to: m.to,
      subject: m.subject,
      html: m.html,
      ...(m.text ? { text: m.text } : {}),
      ...(m.replyTo ? { replyTo: m.replyTo } : {}),
    });
    return error ? error.message : null;
  } catch (e) {
    return e instanceof Error ? e.message : "erreur inconnue";
  }
}

const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

/** Un essai + UN réessai après une courte pause. Chaque échec est écrit dans les logs (sans le contenu de l'email). */
export async function sendWithRetry(m: ResendMessage, kind: string, delayMs = 1500): Promise<string | null> {
  const first = await sendOnce(m);
  if (first === null) return null;
  console.error(`[resend] échec d'envoi (${kind}), nouvel essai dans ${delayMs} ms :`, first);
  await sleep(delayMs);
  const second = await sendOnce(m);
  if (second !== null) console.error(`[resend] 2e échec (${kind}) :`, second);
  return second;
}
