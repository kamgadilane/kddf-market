"use client";
import { useEffect, useState } from "react";
import { addToCart, readCart } from "@/lib/cart";
import type { CartItem } from "@/lib/cart";

export default function AddToCartButton({ item }: { item: CartItem }) {
  const [inCart, setInCart] = useState(false);
  useEffect(() => {
    const sync = () => setInCart(readCart().some((c) => c.id === item.id));
    sync();
    window.addEventListener("kddf-cart", sync);
    return () => window.removeEventListener("kddf-cart", sync);
  }, [item.id]);
  return (
    <button type="button" className="btn-ghost w-full" disabled={inCart} onClick={() => addToCart(item)}>
      {inCart ? "✓ Dans le panier" : "Ajouter au panier"}
    </button>
  );
}
