import WaitlistForm from "@/components/WaitlistForm";
import { COUNTRIES } from "@/lib/currency";
import { PAYMENT_METHODS } from "@/lib/payments";
import { t } from "@/lib/translations";

export const metadata = { title: "International" };

export default function InternationalPage() {
  return (
    <div className="space-y-6">
      <header className="space-y-2">
        <h1 className="font-display text-3xl font-bold text-white">KDDF Market à l&apos;international</h1>
        <p className="text-sm text-zinc-400">Le Cameroun est ouvert. Les autres pays arrivent bientôt : laisse ton WhatsApp pour être parmi les 100 premiers vendeurs.</p>
      </header>
      <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {COUNTRIES.map((c) => (
          <li key={c.code} className="card-float space-y-3 p-5">
            <p className="font-display text-lg font-bold text-white">{c.flag} {c.name}</p>
            {c.active ? (
              <>
                <p className="text-sm font-semibold text-jade-soft">Disponible</p>
                <p className="text-xs text-zinc-400">{PAYMENT_METHODS[c.code].map((m) => m.label).join(" · ")}</p>
              </>
            ) : (
              <>
                <p className="text-sm font-semibold text-amber-300">{t("country.soon")}</p>
                <WaitlistForm country={c.code} countryName={c.name} />
              </>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
