import { LoadingShell, SkeletonBlock } from "@/components/Skeleton";

// Chargement de l'espace créateur : cartes de chiffres puis tableau.
export default function Loading() {
  return (
    <LoadingShell>
      <div className="space-y-6">
        <SkeletonBlock className="h-8 w-1/2 max-w-sm" />
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {Array.from({ length: 4 }, (_, i) => <SkeletonBlock key={i} className="h-24" />)}
        </div>
        <SkeletonBlock className="h-64 w-full" />
      </div>
    </LoadingShell>
  );
}
