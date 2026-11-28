"use client";
import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { explainError } from "@/lib/errors";

// Redirection après validation : uniquement vers une page de NOTRE site (pas de lien externe).
function safeNext(next: string | null): string {
  return next !== null && next.startsWith("/") && !next.startsWith("//") ? next : "/dashboard";
}

function TwoFactorStep() {
  const router = useRouter();
  const params = useSearchParams();
  const [factorId, setFactorId] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");
  const [ready, setReady] = useState(false);

  useEffect(() => {
    (async () => {
      const auth = createClient().auth;
      const { data } = await auth.mfa.listFactors();
      const verified = data?.totp.find((f) => f.status === "verified");
      if (!verified) {
        // Pas de 2FA sur ce compte (ou pas de session) : rien à vérifier ici
        router.replace(params.get("next") ? safeNext(params.get("next")) : "/login");
        return;
      }
      setFactorId(verified.id);
      setReady(true);
    })();
  }, [router, params]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!factorId || busy) return;
    setBusy(true);
    setMsg("");
    const { error } = await createClient().auth.mfa.challengeAndVerify({ factorId, code: code.trim() });
    if (error) {
      setMsg(explainError(error.message));
      setCode("");
      setBusy(false);
      return;
    }
    router.push(safeNext(params.get("next")));
    router.refresh();
  }

  async function cancel() {
    await createClient().auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <form onSubmit={submit} className="glass mx-auto mt-12 max-w-md space-y-4 p-6 sm:p-8">
      <h1 className="font-display text-2xl font-bold text-white">Vérification en 2 étapes</h1>
      <p className="text-sm text-zinc-400">Ouvrez votre application d&apos;authentification (Google Authenticator, Microsoft Authenticator, Authy) et saisissez le code à 6 chiffres de KDDF Market.</p>
      <div>
        <label className="label" htmlFor="code2fa">Code à 6 chiffres</label>
        <input id="code2fa" className="input tracking-widest" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} disabled={!ready} required autoFocus />
      </div>
      {msg && <p role="alert" className="whitespace-pre-line rounded-xl bg-red-500/10 px-4 py-2.5 text-sm text-red-200">{msg}</p>}
      <button className="btn-primary w-full" disabled={busy || !ready || code.length !== 6}>{busy ? "…" : "Valider"}</button>
      <button type="button" onClick={cancel} className="w-full text-center text-xs text-zinc-400 hover:text-white">Annuler et me déconnecter</button>
      <p className="text-center text-xs text-zinc-500">Téléphone perdu ? Écrivez au service client (page « Aide ») : après vérification de votre identité, l&apos;administrateur peut retirer la protection de votre compte.</p>
    </form>
  );
}

export default function TwoFactorPage() {
  return <Suspense><TwoFactorStep /></Suspense>;
}
