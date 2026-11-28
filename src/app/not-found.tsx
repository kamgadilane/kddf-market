import Link from "next/link";

export const metadata = { title: "Page introuvable", robots: { index: false } };

export default function NotFound() {
  return (
    <div className="glass mx-auto mt-16 max-w-lg space-y-4 p-6 text-center sm:p-8">
      <p className="font-display text-5xl font-bold text-volt-soft">404</p>
      <h1 className="font-display text-2xl font-bold text-white">Page introuvable</h1>
      <p className="text-sm text-zinc-300">Cette page n&apos;existe pas ou n&apos;existe plus. Le lien est peut-être incorrect, ou le produit a été retiré par son vendeur.</p>
      <div className="flex flex-wrap justify-center gap-3">
        <Link href="/" className="btn-primary !py-2">Retour à l&apos;accueil</Link>
        <Link href="/suivre-commande" className="btn-ghost !py-2">Suivre ma commande</Link>
        <Link href="/support" className="btn-ghost !py-2">Contacter le support</Link>
      </div>
    </div>
  );
}
