import Link from "next/link";
import FlashError from "@/components/FlashError";
import WholesaleApplyForm from "@/components/WholesaleApplyForm";
import WholesaleQuoteButton from "@/components/WholesaleQuoteButton";
import GuaranteeBadge from "@/components/GuaranteeBadge";
import { getSessionUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { asRows, asRow } from "@/lib/db";
import { formatFcfa } from "@/lib/money";
import { MAIN_CITIES } from "@/lib/currency";
import { WHOLESALE_RATES, type WholesaleProduct } from "@/lib/wholesale";
import { t } from "@/lib/translations";
import { saveWholesale, setRequestStatus } from "./actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Grossistes" };

interface Row extends WholesaleProduct {
  title: string;
  price: number;
  image: string | null;
}
interface Mine { id: string; title: string; price: number }
interface Req { id: string; product_id: string; quantity: number; status: string; created_at: string }
interface WholesaleJoined extends WholesaleProduct {
  product: { title: string; price: number; images: string[] | null; cover_url: string | null } | null;
}
// Profil + espace grossiste en UNE requête (jointures) : indicateur vérifié, candidature, produits physiques, demandes de devis
interface MeJoined {
  wholesale_verified: boolean;
  application: { status: string } | null;
  products: { id: string; title: string; price: number; product_type: string; created_at: string }[] | null;
  wholesale_requests: (Req & { seller_id: string })[] | null;
}

