"use client";
import { OPEN_WELCOME_EVENT } from "@/components/WelcomePosters";

/** Bouton du pied de page : rouvre le guide de bienvenue (affiches). */
export default function WelcomeGuideButton() {
  return (
    <button type="button" onClick={() => window.dispatchEvent(new Event(OPEN_WELCOME_EVENT))} className="underline hover:text-white">
      Revoir le guide
    </button>
  );
}
