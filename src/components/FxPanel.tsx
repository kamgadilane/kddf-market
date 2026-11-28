"use client";
import { FX_CURRENCIES, describeRate, formatMoney, quoteFromFcfa, type FxCurrency } from "@/lib/fxCore";
import type { FxState } from "@/lib/useFx";

interface Props {
  totalFcfa: number;
  fx: FxState;
  currency: FxCurrency;
  onCurrency: (c: FxCurrency) => void;
  /** Vrai si le moyen choisi encaisse en devise étrangère (PayPal) : le montant converti est alors le montant réellement payé. */
  paysInForeign: boolean;
  /** Devise réellement débitée (PayPal : la devise choisie si PayPal l'accepte, sinon USD). */
  chargeCurrency: FxCurrency;
}

/** Conversion en temps réel avant le paiement : l'acheteur voit le total dans sa devise et le taux utilisé. */
export default function FxPanel({ totalFcfa, fx, currency, onCurrency, paysInForeign, chargeCurrency }: Props) {
  const shown = currency === "XAF" ? null : fx.status === "ok" ? quoteFromFcfa(totalFcfa, currency, fx.rates, 0) : null;
  const charge = paysInForeign && fx.status === "ok" ? quoteFromFcfa(totalFcfa, chargeCurrency, fx.rates, fx.marginPercent) : null;
  const when = fx.status === "ok" ? new Date(fx.rates.asOf).toLocaleString("fr-FR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "";

  return (
    <div className="space-y-2 rounded-xl border border-white/10 bg-white/[0.03] p-4 text-sm">
      <div className="flex items-center justify-between gap-3">
        <label className="label !mb-0" htmlFor="fx-currency">Voir le total en</label>
        <select id="fx-currency" className="input !min-h-[40px] !w-auto !py-2" value={currency} onChange={(e) => onCurrency(e.target.value as FxCurrency)}>
          {FX_CURRENCIES.map((c) => <option key={c.code} value={c.code}>{c.code} · {c.label}</option>)}
        </select>
      </div>
      {currency !== "XAF" && fx.status === "loading" && <p className="text-xs text-zinc-500">Chargement du taux de change…</p>}
      {currency !== "XAF" && fx.status === "error" && <p className="text-xs text-amber-300">Taux de change indisponibles pour le moment. Les paiements Mobile Money en FCFA restent possibles.</p>}
      {shown && fx.status === "ok" && (
        <p className="text-zinc-300">
          <span className="font-display text-lg font-bold text-white">≈ {formatMoney(shown.minor, currency)}</span>
          <span className="block text-xs text-zinc-500">{describeRate(currency, fx.rates)} · taux du {when} ({fx.rates.source})</span>
        </p>
      )}
      {paysInForeign && fx.status === "error" && <p className="text-xs text-amber-300">PayPal est momentanément indisponible faute de taux de change : choisissez Mobile Money.</p>}
      {charge && fx.status === "ok" && (
        <p className="rounded-lg bg-jade/10 px-3 py-2 text-xs text-jade-soft">
          Vous paierez exactement <strong>{formatMoney(charge.minor, chargeCurrency)}</strong> sur PayPal ({describeRate(chargeCurrency, fx.rates, fx.marginPercent)}). Ce montant est verrouillé au moment où vous cliquez sur « Payer ».
        </p>
      )}
    </div>
  );
}
