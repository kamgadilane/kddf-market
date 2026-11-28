"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { isInstalled } from "@/lib/installPrompt";
import { posters } from "@/lib/posters";

/** Un drapeau par « première fois » : une fois sur le site web, une fois à la première ouverture de l'application installée. */
const KEY_WEB = "kddf_welcome_web_v1";
const KEY_APP = "kddf_welcome_app_v1";
/** Événement qui rouvre le guide (bouton « Revoir le guide » du pied de page). */
export const OPEN_WELCOME_EVENT = "kddf:open-welcome";
/** Pages où l'on n'interrompt jamais : administration, retours de connexion, paiement. */
const SKIP_PREFIXES = ["/admin", "/auth", "/login/2fa", "/offline"];

function storageKey(): string {
  return isInstalled() ? KEY_APP : KEY_WEB;
}

/** true seulement si le stockage fonctionne ET que le guide n'a jamais été vu (sinon, on ne risque pas de l'afficher à chaque page). */
function neverSeen(): boolean {
  try {
    return localStorage.getItem(storageKey()) === null;
  } catch {
    return false;
  }
}

function markSeen(): void {
  try {
    localStorage.setItem(storageKey(), new Date().toISOString());
  } catch {
    /* ignoré */
  }
}

/**
 * Affiches de bienvenue plein écran : comment utiliser l'application, les avantages, le service client.
 * - Affichées à la toute première visite, puis à la première ouverture de l'application installée.
 * - On passe d'une affiche à l'autre en faisant glisser (téléphone), avec les flèches du clavier ou les boutons.
 * - Le bouton « Quitter » est toujours visible ; Échap ferme aussi.
 */
