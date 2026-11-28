"use client";
import { useEffect, useState } from "react";
import { getDeferredPrompt, isInstalled, promptInstall, subscribeInstall } from "@/lib/installPrompt";

const DISMISS_KEY = "kddf-install-dismissed";

// Bandeau « Installer l'application » (Android/Chrome) affiché automatiquement. Le bouton permanent est dans le pied de page (InstallButton).
export default function InstallPrompt() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    let dismissed = false;
    try {
      dismissed = Boolean(localStorage.getItem(DISMISS_KEY));
    } catch {
      /* stockage indisponible : on affiche quand même */
    }
    const refresh = (): void => setVisible(!dismissed && !isInstalled() && getDeferredPrompt() !== null);
    refresh();
    return subscribeInstall(refresh);
  }, []);

  if (!visible) return null;

  function dismiss(): void {
    try {
      localStorage.setItem(DISMISS_KEY, "1");
    } catch {
      /* ignoré */
    }
    setVisible(false);
  }

  return (
    <div className="fixed inset-x-4 bottom-[max(1rem,env(safe-area-inset-bottom))] z-50 mx-auto flex max-w-md items-center gap-3 rounded-2xl border border-white/10 bg-ink-800/95 p-3 shadow-glow backdrop-blur-xl animate-rise">
      <p className="flex-1 text-sm text-zinc-200">Installez KDDF Market sur votre écran d&apos;accueil.</p>
      <button onClick={() => void promptInstall()} className="btn-primary !px-3 !py-2">Installer</button>
      <button onClick={dismiss} className="text-xs text-zinc-400 hover:text-white" aria-label="Fermer">Plus tard</button>
    </div>
  );
}
