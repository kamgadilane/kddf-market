import { LoadingShell, SkeletonBlock } from "@/components/Skeleton";

// Chargement d'une fiche produit : même disposition que la page (galerie à gauche, achat à droite).
export default function Loading() {
  return (
    <LoadingShell>
      <div className="grid gap-8 lg:grid-cols-[1.1fr_1fr]">
        <div className="space-y-4">
          <SkeletonBlock className="aspect-square w-full" />
          <SkeletonBlock className="h-8 w-3/4" />
          <SkeletonBlock className="h-4 w-full" />
          <SkeletonBlock className="h-4 w-5/6" />
        </div>
        <div className="glass space-y-4 p-5">
          <SkeletonBlock className="h-8 w-1/2" />
          <SkeletonBlock className="h-12 w-full" />
          <SkeletonBlock className="h-12 w-full" />
          <SkeletonBlock className="h-12 w-full" />
        </div>
      </div>
    </LoadingShell>
  );
}
