"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { explainError } from "@/lib/errors";
import { createClient } from "@/lib/supabase/client";

// Étape 2 : après le clic sur le lien reçu par email, /auth/callback ouvre une session, puis l'utilisateur choisit son nouveau mot de passe.
export default function ResetPasswordPage() {
  const router = useRouter();
  const [ready, setReady] = useState<"loading" | "ok" | "none">("loading");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [msg, setMsg] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    createClient()
      .auth.getUser()
      .then(({ data }) => setReady(data.user ? "ok" : "none"))
      .catch(() => setReady("none"));
  }, []);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (password !== confirm) {
      setMsg("Les deux mots de passe ne sont pas identiques. Retapez-les avec attention.");
      return;
    }
    setLoading(true);
    setMsg("");
    const { error } = await createClient().auth.updateUser({ password });
    if (error) {
      setMsg(explainError(error.message));
      setLoading(false);
      return;
    }
    router.push("/dashboard");
    router.refresh();
  }

  if (ready === "loading") return <p className="mt-16 text-center text-sm text-zinc-400">Chargement…</p>;
  if (ready === "none") {
    return (
      <div className="glass mx-auto mt-12 max-w-md space-y-3 p-6 text-center sm:p-8">
        <h1 className="font-display text-2xl font-bold text-white">Lien expiré</h1>
        <p className="text-sm text-zinc-400">Ce lien n&apos;est plus valable (expiré, déjà utilisé, ou ouvert dans un autre navigateur).</p>
        <Link href="/mot-de-passe-oublie" className="btn-primary">Demander un nouveau lien</Link>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="glass mx-auto mt-12 max-w-md space-y-4 p-6 sm:p-8">
      <h1 className="font-display text-2xl font-bold text-white">Nouveau mot de passe</h1>
      <div>
        <label className="label" htmlFor="pw">Nouveau mot de passe (8 caractères minimum)</label>
        <input id="pw" type="password" autoComplete="new-password" minLength={8} className="input" value={password} onChange={(e) => setPassword(e.target.value)} required />
      </div>
      <div>
        <label className="label" htmlFor="pw2">Confirmer le mot de passe</label>
        <input id="pw2" type="password" autoComplete="new-password" minLength={8} className="input" value={confirm} onChange={(e) => setConfirm(e.target.value)} required />
      </div>
      {msg && <p role="alert" className="whitespace-pre-line rounded-xl bg-white/5 px-4 py-2.5 text-sm text-zinc-300">{msg}</p>}
      <button className="btn-primary w-full" disabled={loading}>{loading ? "…" : "Enregistrer"}</button>
    </form>
  );
}
