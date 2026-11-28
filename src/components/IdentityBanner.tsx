import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { asRow } from "@/lib/db";

interface Identity { status: "none" | "pending" | "approved" | "rejected" }

/** Bandeau de l'espace créateur : rappelle de faire vérifier son identité tant qu'elle ne l'est pas. Aucun affichage si c'est fait. */
export default async function IdentityBanner() {
  const supabase = createClient();
  const [{ data: idData }, { data: setData }] = await Promise.all([
    supabase.rpc("my_identity"),
    supabase.from("commission_settings").select("identity_required").eq("id", 1).maybeSingle(),
  ]);
  const required = asRow<{ identity_required: boolean }>(setData)?.identity_required ?? true;
  const status = asRow<Identity>(idData)?.status ?? "none";
  if (!required || status === "approved") return null;
  const text =
    status === "pending" ? "Vos documents d'identité sont en cours de vérification (24 à 48 h). Vous pouvez préparer vos produits en brouillon."
    : status === "rejected" ? "Vos documents d'identité ont été refusés. Cliquez pour voir le motif et les renvoyer."
    : "Vérifiez votre identité pour pouvoir publier vos produits (carte d'identité + selfie, 2 minutes).";
  return (
    <Link href="/dashboard/verification" className="block rounded-2xl border border-volt/30 bg-volt/10 px-4 py-3 text-sm text-volt-soft hover:bg-volt/15">
      🪪 {text} <span className="font-semibold underline">{status === "pending" ? "Voir l'état" : "Ouvrir"}</span>
    </Link>
  );
}
