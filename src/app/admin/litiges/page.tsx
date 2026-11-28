import FlashError from "@/components/FlashError";
import AutoRefresh from "@/components/AutoRefresh";
import { createClient } from "@/lib/supabase/server";
import { asRows } from "@/lib/db";
import { formatFcfa } from "@/lib/money";
import { whatsappLink } from "@/lib/phone";
import { decideDispute } from "./actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Admin · Litiges", robots: { index: false } };

/** Preuve de paiement Mobile Money (sans compte : Numéro + montant + identifiant Fapshi). */
interface PaymentProof {
  order_code: string | null;
  total_amount: number;
  fapshi_trans_id: string | null;
  fapshi_medium: string | null;
  paid_at: string | null;
}

interface Dispute {
  id: string;
  order_id: string;
  buyer_id: string | null;
  seller_id: string | null;
  reason: string;
  photo_buyer: string | null;
  photo_seller: string | null;
  buyer_photos: string[] | null;
  buyer_name: string | null;
  buyer_phone: string | null;
  order_code: string | null;
  status: "en_attente" | "remboursé" | "refusé";
  created_at: string;
  resolved_at: string | null;
  order: { total_price: number; buyer_email: string; phone: string | null; transactions: PaymentProof | PaymentProof[] | null } | null;
  buyer: { full_name: string | null; store_name: string | null } | null;
  seller: { full_name: string | null; store_name: string | null; whatsapp: string | null } | null;
}

/** Liens temporaires (10 min) pour toutes les photos en UNE seule requête de stockage. */
async function signedMap(paths: string[]): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  if (paths.length === 0) return map;
  const { data } = await createClient().storage.from("disputes").createSignedUrls(paths, 600);
  for (const row of data ?? []) if (row.path && row.signedUrl) map.set(row.path, row.signedUrl);
  return map;
}

