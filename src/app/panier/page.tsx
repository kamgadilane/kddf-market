"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { readCart, removeFromCart, type CartItem } from "@/lib/cart";
import { formatFcfa } from "@/lib/money";
import { t } from "@/lib/translations";

/**
 * Panier : liste enregistrée dans le navigateur. Chaque article se règle sur sa page produit (paiement sécurisé, prix recalculé côté serveur) :
 * un paiement = un produit, car chaque vendeur reçoit son propre règlement.
 * L'indication de total n'est qu'informative.
 */
export default function CartPage() {
  const [items, setItems] = useState<CartItem[] | null>(null);
  useEffect(() => {
    const sync = () => setItems(readCart());
    sync();
    window.addEventListener("kddf-cart", sync);
    return () => window.removeEventListener("kddf-cart", sync);
  }, []);

  if (items === null) return <p className="text-sm text-zinc-500">Chargement…</p>;
  const total = items.reduce((s, i) => s + i.price, 0);

  return (
    <div className="space-y-5">
      <h1 className="font-display text-3xl font-bold text-white">{t("cart.title")}</h1>
      {items.length === 0 ? (
        <p className="glass p-8 text-center text-sm text-zinc-400">{t("cart.empty")} <Link href="/" className="text-volt-soft underline">Voir les produits</Link></p>
      ) : (
        <>
          <ul className="space-y-3">
            {items.map((i) => (
              <li key={i.id} className="glass flex items-center gap-3 p-3">
                {i.image && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={i.image} alt="" className="h-16 w-16 rounded-lg object-cover" />
                )}
                <div className="min-w-0 flex-1">
                  <p className="truncate font-semibold text-white">{i.title}</p>
                  <p className="text-sm text-zinc-400">{formatFcfa(i.price)}</p>
                </div>
                <Link href={`/p/${i.id}`} className="btn-primary !px-3 !py-2 text-sm">Payer</Link>
                <button type="button" className="btn-ghost !px-3 !py-2 text-sm text-red-300" onClick={() => removeFromCart(i.id)} aria-label={`Retirer ${i.title}`}>✕</button>
              </li>
            ))}
          </ul>
          <p className="text-right text-sm text-zinc-400">Total indicatif : <span className="font-semibold text-white">{formatFcfa(total)}</span> (chaque article se paie séparément)</p>
        </>
      )}
    </div>
  );
}