export default async function WholesalePage({ searchParams }: { searchParams: { ville?: string; erreur?: string } }) {
  // 2 requêtes de données au maximum (la liste publique + l'espace du grossiste connecté)
  const supabase = createClient();
  const user = await getSessionUser();
  const city = MAIN_CITIES.includes(searchParams.ville ?? "") ? (searchParams.ville as string) : null;

  let q = supabase
    .from("wholesale_products")
    .select("product_id, seller_id, min_quantity_10_price, min_quantity_50_price, stock_wholesale, city, is_active, product:products(title, price, images, cover_url)")
    .eq("is_active", true)
    .order("created_at", { ascending: false })
    .limit(60);
  if (city) q = q.eq("city", city);

  const [wholesaleRes, meRes] = await Promise.all([
    q,
    user
      ? supabase
          .from("profiles")
          .select("wholesale_verified, application:wholesale_applications!user_id(status), products!seller_id(id, title, price, product_type, created_at), wholesale_requests!seller_id(id, product_id, quantity, status, created_at, seller_id)")
          .eq("id", user.id)
          .maybeSingle()
      : Promise.resolve({ data: null }),
  ]);

  const rows: Row[] = asRows<WholesaleJoined>(wholesaleRes.data).flatMap((w) => {
    const { product, ...rest } = w;
    return product ? [{ ...rest, title: product.title, price: product.price, image: product.images?.[0] ?? product.cover_url }] : [];
  });

  const me = asRow<MeJoined>(meRes.data);
  const verified = me?.wholesale_verified === true;
  const byNewest = <T extends { created_at: string }>(list: T[]): T[] => [...list].sort((x, y) => y.created_at.localeCompare(x.created_at));
  const mine: Mine[] = verified ? byNewest(me?.products ?? []).filter((p) => p.product_type === "physical").slice(0, 50) : [];
  const reqs: Req[] = verified ? byNewest(me?.wholesale_requests ?? []).slice(0, 30) : [];
  const application: { status: string } | null = !verified && me ? me.application ?? null : null;

  return (
    <div className="space-y-6">
      <FlashError code={searchParams.erreur} />
      <header className="space-y-2">
        <h1 className="font-display text-3xl font-bold text-white">{t("wholesale.title")}</h1>
        <p className="text-sm text-zinc-400">Achetez en gros auprès de grossistes vérifiés. Prix dégressifs à partir de 10 et 50 pièces. Vous payez sur KDDF Market : <strong className="text-zinc-200">l&apos;argent est gardé jusqu&apos;à la réception</strong>.</p>
        <nav aria-label="Filtrer par ville" className="flex flex-wrap gap-2">
          <Link href="/grossistes" className={`btn-ghost !px-3 !py-1.5 text-xs ${city ? "" : "!border-volt"}`}>Toutes les villes</Link>
          {MAIN_CITIES.map((c) => <Link key={c} href={`/grossistes?ville=${encodeURIComponent(c)}`} className={`btn-ghost !px-3 !py-1.5 text-xs ${city === c ? "!border-volt" : ""}`}>{c}</Link>)}
        </nav>
      </header>

      {rows.length === 0 ? (
        <p className="glass p-8 text-center text-sm text-zinc-400">Aucun produit grossiste pour le moment{city ? ` à ${city}` : ""}.</p>
      ) : (
        <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {rows.map((r) => (
            <li key={r.product_id} className="card-float space-y-3 overflow-hidden p-4">
              {r.image && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={r.image} alt={r.title} className="aspect-[16/10] w-full rounded-xl object-cover" loading="lazy" />
              )}
              <p className="inline-flex items-center gap-1 rounded-full bg-jade/15 px-2.5 py-1 text-[11px] font-semibold text-jade-soft">✓ {t("wholesale.verified")}</p>
              <h2 className="font-display text-base font-semibold text-white">{r.title}</h2>
              <p className="text-sm text-zinc-400">Prix détail : <span className="line-through">{formatFcfa(r.price)}</span></p>
              <p className="text-sm text-zinc-200">
                <span className="font-semibold text-red-400">{formatFcfa(r.min_quantity_10_price)}</span> dès 10 pièces ·{" "}
                <span className="font-semibold text-red-400">{formatFcfa(r.min_quantity_50_price)}</span> dès 50 pièces
              </p>
              <p className="text-xs text-zinc-400">Stock gros : {r.stock_wholesale} · {r.city ?? "—"}</p>
              <Link href={`/grossistes/commander/${r.product_id}`} className="btn-primary w-full text-center">Commander et payer en sécurité</Link>
              <WholesaleQuoteButton productId={r.product_id} title={r.title} loggedIn={user !== null} />
            </li>
          ))}
        </ul>
      )}

      <GuaranteeBadge />

      {!user && <p className="glass p-5 text-sm text-zinc-300"><Link href="/login" className="text-volt-soft underline">Connecte-toi</Link> pour demander un devis ou devenir grossiste.</p>}
      {user && !verified && (
        application?.status === "pending" ? (
          <p role="status" className="glass p-5 text-sm text-amber-200">Votre candidature « Devenir Grossiste » est en cours de vérification.</p>
        ) : (
          <>
            {application?.status === "rejected" && <p className="rounded-xl bg-red-500/10 px-4 py-3 text-sm text-red-200">Votre dernière candidature a été refusée. Vous pouvez la renvoyer avec des photos plus nettes.</p>}
            <WholesaleApplyForm userId={user.id} />
          </>
        )
      )}

      {user && verified && (
        <section className="glass space-y-4 p-5">
          <h2 className="font-display text-xl font-bold text-white">Mon espace grossiste</h2>
          <p className="text-xs text-zinc-400">
            Quand l&apos;acheteur commande et paie sur le site : commission de la plateforme {WHOLESALE_RATES.platform} % au maximum (0 % pendant le lancement ou si votre compte est exempté), affilié {WHOLESALE_RATES.affiliate} % seulement si un affilié a amené la vente, le reste est pour vous ({WHOLESALE_RATES.seller} % à {100 - WHOLESALE_RATES.platform} %). La livraison vous revient entièrement. L&apos;argent est gardé comme pour tout produit physique, puis libéré à la réception. Les commandes de gros apparaissent dans « Mes commandes » avec le badge GROS. Un accord conclu uniquement par WhatsApp, hors du site, n&apos;est ni protégé ni commissionné.
          </p>
          {mine.length === 0 ? (
            <p className="text-sm text-zinc-500">Ajoutez d&apos;abord un produit physique dans votre espace créateur.</p>
          ) : (
            <ul className="space-y-3">
              {mine.map((p) => (
                <li key={p.id}>
                  <form action={saveWholesale} className="grid gap-2 rounded-xl bg-white/5 p-3 sm:grid-cols-6">
                    <input type="hidden" name="product_id" value={p.id} />
                    <p className="text-sm text-white sm:col-span-6">{p.title} <span className="text-zinc-500">(détail {formatFcfa(p.price)})</span></p>
                    <input name="price10" inputMode="numeric" placeholder="Prix dès 10" className="input !py-2" required />
                    <input name="price50" inputMode="numeric" placeholder="Prix dès 50" className="input !py-2" required />
                    <input name="stock" inputMode="numeric" placeholder="Stock gros" className="input !py-2" required />
                    <select name="city" className="input !py-2" defaultValue="Douala">{MAIN_CITIES.map((c) => <option key={c}>{c}</option>)}</select>
                    <select name="active" className="input !py-2" defaultValue="on"><option value="on">Visible</option><option value="off">Masqué</option></select>
                    <button className="btn-primary !py-2">Enregistrer</button>
                  </form>
                </li>
              ))}
            </ul>
          )}
          <div>
            <p className="label">Demandes de devis reçues</p>
            {reqs.length === 0 ? <p className="text-sm text-zinc-500">Aucune demande pour le moment.</p> : (
              <ul className="divide-y divide-white/5 text-sm">
                {reqs.map((r) => (
                  <li key={r.id} className="flex flex-wrap items-center justify-between gap-2 py-2.5 text-zinc-200">
                    <span>{r.quantity} pièces · {new Date(r.created_at).toLocaleDateString("fr-FR")} · <strong>{r.status}</strong></span>
                    <form action={setRequestStatus} className="flex gap-1.5">
                      <input type="hidden" name="id" value={r.id} />
                      <button name="status" value="contacté" className="btn-ghost !px-2.5 !py-1 text-xs">Contacté</button>
                      <button name="status" value="conclu" className="btn-jade !px-2.5 !py-1 text-xs">Conclu</button>
                      <button name="status" value="annulé" className="btn-ghost !px-2.5 !py-1 text-xs">Annulé</button>
                    </form>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </section>
      )}
    </div>
  );
}
