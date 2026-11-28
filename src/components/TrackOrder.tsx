"use client";
import { useState } from "react";
import { compressImage } from "@/lib/imageCompress";
import { MAX_DISPUTE_PHOTOS, TRACK_STEPS, trackHint, trackStepIndex, type TrackedOrder } from "@/lib/guest";

const fcfa = (n: number): string => `${new Intl.NumberFormat("fr-FR").format(n)} FCFA`;

/** Suivi public d'une commande physique (Numéro + Code), réception et litige avec photos. Aucun compte requis. */
export default function TrackOrder({ defaultCode }: { defaultCode: string }) {
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState(defaultCode);
  const [order, setOrder] = useState<TrackedOrder | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [info, setInfo] = useState("");
  const [showDispute, setShowDispute] = useState(false);
  const [reason, setReason] = useState("");
  const [files, setFiles] = useState<File[]>([]);

  async function call(url: string, body: BodyInit, json: boolean): Promise<{ ok: boolean; order?: TrackedOrder; error?: string }> {
    const res = await fetch(url, { method: "POST", body, headers: json ? { "Content-Type": "application/json" } : undefined });
    const data = (await res.json().catch(() => ({}))) as { order?: TrackedOrder; error?: string };
    return { ok: res.ok, order: data.order, error: data.error };
  }

  async function search(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError("");
    setInfo("");
    setOrder(null);
    try {
      const r = await call("/api/suivre-commande", JSON.stringify({ phone, code }), true);
      if (r.ok && r.order) setOrder(r.order);
      else setError(r.error ?? "Commande introuvable.");
    } catch {
      setError("Connexion impossible. Vérifiez votre réseau puis réessayez.");
    }
    setBusy(false);
  }

  async function confirm() {
    if (busy || !order) return;
    setBusy(true);
    setError("");
    setInfo("");
    try {
      const r = await call("/api/suivre-commande/confirmer", JSON.stringify({ phone, code }), true);
      if (r.ok) {
        if (r.order) setOrder(r.order);
        setInfo("Merci ! Votre réception est confirmée.");
      } else setError(r.error ?? "Confirmation impossible.");
    } catch {
      setError("Connexion impossible. Réessayez.");
    }
    setBusy(false);
  }

  async function addFiles(list: FileList | null) {
    setError("");
    const picked = Array.from(list ?? []).slice(0, MAX_DISPUTE_PHOTOS);
    try {
      setFiles(await Promise.all(picked.map((f) => compressImage(f))));
    } catch (err) {
      setFiles([]);
      setError(err instanceof Error ? err.message : "Image illisible.");
    }
  }

  async function openDispute(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError("");
    setInfo("");
    try {
      const fd = new FormData();
      fd.set("phone", phone);
      fd.set("code", code);
      fd.set("reason", reason);
      files.forEach((f) => fd.append("photos", f));
      const r = await call("/api/suivre-commande/litige", fd, false);
      if (r.ok) {
        if (r.order) setOrder(r.order);
        setShowDispute(false);
        setInfo("Litige ouvert. Notre équipe l'examine et vous recontacte sur votre numéro.");
      } else setError(r.error ?? "Litige non enregistré.");
    } catch {
      setError("Connexion impossible. Réessayez.");
    }
    setBusy(false);
  }

  const step = order ? trackStepIndex(order) : 0;

  return (
    <div className="space-y-5">
      <form onSubmit={search} className="glass space-y-4 p-5">
        <div>
          <label className="label" htmlFor="trk-phone">Numéro utilisé pour commander</label>
          <input id="trk-phone" className="input" type="tel" inputMode="tel" autoComplete="tel" placeholder="6XX XX XX XX" value={phone} onChange={(e) => setPhone(e.target.value)} required />
        </div>
        <div>
          <label className="label" htmlFor="trk-code">Code de commande</label>
          <input id="trk-code" className="input font-mono uppercase" placeholder="KDDF-8421" value={code} onChange={(e) => setCode(e.target.value)} maxLength={12} required />
        </div>
        <button className="btn-primary w-full" disabled={busy}>{busy && !order ? "Recherche…" : "Suivre ma commande"}</button>
      </form>

      {error && <p role="alert" className="whitespace-pre-line rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-200">{error}</p>}
      {info && <p role="status" className="rounded-xl border border-jade/30 bg-jade/10 px-4 py-3 text-sm text-jade-soft">{info}</p>}

      {order && (
        <section className="glass space-y-5 p-5" aria-live="polite">
          <header className="space-y-1">
            <p className="font-mono text-sm text-volt-soft">{order.order_code}</p>
            <h2 className="font-display text-xl font-bold text-white">{order.product_title}</h2>
            <p className="text-sm text-zinc-400">
              {order.customer_name ? `${order.customer_name} · ` : ""}Quantité {order.quantity} · {fcfa(order.total_price)}
            </p>
            {order.delivery_address && <p className="text-xs text-zinc-500">Livraison : {order.delivery_address}</p>}
          </header>

          {order.status === "cancelled" ? (
            <p className="text-sm text-red-300">{trackHint(order)}</p>
          ) : (
            <ol className="grid grid-cols-4 gap-2 text-center text-[11px]" aria-label="Avancement de la commande">
              {TRACK_STEPS.map((label, i) => (
                <li key={label} className="space-y-1.5" aria-current={i === step ? "step" : undefined}>
                  <div className={`h-1.5 rounded-full ${i < step ? "bg-jade" : i === step ? "bg-volt" : "bg-white/10"}`} />
                  <span className={i < step ? "text-jade-soft" : i === step ? "font-semibold text-white" : "text-zinc-500"}>{i < step ? "✓ " : ""}{label}</span>
                </li>
              ))}
            </ol>
          )}

          <p className="text-sm text-zinc-300">{trackHint(order)}</p>
          {order.disputed && (
            <p className="rounded-xl border border-amber-400/30 bg-amber-400/10 px-4 py-3 text-sm text-amber-200">
              ⚖️ Litige {order.dispute_status === "en_attente" ? "en cours d'examen" : "traité"}. Les fonds du vendeur restent bloqués tant qu&apos;il n&apos;est pas résolu.
            </p>
          )}

          <div className="flex flex-col gap-3 sm:flex-row">
            {order.can_confirm && <button type="button" className="btn-jade flex-1" onClick={confirm} disabled={busy}>✅ J&apos;ai bien reçu ma commande</button>}
            {order.can_dispute && !showDispute && <button type="button" className="btn-ghost flex-1" onClick={() => setShowDispute(true)}>⚖️ Ouvrir un litige</button>}
          </div>

          {showDispute && (
            <form onSubmit={openDispute} className="space-y-3 border-t border-white/10 pt-4">
              <p className="text-xs text-zinc-400">🛡️ Garantie 7 jours : décrivez le problème et ajoutez jusqu&apos;à {MAX_DISPUTE_PHOTOS} photos.</p>
              <div>
                <label className="label" htmlFor="trk-reason">Que s&apos;est-il passé ?</label>
                <textarea id="trk-reason" className="input min-h-[96px]" value={reason} onChange={(e) => setReason(e.target.value)} minLength={5} maxLength={500} required />
              </div>
              <div>
                <label className="label" htmlFor="trk-photos">Photos (facultatif)</label>
                <input id="trk-photos" className="input" type="file" accept="image/jpeg,image/png,image/webp" multiple onChange={(e) => void addFiles(e.target.files)} />
                {files.length > 0 && <p className="mt-1 text-xs text-zinc-500">{files.length} photo(s) prête(s).</p>}
              </div>
              <div className="flex gap-3">
                <button className="btn-primary flex-1" disabled={busy}>{busy ? "Envoi…" : "Envoyer le litige"}</button>
                <button type="button" className="btn-ghost" onClick={() => setShowDispute(false)}>Annuler</button>
              </div>
            </form>
          )}
        </section>
      )}
    </div>
  );
}
