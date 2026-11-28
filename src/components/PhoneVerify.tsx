"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { explainError } from "@/lib/errors";

/** Met un numéro au format international (+237…) : un numéro camerounais à 9 chiffres reçoit l'indicatif 237. */
export function toE164(raw: string): string {
  const digits = raw.replace(/[^\d+]/g, "");
  if (digits.startsWith("+")) return `+${digits.slice(1).replace(/\D/g, "")}`;
  const d = digits.replace(/\D/g, "");
  if (d.startsWith("00")) return `+${d.slice(2)}`;
  if (d.length === 9 && d.startsWith("6")) return `+237${d}`;
  return `+${d}`;
}

/**
 * Confirmation du numéro de téléphone par SMS (Supabase Auth). Le code est envoyé par SMS ; il faut un fournisseur SMS
 * configuré dans Supabase (Authentication > Providers > Phone), voir SECURITE-COMPTES.md.
 */
export default function PhoneVerify({ verified, phone }: { verified: boolean; phone: string | null }) {
  const router = useRouter();
  const [number, setNumber] = useState("");
  const [sentTo, setSentTo] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  if (verified) {
    return <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">✓ Numéro confirmé{phone ? ` : ${phone}` : ""}.</p>;
  }

  async function sendCode(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    const target = toE164(number);
    if (target.replace(/\D/g, "").length < 9) {
      setMsg({ ok: false, text: "Cause : le numéro est trop court.\nSolution : saisissez-le avec l'indicatif, par exemple +237 6 90 00 00 00." });
      return;
    }
    setBusy(true);
    setMsg(null);
    const { error } = await createClient().auth.updateUser({ phone: target });
    if (error) setMsg({ ok: false, text: explainError(error.message) });
    else {
      setSentTo(target);
      setMsg({ ok: true, text: `Un code vous a été envoyé par SMS au ${target}.` });
    }
    setBusy(false);
  }

  async function confirm(e: React.FormEvent) {
    e.preventDefault();
    if (busy || !sentTo) return;
    setBusy(true);
    setMsg(null);
    const { error } = await createClient().auth.verifyOtp({ phone: sentTo, token: code.trim(), type: "phone_change" });
    if (error) setMsg({ ok: false, text: explainError(error.message) });
    else {
      setMsg({ ok: true, text: "Numéro confirmé." });
      router.refresh();
    }
    setBusy(false);
  }

  return (
    <div className="space-y-4">
      {!sentTo ? (
        <form onSubmit={sendCode} className="space-y-3">
          <div>
            <label className="label" htmlFor="ph-number">Votre numéro de téléphone</label>
            <input id="ph-number" type="tel" className="input max-w-xs" inputMode="tel" autoComplete="tel" placeholder="+237 6 90 00 00 00" value={number} onChange={(e) => setNumber(e.target.value)} required />
          </div>
          <button className="btn-primary" disabled={busy}>{busy ? "…" : "Recevoir le code par SMS"}</button>
        </form>
      ) : (
        <form onSubmit={confirm} className="space-y-3">
          <div>
            <label className="label" htmlFor="ph-code">Code reçu par SMS</label>
            <input id="ph-code" className="input max-w-[12rem] tracking-widest" inputMode="numeric" autoComplete="one-time-code" maxLength={8} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} required />
          </div>
          <div className="flex gap-2">
            <button className="btn-primary" disabled={busy || code.length < 4}>{busy ? "…" : "Confirmer mon numéro"}</button>
            <button type="button" className="btn-ghost" onClick={() => { setSentTo(null); setCode(""); setMsg(null); }}>Changer de numéro</button>
          </div>
        </form>
      )}
      {msg && <p role={msg.ok ? "status" : "alert"} className={`whitespace-pre-line text-sm ${msg.ok ? "text-jade-soft" : "text-red-300"}`}>{msg.text}</p>}
    </div>
  );
}
