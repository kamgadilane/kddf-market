"use client";
import { useState } from "react";
import { COUNTRIES, DEFAULT_COUNTRY, type Country } from "@/lib/currency";
import { t } from "@/lib/translations";
import WaitlistForm from "@/components/WaitlistForm";

/** Sélecteur de pays en haut du site : Cameroun actif, les autres ouvrent une liste d'attente.
 *  inline = true (menu mobile) : la liste s'affiche dans le flux, sur toute la largeur, au lieu de flotter sur le côté. */
export default function CountrySelector({ inline = false }: { inline?: boolean }) {
  const [open, setOpen] = useState(false);
  const [soon, setSoon] = useState<Country | null>(null);
  const current = COUNTRIES.find((c) => c.code === DEFAULT_COUNTRY) ?? COUNTRIES[0];

  function pick(c: Country) {
    setOpen(false);
    if (!c.active) setSoon(c);
  }

  return (
    <div className={inline ? "w-full" : "relative"}>
      <button type="button" onClick={() => setOpen((v) => !v)} aria-haspopup="listbox" aria-expanded={open} className={inline ? "btn-ghost !flex w-full !justify-between !px-4 !py-3" : "btn-ghost !px-3 !py-2"}>
        <span><span aria-hidden>{current.flag}</span> <span className={inline ? "" : "hidden sm:inline"}>{current.name}</span></span> <span aria-hidden>{inline && open ? "▴" : "▾"}</span>
      </button>
      {open && (
        <ul role="listbox" className={`glass z-50 mt-2 space-y-1 p-2 text-sm ${inline ? "w-full" : "absolute right-0 w-60"}`}>
          {COUNTRIES.map((c) => (
            <li key={c.code}>
              <button type="button" role="option" aria-selected={c.code === current.code} onClick={() => pick(c)} className="flex w-full items-center justify-between gap-2 rounded-lg px-3 py-2 text-left hover:bg-white/10">
                <span>{c.flag} {c.name}</span>
                {!c.active && <span className="text-[11px] text-amber-300">{t("country.soon")}</span>}
              </button>
            </li>
          ))}
        </ul>
      )}
      {soon && (
        <div role="dialog" aria-modal="true" className="fixed inset-0 z-[60] flex items-center justify-center bg-black/70 p-4" onClick={() => setSoon(null)}>
          <div className="glass w-full max-w-sm space-y-4 p-6" onClick={(e) => e.stopPropagation()}>
            <p className="font-display text-xl font-bold text-white">{soon.flag} {t("country.popupTitle", { country: soon.name })}</p>
            <p className="text-sm text-zinc-300">{t("country.popupText")}</p>
            <WaitlistForm country={soon.code} countryName={soon.name} />
            <button type="button" className="btn-ghost w-full" onClick={() => setSoon(null)}>Fermer</button>
          </div>
        </div>
      )}
    </div>
  );
}
