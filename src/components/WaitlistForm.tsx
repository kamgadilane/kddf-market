"use client";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { t } from "@/lib/translations";

/** Inscription à la liste d'attente d'un pays (table waitlist_international, via la fonction sécurisée join_waitlist). */
export default function WaitlistForm({ country, countryName, onDone }: { country: string; countryName: string; onDone?: () => void }) {
  const [phone, setPhone] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setMsg(null);
    const { data, error } = await createClient().rpc("join_waitlist", { p_country: country, p_phone: phone });
    setBusy(false);
    if (error) {
      setMsg({ ok: false, text: error.message.includes("telephone_invalide") ? "Numéro invalide. Exemple : +241 06 12 34 56" : "Impossible d'enregistrer pour le moment. Réessaie dans un instant." });
      return;
    }
    setMsg({ ok: true, text: t("country.thanks", { n: Number(data) || 1 }) });
    setPhone("");
    onDone?.();
  }

  return (
    <form onSubmit={submit} className="space-y-3">
      <label className="label" htmlFor={`wl-${country}`}>WhatsApp ({countryName})</label>
      <input id={`wl-${country}`} className="input" inputMode="tel" autoComplete="tel" placeholder="+241 …" value={phone} onChange={(e) => setPhone(e.target.value)} required />
      <button className="btn-primary w-full" disabled={busy}>{busy ? "Envoi…" : t("country.send")}</button>
      {msg && <p role="status" className={`text-sm ${msg.ok ? "text-jade-soft" : "text-red-300"}`}>{msg.text}</p>}
    </form>
  );
}
