"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function clearErrors(): Promise<void> {
  const { error } = await createClient().rpc("admin_clear_errors");
  if (error) redirect("/admin/erreurs?erreur=acces_refuse");
  revalidatePath("/admin/erreurs");
  redirect("/admin/erreurs?ok=vide");
}
