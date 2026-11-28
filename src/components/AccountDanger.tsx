"use client";
import { useState } from "react";

/** Données personnelles : téléchargement (export) et suppression du compte (avec confirmation en tapant SUPPRIMER). */
export default function AccountDanger() {
  const [open, setOpen] = useState(false);
  const [word, setWord] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function remove(e: React.FormEvent): Promise<void> {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const res = await fetch("/api/account/delete", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ confirm: word.trim() }) });
      const json: unknown = await res.json().catch(() => null);
      const msg = json !== null && typeof json === "object" ? (json as { error?: unknown }).error : null;
      if (res.ok) {
        window.location.href = "/?compte=supprime";
        return;
      }
      setError(typeof msg === "string" ? msg : "La suppression a échoué. Réessayez dans un instant.");
    } catch {
      setError("Connexion impossible. Vérifiez votre réseau puis réessayez.");
    }
    setLoading(false);
  }

  return (
    <section className="glass space-y-4 p-5">
      <h2 className="font-display text-xl font-bold text-white">Mes données et mon compte</h2>
      <div className="space-y-2">
        <p className="text-sm text-zinc-400">Téléchargez une copie de vos données (profil, produits, achats, ventes, retraits) au format JSON.</p>
        <a href="/api/account/export" className="btn-ghost inline-flex !py-2" download>Télécharger mes données</a>
      </div>
      <div className="space-y-2 border-t border-white/5 pt-4">
        <p className="text-sm text-zinc-400">
          Supprimer mon compte : votre profil est anonymisé, vos produits sont retirés et vous ne pouvez plus vous connecter. Conditions : portefeuille vide, aucun retrait, litige ou commande physique en cours.
          Les ventes et retraits déjà réalisés sont conservés sans votre nom, comme la loi l&apos;exige pour la comptabilité.
        </p>
        {!open ? (
          <button type="button" className="btn-ghost !py-2 text-red-300" onClick={() => setOpen(true)}>Supprimer mon compte…</button>
        ) : (
          <form onSubmit={remove} className="space-y-3 rounded-xl border border-red-500/30 bg-red-500/5 p-4">
            <p className="text-sm text-red-200">Cette action est définitive. Pour confirmer, tapez le mot <strong>SUPPRIMER</strong>.</p>
            <label className="label" htmlFor="del-word">Confirmation</label>
            <input id="del-word" className="input" autoComplete="off" value={word} onChange={(e) => setWord(e.target.value)} />
            {error && <p role="alert" className="whitespace-pre-line text-sm text-red-300">{error}</p>}
            <div className="flex flex-wrap gap-2">
              <button className="btn-primary !bg-red-600 !py-2" disabled={loading || word.trim() !== "SUPPRIMER"}>{loading ? "Patientez…" : "Supprimer définitivement"}</button>
              <button type="button" className="btn-ghost !py-2" onClick={() => { setOpen(false); setWord(""); setError(""); }}>Annuler</button>
            </div>
          </form>
        )}
      </div>
    </section>
  );
}
