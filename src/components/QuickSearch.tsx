"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useShownAt } from "@/lib/useShownAt";
import { filterItems, normalize, SECTION_LABELS, type SearchItem, type SearchSection } from "@/lib/siteMap";

/** Loupe de l'en-tête : trouve vite une page du site (ou lance une recherche de produits). Raccourci : Ctrl+K ou « / ». */
export default function QuickSearch({ items, variant }: { items: SearchItem[]; variant: "desktop" | "mobile" }) {
  const shown = useShownAt(variant);
  const pathname = usePathname();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const buttonRef = useRef<HTMLButtonElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Section où se trouve la personne : ses résultats passent en premier
  const here: SearchSection = pathname.startsWith("/admin") ? "admin" : pathname.startsWith("/dashboard") ? "dashboard" : "site";

  const results = useMemo(() => {
    const found = filterItems(items, query);
    // Les pages de la section courante d'abord, puis le reste (ordre de pertinence conservé)
    return [...found.filter((i) => i.section === here), ...found.filter((i) => i.section !== here)];
  }, [items, query, here]);

  const q = query.trim();
  const productSearch = q.length >= 2 ? { href: `/?q=${encodeURIComponent(q.slice(0, 60))}#catalogue`, label: `Chercher « ${q.slice(0, 40)} » dans les produits` } : null;
  const total = results.length + (productSearch ? 1 : 0);

  function close(): void {
    setOpen(false);
    setQuery("");
    setActive(0);
    buttonRef.current?.focus();
  }

  function go(href: string): void {
    setOpen(false);
    setQuery("");
    setActive(0);
    router.push(href);
  }

  // Ouverture au clavier (Ctrl+K / Cmd+K, ou « / » hors d'un champ de saisie)
  useEffect(() => {
    if (!shown) return;
    const onKey = (e: KeyboardEvent) => {
      const el = e.target as HTMLElement | null;
      const typing = el !== null && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.tagName === "SELECT" || el.isContentEditable);
      if ((e.key === "k" || e.key === "K") && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        setOpen(true);
      } else if (e.key === "/" && !typing && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        setOpen(true);
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [shown]);

  // Fermer au changement de page ; bloquer le défilement derrière la fenêtre
  useEffect(() => {
    setOpen(false);
  }, [pathname]);
  useEffect(() => {
    if (!open) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    inputRef.current?.focus();
    return () => {
      document.body.style.overflow = previous;
    };
  }, [open]);

  function onInputKey(e: React.KeyboardEvent<HTMLInputElement>): void {
    if (e.key === "Escape") {
      e.preventDefault();
      close();
    } else if (e.key === "ArrowDown") {
      e.preventDefault();
      setActive((a) => (total === 0 ? 0 : (a + 1) % total));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((a) => (total === 0 ? 0 : (a - 1 + total) % total));
    } else if (e.key === "Enter") {
      e.preventDefault();
      const pick = active < results.length ? results[active]?.href : productSearch?.href;
      if (pick) go(pick);
    }
  }

  // Regroupe l'affichage par section en gardant l'ordre
  const rows: { item: SearchItem; index: number; header: string | null }[] = [];
  let lastSection: SearchSection | null = null;
  results.forEach((item, index) => {
    rows.push({ item, index, header: item.section !== lastSection ? (item.section === here && q === "" ? `Dans : ${SECTION_LABELS[item.section]}` : SECTION_LABELS[item.section]) : null });
    lastSection = item.section;
  });

  return (
    <>
      <button
        ref={buttonRef}
        type="button"
        onClick={() => setOpen(true)}
        aria-label="Rechercher dans le site"
        aria-haspopup="dialog"
        className="btn-ghost relative flex h-11 w-11 items-center justify-center !p-0 lg:h-auto lg:w-auto lg:!px-3 lg:!py-2"
      >
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></svg>
      </button>

      {open && createPortal(
        <div className="fixed inset-0 z-[60]">
          <button type="button" aria-label="Fermer la recherche" tabIndex={-1} onClick={close} className="absolute inset-0 h-full w-full cursor-default bg-black/60 backdrop-blur-sm" />
          <div role="dialog" aria-modal="true" aria-label="Recherche dans le site" className="menu-drawer absolute inset-x-3 top-3 mx-auto flex max-h-[85dvh] max-w-xl flex-col overflow-hidden rounded-2xl border border-white/10 bg-ink-900 shadow-2xl sm:top-16">
            <div className="flex items-center gap-2 border-b border-white/10 p-3">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" className="ml-1 shrink-0 text-zinc-500" aria-hidden="true"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></svg>
              <input
                ref={inputRef}
                value={query}
                onChange={(e) => { setQuery(e.target.value); setActive(0); }}
                onKeyDown={onInputKey}
                placeholder="Aller à… (retrait, produits, commandes)"
                aria-label="Que cherchez-vous ?"
                aria-controls="quick-results"
                role="combobox"
                aria-expanded="true"
                aria-activedescendant={total > 0 ? `qs-${active}` : undefined}
                autoComplete="off"
                maxLength={60}
                enterKeyHint="go"
                className="min-w-0 flex-1 bg-transparent py-2 text-base text-white outline-none placeholder:text-zinc-500 sm:text-sm"
              />
              <button type="button" onClick={close} className="btn-ghost !min-h-[36px] !px-3 !py-1.5 text-xs">Fermer</button>
            </div>

            <ul id="quick-results" role="listbox" className="overflow-y-auto p-2">
              {rows.map(({ item, index, header }) => (
                <li key={item.href + item.label} role="presentation">
                  {header && <p className="px-3 pb-1 pt-3 text-[11px] font-semibold uppercase tracking-wider text-zinc-500">{header}</p>}
                  <button
                    type="button"
                    id={`qs-${index}`}
                    role="option"
                    aria-selected={active === index}
                    onClick={() => go(item.href)}
                    onMouseEnter={() => setActive(index)}
                    className={`flex w-full items-center justify-between gap-3 rounded-xl px-3 py-2.5 text-left transition ${active === index ? "bg-volt/15" : "hover:bg-white/5"}`}
                  >
                    <span className="min-w-0">
                      <span className="block truncate text-sm font-semibold text-white">{item.label}</span>
                      <span className="block truncate text-xs text-zinc-400">{item.hint}</span>
                    </span>
                    <span aria-hidden="true" className="text-zinc-500">›</span>
                  </button>
                </li>
              ))}
              {productSearch && (
                <li role="presentation">
                  <p className="px-3 pb-1 pt-3 text-[11px] font-semibold uppercase tracking-wider text-zinc-500">Produits</p>
                  <button
                    type="button"
                    id={`qs-${results.length}`}
                    role="option"
                    aria-selected={active === results.length}
                    onClick={() => go(productSearch.href)}
                    onMouseEnter={() => setActive(results.length)}
                    className={`flex w-full items-center justify-between gap-3 rounded-xl px-3 py-2.5 text-left transition ${active === results.length ? "bg-volt/15" : "hover:bg-white/5"}`}
                  >
                    <span className="min-w-0 truncate text-sm font-semibold text-white">🔎 {productSearch.label}</span>
                    <span aria-hidden="true" className="text-zinc-500">›</span>
                  </button>
                </li>
              )}
              {total === 0 && (
                <li className="px-3 py-8 text-center text-sm text-zinc-400">
                  Aucune page ne correspond à « {normalize(query)} ».
                  <br />Essayez un autre mot, ou ouvrez l&apos;<a href="/support" className="text-volt-soft underline">aide</a>.
                </li>
              )}
            </ul>
            <p className="hidden border-t border-white/10 px-4 py-2 text-[11px] text-zinc-500 sm:block">↑ ↓ pour choisir · Entrée pour ouvrir · Échap pour fermer · Ctrl+K pour rouvrir</p>
          </div>
        </div>,
        document.body
      )}
    </>
  );
}
