"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { isUuid } from "@/lib/validate";
import { formString } from "@/lib/validate";
import { PLATFORM_MAX_PERCENT } from "@/lib/calculateCommission";
import { notifySellersByEmail } from "@/lib/commissionNotify";
import { PROVIDERS } from "@/lib/payments";

const PAGE = "/admin/commissions";

interface RpcResult {
  history_id: string;
  old: number | string;
  new: number | string;
}

function done(qs: string): never {
  revalidatePath(PAGE);
  redirect(`${PAGE}?${qs}`);
}

function failure(message: string): never {
  redirect(`${PAGE}?err=${message.includes("acces_refuse") ? "acces" : message.includes("commission_invalide") ? "plateforme" : "autre"}`);
}

/** Prévient les vendeurs par email si le taux AUGMENTE (et note le nombre de prévenus dans l'historique). */
async function maybeNotify(fd: FormData, r: RpcResult): Promise<string> {
  let qs = "ok=commission";
  if (formString(fd, "notify") === "yes" && Number(r.new) > Number(r.old)) {
    const sent = await notifySellersByEmail(Number(r.new));
    if (sent >= 0) await createClient().rpc("admin_note_notification", { p_history: r.history_id, p_count: sent });
    qs += `&n=${sent}`;
  }
  return qs;
}

/** Choisit le taux appliqué APRÈS les 30 jours de lancement (8 % par défaut, ou libre jusqu'à 10 %). Aucune ancienne règle 5/8/10 % n'existe plus. */
export async function setAfterLaunchPercent(fd: FormData): Promise<void> {
  const raw = formString(fd, "percent") === "custom" ? formString(fd, "custom") : formString(fd, "percent");
  const value = Number(raw.replace(",", ".").trim());
  if (raw.trim() === "" || !Number.isFinite(value) || value < 0 || value > PLATFORM_MAX_PERCENT) redirect(`${PAGE}?err=plateforme`);
  const { data, error } = await createClient().rpc("admin_set_after_launch_percent", { p_percent: value });
  if (error) failure(error.message);
  done(await maybeNotify(fd, data as RpcResult));
}

/** Tarifs réglables à tout moment : commission des vendeurs Pro, prix de l'abonnement Pro, frais de retrait (pourcentage et minimum), supplément du retrait express. Effet immédiat sur les nouvelles opérations. */
export async function setRevenueSettings(fd: FormData): Promise<void> {
  const dec = (k: string): number => Number(formString(fd, k).replace(",", ".").replace(/\s/g, "").trim());
  const proPercent = dec("pro_percent");
  const proPrice = dec("pro_price");
  const feePercent = dec("fee_percent");
  const feeMin = dec("fee_min");
  const expressPercent = dec("express_percent");
  const ok =
    Number.isFinite(proPercent) && proPercent >= 0 && proPercent <= PLATFORM_MAX_PERCENT &&
    Number.isInteger(proPrice) && proPrice >= 500 && proPrice <= 200000 &&
    Number.isFinite(feePercent) && feePercent >= 0 && feePercent <= PLATFORM_MAX_PERCENT &&
    Number.isInteger(feeMin) && feeMin >= 0 && feeMin <= 5000 &&
    Number.isFinite(expressPercent) && expressPercent >= 0 && expressPercent <= PLATFORM_MAX_PERCENT;
  if (!ok) redirect(`${PAGE}?err=tarifs`);
  const { error } = await createClient().rpc("admin_set_revenue_settings", { p_pro_percent: proPercent, p_pro_price: proPrice, p_fee_percent: feePercent, p_fee_min: feeMin, p_express_percent: expressPercent });
  if (error) {
    if (error.message.includes("valeur_invalide")) redirect(`${PAGE}?err=tarifs`);
    failure(error.message);
  }
  revalidatePath("/dashboard/pro");
  revalidatePath("/dashboard/wallet");
  done("ok=tarifs");
}

/** Termine le lancement tout de suite : le taux « après lancement » s'applique immédiatement. */
export async function endLaunchNow(fd: FormData): Promise<void> {
  const raw = formString(fd, "after");
  const value = Number(raw.replace(",", ".").trim());
  if (!Number.isFinite(value) || value <= 0 || value > PLATFORM_MAX_PERCENT) redirect(`${PAGE}?err=plateforme`);
  const { data, error } = await createClient().rpc("admin_set_commission", { p_percent: value });
  if (error) failure(error.message);
  done(await maybeNotify(fd, data as RpcResult));
}

/** (Re)lance une période de 30 jours à 0 %. */
export async function restartLaunch(): Promise<void> {
  const { error } = await createClient().rpc("admin_set_commission", { p_percent: 0 });
  if (error) failure(error.message);
  done("ok=launch");
}

/** Exempte (ou ne exempte plus) un compte : 0 % de commission et aucun frais de retrait. Se fait par e-mail ou par identifiant. */
export async function setCommissionExempt(fd: FormData): Promise<void> {
  let email = formString(fd, "email").trim();
  const id = formString(fd, "id");
  if (email === "" && isUuid(id)) {
    const { data } = await createAdminClient().auth.admin.getUserById(id);
    email = data.user?.email ?? "";
  }
  if (email === "") redirect(`${PAGE}?err=inconnu`);
  const exempt = formString(fd, "exempt") === "yes";
  const { error } = await createClient().rpc("admin_set_commission_exempt", { p_email: email, p_exempt: exempt });
  if (error) {
    if (error.message.includes("utilisateur_introuvable")) redirect(`${PAGE}?err=inconnu`);
    failure(error.message);
  }
  done(`ok=${exempt ? "exempt" : "nonexempt"}`);
}

/** Frais de service payés par l'acheteur, par moyen de paiement (0 à 15 % + 0 à 5 000 FCFA fixes). Effet immédiat sur les nouveaux paiements. */
export async function setServiceFees(fd: FormData): Promise<void> {
  const dec = (k: string): number => Number(formString(fd, k).replace(",", ".").replace(/\s/g, "").trim());
  const supabase = createClient();
  for (const gateway of PROVIDERS) {
    const percent = dec(`${gateway}_percent`);
    const fixed = dec(`${gateway}_fixed`);
    if (!Number.isFinite(percent) || percent < 0 || percent > 15 || !Number.isInteger(fixed) || fixed < 0 || fixed > 5000) redirect(`${PAGE}?err=frais`);
    const { error } = await supabase.rpc("admin_set_service_fee", { p_gateway: gateway, p_percent: percent, p_fixed: fixed });
    if (error) {
      if (error.message.includes("valeur_invalide")) redirect(`${PAGE}?err=frais`);
      failure(error.message);
    }
  }
  revalidatePath("/p/[id]", "page");
  done("ok=frais");
}

/** Nombre de produits publiés autorisés au plan gratuit (0 = illimité). */
export async function setFreeProductLimit(fd: FormData): Promise<void> {
  const value = Number(formString(fd, "limit").replace(/\s/g, "").trim());
  if (!Number.isInteger(value) || value < 0 || value > 1000) redirect(`${PAGE}?err=limite`);
  const { error } = await createClient().rpc("admin_set_free_product_limit", { p_limit: value });
  if (error) {
    if (error.message.includes("valeur_invalide")) redirect(`${PAGE}?err=limite`);
    failure(error.message);
  }
  revalidatePath("/dashboard/products");
  revalidatePath("/dashboard/pro");
  done("ok=limite");
}
