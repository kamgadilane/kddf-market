import { formatFcfa } from "@/lib/money";
import type { Transaction } from "@/lib/types";

export type SplitTx = Pick<Transaction, "total_amount" | "platform_fee" | "affiliate_fee" | "seller_amount" | "affiliate_id"> & { service_fee?: number };

/** Ligne d'historique : "Vente 10 000 FCFA AVEC affilié -> Toi : 6 500 / Affilié : 3 000 / KDDF : 500" */
export function splitLine(t: SplitTx): string {
  const withAff = t.affiliate_id !== null;
  const service = t.service_fee ?? 0;
  const sale = service > 0 ? `${formatFcfa(t.total_amount - service)} + ${formatFcfa(service)} de frais de service` : formatFcfa(t.total_amount);
  return `Vente ${sale} ${withAff ? "AVEC" : "SANS"} affilié -> Toi : ${formatFcfa(t.seller_amount ?? 0)}${
    withAff ? ` / Affilié : ${formatFcfa(t.affiliate_fee ?? 0)}` : ""
  } / KDDF : ${formatFcfa(t.platform_fee ?? 0)}`;
}
