// Éléments de chargement (squelettes) : affichés pendant que la page se charge, pour éviter l'écran blanc.
// role="status" + texte masqué : les lecteurs d'écran annoncent « Chargement en cours ».

export function SkeletonBlock({ className = "" }: { className?: string }) {
  return <div aria-hidden="true" className={`animate-pulse rounded-xl bg-white/[0.06] ${className}`} />;
}

export function LoadingShell({ children }: { children: React.ReactNode }) {
  return (
    <div role="status" aria-live="polite" aria-busy="true">
      <span className="sr-only">Chargement en cours…</span>
      {children}
    </div>
  );
}

/** Grille de cartes produit (accueil, boutiques, grossistes). */
export function CardsSkeleton({ count = 6 }: { count?: number }) {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {Array.from({ length: count }, (_, i) => (
        <div key={i} className="glass space-y-3 p-3">
          <SkeletonBlock className="aspect-[4/3] w-full" />
          <SkeletonBlock className="h-4 w-3/4" />
          <SkeletonBlock className="h-4 w-1/3" />
        </div>
      ))}
    </div>
  );
}
