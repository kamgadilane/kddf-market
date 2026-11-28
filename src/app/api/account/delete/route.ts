import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { rateLimit } from "@/lib/rateLimit";
import { explainError } from "@/lib/errors";
import { asRow } from "@/lib/db";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const BUCKETS = ["covers", "deliverables", "wholesale", "disputes"] as const;

/**
 * POST /api/account/delete  { confirm: "SUPPRIMER" }
 * 1) la base vérifie les conditions (solde vide, aucun retrait / litige / commande en cours) puis anonymise le profil et dépublie les produits ;
 * 2) sans historique de vente ni de retrait : le compte de connexion et ses fichiers sont supprimés ;
 *    avec historique (obligation de conserver les écritures comptables) : le compte est désactivé (connexion impossible) et le profil reste anonymisé.
 */
export async function POST(req: Request): Promise<NextResponse> {
  const body: unknown = await req.json().catch(() => null);
  const confirm = body !== null && typeof body === "object" ? (body as { confirm?: unknown }).confirm : null;
  if (confirm !== "SUPPRIMER") return NextResponse.json({ error: "Tapez le mot SUPPRIMER pour confirmer." }, { status: 400 });

  const supabase = createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return NextResponse.json({ error: explainError("connexion_requise") }, { status: 401 });
  const uid = auth.user.id;
  if (!(await rateLimit(`account-delete:${uid}`, 5, 3600))) return NextResponse.json({ error: "Trop de tentatives. Réessayez dans une heure." }, { status: 429 });

  const { data, error } = await supabase.rpc("delete_my_account");
  if (error) return NextResponse.json({ error: explainError(error.message) }, { status: 400 });
  const keepRecord = asRow<{ keep_login_record?: boolean }>(data)?.keep_login_record === true;

  const admin = createAdminClient();
  let removed = false;
  if (!keepRecord) {
    // Fichiers du compte (dossier portant l'identifiant de l'utilisateur dans chaque espace de stockage)
    for (const bucket of BUCKETS) {
      try {
        const { data: files } = await admin.storage.from(bucket).list(uid, { limit: 1000 });
        const paths = (files ?? []).filter((f) => f.name).map((f) => `${uid}/${f.name}`);
        if (paths.length > 0) await admin.storage.from(bucket).remove(paths);
      } catch {
        /* fichiers orphelins éventuels : sans conséquence pour la suppression du compte */
      }
    }
    const del = await admin.auth.admin.deleteUser(uid);
    removed = !del.error;
    if (del.error) console.error("[compte] suppression impossible, désactivation à la place", del.error.message);
  }
  if (!removed) {
    const ban = await admin.auth.admin.updateUserById(uid, { ban_duration: "876000h" });
    if (ban.error) console.error("[compte] désactivation impossible", ban.error.message);
  }
  await supabase.auth.signOut().catch(() => undefined);
  return NextResponse.json({ ok: true, removed });
}
