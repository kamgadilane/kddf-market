// Badge « Pro » : vendeur abonné à l'offre Pro (commission réduite). Différent de « Vendeur Vérifié » (identité contrôlée).
export default function ProBadge({ size = "md" }: { size?: "sm" | "md" }) {
  return (
    <span title="Vendeur Pro KDDF" className={`inline-flex items-center gap-1 rounded-full bg-amber-400 align-middle font-bold uppercase tracking-wide text-ink-950 ${size === "sm" ? "px-2 py-0.5 text-[10px]" : "px-2.5 py-1 text-xs"}`}>
      <span aria-hidden="true">★</span> Pro
      <span className="sr-only">Vendeur Pro KDDF</span>
    </span>
  );
}
