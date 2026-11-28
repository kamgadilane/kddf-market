"use client";

// Envoie une erreur d'affichage au journal du site (Admin > Erreurs). Silencieux : ne doit JAMAIS aggraver le problème.
const sent = new Set<string>();

export function reportError(error: Error & { digest?: string }): void {
  try {
    const key = `${error.digest ?? ""}|${error.message}`;
    if (sent.has(key) || sent.size >= 5) return; // pas de boucle d'envois : 5 erreurs distinctes au maximum par page
    sent.add(key);
    void fetch("/api/errors", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: error.message, digest: error.digest ?? null, url: window.location.pathname }),
      keepalive: true,
    }).catch(() => undefined);
  } catch {
    /* rien */
  }
}
