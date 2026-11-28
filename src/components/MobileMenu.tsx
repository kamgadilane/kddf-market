"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

export type MobileMenuItem = {
  href: string;
  label: string;
  icon: string;
  primary?: boolean;
};

/**
 * Menu "classeur" pour mobile et tablette : un seul bouton dans la barre du haut,
 * et toutes les options apparaissent dans un tiroir quand on clique dessus.
 */
export default function MobileMenu({
  items,
  signedIn,
  children,
}: {
  items: MobileMenuItem[];
  signedIn: boolean;
  children?: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const pathname = usePathname();
  const buttonRef = useRef<HTMLButtonElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);

  const close = useCallback(() => {
    setOpen(false);
    buttonRef.current?.focus();
  }, []);

  // Fermer automatiquement dès qu'on change de page
  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  // Échap pour fermer + blocage du défilement de la page derrière le tiroir
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") close();
    };
    document.addEventListener("keydown", onKey);
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeRef.current?.focus();
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = previous;
    };
  }, [open, close]);

  return (
    <div className="lg:hidden">
      <button
        ref={buttonRef}
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-label={open ? "Fermer le menu" : "Ouvrir le menu"}
        aria-expanded={open}
        aria-controls="menu-mobile"
        className="btn-ghost relative flex h-11 w-11 items-center justify-center !p-0"
      >
        <span className="sr-only">Menu</span>
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
          <path d="M4 7h16M4 12h16M4 17h16" />
        </svg>
      </button>

      {/* Portail vers <body> : le flou de l'en-tête (backdrop-filter) piégerait sinon le tiroir dans la barre du haut */}
      {open && createPortal(
        <div className="fixed inset-0 z-50">
          <button
            type="button"
            aria-label="Fermer le menu"
            tabIndex={-1}
            onClick={close}
            className="absolute inset-0 h-full w-full cursor-default bg-black/60 backdrop-blur-sm"
          />
          <aside
            id="menu-mobile"
            role="dialog"
            aria-modal="true"
            aria-label="Menu principal"
            className="menu-drawer absolute right-0 top-0 flex h-[100dvh] w-[86%] max-w-sm flex-col overflow-y-auto border-l border-white/10 bg-ink-900 p-4 shadow-2xl"
          >
            <div className="mb-4 flex items-center justify-between">
              <p className="font-display text-lg font-bold text-white">Menu</p>
              <button
                ref={closeRef}
                type="button"
                onClick={close}
                aria-label="Fermer le menu"
                className="btn-ghost flex h-11 w-11 items-center justify-center !p-0"
              >
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
                  <path d="M6 6l12 12M18 6L6 18" />
                </svg>
              </button>
            </div>

            <nav className="flex flex-col gap-2" aria-label="Navigation">
              {items.map((it) => (
                <Link
                  key={it.href}
                  href={it.href}
                  onClick={() => setOpen(false)}
                  className={`${it.primary ? "btn-primary" : "btn-ghost"} !flex min-h-12 w-full !justify-start gap-3 !px-4 !py-3 text-base`}
                >
                  <span aria-hidden="true" className="w-6 text-center text-lg">{it.icon}</span>
                  <span>{it.label}</span>
                </Link>
              ))}
            </nav>

            {children && (
              <div className="mt-4 border-t border-white/10 pt-4">
                <p className="label !mb-2">Pays et devise</p>
                <div className="w-full">{children}</div>
              </div>
            )}

            {signedIn && (
              <form action="/auth/signout" method="post" className="mt-auto pt-6">
                <button className="btn-ghost !flex min-h-12 w-full !justify-start gap-3 !px-4 !py-3 text-base" aria-label="Se déconnecter">
                  <span aria-hidden="true" className="w-6 text-center text-lg">🚪</span>
                  <span>Se déconnecter</span>
                </button>
              </form>
            )}
          </aside>
        </div>,
        document.body
      )}
    </div>
  );
}
