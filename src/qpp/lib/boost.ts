import type { BoostPlan } from "@/lib/types";

// Tarifs du boost (FCFA entiers). Le prix est fixé ICI, côté serveur : jamais lu depuis le navigateur.
// rank : plus il est grand, plus le produit passe devant sur la page d'accueil.
export const BOOST_PLANS: Record<BoostPlan, { days: number; price: number; label: string; badge: string; perk: string; rank: number }> = {
  "3d": { days: 3, price: 1000, label: "Boost 3 jours", badge: "À la une", perk: "En haut de sa catégorie + badge « À la une »", rank: 1 },
  "7d": { days: 7, price: 2500, label: "Boost 7 jours", badge: "Populaire", perk: "En haut de la page d'accueil + badge « Populaire »", rank: 2 },
  "14d": { days: 14, price: 4500, label: "Boost 14 jours", badge: "Populaire", perk: "En haut de la page d'accueil pendant 2 semaines", rank: 3 },
  "30d": { days: 30, price: 8000, label: "Boost 30 jours", badge: "Star", perk: "Tout en haut de l'accueil pendant 30 jours + badge « Star »", rank: 4 },
};

export function isBoostPlan(v: unknown): v is BoostPlan {
  return v === "3d" || v === "7d" || v === "14d" || v === "30d";
}
