import FlashError from "@/components/FlashError";
import { createClient } from "@/lib/supabase/server";
import { asRow, asRows } from "@/lib/db";
import { decideIdentity, setSecurityRules } from "./actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Admin · Identités", robots: { index: false } };

interface Req {
  user_id: string; full_name: string | null; store_name: string | null; phone: string | null; whatsapp: string | null; city: string | null;
  front_path: string; back_path: string; selfie_path: string; selfie_kind: "photo" | "video"; submitted_at: string;
}
interface Overview { identity_pending?: number | string; identity_approved?: number | string; identity_rejected?: number | string; sellers_without_identity?: number | string; phones_confirmed?: number | string; mfa_enabled?: number | string }

/** Liens temporaires (10 min) pour tous les fichiers d'identité, en UNE requête de stockage. */
async function signedMap(paths: string[]): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  if (paths.length === 0) return map;
  const { data } = await createClient().storage.from("identity").createSignedUrls(paths, 600);
  for (const row of data ?? []) if (row.path && row.signedUrl) map.set(row.path, row.signedUrl);
  return map;
}

const num = (v: number | string | undefined): number => Number(v ?? 0);

export default async function AdminIdentity({ searchParams }: { searchParams: { ok?: string; erreur?: string } }) {
  const supabase = createClient();
  const [listRes, ovRes, rulesRes] = await Promise.all([
    supabase.rpc("admin_identity_list"),
    supabase.rpc("admin_security_overview"),
    supabase.from("commission_settings").select("identity_required, phone_required").eq("id", 1).maybeSingle(),
  ]);
  const rules = asRow<{ identity_required: boolean; phone_required: boolean }>(rulesRes.data);
  const identityRequired = rules?.identity_required ?? true;
  const phoneRequired = rules?.phone_required ?? false;
  const reqs = asRows<Req>(listRes.data);
  const ov = asRow<Overview>(ovRes.data) ?? {};
  const signed = await signedMap(reqs.flatMap((r) => [r.front_path, r.back_path, r.selfie_path]));

  return (
    <div className="space-y-6">
      <FlashError code={searchParams.erreur} />
      <h1 className="font-display text-3xl font-bold text-white">Vérification d&apos;identité des vendeurs</h1>
      <p className="max-w-2xl text-sm text-zinc-400">
        Comparez le visage de la vidéo (ou de la photo) avec la photo de la carte, vérifiez que le nom correspond et que la carte est lisible et non expirée. Validez seulement si tout est cohérent.
        Un vendeur validé reçoit le badge « Vendeur vérifié » et peut publier ; un refus doit toujours avoir un motif, que le vendeur verra.
      </p>
      {searchParams.ok === "valide" && <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">Identité validée : le vendeur peut publier.</p>}
      {searchParams.ok === "refuse" && <p role="status" className="rounded-xl bg-white/5 px-4 py-3 text-sm text-zinc-300">Demande refusée : le vendeur a été prévenu avec votre motif.</p>}

      <div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-5">
        {([
          ["En attente", num(ov.identity_pending)],
          ["Validées", num(ov.identity_approved)],
          ["Refusées", num(ov.identity_rejected)],
          ["Téléphones confirmés", num(ov.phones_confirmed)],
          ["Comptes avec 2FA", num(ov.mfa_enabled)],
        ] as [string, number][]).map(([label, n]) => (
          <div key={label} className="glass p-4"><p className="text-xs text-zinc-400">{label}</p><p className="font-display text-2xl font-bold text-white">{n}</p></div>
        ))}
      </div>
      {searchParams.ok === "regles" && <p role="status" className="rounded-xl bg-jade/10 px-4 py-3 text-sm text-jade-soft">Règles enregistrées.</p>}
      <form action={setSecurityRules} className="glass space-y-3 p-5">
        <p className="font-display text-lg font-bold text-white">Règles de sécurité des vendeurs</p>
        <label className="flex items-start gap-3 text-sm text-zinc-200">
          <input type="checkbox" name="identity" value="1" defaultChecked={identityRequired} className="mt-1 h-4 w-4" />
          <span>Identité obligatoire pour publier un produit <span className="block text-xs text-zinc-500">Recommandé. Les brouillons restent possibles ; les anciens vendeurs actifs sont reconnus automatiquement.</span></span>
        </label>
        <label className="flex items-start gap-3 text-sm text-zinc-200">
          <input type="checkbox" name="phone" value="1" defaultChecked={phoneRequired} className="mt-1 h-4 w-4" />
          <span>Téléphone confirmé par SMS obligatoire pour publier <span className="block text-xs text-zinc-500">À activer seulement après avoir configuré un fournisseur SMS dans Supabase (voir SECURITE-COMPTES.md). Les SMS sont payants.</span></span>
        </label>
        <button className="btn-primary !px-5 !py-2">Enregistrer les règles</button>
      </form>
      {num(ov.sellers_without_identity) > 0 && (
        <p className="rounded-xl bg-white/5 px-4 py-3 text-xs text-zinc-400">
          {num(ov.sellers_without_identity)} vendeur(s) ont des produits publiés sans identité validée. Ce sont d&apos;anciens vendeurs reconnus automatiquement : vous pouvez leur demander de se faire vérifier.
        </p>
      )}

      {reqs.length === 0 && <p className="glass p-8 text-center text-sm text-zinc-400">Aucune demande en attente. 🎉</p>}
      <ul className="space-y-5">
        {reqs.map((r) => {
          const front = signed.get(r.front_path);
          const back = signed.get(r.back_path);
          const selfie = signed.get(r.selfie_path);
          return (
            <li key={r.user_id} className="glass space-y-4 p-5">
              <div>
                <p className="font-display text-lg font-bold text-white">{r.store_name ?? r.full_name ?? "—"}</p>
                <p className="text-xs text-zinc-400">
                  {r.full_name ?? "—"} · {r.city ?? "ville ?"} · Tél {r.phone ?? "—"} · WhatsApp {r.whatsapp ?? "—"} · envoyé le {new Date(r.submitted_at).toLocaleString("fr-FR")}
                </p>
              </div>
              <div className="grid gap-3 sm:grid-cols-3">
                <figure className="space-y-1">
                  <figcaption className="text-xs text-zinc-400">Recto</figcaption>
                  {front ? <a href={front} target="_blank" rel="noopener noreferrer"><img src={front} alt="Recto de la carte" loading="lazy" className="max-h-64 w-full rounded-xl object-contain bg-black/40" /></a> : <p className="text-xs text-red-300">Fichier indisponible</p>}
                </figure>
                <figure className="space-y-1">
                  <figcaption className="text-xs text-zinc-400">Verso</figcaption>
                  {back ? <a href={back} target="_blank" rel="noopener noreferrer"><img src={back} alt="Verso de la carte" loading="lazy" className="max-h-64 w-full rounded-xl object-contain bg-black/40" /></a> : <p className="text-xs text-red-300">Fichier indisponible</p>}
                </figure>
                <figure className="space-y-1">
                  <figcaption className="text-xs text-zinc-400">{r.selfie_kind === "video" ? "Vidéo avec la carte" : "Photo avec la carte"}</figcaption>
                  {!selfie ? <p className="text-xs text-red-300">Fichier indisponible</p>
                    : r.selfie_kind === "video" ? <video src={selfie} controls preload="metadata" playsInline className="max-h-64 w-full rounded-xl bg-black/40" />
                    : <a href={selfie} target="_blank" rel="noopener noreferrer"><img src={selfie} alt="Vendeur tenant sa carte" loading="lazy" className="max-h-64 w-full rounded-xl object-contain bg-black/40" /></a>}
                </figure>
              </div>
              <div className="flex flex-wrap items-start gap-3">
                <form action={decideIdentity}>
                  <input type="hidden" name="id" value={r.user_id} />
                  <input type="hidden" name="approve" value="1" />
                  <button className="btn-jade !px-4 !py-2">✓ Valider l&apos;identité</button>
                </form>
                <form action={decideIdentity} className="flex flex-1 flex-wrap gap-2">
                  <input type="hidden" name="id" value={r.user_id} />
                  <input type="hidden" name="approve" value="0" />
                  <label className="sr-only" htmlFor={`why-${r.user_id}`}>Motif du refus</label>
                  <input id={`why-${r.user_id}`} name="reason" className="input min-w-[200px] flex-1" placeholder="Motif du refus (ex. photo floue, carte expirée)" minLength={3} maxLength={300} />
                  <button className="btn-ghost !px-4 !py-2 text-red-300">Refuser</button>
                </form>
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
