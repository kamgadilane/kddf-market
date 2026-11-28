import Link from "next/link";
import { LEGAL_LINKS, LEGAL_UPDATED } from "@/lib/legal";

/** Mise en page commune des pages légales. */
export default function LegalPage({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <article className="mx-auto max-w-3xl space-y-6">
      <header className="space-y-1">
        <h1 className="font-display text-3xl font-bold text-white">{title}</h1>
        <p className="text-xs text-zinc-500">Dernière mise à jour : {LEGAL_UPDATED}</p>
      </header>
      <div className="glass space-y-6 p-5 text-sm leading-relaxed text-zinc-300 sm:p-8 [&_h2]:font-display [&_h2]:text-lg [&_h2]:font-bold [&_h2]:text-white [&_li]:ml-5 [&_li]:list-disc [&_ul]:space-y-1.5">
        {children}
      </div>
      <nav aria-label="Autres pages légales" className="flex flex-wrap gap-2 text-xs">
        {LEGAL_LINKS.map((l) => <Link key={l.href} href={l.href} className="btn-ghost !px-3 !py-1.5">{l.label}</Link>)}
      </nav>
    </article>
  );
}
