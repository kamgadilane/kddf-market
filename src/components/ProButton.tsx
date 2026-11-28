"use client";
import { explainError } from "@/lib/errors";
import { useState } from "react";

// Lance le paiement Fapshi de l'abonnement Pro puis redirige vers la page de paiement.
export default function ProButton({ label }: { label: string }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function pay(): Promise<void> {
    setBusy(true);
    setError("");
    try {
      const res = await fetch("/api/pro", { method: "POST" });
      const json: unknown = await res.json().catch(() => null);
      const body = json !== null && typeof json === "object" ? (json as { url?: unknown; error?: unknown }) : {};
      if (res.ok && typeof body.url === "string") {
        window.location.href = body.url;
        return;
      }
      setError(typeof body.error === "string" ? body.error : explainError(undefined));
    } catch {
      setError(explainError("failed to fetch"));
    }
    setBusy(false);
  }

  return (
    <div className="space-y-2">
      <button type="button" onClick={pay} disabled={busy} className="btn-primary">{busy ? "Redirection…" : label}</button>
      {error && <p role="alert" className="whitespace-pre-line text-xs text-red-300">{error}</p>}
    </div>
  );
}
