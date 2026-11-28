"use server";
import { revalidatePath } from "next/cache";
import { failWith } from "@/lib/flash";
import { createClient } from "@/lib/supabase/server";
import { validateAffiliatePercent } from "@/lib/calculateCommission";
import { formString, isUuid } from "@/lib/validate";

// Toutes ces actions passent par le client connecté : les règles RLS garantissent
// qu'un vendeur ne peut modifier QUE ses propres produits.

export async function togglePublish(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  if (!isUuid(id)) return;
  const { error } = await createClient().from("products").update({ is_published: formString(fd, "publish") === "1" }).eq("id", id);
  if (error) failWith("/dashboard/products", error.message);
  revalidatePath("/dashboard/products");
}

export async function saveAffiliateSettings(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  const percent = Number(formString(fd, "percent"));
  if (!isUuid(id)) return;
  // 1 % à 50 % seulement : au-delà de 50 %, refus avec explication (jamais d'arrondi silencieux)
  if (!validateAffiliatePercent(percent).ok) failWith("/dashboard/products", "affiliation_invalide");
  const { error } = await createClient()
    .from("products")
    .update({ affiliate_enabled: formString(fd, "enabled") === "on", affiliate_percent: percent })
    .eq("id", id);
  if (error) failWith("/dashboard/products", error.message);
  revalidatePath("/dashboard/products");
  revalidatePath("/dashboard/affiliates");
}

export async function updateStock(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  const stock = Number(formString(fd, "stock"));
  if (!isUuid(id) || !Number.isInteger(stock) || stock < 0 || stock > 100000) return;
  const { error } = await createClient().from("products").update({ stock }).eq("id", id).eq("product_type", "physical");
  if (error) failWith("/dashboard/products", error.message);
  revalidatePath("/dashboard/products");
}

export async function deleteProduct(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  if (!isUuid(id)) return;
  // Un produit déjà commandé ne peut pas être supprimé (la base refuse) : on le dépublie à la place.
  const { error } = await createClient().from("products").delete().eq("id", id);
  if (error) await createClient().from("products").update({ is_published: false }).eq("id", id);
  revalidatePath("/dashboard/products");
}
