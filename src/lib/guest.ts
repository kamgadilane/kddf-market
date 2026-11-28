// Achat SANS compte (« Guest Checkout ») pour les produits PHYSIQUES : outils partagés (serveur et navigateur).
// Aucune clé secrète ici : ce fichier est importé par des composants client.

/** Message affiché quand quelqu'un sans compte essaie d'acheter un produit digital. */
export const GUEST_DIGITAL_MESSAGE = "Pour les produits digitaux, crée un compte gratuit en 30 secondes pour recevoir ton fichier";

/** Nombre maximum de photos jointes à un litige. */
export const MAX_DISPUTE_PHOTOS = 3;

/**
 * Code de suivi d'une commande physique : KDDF- puis 4 chiffres (ex. KDDF-8421) ;
 * 5 ou 6 chiffres seulement quand les 4 chiffres sont épuisés.
 */
export function normalizeOrderCode(raw: string): string | null {
  const c = raw.trim().toUpperCase().replace(/[\s_]/g, "");
  const m = /^(?:KDDF-?)?([0-9]{4,6})$/.exec(c);
  return m ? `KDDF-${m[1]}` : null;
}

/** Adresse technique donnée à une commande sans email (Fapshi et Flutterwave en exigent une). Jamais utilisée pour écrire au client. */
export function technicalEmail(phone: string): string {
  const digits = phone.replace(/\D/g, "").slice(-9);
  return `invite-${digits || "inconnu"}@example.com`;
}

export function isTechnicalEmail(email: string | null | undefined): boolean {
  return typeof email === "string" && /^invite-[^@\s]*@example\.com$/i.test(email.trim());
}

/** Message de confirmation envoyé (WhatsApp / SMS) avec le code. */
export function orderConfirmationMessage(name: string | null | undefined, code: string): string {
  const first = (name ?? "").trim().split(/\s+/)[0];
  return `Merci ${first || "cher client"} ! Ta commande ${code} est confirmée.`;
}

export const TRACK_STEPS = ["En attente", "En livraison", "Livré", "Terminé"] as const;

export interface TrackableOrder {
  status: string;
  payment_status: string;
  payment_method?: string | null;
}

/** Étape du suivi (0 à 3) : En attente -> En livraison -> Livré -> Terminé ; -1 = commande annulée. */
export function trackStepIndex(o: TrackableOrder): number {
  switch (o.status) {
    case "cancelled":
      return -1;
    case "shipped":
    case "ready_for_pickup":
      return 1;
    case "delivered":
      return 2;
    case "completed":
      return 3;
    default:
      return 0; // pending, confirmed
  }
}

/** Phrase d'explication sous le suivi. */
export function trackHint(o: TrackableOrder): string {
  if (o.status === "cancelled") return "Cette commande a été annulée.";
  if (o.payment_status !== "paid" && o.payment_method !== "cod") return "Le paiement n'est pas encore confirmé. S'il a été débité, patientez quelques minutes puis actualisez.";
  switch (trackStepIndex(o)) {
    case 0:
      return "Le vendeur prépare votre commande.";
    case 1:
      return o.status === "ready_for_pickup" ? "Votre commande est prête : le vendeur vous contacte pour le retrait." : "Votre commande est en cours de livraison.";
    case 2:
      return "Votre commande est livrée. Confirmez la réception, ou ouvrez un litige en cas de problème.";
    default:
      return "Commande terminée. Merci pour votre confiance !";
  }
}

/** Réponse de /api/suivre-commande (sans aucune donnée privée du vendeur). */
export interface TrackedOrder {
  order_code: string;
  customer_name: string | null;
  product_title: string;
  quantity: number;
  total_price: number;
  delivery_method: string | null;
  delivery_address: string | null;
  payment_method: string;
  payment_status: string;
  status: string;
  created_at: string;
  paid_at: string | null;
  delivered_at: string | null;
  buyer_confirmed_at: string | null;
  disputed: boolean;
  dispute_status: string | null;
  can_confirm: boolean;
  can_dispute: boolean;
}
