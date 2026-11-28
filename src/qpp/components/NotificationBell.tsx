"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { createClient } from "@/lib/supabase/client";
import { useShownAt } from "@/lib/useShownAt";

interface Notice {
  id: string;
  title: string;
  body: string;
  link: string | null;
  created_at: string;
  is_read: boolean;
  kind?: "annonce" | "perso";
}

function ago(iso: string): string {
  const s = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 1000));
  if (s < 60) return "à l'instant";
  if (s < 3600) return `il y a ${Math.floor(s / 60)} min`;
  if (s < 86400) return `il y a ${Math.floor(s / 3600)} h`;
  if (s < 7 * 86400) return `il y a ${Math.floor(s / 86400)} j`;
  return new Date(iso).toLocaleDateString("fr-FR");
}

/** Cloche de notification : les annonces de KDDF Market (messages de l'administrateur). Visible pour les personnes connectées. */
export default function NotificationBell({ variant }: { variant: "desktop" | "mobile" }) {
  const shown = useShownAt(variant);
  const [unread, setUnread] = useState(0);
  const [items, setItems] = useState<Notice[] | null>(null);
  const [open, setOpen] = useState(false);
  const [failed, setFailed] = useState(false);
  const buttonRef = useRef<HTMLButtonElement>(null);

  const refreshCount = useCallback(async () => {
    try {
      const { data, error } = await createClient().rpc("my_unread_notifications");
      if (!error && typeof data === "number") setUnread(data);
    } catch {
      /* hors ligne : on garde la valeur précédente */
    }
  }, []);

  // Compteur au chargement, toutes les 2 minutes et au retour sur l'onglet
  useEffect(() => {
    if (!shown) return;
    void refreshCount();
    const timer = window.setInterval(() => void refreshCount(), 120000);
    const onVisible = () => { if (document.visibilityState === "visible") void refreshCount(); };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [refreshCount, shown]);

  async function openPanel(): Promise<void> {
    setOpen(true);
    setFailed(false);
    try {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("my_notifications", { p_limit: 30 });
      if (error) throw new Error(error.message);
      setItems(Array.isArray(data) ? (data as Notice[]) : []);
      // Ouvrir la cloche = tout est lu (les annonces restent affichées avec leur ancien statut jusqu'à la prochaine ouverture)
      await supabase.rpc("mark_notifications_read");
      setUnread(0);
    } catch {
      setFailed(true);
      setItems([]);
    }
  }

  function closePanel(): void {
    setOpen(false);
    setItems((cur) => (cur ? cur.map((n) => ({ ...n, is_read: true })) : cur));
    buttonRef.current?.focus();
  }

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") closePanel(); };
    document.addEventListener("keydown", onKey);
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = previous;
    };
  }, [open]);

  return (
    <>
      <button
        ref={buttonRef}
        type="button"
        onClick={() => (open ? closePanel() : void openPanel())}
        aria-label={unread > 0 ? `Notifications : ${unread} non lue${unread > 1 ? "s" : ""}` : "Notifications"}
        aria-haspopup="dialog"
        aria-expanded={open}
        className="btn-ghost relative flex h-11 w-11 items-center justify-center !p-0 lg:h-auto lg:w-auto lg:!px-3 lg:!py-2"
      >
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" /><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
        </svg>
        {unread > 0 && (
          <span className="absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-red-500 px-1 text-[11px] font-bold leading-none text-white">{unread > 9 ? "9+" : unread}</span>
        )}
      </button>

      {open && createPortal(
        <div className="fixed inset-0 z-[60]">
          <button type="button" aria-label="Fermer les notifications" tabIndex={-1} onClick={closePanel} className="absolute inset-0 h-full w-full cursor-default bg-black/50 backdrop-blur-[2px]" />
          <section role="dialog" aria-modal="true" aria-label="Notifications" className="menu-drawer absolute inset-x-3 top-3 mx-auto flex max-h-[80dvh] max-w-md flex-col overflow-hidden rounded-2xl border border-white/10 bg-ink-900 shadow-2xl sm:left-auto sm:right-6 sm:top-16 sm:mx-0 sm:w-[24rem]">
            <header className="flex items-center justify-between border-b border-white/10 px-4 py-3">
              <p className="font-display text-base font-bold text-white">Notifications</p>
              <button type="button" onClick={closePanel} className="btn-ghost !min-h-[36px] !px-3 !py-1.5 text-xs">Fermer</button>
            </header>
            <div className="overflow-y-auto">
              {items === null && <p className="px-4 py-8 text-center text-sm text-zinc-400">Chargement…</p>}
              {failed && <p role="alert" className="px-4 py-8 text-center text-sm text-red-300">Impossible de charger les notifications pour le moment. Vérifiez votre connexion puis réessayez.</p>}
              {items !== null && !failed && items.length === 0 && (
                <p className="px-4 py-10 text-center text-sm text-zinc-400"><span aria-hidden="true" className="mb-2 block text-2xl">🔔</span>Aucune notification pour le moment.<br />Vos ventes, retraits et les messages de KDDF Market apparaîtront ici.</p>
              )}
              {items !== null && items.length > 0 && (
                <ul className="divide-y divide-white/5">
                  {items.map((n) => {
                    const inner = (
                      <>
                        <span className="flex items-start gap-2">
                          {!n.is_read && <span aria-label="Nouveau" className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-volt" />}
                          <span className="min-w-0">
                            <span className="block text-sm font-semibold text-white">{n.title}</span>
                            <span className="mt-0.5 block whitespace-pre-line break-words text-sm text-zinc-300">{n.body}</span>
                            <span className="mt-1 block text-xs text-zinc-500">{ago(n.created_at)}{n.link ? " · Ouvrir ›" : ""}</span>
                          </span>
                        </span>
                      </>
                    );
                    const cls = `block px-4 py-3 transition ${n.is_read ? "" : "bg-volt/5"} ${n.link ? "hover:bg-white/5" : ""}`;
                    return (
                      <li key={n.id}>
                        {n.link === null ? (
                          <div className={cls}>{inner}</div>
                        ) : n.link.startsWith("/") ? (
                          <Link href={n.link} onClick={closePanel} className={cls}>{inner}</Link>
                        ) : (
                          <a href={n.link} target="_blank" rel="noopener noreferrer" className={cls}>{inner}</a>
                        )}
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>
          </section>
        </div>,
        document.body
      )}
    </>
  );
}
