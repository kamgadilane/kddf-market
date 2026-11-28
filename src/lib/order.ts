// Quantité maximale par commande : la vraie limite est le STOCK du vendeur (vérifié par la base).
// Ce plafond technique évite seulement les valeurs absurdes. Même valeur dans la base (create_checkout_order).
export const MAX_ORDER_QUANTITY = 1000;
