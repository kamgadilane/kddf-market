// Taux de change (serveur). Sources, dans l'ordre :
//   1. open.er-api.com (gratuit, sans clé, mis à jour chaque jour)
//   2. frankfurter.dev (Banque centrale européenne)
//   3. dernière copie enregistrée en base (table fx_rates), utilisable 48 h au maximum
// Le FCFA n'est jamais demandé à une source : il est arrimé à l'euro (1 EUR = 655,957 FCFA, taux fixe officiel).
// Chaque taux reçu est contrôlé (bornes de bon sens) avant d'être utilisé. Les taux sont gardés 30 minutes en mémoire.
import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { asRows } from "@/lib/db";
import { XAF_PER_EUR, sanitizePerEur, type FxRates } from "@/lib/fxCore";

export class FxUnavailableError extends Error {
  constructor() {
    super("Taux de change indisponibles");
    this.name = "FxUnavailableError";
  }
}

const MEMORY_TTL_MS = 30 * 60 * 1000;
const DB_MAX_AGE_MS = 48 * 3600 * 1000;
const FETCH_TIMEOUT_MS = 6000;

let memory: { rates: FxRates; at: number } | null = null;

function isRecord(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

async function getJson(url: string): Promise<Record<string, unknown> | null> {
  const res = await fetch(url, { cache: "no-store", signal: AbortSignal.timeout(FETCH_TIMEOUT_MS), headers: { Accept: "application/json" } });
  if (!res.ok) return null;
  const json: unknown = await res.json().catch(() => null);
  return isRecord(json) ? json : null;
}

async function fromErApi(): Promise<FxRates | null> {
  const json = await getJson("https://open.er-api.com/v6/latest/EUR");
  if (!json || json.result !== "success" || !isRecord(json.rates)) return null;
  const perEur = sanitizePerEur(json.rates);
  if (!perEur) return null;
  const unix = typeof json.time_last_update_unix === "number" ? json.time_last_update_unix : NaN;
  const asOf = Number.isFinite(unix) ? new Date(unix * 1000).toISOString() : new Date().toISOString();
  return { perEur, asOf, source: "open.er-api.com", cached: false };
}

async function fromFrankfurter(): Promise<FxRates | null> {
  const json = await getJson("https://api.frankfurter.dev/v1/latest?base=EUR&symbols=USD,GBP,CAD");
  if (!json || !isRecord(json.rates)) return null;
  const perEur = sanitizePerEur(json.rates);
  if (!perEur) return null;
  const date = typeof json.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(json.date) ? `${json.date}T16:00:00.000Z` : new Date().toISOString();
  return { perEur, asOf: date, source: "frankfurter.dev (BCE)", cached: false };
}

async function saveToDb(rates: FxRates): Promise<void> {
  try {
    const rows = (["USD", "GBP", "CAD"] as const).map((code) => ({ currency: code, per_eur: rates.perEur[code], source: rates.source, as_of: rates.asOf, fetched_at: new Date().toISOString() }));
    await createAdminClient().from("fx_rates").upsert(rows, { onConflict: "currency" });
  } catch (e) {
    console.error("[fx] copie en base impossible :", e instanceof Error ? e.message : e);
  }
}

async function fromDb(): Promise<FxRates | null> {
  try {
    const { data } = await createAdminClient().from("fx_rates").select("currency, per_eur, source, as_of, fetched_at");
    const rows = asRows<{ currency: string; per_eur: number | string; source: string; as_of: string; fetched_at: string }>(data);
    if (rows.length === 0) return null;
    const raw: Record<string, unknown> = {};
    let oldest = Infinity;
    let source = "copie en base";
    let asOf = new Date(0).toISOString();
    for (const r of rows) {
      raw[r.currency] = Number(r.per_eur);
      oldest = Math.min(oldest, new Date(r.fetched_at).getTime());
      source = r.source;
      asOf = r.as_of;
    }
    if (!Number.isFinite(oldest) || Date.now() - oldest > DB_MAX_AGE_MS) return null;
    const perEur = sanitizePerEur(raw);
    return perEur ? { perEur, asOf, source: `${source} (copie)`, cached: true } : null;
  } catch {
    return null;
  }
}

/** Taux actuels. Lève FxUnavailableError si aucune source fiable n'est disponible (le paiement en devise étrangère est alors refusé). */
export async function getFxRates(): Promise<FxRates> {
  if (memory && Date.now() - memory.at < MEMORY_TTL_MS) return memory.rates;
  for (const source of [fromErApi, fromFrankfurter]) {
    try {
      const rates = await source();
      if (rates) {
        memory = { rates, at: Date.now() };
        await saveToDb(rates);
        return rates;
      }
    } catch (e) {
      console.error("[fx] source indisponible :", e instanceof Error ? e.message : e);
    }
  }
  const stored = await fromDb();
  if (stored) {
    memory = { rates: stored, at: Date.now() - MEMORY_TTL_MS + 2 * 60 * 1000 }; // on réessaie les sources en ligne dans 2 minutes
    return stored;
  }
  throw new FxUnavailableError();
}

/** Marge appliquée aux paiements en devise étrangère (variable FX_MARGIN_PERCENT, 0 à 10 ; 0 par défaut). */
export function fxMarginPercent(): number {
  const n = Number(process.env.FX_MARGIN_PERCENT ?? "0");
  return Number.isFinite(n) ? Math.min(10, Math.max(0, n)) : 0;
}

export { XAF_PER_EUR };