export default async function AdminDisputes({ searchParams }: { searchParams: { erreur?: string } }) {
  // UNE requête de données : litiges + commande + acheteur + vendeur (jointures)
  const supabase = createClient();
  const list = asRows<Dispute>(
    (
      await supabase
        .from("disputes")
        .select("id, order_id, buyer_id, seller_id, reason, photo_buyer, photo_seller, buyer_photos, buyer_name, buyer_phone, order_code, status, created_at, resolved_at, order:orders!order_id(total_price, buyer_email, phone, transactions(order_code, total_amount, fapshi_trans_id, fapshi_medium, paid_at)), buyer:profiles!buyer_id(full_name, store_name), seller:profiles!seller_id(full_name, store_name, whatsapp)")
        .order("created_at", { ascending: false })
        .limit(100)
    ).data
  );
  const signed = await signedMap(list.flatMap((d) => [d.photo_buyer, d.photo_seller, ...(d.buyer_photos ?? [])]).filter((x): x is string => x !== null));
  const open = list.filter((d) => d.status === "en_attente");

  return (
    <div className="space-y-6">
      <FlashError code={searchParams.erreur} />
      <AutoRefresh seconds={30} />
      <h1 className="font-display text-3xl font-bold text-white">Litiges ({open.length} en attente)</h1>
      {list.length === 0 ? (
        <p className="glass p-8 text-center text-sm text-zinc-400">Aucun litige.</p>
      ) : (
        <ul className="space-y-4">
          {list.map((d) => {
            const o = d.order;
            const ph = { buyer: d.photo_buyer ? signed.get(d.photo_buyer) ?? null : null, seller: d.photo_seller ? signed.get(d.photo_seller) ?? null : null };
            const proof = Array.isArray(o?.transactions) ? o?.transactions[0] ?? null : o?.transactions ?? null;
            const guestName = d.buyer_name ?? "";
            const isGuest = d.buyer_id === null;
            const buyerName = isGuest ? guestName || "Client sans compte" : d.buyer?.full_name ?? d.buyer?.store_name ?? "—";
            const buyerPhone = d.buyer_phone ?? o?.phone ?? null;
            const code = d.order_code ?? proof?.order_code ?? null;
            const buyerPhotos = (d.buyer_photos ?? []).map((p) => signed.get(p)).filter((u): u is string => typeof u === "string");
            const sellerName = d.seller?.store_name ?? d.seller?.full_name ?? "—";
            return (
              <li key={d.id} className="glass space-y-3 p-5 text-sm text-zinc-200">
                <p className="flex flex-wrap justify-between gap-2">
                  <span className="font-semibold text-white">Acheteur : {buyerName} · Vendeur : {sellerName}</span>
                  <span className="text-xs text-zinc-500">{new Date(d.created_at).toLocaleString("fr-FR")}</span>
                </p>
                <p>Montant : {o ? formatFcfa(o.total_price) : "—"} · Motif : {d.reason}</p>
                {isGuest && (
                  <div className="rounded-xl border border-white/10 bg-white/[0.03] p-3 text-xs">
                    <p className="font-semibold text-white">Client sans compte : Nom + Numéro + Code</p>
                    <p>Nom : {guestName || "—"} · Numéro : {buyerPhone ?? "—"} · Code : <span className="font-mono">{code ?? "—"}</span></p>
                    <p className="mt-1 text-zinc-400">
                      Preuve de paiement Mobile Money : numéro déclaré {buyerPhone ?? "—"} · montant {proof ? formatFcfa(proof.total_amount) : "—"} · ID Fapshi {proof?.fapshi_trans_id ?? "—"}
                      {proof?.fapshi_medium ? ` · ${proof.fapshi_medium}` : ""}{proof?.paid_at ? ` · payé le ${new Date(proof.paid_at).toLocaleString("fr-FR")}` : ""}
                    </p>
                  </div>
                )}
                <div className="flex flex-wrap gap-3 text-xs">
                  {buyerPhotos.length > 0
                    ? buyerPhotos.map((u, i) => <a key={u} href={u} target="_blank" rel="noopener noreferrer" className="text-volt-soft underline">Photo de l&apos;acheteur {buyerPhotos.length > 1 ? i + 1 : ""}</a>)
                    : ph?.buyer ? <a href={ph.buyer} target="_blank" rel="noopener noreferrer" className="text-volt-soft underline">Photo de l&apos;acheteur</a> : <span className="text-zinc-500">Pas de photo acheteur</span>}
                  {ph?.seller ? <a href={ph.seller} target="_blank" rel="noopener noreferrer" className="text-volt-soft underline">Photo du vendeur</a> : <span className="text-zinc-500">Pas de photo vendeur</span>}
                </div>
                <div className="flex flex-wrap gap-2 text-xs">
                  <span className="text-zinc-500">💬 Envoyer WhatsApp manuel :</span>
                  {d.seller?.whatsapp ? <a className="btn-ghost !px-3 !py-1.5" target="_blank" rel="noopener noreferrer" href={whatsappLink(d.seller.whatsapp, `Bonjour ${sellerName}, un litige est ouvert sur une de vos ventes KDDF Market (motif : ${d.reason}). Merci d'envoyer la photo du colis AVANT envoi.`)}>Au vendeur</a> : <span className="text-zinc-500">vendeur sans WhatsApp</span>}
                  {buyerPhone ? <a className="btn-ghost !px-3 !py-1.5" target="_blank" rel="noopener noreferrer" href={whatsappLink(buyerPhone, `Bonjour ${buyerName}, nous traitons votre litige KDDF Market. Merci d'envoyer la photo du produit APRÈS réception.`)}>À l&apos;acheteur</a> : <span className="text-zinc-500">acheteur sans téléphone</span>}
                </div>
                {d.status === "en_attente" ? (
                  <div className="flex flex-wrap gap-2">
                    <form action={decideDispute}>
                      <input type="hidden" name="id" value={d.id} />
                      <input type="hidden" name="decision" value="refund" />
                      <button className="btn-jade !px-3 !py-2">Rembourser l&apos;acheteur</button>
                    </form>
                    <form action={decideDispute}>
                      <input type="hidden" name="id" value={d.id} />
                      <input type="hidden" name="decision" value="reject" />
                      <button className="btn-ghost !px-3 !py-2 text-red-300">Refuser le litige</button>
                    </form>
                  </div>
                ) : (
                  <p className="text-xs font-semibold text-zinc-400">Décision : {d.status}</p>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
