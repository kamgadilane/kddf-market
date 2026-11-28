"use client";
import { useState } from "react";
import Link from "next/link";
import { explainError } from "@/lib/errors";
import { createClient } from "@/lib/supabase/client";

// Étape 1 : l'utilisateur saisit son email, Supabase lui envoie un lien vers /auth/callback -> /reset-password.
export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [msg, setMsg] = useState("");
  const [sent, setSent] = useState(false);
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setMsg("");
    const { error } = await createClient().auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/auth/callback?next=/reset-password`,
    });
    if (error) setMsg(explainError(error.message));
    else setSent(true); // même réponse que l'email existe ou non (on ne révèle pas les comptes)
    setLoading(false);
  }

  return (
    <form onSubmit={submit} className="glass mx-auto mt-12 max-w-md space-y-4 p-6 sm:p-8">
      <h1 className="font-display text-2xl font-bold text-white">Mot de passe oublié</h1>
      {sent ? (
        <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">
          Si un compte existe avec cet email, un lien de réinitialisation vient d&apos;être envoyé. Ouvrez-le <strong>dans ce même navigateur</strong> (pensez à vérifier les spams).
        </p>
      ) : (
        <>
          <p className="text-sm text-zinc-400">Saisissez l&apos;email de votre compte : nous vous envoyons un lien pour choisir un nouveau mot de passe.</p>
          <div>
            <label className="label" htmlFor="em">Email</label>
            <input id="em" type="email" autoComplete="email" className="input" value={email} onChange={(e) => setEmail(e.target.value)} required />
          </div>
          {msg && <p role="alert" className="whitespace-pre-line rounded-xl bg-white/5 px-4 py-2.5 text-sm text-zinc-300">{msg}</p>}
          <button className="btn-primary w-full" disabled={loading}>{loading ? "…" : "Envoyer le lien"}</button>
        </>
      )}
      <Link href="/login" className="block text-center text-xs text-zinc-400 hover:text-white">Retour à la connexion</Link>
    </form>
  );
}
