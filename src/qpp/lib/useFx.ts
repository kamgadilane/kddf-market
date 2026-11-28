"use client";
import { useEffect, useState } from "react";
import type { FxRates } from "@/lib/fxCore";

export type FxState = { status: "loading" } | { status: "error" } | { status: "ok"; rates: FxRates; marginPercent: number };

/** Charge les taux de change du jour (et les rafraîchit toutes les 10 minutes tant que la page est ouverte). */
export function useFxRates(): FxState {
  const [state, setState] = useState<FxState>({ status: "loading" });
  useEffect(() => {
    let cancelled = false;
    async function load(): Promise<void> {
      try {
        const res = await fetch("/api/fx", { cache: "no-store" });
        const json: unknown = await res.json().catch(() => null);
        const b = json !== null && typeof json === "object" ? (json as { rates?: FxRates; marginPercent?: number }) : {};
        if (!cancelled) setState(res.ok && b.rates ? { status: "ok", rates: b.rates, marginPercent: typeof b.marginPercent === "number" ? b.marginPercent : 0 } : { status: "error" });
      } catch {
        if (!cancelled) setState({ status: "error" });
      }
    }
    void load();
    const timer = setInterval(() => void load(), 10 * 60 * 1000);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, []);
  return state;
}
