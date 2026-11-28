import Link from "next/link";
import { redirect } from "next/navigation";
import IdentityForm from "@/components/IdentityForm";
import { getSessionUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { asRow } from "@/lib/db";

export const dynamic = "force-dynamic";
export const metadata = { title: "Vérification d'identité", robots: { index: false } };

interface Identity { status: "none" | "pending" | "approved" | "rejected"; reason: string | null; legacy: boolean }

export default async function VerificationPage() {
  const user = await getSessionUser();
  if (!user) redirect("/login?next=/dashboard/verification");
  const { data } = await createClient().rpc("my_identity");
  const id = asRow<Identity>(data) ?? { status: "none", reason: null, legacy: false };

  return (
    <div className="mx-auto max-w-xl space-y-5">
      <h1 className="font-display text-3xl font-bold text-white">Vérification d&apos;identité</h1>
      <p className="text-sm text-zinc-400">
        Pour protéger les acheteurs contre les vendeurs malhonnêtes, chaque vendeur est vérifié par l&apos;administrateur avant de publier ses produits.
        Vous pouvez préparer vos produits en brouillon pendant ce temps.
      </p>

      {id.status === "approved" && (
        <div role="status" className="glass space-y-2 p-5">
          <p className="font-display text-lg font-bold text-jade-soft">✓ Identité vérifiée</p>
          <p className="text-sm text-zinc-300">{id.legacy ? "Votre compte était déjà actif : il est reconnu automatiquement." : "Votre identité a été validée."} Vous pouvez publier vos produits.</p>
          <Link href="/dashboard/products" className="btn-primary inline-block">Mon catalogue</Link>
        </div>
      )}
      {id.status === "pending" && (
        <div role="status" className="glass space-y-2 p-5">
          <p className="font-display text-lg font-bold text-white">⏳ En cours de vérification</p>
          <p className="text-sm text-zinc-300">Vos documents ont bien été reçus. Réponse sous 24 à 48 h : vous serez prévenu dans la cloche 🔔.</p>
        </div>
      )}
      {id.status === "rejected" && (
        <div role="alert" className="space-y-2 rounded-2xl bg-red-500/10 p-5">
          <p className="font-display text-lg font-bold text-red-200">Documents refusés</p>
          <p className="text-sm text-red-100">Motif : {id.reason ?? "non précisé"}</p>
          <p className="text-sm text-zinc-300">Corrigez le problème puis renvoyez vos documents ci-dessous.</p>
        </div>
      )}
      {(id.status === "none" || id.status === "rejected") && <IdentityForm userId={user.id} />}
      <p className="text-xs text-zinc-500">Besoin d&apos;aide ? <Link href="/support" className="underline">Contacter le service client</Link>.</p>
    </div>
  );
}
