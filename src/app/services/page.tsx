import Link from "next/link";
import { formatFcfa } from "@/lib/money";
import { PAID_SERVICES } from "@/lib/services";
import { appName } from "@/lib/env";

export const metadata = { title: "Services pour les vendeurs", description: "Page produit, visuel, lancement accompagné, coaching et publicité sur KDDF Market." };

export default function ServicesPage() {
  const name = appName();
  const wa = (process.env.NEXT_PUBLIC_SUPPORT_WHATSAPP ?? "").replace(/[^0-9]/g, "");
  const link = (title: string): string | null =>
    wa ? `https://wa.me/${wa}?text=${encodeURIComponent(`Bonjour ${name}, je suis intéressé(e) par le service « ${title} ». Pouvez-vous me donner la marche à suivre ?`)}` : null;

  return (
    <div className="space-y-8">
      <header className="space-y-2">
        <h1 className="font-display text-3xl font-bold text-white sm:text-4xl">Services pour les vendeurs</h1>
        <p className="max-w-2xl text-zinc-400">Vous préférez vous concentrer sur votre produit ? Nous nous occupons du reste. Choisissez un service, écrivez-nous sur WhatsApp, et nous convenons des détails ensemble.</p>
      </header>

      <div className="grid gap-4 sm:grid-cols-2">
        {PAID_SERVICES.map((s) => {
          const href = link(s.title);
          return (
            <article key={s.id} className="card-float flex flex-col gap-3 p-5">
              <h2 className="font-display text-lg font-semibold text-white">{s.title}</h2>
              <p className="flex-1 text-sm text-zinc-400">{s.description}</p>
              <p className="font-display text-xl font-bold text-jade-soft">{s.from ? "À partir de " : ""}{formatFcfa(s.price)}{s.unit ? <span className="text-sm font-normal text-zinc-400"> {s.unit}</span> : null}</p>
              {href ? (
                <a href={href} target="_blank" rel="noopener noreferrer" className="btn-primary !py-2.5 text-center">💬 Commander sur WhatsApp</a>
              ) : (
                <Link href="/support" className="btn-primary !py-2.5 text-center">Nous écrire</Link>
              )}
            </article>
          );
        })}
      </div>

      <p className="text-sm text-zinc-500">Vous êtes vendeur régulier ? L&apos;<Link href="/dashboard/pro" className="underline hover:text-white">abonnement Pro</Link> réduit votre commission et vos boosts.</p>
    </div>
  );
}
