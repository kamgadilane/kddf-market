"use client";
import { useEffect, useState } from "react";

/**
 * L'en-tête contient chaque bouton deux fois (version ordinateur et version mobile, l'une masquée par le CSS).
 * Ce hook dit si CETTE version est celle qui est visible (seuil « lg » de Tailwind : 1024 px), pour que
 * le raccourci clavier et les mises à jour ne tournent qu'une fois.
 */
export function useShownAt(variant: "desktop" | "mobile"): boolean {
  const [shown, setShown] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(min-width: 1024px)");
    const sync = () => setShown(variant === "desktop" ? mq.matches : !mq.matches);
    sync();
    mq.addEventListener("change", sync);
    return () => mq.removeEventListener("change", sync);
  }, [variant]);
  return shown;
}
