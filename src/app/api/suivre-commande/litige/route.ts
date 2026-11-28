import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { dbErrorMessage } from "@/lib/labels";
import { imageKind } from "@/lib/imageKind";
import { MAX_DISPUTE_PHOTOS } from "@/lib/guest";
import { NOT_FOUND_MESSAGE, findGuestOrderId, readGuestKey, trackGuestOrder } from "@/lib/guestTrack";
import { notifyDisputeOpened } from "@/lib/disputeNotify";
import { cleanText, formString } from "@/lib/validate";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_PHOTO_BYTES = 4 * 1024 * 1024;
const EXT = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" } as const;

/**
 * « Ouvrir un litige » sans compte : Numéro + Code + motif + jusqu'à 3 photos.
 * Les photos sont vérifiées (octets réels, 4 Mo max) puis rangées dans le bucket privé « disputes », dossier = id de la commande.
 */
export async function POST(req: Request) {
  const fd = await req.formData().catch(() => null);
  if (!fd) return NextResponse.json({ error: "Formulaire illisible. Réessayez." }, { status: 400 });

  const k = await readGuestKey(req, formString(fd, "phone"), formString(fd, "code"));
  if (!k.ok) return NextResponse.json({ error: k.error }, { status: k.status });
  const reason = cleanText(formString(fd, "reason"), 500);
  if (reason.length < 5) return NextResponse.json({ error: dbErrorMessage("motif_invalide") }, { status: 400 });

  const files = fd.getAll("photos").filter((f): f is File => typeof f !== "string" && f.size > 0);
  if (files.length > MAX_DISPUTE_PHOTOS) return NextResponse.json({ error: dbErrorMessage("trop_de_photos") }, { status: 400 });

  const orderId = await findGuestOrderId(k.key);
  if (!orderId) return NextResponse.json({ error: NOT_FOUND_MESSAGE }, { status: 404 });

  const db = createAdminClient();
  const uploaded: string[] = [];
  try {
    for (const f of files) {
      if (f.size > MAX_PHOTO_BYTES) return await fail(db, uploaded, "Photo trop lourde (4 Mo maximum par photo).");
      const bytes = new Uint8Array(await f.arrayBuffer());
      const kind = imageKind(bytes);
      if (!kind) return await fail(db, uploaded, "Une photo n'est pas valide (JPG, PNG ou WebP uniquement).");
      const path = `${orderId}/guest-${Date.now()}-${uploaded.length}.${EXT[kind]}`;
      const up = await db.storage.from("disputes").upload(path, bytes, { contentType: kind, upsert: false });
      if (up.error) return await fail(db, uploaded, "Envoi de la photo impossible. Réessayez avec une image plus légère.");
      uploaded.push(path);
    }

    const { error } = await db.rpc("guest_open_dispute", { p_phone: k.key.phone, p_code: k.key.code, p_reason: reason, p_paths: uploaded });
    if (error) {
      await cleanup(db, uploaded);
      return NextResponse.json({ error: dbErrorMessage(error.message) }, { status: 400 });
    }
  } catch (e) {
    await cleanup(db, uploaded);
    console.error("[suivre-commande/litige]", e instanceof Error ? e.message : e);
    return NextResponse.json({ error: "Une erreur est survenue. Réessayez dans un instant." }, { status: 500 });
  }

  await notifyDisputeOpened(orderId); // ne lève jamais d'exception
  const order = await trackGuestOrder(k.key);
  return NextResponse.json({ ok: true, order }, { headers: { "Cache-Control": "no-store" } });
}

async function cleanup(db: ReturnType<typeof createAdminClient>, paths: string[]): Promise<void> {
  if (paths.length === 0) return;
  try {
    await db.storage.from("disputes").remove(paths);
  } catch {
    /* sans importance : fichier orphelin dans un bucket privé */
  }
}

async function fail(db: ReturnType<typeof createAdminClient>, paths: string[], error: string): Promise<NextResponse> {
  await cleanup(db, paths);
  return NextResponse.json({ error }, { status: 400 });
}
