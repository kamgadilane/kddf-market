import FlashError from "@/components/FlashError";
import { createClient } from "@/lib/supabase/server";
import { asRows } from "@/lib/db";
import { decideWholesale, verifySeller } from "./actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Admin · Validation", robots: { index: false } };

interface App {
  user_id: string;
  cni_path: string;
  shop_photo_path: string;
  whatsapp: string;
  status: string;
  created_at: string;
  profile: { full_name: string | null; store_name: string | null } | null;
}
interface Seller { id: string; full_name: string | null; store_name: string | null; city: string | null; is_verified: boolean }
interface Low { seller_id: string; seller_name: string; avg_rating: number | string; review_count: number | string }

/** Liens temporaires (10 min) pour TOUS les fichiers en UNE seule requête de stockage. */
async function signedMap(paths: string[]): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  if (paths.length === 0) return map;
  const { data } = await createClient().storage.from("wholesale").createSignedUrls(paths, 600);
  for (const row of data ?? []) if (row.path && row.signedUrl) map.set(row.path, row.signedUrl);
  return map;
}

export default async function AdminValidation({ searchParams }: { searchParams: { erreur?: string } }) {
  // 3 requêtes de données : candidatures grossistes (+ nom en jointure), vendeurs à vérifier (jointure produits), vendeurs mal notés (fonction SQL)
  const supabase = createClient();
  const [appsRes, sellersRes, lowRes] = await Promise.all([
    supabase.from("wholesale_applications").select("user_id, cni_path, shop_photo_path, whatsapp, status, created_at, profile:profiles!user_id(full_name, store_name)").eq("status", "pending").order("created_at").limit(50),
    supabase.from("profiles").select("id, full_name, store_name, city, is_verified, products!seller_id!inner(id)").eq("is_verified", false).limit(100),
    supabase.rpc("admin_low_rated_sellers", { p_below: 3, p_limit: 50 }),
  ]);
  const apps = asRows<App>(appsRes.data);
  const sellers = asRows<Seller>(sellersRes.data);
  const low = asRows<Low>(lowRes.data);
  const signed = await signedMap(apps.flatMap((a) => [a.cni_path, a.shop_photo_path]));
  const linkOf = new Map(apps.map((a) => [a.user_id, { cni: signed.get(a.cni_path) ?? null, shop: signed.get(a.shop_photo_path) ?? null }]));
  const names = new Map(apps.map((a) => [a.user_id, a.profile?.full_name ?? a.profile?.store_name ?? "—"]));
  const lowNames = new Map(low.map((l) => [l.seller_id, l.seller_name]));

  return (
    <div className="space-y-6">
      <FlashError code={searchParams.erreur} />
      <h1 className="font-display text-3xl font-bold text-white">Validation</h1>

      <section className="glass p-5">
        <p className="label">Candidatures « Grossiste » ({apps.length})</p>
        {apps.length === 0 ? <p className="text-sm text-zinc-500">Aucune candidature en attente.</p> : (
          <ul className="divide-y divide-white/5 text-sm">
            {apps.map((a) => (
              <li key={a.user_id} className="space-y-2 py-3 text-zinc-200">
                <p className="font-semibold text-white">{names.get(a.user_id) || "—"} · WhatsApp {a.whatsapp}</p>
                <p className="flex gap-4 text-xs">
                  {linkOf.get(a.user_id)?.cni ? <a className="text-volt-soft underline" href={linkOf.get(a.user_id)?.cni ?? "#"} target="_blank" rel="noopener noreferrer">Voir la CNI</a> : "CNI indisponible"}
                  {linkOf.get(a.user_id)?.shop ? <a className="text-volt-soft underline" href={linkOf.get(a.user_id)?.shop ?? "#"} target="_blank" rel="noopener noreferrer">Voir la boutique</a> : "Photo indisponible"}
                </p>
                <div className="flex gap-2">
                  <form action={decideWholesale}><input type="hidden" name="id" value={a.user_id} /><input type="hidden" name="approve" value="1" /><button className="btn-jade !px-3 !py-2">Valider le grossiste</button></form>
                  <form action={decideWholesale}><input type="hidden" name="id" value={a.user_id} /><input type="hidden" name="approve" value="0" /><button className="btn-ghost !px-3 !py-2 text-red-300">Refuser</button></form>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="glass p-5">
        <p className="label">Vendeurs à vérifier (CNI) ({sellers.length})</p>
        {sellers.length === 0 ? <p className="text-sm text-zinc-500">Tous les vendeurs sont vérifiés.</p> : (
          <ul className="divide-y divide-white/5 text-sm">
            {sellers.map((s) => (
              <li key={s.id} className="flex flex-wrap items-center justify-between gap-2 py-2.5 text-zinc-200">
                <span>{s.store_name ?? s.full_name ?? "—"} · {s.city ?? "—"}</span>
                <form action={verifySeller}><input type="hidden" name="id" value={s.id} /><input type="hidden" name="value" value="1" /><button className="btn-jade !px-3 !py-2">Valider (CNI contrôlée)</button></form>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="glass p-5">
        <p className="label">Vendeurs signalés : moins de 3 étoiles ({low.length})</p>
        {low.length === 0 ? <p className="text-sm text-zinc-500">Aucun vendeur mal noté.</p> : (
          <ul className="divide-y divide-white/5 text-sm">
            {low.map((l) => <li key={l.seller_id} className="flex justify-between gap-2 py-2.5 text-zinc-200"><span>{lowNames.get(l.seller_id) ?? "—"}</span><span className="text-amber-300">{Number(l.avg_rating).toFixed(1)} ★ · {Number(l.review_count)} avis</span></li>)}
          </ul>
        )}
      </section>
    </div>
  );
}
