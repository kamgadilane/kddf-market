import { notFound } from "next/navigation";
import Link from "next/link";
import CheckoutForm from "@/components/CheckoutForm";
import GuaranteeBadge from "@/components/GuaranteeBadge";
import WholesaleQuoteButton from "@/components/WholesaleQuoteButton";
import { createClient } from "@/lib/supabase/server";
import { asRow } from "@/lib/db";
import { formatFcfa } from "@/lib/money";
import { isUuid } from "@/lib/validate";
import { enabledProviders } from "@/lib/payments";
import { getServiceFeeRules } from "@/lib/serviceFeeServer";
import { t } from "@/lib/translations";
import type { DeliveryOptions } from "@/lib/types";

export const dynamic = "force-dynamic";
export const metadata = { title: "Commander en gros" };

interface Offer {
  product_id: string;
  seller_id: string;
  min_quantity_10_price: number;
  min_quantity_50_price: number;
  stock_wholesale: number;
  city: string | null;
  product: {
    id: string;
    title: string;
    price: number;
    stock: number | null;
    images: string[] | null;
    cover_url: string | null;
    delivery_options: DeliveryOptions | null;
    product_type: string;
    is_published: boolean;
  } | null;
}

/** Commande de gros : même circuit sécurisé qu'un achat normal (argent gardé, litige possible), avec le prix de gros par palier. */
export default async function WholesaleOrderPage({ params }: { params: { id: string } }) {
  if (!isUuid(params.id)) notFound();
  const supabase = createClient();
  // La RLS ne montre que les offres actives d'un grossiste vérifié et non bloqué
  const { data } = await supabase
    .from("wholesale_products")
    .select("product_id, seller_id, min_quantity_10_price, min_quantity_50_price, stock_wholesale, city, product:products(id, title, price, stock, images, cover_url, delivery_options, product_type, is_published)")
    .eq("product_id", params.id)
    .eq("is_active", true)
    .maybeSingle();
  const offer = asRow<Offer>(data);
  const p = offer?.product;
  if (!offer || !p || !p.is_published || p.product_type !== "physical") notFound();

  const { data: auth } = await supabase.auth.getUser();
  const feeRules = await getServiceFeeRules();
  const image = p.images?.[0] ?? p.cover_url;
  const price10 = Math.min(p.price, offer.min_quantity_10_price);
  const price50 = Math.min(p.price, offer.min_quantity_50_price);
  const available = Math.min(p.stock ?? 0, offer.stock_wholesale);

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <nav aria-label="Fil d'Ariane" className="text-xs text-zinc-500">
        <Link href="/grossistes" className="hover:text-white">← Retour aux grossistes</Link>
      </nav>

      <header className="glass flex flex-col gap-4 p-5 sm:flex-row">
        {image && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={image} alt={p.title} className="aspect-[4/3] w-full rounded-xl object-cover sm:w-48" />
        )}
        <div className="space-y-2">
          <p className="inline-flex items-center gap-1 rounded-full bg-jade/15 px-2.5 py-1 text-[11px] font-semibold text-jade-soft">✓ {t("wholesale.verified")}</p>
          <h1 className="font-display text-2xl font-bold text-white">{p.title}</h1>
          <p className="text-sm text-zinc-400">Prix détail : <span className="line-through">{formatFcfa(p.price)}</span></p>
          <p className="text-sm text-zinc-200">
            <span className="font-semibold text-red-400">{formatFcfa(price10)}</span> l&apos;unité dès 10 pièces ·{" "}
            <span className="font-semibold text-red-400">{formatFcfa(price50)}</span> dès 50 pièces
          </p>
          <p className="text-xs text-zinc-400">{available} pièces disponibles en gros · {offer.city ?? "—"}</p>
        </div>
      </header>

      <section className="glass space-y-4 p-5" aria-labelledby="gros-cmd">
        <h2 id="gros-cmd" className="font-display text-lg font-semibold text-white">Commander et payer en sécurité</h2>
        <CheckoutForm
          productId={p.id}
          productType="physical"
          price={p.price}
          stock={p.stock}
          deliveryOptions={p.delivery_options}
          defaultEmail={auth.user?.email ?? ""}
          loggedIn={auth.user !== null}
          providers={enabledProviders()}
          feeRules={feeRules}
          wholesale={{ price10: offer.min_quantity_10_price, price50: offer.min_quantity_50_price, stockGros: offer.stock_wholesale }}
        />
      </section>

      <GuaranteeBadge />

      <section className="glass space-y-3 p-5 text-sm text-zinc-300">
        <h2 className="font-display text-base font-semibold text-white">Comment ça se passe</h2>
        <ol className="list-decimal space-y-1 pl-5">
          <li>Vous choisissez la quantité (10 à 1 000 pièces) : le prix de gros s&apos;applique tout seul.</li>
          <li>Vous payez en ligne (Mobile Money, carte, PayPal ou crypto). <strong>Le grossiste n&apos;est pas payé tout de suite</strong> : KDDF Market garde l&apos;argent.</li>
          <li>Le grossiste prépare et livre votre commande. Vous suivez l&apos;état avec le code KDDF-XXXX.</li>
          <li>À la réception, vous confirmez : l&apos;argent est libéré (jamais avant 7 jours après le paiement). Problème ? Vous ouvrez un litige avec photos et nous tranchons.</li>
        </ol>
        <p className="text-xs text-zinc-500">Pas de paiement à la livraison pour le gros. Un compte gratuit est obligatoire : il protège l&apos;acheteur et le grossiste.</p>
      </section>

      <section className="glass space-y-2 p-5">
        <h2 className="font-display text-base font-semibold text-white">Plus de 1 000 pièces, ou un prix à discuter ?</h2>
        <p className="text-xs text-zinc-400">Demandez un devis : le WhatsApp du grossiste s&apos;ouvre. Pour être protégé, finalisez ensuite la commande ici plutôt qu&apos;en dehors du site.</p>
        <WholesaleQuoteButton productId={p.id} title={p.title} loggedIn={auth.user !== null} />
      </section>
    </div>
  );
}
