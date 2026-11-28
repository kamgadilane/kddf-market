"use client";
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { explainError } from "@/lib/errors";

type Phase = "loading" | "off" | "scan" | "on" | "disable";

interface Enroll { factorId: string; qr: string; secret: string }

/**
 * Protection 2FA FACULTATIVE (application d'authentification : Google Authenticator, Microsoft Authenticator, Authy...).
 * - Activer : on affiche un QR code, l'utilisateur saisit le code à 6 chiffres pour prouver que ça marche.
 * - Désactiver : il faut saisir un code valide (c'est aussi la règle de Supabase), pour qu'un voleur de session ne puisse pas l'enlever.
 */
export default function TwoFactorSetup() {
  const router = useRouter();
  const [phase, setPhase] = useState<Phase>("loading");
  const [factorId, setFactorId] = useState<string | null>(null);
  const [enroll, setEnroll] = useState<Enroll | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  const refresh = useCallback(async () => {
    const { data, error } = await createClient().auth.mfa.listFactors();
    if (error || !data) {
      setMsg({ ok: false, text: explainError(error?.message) });
      setPhase("off");
      return;
    }
    const verified = data.totp.find((f) => f.status === "verified");
    setFactorId(verified?.id ?? null);
    setPhase(verified ? "on" : "off");
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function start() {
    setBusy(true);
    setMsg(null);
    const auth = createClient().auth;
    // Une activation abandonnée plus tôt laisse un facteur « non confirmé » : on le retire pour repartir proprement.
    const { data: list } = await auth.mfa.listFactors();
    for (const f of list?.all ?? []) if (f.status === "unverified") await auth.mfa.unenroll({ factorId: f.id });
    const { data, error } = await auth.mfa.enroll({ factorType: "totp", friendlyName: `KDDF Market ${new Date().toISOString().slice(0, 10)}` });
    if (error || !data) {
      setMsg({ ok: false, text: explainError(error?.message) });
    } else {
      setEnroll({ factorId: data.id, qr: data.totp.qr_code, secret: data.totp.secret });
      setCode("");
      setPhase("scan");
    }
    setBusy(false);
  }

  async function confirmEnable(e: React.FormEvent) {
    e.preventDefault();
    if (!enroll || busy) return;
    setBusy(true);
    setMsg(null);
    const { error } = await createClient().auth.mfa.challengeAndVerify({ factorId: enroll.factorId, code: code.trim() });
    if (error) {
      setMsg({ ok: false, text: explainError(error.message) });
    } else {
      setMsg({ ok: true, text: "Protection 2FA activée. Elle vous sera demandée à chaque connexion." });
      setEnroll(null);
      await refresh();
      router.refresh();
    }
    setBusy(false);
  }

  async function confirmDisable(e: React.FormEvent) {
    e.preventDefault();
    if (!factorId || busy) return;
    setBusy(true);
    setMsg(null);
    const auth = createClient().auth;
    const check = await auth.mfa.challengeAndVerify({ factorId, code: code.trim() });
    if (check.error) {
      setMsg({ ok: false, text: explainError(check.error.message) });
    } else {
      const { error } = await auth.mfa.unenroll({ factorId });
      if (error) setMsg({ ok: false, text: explainError(error.message) });
      else {
        setMsg({ ok: true, text: "Protection 2FA désactivée. Vous pouvez la réactiver quand vous voulez." });
        setCode("");
        await refresh();
        router.refresh();
      }
    }
    setBusy(false);
  }

  if (phase === "loading") return <p className="text-sm text-zinc-400" role="status">Chargement…</p>;

  return (
    <div className="space-y-4">
      {phase === "off" && (
        <>
          <p className="text-sm text-zinc-300">
            Facultatif, mais recommandé si vous vendez ou retirez de l&apos;argent : en plus du mot de passe, un code à 6 chiffres (qui change toutes les 30 secondes) est demandé à la connexion.
            Même si quelqu&apos;un vole votre mot de passe, il ne peut ni entrer dans votre compte ni retirer votre argent.
          </p>
          <button type="button" onClick={start} disabled={busy} className="btn-primary">{busy ? "…" : "Activer la protection 2FA"}</button>
        </>
      )}

      {phase === "scan" && enroll && (
        <form onSubmit={confirmEnable} className="space-y-4">
          <ol className="list-decimal space-y-1 pl-5 text-sm text-zinc-300">
            <li>Installez une application d&apos;authentification (Google Authenticator, Microsoft Authenticator ou Authy).</li>
            <li>Dans l&apos;application, choisissez « Ajouter un compte » puis scannez ce QR code.</li>
            <li>Saisissez ci-dessous le code à 6 chiffres affiché.</li>
          </ol>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={enroll.qr} alt="QR code à scanner avec votre application d'authentification" width={180} height={180} className="rounded-xl bg-white p-2" />
          <p className="text-xs text-zinc-400">Impossible de scanner ? Saisissez cette clé dans l&apos;application : <code className="break-all text-volt-soft">{enroll.secret}</code></p>
          <div>
            <label className="label" htmlFor="mfa-code">Code à 6 chiffres</label>
            <input id="mfa-code" className="input max-w-[12rem] tracking-widest" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} required />
          </div>
          <div className="flex gap-2">
            <button className="btn-primary" disabled={busy || code.length !== 6}>{busy ? "…" : "Confirmer et activer"}</button>
            <button type="button" className="btn-ghost" onClick={() => { setEnroll(null); setPhase("off"); setMsg(null); }}>Annuler</button>
          </div>
        </form>
      )}

      {phase === "on" && (
        <>
          <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">✓ Protection 2FA activée : un code vous est demandé à chaque connexion.</p>
          <button type="button" className="btn-ghost text-red-300" onClick={() => { setPhase("disable"); setCode(""); setMsg(null); }}>Désactiver la protection 2FA</button>
        </>
      )}

      {phase === "disable" && (
        <form onSubmit={confirmDisable} className="space-y-3">
          <p className="text-sm text-zinc-300">Pour désactiver, saisissez le code actuel de votre application.</p>
          <div>
            <label className="label" htmlFor="mfa-off">Code à 6 chiffres</label>
            <input id="mfa-off" className="input max-w-[12rem] tracking-widest" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} required />
          </div>
          <div className="flex gap-2">
            <button className="btn-primary" disabled={busy || code.length !== 6}>{busy ? "…" : "Désactiver"}</button>
            <button type="button" className="btn-ghost" onClick={() => { setPhase("on"); setMsg(null); }}>Annuler</button>
          </div>
        </form>
      )}

      {msg && <p role={msg.ok ? "status" : "alert"} className={`whitespace-pre-line text-sm ${msg.ok ? "text-jade-soft" : "text-red-300"}`}>{msg.text}</p>}
    </div>
  );
}
