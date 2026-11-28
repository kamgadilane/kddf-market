// /admin/payouts : validation des demandes de retrait (même page que /admin/withdrawals, sous le nom demandé).
export const dynamic = "force-dynamic";
export const metadata = { title: "Admin · Payouts", robots: { index: false } };
export { default } from "../withdrawals/page";
