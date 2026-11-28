"use client";
import { useEffect } from "react";
import { reportError } from "@/lib/reportError";

// Dernier filet de sécurité : erreur dans la mise en page elle-même (le style du site peut ne pas être chargé : styles en ligne).
export default function GlobalError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => reportError(error), [error]);
  return (
    <html lang="fr">
      <body style={{ margin: 0, background: "#0b0b12", color: "#fff", fontFamily: "system-ui, sans-serif", display: "grid", placeItems: "center", minHeight: "100vh", padding: 16 }}>
        <div style={{ maxWidth: 420, textAlign: "center" }}>
          <h1 style={{ fontSize: 24 }}>Oups, un problème est survenu</h1>
          <p style={{ color: "#c4c4d0", fontSize: 14 }}>
            Le site n&apos;a pas pu s&apos;afficher. Rechargez la page. Si cela continue, revenez dans quelques minutes : l&apos;équipe a été prévenue.
          </p>
          {error.digest && <p style={{ color: "#8a8a99", fontFamily: "monospace", fontSize: 12 }}>Référence : {error.digest}</p>}
          <button type="button" onClick={reset} style={{ marginTop: 12, padding: "10px 20px", borderRadius: 12, border: 0, background: "#6366f1", color: "#fff", fontSize: 15 }}>Réessayer</button>
        </div>
      </body>
    </html>
  );
}
