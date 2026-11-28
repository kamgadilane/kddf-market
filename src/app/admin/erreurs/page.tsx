import FlashError from "@/components/FlashError";
import { createClient } from "@/lib/supabase/server";
import { asRows } from "@/lib/db";
import { clearErrors } from "./actions";
import { adviceFor, URGENCY_LABEL } from "@/lib/errorAdvice";

export const dynamic = "force-dynamic";
export const metadata = { title: "Admin · Erreurs", robots: { index: false } };

interface Row { id: number; created_at: string; source: string; message: string; url: string | null; digest: string | null; occurrences: number | string }

export default async function AdminErrors({ searchParams }: { searchParams: { ok?: string; erreur?: string } }) {
  const { data, error } = await createClient().rpc("admin_list_errors");
  const rows = asRows<Row>(data);
  return (
    <div className="space-y-5">
      <FlashError code={searchParams.erreur} />
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="font-display text-3xl font-bold text-white">Erreurs du site</h1>
        {rows.length > 0 && (
          <form action={clearErrors}><button className="btn-ghost !px-4 !py-2 text-red-300">Vider le journal</button></form>
        )}
      </div>
      <p className="text-sm text-zinc-400">
        Les pages qui plantent chez vos visiteurs sont notées ici (100 dernières, conservées 30 jours). Recopiez la « Référence » pour la retrouver dans les journaux Vercel (Logs).
        Une erreur qui revient souvent mérite d&apos;être corrigée en premier. Cliquez sur « que faire ? » sous chaque erreur : la cause probable et les étapes y sont expliquées.
        Vous êtes aussi prévenu par la cloche et par email (au plus un message toutes les 30 minutes) pour les erreurs importantes.
      </p>
      {searchParams.ok === "vide" && <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">Journal vidé.</p>}
      {error && <p role="alert" className="rounded-xl bg-red-500/10 px-4 py-3 text-sm text-red-200">Le journal n&apos;est pas disponible : exécutez supabase/mise-a-jour-finale.sql dans Supabase (SQL Editor).</p>}
      {!error && rows.length === 0 && <p className="glass p-8 text-center text-sm text-zinc-400">Aucune erreur enregistrée. 🎉</p>}
      {rows.length > 0 && (
        <ul className="glass divide-y divide-white/5 text-sm">
          {rows.map((r) => (
            <li key={r.id} className="space-y-1 px-4 py-3">
              <p className="break-words text-zinc-100">{r.message}</p>
              <details className="rounded-xl bg-white/[0.04] px-3 py-2 text-xs text-zinc-300">
                <summary className="cursor-pointer font-semibold text-white">{adviceFor(r.message).title} · {URGENCY_LABEL[adviceFor(r.message).urgency]} — que faire ?</summary>
                <p className="mt-2"><strong>Cause probable :</strong> {adviceFor(r.message).cause}</p>
                <ol className="mt-1 list-decimal space-y-1 pl-5">{adviceFor(r.message).steps.map((s) => <li key={s}>{s}</li>)}</ol>
              </details>
              <p className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-zinc-500">
                <span>{new Date(r.created_at).toLocaleString("fr-FR")}</span>
                {r.url && <span>Page : {r.url}</span>}
                {r.digest && <span className="font-mono">Réf. {r.digest}</span>}
                <span>{Number(r.occurrences)} fois en 30 jours</span>
              </p>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
