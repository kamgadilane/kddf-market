import { createClient } from "@/lib/supabase/server";
import { asRows } from "@/lib/db";
import { formatFcfa } from "@/lib/money";
import { createBanner, deleteBanner, toggleBanner } from "./actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Admin · Pub & bannières", robots: { index: false } };

interface Banner { id: string; kind: "banner" | "product"; title: string; body: string | null; link_url: string | null; label: string; product_id: string | null; is_active: boolean; starts_at: string | null; ends_at: string | null }

const MESSAGES: Record<string, string> = {
  cree: "Enregistré : visible sur l'accueil selon les dates choisies.",
  maj: "Modification enregistrée.",
  supprime: "Supprimé.",
};
const ERRORS: Record<string, string> = {
  titre: "Le titre est trop court (2 caractères minimum).",
  produit: "Choisissez un produit pour le « produit de la semaine ».",
  lien: "Le lien ou l'image est refusé.\nUn lien doit commencer par https:// (ou par / pour une page du site) et une image par https://.",
  autre: "L'enregistrement a échoué.\nVérifiez que la mise à jour de la base (supabase/mise-a-jour-finale.sql) a bien été exécutée.",
};

const day = (d: string | null): string => (d ? new Date(d).toLocaleDateString("fr-FR") : "…");

export default async function AdminPub({ searchParams }: { searchParams: { ok?: string; err?: string } }) {
  const supabase = createClient();
  const [{ data: bData }, { data: pData }] = await Promise.all([
    supabase.from("site_banners").select("id, kind, title, body, link_url, label, product_id, is_active, starts_at, ends_at").order("created_at", { ascending: false }).limit(60),
    supabase.from("products").select("id, title, price").eq("is_published", true).eq("moderation_status", "approved").order("created_at", { ascending: false }).limit(100),
  ]);
  const banners = asRows<Banner>(bData);
  const products = asRows<{ id: string; title: string; price: number }>(pData);
  const titleOf = new Map(products.map((p) => [p.id, p.title]));
  const now = Date.now();
  const state = (b: Banner): string => {
    if (!b.is_active) return "Désactivée";
    if (b.starts_at && new Date(b.starts_at).getTime() > now) return "Programmée";
    if (b.ends_at && new Date(b.ends_at).getTime() <= now) return "Terminée";
    return "En ligne";
  };

  return (
    <div className="space-y-6">
      <h1 className="font-display text-3xl font-bold text-white">Pub &amp; bannières</h1>
      <p className="max-w-2xl text-sm text-zinc-400">Vendez de la visibilité : une bannière « Sponsorisé » (marque partenaire, outil, opérateur…) ou un « produit de la semaine » s&apos;affichent en haut de la page d&apos;accueil. Les tarifs sont dans <code className="text-volt-soft">src/lib/services.ts</code>.</p>
      {searchParams.ok && MESSAGES[searchParams.ok] && <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">{MESSAGES[searchParams.ok]}</p>}
      {searchParams.err && ERRORS[searchParams.err] && <p role="alert" className="whitespace-pre-line rounded-xl bg-red-500/10 px-4 py-3 text-sm text-red-200">{ERRORS[searchParams.err]}</p>}

      <form action={createBanner} className="glass space-y-4 p-5">
        <p className="label !mb-0">Ajouter</p>
        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <label className="label" htmlFor="pub-kind">Type</label>
            <select id="pub-kind" name="kind" className="input" defaultValue="banner">
              <option value="banner">Bannière sponsorisée</option>
              <option value="product">Produit de la semaine</option>
            </select>
          </div>
          <div>
            <label className="label" htmlFor="pub-title">Titre (80 caractères max)</label>
            <input id="pub-title" name="title" maxLength={80} className="input" placeholder="Ex : Orange Money : -10 % sur vos achats" />
          </div>
          <div className="sm:col-span-2">
            <label className="label" htmlFor="pub-body">Texte court (facultatif)</label>
            <input id="pub-body" name="body" maxLength={200} className="input" />
          </div>
          <div>
            <label className="label" htmlFor="pub-link">Lien (bannière) : https://… ou /page</label>
            <input id="pub-link" name="link_url" className="input" placeholder="https://exemple.com" />
          </div>
          <div>
            <label className="label" htmlFor="pub-image">Image (bannière, facultatif) : https://…</label>
            <input id="pub-image" name="image_url" className="input" placeholder="https://…/image.jpg" />
          </div>
          <div>
            <label className="label" htmlFor="pub-label">Étiquette</label>
            <input id="pub-label" name="label" maxLength={20} defaultValue="Sponsorisé" className="input" />
          </div>
          <div>
            <label className="label" htmlFor="pub-product">Produit (pour « produit de la semaine »)</label>
            <select id="pub-product" name="product_id" className="input" defaultValue="">
              <option value="">— aucun —</option>
              {products.map((p) => <option key={p.id} value={p.id}>{p.title} · {formatFcfa(p.price)}</option>)}
            </select>
          </div>
          <div>
            <label className="label" htmlFor="pub-starts">Début (facultatif)</label>
            <input id="pub-starts" name="starts" type="date" className="input" />
          </div>
          <div>
            <label className="label" htmlFor="pub-ends">Fin (facultatif)</label>
            <input id="pub-ends" name="ends" type="date" className="input" />
          </div>
        </div>
        <button className="btn-primary">Enregistrer</button>
      </form>

      <section className="glass p-5">
        <p className="label">Bannières et produits de la semaine ({banners.length})</p>
        {banners.length === 0 ? (
          <p className="text-sm text-zinc-500">Rien pour le moment.</p>
        ) : (
          <ul className="divide-y divide-white/5 text-sm">
            {banners.map((b) => (
              <li key={b.id} className="space-y-2 py-3">
                <p className="text-zinc-200">
                  <span className="font-semibold text-white">{b.title}</span>{" "}
                  <span className="text-xs text-zinc-500">· {b.kind === "product" ? `produit de la semaine : ${titleOf.get(b.product_id ?? "") ?? "produit"}` : `bannière « ${b.label} »`} · {state(b)} · du {day(b.starts_at)} au {day(b.ends_at)}</span>
                </p>
                {b.link_url && <p className="break-all text-xs text-zinc-500">{b.link_url}</p>}
                <div className="flex flex-wrap gap-2">
                  <form action={toggleBanner}>
                    <input type="hidden" name="id" value={b.id} />
                    <input type="hidden" name="active" value={b.is_active ? "no" : "yes"} />
                    <button className="btn-ghost !px-3 !py-1.5 text-xs">{b.is_active ? "Désactiver" : "Activer"}</button>
                  </form>
                  <form action={deleteBanner}>
                    <input type="hidden" name="id" value={b.id} />
                    <button className="btn-ghost !px-3 !py-1.5 text-xs text-red-300">Supprimer</button>
                  </form>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
