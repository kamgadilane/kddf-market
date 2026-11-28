"use client";
import { useEffect, useState } from "react";
import { getDeferredPrompt, isInstalled, isIos, promptInstall, subscribeInstall } from "@/lib/installPrompt";

/**
 * Bouton « Installer l'application KDDF Market », visible sur mobile (pied de page de chaque page) tant que l'app n'est pas installée.
 *  - Android / Chrome : ouvre directement la fenêtre d'installation ;
 *  - si le navigateur ne la propose pas (ou sur iPhone) : affiche le geste à faire (Partager > Sur l'écran d'accueil, ou menu ⋮ > Installer).
 */
export default function InstallButton() {
  const [ready, setReady] = useState(false);
  const [installed, setInstalled] = useState(false);
  const [canPrompt, setCanPrompt] = useState(false);
  const [help, setHelp] = useState(false);

  useEffect(() => {
    const refresh = (): void => {
      setInstalled(isInstalled());
      setCanPrompt(getDeferredPrompt() !== null);
    };
    refresh();
    setReady(true);
    return subscribeInstall(refresh);
  }, []);

  if (!ready || installed) return null;

  async function onClick(): Promise<void> {
    const ok = await promptInstall();
    if (!ok && !getDeferredPrompt()) setHelp(true);
  }

  return (
    <div className="md:hidden">
      <button type="button" onClick={onClick} className="btn-primary w-full max-w-sm" data-testid="install-app">
        📲 Installer l&apos;application KDDF Market
      </button>
      {help && !canPrompt && (
        <p role="status" className="mx-auto mt-3 max-w-sm rounded-xl bg-white/5 px-4 py-3 text-left text-xs text-zinc-300">
          {isIos()
            ? "Sur iPhone : touchez le bouton Partager (carré avec une flèche), puis « Sur l'écran d'accueil »."
            : "Sur Android : ouvrez le menu ⋮ de Chrome, puis « Installer l'application » (ou « Ajouter à l'écran d'accueil »)."}
        </p>
      )}
    </div>
  );
}
