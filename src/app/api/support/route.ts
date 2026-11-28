import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { explain } from "@/lib/errors";
import { cleanText, isEmail } from "@/lib/validate";
import { notifySupport, SUPPORT_CATEGORIES } from "@/lib/supportEmail";
import { rateLimit, rateLimitIp, tooManyRequests } from "@/lib/rateLimit";
import { imageKind } from "@/lib/imageKind";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_IMAGES = 3;
const MAX_IMAGE_BYTES = 4 * 1024 * 1024;
const MAX_TOTAL_BYTES = 4.4 * 1024 * 1024; // Vercel limite le corps d'une requête à ~4,5 Mo
const EXT: Record<string, string> = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" };

/**
 * POST /api/support : un message de support (avec captures d'écran facultatives).
 * Ouvert à tous, même sans compte. Protections : champ piège anti-robot, limite par email et globale.
 */
export async function POST(req: Request): Promise<NextResponse> {
  // Anti-abus par IP : 5 messages par heure (n'empêche pas les autres visiteurs d'écrire)
  if (!(await rateLimitIp(req, "support", 5, 3600))) return tooManyRequests("Trop de messages envoyés en peu de temps. Patientez une heure ou contactez-nous par WhatsApp.");
  let fd: FormData;
  try {
    fd = await req.formData();
  } catch {
    return NextResponse.json({ error: explain("Le message n'a pas pu être lu (fichiers trop lourds ?).", "Retirez les captures d'écran ou envoyez des images plus légères (4 Mo au total), puis réessayez.") }, { status: 400 });
  }

  // Champ piège : un humain ne le remplit jamais. On répond "ok" sans rien enregistrer.
  if (cleanText(fd.get("website"), 100) !== "") return NextResponse.json({ ok: true });

  const name = cleanText(fd.get("name"), 100);
  const email = cleanText(fd.get("email"), 254).toLowerCase();
  const message = cleanText(fd.get("message"), 3000);
  const page = cleanText(fd.get("page"), 500);
  const catRaw = cleanText(fd.get("category"), 20);
  const category = catRaw in SUPPORT_CATEGORIES ? catRaw : "autre";

  if (!name) return NextResponse.json({ error: explain("Votre nom est manquant.", "Indiquez votre nom puis envoyez à nouveau.") }, { status: 400 });
  if (!isEmail(email)) return NextResponse.json({ error: explain("L'adresse email n'est pas valide.", "Vérifiez-la (exemple : nom@gmail.com) : c'est là que nous vous répondrons.") }, { status: 400 });
  if (message.length < 10) return NextResponse.json({ error: explain("Le message est trop court.", "Décrivez le problème en au moins 10 caractères : que faisiez-vous, et que s'est-il passé ?") }, { status: 400 });

  const files = fd.getAll("images").filter((f): f is File => typeof f !== "string" && f.size > 0);
  if (files.length > MAX_IMAGES) return NextResponse.json({ error: explain(`Trop de captures d'écran (maximum ${MAX_IMAGES}).`, "Gardez les plus utiles et réessayez.") }, { status: 400 });
  let total = 0;
  for (const f of files) {
    total += f.size;
    if (!(f.type in EXT) || f.size > MAX_IMAGE_BYTES) {
      return NextResponse.json({ error: explain("Une capture n'est pas acceptée (format JPG, PNG ou WebP, 4 Mo maximum).", "Retirez-la ou choisissez une autre image, puis réessayez.") }, { status: 400 });
    }
  }
  if (total > MAX_TOTAL_BYTES) return NextResponse.json({ error: explain("Les captures sont trop lourdes ensemble (4 Mo maximum).", "Envoyez moins d'images ou des images plus légères.") }, { status: 400 });

  const db = createAdminClient();

  // Anti-abus : 5 messages par heure par email, 300 par heure au total (plafond large : un attaquant ne peut plus bloquer tout le monde)
  const [okMail, okAll] = await Promise.all([rateLimit(`support-mail:${email}`, 5, 3600), rateLimit("support-all", 300, 3600)]);
  if (!okMail || !okAll) {
    return NextResponse.json({ error: explain("Trop de messages envoyés en peu de temps.", "Patientez une heure puis réessayez, ou contactez-nous directement par WhatsApp.") }, { status: 429 });
  }

  const { data: auth } = await createClient().auth.getUser();
  const id = crypto.randomUUID();

  // Captures d'écran : dossier privé du message. Le vrai format est lu dans le contenu du fichier (le type annoncé par le navigateur est falsifiable).
  const paths: string[] = [];
  for (let i = 0; i < files.length; i++) {
    const f = files[i];
    const bytes = Buffer.from(await f.arrayBuffer());
    const kind = imageKind(bytes);
    if (!kind) continue;
    const path = `${id}/${i + 1}.${EXT[kind]}`;
    const up = await db.storage.from("support").upload(path, bytes, { contentType: kind });
    if (!up.error) paths.push(path);
    else console.error("[support] capture non enregistrée :", up.error.message);
  }

  const { error } = await db.from("support_messages").insert({
    id,
    user_id: auth.user?.id ?? null,
    name,
    email,
    category,
    message,
    page_url: page || null,
    images: paths,
  });
  if (error) {
    if (paths.length > 0) await db.storage.from("support").remove(paths);
    console.error("[support] enregistrement impossible :", error.message);
    return NextResponse.json({ error: explain("Votre message n'a pas pu être enregistré (la base de support n'est peut-être pas installée).", "Réessayez plus tard ou contactez-nous par WhatsApp. Le propriétaire doit exécuter supabase/schema.sql dans Supabase.") }, { status: 500 });
  }

  await notifySupport({ name, email, category, message, pageUrl: page || null, imageCount: paths.length });
  return NextResponse.json({ ok: true, ref: id.slice(0, 8).toUpperCase(), imagesSaved: paths.length, imagesSent: files.length });
}
