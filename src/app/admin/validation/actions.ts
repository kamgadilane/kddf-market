"use server";
import { revalidatePath } from "next/cache";
import { failWith } from "@/lib/flash";
import { createClient } from "@/lib/supabase/server";
import { formString, isUuid } from "@/lib/validate";

const PAGE = "/admin/validation";

export async function decideWholesale(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  if (!isUuid(id)) return;
  const { error } = await createClient().rpc("admin_wholesale_decide", { p_user: id, p_approve: formString(fd, "approve") === "1" });
  if (error) failWith(PAGE, error.message);
  revalidatePath(PAGE);
  revalidatePath("/grossistes");
}

/** Valide (ou retire) le badge « Vendeur Vérifié KDDF » après contrôle de la CNI. */
export async function verifySeller(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  if (!isUuid(id)) return;
  const { error } = await createClient().rpc("admin_set_verified", { p_user: id, p_value: formString(fd, "value") === "1" });
  if (error) failWith(PAGE, error.message);
  revalidatePath(PAGE);
}
