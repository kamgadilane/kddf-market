"use server";
import { revalidatePath } from "next/cache";
import { failWith } from "@/lib/flash";
import { createClient } from "@/lib/supabase/server";
import { formString, isUuid } from "@/lib/validate";

const PAGE = "/admin/fraude";

// Les fonctions SQL vérifient elles-mêmes que l'appelant est administrateur.

/** Valider la vente (commission normale, 7 jours), la bloquer (commission = 0) ou bannir l'utilisateur. */
export async function resolveFraud(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  const decision = formString(fd, "decision");
  if (!isUuid(id) || (decision !== "validate" && decision !== "block" && decision !== "ban")) return;
  const { error } = await createClient().rpc("admin_fraud_resolve", { p_log: id, p_decision: decision });
  if (error) failWith(PAGE, error.message);
  revalidatePath(PAGE);
}

/** Débloquer manuellement un compte « en cours de vérification ». */
export async function unblockUser(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  if (!isUuid(id)) return;
  const { error } = await createClient().rpc("admin_fraud_unblock", { p_user: id });
  if (error) failWith(PAGE, error.message);
  revalidatePath(PAGE);
}

export async function setFraudActive(fd: FormData): Promise<void> {
  const { error } = await createClient().rpc("admin_fraud_set_active", { p_active: formString(fd, "active") === "on" });
  if (error) failWith(PAGE, error.message);
  revalidatePath(PAGE);
}
