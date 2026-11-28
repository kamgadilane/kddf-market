import Link from "next/link";
import ProductCard from "@/components/ProductCard";
import SponsorBanner, { type BannerData } from "@/components/SponsorBanner";
import { createClient } from "@/lib/supabase/server";
import { asRows } from "@/lib/db";
import { BOOST_PLANS } from "@/lib/boost";
import { CITIES } from "@/lib/shop";
import { PRODUCT_CATEGORIES, SORT_LABELS, cleanSearch, isSortKey, parsePrice, type SortKey } from "@/lib/catalog";
import type { BoostPlan } from "@/lib/types";
import type { Product } from "@/lib/types";

export const dynamic = "force-dynamic";

type ListedProduct = Pick<Product, "id" | "title" | "price" | "cover_url" | "images" | "product_type" | "digital_kind" | "stock" | "rating_avg" | "rating_count" | "city">;

const COLS = "id, title, price, cover_url, images, product_type, digital_kind, stock, rating_avg, rating_count, city";

interface Params { vendeur?: string; q?: string; category?: string; city?: string; min?: string; max?: string; type?: string; sort?: string }

export default async function Home({ searchParams }: { searchParams: Params }) {
  const filter = searchParams.type === "digital" || searchParams.type === "physical" ? searchParams.type : null;
  const q = cleanSearch(searchParams.q);
  const vendeur = cleanSearch(searchParams.vendeur);
  const category = PRODUCT_CATEGORIES.includes(searchParams.category ?? "") ? (searchParams.category as string) : "";
  const city = CITIES.includes(searchParams.city ?? "") ? (searchParams.city as string) : "";
  const min = parsePrice(searchParams.min);
  const max = parsePrice(searchParams.max);
  const sort: SortKey = isSortKey(searchParams.sort) ? searchParams.sort : "recent";
  const advancedCount = [category !== "", city !== "", vendeur !== "", min !== null, max !== null].filter(Boolean).length;
  const filtering = q !== "" || vendeur !== "" || category !== "" || city !== "" || min !== null || max !== null || filter !== null || sort !== "recent";

  // Recherche + filtres + tri combinés (seuls les produits publiés ET validés par l'admin sont visibles)
  let query = createClient().from("products").select(COLS).eq("is_published", true).eq("moderation_status", "approved");
  if (q) query = query.ilike("title", `%${q}%`);
  if (vendeur) {
    // Filtre par vendeur : on retrouve les boutiques dont le nom correspond (seuls les profils publics sont lisibles)
    const { data: shops } = await createClient().from("public_profiles").select("id").ilike("store_name", `%${vendeur}%`).limit(50);
    const shopIds = asRows<{ id: string }>(shops).map((s) => s.id);
    query = query.in("seller_id", shopIds.length > 0 ? shopIds : ["00000000-0000-0000-0000-000000000000"]);
  }
  if (category) query = query.eq("category", category);
  if (city) query = query.eq("city", city);
  if (min !== null) query = query.gte("price", min);
  if (max !== null) query = query.lte("price", max);
  if (filter) query = query.eq("product_type", filter);
  switch (sort) {
    case "price_asc": query = query.order("price", { ascending: true }); break;
    case "price_desc": query = query.order("price", { ascending: false }); break;
    case "rating": query = query.order("rating_avg", { ascending: false }).order("rating_count", { ascending: false }); break;
    default: query = query.order("created_at", { ascending: false });
  }
  const products = asRows<ListedProduct>((await query.limit(48)).data);

  // Produits boostés actifs (la formule la plus longue passe devant : 30 j, 14 j, 7 j puis 3 j) : seulement sans recherche/filtre
  const supabase = createClient();
  const { data: boostData } = filtering ? { data: [] } : await supabase.from("active_boosts").select("product_id, plan");
  const boosts = asRows<{ product_id: string; plan: BoostPlan }>(boostData);
  const planOf = new Map<string, BoostPlan>();
  // Un produit boosté plusieurs fois garde sa meilleure formule (30 j > 14 j > 7 j > 3 j)
  for (const b of boosts) if ((BOOST_PLANS[planOf.get(b.product_id) ?? "3d"].rank <= BOOST_PLANS[b.plan].rank) || !planOf.has(b.product_id)) planOf.set(b.product_id, b.plan);
  let featured: ListedProduct[] = [];
  if (planOf.size > 0) {
    const fq = supabase.from("products").select(COLS).eq("is_published", true).eq("moderation_status", "approved").in("id", Array.from(planOf.keys()));
    featured = asRows<ListedProduct>((await fq).data).sort((a, b) => BOOST_PLANS[planOf.get(b.id) ?? "3d"].rank - BOOST_PLANS[planOf.get(a.id) ?? "3d"].rank);
  }
  // Bannières sponsorisées et « produit de la semaine » (gérés par l'admin dans /admin/pub) : seulement sans recherche/filtre
  let banners: BannerData[] = [];
  let weekProduct: ListedProduct | null = null;
  if (!filtering) {
    const nowIso = new Date().toISOString();
    const { data: bData } = await supabase
      .from("site_banners")
      .select("id, kind, title, body, link_url, image_url, label, product_id")
      .eq("is_active", true)
      .or(`starts_at.is.null,starts_at.lte.${nowIso}`)
      .or(`ends_at.is.null,ends_at.gt.${nowIso}`)
      .order("created_at", { ascending: false })
      .limit(12);
    const rows = asRows<BannerData & { kind: "banner" | "product"; product_id: string | null }>(bData);
    banners = rows.filter((r) => r.kind === "banner").slice(0, 3);
    const wk = rows.find((r) => r.kind === "product" && r.product_id !== null);
    if (wk?.product_id) {
      const { data: wp } = await supabase.from("products").select(COLS).eq("id", wk.product_id).eq("is_published", true).eq("moderation_status", "approved").maybeSingle();
      weekProduct = (wp as ListedProduct | null) ?? null;
    }
  }

  const featuredIds = new Set(featured.map((f) => f.id));
  if (weekProduct) featuredIds.add(weekProduct.id);
  const rest = products.filter((p) => !featuredIds.has(p.id));
  const badgeOf = (id: string): string | undefined => {
    const plan = planOf.get(id);
    return plan ? BOOST_PLANS[plan].badge : undefined;
  };

  return (
    <div className="space-y-10">
      <section className="py-10 text-center sm:py-16">
        <h1 className="mx-auto max-w-3xl font-display text-4xl font-extrabold leading-tight text-white sm:text-5xl">
          Vendez vos produits <span className="text-volt-soft">digitaux</span> et <span className="text-jade-soft">physiques</span>
        </h1>
        <p className="mx-auto mt-4 max-w-xl text-zinc-400">
          Ebooks, formations, licences, coaching et produits livrés chez vous. Paiement Mobile Money, affiliation intégrée.
        </p>
        <div className="mt-6 flex justify-center gap-3">
          <Link href="/login?mode=signup" className="btn-primary">Créer ma boutique</Link>
          <a href="#catalogue" className="btn-ghost">Voir le catalogue</a>
        </div>
      </section>

      {banners.length > 0 && (
        <section className="grid gap-4 md:grid-cols-2" aria-label="Partenaires">
          {banners.map((b) => <SponsorBanner key={b.id} b={b} />)}
        </section>
      )}

      {weekProduct && (
        <section className="space-y-4">
          <h2 className="font-display text-2xl font-bold text-white">Produit de la semaine</h2>
          <div className="max-w-md">
            <ProductCard p={weekProduct} badge="Produit de la semaine" />
          </div>
        </section>
      )}

      {featured.length > 0 && (
        <section className="space-y-4">
          <h2 className="font-display text-2xl font-bold text-white">Produits à la une</h2>
          <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {featured.map((p) => <ProductCard key={p.id} p={p} badge={badgeOf(p.id)} />)}
          </div>
        </section>
      )}

      <section id="catalogue" className="space-y-5">
        <form method="get" action="/" className="glass space-y-4 p-4 sm:p-5">
          <div className="search-bar">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" className="shrink-0 text-zinc-500" aria-hidden="true"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></svg>
            <input type="search" name="q" defaultValue={q} placeholder="Que cherchez-vous ?" aria-label="Rechercher un produit" maxLength={60} enterKeyHint="search" />
            <button className="btn-primary !min-h-[40px] !rounded-xl !px-5 !py-2">Rechercher</button>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            {[{ v: "", l: "Tous" }, { v: "physical", l: "Physiques" }, { v: "digital", l: "Digitaux" }].map((o) => (
              <label key={o.v} className="cursor-pointer">
                <input type="radio" name="type" value={o.v} defaultChecked={(filter ?? "") === o.v} className="peer sr-only" />
                <span className="pill peer-checked:border-volt peer-checked:bg-volt peer-checked:text-white peer-focus-visible:ring-2 peer-focus-visible:ring-volt/50">{o.l}</span>
              </label>
            ))}
            <select name="sort" defaultValue={sort} aria-label="Trier par" className="input select ml-auto !min-h-[40px] !w-auto !rounded-full !py-2 !pl-4">
              {(Object.keys(SORT_LABELS) as SortKey[]).map((k) => <option key={k} value={k}>{SORT_LABELS[k]}</option>)}
            </select>
          </div>

          <details className="filters" open={category !== "" || city !== "" || vendeur !== "" || min !== null || max !== null}>
            <summary className="flex cursor-pointer items-center justify-between gap-2 rounded-xl border border-dashed border-white/15 px-4 py-2.5 text-sm font-medium text-zinc-300 hover:border-white/30">
              <span>Plus de filtres{advancedCount > 0 ? ` (${advancedCount})` : ""}</span>
              <svg className="filters-chevron transition" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" aria-hidden="true"><path d="m6 9 6 6 6-6" /></svg>
            </summary>
            <div className="mt-4 grid grid-cols-2 gap-3 lg:grid-cols-3">
              <div className="col-span-2 sm:col-span-1">
                <label className="label" htmlFor="f-cat">Catégorie</label>
                <select id="f-cat" name="category" defaultValue={category} className="input select">
                  <option value="">Toutes</option>
                  {PRODUCT_CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
                </select>
              </div>
              <div className="col-span-2 sm:col-span-1">
                <label className="label" htmlFor="f-city">Ville</label>
                <select id="f-city" name="city" defaultValue={city} className="input select">
                  <option value="">Toutes</option>
                  {CITIES.map((c) => <option key={c} value={c}>{c}</option>)}
                </select>
              </div>
              <div className="col-span-2 sm:col-span-1">
                <label className="label" htmlFor="f-vendeur">Vendeur / boutique</label>
                <input id="f-vendeur" name="vendeur" defaultValue={vendeur} placeholder="Nom de la boutique" className="input" maxLength={60} />
              </div>
              <div>
                <label className="label" htmlFor="f-min">Prix min (FCFA)</label>
                <input id="f-min" name="min" type="number" inputMode="numeric" min={0} defaultValue={min ?? ""} placeholder="0" className="input" />
              </div>
              <div>
                <label className="label" htmlFor="f-max">Prix max (FCFA)</label>
                <input id="f-max" name="max" type="number" inputMode="numeric" min={0} defaultValue={max ?? ""} placeholder="Sans limite" className="input" />
              </div>
            </div>
          </details>

          {filtering && <Link href="/#catalogue" className="inline-block text-sm font-medium text-volt-soft underline underline-offset-4">Réinitialiser la recherche</Link>}
        </form>
        {rest.length === 0 && featured.length === 0 ? (
          <p className="glass p-8 text-center text-sm text-zinc-400">{filtering ? "Aucun produit ne correspond à votre recherche." : "Aucun produit pour le moment."}</p>
        ) : (
          <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {rest.map((p) => <ProductCard key={p.id} p={p} badge={badgeOf(p.id)} />)}
          </div>
        )}
      </section>
    </div>
  );
}