export default function WelcomePosters() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const [index, setIndex] = useState(0);
  const scroller = useRef<HTMLDivElement>(null);
  const closeBtn = useRef<HTMLButtonElement>(null);
  const list = posters();
  const last = list.length - 1;

  // Premier passage
  useEffect(() => {
    if (SKIP_PREFIXES.some((p) => pathname.startsWith(p))) return;
    if (neverSeen()) setOpen(true);
  }, [pathname]);

  // Réouverture à la demande
  useEffect(() => {
    const reopen = (): void => {
      setIndex(0);
      setOpen(true);
    };
    window.addEventListener(OPEN_WELCOME_EVENT, reopen);
    return () => window.removeEventListener(OPEN_WELCOME_EVENT, reopen);
  }, []);

  const close = useCallback((): void => {
    markSeen();
    setOpen(false);
  }, []);

  const goTo = useCallback(
    (i: number): void => {
      const el = scroller.current;
      if (!el) return;
      const target = Math.max(0, Math.min(last, i));
      const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      el.scrollTo({ left: target * el.clientWidth, behavior: reduce ? "auto" : "smooth" });
      setIndex(target);
    },
    [last]
  );

  // Bloque le défilement de la page derrière, gère le clavier, met le focus sur « Quitter »
  useEffect(() => {
    if (!open) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeBtn.current?.focus();
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === "Escape") close();
      else if (e.key === "ArrowRight") goTo(index + 1);
      else if (e.key === "ArrowLeft") goTo(index - 1);
    };
    window.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = previous;
      window.removeEventListener("keydown", onKey);
    };
  }, [open, index, close, goTo]);

  if (!open) return null;

  function onScroll(): void {
    const el = scroller.current;
    if (!el || el.clientWidth === 0) return;
    const i = Math.round(el.scrollLeft / el.clientWidth);
    if (i !== index) setIndex(i);
  }

  return (
    <div role="dialog" aria-modal="true" aria-label="Guide de bienvenue" className="fixed inset-0 z-[100] flex flex-col bg-ink-950">
      {/* Barre du haut : progression + Quitter (toujours visible) */}
      <div className="absolute inset-x-0 top-0 z-10 flex items-center justify-between gap-3 px-4 pb-2 pt-[max(0.75rem,env(safe-area-inset-top))]">
        <p className="rounded-full bg-black/40 px-3 py-1 text-xs font-semibold text-white" aria-live="polite">{index + 1} / {list.length}</p>
        <button ref={closeBtn} type="button" onClick={close} className="rounded-full bg-white/15 px-4 py-2 text-sm font-semibold text-white backdrop-blur hover:bg-white/25 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white">
          Quitter ✕
        </button>
      </div>

      {/* Affiches : on glisse de l'une à l'autre */}
      <div ref={scroller} onScroll={onScroll} className="no-scrollbar flex flex-1 snap-x snap-mandatory overflow-x-auto overscroll-x-contain" tabIndex={0} aria-label="Affiches : faites glisser pour voir la suite">
        {list.map((p, i) => (
          <section
            key={p.id}
            aria-roledescription="affiche"
            aria-label={`${i + 1} sur ${list.length} : ${p.title}`}
            className="relative flex min-w-full snap-center flex-col items-center overflow-y-auto px-6 pb-40 pt-16 text-center"
            style={{ background: `radial-gradient(circle at 20% 15%, ${p.accent}33, transparent 45%), radial-gradient(circle at 85% 90%, ${p.accent}22, transparent 50%), linear-gradient(160deg, ${p.from}, ${p.to})` }}
          >
            <div className="mx-auto my-auto flex w-full max-w-md flex-col items-center gap-3 sm:gap-4">
              <div className="flex h-20 w-20 items-center justify-center rounded-3xl text-4xl shadow-2xl sm:h-24 sm:w-24 sm:text-5xl" style={{ background: `${p.accent}26`, boxShadow: `0 0 60px ${p.accent}55`, border: `1px solid ${p.accent}66` }} aria-hidden="true">{p.emoji}</div>
              <p className="text-xs font-bold uppercase tracking-[0.2em]" style={{ color: p.accent }}>{p.kicker}</p>
              <h2 className="font-display text-2xl font-extrabold leading-tight text-white sm:text-3xl">{p.title}</h2>
              <p className="text-sm text-white/85 sm:text-base">{p.text}</p>
              <ul className="w-full space-y-2 text-left">
                {p.bullets.map((b) => (
                  <li key={b} className="flex gap-2 rounded-2xl bg-black/25 px-4 py-2.5 text-sm text-white backdrop-blur">
                    <span aria-hidden="true" style={{ color: p.accent }}>●</span>
                    <span>{b}</span>
                  </li>
                ))}
              </ul>
              {p.cta && (
                <Link href={p.cta.href} onClick={close} className="mt-1 rounded-2xl px-6 py-3 text-sm font-bold text-ink-950 shadow-lg" style={{ background: p.accent }}>
                  {p.cta.label}
                </Link>
              )}
            </div>
          </section>
        ))}
      </div>

      {/* Barre du bas : points + précédent / suivant */}
      <div className="absolute inset-x-0 bottom-0 z-10 flex flex-col items-center gap-3 bg-gradient-to-t from-black/60 to-transparent px-4 pb-[max(1rem,env(safe-area-inset-bottom))] pt-8">
        <div className="flex gap-2" role="tablist" aria-label="Choisir une affiche">
          {list.map((p, i) => (
            <button key={p.id} type="button" role="tab" aria-selected={i === index} aria-label={`Affiche ${i + 1} : ${p.kicker}`} onClick={() => goTo(i)} className={`h-2.5 rounded-full transition-all ${i === index ? "w-7 bg-white" : "w-2.5 bg-white/40"}`} />
          ))}
        </div>
        <div className="flex w-full max-w-md gap-3">
          <button type="button" onClick={() => goTo(index - 1)} disabled={index === 0} className="flex-1 rounded-2xl bg-white/15 py-3 text-sm font-semibold text-white disabled:opacity-30">← Précédent</button>
          {index < last ? (
            <button type="button" onClick={() => goTo(index + 1)} className="flex-1 rounded-2xl bg-white py-3 text-sm font-bold text-ink-950">Suivant →</button>
          ) : (
            <button type="button" onClick={close} className="flex-1 rounded-2xl bg-white py-3 text-sm font-bold text-ink-950">Commencer ✓</button>
          )}
        </div>
      </div>
    </div>
  );
}
