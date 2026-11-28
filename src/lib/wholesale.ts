/** Module grossistes : types et message WhatsApp pré-rempli. Aucun calcul d'argent ici (il se fait dans la base : wholesale_split). */
export interface WholesaleProduct {
  product_id: string;
  seller_id: string;
  min_quantity_10_price: number;
  min_quantity_50_price: number;
  stock_wholesale: number;
  city: string | null;
  is_active: boolean;
}

/** Commissions d'une vente en gros (affichage seulement) : plateforme 3 %, affilié 5 %, vendeur 92 %. */
export const WHOLESALE_RATES = { platform: 3, affiliate: 5, seller: 92 } as const;

export function quoteMessage(title: string, quantity: number, unitPrice: number): string {
  return `Bonjour, je souhaite un devis grossiste sur KDDF Market : ${title} - ${quantity} pièces (prix indicatif ${unitPrice} FCFA l'unité). Merci de me confirmer le prix et la disponibilité.`;
}

export function whatsappUrl(number: string, message: string): string {
  const digits = number.replace(/[^0-9]/g, "");
  return `https://wa.me/${digits}?text=${encodeURIComponent(message)}`;
}
