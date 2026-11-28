"use server";
import { revalidatePath } from "next/cache";
import { failWith } from "@/lib/flash";
import { createClient } from "@/lib/supabase/server";
import { formString, isUuid } from "@/lib/validate";
import { notifyDisputeDecision } from "@/lib/disputeNotify";

const PAGE = "/admin/litiges";

/** Rembourser l'acheteur (refund) ou refuser le litige (reject : le vendeur est payé). Contrôle admin refait dans la base. */
export async function decideDispute(fd: FormData): Promise<void> {
  const id = formString(fd, "id");
  const decision = formString(fd, "decision");
  if (!isUuid(id) || (decision !== "refund" && decision !== "reject")) return;
  const { error } = await createClient().rpc("admin_dispute_decide", { p_dispute: id, p_decision: decision });
  if (error) failWith(PAGE, error.message);
  await notifyDisputeDecision(id, decision);
  revalidatePath(PAGE);
}
