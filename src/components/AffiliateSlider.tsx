"use client";
import { useState } from "react";

interface Props {
  id: string;
  /** Si fourni, le curseur est piloté par le parent (formulaire de création). Sinon il garde sa valeur et l'envoie via un champ caché. */
  value?: number;
  onChange?: (v: number) => void;
  defaultValue?: number;
  /** Nom du champ envoyé avec le formulaire (formulaires serveur). */
  name?: string;
}

const MIN = 1;
const MAX = 50;
const RECOMMENDED = 20;

const CSS = `
.aff-range{-webkit-appearance:none;appearance:none;width:100%;height:8px;border-radius:9999px;outline:none;cursor:pointer;
  background:linear-gradient(90deg,#6366F1 0%,#6366F1 var(--p),rgba(148,148,170,.28) var(--p),rgba(148,148,170,.28) 100%)}
.aff-range::-webkit-slider-thumb{-webkit-appearance:none;appearance:none;height:24px;width:24px;border-radius:9999px;background:#fff;
  border:4px solid #6366F1;box-shadow:0 2px 10px rgba(99,102,241,.55);transition:transform .15s}
.aff-range::-moz-range-thumb{height:18px;width:18px;border-radius:9999px;background:#fff;border:4px solid #6366F1;box-shadow:0 2px 10px rgba(99,102,241,.55)}
.aff-range:hover::-webkit-slider-thumb{transform:scale(1.12)}
.aff-range:focus-visible{box-shadow:0 0 0 3px rgba(99,102,241,.4)}
`;

/** Curseur « Commission affilié » de 1 % à 50 % (20 % conseillé). Le serveur revérifie toujours la valeur. */
export default function AffiliateSlider({ id, value, onChange, defaultValue = RECOMMENDED, name }: Props) {
  const [inner, setInner] = useState(defaultValue);
  const current = Math.min(MAX, Math.max(MIN, value ?? inner));
  const pct = ((current - MIN) / (MAX - MIN)) * 100;

  function set(v: number): void {
    setInner(v);
    onChange?.(v);
  }

  return (
    <div className="space-y-2">
      <style>{CSS}</style>
      <div className="flex items-center justify-between gap-3">
        <label className="label !mb-0" htmlFor={id}>Commission affilié</label>
        <span className="rounded-full bg-volt/15 px-3 py-1 text-sm font-bold text-volt-soft" aria-live="polite">{current} %</span>
      </div>
      <input
        id={id}
        type="range"
        min={MIN}
        max={MAX}
        step={1}
        value={current}
        onChange={(e) => set(Number(e.target.value))}
        className="aff-range"
        style={{ ["--p" as string]: `${pct}%` }}
        aria-valuemin={MIN}
        aria-valuemax={MAX}
        aria-valuenow={current}
      />
      {name && <input type="hidden" name={name} value={current} />}
      <div className="relative h-4 text-[11px] text-zinc-500">
        <span className="absolute left-0">{MIN} %</span>
        <span className="absolute -translate-x-1/2" style={{ left: `${((RECOMMENDED - MIN) / (MAX - MIN)) * 100}%` }}>{RECOMMENDED} % conseillé</span>
        <span className="absolute right-0">{MAX} %</span>
      </div>
      <p className="text-xs text-zinc-400">
        Plus tu donnes aux affiliés, plus ils vont vendre ton produit vite. 1 % = tu gagnes plus mais tu vends lentement. 50 % = tu gagnes moins par vente mais tu vends 10x plus vite.
        Le nouveau pourcentage s&apos;applique aux <strong>nouvelles</strong> ventes, pas aux anciennes.
      </p>
    </div>
  );
}
