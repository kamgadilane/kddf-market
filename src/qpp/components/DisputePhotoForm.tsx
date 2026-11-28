"use client";
import { compressImage } from "@/lib/imageCompress";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

/** Ajoute une photo de preuve (colis avant envoi côté vendeur, produit reçu côté acheteur). Bucket privé « disputes ». */
export default function DisputePhotoForm({ orderId, label, mode = "dispute" }: { orderId: string; label: string; mode?: "dispute" | "order" }) {
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!file || busy) return;
    setBusy(true);
    setMsg(null);
    const supabase = createClient();
    let small: File;
    try {
      small = await compressImage(file); // 800 px / 200 Ko max
    } catch (err) {
      setBusy(false);
      setMsg({ ok: false, text: err instanceof Error ? err.message : "Image illisible." });
      return;
    }
    const path = `${orderId}/${Date.now()}.jpg`;
    const up = await supabase.storage.from("disputes").upload(path, small, { contentType: small.type });
    if (up.error) {
      setBusy(false);
      setMsg({ ok: false, text: "Envoi impossible (image JPG/PNG de 4 Mo maximum)." });
      return;
    }
    // mode "order" : photo du colis avant envoi (vendeur) / du produit reçu (acheteur), sans litige ; mode "dispute" : preuve d'un litige ouvert
    const { error } = await supabase.rpc(mode === "order" ? "order_add_photo" : "dispute_attach_photo", { p_order: orderId, p_path: path });
    setBusy(false);
    setMsg(error ? { ok: false, text: "Photo non enregistrée." } : { ok: true, text: "Photo enregistrée. Merci." });
  }

  return (
    <form onSubmit={submit} className="space-y-3">
      <label className="label" htmlFor={`dp-${orderId}`}>{label}</label>
      <input id={`dp-${orderId}`} type="file" accept="image/jpeg,image/png" capture="environment" className="input" onChange={(e) => setFile(e.target.files?.[0] ?? null)} required />
      <button className="btn-primary" disabled={busy}>{busy ? "Envoi…" : "Envoyer la photo"}</button>
      {msg && <p role="status" className={`text-sm ${msg.ok ? "text-jade-soft" : "text-red-300"}`}>{msg.text}</p>}
    </form>
  );
}
