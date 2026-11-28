import Link from "next/link";

export interface BannerData {
  id: string;
  title: string;
  body: string | null;
  link_url: string | null;
  image_url: string | null;
  label: string;
}

// Bannière publicitaire / partenaire de la page d'accueil (créée par l'admin dans /admin/pub). Toujours étiquetée (« Sponsorisé »).
export default function SponsorBanner({ b }: { b: BannerData }) {
  const external = b.link_url !== null && /^https?:\/\//.test(b.link_url);
  const inner = (
    <div className="card-float relative flex min-h-[120px] items-stretch overflow-hidden">
      {b.image_url && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={b.image_url} alt="" loading="lazy" className="hidden w-40 shrink-0 object-cover sm:block" />
      )}
      <div className="flex min-w-0 flex-1 flex-col justify-center gap-1 p-4 sm:p-5">
        <span className="w-fit rounded-full bg-amber-400/90 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-ink-950">{b.label}</span>
        <p className="font-display text-lg font-bold leading-snug text-white [overflow-wrap:anywhere]">{b.title}</p>
        {b.body && <p className="text-sm text-zinc-400 [overflow-wrap:anywhere]">{b.body}</p>}
      </div>
    </div>
  );
  if (!b.link_url) return inner;
  return external ? (
    <a href={b.link_url} target="_blank" rel="noopener noreferrer sponsored" className="block">{inner}</a>
  ) : (
    <Link href={b.link_url} className="block">{inner}</Link>
  );
}
