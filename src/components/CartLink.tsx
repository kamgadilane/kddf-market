"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { readCart } from "@/lib/cart";
import { t } from "@/lib/translations";

export default function CartLink() {
  const [n, setN] = useState(0);
  useEffect(() => {
    const sync = () => setN(readCart().length);
    sync();
    window.addEventListener("kddf-cart", sync);
    return () => window.removeEventListener("kddf-cart", sync);
  }, []);
  return <Link href="/panier" className="btn-ghost !px-3 !py-2">🛒 <span className="hidden sm:inline">{t("nav.cart")}</span>{n > 0 && <span className="ml-1 rounded-full bg-volt px-1.5 text-[11px] font-bold text-white">{n}</span>}</Link>;
}
