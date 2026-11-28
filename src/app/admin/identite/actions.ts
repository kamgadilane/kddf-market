"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { failWith } from "@/lib/flash";
import { createClient } from "@/lib/supabase/server";
import { cleanText, formString, isUuid } from "@/lib/validate";

const PAGE = "/admin/identite";

/** Valide ou refuse les documents d'identité d'un vendeur (un motif est obligatoire pour un refus). */
export async function decideIdentity(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  if (!isUuid(id)) return;
  const approve = formString(fd, "approve") === "1";
  const reason = cleanText(formString(fd, "reason"), 300);
  const { error } = await createClient().rpc("admin_identity_decide", { p_user: id, p_approve: approve, p_reason: approve ? null : reason });
  if (error) failWith(PAGE, error.message);
  revalidatePath(PAGE);
  redirect(`${PAGE}?ok=${approve ? "valide" : "refuse"}`);
}

/** Règles de sécurité réglables à tout moment : identité obligatoire pour publier, téléphone confirmé par SMS obligatoire pour publier. */
export async function setSecurityRules(fd: FormData): Promise<void> {
  const supabase = createClient();
  const a = await supabase.rpc("admin_set_identity_required", { p_required: formString(fd, "identity") === "1" });
  if (a.error) failWith(PAGE, a.error.message);
  const b = await supabase.rpc("admin_set_phone_required", { p_required: formString(fd, "phone") === "1" });
  if (b.error) failWith(PAGE, b.error.message);
  revalidatePath(PAGE);
  redirect(`${PAGE}?ok=regles`);
}
