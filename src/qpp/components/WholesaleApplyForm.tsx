"use client";
import { compressImage } from "@/lib/imageCompress";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { explainError } from "@/lib/errors";

/** « Devenir Grossiste » : CNI + photo de la boutique + WhatsApp. Les fichiers vont dans un bucket PRIVÉ ; l'admin valide. */
export default function WholesaleApplyForm({ userId }: { userId: string }) {
  const [cni, setCni] = useState<File | null>(null);
  const [shop, setShop] = useState<File | null>(null);
  const [wa, setWa] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (busy || !cni || !shop) return;
    setBusy(true);
    setMsg(null);
    try {
      const supabase = createClient();
      const stamp = Date.now();
      const cniSmall = await compressImage(cni); // 800 px / 200 Ko max
      const shopSmall = await compressImage(shop);
      const cniPath = `${userId}/cni-${stamp}.jpg`;
      const shopPath = `${userId}/boutique-${stamp}.jpg`;
      const a = await supabase.storage.from("wholesale").upload(cniPath, cniSmall, { contentType: cniSmall.type });
      if (a.error) throw new Error("Envoi de la CNI impossible (image JPG/PNG de 5 Mo maximum).");
      const b = await supabase.storage.from("wholesale").upload(shopPath, shopSmall, { contentType: shopSmall.type });
      if (b.error) throw new Error("Envoi de la photo de la boutique impossible (image JPG/PNG de 5 Mo maximum).");
      const { error } = await supabase.rpc("wholesale_apply", { p_cni: cniPath, p_shop: shopPath, p_whatsapp: wa });
      if (error) throw new Error(error.message.includes("telephone_invalide") ? "Numéro WhatsApp invalide.\nSaisissez 8 à 15 chiffres, par exemple 6XXXXXXXX ou +2376XXXXXXXX." : explainError(error.message));
      setMsg({ ok: true, text: "Candidature envoyée. L'administrateur va la vérifier." });
    } catch (err) {
      setMsg({ ok: false, text: err instanceof Error ? err.message : "Erreur inattendue." });
    }
    setBusy(false);
  }

  return (
    <form onSubmit={submit} className="glass space-y-4 p-5">
      <p className="font-display text-lg font-bold text-white">Devenir Grossiste</p>
      <div>
        <label className="label" htmlFor="w-cni">Photo de votre CNI</label>
        <input id="w-cni" type="file" accept="image/jpeg,image/png" className="input" onChange={(e) => setCni(e.target.files?.[0] ?? null)} required />
      </div>
      <div>
        <label className="label" htmlFor="w-shop">Photo de votre boutique</label>
        <input id="w-shop" type="file" accept="image/jpeg,image/png" className="input" onChange={(e) => setShop(e.target.files?.[0] ?? null)} required />
      </div>
      <div>
        <label className="label" htmlFor="w-wa">Numéro WhatsApp</label>
        <input id="w-wa" className="input" inputMode="tel" placeholder="+237 6…" value={wa} onChange={(e) => setWa(e.target.value)} required />
      </div>
      <button className="btn-primary w-full" disabled={busy}>{busy ? "Envoi…" : "Envoyer ma candidature"}</button>
      {msg && <p role="status" className={`whitespace-pre-line text-sm ${msg.ok ? "text-jade-soft" : "text-red-300"}`}>{msg.text}</p>}
    </form>
  );
}
