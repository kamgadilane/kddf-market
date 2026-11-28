"use client";
/** Panier léger enregistré dans le navigateur (aucun montant n'y fait foi : le prix est TOUJOURS recalculé côté serveur au paiement). */
export interface CartItem {
  id: string;
  title: string;
  price: number;
  image: string | null;
  type: "physical" | "digital";
}

const KEY = "kddf_cart_v1";

export function readCart(): CartItem[] {
  try {
    const raw = window.localStorage.getItem(KEY);
    const parsed: unknown = raw ? JSON.parse(raw) : [];
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((x): x is CartItem => typeof x === "object" && x !== null && typeof (x as CartItem).id === "string" && typeof (x as CartItem).title === "string");
  } catch {
    return [];
  }
}

export function writeCart(items: CartItem[]): void {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(items.slice(0, 50)));
    window.dispatchEvent(new Event("kddf-cart"));
  } catch {
    /* stockage indisponible : on ignore */
  }
}

export function addToCart(item: CartItem): void {
  const cart = readCart();
  if (!cart.some((c) => c.id === item.id)) writeCart([...cart, item]);
}

export function removeFromCart(id: string): void {
  writeCart(readCart().filter((c) => c.id !== id));
}
