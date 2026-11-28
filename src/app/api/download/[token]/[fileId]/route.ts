import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { asRow } from "@/lib/db";
import { isUuid } from "@/lib/validate";
import { rateLimitIp, tooManyRequests } from "@/lib/rateLimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// Téléchargement d'un fichier acheté : on vérifie que la commande est PAYÉE, puis on redirige
// vers un lien signé qui expire au bout de 60 secondes (les fichiers ne sont jamais publics).
export async function GET(req: Request, { params }: { params: { token: string; fileId: string } }): Promise<NextResponse> {
  if (!isUuid(params.token) || !isUuid(params.fileId)) return NextResponse.json({ error: "Lien invalide" }, { status: 404 });
  // Anti-abus : 60 demandes de téléchargement par IP et par 10 minutes
  if (!(await rateLimitIp(req, "download", 60, 600))) return tooManyRequests("Trop de téléchargements en peu de temps. Patientez quelques minutes.");
  const db = createAdminClient();

  const { data: orderRow } = await db
    .from("orders")
    .select("product_id, payment_status, status")
    .eq("download_token", params.token)
    .maybeSingle();
  const order = asRow<{ product_id: string; payment_status: string; status: string }>(orderRow);
  if (!order || order.payment_status !== "paid" || order.status === "cancelled") {
    return NextResponse.json({ error: "Accès refusé" }, { status: 403 });
  }

  const { data: fileRow } = await db
    .from("product_files")
    .select("product_id, storage_path, file_name")
    .eq("id", params.fileId)
    .maybeSingle();
  const file = asRow<{ product_id: string; storage_path: string; file_name: string }>(fileRow);
  if (!file) return NextResponse.json({ error: "Fichier introuvable" }, { status: 404 });

  // Le fichier doit appartenir au produit acheté, ou à un produit de l'offre groupée achetée
  let allowed = file.product_id === order.product_id;
  if (!allowed) {
    const { data: link } = await db
      .from("bundle_items")
      .select("product_id")
      .eq("bundle_id", order.product_id)
      .eq("product_id", file.product_id)
      .maybeSingle();
    allowed = link !== null;
  }
  if (!allowed) return NextResponse.json({ error: "Accès refusé" }, { status: 403 });

  // Compteur par commande (limite le partage d'un lien d'achat) : 200 téléchargements au maximum
  const { data: counted } = await db.rpc("register_download", { p_token: params.token, p_max: 200 });
  if (!counted) {
    return NextResponse.json({ error: "Limite de téléchargements atteinte pour cet achat. Contactez le support." }, { status: 429 });
  }

  const { data: signed, error } = await db.storage
    .from("deliverables")
    .createSignedUrl(file.storage_path, 60, { download: file.file_name });
  if (error || !signed) return NextResponse.json({ error: "Lien indisponible" }, { status: 500 });
  return NextResponse.redirect(signed.signedUrl);
}
