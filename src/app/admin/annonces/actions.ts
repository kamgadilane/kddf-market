"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { errorCode } from "@/lib/errors";
import { cleanText, formString, isUuid } from "@/lib/validate";

const PAGE = "/admin/annonces";

function fail(message: string): never {
  const code = errorCode(message);
  redirect(`${PAGE}?erreur=${code === "inconnue" ? "annonce_invalide" : code}`);
}

/** Envoie une annonce : elle apparaît dans la cloche des utilisateurs concernés (tous, vendeurs ou abonnés Pro). Les contrôles sont dans la base. */
export async function sendAnnouncement(fd: FormData): Promise<void> {
  const audienceRaw = formString(fd, "audience");
  const audience = audienceRaw === "sellers" || audienceRaw === "pro" ? audienceRaw : "all";
  const daysRaw = formString(fd, "days").trim();
  const days = daysRaw === "" ? null : Number(daysRaw);
  if (days !== null && (!Number.isInteger(days) || days < 1 || days > 365)) redirect(`${PAGE}?erreur=annonce_invalide`);
  const { error } = await createClient().rpc("admin_send_announcement", {
    p_title: cleanText(formString(fd, "title"), 80),
    p_body: formString(fd, "body").trim().slice(0, 500),
    p_audience: audience,
    p_link: formString(fd, "link").trim() || null,
    p_days: days,
  });
  if (error) fail(error.message);
  revalidatePath(PAGE);
  redirect(`${PAGE}?ok=envoyee`);
}

export async function deleteAnnouncement(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  if (!isUuid(id)) redirect(`${PAGE}?erreur=annonce_invalide`);
  const { error } = await createClient().rpc("admin_delete_announcement", { p_id: id });
  if (error) fail(error.message);
  revalidatePath(PAGE);
  redirect(`${PAGE}?ok=supprimee`);
}
