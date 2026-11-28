import Link from "next/link";
import { notFound } from "next/navigation";
import DisputePhotoForm from "@/components/DisputePhotoForm";
import GuaranteeBadge from "@/components/GuaranteeBadge";
import { getSessionUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { asRow } from "@/lib/db";
import { isUuid } from "@/lib/validate";

export const dynamic = "force-dynamic";
export const metadata = { title: "Mon litige", robots: { index: false } };

interface Dispute {
  id: string;
  buyer_id: string | null;
  seller_id: string | null;
  reason: string;
  photo_buyer: string | null;
  photo_seller: string | null;
  status: "en_attente" | "remboursé" | "refusé";
  created_at: string;
}

const STATUS: Record<Dispute["status"], string> = {
  en_attente: "En attente de décision",
  remboursé: "Remboursé",
  refusé: "Refusé (la commande est maintenue)",
};

/** Suivi d'un litige et envoi de photos de preuve (acheteur : produit reçu · vendeur : colis avant envoi). */
export default async function DisputePage({ params }: { params: { orderId: string } }) {
  if (!isUuid(params.orderId)) notFound();
  const user = await getSessionUser();
  if (!user) notFound();
  const supabase = createClient();
  // La règle RLS ne montre le litige qu'à l'acheteur, au vendeur et à l'admin.
  const d = asRow<Dispute>((await supabase.from("disputes").select("id, buyer_id, seller_id, reason, photo_buyer, photo_seller, status, created_at").eq("order_id", params.orderId).order("created_at", { ascending: false }).limit(1).maybeSingle()).data);
  if (!d) notFound();
  const isBuyer = d.buyer_id === user.id;
  const isSeller = d.seller_id === user.id;

  return (
    <div className="mx-auto max-w-xl space-y-5">
      <h1 className="font-display text-3xl font-bold text-white">Litige</h1>
      <section className="glass space-y-2 p-5 text-sm text-zinc-200">
        <p>Statut : <strong className="text-white">{STATUS[d.status]}</strong></p>
        <p>Motif : {d.reason}</p>
        <p className="text-xs text-zinc-400">Photo de l&apos;acheteur : {d.photo_buyer ? "reçue" : "pas encore"} · Photo du vendeur : {d.photo_seller ? "reçue" : "pas encore"}</p>
      </section>
      {d.status === "en_attente" && (isBuyer || isSeller) && (
        <section className="glass p-5">
          <DisputePhotoForm orderId={params.orderId} label={isBuyer ? "Photo du produit reçu" : "Photo du colis avant envoi"} />
        </section>
      )}
      <GuaranteeBadge />
      <Link href="/library" className="btn-ghost inline-flex">← Retour</Link>
    </div>
  );
}
