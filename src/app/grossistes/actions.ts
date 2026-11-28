"use server";
import { revalidatePath } from "next/cache";
import { failWith } from "@/lib/flash";
import { createClient } from "@/lib/supabase/server";
import { formString, isUuid } from "@/lib/validate";

const PAGE = "/grossistes";

function wholeFcfa(v: string): number {
  const n = Number(v.replace(/\s/g, ""));
  return Number.isInteger(n) && n > 0 ? n : 0;
}

/** Un grossiste vérifié met un de ses produits physiques en vente en gros (les contrôles sont refaits dans la base). */
export async function saveWholesale(fd: FormData): Promise<void> {
  const id = formString(fd, "product_id");
  if (!isUuid(id)) return;
  const { error } = await createClient().rpc("wholesale_save", {
    p_product: id,
    p_p10: wholeFcfa(formString(fd, "price10")),
    p_p50: wholeFcfa(formString(fd, "price50")),
    p_stock: Math.max(0, Math.trunc(Number(formString(fd, "stock")) || 0)),
    p_city: formString(fd, "city").slice(0, 60),
    p_active: formString(fd, "active") !== "off",
  });
  if (error) failWith(PAGE, error.message);
  revalidatePath(PAGE);
}

export async function setRequestStatus(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  const status = formString(fd, "status");
  if (!isUuid(id)) return;
  const { error } = await createClient().rpc("wholesale_set_request_status", { p_request: id, p_status: status });
  if (error) failWith(PAGE, error.message);
  revalidatePath(PAGE);
}
