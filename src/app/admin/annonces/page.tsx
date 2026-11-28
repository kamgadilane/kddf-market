import FlashError from "@/components/FlashError";
import { createClient } from "@/lib/supabase/server";
import { asRows } from "@/lib/db";
import { deleteAnnouncement, sendAnnouncement } from "./actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Admin · Annonces", robots: { index: false } };

interface Row { id: string; title: string; body: string; audience: string; link: string | null; created_at: string; expires_at: string | null; reads: number | string }

const AUDIENCE: Record<string, string> = { all: "Tous les utilisateurs", sellers: "Vendeurs (au moins 1 produit)", pro: "Abonnés Pro" };

export default async function AdminAnnonces({ searchParams }: { searchParams: { ok?: string; erreur?: string } }) {
  const { data, error } = await createClient().rpc("admin_list_announcements");
  const rows = asRows<Row>(data);
  const now = Date.now();

  return (
    <div className="space-y-6">
      <h1 className="font-display text-3xl font-bold text-white">Annonces (cloche 🔔)</h1>
      <p className="text-sm text-zinc-400">Écrivez un message : il apparaît dans la cloche des utilisateurs connectés, avec un point rouge tant qu&apos;ils ne l&apos;ont pas ouvert. Les annonces restent visibles 30 jours au plus.</p>

      <FlashError code={searchParams.erreur} />
      {searchParams.ok === "envoyee" && <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">Annonce envoyée : elle apparaît tout de suite dans la cloche.</p>}
      {searchParams.ok === "supprimee" && <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">Annonce supprimée : elle disparaît de la cloche de tout le monde.</p>}
      {error && <p role="alert" className="rounded-xl bg-red-500/10 px-4 py-3 text-sm text-red-200">Les annonces ne sont pas encore installées. Lancez <strong>mise-a-jour-recherche-cloche.sql</strong> dans le SQL Editor de Supabase, puis rechargez cette page.</p>}

      <section className="glass space-y-4 p-5">
        <p className="label !mb-0">Nouvelle annonce</p>
        <form action={sendAnnouncement} className="grid gap-4 sm:grid-cols-2">
          <div className="sm:col-span-2">
            <label className="label" htmlFor="an-title">Titre (80 caractères max)</label>
            <input id="an-title" name="title" required minLength={3} maxLength={80} placeholder="Ex. Nouveau : retrait express" className="input" />
          </div>
          <div className="sm:col-span-2">
            <label className="label" htmlFor="an-body">Message (500 caractères max)</label>
            <textarea id="an-body" name="body" required minLength={3} maxLength={500} rows={4} placeholder="Écrivez simplement ce que les utilisateurs doivent savoir." className="input" />
          </div>
          <div>
            <label className="label" htmlFor="an-aud">Destinataires</label>
            <select id="an-aud" name="audience" className="input select" defaultValue="all">
              {Object.entries(AUDIENCE).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
            </select>
          </div>
          <div>
            <label className="label" htmlFor="an-days">Disparaît après (jours, facultatif)</label>
            <input id="an-days" name="days" type="number" inputMode="numeric" min={1} max={365} placeholder="30 par défaut" className="input" />
          </div>
          <div className="sm:col-span-2">
            <label className="label" htmlFor="an-link">Lien au clic (facultatif)</label>
            <input id="an-link" name="link" maxLength={300} placeholder="/dashboard/wallet  ou  https://…" className="input" />
            <p className="mt-1 text-xs text-zinc-500">Une page du site commence par / (exemples : /dashboard/pro, /grossistes, /services). Un site extérieur doit commencer par https://.</p>
          </div>
          <div className="sm:col-span-2"><button className="btn-primary">Envoyer l&apos;annonce</button></div>
        </form>
      </section>

      <section className="glass p-5">
        <p className="label">Annonces envoyées ({rows.length})</p>
        {rows.length === 0 ? (
          <p className="text-sm text-zinc-500">Aucune annonce pour le moment.</p>
        ) : (
          <ul className="divide-y divide-white/5">
            {rows.map((r) => {
              const expired = r.expires_at !== null && new Date(r.expires_at).getTime() < now;
              return (
                <li key={r.id} className="space-y-1 py-3 text-sm">
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <p className="font-semibold text-white">{r.title}{expired && <span className="ml-2 rounded-full bg-white/10 px-2 py-0.5 text-xs font-normal text-zinc-300">expirée</span>}</p>
                    <form action={deleteAnnouncement}>
                      <input type="hidden" name="id" value={r.id} />
                      <button className="btn-ghost !px-3 !py-1.5 text-xs text-red-300">Supprimer</button>
                    </form>
                  </div>
                  <p className="whitespace-pre-line text-zinc-300">{r.body}</p>
                  <p className="text-xs text-zinc-500">
                    {AUDIENCE[r.audience] ?? r.audience} · envoyée le {new Date(r.created_at).toLocaleString("fr-FR")} · lue par {Number(r.reads)} personne(s)
                    {r.link ? ` · lien : ${r.link}` : ""}{r.expires_at ? ` · jusqu'au ${new Date(r.expires_at).toLocaleDateString("fr-FR")}` : ""}
                  </p>
                </li>
              );
            })}
          </ul>
        )}
      </section>
    </div>
  );
}
