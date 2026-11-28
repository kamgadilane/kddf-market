import Link from "next/link";
import { redirect } from "next/navigation";
import PhoneVerify from "@/components/PhoneVerify";
import TwoFactorSetup from "@/components/TwoFactorSetup";
import { getSessionUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { asRow } from "@/lib/db";

export const dynamic = "force-dynamic";
export const metadata = { title: "Sécurité du compte", robots: { index: false } };

interface Identity { status: "none" | "pending" | "approved" | "rejected" }
interface Phone { verified: boolean; phone: string | null }

const IDENTITY_LABEL: Record<Identity["status"], string> = {
  none: "Non envoyée",
  pending: "En cours de vérification",
  approved: "Vérifiée ✓",
  rejected: "Refusée : à renvoyer",
};

export default async function SecurityPage() {
  const user = await getSessionUser();
  if (!user) redirect("/login?next=/securite");
  const supabase = createClient();
  const [{ data: idData }, { data: phData }] = await Promise.all([supabase.rpc("my_identity"), supabase.rpc("my_phone")]);
  const identity = asRow<Identity>(idData)?.status ?? "none";
  const phone = asRow<Phone>(phData) ?? { verified: false, phone: null };

  return (
    <div className="mx-auto max-w-xl space-y-6">
      <div>
        <h1 className="font-display text-3xl font-bold text-white">Sécurité du compte</h1>
        <p className="mt-1 text-sm text-zinc-400">Trois protections pour vous et vos acheteurs. Seule la vérification d&apos;identité est demandée aux vendeurs ; les deux autres sont facultatives.</p>
      </div>

      <section className="glass space-y-3 p-5" aria-labelledby="sec-id">
        <h2 id="sec-id" className="font-display text-lg font-bold text-white">🪪 Vérification d&apos;identité (vendeurs)</h2>
        <p className="text-sm text-zinc-300">État : <strong>{IDENTITY_LABEL[identity]}</strong></p>
        <p className="text-sm text-zinc-400">Carte d&apos;identité (recto, verso) et vidéo ou photo de vous avec votre carte, contrôlées par l&apos;administrateur avant de publier des produits.</p>
        {identity !== "approved" && <Link href="/dashboard/verification" className="btn-primary inline-block">{identity === "pending" ? "Voir l'état" : "Vérifier mon identité"}</Link>}
      </section>

      <section className="glass space-y-3 p-5" aria-labelledby="sec-phone">
        <h2 id="sec-phone" className="font-display text-lg font-bold text-white">📱 Numéro de téléphone</h2>
        <p className="text-sm text-zinc-400">Confirmé par un code reçu par SMS. Cela rassure les acheteurs et permet de vous contacter.</p>
        <PhoneVerify verified={phone.verified} phone={phone.phone} />
      </section>

      <section className="glass space-y-3 p-5" aria-labelledby="sec-2fa">
        <h2 id="sec-2fa" className="font-display text-lg font-bold text-white">🔐 Protection 2FA (facultative)</h2>
        <TwoFactorSetup />
      </section>

      <p className="text-xs text-zinc-500">Un problème ? <Link href="/support" className="underline">Contacter le service client</Link>.</p>
    </div>
  );
}
