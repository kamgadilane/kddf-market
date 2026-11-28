"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { cleanText, formString, isUuid } from "@/lib/validate";

const PAGE = "/admin/pub";

function done(ok: string): never {
  revalidatePath(PAGE);
  revalidatePath("/");
  redirect(`${PAGE}?ok=${ok}`);
}

/** Date AAAA-MM-JJ du formulaire -> début ou fin de journée (UTC), ou null si vide / invalide. */
function dayBoundary(raw: string, end: boolean): string | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return null;
  const d = new Date(`${raw}T${end ? "23:59:59" : "00:00:00"}Z`);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

// Les règles de sécurité sont dans la base : seul l'administrateur peut écrire dans site_banners (RLS), et les liens doivent commencer par https:// ou /.

/** Crée une bannière sponsorisée OU désigne le « produit de la semaine ». */
export async function createBanner(fd: FormData): Promise<void> {
  const kind = formString(fd, "kind") === "product" ? "product" : "banner";
  const productId = formString(fd, "product_id");
  const title = cleanText(formString(fd, "title"), 80) || (kind === "product" ? "Produit de la semaine" : "");
  if (title.length < 2) redirect(`${PAGE}?err=titre`);
  if (kind === "product" && !isUuid(productId)) redirect(`${PAGE}?err=produit`);
  const link = formString(fd, "link_url").trim();
  const image = formString(fd, "image_url").trim();
  const row = {
    kind,
    title,
    body: cleanText(formString(fd, "body"), 200) || null,
    link_url: kind === "banner" && link !== "" ? link : null,
    image_url: kind === "banner" && image !== "" ? image : null,
    label: cleanText(formString(fd, "label"), 20) || "Sponsorisé",
    product_id: kind === "product" ? productId : null,
    starts_at: dayBoundary(formString(fd, "starts"), false),
    ends_at: dayBoundary(formString(fd, "ends"), true),
  };
  const { error } = await createClient().from("site_banners").insert(row);
  if (error) redirect(`${PAGE}?err=${error.message.includes("check") ? "lien" : "autre"}`);
  done("cree");
}

export async function toggleBanner(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  if (!isUuid(id)) return;
  const { error } = await createClient().from("site_banners").update({ is_active: formString(fd, "active") === "yes" }).eq("id", id);
  if (error) redirect(`${PAGE}?err=autre`);
  done("maj");
}

export async function deleteBanner(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  if (!isUuid(id)) return;
  const { error } = await createClient().from("site_banners").delete().eq("id", id);
  if (error) redirect(`${PAGE}?err=autre`);
  done("supprime");
}
