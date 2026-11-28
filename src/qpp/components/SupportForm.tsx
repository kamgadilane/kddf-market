"use client";
import { compressImage } from "@/lib/imageCompress";
import { useState } from "react";

const CATEGORIES: [string, string][] = [
  ["bug", "Bug / erreur sur le site"],
  ["paiement", "Paiement"],
  ["commande", "Commande / livraison"],
  ["compte", "Compte / connexion"],
  ["autre", "Autre"],
];

interface Props {
  defaultName: string;
  defaultEmail: string;
  defaultMessage: string;
}

/** Réduit une capture (max 1600 px, JPEG) pour qu'elle passe facilement même avec une connexion lente. */
export default function SupportForm({ defaultName, defaultEmail, defaultMessage }: Props) {
  const [name, setName] = useState(defaultName);
  const [email, setEmail] = useState(defaultEmail);
  const [category, setCategory] = useState("bug");
  const [message, setMessage] = useState(defaultMessage);
  const [files, setFiles] = useState<File[]>([]);
  const [error, setError] = useState("");
  const [done, setDone] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function addFiles(list: FileList | null): Promise<void> {
    if (!list) return;
    setError("");
    const next = [...files];
    for (const f of Array.from(list)) {
      if (next.length >= 3) {
        setError("Maximum 3 captures d'écran.");
        break;
      }
      if (!/^image\/(jpeg|png|webp)$/.test(f.type)) {
        setError("Seules les images JPG, PNG ou WebP sont acceptées.");
        continue;
      }
      try {
        next.push(await compressImage(f)); // 800 px / 200 Ko max
      } catch (err) {
        setError(err instanceof Error ? err.message : "Image illisible.");
      }
    }
    setFiles(next);
  }

  async function submit(e: React.FormEvent<HTMLFormElement>): Promise<void> {
    e.preventDefault();
    setError("");
    const total = files.reduce((s, f) => s + f.size, 0);
    if (total > 4.4 * 1024 * 1024) {
      setError("Les captures sont trop lourdes ensemble (4 Mo maximum).\nRetirez-en une ou choisissez des images plus légères.");
      return;
    }
    setLoading(true);
    try {
      const fd = new FormData(e.currentTarget); // inclut le champ piège "website" (caché, doit rester vide)
      fd.set("name", name);
      fd.set("email", email);
      fd.set("category", category);
      fd.set("message", message);
      fd.set("page", document.referrer.slice(0, 500)); // la page d'où vient la personne
      fd.delete("images");
      files.forEach((f) => fd.append("images", f));
      const res = await fetch("/api/support", { method: "POST", body: fd });
      const body: { ok?: boolean; ref?: string; error?: string; imagesSaved?: number; imagesSent?: number } = await res.json().catch(() => ({}));
      if (!res.ok || !body.ok) {
        setError(body.error ?? "Le message n'a pas pu être envoyé.\nVérifiez votre connexion et réessayez.");
        return;
      }
      const lost = (body.imagesSent ?? 0) - (body.imagesSaved ?? 0);
      setDone(`${body.ref ?? ""}${lost > 0 ? `|${lost}` : ""}`);
    } catch {
      setError("Le message n'a pas pu être envoyé.\nVérifiez votre connexion internet et réessayez.");
    } finally {
      setLoading(false);
    }
  }

  if (done !== null) {
    const [ref, lost] = done.split("|");
    return (
      <div className="glass space-y-2 p-6 text-center">
        <p className="text-4xl">✅</p>
        <h2 className="font-display text-xl font-bold text-white">Message envoyé, merci !</h2>
        <p className="text-sm text-zinc-300">Nous le lisons et vous répondons par email à <span className="text-white">{email}</span>.</p>
        {ref && <p className="font-mono text-xs text-zinc-500">Référence : {ref}</p>}
        {lost && <p className="text-xs text-amber-300">{lost} capture(s) n&apos;ont pas pu être enregistrées : renvoyez-les dans un second message si besoin.</p>}
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="glass space-y-4 p-5 sm:p-6">
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className="label" htmlFor="sp-name">Votre nom</label>
          <input id="sp-name" required maxLength={100} className="input" value={name} onChange={(e) => setName(e.target.value)} />
        </div>
        <div>
          <label className="label" htmlFor="sp-email">Votre email (pour vous répondre)</label>
          <input id="sp-email" type="email" required maxLength={254} className="input" value={email} onChange={(e) => setEmail(e.target.value)} />
        </div>
      </div>
      <div>
        <label className="label" htmlFor="sp-cat">Type de problème</label>
        <select id="sp-cat" className="input" value={category} onChange={(e) => setCategory(e.target.value)}>
          {CATEGORIES.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
        </select>
      </div>
      <div>
        <label className="label" htmlFor="sp-msg">Décrivez le problème</label>
        <textarea id="sp-msg" required minLength={10} maxLength={3000} rows={6} className="input" placeholder="Que faisiez-vous ? Que s'est-il passé ? Quel message d'erreur avez-vous vu ?" value={message} onChange={(e) => setMessage(e.target.value)} />
      </div>
      <div>
        <label className="label" htmlFor="sp-files">Captures d&apos;écran (facultatif, 3 maximum)</label>
        <input id="sp-files" type="file" accept="image/jpeg,image/png,image/webp" multiple className="input" onChange={(e) => { void addFiles(e.target.files); e.target.value = ""; }} />
        {files.length > 0 && (
          <ul className="mt-2 space-y-1 text-xs text-zinc-300">
            {files.map((f, i) => (
              <li key={`${f.name}-${i}`} className="flex items-center justify-between gap-2 rounded-lg bg-white/5 px-3 py-1.5">
                <span className="truncate">{f.name} · {(f.size / 1024).toFixed(0)} Ko</span>
                <button type="button" className="text-red-300 underline" onClick={() => setFiles(files.filter((_, j) => j !== i))}>Retirer</button>
              </li>
            ))}
          </ul>
        )}
      </div>
      {/* Champ piège anti-robot : caché pour les humains */}
      <div aria-hidden className="absolute left-[-9999px] h-0 w-0 overflow-hidden">
        <label>Ne pas remplir<input name="website" tabIndex={-1} autoComplete="off" /></label>
      </div>
      {error && <p role="alert" className="whitespace-pre-line rounded-xl bg-red-500/10 px-4 py-2.5 text-sm text-red-300">{error}</p>}
      <button className="btn-primary w-full" disabled={loading}>{loading ? "Envoi en cours…" : "Envoyer mon message"}</button>
    </form>
  );
}
