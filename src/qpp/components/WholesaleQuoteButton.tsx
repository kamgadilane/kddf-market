"use client";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { quoteMessage, whatsappUrl } from "@/lib/wholesale";
import { t } from "@/lib/translations";

/** « Demander un devis grossiste » : enregistre la demande puis ouvre le WhatsApp du vendeur avec un message pré-rempli. */
export default function WholesaleQuoteButton({ productId, title, loggedIn }: { productId: string; title: string; loggedIn: boolean }) {
  const [qty, setQty] = useState(10);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function go() {
    if (!loggedIn) {
      window.location.href = `/login?next=${encodeURIComponent("/grossistes")}`;
      return;
    }
    if (busy) return;
    setBusy(true);
    setErr(null);
    const { data, error } = await createClient().rpc("wholesale_request", { p_product: productId, p_quantity: qty });
    setBusy(false);
    if (error) {
      setErr(error.message.includes("quantite_invalide") ? "Minimum 10 pièces." : error.message.includes("trop_de_demandes") ? "Trop de demandes aujourd'hui. Réessayez demain." : "Demande impossible pour le moment.");
      return;
    }
    const r = data as { whatsapp?: string | null; unit_price?: number } | null;
    if (!r?.whatsapp) {
      setErr("Ce vendeur n'a pas de numéro WhatsApp enregistré.");
      return;
    }
    window.open(whatsappUrl(r.whatsapp, quoteMessage(title, qty, Number(r.unit_price) || 0)), "_blank", "noopener,noreferrer");
  }

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        <label className="label !mb-0" htmlFor={`q-${productId}`}>Quantité</label>
        <input id={`q-${productId}`} type="number" min={10} max={100000} step={1} className="input !w-28 !py-2" value={qty} onChange={(e) => setQty(Math.max(0, Math.trunc(Number(e.target.value) || 0)))} />
      </div>
      <button type="button" className="btn-primary w-full" onClick={go} disabled={busy}>{busy ? "…" : t("wholesale.quote")}</button>
      {err && <p role="alert" className="text-xs text-red-300">{err}</p>}
    </div>
  );
}
